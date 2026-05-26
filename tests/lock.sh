#!/bin/bash
# tests/lock.sh — fleet_acquire_lock / fleet_release_lock contention test.
#
# Forks two background invocations of a stub runner that source lib/common.sh,
# call fleet_acquire_lock for the same slug+phase, write a marker, then sleep.
# The mutex must let exactly one of them write to the shared output file; the
# other must log "skipped — locked by <pid>" and exit 0 without writing.
#
# Also asserts:
#   - the lock dir is at $CACHE_DIR/lock as the ticket specifies
#   - a lock dir mtime older than 6 hours is treated as stale + reclaimed
#   - fleet_release_lock removes the lock dir
#
# Self-contained: stubs $HOME so we never touch real ~/.cache state, stubs
# `claude` so we never hit the network. Exits non-zero on any failure.

set -euo pipefail

REPO_ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"

TMP="$(mktemp -d -t fleet-lock-test.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

# Isolate from the real fleet cache. The lib derives CACHE_DIR from $HOME and
# $SLUG, so a fake HOME is enough.
export HOME="$TMP/home"
mkdir -p "$HOME"

# A tiny manifest the runner will source.
MANIFEST_DIR="$TMP/project"
mkdir -p "$MANIFEST_DIR"
cat > "$MANIFEST_DIR/agents.config.sh" <<'CFG'
SLUG="locktest"
PROJECT_NAME="locktest"
REPO_URL="https://github.com/example/locktest.git"
SELF_CANCEL="20990101"
CFG

SHARED_OUT="$TMP/shared.out"
RUNNER_LOG_DIR="$TMP/runner-logs"
mkdir -p "$RUNNER_LOG_DIR"

# Stub runner — sources common.sh, acquires the lock, appends one line to
# $SHARED_OUT (if it wins) and exits. Sleeps inside the critical section so the
# two forks actually race for the mutex.
STUB="$TMP/stub-runner.sh"
cat > "$STUB" <<STUB_EOF
#!/bin/bash
set -euo pipefail
source "$REPO_ROOT/lib/common.sh"
fleet_load_manifest "$MANIFEST_DIR"
# Redirect ALL output of the runner to a per-pid log so the test can grep it.
exec >"$RUNNER_LOG_DIR/runner-\$\$.log" 2>&1
trap 'fleet_release_lock ship || true' EXIT
if ! fleet_acquire_lock ship; then
  exit 0
fi
# Critical section: hold the lock long enough that the sibling races into us.
echo "won pid=\$\$" >> "$SHARED_OUT"
sleep 2
STUB_EOF
chmod +x "$STUB"

# --- assertion 1: contention ---------------------------------------------
"$STUB" &
PID_A=$!
# Tiny stagger so A claims the mkdir first deterministically; the second still
# exercises the contention codepath because A is sleeping inside the section.
sleep 0.2
"$STUB" &
PID_B=$!

wait "$PID_A" || { echo "FAIL: runner A exited non-zero"; exit 1; }
wait "$PID_B" || { echo "FAIL: runner B exited non-zero (should have logged-and-exit-0)"; exit 1; }

WINNERS=$(wc -l < "$SHARED_OUT" | tr -d ' ')
if [ "$WINNERS" != "1" ]; then
  echo "FAIL: expected exactly 1 winner, got $WINNERS"
  echo "--- shared.out ---"; cat "$SHARED_OUT"
  echo "--- runner logs ---"; tail -n +1 "$RUNNER_LOG_DIR"/*.log
  exit 1
fi

# The loser must have logged the "skipped — locked by <pid>" line.
if ! grep -q "skipped — locked by" "$RUNNER_LOG_DIR"/*.log; then
  echo "FAIL: no 'skipped — locked by <pid>' line in any runner log"
  tail -n +1 "$RUNNER_LOG_DIR"/*.log
  exit 1
fi
if ! grep -q "locktest-ship skipped — locked by" "$RUNNER_LOG_DIR"/*.log; then
  echo "FAIL: skip line missing 'locktest-ship' slug+phase prefix"
  tail -n +1 "$RUNNER_LOG_DIR"/*.log
  exit 1
fi

# --- assertion 2: lock dir lives under $CACHE_DIR/lock ------------------
EXPECTED_LOCK_PARENT="$HOME/.cache/locktest-agent/lock"
# After both runners exit (trap releases), the lock dir should be gone.
if [ -e "$EXPECTED_LOCK_PARENT/ship" ]; then
  echo "FAIL: lock dir $EXPECTED_LOCK_PARENT/ship not released after runners exited"
  exit 1
fi

# --- assertion 3: stale lock (>6h old) is reclaimed ---------------------
mkdir -p "$EXPECTED_LOCK_PARENT/ship"
echo "99999" > "$EXPECTED_LOCK_PARENT/ship/pid"
# Backdate the lock dir 7 hours.
touch -t "$(date -u -v-7H +%Y%m%d%H%M.%S 2>/dev/null || date -u -d '7 hours ago' +%Y%m%d%H%M.%S)" \
  "$EXPECTED_LOCK_PARENT/ship"

STALE_LOG="$TMP/stale-runner.log"
(
  set -euo pipefail
  # shellcheck disable=SC1091
  source "$REPO_ROOT/lib/common.sh"
  fleet_load_manifest "$MANIFEST_DIR"
  exec >"$STALE_LOG" 2>&1
  trap 'fleet_release_lock ship || true' EXIT
  if ! fleet_acquire_lock ship; then
    echo "FAIL-INNER: should have claimed stale lock"
    exit 1
  fi
  echo "claimed-stale"
)

if ! grep -q "stale lock: claiming" "$STALE_LOG"; then
  echo "FAIL: stale lock not detected; log was:"; cat "$STALE_LOG"
  exit 1
fi
if ! grep -q "claimed-stale" "$STALE_LOG"; then
  echo "FAIL: runner did not proceed after claiming stale lock"; cat "$STALE_LOG"
  exit 1
fi

# --- assertion 4: release removes the lock dir --------------------------
if [ -e "$EXPECTED_LOCK_PARENT/ship" ]; then
  echo "FAIL: fleet_release_lock did not remove $EXPECTED_LOCK_PARENT/ship"
  exit 1
fi

echo "ok: tests/lock.sh passed"
