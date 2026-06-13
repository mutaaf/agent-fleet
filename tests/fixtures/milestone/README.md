# tests/fixtures/milestone/

Canonical synthetic `events.jsonl` files for the four `tests/milestone.sh`
scenarios (ticket 0049). The test seeds these in-place under
`$HOME/.cache/<slug>-agent/` via the local `seed_*` helpers — see
`tests/milestone.sh` for the per-AC fixture definitions.

Scenarios covered:

1. `af-cross-10` — clean 10-day streak ending today (just crossed the
   default 10d threshold; yesterday it was 9d, below the threshold).
2. `cq-new-23` — clean 23-day streak ending today, preceded by an
   18-day prior longest. Both `THRESHOLD_CROSSED` (10d crossed earlier)
   and `NEW LONGEST STREAK 23d > 18d` apply.
3. `dc-break-14` — 14 green days then a `ship_paused` break TODAY.
   Includes a `lesson_draft_emitted` on the break day for the
   recovery line to surface.
4. `q-none` — no qualifying events (empty `events.jsonl`).

The fixtures are reseeded from inline shell on every test run so they
stay byte-exact deterministic across hosts. This README is the
fixture-directory anchor (per the `tests/fixtures/streak/README.md`
convention) — adding it lets the AC#16 "fixture directory present"
check stay green even when the per-test reseed is fast enough that no
file persists between runs.
