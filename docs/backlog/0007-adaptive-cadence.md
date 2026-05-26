---
id: 0007
title: Adaptive groom cadence when backlog is empty
status: groomed
priority: P2
area: engine
created: 2026-05-26
owner: gtm-innovation
---

## User story

As a fleet operator, I want groom to run less often when the backlog has no
P0/P1 work left, so that I'm not paying for groom passes that find nothing to
do.

## Why now (four lenses)

### Product Owner
Removes a wasted run class. Today groom fires on a fixed schedule even when
there's nothing to groom; that's an expensive no-op.

### Stakeholder
Cost moat. Compounds across projects: 4 groom runs/day × 6 projects = 24
runs; cutting half of those when nothing's actionable adds up.

### Operator
The portal's "Next" panel shows the adjusted cadence ("next groom: 12h") and
the operator understands why.

### Growth
"The kit slows down when it has nothing to do" is a frugality property
worth showing.

## Acceptance criteria

Each box maps 1:1 to a test scenario in `tests/cadence.sh`.

- [ ] Given a fresh checkout whose `docs/backlog/` has zero `status: proposed`
      tickets AND fewer than 3 groomed P0/P1 tickets, `lib/groom.sh` writes
      an ISO8601 UTC timestamp into `$CACHE_DIR/groom-slowed-since`, emits
      `fleet_emit_event groom_throttled since=<ts> reason=empty_backlog`, and
      exits 0 without spawning `fleet_run_claude`.
- [ ] Given the marker file exists and its timestamp is less than 12h old,
      groom exits 0 immediately and emits a second `groom_throttled` event
      with `since=<original_ts>`.
- [ ] Given the marker file exists and its timestamp is 12h+ old, groom
      proceeds (spawns the subagent) and removes the marker before exit.
- [ ] Given the marker file is absent AND backlog has groomed P0/P1 work,
      groom proceeds normally and no `groom_throttled` event is emitted.
- [ ] `bin/fleet doctor` reports a `groom_cadence` check per project: PASS
      if no marker or marker stale; INFO/WARN if throttled with the marker
      timestamp in the reason field; the `--json` output exposes the
      timestamp under `checks[].reason`.

## Out of scope

- Adjusting `ship`/`review`/`eng` cadence. Groom-only in v1.
- Changing the launchd plist schedule itself. Shell-side floor only.
- Adaptive *floor* (12h is constant; not env-tunable in v1).

## Engineering notes

- `lib/groom.sh` — gate before `fleet_run_claude`. Reuse `fleet_checkout`
  to get a fresh `docs/backlog/`.
- Read the backlog index in shell: parse markdown table rows where status
  is `proposed`/`groomed` and priority is `P0`/`P1` via a small `awk`
  pipeline. (Don't re-implement `check-backlog.mjs`; the table is the
  ordering truth — that's what we read.)
- `bin/fleet` doctor — extend the existing `doctor()` with a `groom_cadence`
  check that stats the marker file.
- `tests/cadence.sh` — `mktemp -d` fixtures for `CACHE_DIR` and a fake
  checkout with controlled backlog index content. Use `touch -t` to age
  the marker (mind the BSD-touch-is-local lesson from 0001).
- Public API: additive.
- Reinstall: all projects.

## Implementation log

(Appended by the implementation-dev agent during execution.)
