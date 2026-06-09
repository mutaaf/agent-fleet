#!/bin/bash
# Negative fixture for bash-32-lc_all-string-length (LESSONS 2026-06-05).
# Width via `wc -c` + awk under explicit LC_ALL=C — byte-mode regardless
# of the caller's locale.
set -euo pipefail

visible_width() {
  local s="$1" total cont
  total="$(printf -- '%s' "$s" | LC_ALL=C wc -c | tr -d ' ')"
  cont="$(printf -- '%s' "$s" | LC_ALL=C awk '
    BEGIN { for (k=0; k<256; k++) ord[sprintf("%c", k)] = k; n = 0 }
    { for (i=1; i<=length($0); i++) { v = ord[substr($0, i, 1)]; if (v >= 128 && v < 192) n++ } }
    END { print n+0 }
  ')"
  printf '%d' "$(( total - cont ))"
}

visible_width "$@"
