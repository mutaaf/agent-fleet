# LESSONS

Operational memory for agent-fleet test fixture.

## 2026-05-25 — bootstrap entry without expiry marker

This paragraph has no `<!-- EXPIRES: -->` marker. It MUST never be
listed by `lessons-prune` regardless of the frozen clock — silent
paragraphs are append-only, never pruned.

## 2026-05-27 — $(cat file) strips trailing newlines
<!-- EXPIRES: 2026-06-30 -->

Bash command substitution strips ALL trailing newlines from captured
output. Fix: back up with `cp` and restore with `cp` — byte-exact.
Marked EXPIRES=tomorrow-ish (2026-06-30 is well beyond the frozen
clock 2026-06-07) — MUST NOT be pruned today.

## 2026-05-28 — printf '- foo' treats the leading dash as a flag
<!-- EXPIRES: someday -->

Bash builtin printf parses the first argument as flags, so a format
string starting with `-` fails. Fix: prefix with `--` end-of-options
marker. EXPIRES value is malformed (not YYYY-MM-DD); MUST warn to
stderr but MUST NOT prune and MUST NOT exit nonzero.
