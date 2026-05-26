---
id: 0004
title: Per-slug daily $ budget caps
status: shipped
priority: P1
area: governance
created: 2026-05-26
owner: gtm-innovation
---

## User story

As a fleet operator, I want each project to soft-abort its runners once it
hits a daily $ ceiling I set in `agents.config.sh`, so that a runaway loop
can't burn an unbounded amount before I notice.

## Why now (four lenses)

### Product Owner
The simplest unit of cost safety — one number per project, enforced before
the runner spawns `claude`. No surprise bills.

### Stakeholder
Widens the moat on `governance`. Costs are bounded by design. Pairs with
fleet-control's forecast (FC#5): the portal can show "remaining today" per
project.

### Operator
"It can't run away" is a property the operator wants to be sure of, not check
for. The cap is in the manifest, visible at install time.

### Growth
"Budget caps per project, declared in one variable" is a shareable property
for anyone running autonomous agents on their own dime.

## Acceptance criteria

- [ ] `agents.config.sh` gains an optional `MAX_DAILY_USD` variable. Default
      is unset (no cap, current behavior).
- [ ] `common.sh` exposes `fleet_check_budget` which:
      - returns 0 (proceed) if `MAX_DAILY_USD` is unset.
      - reads today's `total_cost_usd` for this slug from `runs.jsonl`
        (the structured record `fleet_run_claude` already writes) AND any
        manual entries (sum all ts_start dates matching today UTC).
      - returns 0 if `sum < MAX_DAILY_USD`.
      - returns 1 if `sum >= MAX_DAILY_USD` and emits
        `fleet_emit_event budget_block reason=daily_cap spent=$sum cap=$cap`
        (requires ticket 0002 to be shipped first).
- [ ] `ship.sh`, `groom.sh`, `review.sh`, `eng.sh` call
      `fleet_check_budget || exit 0` immediately after `fleet_self_cancel`.
- [ ] The summed value tolerates a missing `total_cost_usd` field (treats it
      as 0) and a missing `runs.jsonl` (treats it as 0).
- [ ] `tests/budget.sh` seeds a `runs.jsonl` summing to $4.50, sets
      `MAX_DAILY_USD=5`, asserts `fleet_check_budget` returns 0; then bumps
      the sum to $5.10 and asserts it returns 1.
- [ ] `manifest.example.sh` documents the new variable inline.
- [ ] `AGENTS.md` Telemetry section gains the `budget_block` event row.

## Out of scope

- Weekly / monthly caps. Daily only in v1.
- Pre-spawn token estimation. Reactive only: we know cost after a run ends.
- Hard kills mid-run. Soft-abort at the start of the next run is enough.

## Engineering notes

- `lib/common.sh` — `fleet_check_budget` near `fleet_self_cancel`. Use
  `jq` if available, fall back to a portable `awk` sum.
- `manifest.example.sh` — add the variable in the `--- spend bound ---`
  section with a comment.
- `tests/budget.sh` — fixture under `mktemp -d`, seed `runs.jsonl`.
- Blocked-by: 0002 (events channel).
- Reinstall: all projects.
- Public API: additive.

## Implementation log

- 2026-05-26 — implementation-dev: started. Branch `feat/0004-budget-caps`.
  Interpretation: `fleet_check_budget` reads today's UTC `total_cost_usd` from
  `$CACHE_DIR/runs.jsonl` filtered by `ts_start` prefix matching today's date,
  and by this slug (defensive — the file is per-slug already, but a stray
  entry from a different SLUG should not pollute the cap). Sum is computed
  via `jq` if available, otherwise a portable `awk` regex fallback. Cap
  comparison is float-safe via `awk`. Emits `budget_block` event when
  blocking.
- 2026-05-26 — implementation-dev: shipped via PR #4. CI gates
  (`shellcheck`, `validate`) green; auto-merged to main.
