#!/bin/bash
# Positive fixture for dispatcher-forward-reference (LESSONS 2026-06-05).
# replay() calls helper_late() defined LATER in the file; the inline
# dispatcher fires before bash parses helper_late.
set -euo pipefail

replay() {
  helper_late "hello"
  exit 0
}

CMD="${1:-replay}"
if [ "$CMD" = "replay" ]; then
  replay "$@"
fi

helper_late() {
  echo "late: $1"
}
