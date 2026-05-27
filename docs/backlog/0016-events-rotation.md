---
id: 0016
title: events.jsonl size-based rotation with retained archives
status: shipped
priority: P2
area: telemetry
created: 2026-05-26
owner: gtm-innovation
---

## User story

As a fleet operator running the loop for months, I want
`$CACHE_DIR/events.jsonl` to rotate at a size threshold instead of growing
unbounded, so that a tail of the channel stays fast and a year-old run
doesn't dominate the file. The historical events stay on disk in
archives — I never lose telemetry, I just don't carry it all in one line-
addressable file.

## Why now (four lenses)

### Product Owner
AGENTS.md § Telemetry explicitly defers this: "A future ticket will cover
GC if size becomes an issue — for now the channel grows." With 0002
shipped and four downstream consumers depending on the channel (0003,
0004, 0005, 0006, 0012, 0014, and the proposed 0015), unbounded growth
is now a forward liability: ~6 events per ship run × 24 runs/day × 6
projects × 90 days ≈ 78k lines per project. Cheap to fix today, painful
to retrofit once consumers start scanning the whole file.

### Stakeholder
Widens the moat on `telemetry`. Rotation is the property that makes the
channel a real, audit-ready operational record instead of an
ever-growing junk drawer. Archival format is identical (still JSONL), so
every consumer keeps working — they just opt in to historical files by
glob if they care.

### User (operator a year in)
`fleet tail` (0015) doesn't slow down because events.jsonl is bounded.
`fleet digest` (0012) windowing stays fast. The operator can `ls
$CACHE_DIR/events.jsonl.archive/` and see a clean monthly archive trail —
"this is what the agent did in September."

### Growth
"Append-only telemetry with bounded files and full retention" reads as
maturity. Compare to "JSONL grows forever, hope you have disk." Anyone
evaluating the kit for a long-running deployment looks for this.

## Acceptance criteria

Each box maps 1:1 to a test scenario in `tests/events-rotation.sh`.

- [ ] `lib/common.sh` exposes `fleet_rotate_events` which:
      - Returns 0 immediately if `$CACHE_DIR/events.jsonl` doesn't exist or
        is smaller than `${FLEET_EVENTS_MAX_BYTES:-1048576}` (default 1 MiB).
      - Otherwise: moves the file to
        `$CACHE_DIR/events.jsonl.archive/<YYYYMMDD>-<HHMMSS>.jsonl`
        (UTC), creates an empty new `events.jsonl`, and emits a
        `fleet_emit_event events_rotated archived=<path> bytes=<n>` line
        to the NEW file.
- [ ] `fleet_rotate_events` is called from `fleet_emit_event` BEFORE the
      append, at most once per process (guarded by a
      `FLEET_EVENTS_ROTATE_CHECKED` flag) so high-frequency emitters don't
      pay the size check on every call. The check runs again on the next
      process invocation.
- [ ] The archive directory is created lazily (only when first rotation
      happens). Permissions match the parent cache dir.
- [ ] Given an events.jsonl that's exactly 1 MiB + 1 byte, calling
      `fleet_emit_event` rotates it. The test seeds a file at that size,
      calls the function, asserts archive exists and the new
      events.jsonl contains exactly two lines (the `events_rotated`
      marker followed by the just-emitted event).
- [ ] Given an events.jsonl under the threshold, `fleet_emit_event`
      appends without rotating. The test asserts no archive directory
      was created.
