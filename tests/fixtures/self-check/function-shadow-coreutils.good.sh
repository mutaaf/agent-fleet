#!/bin/bash
# Negative fixture for function-shadow-coreutils (LESSONS 2026-05-26).
# Namespaced as `tail_cmd()` to bypass the coreutils shadow.
set -euo pipefail

tail_cmd() {
  echo "fleet tail dispatcher: $*"
}

tail -F /tmp/events.jsonl
tail_cmd "$@"
