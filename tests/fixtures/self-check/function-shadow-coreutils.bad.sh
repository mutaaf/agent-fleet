#!/bin/bash
# Positive fixture for function-shadow-coreutils (LESSONS 2026-05-26).
# Defining `tail()` shadows /usr/bin/tail; internal `tail -F` recurses.
set -euo pipefail

tail() {
  echo "fleet tail dispatcher: $*"
}

# Same file also shells out to the binary -> infinite recursion.
tail -F /tmp/events.jsonl
