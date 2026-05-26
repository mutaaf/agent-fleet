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
fleet_emit_event run_started "pid=$$" || true
fleet_self_cancel || exit 0
fleet_acquire_lock eng || exit 0
trap 'fleet_release_lock eng' EXIT
fleet_checkout eng-checkout

fleet_run_claude eng < "$FLEET_PROMPTS/eng.prompt.md"
EXIT=$?

echo
echo "=== ${SLUG}-eng complete $(date -u) — exit=$EXIT ==="
fleet_emit_event run_completed "exit=$EXIT" "duration_ms=$(( ( $(date -u +%s) - RUN_STARTED_EPOCH ) * 1000 ))" || true
exit $EXIT
