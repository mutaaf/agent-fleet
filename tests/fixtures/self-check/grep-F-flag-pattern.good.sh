#!/bin/bash
# Negative fixture for grep-F-flag-pattern (LESSONS 2026-05-30).
# `grep -qF --` end-of-options marker defuses the trap.
set -euo pipefail

grep -qF -- "--since" /etc/hosts
