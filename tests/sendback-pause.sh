#!/bin/bash
# tests/sendback-pause.sh — fleet_check_sendback_streak auto-pause test.
#
# Ticket 0006. Stubs `gh`, `launchctl`, and `date` so the function under test
# sees a deterministic universe, then asserts:
#   1. TRIP path — when 3 or more agent-branch PRs in the last 24h received
#      REQUEST_CHANGES and closed without resolution, the function:
#        - returns non-zero (caller does `|| exit 0` to abort PHASE 2)
#        - appends a `ship_paused` event to events.jsonl with
#          reason=sendback_streak and a count>=3
#        - posts a NEW GitHub Issue titled `[FLEET] ship paused after N
#          send-backs` (idempotency: when the issue already exists, the
#          function updates the existing one instead of creating a duplicate)
#        - invokes `launchctl disable gui/<UID>/<NAMESPACE>.agent-ship`
#   2. NO-TRIP path — when only 2 recent send-backs (plus one older than 24h),
#      the function returns 0, emits NO `ship_paused` event, and does NOT
#      touch `gh issue create` or `launchctl disable`.
#   3. PHASE 1 unaffected — the function exposes its decision via the env var
#      `FLEET_SHIP_PAUSED` (1 on trip, unset otherwise). The ship runner is
#      expected to use this to gate PHASE 2 only; PHASE 1 (heal) reads the
#      same channel and is free to proceed. We assert the env contract here.
#
# Self-contained: stubs $HOME so we never touch real ~/.cache state. Exits
# non-zero on any failure.

set -euo pipefail

REPO_ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"

TMP="$(mktemp -d -t fleet-sendback-test.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

# Isolate from the real fleet cache. CACHE_DIR is derived from $HOME + $SLUG.
export HOME="$TMP/home"
mkdir -p "$HOME"

MANIFEST_DIR="$TMP/project"
mkdir -p "$MANIFEST_DIR"
cat > "$MANIFEST_DIR/agents.config.sh" <<'CFG'
SLUG="sendbacktest"
PROJECT_NAME="sendbacktest"
REPO_URL="https://github.com/example/sendbacktest.git"
NAMESPACE="com.fleet.sendbacktest"
SELF_CANCEL="20990101"
CFG

CACHE="$HOME/.cache/sendbacktest-agent"
EVENTS="$CACHE/events.jsonl"
mkdir -p "$CACHE"

# --- stub binaries on PATH ------------------------------------------------
# We prepend $TMP/bin to PATH so the function under test calls our stubs
# instead of the real `gh` and `launchctl`. Each stub writes a transcript
# to $TMP/calls.log so the test can assert what was invoked, with what args.
STUB_BIN="$TMP/bin"
mkdir -p "$STUB_BIN"
CALLS_LOG="$TMP/calls.log"
: > "$CALLS_LOG"

# `gh` stub. The function under test issues at most two kinds of calls:
#   (a) `gh pr list --state closed --search "..." --json ...`
#       → we emit a canned JSON array driven by $TMP/gh-prs.json
#   (b) `gh issue list --search "..." --json number,title --state open`
#       → driven by $TMP/gh-issue.json
#   (c) `gh issue create ...` or `gh issue comment ...`
#       → no-op, but logged
cat > "$STUB_BIN/gh" <<GH_EOF
#!/bin/bash
# Log one line per invocation in the form "gh ARG1 ARG2 ..." with raw,
# UNESCAPED argv (separated by U+001F so the test can grep on substrings
# that include spaces without worrying about printf %q escaping).
{
  printf 'gh'
  for a in "\$@"; do printf ' %s' "\$a"; done
  printf '\n'
} >> "$CALLS_LOG"

case " \$* " in
  *" pr list "*)
    cat "$TMP/gh-prs.json"
    ;;
  *" issue list "*)
    cat "$TMP/gh-issue.json"
    ;;
  *" issue create "*|*" issue comment "*|*" issue edit "*)
    # Pretend the create succeeded — print a URL like real gh does.
    echo "https://github.com/example/sendbacktest/issues/999"
    ;;
  *)
    echo "stub-gh: unhandled invocation: \$*" >&2
    exit 2
    ;;
esac
GH_EOF
chmod +x "$STUB_BIN/gh"

# `launchctl` stub — just log the argv.
cat > "$STUB_BIN/launchctl" <<LC_EOF
#!/bin/bash
{
  printf 'launchctl'
  for a in "\$@"; do printf ' %s' "\$a"; done
  printf '\n'
} >> "$CALLS_LOG"
exit 0
LC_EOF
chmod +x "$STUB_BIN/launchctl"

export PATH="$STUB_BIN:$PATH"

# Compute timestamps for the canned PRs. Recent = 2h ago; old = 36h ago.
RECENT_TS="$(date -u -v-2H +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d '2 hours ago' +%Y-%m-%dT%H:%M:%SZ)"
OLD_TS="$(date -u -v-36H +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d '36 hours ago' +%Y-%m-%dT%H:%M:%SZ)"

