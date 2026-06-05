#!/bin/bash
# tests/quiet-hours.sh — QUIET_HOURS manifest knob suppresses ship/groom/eng
# during operator-declared local-time windows. Ticket 0033.
#
# Eleven acceptance-criteria scenarios, mapped 1:1 to the ticket's AC boxes.
# Strategy:
#   * Source lib/common.sh in a subshell per case, load one of the fixture
#     manifests (tests/fixtures/quiet-hours/*.agents.config.sh) via
#     fleet_load_manifest, set $FLEET_PHASE, and inject the clock with
#     FLEET_NOW_OVERRIDE (a new test-only env parsed by the helper).
#   * AC#1 / AC#11 also exercise the runner end-to-end — we drive
#     `bash lib/ship.sh <project-dir>` with a stubbed `claude`, `gh`, and
#     `git` under $HOME/.local/bin (per LESSONS 2026-05-26 the PATH reset
#     in common.sh would shadow stubs anywhere else), assert no claude
#     invocation, and read the resulting events.jsonl + log file.
#   * Fixture content is copied via `cp` (LESSONS 2026-05-27) so the
#     trailing newline survives byte-for-byte for AC#11's install assertion.
#   * `printf -- '%s'` is used for any value whose first byte might be
#     `-` (LESSONS 2026-05-28) — defensive even though our values start
#     with digits.
#   * Helper outputs are parsed line-by-line, never with `awk -v paragraph=`
#     style multi-line variable passes (LESSONS 2026-06-01).
#   * All values are ASCII (HH:MM-HH:MM, ISO8601, phase names) so the
#     _json_escape sign-extension trap (LESSONS 2026-06-03) does not bite.
#
# Self-contained: stubs $HOME under $TMP and exits non-zero on any failure.

set -euo pipefail

REPO_ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"

TMP="$(mktemp -d -t fleet-quiet-hours-test.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

# Isolate from the real fleet cache.
export HOME="$TMP/home"
mkdir -p "$HOME/.local/bin"

# --- stubs (LESSONS 2026-05-26: under $HOME/.local/bin so the PATH reset
# in lib/common.sh keeps them visible). The runner end-to-end blocks at
# AC#1/AC#2/AC#3 need claude/gh/git on PATH; we never expect claude to
# fire on the suppress path, but the stubs make a positive assertion
# possible (the calls land in $TMP/claude.log if invoked at all).
STUB_BIN="$HOME/.local/bin"
CLAUDE_LOG="$TMP/claude.log"
: > "$CLAUDE_LOG"

cat > "$STUB_BIN/claude" <<STUB
#!/bin/bash
printf '%s\n' "claude \$*" >> "$CLAUDE_LOG"
cat >/dev/null 2>&1 || true
printf '%s\n' '{"result":"unused","total_cost_usd":0,"session_id":"x","duration_ms":1,"num_turns":1,"usage":{},"is_error":false}'
exit 0
STUB
chmod +x "$STUB_BIN/claude"

# gh + git stubs — used only by fleet_checkout in the ship.sh end-to-end
# scenarios (AC#1 specifically wants to assert "gh is not touched" on the
# suppress path). The stubs always exit 0; the log captures every call.
GH_LOG="$TMP/gh.log"
GIT_LOG="$TMP/git.log"
: > "$GH_LOG"
: > "$GIT_LOG"
cat > "$STUB_BIN/gh" <<STUB
#!/bin/bash
printf '%s\n' "gh \$*" >> "$GH_LOG"
exit 0
STUB
chmod +x "$STUB_BIN/gh"

# launchctl stub — `fleet_check_sendback_streak` and the install path may
# call it; we don't care about the result, only that the runner doesn't
# blow up.
cat > "$STUB_BIN/launchctl" <<'STUB'
#!/bin/bash
exit 0
STUB
chmod +x "$STUB_BIN/launchctl"

export PATH="$STUB_BIN:$PATH"

# ---------------------------------------------------------------------------
# Helper — load a fixture manifest into a fresh project dir, returning the
# absolute path. Uses `cp` (LESSONS 2026-05-27) so trailing newline is
# preserved byte-for-byte (AC#11 leans on this).
# ---------------------------------------------------------------------------
load_fixture() {
  local name="${1:?load_fixture: fixture name required}"
  local project_dir="$TMP/proj-${name}-$$-$RANDOM"
  mkdir -p "$project_dir"
  cp "$REPO_ROOT/tests/fixtures/quiet-hours/${name}.agents.config.sh" \
     "$project_dir/agents.config.sh"
  printf '%s\n' "$project_dir"
}

