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

echo
echo "=== ${SLUG}-ship complete $(date -u) — exit=$EXIT ==="
# Ticket 0010: in dry-run mode, fleet_run_claude already emitted run_dry_run
# (carrying the plan_head). run_completed is REPLACED, not paired — so skip
# the usual emission when FLEET_DRY_RUN_EMITTED is set.
if [ -z "${FLEET_DRY_RUN_EMITTED:-}" ]; then
  fleet_emit_event run_completed "exit=$EXIT" "duration_ms=$(( ( $(date -u +%s) - RUN_STARTED_EPOCH ) * 1000 ))" || true
fi
exit $EXIT
