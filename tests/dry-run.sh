#!/bin/bash
# tests/dry-run.sh — AGENT_DRY_RUN end-to-end mode (ticket 0010).
#
# One assertion block per acceptance-criteria checkbox in
# docs/backlog/0010-dry-run-mode.md. Strategy:
#   * Stub `claude` on PATH so we can (a) record the argv it receives and
#     (b) return a canned JSON envelope that fleet_run_claude treats as a
#     real run. The stub writes argv to $CLAUDE_LOG and a tiny JSON body
#     containing `result`, `session_id`, `total_cost_usd`, etc. to stdout.
#   * Stub `launchctl` for the `fleet kickstart` AC blocks. It records argv
#     to $LAUNCHCTL_LOG and, importantly, when invoked as
#     `launchctl kickstart ...` writes the current value of AGENT_DRY_RUN
#     into $SENTINEL — that's how AC#5/AC#6 prove the env was (or wasn't)
#     set across the kickstart call.
#   * HOME is redirected under $TMP so we never touch real ~/.cache state.
#
# Self-contained, no jq dependency for the assertions (we parse the
# resulting JSONL with sed/awk to keep the test portable).

set -euo pipefail

REPO_ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
FLEET="$REPO_ROOT/bin/fleet"

TMP="$(mktemp -d -t fleet-dry-run-test.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

export HOME="$TMP/home"
mkdir -p "$HOME"

# --- manifest the runner will source -------------------------------------
MANIFEST_DIR="$TMP/project"
mkdir -p "$MANIFEST_DIR"
cat > "$MANIFEST_DIR/agents.config.sh" <<'CFG'
SLUG="dryruntest"
PROJECT_NAME="dryruntest"
NAMESPACE="com.dryruntest"
REPO_URL="https://github.com/example/dryruntest.git"
SELF_CANCEL="20990101"
CFG

# Per-slug cache (where runs.jsonl + events.jsonl land).
CACHE_DIR="$HOME/.cache/dryruntest-agent"
RUNS_FILE="$CACHE_DIR/runs.jsonl"
EVENTS_FILE="$CACHE_DIR/events.jsonl"

# --- claude stub ----------------------------------------------------------
# Records argv to $CLAUDE_LOG, emits a canned JSON envelope on stdout so
# fleet_run_claude's jq path is exercised end-to-end. The `result` field
# is long enough to make the 200-char `plan_head` truncation observable.
#
# IMPORTANT: lib/common.sh resets PATH to a hardcoded list at source time
# (`$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:...`) — see the
# `export PATH=...` line at the top of common.sh. To survive that reset we
# place stubs under `$HOME/.local/bin`, which is the very first entry in
# the reset PATH. `bin/fleet` is a standalone shell script that does NOT
# source common.sh, so its PATH inherits from the test process — the same
# stub dir works for it.
BIN_STUB="$HOME/.local/bin"
mkdir -p "$BIN_STUB"
CLAUDE_LOG="$TMP/claude.log"
LAUNCHCTL_LOG="$TMP/launchctl.log"
SENTINEL="$TMP/sentinel.env"
: > "$CLAUDE_LOG"
: > "$LAUNCHCTL_LOG"

cat > "$BIN_STUB/claude" <<STUB
#!/bin/bash
# Append argv (one line) to $CLAUDE_LOG so tests can diff it.
printf '%s\n' "claude \$*" >> "$CLAUDE_LOG"
# Drain stdin so the real fleet_run_claude pipe behaves naturally.
cat >/dev/null 2>&1 || true
# Emit a canned JSON envelope — the same shape claude --output-format json
# would write today (result + session_id + total_cost_usd + duration_ms +
# num_turns + usage + is_error). We pad \`result\` past 200 chars so the
# plan_head truncation in AC#3 is observable.
cat <<'JSON'
{
  "result": "DRYRUN PLAN: ship 0010 — would write tests/dry-run.sh, branch in fleet_run_claude on AGENT_DRY_RUN, append --allowedTools none, swap run_completed for run_dry_run, document under README Daily ops. tail of plan beyond 200.",
  "session_id": "abc123",
  "total_cost_usd": 0.42,
  "duration_ms": 12345,
  "num_turns": 1,
  "usage": {"input_tokens": 100, "output_tokens": 200},
  "is_error": false
}
JSON
exit 0
STUB
chmod +x "$BIN_STUB/claude"

