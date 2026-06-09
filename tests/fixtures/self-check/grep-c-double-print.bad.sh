#!/bin/bash
# Positive fixture for grep-c-double-print (LESSONS 2026-06-01).
# `grep -c | || echo 0` double-prints on zero matches.
set -euo pipefail

n=$(grep -cF -- "<!-- DRAFT: " /tmp/lessons.md || echo 0)
echo "$n"