# ===========================================================================
# CASE A — TRIP: three recent agent-branch send-backs in the last 24h.
# ===========================================================================
cat > "$TMP/gh-prs.json" <<JSON
[
  {"number": 101, "closedAt": "${RECENT_TS}", "headRefName": "feat/0010-a", "reviews": [{"state": "CHANGES_REQUESTED", "submittedAt": "${RECENT_TS}"}]},
  {"number": 102, "closedAt": "${RECENT_TS}", "headRefName": "feat/0011-b", "reviews": [{"state": "CHANGES_REQUESTED", "submittedAt": "${RECENT_TS}"}]},
  {"number": 103, "closedAt": "${RECENT_TS}", "headRefName": "eng/0012-c",  "reviews": [{"state": "CHANGES_REQUESTED", "submittedAt": "${RECENT_TS}"}]},
  {"number": 104, "closedAt": "${OLD_TS}",    "headRefName": "feat/0013-d", "reviews": [{"state": "CHANGES_REQUESTED", "submittedAt": "${OLD_TS}"}]}
]
JSON
# No existing meta-issue → expect a CREATE.
echo '[]' > "$TMP/gh-issue.json"

(
  set -euo pipefail
  # shellcheck disable=SC1091
  source "$REPO_ROOT/lib/common.sh"
  fleet_load_manifest "$MANIFEST_DIR"
  FLEET_PHASE="ship"; export FLEET_PHASE
  # common.sh resets PATH for launchd-safety; re-prepend the stubs AFTER
  # sourcing so `command -v gh` and `command -v launchctl` resolve here.
  export PATH="$STUB_BIN:$PATH"
  if fleet_check_sendback_streak; then
    echo "FAIL: trip path expected non-zero exit (caller aborts)"
    exit 1
  fi
  if [ "${FLEET_SHIP_PAUSED:-}" != "1" ]; then
    echo "FAIL: trip path expected FLEET_SHIP_PAUSED=1, got '${FLEET_SHIP_PAUSED:-}'"
    exit 1
  fi
) || exit 1

if [ ! -f "$EVENTS" ]; then
  echo "FAIL: events.jsonl not created on trip path"
  exit 1
fi
if ! grep -q '"type":"ship_paused"' "$EVENTS"; then
  echo "FAIL: ship_paused event missing from events.jsonl"
  cat "$EVENTS"
  exit 1
fi

node -e '
  const fs = require("fs");
  const lines = fs.readFileSync(process.argv[1], "utf8").split("\n").filter(Boolean);
  const ev = lines.map(JSON.parse).find(e => e.type === "ship_paused");
  if (!ev) { console.error("FAIL: no ship_paused event parsed"); process.exit(1); }
  if (ev.reason !== "sendback_streak") {
    console.error("FAIL: ship_paused.reason=" + ev.reason + " (want sendback_streak)");
    process.exit(1);
  }
  if (!ev.count || parseInt(ev.count, 10) < 3) {
    console.error("FAIL: ship_paused.count=" + ev.count + " (want >=3)");
    process.exit(1);
  }
  console.log("ok: ship_paused event payload");
' "$EVENTS"

# Issue create + launchctl disable must have been called.
if ! grep -q 'gh issue create' "$CALLS_LOG"; then
  echo "FAIL: gh issue create not invoked on trip path"
  cat "$CALLS_LOG"
  exit 1
fi
if ! grep -qF '[FLEET] ship paused after' "$CALLS_LOG"; then
  echo "FAIL: gh issue create did not carry the expected title fragment"
  cat "$CALLS_LOG"
  exit 1
fi
if ! grep -qE 'launchctl disable gui/[0-9]+/com\.fleet\.sendbacktest\.agent-ship' "$CALLS_LOG"; then
  echo "FAIL: launchctl disable not invoked with the expected target"
  cat "$CALLS_LOG"
  exit 1
fi

# ===========================================================================
# CASE B — IDEMPOTENT META-ISSUE: a matching open issue already exists; the
# function should COMMENT on it (or edit it) rather than create a new one.
# ===========================================================================
: > "$CALLS_LOG"
: > "$EVENTS"
echo '[{"number": 555, "title": "[FLEET] ship paused after 3 send-backs"}]' > "$TMP/gh-issue.json"

(
  set -euo pipefail
  # shellcheck disable=SC1091
  source "$REPO_ROOT/lib/common.sh"
  fleet_load_manifest "$MANIFEST_DIR"
  FLEET_PHASE="ship"; export FLEET_PHASE
  # common.sh resets PATH for launchd-safety; re-prepend the stubs AFTER
  # sourcing so `command -v gh` and `command -v launchctl` resolve here.
  export PATH="$STUB_BIN:$PATH"
  if fleet_check_sendback_streak; then
    echo "FAIL: trip path expected non-zero exit (idempotent meta-issue case)"
    exit 1
  fi
) || exit 1

if grep -q 'gh issue create' "$CALLS_LOG"; then
  echo "FAIL: gh issue create called even though meta-issue already exists"
  cat "$CALLS_LOG"
  exit 1
