#!/bin/bash
# Positive fixture for cat-roundtrip (LESSONS 2026-05-27).
# `$(cat file)` strips trailing newlines and the restore later writes
# the captured value back via printf.
set -euo pipefail

BACKUP="$(cat "$1")"
printf '%s' "$BACKUP" > "$1"
