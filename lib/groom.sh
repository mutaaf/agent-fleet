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
fleet_self_cancel || exit 0
fleet_checkout checkout

claude --print --dangerously-skip-permissions --model "$MODEL" < "$FLEET_PROMPTS/groom.prompt.md"
EXIT=$?

echo
echo "=== ${SLUG}-groom complete $(date -u) — exit=$EXIT ==="
exit $EXIT