SETENV_STATE="$TMP/launchd-setenv.state"
: > "$SETENV_STATE"
cat > "$BIN_STUB/launchctl" <<STUB
#!/bin/bash
# Record argv to the log.
printf '%s\n' "launchctl \$*" >> "$LAUNCHCTL_LOG"
# Simulate launchd's session env: 'launchctl setenv KEY VALUE' updates the
# user-session env, which 'launchctl kickstart' propagates into the spawned
# job's env. We model that with a state file that setenv writes and
# kickstart reads — closer to production semantics than reading the calling
# shell's env (which would lose the setenv between processes).
case "\${1:-}" in
  setenv)
    # \$2=key \$3=value
    if [ -n "\${2:-}" ]; then
      # Strip any prior entry for this key, then append the new one.
      grep -v "^\${2}=" "$SETENV_STATE" 2>/dev/null > "$SETENV_STATE.tmp" || true
      printf '%s=%s\n' "\$2" "\${3:-}" >> "$SETENV_STATE.tmp"
      mv "$SETENV_STATE.tmp" "$SETENV_STATE"
    fi
    ;;
  unsetenv)
    if [ -n "\${2:-}" ]; then
      grep -v "^\${2}=" "$SETENV_STATE" 2>/dev/null > "$SETENV_STATE.tmp" || true
      mv "$SETENV_STATE.tmp" "$SETENV_STATE"
    fi
    ;;
  kickstart)
    # Resolve the simulated session value of AGENT_DRY_RUN and write it
    # to the sentinel so the test can assert what the spawned job would
    # have inherited.
    val=""
    if [ -f "$SETENV_STATE" ]; then
      val="\$(sed -n 's/^AGENT_DRY_RUN=//p' "$SETENV_STATE" | tail -1)"
    fi
    printf 'AGENT_DRY_RUN=%s\n' "\$val" > "$SENTINEL"
    ;;
esac
exit 0
STUB
chmod +x "$BIN_STUB/launchctl"

export PATH="$BIN_STUB:$PATH"

reset_state() {
  : > "$CLAUDE_LOG"
  : > "$LAUNCHCTL_LOG"
  : > "$SETENV_STATE"
  rm -f "$SENTINEL"
  rm -rf "$CACHE_DIR"
  mkdir -p "$CACHE_DIR"
}

# Run fleet_run_claude in a subshell that sources common.sh + the manifest.
# $1 = AGENT_DRY_RUN value (empty string == unset). Captures stdout +
# returns whatever fleet_run_claude returned.
invoke_run_claude() {
  local dry_value="$1"
  local out
  out="$(
    set -u
    # shellcheck disable=SC1091
    source "$REPO_ROOT/lib/common.sh"
    fleet_load_manifest "$MANIFEST_DIR"
    # Mirror what fleet_log_init does so fleet_emit_event tags events.
    FLEET_PHASE="ship"
    RUN_STARTED_UTC="$(date -u +%FT%TZ)"
    export FLEET_PHASE RUN_STARTED_UTC
    if [ -n "$dry_value" ]; then
      export AGENT_DRY_RUN="$dry_value"
    else
      unset AGENT_DRY_RUN
    fi
    # Stdin is unused by the stub but the real claude reads the prompt.
    printf 'pretend-prompt\n' | fleet_run_claude ship
  )" || true
  printf '%s' "$out"
}

