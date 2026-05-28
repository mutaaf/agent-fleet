#!/bin/bash
# tests/heal-infra-flake.sh — heal-phase infra-flake catalog test (ticket 0020).
#
# One assertion block per acceptance-criteria checkbox in
# docs/backlog/0020-heal-detects-infra-flake-and-reruns.md:
#
#   AC#1  fleet_match_infra_flake <log-file> prints one of the four catalog
#         tokens or empty.
#   AC#2  lib/heal-catalog.sh ships the four catalog patterns AND each is
#         annotated with the LESSONS entry it codifies (date + repo).
#   AC#3  Four fixture logs (one per pattern) map to their expected token,
#         plus a negative fixture (a real shellcheck failure) returns empty.
#   AC#4  prompts/ship.prompt.md PHASE 1 RED branch wires up the catalog —
#         asserted by grepping the prompt for `fleet_match_infra_flake` and
#         for `gh run rerun`.
#   AC#5  Dedupe: a second invocation within 2h scanning events.jsonl for
#         the same pattern + run_id falls through to the normal heal path
#         (we expose `fleet_infra_flake_already_rerun <token> <run_id>` so
#         the prompt's pre-step can ask the question shell-side).
#   AC#6  AGENTS.md § Telemetry gains an `infra_flake_rerun` event-type
#         bullet (same shape as `rollback_opened` / `events_rotated`).
#   AC#7  This file covers all of the above end-to-end.
#   AC#8  lib/common.sh public API unchanged — additive only. Asserted by
#         grepping for each of the documented public fleet_* names.
#
# Self-contained. Uses $HOME/.local/bin for stubs (per LESSONS 2026-05-26:
# lib/common.sh resets PATH, so a $TMP/bin stub gets clobbered).

set -euo pipefail

REPO_ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"

TMP="$(mktemp -d -t fleet-heal-infra-flake-test.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

export HOME="$TMP/home"
mkdir -p "$HOME"

# Per-slug manifest.
MANIFEST_DIR="$TMP/project"
mkdir -p "$MANIFEST_DIR"
cat > "$MANIFEST_DIR/agents.config.sh" <<'CFG'
SLUG="healflaketest"
PROJECT_NAME="healflaketest"
REPO_URL="https://github.com/example/healflaketest.git"
SELF_CANCEL="20990101"
CFG

CACHE_DIR="$HOME/.cache/healflaketest-agent"
EVENTS_FILE="$CACHE_DIR/events.jsonl"

# Stubs survive the PATH reset only when they live in $HOME/.local/bin.
BIN_STUB="$HOME/.local/bin"
mkdir -p "$BIN_STUB"

# --- fixture logs (AC#3) -------------------------------------------------
FIX_DIR="$TMP/fixtures"
mkdir -p "$FIX_DIR"

# actions_silent — recreate the agent-fleet 2026-05-26 lesson. The signature
# is the empty statusCheckRollup paired with `mergeStateStatus":"BLOCKED"`
# and zero workflow runs over many minutes.
cat > "$FIX_DIR/actions_silent.log" <<'LOG'
gh pr view 7 --json statusCheckRollup,mergeStateStatus
{"statusCheckRollup":[],"mergeStateStatus":"BLOCKED"}
gh run list --branch feat/0006-auto-pause-on-sendbacks
no runs found
LOG

# supabase_port_bind — courtiq 2026-05-25 lesson, ticket 0029.
cat > "$FIX_DIR/supabase_port_bind.log" <<'LOG'
Run npx supabase start
failed to bind host port for 0.0.0.0:54322: address already in use
LOG

# account_suspended — courtiq PR #314.
cat > "$FIX_DIR/account_suspended.log" <<'LOG'
Run actions/checkout@v4
Error: Your account is suspended
exit code 403
LOG

# gh_graphql_502 — courtiq 2026-05-21 lesson, ticket 0012.
cat > "$FIX_DIR/gh_graphql_502.log" <<'LOG'
gh pr checks --watch
GraphQL: Something went wrong while executing your query (HTTP 502)
LOG

# Negative fixture — a real shellcheck failure. Must NOT match.
cat > "$FIX_DIR/shellcheck_real.log" <<'LOG'
In lib/common.sh line 42:
  if [ $foo = bar ]; then
       ^-- SC2086: Double quote to prevent globbing and word splitting.
LOG

