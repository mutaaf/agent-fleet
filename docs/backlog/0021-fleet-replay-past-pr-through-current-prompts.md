---
id: 0021
title: fleet replay re-runs a past merged PR through the current prompts in dry-run
status: in-progress
priority: P2
area: governance
created: 2026-05-28
owner: gtm-innovation
---

## User story

As a fleet operator who just edited `prompts/PRINCIPLES.md` or
`prompts/ship.prompt.md`, I want `bin/fleet replay <slug> --pr <N>` to
re-run the ship/review prompt against a past merged PR's ticket +
diff in dry-run mode and print what the new prompt WOULD have done,
so that I can sanity-check a prompt change against real historical
behavior before letting the live loop fire under it.

## Why now (four lenses)

### Product Owner
Prompts are now the loop's constitution (PRINCIPLES.md, ticket 0018) and
they version (CHANGELOG + SHA pin, ticket 0013). What is missing is a
way to ask "would the new prompt have rejected PR #42, which we know
was a good ship?" Today the only way to answer is to wait for the next
real PR and hope. `fleet replay` closes that loop in one command:
dry-run mode (ticket 0010) already provides the tool-locked execution
substrate; events.jsonl + runs.jsonl record past PR metadata; the
prompt under test reads AGENTS.md + the ticket + the diff at runtime,
which we can synthesize from `gh pr view --json` + `gh pr diff`. The
smallest unit of value is "type one command, get one verdict."

### Stakeholder
Widens the moat on `governance` and on the safe-self-modifying-loop
claim. Today's prompt edits ship on a CI gate (`shellcheck`,
`validate`) that can not measure semantic regression — a bad prompt
edit that makes the reviewer too strict, or the dev agent too timid,
sails through. `fleet replay` is the first regression check for the
prompts themselves: ten past good PRs replayed through the new prompt,
ten "would have signed off" verdicts, ship it. It is the same logic
that made the backlog validator load-bearing — codify the contract,
gate on the codification.

### User (operator after editing PRINCIPLES.md)
Types `fleet replay agent-fleet --pr 17 --phase review`. Sees:

```
Replaying review prompt against agent-fleet PR #17 (0017-fleet-rollback)
  ticket: docs/backlog/0017-fleet-rollback.md (shipped 2026-05-26)
  diff:   42 files, +1483/-7
  prompt: prompts/review.prompt.md (sha 8a20547, edited 2 min ago)

Dry-run verdict (from claude --print --allowedTools none):
  VERDICT: sign-off
  rationale: respects branch-prefix convention; tests cover all ACs;
             no HARD NO violation; the additive event-type matches
             AGENTS.md § Telemetry contract.

OK to proceed.
```

Or, in the unhappy case:

```
  VERDICT: --request-changes
  rationale: new prompt's P-7 strict-monotonicity rule trips on the
             revert/ branch prefix being added in the same PR.

Hold. Recheck the prompt edit.
```

One command, one verdict, one decision. The "did my prompt edit
silently break the loop?" anxiety drops to a 30-second check.

### Growth
"You can replay a past PR through your current prompts" is exactly the
kind of property that makes a careful operator trust the kit with
prompt edits. It is also the natural extension of dry-run mode that a
friend asking "how do you test prompt changes?" wants to hear about.
The full circuit — PRINCIPLES.md (0018) writes the rules,
prompts-diff (0013) shows the change, replay (this) tests the change
— closes the doctrine loop.

## Acceptance criteria

Each box maps 1:1 to a test scenario in `tests/replay.sh`.