# ========================================================================
# AC #1 — Given AGENT_DRY_RUN=1, fleet_run_claude calls claude with argv
#         containing `--allowedTools` followed by `none`.
# ========================================================================
reset_state
invoke_run_claude "1" >/dev/null
if ! grep -qE -- '--allowedTools[[:space:]]+none' "$CLAUDE_LOG"; then
  echo "FAIL: AC#1 expected '--allowedTools none' in claude argv when AGENT_DRY_RUN=1"
  cat "$CLAUDE_LOG"
  exit 1
fi
echo "ok: AC#1 AGENT_DRY_RUN=1 injects --allowedTools none"

# ========================================================================
# AC #2 — With AGENT_DRY_RUN unset, claude argv does NOT contain
#         `--allowedTools none`.
# ========================================================================
reset_state
invoke_run_claude "" >/dev/null
if grep -qE -- '--allowedTools[[:space:]]+none' "$CLAUDE_LOG"; then
  echo "FAIL: AC#2 claude argv must not include '--allowedTools none' when AGENT_DRY_RUN is unset"
  cat "$CLAUDE_LOG"
  exit 1
fi
echo "ok: AC#2 unset AGENT_DRY_RUN leaves argv alone"

# ========================================================================
# AC #3 — Dry-run emits `run_dry_run plan_head=<first-200-chars>` and does
#         NOT emit `run_completed`.
# ========================================================================
reset_state
invoke_run_claude "1" >/dev/null
if [ ! -f "$EVENTS_FILE" ]; then
  echo "FAIL: AC#3 expected events.jsonl at $EVENTS_FILE"
  exit 1
fi
if ! grep -q '"type":"run_dry_run"' "$EVENTS_FILE"; then
  echo "FAIL: AC#3 expected a run_dry_run event in events.jsonl"
  cat "$EVENTS_FILE"
  exit 1
fi
if grep -q '"type":"run_completed"' "$EVENTS_FILE"; then
  echo "FAIL: AC#3 dry-run must NOT also emit run_completed"
  cat "$EVENTS_FILE"
  exit 1
fi
if ! grep -q '"plan_head":' "$EVENTS_FILE"; then
  echo "FAIL: AC#3 run_dry_run event missing plan_head field"
  cat "$EVENTS_FILE"
  exit 1
fi
# Extract plan_head and confirm it's <=200 chars and is a prefix of the
# stub's `result` string.
plan_head="$(sed -nE 's/.*"plan_head":"([^"]*)".*/\1/p' "$EVENTS_FILE" | head -1)"
if [ -z "$plan_head" ]; then
  echo "FAIL: AC#3 could not parse plan_head"
  cat "$EVENTS_FILE"
  exit 1
fi
if [ "${#plan_head}" -gt 200 ]; then
  echo "FAIL: AC#3 plan_head must be <=200 chars (got ${#plan_head})"
  exit 1
fi
case "$plan_head" in
  "DRYRUN PLAN: ship 0010"*) ;;
  *)
    echo "FAIL: AC#3 plan_head should be a prefix of the claude result"
    echo "plan_head=$plan_head"
    exit 1 ;;
esac
echo "ok: AC#3 run_dry_run replaces run_completed and carries plan_head"

# ========================================================================
# AC #4 — Dry-run still appends to runs.jsonl with cost + result.
# ========================================================================
# Reuses the events.jsonl run above (reset_state cleared CACHE_DIR before).
if [ ! -f "$RUNS_FILE" ]; then
  echo "FAIL: AC#4 expected runs.jsonl at $RUNS_FILE"
  exit 1
fi
if ! grep -q '"total_cost_usd":0.42' "$RUNS_FILE"; then
  echo "FAIL: AC#4 runs.jsonl missing the canned total_cost_usd=0.42"
  cat "$RUNS_FILE"
  exit 1
fi
if ! grep -q '"result_head":"DRYRUN PLAN' "$RUNS_FILE"; then
  echo "FAIL: AC#4 runs.jsonl missing result_head prefix"
  cat "$RUNS_FILE"
  exit 1
fi
echo "ok: AC#4 runs.jsonl still records cost + result on dry-run"

