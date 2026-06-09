#!/bin/bash
# Negative fixture for export-in-command-substitution (LESSONS 2026-06-05).
# Helper writes verdict to stdout (consumed without $(...)) and exports
# the at-most-once guard from the runner's own shell — outside any
# command substitution.
set -euo pipefail

fleet_check_quiet_hours() {
  echo "suppress"
  FLEET_QUIET_HOURS_EMITTED=1
  export FLEET_QUIET_HOURS_EMITTED
}

fleet_check_quiet_hours >/dev/null
echo "guard=${FLEET_QUIET_HOURS_EMITTED:-unset}"
