#!/bin/bash
# Positive fixture for export-in-command-substitution (LESSONS 2026-06-05).
# `export FOO_EMITTED=1` inside $(...) never leaks to the parent shell.
set -euo pipefail

VERDICT="$(
  echo "suppress"
  export FLEET_QUIET_HOURS_EMITTED=1
)"
echo "$VERDICT"
echo "guard=${FLEET_QUIET_HOURS_EMITTED:-unset}"
