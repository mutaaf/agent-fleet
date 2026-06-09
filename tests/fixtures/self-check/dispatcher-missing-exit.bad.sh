#!/bin/bash
# Positive fixture for dispatcher-missing-exit (LESSONS 2026-06-01).
# Subcommand function body falls through without explicit `exit N`.
set -euo pipefail

badge() {
  local format="${1:-md}"
  case "$format" in
    md) echo "[![fleet](svg)](url)" ;;
    txt) echo "fleet badge" ;;
  esac
}

CMD="${1:-badge}"
if [ "$CMD" = "badge" ]; then
  badge "$@"
fi
