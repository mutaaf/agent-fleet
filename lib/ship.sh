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
fleet_self_cancel || exit 0
fleet_acquire_lock ship || exit 0
trap 'fleet_release_lock ship' EXIT
fleet_checkout checkout

fleet_run_claude ship < "$FLEET_PROMPTS/ship.prompt.md"
EXIT=$?

echo
echo "=== ${SLUG}-ship complete $(date -u) — exit=$EXIT ==="
exit $EXIT