- [ ] `bin/fleet doctor` reports an `events_size` check per project:
      PASS if under threshold or rotation has run in the last 7 days,
      WARN if over threshold AND no recent rotation marker, FAIL on a
      malformed events.jsonl (line that doesn't parse as JSON). The
      check is best-effort and never aborts the doctor pass.
- [ ] `bin/fleet tail` (ticket 0015) MUST honor rotation: when
      events.jsonl is moved out from under `tail -F`, the next process
      lifecycle picks up the new file. The contract is satisfied by the
      `tail -F` semantic (capital F follows by name, not fd), but a
      regression test in `tests/tail.sh` exercises a rotation while a
      tail is running and asserts new lines still appear.
- [ ] `AGENTS.md § Telemetry` gets a new sentence in the "Format" bullet:
      "Rotates at `FLEET_EVENTS_MAX_BYTES` (default 1 MiB) into
      `events.jsonl.archive/<UTC-stamp>.jsonl`; the contract above
      applies to all files in the channel including archives."
- [ ] The `events_rotated` event type is documented in
      `AGENTS.md § Telemetry` event types list with its two fields
      (`archived`, `bytes`).

## Out of scope

- Time-based rotation (e.g. "rotate at UTC midnight"). Size-only in v1 —
  ship cadence already imposes a natural floor.
- Pruning archives. The operator manages disk; the kit keeps everything.
- Compressing archives (e.g. `.jsonl.gz`). Plain files. A future ticket
  can add `gzip` if archive bloat becomes a real concern.
- Cross-project archive aggregation.

## Engineering notes

- `lib/common.sh` — add `fleet_rotate_events` adjacent to
  `fleet_emit_event`. Use `stat -f %z` on macOS / `stat -c %s` on Linux;
  shell-only, no `du` pipeline. A small helper picks the right `stat`
  flag.
- The rotation MUST be atomic-enough: `mv events.jsonl archive/<ts>.jsonl`
  is a rename on the same filesystem (always true here — both are under
  `$CACHE_DIR`), and the subsequent `: > events.jsonl` truncates an empty
  file. Worst case under a concurrent emitter is one event landing in the
  archive instead of the new file; the per-slug flock from ticket 0001
  already serializes runners, but `fleet_emit_event` itself is callable
  outside the locked region (e.g. from `prompts/ship.prompt.md` via the
  dev agent). That's acceptable — every event is preserved, none are
  lost.
- `tests/events-rotation.sh` — `mktemp -d`, set `CACHE_DIR=$tmpdir`,
  seed events.jsonl to a controlled size with `dd` (or printf padding
  to known bytes), source `common.sh`, call `fleet_emit_event`, assert
  filesystem state.
- Public API: additive (`fleet_rotate_events`,
  `FLEET_EVENTS_MAX_BYTES`, `events_rotated` event type). No signature
  changes.
- Reinstall: all projects (the rotation logic lives in `lib/common.sh`).
- Cross-ticket: 0015 (`fleet tail`) MUST work across rotations — the
  AC list above captures the regression check.

## Implementation log

- 2026-05-27 — implementation-dev: picked up. Plan: write `tests/events-rotation.sh`
  with one block per AC, add `fleet_rotate_events` + integration into
  `fleet_emit_event` in `lib/common.sh` (size helper via `stat -f %z` / `stat -c %s`,
  one-time guard via `FLEET_EVENTS_ROTATE_CHECKED`), wire `events_size` check into
  `bin/fleet doctor`, extend `tests/tail.sh` with a rotation-mid-tail regression,
  document the new event type + rotation contract in `AGENTS.md § Telemetry`.
- 2026-05-27 — implementation-dev: shipped. `fleet_rotate_events` added to
  `lib/common.sh` adjacent to `fleet_emit_event`, with a `_fleet_file_size`
  helper covering both `stat -f %z` (macOS) and `stat -c %s` (Linux). The
  guard `FLEET_EVENTS_ROTATE_CHECKED` is set BEFORE the recursive
  `events_rotated` emit so the inner call short-circuits cleanly. Doctor's
  new `events_size` check uses python3 (with a node fallback) to validate
  every line is JSON; size-only WARN when the file is over threshold AND no
  archive < 7d old exists; PASS otherwise. `tests/tail.sh` got a new AC#R
  block that simulates the exact mv+truncate sequence and asserts the
  post-rotation event still streams via `tail -F`. Local gate green
  (`shellcheck -S warning`, `bash -n`, `check-backlog`,
  `check-prompts-changelog`); `tests/events.sh`, `tests/doctor.sh`,
  `tests/tail.sh`, and `tests/events-rotation.sh` all pass.
