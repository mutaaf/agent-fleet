#!/bin/bash
# Negative fixture for awk-v-multiline (LESSONS 2026-06-01).
# Multi-line value goes through a tmp file via getline.
set -euo pipefail

body_file=/tmp/multi-line-body.txt
awk 'BEGIN { while ((getline line < "/tmp/multi-line-body.txt") > 0) print line }'
echo "$body_file"
