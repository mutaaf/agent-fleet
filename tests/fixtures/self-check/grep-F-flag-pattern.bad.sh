#!/bin/bash
# Positive fixture for grep-F-flag-pattern (LESSONS 2026-05-30).
# `grep -qF "--since"` parses --since as a grep option.
set -euo pipefail

grep -qF "--since" /etc/hosts