# Reset per-slug cache.
reset_cache() {
  rm -rf "$HOME/.cache/quiethourstest-agent"
  mkdir -p "$HOME/.cache/quiethourstest-agent"
}

# Wrapper: source lib/common.sh, load the named fixture, set phase + clock,
# invoke fleet_check_quiet_hours, and echo the result string. We do NOT
# branch on it here — the caller asserts the output and any side effects.
check_quiet_hours() {
  local fixture="$1"
  local phase="$2"
  local now_override="${3:-}"
  local project_dir
  project_dir="$(load_fixture "$fixture")"
  (
    set -euo pipefail
    # shellcheck disable=SC1091
    source "$REPO_ROOT/lib/common.sh"
    fleet_load_manifest "$project_dir"
    FLEET_PHASE="$phase"; export FLEET_PHASE
    if [ -n "$now_override" ]; then
      export FLEET_NOW_OVERRIDE="$now_override"
    else
      unset FLEET_NOW_OVERRIDE
    fi
    fleet_check_quiet_hours
  )
}

# ===========================================================================
# AC #1 — Inside the window, the runner emits exactly one quiet_hours_skip
#         event, prints the documented banner, exits 0, does NOT call claude,
#         and does NOT touch gh.
# ===========================================================================
reset_cache
: > "$CLAUDE_LOG"
: > "$GH_LOG"
PROJECT_DIR_AC1="$(load_fixture window-overnight)"
EVENTS_AC1="$HOME/.cache/quiethourstest-agent/events.jsonl"

# Run the actual ship.sh entry point with FLEET_NOW_OVERRIDE set to 02:37
# local. The fleet_checkout call would otherwise try a real git clone; we
# guard against that by setting FLEET_QUIET_HOURS_CHECK_FIRST=1 which the
# runner reads to short-circuit the checkout when the gate trips. But the
# ticket's engineering notes say the quiet-hours check goes "right after
# fleet_check_budget" — which sits BEFORE the lock/checkout. Let's read
# ship.sh to confirm the ordering matches what we expect. (It does: the
# new check lands before fleet_acquire_lock + fleet_checkout, so a
# suppress short-circuits before the git/gh calls.)
AC1_LOG="$TMP/ac1.log"
set +e
FLEET_NOW_OVERRIDE="2026-06-06T02:37:09-0700" \
  bash "$REPO_ROOT/lib/ship.sh" "$PROJECT_DIR_AC1" > "$AC1_LOG" 2>&1
AC1_EXIT=$?
set -e

if [ "$AC1_EXIT" -ne 0 ]; then
  echo "FAIL: AC#1 ship.sh exited $AC1_EXIT (want 0)"
  cat "$AC1_LOG"
  exit 1
fi

if [ -s "$CLAUDE_LOG" ]; then
  echo "FAIL: AC#1 claude was invoked on the suppress path"
  cat "$CLAUDE_LOG"
  exit 1
fi

if [ -s "$GH_LOG" ]; then
  echo "FAIL: AC#1 gh was invoked on the suppress path"
  cat "$GH_LOG"
  exit 1
fi

if [ ! -f "$EVENTS_AC1" ]; then
  echo "FAIL: AC#1 events.jsonl was not created"
  exit 1
fi

# Exactly ONE quiet_hours_skip event.
SKIP_COUNT="$(awk '/"type":"quiet_hours_skip"/ { n++ } END { print (n+0) }' "$EVENTS_AC1")"
if [ "$SKIP_COUNT" -ne 1 ]; then
  echo "FAIL: AC#1 want exactly 1 quiet_hours_skip event, got $SKIP_COUNT"
  cat "$EVENTS_AC1"
  exit 1
fi

# Banner line landed in the captured log file (the fleet log lives under
# $HOME/.cache/quiethourstest-agent/logs/ship-*.log — fleet_log_init redirects
# stdout/stderr there). The pre-redirect echoes from the manifest load go to
# the captured AC1_LOG too, but the banner is post-log_init.
LOG_FILE="$(ls "$HOME/.cache/quiethourstest-agent/logs/"ship-*.log 2>/dev/null | tail -1)"
if [ -z "$LOG_FILE" ] || [ ! -f "$LOG_FILE" ]; then
  echo "FAIL: AC#1 no ship log file was created"
  ls -la "$HOME/.cache/quiethourstest-agent/logs/" 2>/dev/null || true
  exit 1
