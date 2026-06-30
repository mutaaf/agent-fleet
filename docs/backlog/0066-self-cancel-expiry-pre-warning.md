---
id: 0066
title: Warn before SELF_CANCEL expiry so the loop never silently parks
status: groomed
priority: P1
area: safety
created: 2026-06-30
owner: operator
---

## User story

As a fleet operator who relies on `SELF_CANCEL` as a dead-man's switch, I want
the loop to warn me in the days *before* it expires — not just no-op silently
after — so that I re-arm on purpose instead of discovering, days later, that the
whole fleet quietly stopped shipping.

## Why now (four lenses)

### Product Owner
This shipped from a real incident: every project's `SELF_CANCEL` lapsed on
2026-06-25 and the fleet went dark for ~5 days before the operator noticed. The
current `fleet_self_cancel` only acts *at/after* expiry — it prints to a run log
nobody reads and exits 0. The smallest meaningful unit of value is a warning
*before* the cliff, surfaced where the operator already looks.

### Stakeholder
A self-pausing loop is a moat feature only if the operator knows it's about to
pause. Silent expiry turns a safety mechanism into an availability bug. Closing
this makes the dead-man's switch trustworthy instead of a recurring outage.

### Operator (9am glance)
"Everything green, nothing shipping" should never be a silent state. A loud
`⚠ agent-fleet self-cancels in 3 days — re-arm: …` line in the daily surfaces
turns a week-long blind spot into a one-glance, one-command fix.

### Extensibility — earned by capability, NOT marketing
Pure operator capability, no surface for strangers. A second operator adopting
the kit inherits a switch that warns instead of one that ambushes them.

## Acceptance criteria

- [ ] When `today` is within `SELF_CANCEL_WARN_DAYS` (manifest knob, default 5)
      of `SELF_CANCEL`, the runner prints a `⚠ self-cancel in N day(s)` warning
      to the run log AND emits a `self_cancel_warning` event carrying
      `days_remaining` and `self_cancel` to the events channel.
- [ ] `fleet doctor` (and `fleet morning`/`fleet inbox` if present) prominently
      lists every installed project inside its warning window, with the exact
      re-arm command.
- [ ] The warning fires at most once per project per day (no per-run spam across
      the 5-min review cadence) — dedup via a dated marker under `$CACHE_DIR`.
- [ ] Regression: when `today >= SELF_CANCEL`, behavior is unchanged (no-op,
      exit 0, existing expiry message preserved).
- [ ] `SELF_CANCEL_WARN_DAYS` defaults safely when absent from the manifest; an
      invalid/empty value falls back to 5 rather than erroring.
- [ ] No break to the `fleet_self_cancel` public signature (additive only);
      `install.sh` stays idempotent.

## Out of scope

- Auto-re-arming `SELF_CANCEL` (operator must decide to extend — that's the
  whole point of the switch).
- Push/SMS/desktop notifications — that's fleet-control/fleetd's job; this
  ticket only emits the event + log line they consume.

## Engineering notes

- `lib/common.sh` — add the pre-expiry window check near `fleet_self_cancel`
  (additive helper, e.g. `fleet_self_cancel_warn`); reuse the existing date math
  and `fleet_emit_event`.
- `agents.config.sh` template + `templates/AGENTS.section.md` — document the
  optional `SELF_CANCEL_WARN_DAYS` knob (default 5).
- `bin/fleet` — `doctor`/`morning`/`inbox` read the new event (or recompute the
  window) and render the warning block.
- New deps: none (shell-only, `date` math already in common.sh).
- Backwards compatibility: maintain `fleet_*` signatures; mark `BREAKING:` only
  if a signature must change (it should not).

## Implementation log

(Appended by the implementation-dev agent during execution.)
