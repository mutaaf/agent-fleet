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

- [ ] `lib/groom.sh` gains a pre-flight check: if `docs/backlog/` (in the
      fresh checkout) has zero `status: proposed` rows AND fewer than 3
      `status: groomed` rows at `P0`/`P1`, the runner sets a marker file at
      `$CACHE_DIR/groom-slowed-since` (timestamp) and exits 0.
- [ ] Once the marker is set, subsequent groom runs only proceed if at least
      12h has elapsed since the marker. (The launchd job still fires on its
      schedule; the shell logic enforces the 12h floor.)
- [ ] When groom does proceed, it clears the marker. When it would have
      proceeded but is being suppressed, it emits
      `fleet_emit_event groom_throttled` with `since=$marker_ts`.
- [ ] `fleet doctor` reports the marker state per project ("groom-throttled
      since X").
- [ ] `tests/cadence.sh` exercises both paths: marker absent → proceeds;
      marker fresh → suppresses; marker stale (>12h) → proceeds.

## Out of scope

- Adjusting `ship`/`review`/`eng` cadence. Groom-only in v1.
- Changing the launchd plist schedule itself. Shell-side floor only.

## Engineering notes

- `lib/groom.sh` — add the check before `fleet_run_claude`. Reuse
  `fleet_checkout` to get a fresh `docs/backlog/`.
- Reading the backlog index in shell: parse the markdown table rows where
  status is `proposed`/`groomed` and priority is `P0`/`P1`. A small `awk`
  pipeline.
- Blocked-by: 0002 (events channel).
- Public API: additive.

## Implementation log

(Appended by the implementation-dev agent during execution.)