- [ ] `bin/fleet replay <slug> --pr <N>` (no `--phase`) defaults to
      `--phase review`. With `--phase review` it: (a) uses
      `rollback_resolve_manifest` (already in `bin/fleet`, per
      0017) to find the slug's repo URL; (b) calls `gh pr view <N>
      --repo <repo> --json number,title,headRefName,body,mergeCommit,mergedAt,files`
      and `gh pr diff <N> --repo <repo>`; (c) reads the linked
      ticket file from the PR title's `feat/<id>-` prefix; (d)
      composes a prompt input containing the diff, the ticket, the
      repo's AGENTS.md, and LESSONS.md from a fresh checkout; (e)
      invokes `fleet_run_claude` with `AGENT_DRY_RUN=1` (i.e. the
      already-shipped `--allowedTools none` path) and the review
      prompt; (f) prints the first 400 chars of the result plus a
      single-line verdict line parsed by regex (`^VERDICT:\s*(sign-off|request-changes)`).
- [ ] `--phase ship` runs the same flow but composes the ship prompt
      input (ticket + LESSONS, no diff — the ship prompt is asked
      "what would you do?" not "is this good?"). Verdict line is
      `^ACTION:\s*(heal|ship|wait|noop)`.
- [ ] `--phase review --request-changes-ok` flips the success
      condition: exit 0 only if the verdict is `request-changes`.
      Useful for replaying KNOWN-BAD PRs (a regression set the
      operator builds up) and asserting the prompt still catches
      them. Default exit code: 0 when verdict is `sign-off` for
      review or `ship`/`heal` for ship; 1 otherwise.
- [ ] `--dry` (default) does NOT call `gh pr merge`, does NOT push,
      does NOT comment on the PR. It is `AGENT_DRY_RUN=1` end-to-end.
      The test stubs `claude` to record its argv and asserts
      `--allowedTools none` is present.
- [ ] `--out FILE` writes the full claude result to a file (default:
      `$CACHE_DIR/replay-<slug>-pr<N>-<phase>-<ts>.txt`). The path
      is printed at end of stdout so the operator can `cat` it for
      detail.
- [ ] When the PR's title does NOT match `feat/<NNNN>-` (e.g. a
      `chore/gtm-` PR), `replay` prints `not an agent feature PR;
      replay is scoped to feat/ and eng/ branches` and exits 2.
      The test asserts this on a fixture chore PR.
- [ ] When the PR is unmerged, `replay --pr <N>` still works — it
      reads the open PR's head diff. The test asserts both merged
      and open paths via stubbed `gh pr view` output.
- [ ] A `runs.jsonl` line is appended for the replay call (real
      claude cost), tagged `phase=replay` so cost accounting and
      `fleet digest` do not confuse it with a real ship run. The
      `runs.jsonl` writer in `lib/common.sh` already accepts a
      `phase` arg via `fleet_log_init` — confirm and reuse.
- [ ] `tests/replay.sh` uses `$HOME/.local/bin` stubs (per LESSONS
      2026-05-26) for `claude`, `gh`, `git`. Asserts argv contains
      `--allowedTools none`, no `gh pr merge` was called, and the
      printed verdict matches the stubbed claude result.
- [ ] `README.md` "Daily ops" section gains a one-line callout
      placed next to the `kickstart --dry-run` callout.

## Out of scope

- Replaying a batch of PRs in one command (`fleet replay --recent
  10`). v1 is one PR at a time; batching is a wrapper around v1
  the operator can write as a shell loop.
- Recording a replay regression suite (`fleet replay --record`
  saves the verdict as the expected output of a future regression
  run). The output file is already saved; codifying it as a test
  fixture is a separate ticket.
- Replaying past LESSONS edits (testing whether a new LESSON would
  have changed past decisions). LESSONS is consulted by the prompts
  but not the prompt itself; this ticket is scoped to prompts/*.md.
- A web UI for replays. Fleet-control can render the output later.
- Replaying review with the OLD prompt to compare. The point is to
  test the CURRENT (potentially-edited) tree; comparing against the
  pinned SHA is what `prompts-diff` already does.

## Engineering notes

- `bin/fleet` — new `replay()` function plus dispatcher case.
  Reuses `rollback_resolve_manifest`, `rollback_first_pr_json`-style
  patterns from ticket 0017 for the `gh pr view` shape.
- `lib/common.sh` — no changes expected. `fleet_run_claude` already
  honors `AGENT_DRY_RUN`. If `fleet_log_init` needs to learn the
  `replay` phase string (purely a label, not a behavior change),
  that is a one-line tweak.
- The prompt input composition mirrors what `lib/review.sh` and
  `lib/ship.sh` already build — the same checkout pattern via
  `fleet_checkout` into a one-shot `$CACHE_DIR/replay-checkout/`.
- `tests/replay.sh` — `mktemp -d` fixture, stubbed `claude` that
  echoes a canned `VERDICT: sign-off` plus rationale; stubbed `gh`
  that returns canned `pr view --json` and `pr diff` output;
  assertions on argv, stdout, exit code, runs.jsonl shape.
- New deps: none.
- Public API: additive (`bin/fleet replay`, optional `phase=replay`
  label in `fleet_log_init`). No existing signature changes.
- Reinstall required: NO if `lib/common.sh` is untouched; YES if
  `fleet_log_init` learns the new phase label. Prefer NO — make the
  phase label a plain string passed by the caller.
- The `tail`-shadowing lesson (LESSONS 2026-05-26): `replay()`
  does not collide with a coreutils binary, no `_cmd` suffix
  needed.

## Implementation log

- 2026-05-28 — picked up by implementation-dev. Branch `feat/0021-fleet-replay`. Plan:
  add a new `replay()` dispatcher in `bin/fleet` that reuses
  `rollback_resolve_manifest` (per ticket 0017), composes a prompt input from
  `gh pr view --json` + `gh pr diff` + the AGENTS.md/LESSONS.md/ticket files
  from a fresh kit checkout, then invokes `claude --print --output-format json
  --allowedTools none` directly (we don't need `fleet_run_claude` since the
  caller is not a runner — and we want `phase=replay` to be a plain label).
  We DO append to `runs.jsonl` so cost accounting reflects the replay.
  No changes to `lib/common.sh` — `fleet_log_init` stays out of this. The
  prompt label is just a string we tag.