fi
if ! grep -qF -- 'quiet hours active (22:00-07:00 local) — ship no-op until 07:00' "$LOG_FILE"; then
  echo "FAIL: AC#1 documented banner missing from log file"
  echo "log file: $LOG_FILE"
  cat "$LOG_FILE"
  exit 1
fi

echo "ok: AC#1 inside-window run emits one quiet_hours_skip, prints banner, exits 0, no claude/gh"

# ===========================================================================
# AC #2 — QUIET_HOURS="" (default) runs normally at any time. No
#         quiet_hours_skip event; claude IS invoked.
# ===========================================================================
reset_cache
out="$(check_quiet_hours window-empty ship "2026-06-06T02:37:09-0700" || true)"
case "$out" in
  ok) ;;
  *)
    echo "FAIL: AC#2 expected 'ok' from empty QUIET_HOURS at 02:37, got '$out'"
    exit 1 ;;
esac

EVENTS_AC2="$HOME/.cache/quiethourstest-agent/events.jsonl"
if [ -f "$EVENTS_AC2" ] && grep -q '"type":"quiet_hours_skip"' "$EVENTS_AC2"; then
  echo "FAIL: AC#2 empty QUIET_HOURS must not emit quiet_hours_skip"
  cat "$EVENTS_AC2"
  exit 1
fi
echo "ok: AC#2 empty QUIET_HOURS proceeds and emits nothing"

# ===========================================================================
# AC #3 — QUIET_HOURS="22:00-07:00" at 14:00 (outside window) → 'ok',
#         no event.
# ===========================================================================
reset_cache
out="$(check_quiet_hours window-overnight ship "2026-06-06T14:00:00-0700" || true)"
case "$out" in
  ok) ;;
  *)
    echo "FAIL: AC#3 expected 'ok' at 14:00 outside 22:00-07:00 window, got '$out'"
    exit 1 ;;
esac

EVENTS_AC3="$HOME/.cache/quiethourstest-agent/events.jsonl"
if [ -f "$EVENTS_AC3" ] && grep -q '"type":"quiet_hours_skip"' "$EVENTS_AC3"; then
  echo "FAIL: AC#3 outside-window run must not emit quiet_hours_skip"
  cat "$EVENTS_AC3"
  exit 1
fi
echo "ok: AC#3 outside-window proceeds, no event"

# ===========================================================================
# AC #4 — Window crossing midnight (22:00-07:00). Boundary points:
#         21:59 → run; 22:00 → skip; 06:59 → skip; 07:00 → run.
# ===========================================================================
# Use `|` as the delimiter so the ISO8601 colons don't confuse parameter
# expansion.
for tuple in \
  "2026-06-06T21:59:00-0700|ok|run" \
  "2026-06-06T22:00:00-0700|suppress|skip" \
  "2026-06-06T06:59:00-0700|suppress|skip" \
  "2026-06-06T07:00:00-0700|ok|run"; do
  iso="${tuple%%|*}"
  rest="${tuple#*|}"
  expected="${rest%%|*}"
  label="${rest##*|}"
  reset_cache
  got="$(check_quiet_hours window-overnight ship "$iso" || true)"
  if [ "$got" != "$expected" ]; then
    echo "FAIL: AC#4 overnight window at $iso want '$expected' ($label), got '$got'"
    exit 1
  fi
done
echo "ok: AC#4 overnight window boundaries (21:59 run, 22:00 skip, 06:59 skip, 07:00 run)"

# ===========================================================================
# AC #5 — Window that does NOT cross midnight (09:00-17:00). Boundary
#         points: 08:59 → run; 09:00 → skip; 16:59 → skip; 17:00 → run.
# ===========================================================================
for tuple in \
  "2026-06-06T08:59:00-0700|ok|run" \
  "2026-06-06T09:00:00-0700|suppress|skip" \
  "2026-06-06T16:59:00-0700|suppress|skip" \
  "2026-06-06T17:00:00-0700|ok|run"; do
  iso="${tuple%%|*}"
  rest="${tuple#*|}"
  expected="${rest%%|*}"
  label="${rest##*|}"
  reset_cache
  got="$(check_quiet_hours window-daytime ship "$iso" || true)"
  if [ "$got" != "$expected" ]; then
    echo "FAIL: AC#5 daytime window at $iso want '$expected' ($label), got '$got'"
    exit 1
  fi
