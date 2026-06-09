#!/bin/bash
# Positive fixture for awk-v-multiline (LESSONS 2026-06-01).
# Multi-line value captured via $(cat ...) is passed to awk -v.
set -euo pipefail

awk -v body="$(cat /tmp/multi-line-body.txt)" 'BEGIN { print body }'
