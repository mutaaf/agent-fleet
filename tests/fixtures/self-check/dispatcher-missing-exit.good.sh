#!/bin/bash
# Negative fixture for dispatcher-missing-exit (LESSONS 2026-06-01).
# Subcommand function ends with an explicit `exit 0`.
set -euo pipefail

badge() {
  local format="${1:-md}"
  case "$format" in
    md) echo "[![fleet](svg)](url)" ;;
    txt) echo "fleet badge" ;;
  esac
  exit 0
}

CMD="${1:-badge}"
if [ "$CMD" = "badge" ]; then
  badge "$@"
fi