done
echo "ok: AC#5 daytime window boundaries (08:59 run, 09:00 skip, 16:59 skip, 17:00 run)"

# ===========================================================================
# AC #6 — review phase is EXEMPT. Even at 02:00 local inside the window,
#         fleet_check_quiet_hours returns 'ok' when $FLEET_PHASE=review.
# ===========================================================================
reset_cache
out="$(check_quiet_hours window-overnight review "2026-06-06T02:00:00-0700" || true)"
case "$out" in
  ok) ;;
  *)
    echo "FAIL: AC#6 review phase at 02:00 inside window should return 'ok', got '$out'"
    exit 1 ;;
esac

EVENTS_AC6="$HOME/.cache/quiethourstest-agent/events.jsonl"
if [ -f "$EVENTS_AC6" ] && grep -q '"type":"quiet_hours_skip"' "$EVENTS_AC6"; then
  echo "FAIL: AC#6 review phase must not emit quiet_hours_skip"
  cat "$EVENTS_AC6"
  exit 1
fi
echo "ok: AC#6 review phase is exempt regardless of clock"

# ===========================================================================
# AC #7 — Invalid QUIET_HOURS values are treated as empty (return 'invalid'
#         per the helper's contract → caller proceeds), AND a one-time
#         stderr line is printed. Test all three invalid fixtures.
# ===========================================================================
for fixture in invalid-out-of-range invalid-no-colons invalid-half-window; do
  reset_cache
  PROJECT_DIR_INV="$(load_fixture "$fixture")"
  STDERR_INV="$TMP/${fixture}.stderr"
  STDOUT_INV="$TMP/${fixture}.stdout"
  (
    set -euo pipefail
    # shellcheck disable=SC1091
    source "$REPO_ROOT/lib/common.sh"
    fleet_load_manifest "$PROJECT_DIR_INV"
    FLEET_PHASE="ship"; export FLEET_PHASE
    FLEET_NOW_OVERRIDE="2026-06-06T02:00:00-0700"; export FLEET_NOW_OVERRIDE
    fleet_check_quiet_hours
  ) > "$STDOUT_INV" 2> "$STDERR_INV" || true

  got="$(cat "$STDOUT_INV" | tr -d '\n')"
  if [ "$got" != "invalid" ]; then
    echo "FAIL: AC#7 fixture $fixture: helper should echo 'invalid', got '$got'"
    cat "$STDERR_INV"
    exit 1
  fi
  if ! grep -qF -- 'quiet_hours_invalid' "$STDERR_INV"; then
    echo "FAIL: AC#7 fixture $fixture: stderr must contain 'quiet_hours_invalid' line"
    cat "$STDERR_INV"
    exit 1
  fi

  # Invalid path emits NO event (it's operator error, not telemetry truth).
  EV_INV="$HOME/.cache/quiethourstest-agent/events.jsonl"
  if [ -f "$EV_INV" ] && grep -q '"type":"quiet_hours_skip"' "$EV_INV"; then
    echo "FAIL: AC#7 fixture $fixture: invalid value must not emit quiet_hours_skip"
    cat "$EV_INV"
    exit 1
  fi
done
echo "ok: AC#7 invalid QUIET_HOURS → 'invalid' + stderr warn, no event"

