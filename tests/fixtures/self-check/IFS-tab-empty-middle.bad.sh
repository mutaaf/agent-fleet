#!/bin/bash
# Positive fixture for IFS-tab-empty-middle (LESSONS 2026-06-08).
# 4+ fields read from a TSV stream with no `-` sentinel remap — when a
# middle column is empty bash collapses two adjacent tabs into one and
# the headline shifts left.
set -euo pipefail

awk '{ printf "%s\t%s\t%s\t%s\n", "a", "", "c", "d" }' /tmp/in.tsv \
| while IFS=$'\t' read -r head end orig expires headline; do
    echo "$head|$end|$orig|$expires|$headline"
  done