fi
if ! grep -qE 'gh issue (comment|edit) [^ ]*555' "$CALLS_LOG"; then
  echo "FAIL: existing meta-issue #555 should have been commented-on or edited"
  cat "$CALLS_LOG"
  exit 1
fi

# ===========================================================================
# CASE C — NO TRIP: only 2 recent send-backs in the last 24h (plus old).
# ===========================================================================
: > "$CALLS_LOG"
: > "$EVENTS"
cat > "$TMP/gh-prs.json" <<JSON
[
  {"number": 201, "closedAt": "${RECENT_TS}", "headRefName": "feat/0020-a", "reviews": [{"state": "CHANGES_REQUESTED", "submittedAt": "${RECENT_TS}"}]},
  {"number": 202, "closedAt": "${RECENT_TS}", "headRefName": "feat/0021-b", "reviews": [{"state": "CHANGES_REQUESTED", "submittedAt": "${RECENT_TS}"}]},
  {"number": 203, "closedAt": "${OLD_TS}",    "headRefName": "feat/0022-c", "reviews": [{"state": "CHANGES_REQUESTED", "submittedAt": "${OLD_TS}"}]},
  {"number": 204, "closedAt": "${OLD_TS}",    "headRefName": "feat/0023-d", "reviews": [{"state": "CHANGES_REQUESTED", "submittedAt": "${OLD_TS}"}]}
]
JSON
echo '[]' > "$TMP/gh-issue.json"

(
  set -euo pipefail
  # shellcheck disable=SC1091
  source "$REPO_ROOT/lib/common.sh"
  fleet_load_manifest "$MANIFEST_DIR"
  FLEET_PHASE="ship"; export FLEET_PHASE
  # common.sh resets PATH for launchd-safety; re-prepend the stubs AFTER
  # sourcing so `command -v gh` and `command -v launchctl` resolve here.
  export PATH="$STUB_BIN:$PATH"
  if ! fleet_check_sendback_streak; then
    echo "FAIL: 2 recent send-backs is below the threshold; function should return 0"
    exit 1
  fi
  if [ "${FLEET_SHIP_PAUSED:-}" = "1" ]; then
    echo "FAIL: no-trip path should leave FLEET_SHIP_PAUSED unset, got '1'"
    exit 1
  fi
) || exit 1

if [ -f "$EVENTS" ] && grep -q '"type":"ship_paused"' "$EVENTS"; then
  echo "FAIL: no-trip path emitted a ship_paused event"
  cat "$EVENTS"
  exit 1
fi
if grep -q 'gh issue create' "$CALLS_LOG"; then
  echo "FAIL: no-trip path called gh issue create"
  cat "$CALLS_LOG"
  exit 1
fi
if grep -q 'launchctl disable' "$CALLS_LOG"; then
  echo "FAIL: no-trip path called launchctl disable"
  cat "$CALLS_LOG"
  exit 1
fi

# ===========================================================================
# CASE D — TRIP path is excluded for non-agent-branch PRs. A human's branch
# named "fix/whatever" must NOT count toward the streak.
# ===========================================================================
: > "$CALLS_LOG"
: > "$EVENTS"
cat > "$TMP/gh-prs.json" <<JSON
[
  {"number": 301, "closedAt": "${RECENT_TS}", "headRefName": "feat/0030-a",         "reviews": [{"state": "CHANGES_REQUESTED", "submittedAt": "${RECENT_TS}"}]},
  {"number": 302, "closedAt": "${RECENT_TS}", "headRefName": "fix/human-cleanup",   "reviews": [{"state": "CHANGES_REQUESTED", "submittedAt": "${RECENT_TS}"}]},
  {"number": 303, "closedAt": "${RECENT_TS}", "headRefName": "release/2026-05-26",  "reviews": [{"state": "CHANGES_REQUESTED", "submittedAt": "${RECENT_TS}"}]},
  {"number": 304, "closedAt": "${RECENT_TS}", "headRefName": "feat/0031-b",         "reviews": [{"state": "CHANGES_REQUESTED", "submittedAt": "${RECENT_TS}"}]}
]
JSON
echo '[]' > "$TMP/gh-issue.json"

(
  set -euo pipefail
  # shellcheck disable=SC1091
  source "$REPO_ROOT/lib/common.sh"
  fleet_load_manifest "$MANIFEST_DIR"
  FLEET_PHASE="ship"; export FLEET_PHASE
  # common.sh resets PATH for launchd-safety; re-prepend the stubs AFTER
  # sourcing so `command -v gh` and `command -v launchctl` resolve here.
  export PATH="$STUB_BIN:$PATH"
  if ! fleet_check_sendback_streak; then
    echo "FAIL: only 2 agent-branch send-backs after prefix filter; should not trip"
    exit 1
  fi
) || exit 1

if grep -q 'gh issue create' "$CALLS_LOG"; then
  echo "FAIL: prefix-filtered no-trip still called gh issue create"
  cat "$CALLS_LOG"
  exit 1
fi

echo "ok: tests/sendback-pause.sh passed"