# --- helper: source common.sh in a subshell and call fleet_match_infra_flake.
match() {
  local logfile="$1"
  (
    set -u
    # shellcheck disable=SC1091
    source "$REPO_ROOT/lib/common.sh"
    fleet_load_manifest "$MANIFEST_DIR"
    fleet_match_infra_flake "$logfile"
  )
}

# ========================================================================
# AC#1 + AC#3 — four positive matches, one negative.
# ========================================================================
expect_token() {
  local label="$1" logfile="$2" want="$3"
  local got
  got="$(match "$logfile" || true)"
  if [ "$got" != "$want" ]; then
    echo "FAIL: $label expected '$want', got '$got'"
    exit 1
  fi
  echo "ok: $label → $want"
}

expect_token "actions_silent"     "$FIX_DIR/actions_silent.log"     "actions_silent"
expect_token "supabase_port_bind" "$FIX_DIR/supabase_port_bind.log" "supabase_port_bind"
expect_token "account_suspended"  "$FIX_DIR/account_suspended.log"  "account_suspended"
expect_token "gh_graphql_502"     "$FIX_DIR/gh_graphql_502.log"     "gh_graphql_502"
expect_token "shellcheck_real (negative)" "$FIX_DIR/shellcheck_real.log" ""

# ========================================================================
# AC#2 — lib/heal-catalog.sh ships the four patterns AND each has an inline
# comment naming the LESSONS entry (date + repo) it codifies.
# ========================================================================
CATALOG="$REPO_ROOT/lib/heal-catalog.sh"
if [ ! -f "$CATALOG" ]; then
  echo "FAIL: AC#2 missing lib/heal-catalog.sh"
  exit 1
fi
for tok in actions_silent supabase_port_bind account_suspended gh_graphql_502; do
  if ! grep -q "$tok" "$CATALOG"; then
    echo "FAIL: AC#2 catalog missing pattern '$tok'"
    exit 1
  fi
done
# Each pattern's source lesson is named — match a date (YYYY-MM-DD) and a
# repo name (agent-fleet | courtiq) near each token. We grep the catalog
# for the 4 lesson references rather than per-token windows so the check
# is robust to comment placement.
for ref in 'agent-fleet 2026-05-26' 'courtiq 2026-05-25' 'courtiq PR #314' 'courtiq 2026-05-21'; do
  if ! grep -F -q "$ref" "$CATALOG"; then
    echo "FAIL: AC#2 catalog missing LESSON reference: $ref"
    exit 1
  fi
done
echo "ok: AC#2 catalog ships four patterns with lesson refs"

# Also assert FLEET_HEAL_CATALOG override works — point it at a stub
# catalog with one fake pattern and confirm fleet_match_infra_flake picks
# that up instead of the kit's default. This proves tests can swap the
# catalog without monkey-patching common.sh.
STUB_CATALOG="$TMP/stub-catalog.sh"
cat > "$STUB_CATALOG" <<'STUB'
# Stub catalog for AC#2 override test.
FLEET_HEAL_PATTERNS=(
  "synthetic_flake|FLEETTESTONLY_synthetic_flake_marker"
)
STUB
cat > "$FIX_DIR/synthetic.log" <<'LOG'
something happened: FLEETTESTONLY_synthetic_flake_marker
LOG
got="$(
  set -u
  export FLEET_HEAL_CATALOG="$STUB_CATALOG"
  # shellcheck disable=SC1091
  source "$REPO_ROOT/lib/common.sh"
  fleet_load_manifest "$MANIFEST_DIR"
  fleet_match_infra_flake "$FIX_DIR/synthetic.log"
)"
if [ "$got" != "synthetic_flake" ]; then
  echo "FAIL: AC#2 FLEET_HEAL_CATALOG override did not load stub (got '$got')"
  exit 1
fi
echo "ok: AC#2 FLEET_HEAL_CATALOG override loads a stub catalog"

# ========================================================================
# AC#4 — prompts/ship.prompt.md PHASE 1 RED branch references the catalog
# and the rerun command.
# ========================================================================
PROMPT="$REPO_ROOT/prompts/ship.prompt.md"
if ! grep -q 'fleet_match_infra_flake' "$PROMPT"; then
  echo "FAIL: AC#4 prompts/ship.prompt.md must mention fleet_match_infra_flake"
  exit 1
