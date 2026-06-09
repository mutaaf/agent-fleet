#!/bin/bash
# Negative fixture for IFS-tab-empty-middle (LESSONS 2026-06-08).
# 4+ fields read from a TSV stream with a `-` sentinel remapped to ""
# in the consumer.
set -euo pipefail

awk '{ printf "%s\t%s\t%s\t%s\n", "a", "-", "c", "d" }' /tmp/in.tsv \
| while IFS=$'\t' read -r head end orig expires headline; do
    [ "$expires" = "-" ] && expires=""
    echo "$head|$end|$orig|$expires|$headline"
  done
