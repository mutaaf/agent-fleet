#!/bin/bash
# Positive fixture for printf-leading-dash (LESSONS 2026-05-28).
# Format string begins with `-` and `--` does not precede.
set -euo pipefail

pr_number="42"
printf '- number: #%s\n' "$pr_number"
