#!/bin/bash
# Negative fixture for json-escape-sign-extension (LESSONS 2026-06-03).
# Named `*_json_escape` helper guarded on `code -ge 0` to skip the
# sign-extended UTF-8 high bytes.
set -euo pipefail

provenance_json_escape() {
  local s="${1-}" out="" i ch code
  for (( i=0; i<${#s}; i++ )); do
    ch="${s:i:1}"
    case "$ch" in
      '\\') out+='\\\\' ;;
      *) printf -v code '%d' "'$ch"
         if [ "$code" -ge 0 ] && [ "$code" -lt 32 ]; then
           printf -v out '%s\\u%04x' "$out" "$code"
         else
           out+="$ch"
         fi ;;
    esac
  done
  printf '%s' "$out"
}
provenance_json_escape "$@"
