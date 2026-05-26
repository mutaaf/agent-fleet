#!/bin/bash
# agent-fleet/lib/groom.sh — generic autonomous "groom" runner.
#
# Usage (from launchd): bash groom.sh /abs/path/to/config-dir
#
# Closes superseded backlog PRs, self-gates when the backlog is full, otherwise
# regrooms + adds 2-4 fresh tickets focused on acquisition / retention / moat.
# The gtm-innovation subagent (per project) does the thinking; this is the launcher.

source "$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )/common.sh"

fleet_load_manifest "${1:-}"
fleet_log_init groom
fleet_emit_event run_started "pid=$$" || true
fleet_self_cancel || exit 0
fleet_check_budget || exit 0
fleet_check_prompts_sha || true
fleet_acquire_lock groom || exit 0
trap 'fleet_release_lock groom' EXIT
fleet_checkout checkout

# Adaptive cadence (ticket 0007): when the backlog is empty AND we have
# fewer than 3 groomed P0/P1 tickets, throttle the spawn behind a 12h
# floor. The gate writes $CACHE_DIR/groom-slowed-since + emits a
# `groom_throttled` event; the caller short-circuits without spawning.
fleet_check_groom_cadence || {
  fleet_emit_event run_completed "exit=0" "duration_ms=$(( ( $(date -u +%s) - RUN_STARTED_EPOCH ) * 1000 ))" "throttled=1" || true
  exit 0
}

fleet_run_claude groom < "$FLEET_PROMPTS/groom.prompt.md"
EXIT=$?

echo
echo "=== ${SLUG}-groom complete $(date -u) — exit=$EXIT ==="
# Ticket 0010: dry-run already emitted run_dry_run; skip the run_completed pair.
if [ -z "${FLEET_DRY_RUN_EMITTED:-}" ]; then
  fleet_emit_event run_completed "exit=$EXIT" "duration_ms=$(( ( $(date -u +%s) - RUN_STARTED_EPOCH ) * 1000 ))" || true
fi
exit $EXIT
