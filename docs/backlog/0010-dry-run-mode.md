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

Each box maps 1:1 to a test scenario in `tests/dry-run.sh`.

- [ ] Given `AGENT_DRY_RUN=1` and a stubbed `claude` on PATH that records
      its argv, calling `fleet_run_claude` results in argv containing
      `--allowedTools` followed by `none`.
- [ ] Given `AGENT_DRY_RUN` unset, the same `fleet_run_claude` invocation
      does NOT pass `--allowedTools none`.
- [ ] In dry-run mode, `fleet_emit_event run_dry_run
      plan_head=<first-200-chars-of-result>` is emitted; `run_completed`
      is NOT emitted (it's replaced, not paired).
- [ ] Dry-run mode still appends to `runs.jsonl` with the recorded cost
      and result (it's a real claude call, just tool-locked).
- [ ] `bin/fleet kickstart <slug> <phase> --dry-run` exports
      `AGENT_DRY_RUN=1` and invokes `launchctl kickstart` against the
      matching label. The test stubs `launchctl` and asserts the kickstart
      call was made and the env was exported (by having the kickstart
      stub echo `AGENT_DRY_RUN` into a file).
- [ ] `bin/fleet kickstart <slug> <phase>` (without `--dry-run`) does NOT
      set the env var.
- [ ] `README.md` "Daily ops" section mentions the env var and the
      `--dry-run` kickstart flag (grep for `AGENT_DRY_RUN`).

## Out of scope

- A separate dry-run prompt. The same prompt runs; only tool execution is
  disabled.
- Dry-run-then-confirm flows. v1 is just observation.
- Dry-run for the `review` phase (review already has no write effects on
  the repo — its only mutation is the GitHub review comment; we'd need a
  separate ticket for that).

## Engineering notes

- `lib/common.sh` — branch in `fleet_run_claude` on `${AGENT_DRY_RUN:-}`.
  Append `--allowedTools none` to the existing argv when set. Replace the
  `run_completed` emission with `run_dry_run` when set.
- `bin/fleet` — introduce `kickstart <slug> <phase> [--dry-run]` subcommand
  (small; wraps `launchctl kickstart -k gui/$UID/$NAMESPACE.agent-$PHASE`
  with an optional `env AGENT_DRY_RUN=1` prefix via `launchctl setenv`).
- Public API: additive — `fleet_run_claude` behavior gains an env-driven
  branch, signature unchanged.
- Reinstall: all projects.

## Implementation log

(Appended by the implementation-dev agent during execution.)
