# LESSONS — ARCHIVE

This file is the retirement target for `docs/LESSONS.md` paragraphs
whose `<!-- EXPIRES: YYYY-MM-DD -->` marker has come due and were
moved here by `bin/fleet lessons-prune --commit`. Pruning is
operator-invoked, append-only, and never deletes a lesson — the move
is the contract.

PHASE 0 readers DO NOT read this file. Only `docs/LESSONS.md` is on
the hot read path. See `AGENTS.md § Lessons` and ticket 0039.

## archived 2026-06-07 — originally 2026-05-26

## 2026-05-26 — bash scripts launched with & cannot be SIGINT-tested
<!-- EXPIRES: 2026-06-07 -->

POSIX says a signal set to be ignored on entry to a process shall
remain ignored. When the test harness launches `./script.sh &`, bash
inherits SIGINT as SIG_IGN. Workaround: in tests, use `kill -TERM`
which is honoured. Marked EXPIRES=today (relative to the test's
frozen clock 2026-06-07) so the prune walker MUST flag it.

## archived 2026-06-07 — originally 2026-06-03

## 2026-06-03 — doctor_json_escape sign-extends multi-byte UTF-8
<!-- EXPIRES: 2024-01-01 -->

Under LC_ALL=C bash treats `${s:i:1}` as one BYTE not one character,
yielding negative ints for high bytes. Fix: guard on `code >= 0`
before treating it as a control char. EXPIRES long-past (2024-01-01
<= 2026-06-07) — MUST be pruned today.
