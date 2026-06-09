#!/bin/bash
# Negative fixture for printf-leading-dash (LESSONS 2026-05-28).
# `printf --` end-of-options marker defuses the leading-dash trap.
set -euo pipefail

pr_number="42"
printf -- '- number: #%s\n' "$pr_number"
