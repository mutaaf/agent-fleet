---
id: 0005
title: Prompt-version pinning in agents.config.sh
status: groomed
priority: P1
area: governance
created: 2026-05-26
owner: gtm-innovation
---

## User story

As a fleet operator, I want each project to declare the `prompts/` SHA it was
last tested against, so that the runner can warn me when the shared engine's
prompts have drifted since the last reinstall — before behavior silently
changes.

## Why now (four lenses)

### Product Owner
A change to `prompts/ship.prompt.md` affects every installed project the next
time install.sh runs. The operator deserves a visible "behavior shifted" signal,
not a surprise. One field in the manifest, one check in `common.sh`.

### Stakeholder
Widens the moat on `governance`. The self-modifying loop becomes legible:
the operator can see, for every project, "this is the prompt set you're on."

### Operator
After upgrading the kit, `fleet doctor` (ticket 0003) lights up the projects
whose pinned SHA no longer matches `lib/`'s actual SHA. The operator chooses
to bump the pin (acknowledging the new behavior) or revert.

### Growth
"Prompt drift detection" is the kind of property that signals a serious
autonomous-agent kit, not a weekend hack.

## Acceptance criteria

- [ ] `bin/fleet prompts-sha` prints the SHA256 of
      `find prompts -type f -name '*.md' | sort | xargs cat`. Deterministic.
- [ ] `agents.config.sh` gains an optional `PROMPTS_SHA` variable. When
      unset, runners assume current and don't warn.
- [ ] When `PROMPTS_SHA` is set and doesn't match the current `prompts/`
      SHA, `common.sh` emits a single `prompts_drift` event per run
      (`fleet_emit_event prompts_drift pinned=$pin actual=$cur`) and prints
      a warning to the log, but continues. Not a fatal abort.
- [ ] `fleet doctor` adds a `prompts_pinned` check per project: PASS if
      `PROMPTS_SHA` is set and matches, WARN if unset, FAIL if mismatched.
- [ ] `lib/install.sh` writes the current `PROMPTS_SHA` into the copied
      manifest under `$CFG_DIR/agents.config.sh` (NOT the source manifest —
      the source is owned by the operator). Adds a line:
      `# PROMPTS_SHA pinned at install time: <sha>`
- [ ] `tests/prompts-sha.sh` validates `bin/fleet prompts-sha` is stable
      across two invocations.
- [ ] Documented in `AGENTS.md` § Telemetry as the `prompts_drift` event.

## Out of scope

- Auto-bumping the pin. The operator does this manually by re-running
  install.sh (which is what they were going to do anyway).
- Multi-SHA pinning (per-phase). One SHA covers all prompts.

## Engineering notes

- `bin/fleet` — add `prompts-sha` subcommand. Use `shasum -a 256`.
- `lib/common.sh` — drift check near `fleet_self_cancel`.
- `lib/install.sh` — append `# PROMPTS_SHA pinned at install time: <sha>` to
  `$CFG_DIR/agents.config.sh`. Idempotent — strip the old line if present
  before appending.
- Blocked-by: 0002 (events channel) and ideally 0003 (doctor) but not hard.
- Reinstall: all projects (so the pin gets written).

## Implementation log

(Appended by the implementation-dev agent during execution.)
