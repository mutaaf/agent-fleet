#!/bin/bash
# Negative fixture for dispatcher-forward-reference (LESSONS 2026-06-05).
# helper_early is defined ABOVE replay so the dispatcher can resolve it.
set -euo pipefail

helper_early() {
  echo "early: $1"
}

replay() {
  helper_early "hello"
  exit 0
}

CMD="${1:-replay}"
if [ "$CMD" = "replay" ]; then
  replay "$@"
fi
