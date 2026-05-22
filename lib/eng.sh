#!/bin/bash
# agent-fleet/lib/eng.sh — generic autonomous "engineering" runner (optional queue).
#
# Usage (from launchd): bash eng.sh /abs/path/to/config-dir
#
# Peer of ship.sh, but consumes the ENGINEERING backlog (code quality, types,
# performance, test infra, dep hygiene) instead of the feature backlog. Its PRs
# use the eng/ branch prefix and an independent single-PR gate, so an open eng/
# PR never blocks the feature ship loop (and vice versa). Both go to one reviewer.
#
# Only installed when ENG_ENABLED=1 in the manifest.

source "$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )/common.sh"

fleet_load_manifest "${1:-}"
fleet_log_init eng
fleet_self_cancel || exit 0
fleet_checkout eng-checkout

claude --print --dangerously-skip-permissions --model "$MODEL" < "$FLEET_PROMPTS/eng.prompt.md"
EXIT=$?

echo
echo "=== ${SLUG}-eng complete $(date -u) — exit=$EXIT ==="
exit $EXIT
