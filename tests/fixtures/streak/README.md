# tests/fixtures/streak/

Synthetic `events.jsonl` files referenced by `tests/streak.sh`. Most
scenarios are generated inline by the test (it composes per-day
events from helpers), so this dir mostly holds documentation and any
golden snapshot we add later.

Scenarios exercised by `tests/streak.sh`:

- 30-day clean streak — tests longest computation over the default window.
- Single-day break in the middle of the window — collapses runs around
  it.
- `ship_paused` break — broken_by column cites the `ship_paused` event.
- `budget_block` break — same shape with a different event type.
- `gate_failed`-but-resolved — same-day `run_completed exit=0` keeps the
  streak alive.
- `gate_failed`-and-unresolved — breaks the streak; broken_by cites
  `gate_failed`.
- Neutral day (no ship events) — does not extend, does not break.
- Month-boundary streak (2026-05-30 → 2026-06-03) — exercises BSD
  `date -u -j -v` day arithmetic across month boundaries.

All events use the JSONL schema defined in `AGENTS.md § Telemetry` —
`ts`, `slug`, `phase`, `type` plus per-type fields. No new event
types are introduced.