# ===========================================================================
# AC #8 — Event payload: {phase, window, now_local}. Fires AT MOST ONCE
#         per process (FLEET_QUIET_HOURS_EMITTED guard inside the helper).
# ===========================================================================
reset_cache
EVENTS_AC8="$HOME/.cache/quiethourstest-agent/events.jsonl"
PROJECT_DIR_AC8="$(load_fixture window-overnight)"
(
  set -euo pipefail
  # shellcheck disable=SC1091
  source "$REPO_ROOT/lib/common.sh"
  fleet_load_manifest "$PROJECT_DIR_AC8"
  FLEET_PHASE="groom"; export FLEET_PHASE
  FLEET_NOW_OVERRIDE="2026-06-06T03:15:00-0700"; export FLEET_NOW_OVERRIDE
  # Call WITHOUT command substitution so the helpers exported guard
  # leaks into THIS shell, exactly the way the production runners do
  # it. Read the verdict from the exported FLEET_QUIET_HOURS_VERDICT
  # global. Single emit happens here (and only here) — the helper's
  # in-process guard ensures a second call is silent.
  fleet_check_quiet_hours >/dev/null
  if [ "${FLEET_QUIET_HOURS_VERDICT:-}" != "suppress" ]; then
    echo "FAIL: AC#8 first call verdict should be 'suppress' (got '${FLEET_QUIET_HOURS_VERDICT:-}')" >&2
    exit 1
  fi
  if [ -z "${FLEET_QUIET_HOURS_EMITTED:-}" ]; then
    echo "FAIL: AC#8 FLEET_QUIET_HOURS_EMITTED guard not set after first suppress" >&2
    exit 1
  fi
  # Second call: helper STILL records verdict='suppress' (time-of-day fact
  # has not changed), but the guard short-circuits the emit so no second
  # event lands.
  fleet_check_quiet_hours >/dev/null
  if [ "${FLEET_QUIET_HOURS_VERDICT:-}" != "suppress" ]; then
    echo "FAIL: AC#8 second call verdict should still be 'suppress'" >&2
    exit 1
  fi
)

if [ ! -f "$EVENTS_AC8" ]; then
  echo "FAIL: AC#8 events.jsonl missing"
  exit 1
fi
# Exactly ONE quiet_hours_skip event because the caller respects the guard.
SKIP_AC8="$(awk '/"type":"quiet_hours_skip"/ { n++ } END { print (n+0) }' "$EVENTS_AC8")"
if [ "$SKIP_AC8" -ne 1 ]; then
  echo "FAIL: AC#8 want exactly 1 quiet_hours_skip event, got $SKIP_AC8"
  cat "$EVENTS_AC8"
  exit 1
fi

# Validate payload shape via node.
node -e '
  const fs = require("fs");
  const lines = fs.readFileSync(process.argv[1], "utf8").split("\n").filter(Boolean);
  const ev = lines.map(JSON.parse).find(e => e.type === "quiet_hours_skip");
  if (!ev) { console.error("FAIL: AC#8 no quiet_hours_skip event parsed"); process.exit(1); }
  // Top-level schema keys (every event):
  for (const k of ["ts","slug","phase","type"]) {
    if (typeof ev[k] !== "string" || ev[k].length === 0) {
      console.error("FAIL: AC#8 event missing/empty " + k + ": " + JSON.stringify(ev));
      process.exit(1);
    }
  }
  // Type-specific keys.
  if (ev.phase !== "groom") {
    console.error("FAIL: AC#8 ev.phase=" + ev.phase + " (want groom)");
    process.exit(1);
  }
  if (ev.window !== "22:00-07:00") {
    console.error("FAIL: AC#8 ev.window=" + ev.window + " (want 22:00-07:00)");
    process.exit(1);
  }
  if (ev.now_local !== "2026-06-06T03:15:00-0700") {
    console.error("FAIL: AC#8 ev.now_local=" + ev.now_local + " (want 2026-06-06T03:15:00-0700)");
    process.exit(1);
  }
  console.log("ok: AC#8 event payload {phase, window, now_local} shape valid");
' "$EVENTS_AC8"

# ===========================================================================
# AC #9 — AGENTS.md § Telemetry documents quiet_hours_skip with the
#         {phase, window, now_local} shape, following the existing entry
#         style. Reviewer's telemetry-contract check requires this in the
#         same diff.
# ===========================================================================
AGENTS="$REPO_ROOT/AGENTS.md"
if ! grep -qF -- 'quiet_hours_skip' "$AGENTS"; then
  echo "FAIL: AC#9 AGENTS.md § Telemetry must mention quiet_hours_skip"
  exit 1
fi
if ! grep -qE 'quiet_hours_skip[[:space:]]*\{[^}]*phase[^}]*window[^}]*now_local' "$AGENTS"; then
  echo "FAIL: AC#9 AGENTS.md must document quiet_hours_skip with {phase, window, now_local} shape"
  grep -F 'quiet_hours_skip' "$AGENTS" || true
  exit 1
fi
echo "ok: AC#9 AGENTS.md § Telemetry documents quiet_hours_skip"

