---
id: 0002
title: Structured events.jsonl telemetry channel
status: shipped
priority: P0
area: telemetry
created: 2026-05-26
owner: gtm-innovation
---

## User story

As a fleet operator, I want every runner to emit typed events to a single
JSONL file per slug, so that fleet-control can read them directly instead of
scraping transcripts and so future tickets (budget caps, anomaly detection,
auto-pause) have a stable input.

## Why now (four lenses)

### Product Owner
This is the foundation under half the other tickets. Today fleet-control
reverse-engineers run identity, PR linkage, and outcome from `claude --print
--output-format json` transcripts. That works but is fragile. A typed event
stream is one source of truth.

### Stakeholder
Widens the moat on `telemetry`. Once the contract is stable, every consumer
(portal, alerts, budget enforcement) reads the same file. New consumers don't
re-parse.

### Operator (Tuesday 9am, glance at the portal)
The "Now / Last / Next" panel reads events.jsonl and shows the phase and any
`gate_failed`/`pr_opened`/`self_cancel_trip` without a transcript-tail
heuristic. The "is it stuck?" question gets a definitive answer.

### Growth
"Add your own consumer in 10 lines of Node" is a shareable property. The
JSONL schema is small enough to fit on a postcard.

## Acceptance criteria

- [ ] `common.sh` exposes `fleet_emit_event <type> [k=v]...` that appends a
      single JSON line to `$CACHE_DIR/events.jsonl`. Every event includes
      `ts` (ISO8601 UTC), `slug`, `phase`, `type`, plus any extra `k=v`
      fields converted to JSON keys.
- [ ] Event types emitted by the existing runners (with their fields):
      `run_started {pid}`, `run_completed {exit, duration_ms}`,
      `gate_failed {check}` (best-effort from the heal path),
      `pr_opened {number, branch}`, `self_cancel_trip {}`,
      `lock_blocked {phase, holder_pid}` (paired with ticket 0001),
      `budget_block {reason}` (placeholder until ticket 0004).
- [ ] The implementation is shell-only, no `jq` dependency for *writing*
      (compose JSON by hand with escapes); reading still uses `jq` where
      available.
- [ ] A test in `tests/events.sh` calls `fleet_emit_event` with a sample
      event containing a value that needs escaping (a quote and a backslash)
      and asserts the resulting line is valid JSON via
      `node -e "JSON.parse(require('fs').readFileSync(...))"`.
- [ ] The file rotates by **append-only**; no truncation. A separate ticket
      will cover GC if needed.
- [ ] `prompts/ship.prompt.md` is updated to mention `events.jsonl` as the
      destination for `pr_opened` (so the dev agent emits it after
      `gh pr create`).
- [ ] Documented in `AGENTS.md` under a new `## Telemetry` section: schema +
      file path + the event type list.

## Out of scope

- A binary protobuf format. JSONL is the contract.
- Cross-slug aggregation (that's fleet-control's job, ticket FC#1).
- Retention/rotation (separate ticket).

## Engineering notes

- `lib/common.sh` — add `fleet_emit_event` near the bottom. Compose JSON via
  `printf` with a small `_json_escape` helper (escape `"` and `\` and control
  chars; keep it under 20 lines).
- `lib/ship.sh`, `groom.sh`, `review.sh`, `eng.sh` — emit `run_started` after
  `fleet_log_init` and `run_completed` before the final `exit`.
- `prompts/ship.prompt.md` — add a one-liner: "After `gh pr create`, emit
  `fleet_emit_event pr_opened number=$N branch=$B`."
- `AGENTS.md` — add `## Telemetry` section documenting schema + types.
- Reinstall: all projects.
- Public API: additive (`fleet_emit_event`). No BREAKING.

## Implementation log

- 2026-05-26 — picked up by `implementation-dev`. Branch
  `feat/0002-events-jsonl-channel`. Plan: failing test first
  (`tests/events.sh` calling `fleet_emit_event` with a value containing a
  quote and a backslash, validated via `node -e "JSON.parse(...)"`), then
  add `_json_escape` + `fleet_emit_event` to `lib/common.sh`, then wire
  `run_started`/`run_completed` into `ship.sh`/`groom.sh`/`review.sh`/`eng.sh`,
  then add the `pr_opened` instruction to `prompts/ship.prompt.md`, then
  document the schema in `AGENTS.md` under a new `## Telemetry` section.
- 2026-05-26 — shipped. `_json_escape` is a 17-line pure-bash escaper
  (handles `"`, `\\`, `\b\f\n\r\t`, and `\u00xx` for the rest of the C0
  control range). `fleet_emit_event` composes one line by hand and appends
  to `$CACHE_DIR/events.jsonl`. Runners now set `FLEET_PHASE` in
  `fleet_log_init` so emitted events carry the right phase; `ship.sh`,
  `groom.sh`, `eng.sh`, and `review.sh` emit `run_started {pid}` after
  `fleet_log_init` and `run_completed {exit, duration_ms}` before the
  final `exit`. `tests/events.sh` covers the JSON.parse round-trip on a
  value containing a quote AND a backslash, the four-key schema, extras
  landing as JSON keys, and append-only semantics across two invocations.
