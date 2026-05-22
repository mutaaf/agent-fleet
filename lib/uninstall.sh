#!/bin/bash
# agent-fleet/lib/uninstall.sh — remove one project's fleet agents from launchd.
#
# Usage: bash uninstall.sh /abs/path/to/project   (the dir holding agents.config.sh)
#
# Unloads the jobs and removes the plists. Keeps logs and the TCC-safe manifest
# copy for reference (rm -rf ~/.cache/<slug>-agent to wipe logs too).

set -euo pipefail

PROJECT_DIR="$( cd "${1:?usage: uninstall.sh /abs/path/to/project}" && pwd )"
# shellcheck disable=SC1090
source "$PROJECT_DIR/agents.config.sh"
: "${SLUG:?manifest missing SLUG}"
NAMESPACE="${NAMESPACE:-com.fleet.$SLUG}"

DOMAIN="gui/$UID"
AGENTS_DIR="$HOME/Library/LaunchAgents"

for SUFFIX in agent-ship agent-groom agent-review agent-eng; do
  LABEL="$NAMESPACE.$SUFFIX"
  launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true
  rm -f "$AGENTS_DIR/$LABEL.plist"
  echo "removed $LABEL"
done

echo
echo "✓ uninstalled $SLUG. Logs at ~/.cache/${SLUG}-agent/logs/ are kept."