# ========================================================================
# AC #5 — `bin/fleet kickstart <slug> <phase> --dry-run` exports
#         AGENT_DRY_RUN=1 across the launchctl kickstart call.
# ========================================================================
reset_state
# Discovery for `fleet kickstart` mirrors `fleet doctor`/`fleet tail` —
# point FLEET_DISCOVERY_ROOT at the fixture so the slug resolves.
FIXTURE="$TMP/projects"
mkdir -p "$FIXTURE/dryruntest"
cp "$MANIFEST_DIR/agents.config.sh" "$FIXTURE/dryruntest/agents.config.sh"
export FLEET_DISCOVERY_ROOT="$FIXTURE"

"$FLEET" kickstart dryruntest ship --dry-run >/dev/null 2>&1 \
  || { echo "FAIL: AC#5 fleet kickstart --dry-run returned non-zero"; cat "$LAUNCHCTL_LOG"; exit 1; }

if ! grep -qE 'launchctl kickstart -k gui/[0-9]+/com\.dryruntest\.agent-ship' "$LAUNCHCTL_LOG"; then
  echo "FAIL: AC#5 expected 'launchctl kickstart -k gui/<uid>/com.dryruntest.agent-ship'"
  cat "$LAUNCHCTL_LOG"
  exit 1
fi
if [ ! -f "$SENTINEL" ]; then
  echo "FAIL: AC#5 sentinel file missing — launchctl kickstart never fired"
  cat "$LAUNCHCTL_LOG"
  exit 1
fi
if ! grep -q '^AGENT_DRY_RUN=1$' "$SENTINEL"; then
  echo "FAIL: AC#5 expected AGENT_DRY_RUN=1 to be exported across kickstart"
  echo "sentinel:"; cat "$SENTINEL"
  echo "launchctl log:"; cat "$LAUNCHCTL_LOG"
  exit 1
fi
echo "ok: AC#5 fleet kickstart --dry-run kickstarts with AGENT_DRY_RUN=1"

# ========================================================================
# AC #6 — `bin/fleet kickstart <slug> <phase>` (no flag) does NOT set
#         AGENT_DRY_RUN.
# ========================================================================
reset_state
# Ensure no leftover env from the test process.
unset AGENT_DRY_RUN
"$FLEET" kickstart dryruntest ship >/dev/null 2>&1 \
  || { echo "FAIL: AC#6 fleet kickstart (no flag) returned non-zero"; cat "$LAUNCHCTL_LOG"; exit 1; }

if [ ! -f "$SENTINEL" ]; then
  echo "FAIL: AC#6 sentinel file missing — launchctl kickstart never fired"
  cat "$LAUNCHCTL_LOG"
  exit 1
fi
if ! grep -q '^AGENT_DRY_RUN=$' "$SENTINEL"; then
  echo "FAIL: AC#6 plain kickstart must leave AGENT_DRY_RUN unset (sentinel shows it set)"
  echo "sentinel:"; cat "$SENTINEL"
  echo "launchctl log:"; cat "$LAUNCHCTL_LOG"
  exit 1
fi
echo "ok: AC#6 plain fleet kickstart leaves AGENT_DRY_RUN unset"

# ========================================================================
# AC #7 — README "Daily ops" section mentions AGENT_DRY_RUN env var AND
#         the `--dry-run` kickstart flag.
# ========================================================================
README="$REPO_ROOT/README.md"
if ! grep -q 'AGENT_DRY_RUN' "$README"; then
  echo "FAIL: AC#7 README.md must mention AGENT_DRY_RUN"
  exit 1
fi
if ! grep -qE 'kickstart .*--dry-run|--dry-run.*kickstart' "$README"; then
  echo "FAIL: AC#7 README.md must mention the --dry-run kickstart flag"
  exit 1
fi
echo "ok: AC#7 README documents env var + --dry-run flag"

echo
echo "all dry-run.sh assertions passed."
