---
id: 0068
title: Warn before daily budget cap trips so the operator raises or waits on purpose
status: groomed
priority: P1
area: governance
created: 2026-07-01
owner: gtm-innovation
---

## User story

As a fleet operator whose 0004 `MAX_DAILY_USD` cap already soft-aborts a slug
when it trips — but silently and only AT the trip — I want the loop to warn
me BEFORE the cap trips, at current burn rate, so I raise it or wait on
purpose instead of discovering at 4pm that half the fleet stopped shipping
around lunch.

## Why now (four lenses)

### Product Owner
0004 emits `budget_block` only ON the trip, mirroring the pre-fix 0066 shape
of `SELF_CANCEL`. The operator's brief names "don't want surprise costs" as a
top-3 pain point. Today the loop can hit the cap at 12:37, no-op all afternoon,
and only the daily digest tomorrow surfaces the fact. The smallest meaningful
unit of value is a pre-cliff warning at burn-rate projection — the same shape
as 0066 for the OTHER dead-man's switch (SELF_CANCEL). Symmetric with 0066:
one event, one one-glance surface, one operator decision.

### Stakeholder
Budget caps are moat infrastructure (P-5). A cap that trips silently is a
one-hop-away outage the operator cannot pre-empt. Closing this pairs the
kit's two dead-man's switches with the SAME "pre-warn, don't ambush"
discipline — the second operator adopting the kit inherits both promises.
Per P-6, the pre-warn state IS the projection event; consumers read it.

### Operator (9am glance)
`fleet morning` already shows spend-so-far per slug. Without pre-warning, a
slug at 60% of cap at 9am looks identical to a slug at 60% that is coasting
— nothing tells the operator the FIRST one is projected to trip by 11am.
After this ticket, the morning shows
`⚠ courtiq projected to trip $12/day cap at 11:04 (currently $7.20, +$0.90/h)`
and the operator raises the cap OR stops the run before it wastes a
`heal:` cycle on a mid-run abort.

### Extensibility — earned by capability, NOT marketing
Pure capability. Any future consumer (fleet-control) that reads
`events.jsonl` gets one new typed event and one more question the operator
does not have to ask ("will this cap trip today?"). A second operator's
first cap-adoption becomes trustable instead of a source of anxiety.

## Acceptance criteria

- [ ] A new `fleet_check_budget_projection` helper in `lib/common.sh`
      computes the current UTC-day burn rate from `events.jsonl` cost fields
      and, when the projected end-of-day spend >= `MAX_DAILY_USD * BUDGET_WARN_PCT`
      (default 0.80) AND the projected trip time is within
      `BUDGET_WARN_LOOKAHEAD_HOURS` (default 6), emits a `budget_warning`
      event with fields `spent`, `cap`, `pct_projected`, `eta_iso` — at most
      once per project per UTC day (dedup marker under `$CACHE_DIR`).
- [ ] `fleet doctor` and `fleet morning`/`fleet inbox` render a
      `⚠ <slug> projected to trip $<cap>/day cap at <HH:MM> (currently
      $<spent>, +$<rate>/h)` line for every project currently inside the
      warning window. Test asserts the literal `⚠ ` marker via
      `grep -qF -- "$kw"` per LESSONS 2026-05-30.
- [ ] Regression: when today's spend is < `BUDGET_WARN_PCT * MAX_DAILY_USD`,
      no event fires and no warning renders. When today's spend has already
      TRIPPED (>= cap), only the existing 0004 `budget_block` event fires —
      no double-warn.
- [ ] `BUDGET_WARN_PCT` and `BUDGET_WARN_LOOKAHEAD_HOURS` default safely when
      absent from the manifest; invalid/empty values fall back to 0.80 / 6
      rather than erroring. Test asserts via a manifest with
      `BUDGET_WARN_PCT=` (empty) — helper returns cleanly with defaults.
- [ ] No break to `fleet_check_budget` public signature (additive helper
      only); `install.sh` remains idempotent (running twice produces
      byte-identical installed tree). Test asserts via
      `bash lib/install.sh $repo && sha=$(sha256 …) && bash lib/install.sh
      $repo && sha2=$(sha256 …) && [ "$sha" = "$sha2" ]`.
- [ ] The event schema keys and phase carrier match the existing
      `budget_block` shape (`phase=$FLEET_PHASE`, `slug`, `type=budget_warning`)
      so consumers do not need a schema branch. Test asserts via
      `node -e 'JSON.parse(…)'` against the emitted line.

## Out of scope

- Auto-raising the cap. The operator decides — that's the whole point of a
  manifest-declared knob.
- Push/SMS/desktop notification channels. That's fleet-control's job; this
  ticket only produces the event.
- Backfilling projections across historical days. The warning is
  today-forward only.
- Charging a "priority" burn rate to reserve headroom for the eng runner
  (an interesting future policy, but write-side and out of scope).

## Engineering notes

- `lib/common.sh` — add `fleet_check_budget_projection` next to
  `fleet_check_budget` (grep for the existing symbol). Reuse the existing
  cost-parsing awk pass over `events.jsonl` to avoid a second scan per
  process — helper returns via exported `FLEET_BUDGET_WARN_VERDICT` per
  LESSONS 2026-06-05 (an at-most-once export cannot survive a `$(...)`
  fork).
- `agents.config.sh` template + `templates/AGENTS.section.md` — document the
  optional `BUDGET_WARN_PCT` and `BUDGET_WARN_LOOKAHEAD_HOURS` knobs
  (defaults 0.80 and 6).
- `bin/fleet` — `doctor`, `morning`, `inbox` grow one new render block each
  reading the new event (or recomputing the projection when
  `$FLEET_BUDGET_WARN_VERDICT` is unset — same shape as
  `self_cancel_warning` in 0066).
- `AGENTS.md § Telemetry` — document the new `budget_warning` event type
  next to `budget_block`.
- New deps: none (shell-only, awk math). Backwards compatibility: additive
  event type — consumers MUST tolerate unknown types per the existing
  Telemetry contract.
- Reinstall required: YES — `lib/common.sh` and `prompts/` (documentation)
  change. PR body carries `Reinstall: all projects`.

## Implementation log

(Appended by the implementation-dev agent during execution.)
