---
id: 0014
title: Trainee mode requires operator approval for the first N PRs
status: groomed
priority: P1
area: safety
created: 2026-05-26
owner: gtm-innovation
---

## User story

As a fleet operator onboarding a fresh project, I want the first N ship PRs
to NOT arm GitHub auto-merge, so that I see every change the agent makes
before it lands while the project is still finding its rhythm — and the
loop graduates itself to full autonomy once I've signed off on enough work.

## Why now (four lenses)

### Product Owner
The biggest mental cost of adopting the kit on a new project is the "what
if it goes wild on hour one" objection. Today the operator's only
mitigations are (a) hand-merging the first few PRs by pulling the
auto-merge themselves, or (b) `SELF_CANCEL`-ing the project after a day to
re-evaluate. Trainee mode is the missing seatbelt: declarative, in the
manifest, no extra ritual.

### Stakeholder
Widens the moat on `safety` AND on `adoption`. The kit becomes safer to
TRY (the worst case in the first day is "PRs pile up waiting for me to
review them" — not "an agent merged something weird while I slept"). It
pairs naturally with `fleet onboard` (0011): the onboard command sets
`TRAINEE_PR_COUNT=5` by default, and operators graduate explicitly.

### User (operator on day one of a new project)
"It opened a PR. It posted a comment: 'Trainee mode 1/5 — please review
before merging.' I read the diff, click merge, see ship pick up the next
ticket on the next :41. I do that five times and trainee mode turns off
on its own." That's a fundamentally different onboarding experience than
"set up the agent and pray it doesn't go off the rails overnight."

### Growth
"It won't auto-merge until you've signed off on the first five PRs" is
exactly the property that turns "I'm scared to install this" into "ok I
trust it enough to try." This is the conversion-rate ticket.

## Acceptance criteria

Each box maps 1:1 to a test scenario in `tests/trainee.sh`.

- [ ] `agents.config.sh` gains an optional `TRAINEE_PR_COUNT` variable
      (default 0 = trainee mode disabled, current behavior preserved).
      `manifest.example.sh` documents it inline.
- [ ] `lib/common.sh` exposes `fleet_trainee_remaining` which returns the
      integer `max(0, TRAINEE_PR_COUNT - <merged feat/ PRs to main>)`. The
      merged count comes from `gh pr list --state merged --search "head:feat/
      base:main" --json number | jq length`. If `TRAINEE_PR_COUNT` is unset
      or 0, the function prints `0` and returns 0.
- [ ] `lib/common.sh` exports `FLEET_TRAINEE_REMAINING` (the integer above)
      after `fleet_load_manifest`. The export is visible to subagents that
      consume the environment via `fleet_run_claude`.
- [ ] `prompts/ship.prompt.md` is updated: when arming auto-merge in PHASE
      1(e) and PHASE 2, the prompt instructs the dev agent to check
      `FLEET_TRAINEE_REMAINING`. If > 0: skip `gh pr merge --auto`, instead
      post a comment `[FLEET trainee mode <K>/<N>] Please review and merge
      manually.` where K = `TRAINEE_PR_COUNT - FLEET_TRAINEE_REMAINING + 1`.
      If 0: arm auto-merge as today.
- [ ] `fleet_emit_event trainee_pr_opened number=<N> remaining=<R>` fires
      when the dev agent opens a PR while trainee mode is active. The test
      stubs the prompt invocation, asserts the event.
- [ ] `bin/fleet doctor` adds a `trainee_mode` check per project:
      INFO/WARN with `trainee mode active: N PRs remaining` when
      `FLEET_TRAINEE_REMAINING > 0`; PASS otherwise. Visible in `--json`.
- [ ] `bin/fleet digest` (ticket 0012, if shipped first) shows
      `TRAINEE-N` in the state tag column. If 0012 hasn't shipped, just
      ensure the events.jsonl entry exists so a future digest can pick
      it up.
- [ ] Given a fixture with `TRAINEE_PR_COUNT=3` and one merged `feat/` PR,
      `fleet_trainee_remaining` prints `2`. Given the same with 5 merged
      PRs, it prints `0`. Given `TRAINEE_PR_COUNT` unset, it prints `0`.
- [ ] Documented in `AGENTS.md § Telemetry` as the `trainee_pr_opened`
      event row.

## Out of scope

- Trainee mode for `eng/` or `chore/gtm-` PRs. Feature PRs only — those
  are the user-visible changes.
- A "trainee mode for one specific area" filter. v1 is project-wide.
- Auto-graduation based on time (rather than PR count). Count is simpler
  and operator-controllable.
- Resetting the counter if old PRs are reverted. The count is "PRs ever
  merged to main."

## Engineering notes

- `lib/common.sh` — `fleet_trainee_remaining` near `fleet_check_budget`
  (0004). Single `gh pr list` call, cached per process (the same run
  shouldn't pay for two API hits).
- `manifest.example.sh` — add `TRAINEE_PR_COUNT` in the `--- spend bound
  ---` section with a comment ("first N feature PRs require manual
  merge; 0 = disabled").
- `prompts/ship.prompt.md` — add a small section right before the auto-
  merge instruction in PHASE 1(e) and PHASE 2. Keep it under 5 lines —
  the prompt is already tight.
- `bin/fleet onboard` (ticket 0011, if shipped first) — the generated
  `agents.config.sh` SHOULD include `TRAINEE_PR_COUNT=5` by default.
  Cross-link this in the implementation log of 0011 if both are in flight.
- `tests/trainee.sh` — `mktemp -d` fixture, stub `gh` on PATH to return
  controllable PR counts, source `common.sh`, assert
  `fleet_trainee_remaining` math and the env export.
- Public API: additive (`fleet_trainee_remaining`, `FLEET_TRAINEE_REMAINING`
  env). No signature changes to existing functions.
- Reinstall: all projects.

## Implementation log

(Appended by the implementation-dev agent during execution.)
