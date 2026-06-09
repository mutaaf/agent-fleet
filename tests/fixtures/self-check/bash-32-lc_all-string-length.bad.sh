#!/bin/bash
# Positive fixture for bash-32-lc_all-string-length (LESSONS 2026-06-05).
# Function tries to flip LC_ALL=C and then uses `${#s}` / `${s:i:1}` —
# bash 3.2 has already cached the locale at startup so the dance fails.
set -euo pipefail

visible_width() {
  export LC_ALL=C
  local s="$1" i ch n=0
  for (( i=0; i<${#s}; i++ )); do
    ch="${s:i:1}"
    n=$(( n + 1 ))
  done
  echo "$n"
}

visible_width "$@"