# ===========================================================================
# AC #10 — manifest.example.sh has a `# --- quiet hours ---` section with
#          `QUIET_HOURS=""` and the User-lens comment.
# ===========================================================================
MANIFEST="$REPO_ROOT/manifest.example.sh"
if ! grep -qF -- '# --- quiet hours ---' "$MANIFEST"; then
  echo "FAIL: AC#10 manifest.example.sh missing '# --- quiet hours ---' section header"
  exit 1
fi
if ! grep -qE '^# QUIET_HOURS=""$' "$MANIFEST"; then
  echo "FAIL: AC#10 manifest.example.sh missing commented '# QUIET_HOURS=\"\"' default"
  grep -F 'QUIET_HOURS' "$MANIFEST" || true
  exit 1
fi
if ! grep -qF -- 'Local time' "$MANIFEST"; then
  echo "FAIL: AC#10 manifest.example.sh missing the 'Local time' explanatory comment"
  exit 1
fi
echo "ok: AC#10 manifest.example.sh documents QUIET_HOURS=\"\" default"

# ===========================================================================
# AC #11 — lib/install.sh copies the QUIET_HOURS line through to the
#          per-project installed manifest byte-for-byte. Idempotent
#          re-install is still a no-op.
# ===========================================================================
# Build a synthetic project dir whose agents.config.sh carries a
# QUIET_HOURS line, run install.sh, and assert the installed copy under
# ~/.local/share/agent-fleet/projects/<slug>/agents.config.sh contains
# the SAME line byte-for-byte. We don't actually want launchd to fire,
# so we stub launchctl (already done above) and just check the copy.
INSTALL_SRC="$TMP/install-src"
mkdir -p "$INSTALL_SRC"
cat > "$INSTALL_SRC/agents.config.sh" <<'CFG'
SLUG="quietinstalltest"
PROJECT_NAME="quietinstalltest"
NAMESPACE="com.fleet.quietinstalltest"
REPO_URL="https://github.com/example/quietinstalltest.git"
SELF_CANCEL="20990101"
MAX_DAILY_USD=5
QUIET_HOURS="22:00-07:00"
CFG

INSTALLED_CFG="$HOME/.local/share/agent-fleet/projects/quietinstalltest/agents.config.sh"
rm -rf "$HOME/.local/share/agent-fleet"

set +e
bash "$REPO_ROOT/lib/install.sh" "$INSTALL_SRC" > "$TMP/install.out" 2> "$TMP/install.err"
INSTALL_EXIT=$?
set -e
if [ "$INSTALL_EXIT" -ne 0 ]; then
  echo "FAIL: AC#11 lib/install.sh exited $INSTALL_EXIT"
  cat "$TMP/install.err"
  exit 1
fi
if [ ! -f "$INSTALLED_CFG" ]; then
  echo "FAIL: AC#11 installed manifest missing at $INSTALLED_CFG"
  ls -la "$HOME/.local/share/agent-fleet/projects/" 2>/dev/null || true
  exit 1
fi

# The installed copy MUST contain the verbatim QUIET_HOURS line.
if ! grep -qE '^QUIET_HOURS="22:00-07:00"$' "$INSTALLED_CFG"; then
  echo "FAIL: AC#11 installed manifest missing verbatim 'QUIET_HOURS=\"22:00-07:00\"' line"
  echo "installed manifest contents:"
  cat "$INSTALLED_CFG"
  exit 1
fi

# Idempotent re-install: run install.sh a second time and confirm the
# QUIET_HOURS line is still byte-identical (install.sh would normally
# append PROMPTS_SHA stamps but the source line stays intact).
set +e
bash "$REPO_ROOT/lib/install.sh" "$INSTALL_SRC" > "$TMP/install2.out" 2> "$TMP/install2.err"
INSTALL2_EXIT=$?
set -e
if [ "$INSTALL2_EXIT" -ne 0 ]; then
  echo "FAIL: AC#11 second install.sh exited $INSTALL2_EXIT"
  cat "$TMP/install2.err"
  exit 1
fi
if ! grep -qE '^QUIET_HOURS="22:00-07:00"$' "$INSTALLED_CFG"; then
  echo "FAIL: AC#11 re-install dropped the QUIET_HOURS line"
  cat "$INSTALLED_CFG"
  exit 1
fi
echo "ok: AC#11 lib/install.sh copies QUIET_HOURS byte-for-byte (idempotent)"

echo
echo "all quiet-hours.sh assertions passed."