fi
if ! grep -qE 'gh run rerun.* --failed|gh run rerun .*--failed' "$PROMPT"; then
  echo "FAIL: AC#4 prompts/ship.prompt.md must mention 'gh run rerun ... --failed'"
  exit 1
fi
if ! grep -q 'infra_flake_rerun' "$PROMPT"; then
  echo "FAIL: AC#4 prompts/ship.prompt.md must reference the infra_flake_rerun event"
  exit 1
fi
echo "ok: AC#4 ship prompt wires up the catalog + rerun + event emission"

# ========================================================================
# AC#5 — dedupe via events.jsonl. We expose a helper
# `fleet_infra_flake_already_rerun <token> <run_id> [window_seconds]` that
# returns 0 when a prior infra_flake_rerun for the same token+run_id is
# present within the window, 1 otherwise. The ship prompt's pre-step
# calls it before invoking `gh run rerun`.
# ========================================================================
already_rerun() {
  local token="$1" run_id="$2"
  (
    set -u
    # shellcheck disable=SC1091
    source "$REPO_ROOT/lib/common.sh"
    fleet_load_manifest "$MANIFEST_DIR"
    fleet_infra_flake_already_rerun "$token" "$run_id"
  )
}

# No events file → never been rerun.
rm -rf "$CACHE_DIR"
mkdir -p "$CACHE_DIR"
if already_rerun supabase_port_bind 999; then
  echo "FAIL: AC#5 dedupe must NOT trip on an empty events.jsonl"
  exit 1
fi
echo "ok: AC#5 empty events.jsonl → not deduped"

# Seed events.jsonl with an infra_flake_rerun from "now" — dedupe must trip.
now_iso="$(date -u +%FT%TZ)"
cat > "$EVENTS_FILE" <<EVT
{"ts":"$now_iso","slug":"healflaketest","phase":"ship","type":"infra_flake_rerun","pattern":"supabase_port_bind","run_id":"42","pr":"7"}
EVT
if ! already_rerun supabase_port_bind 42; then
  echo "FAIL: AC#5 dedupe must trip on a recent matching event"
  cat "$EVENTS_FILE"
  exit 1
fi
echo "ok: AC#5 recent matching event → deduped"

# A different run_id with the same token does NOT dedupe.
if already_rerun supabase_port_bind 43; then
  echo "FAIL: AC#5 same token but different run_id must NOT dedupe"
  exit 1
fi
echo "ok: AC#5 different run_id → not deduped"

# An event older than the 2h window does NOT dedupe.
old_iso="$(date -u -v-3H +%FT%TZ 2>/dev/null || date -u -d '-3 hours' +%FT%TZ)"
cat > "$EVENTS_FILE" <<EVT
{"ts":"$old_iso","slug":"healflaketest","phase":"ship","type":"infra_flake_rerun","pattern":"supabase_port_bind","run_id":"42","pr":"7"}
EVT
if already_rerun supabase_port_bind 42; then
  echo "FAIL: AC#5 events older than the window must NOT dedupe"
  exit 1
fi
echo "ok: AC#5 stale (>2h) event → not deduped"

# ========================================================================
# AC#6 — AGENTS.md § Telemetry has an infra_flake_rerun event-type bullet.
# ========================================================================
AGENTS="$REPO_ROOT/AGENTS.md"
if ! grep -q 'infra_flake_rerun' "$AGENTS"; then
  echo "FAIL: AC#6 AGENTS.md must document the infra_flake_rerun event type"
  exit 1
fi
echo "ok: AC#6 AGENTS.md documents infra_flake_rerun"

# ========================================================================
# AC#8 — public API unchanged. Each documented public name must still
# resolve as a function after sourcing common.sh.
# ========================================================================
api_check="$(
  set -u
  # shellcheck disable=SC1091
  source "$REPO_ROOT/lib/common.sh" >/dev/null 2>&1
  for fn in fleet_load_manifest fleet_self_cancel fleet_log_init fleet_checkout fleet_run_claude fleet_emit_event fleet_match_infra_flake fleet_infra_flake_already_rerun; do
    type -t "$fn" >/dev/null 2>&1 || { echo "missing:$fn"; exit 1; }
  done
  echo ok
)"
if [ "$api_check" != "ok" ]; then
  echo "FAIL: AC#8 public API check: $api_check"
  exit 1
fi
echo "ok: AC#8 public API surface preserved + additive only"

echo
echo "all heal-infra-flake.sh assertions passed."
