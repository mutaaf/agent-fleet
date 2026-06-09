#!/bin/bash
# Negative fixture for grep-c-double-print (LESSONS 2026-06-01).
# awk for counting always exits 0 and emits exactly one number.
set -euo pipefail

n=$(awk '/<!-- DRAFT: / { n++ } END { print (n+0) }' /tmp/lessons.md)
echo "$n"
