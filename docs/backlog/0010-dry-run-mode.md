---
id: 0010
title: AGENT_DRY_RUN end-to-end mode
status: groomed
priority: P2
area: safety
created: 2026-05-26
owner: gtm-innovation
---

## User story

As a fleet operator, I want to set `AGENT_DRY_RUN=1` and have a runner go
through its full motion without taking real actions, so that I can validate a
config change or a new prompt safely before letting the loop loose with money
on the line.

## Why now (four lenses)

### Product Owner
A pre-flight check that costs one env var and gives the operator confidence
before turning a new project loose. Today the only way to test is to wait
for `:41` and pray.

### Stakeholder
Widens the moat on `safety`. Pairs with `fleet doctor`: doctor checks state,
dry-run checks behavior.

### Operator
"Let me see what it would have done" — the runner emits its plan to the log
and the events.jsonl without pushing, committing, or paying for a real
claude run.

### Growth
"Dry-run mode" is the kind of property a careful operator will look for
before adopting a new autonomous-agent kit.

## Acceptance criteria

- [ ] When `AGENT_DRY_RUN=1` is set in the environment (or the manifest),
      `fleet_run_claude` invokes `claude --print --allowedTools none` so
      the model emits a plan but can't run tools. The .result is logged
      and recorded normally.
- [ ] The dev agent's prompt has no special accommodation needed — it just
      can't execute tools. The log captures the model's intended plan.
- [ ] `fleet_emit_event run_dry_run plan_head=<first-200-chars-of-result>`
      is emitted instead of `run_completed` when dry-run mode is active.
- [ ] `bin/fleet kickstart <slug> <phase> --dry-run` triggers a one-off
      dry run by setting the env var and invoking `launchctl kickstart`.
- [ ] `tests/dry-run.sh` stubs the `claude` binary with a script that asserts
      `--allowedTools none` was passed when `AGENT_DRY_RUN=1` is set, and
      not passed when unset.
- [ ] `README.md` "Daily ops" section mentions the env var and the
      `--dry-run` kickstart flag.

## Out of scope

- A separate dry-run prompt. The same prompt runs; only tool execution is
  disabled.
- Dry-run-then-confirm flows. v1 is just observation.

## Engineering notes

- `lib/common.sh` — branch in `fleet_run_claude` on `${AGENT_DRY_RUN:-}`.
- `bin/fleet` — add `--dry-run` flag to `kickstart` subcommand (introduce
  the subcommand if it doesn't exist yet; it's small).
- Blocked-by: 0002 (events channel).
- Public API: additive — `fleet_run_claude` behavior gains an env-driven
  branch, signature unchanged.

## Implementation log

(Appended by the implementation-dev agent during execution.)
