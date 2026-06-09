#!/bin/bash
# Negative fixture for cat-roundtrip (LESSONS 2026-05-27).
# `cp` is byte-exact and newline-preserving.
set -euo pipefail

cp "$1" "$1.bak"
cp "$1.bak" "$1"
