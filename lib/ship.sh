#!/bin/bash
# agent-fleet/lib/ship.sh — generic autonomous "ship" runner.
#
# Usage (from launchd): bash ship.sh /abs/path/to/config-dir
#
# Heals the in-flight PR first; only if there's nothing to heal, ships the top
# ticket. Heal OR ship, never both in one run. All project specifics are read by
# the agent at runtime from AGENTS.md (§ Agent parameters) in the fresh checkout.

source "$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )/common.sh"

fleet_load_manifest "${1:-}"
fleet_log_init ship
fleet_emit_event run_started "pid=$$" || true
fleet_self_cancel || exit 0
fleet_check_budget || exit 0

# Ticket 0033 — operator-declared local-time quiet hours. The helper emits
# one `quiet_hours_skip` event on the first suppress per process (guarded
# by FLEET_QUIET_HOURS_EMITTED) and writes its verdict to the exported
# global FLEET_QUIET_HOURS_VERDICT. We call it WITHOUT `$(…)` so the side
# effects (emit + guard) land in this shell rather than a discarded
# subshell. Outside the window (or for `review`, which is exempt) the
# verdict is "ok"; invalid QUIET_HOURS warns once to stderr and the
# verdict is "invalid" (the runner treats that like "ok" and proceeds).
# Lands BEFORE fleet_acquire_lock + fleet_checkout so the suppress path
# never touches gh/git/launchctl.
fleet_check_quiet_hours >/dev/null
if [ "${FLEET_QUIET_HOURS_VERDICT:-ok}" = "suppress" ]; then
  FLEET_QUIET_END_HHMM="${QUIET_HOURS#*-}"
  echo "quiet hours active ($QUIET_HOURS local) — $FLEET_PHASE no-op until $FLEET_QUIET_END_HHMM"
  exit 0
fi

fleet_check_prompts_sha || true
fleet_acquire_lock ship || exit 0
trap 'fleet_release_lock ship' EXIT
fleet_checkout checkout

# Ticket 0006 — auto-pause PHASE 2 (shipping a new ticket) if the last 24h
# show 3+ unresolved REQUEST_CHANGES on agent-branch PRs. On trip the gate
# (a) emits a `ship_paused` event, (b) opens/updates a meta-issue, and
# (c) runs `launchctl disable` so this label stops firing until the operator
# explicitly re-enables it. PHASE 1 (heal the in-flight PR) is NOT disabled
# — we still hand off to claude so an in-flight PR can heal, but the prompt
# reads $FLEET_SHIP_PAUSED and refuses to pick up a new ticket.
#
# Returns non-zero ONLY on trip; we deliberately do NOT `|| exit 0` here.
fleet_check_sendback_streak || true

fleet_run_claude ship < "$FLEET_PROMPTS/ship.prompt.md"
EXIT=$?

# Ticket 0044 — per-merge ROI footer hook. The dev agent runs `gh pr
# create` and `gh pr merge --auto --squash` inside the ship prompt; we
# fire `bin/fleet pr-footer <pr>` here, after fleet_run_claude returns,
# for the most-recent `pr_opened` event in this slug's events.jsonl.
# `pr-footer` itself refuses non-merged PRs (exit 2), so a ship run
# that only opens a PR (auto-merge still pending CI) is a silent
# no-op on this hook — the operator can re-fire it post-hoc, or the
# next ship run will catch it once the PR merges.
#
# PR_FOOTER_ENABLED is a manifest knob defaulting to 1 (the v1
# acquisition bet — see ticket 0044's growth lens). Set
# PR_FOOTER_ENABLED=0 in agents.config.sh to opt out.
#
# Per LESSONS 2026-05-26 (actions silent flake) a footer-post failure
# is NOT a heal trigger — the merge has already happened (or not).
# Per LESSONS 2026-05-28 every `printf` of a user-derived string
# uses `printf --`. The background fork via `&` means the merge
# path doesn't wait on the gh REST roundtrip.
if [ "${PR_FOOTER_ENABLED:-1}" = "1" ] && [ "$EXIT" = "0" ]; then
  PR_FOOTER_PR=""
  if [ -f "$CACHE_DIR/events.jsonl" ]; then
    PR_FOOTER_PR="$(awk '
      function jv(line, key,    re, val) {
        re = "\"" key "\"[[:space:]]*:[[:space:]]*\"[^\"]*\""
        if (match(line, re)) {
          val = substr(line, RSTART, RLENGTH)
          sub(/.*:[[:space:]]*"/, "", val); sub(/".*/, "", val)
          return val
        }
        return ""
      }
      { if (jv($0, "type") == "pr_opened") last = jv($0, "number") }
      END { if (last != "") print last }
    ' "$CACHE_DIR/events.jsonl")"
  fi
  if [ -n "$PR_FOOTER_PR" ]; then
    FLEET_BIN_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/../bin" 2>/dev/null && pwd )"
    if [ -x "$FLEET_BIN_DIR/fleet" ]; then
      ( "$FLEET_BIN_DIR/fleet" pr-footer "$PR_FOOTER_PR" \
          >> "$FLEET_LOG" 2>&1 || true ) &
    fi
  fi
fi

echo
echo "=== ${SLUG}-ship complete $(date -u) — exit=$EXIT ==="
# Ticket 0010: in dry-run mode, fleet_run_claude already emitted run_dry_run
# (carrying the plan_head). run_completed is REPLACED, not paired — so skip
# the usual emission when FLEET_DRY_RUN_EMITTED is set.
if [ -z "${FLEET_DRY_RUN_EMITTED:-}" ]; then
  fleet_emit_event run_completed "exit=$EXIT" "duration_ms=$(( ( $(date -u +%s) - RUN_STARTED_EPOCH ) * 1000 ))" || true
fi
exit $EXIT
