---
id: 0024
title: fleet prompts-score grades each prompt revision from real event history
status: in-progress
priority: P1
area: governance
created: 2026-05-30
owner: gtm-innovation
---

## User story

As a fleet operator who just edited `prompts/ship.prompt.md` or
`prompts/PRINCIPLES.md` and is about to merge the change to main, I want
`bin/fleet prompts-score <slug> [--since 30d]` to read `events.jsonl`
and `runs.jsonl`, group the project's runs by the `PROMPTS_SHA` in
effect at the time, and print one score row per prompt revision —
sendback rate, draft-emit rate, heal attempts per PR, mean spend per
shipped PR, infra-flake share — so that I can SEE whether my last edit
actually made the loop tighter or sloppier instead of guessing from
vibes.

## Why now (four lenses)

### Product Owner
The kit's central self-improvement story has three legs today:
ticket 0013 logs every prompt change in `CHANGELOG.md`; ticket 0021
replays a past PR through the current prompts in dry-run; ticket 0022
drops a draft lesson on every send-back. What is missing is the
**rear-view-mirror** leg: did the prompt edits I shipped last week
actually move the numbers? Today the only answer is "ask the next ten
PRs." `prompts-score` reads what already happened — every event since
ticket 0002 carries the slug, phase, and timestamp; every run carries
the cost. Group by the `PROMPTS_SHA` pin in effect at the run's
timestamp and you have a per-revision report card. Smallest unit of
value: one command, one table, one decision ("revert the last prompt
edit; it doubled the send-back rate").

### Stakeholder
This is the moat-deepening ticket. The kit's claim — "the loop reads
LESSONS and gets better" — is currently unfalsifiable. There is no
score; there is only vibes. `prompts-score` codifies the claim into
something an operator can graph over time and something a sibling
project's operator can compare against. It is the first metric that
makes prompt edits a measurable change rather than a leap of faith.
Combined with `replay` (0021) for forward testing and `prompts-diff`
(0013) for naming the change, it closes the prompt-edit feedback
loop: see the diff, predict via replay, ship, score after a week.

### User (operator after a week of prompt edits)
Types `fleet prompts-score agent-fleet --since 14d`. Sees:

```
PROMPT REVISIONS for agent-fleet (last 14d, 23 runs)

SHA      DATE        RUNS  PRS   SENDBACK%  DRAFTS  HEAL/PR  INFRA-FLK  $/PR
─────────────────────────────────────────────────────────────────────────────
8a20547  2026-05-22   8     5    20.0%      1       0.4      0          $0.31
fe8015c  2026-05-26   9     6    16.7%      1       0.5      1          $0.34
a91c204  2026-05-29   6     3    33.3%      2       1.3      0          $0.52  ← current

trend: send-backs up 16pp, heal/PR up 0.8 since pin a91c204 (3d ago).
       cost per merged PR up $0.18. consider `fleet prompts-diff
       --since fe8015c` to read the change.

7-day baseline: 18% send-backs, 0.45 heal/PR, $0.32/PR.
```

They see the numbers got worse after the latest pin. They open
`prompts-diff --since fe8015c`, read the change, and either revert
the offending line or tighten the prompt further. The "did my edit
help?" question now has a 5-second answer instead of a week-long
guess. Confidence in editing prompts goes from "I hope" to "I see."

### Growth
"You can grade your own prompts against real history" is the kind of
property that turns the kit from "an autonomous coding loop" into "a
small platform for governed agent change." A friend running their own
loop sees the table and immediately understands: edits are
hypotheses; the kit measures them. That re-framing is what makes a
toolkit shareable to operators who would otherwise build their own.

## Acceptance criteria

Each box maps 1:1 to a test scenario in `tests/prompts-score.sh`.

- [ ] `bin/fleet prompts-score <slug>` (no flags) defaults to
      `--since 7d`, exits 0, prints a table with columns:
      `SHA | DATE | RUNS | PRS | SENDBACK% | DRAFTS | HEAL/PR | INFRA-FLK | $/PR`.
      The current revision is marked with a trailing `← current` cell.
      The test fixtures a synthetic `events.jsonl` + `runs.jsonl` with
      runs across three known SHAs and asserts the table renders
      three rows.
- [ ] Grouping by `PROMPTS_SHA`: each runs.jsonl row is tagged with
      the SHA in effect at its `ts_start`. The mapping comes from
      scanning `events.jsonl` for `prompts_drift` events (ticket 0005)
      which already record `pinned` + `actual` SHAs, AND from a new
      event `prompts_pin_changed {old, new}` emitted by
      `lib/install.sh` when it rewrites the `PROMPTS_SHA=` line in a
      manifest. Test fixtures both event flavors and asserts the
      derived per-run SHA assignment matches the timeline.
- [ ] Metrics computed per row:
      - `RUNS` = count of runs.jsonl rows in that SHA's window
      - `PRS`  = count of `pr_opened` events in that window
      - `SENDBACK%` = `lesson_draft_emitted` count divided by `PRS`
        (ticket 0022's event is the canonical send-back signal),
        rendered as `<n>.<f>%` with one decimal
      - `DRAFTS` = `lesson_draft_emitted` count (the absolute number,
        for operators who want to know promotion debt)
      - `HEAL/PR` = count of `gate_failed` events divided by `PRS`,
        rendered to 1 decimal
      - `INFRA-FLK` = count of `infra_flake_rerun` events
      - `$/PR` = sum of `total_cost_usd` in window divided by `PRS`,
        rendered `$N.NN`
      Test asserts each metric to within rounding tolerance on the
      synthetic fixture.
- [ ] `--since <Nh|Nd>` parsing reuses `digest_parse_since` from ticket
      0012 (already exists in `bin/fleet` ~line 1133). Invalid values
      print `prompts-score: invalid --since "<v>" (use Nh or Nd)` and
      exit 2. The test covers both valid (`24h`, `30d`) and invalid
      (`30`, `30m`, `forever`) forms.
- [ ] `--json` flag prints one JSON object per revision instead of the
      human table. Schema:
      `{"sha": "...", "date": "YYYY-MM-DD", "runs": N, "prs": N,
      "sendback_rate": 0.20, "drafts": N, "heal_per_pr": 0.4,
      "infra_flake": N, "spend_per_pr": 0.31, "is_current": true|false}`.
      Output is one JSON per line (JSONL). The test pipes the output
      through `node -e 'JSON.parse(...)'` per line to assert
      well-formedness.
- [ ] `--slug` filter applied via the leading positional argument.
      Without a slug, `prompts-score` errors out: `prompts-score:
      missing <slug> argument` (exit 2). The test asserts the error
      string and exit code. (Unlike `digest` which iterates every
      project, `prompts-score` is intentionally per-slug — the
      `PROMPTS_SHA` line is per-project, so cross-project mixing
      would be lying.)
- [ ] Trend line below the table: when ≥2 revisions present, the
      command prints a single trailing line summarizing the delta
      between the previous and current revision (sendback% delta in
      pp, heal/PR delta, $/PR delta). When fewer revisions exist, the
      trend line is suppressed. Test fixtures both cases.
- [ ] When `events.jsonl` is missing or empty, the command prints
      `prompts-score: no events found for <slug> (cache: <path>)` to
      stderr and exits 0 (NOT 1 — absent telemetry is not an error,
      it's a fresh project). Test asserts the message and exit code on
      an empty cache fixture.
- [ ] Telemetry: a new event `prompts_pin_changed {old, new}` is
      added to AGENTS.md § Telemetry. `lib/install.sh` emits it once
      per install when the manifest's `PROMPTS_SHA=` differs from the
      installed copy's. The event carries `phase=install`. Test
      fixtures a manifest swap and asserts the event lands in
      events.jsonl with the right `old`/`new` payload.
- [ ] `tests/prompts-score.sh` covers all nine boxes with
      `$HOME/.local/bin` stubs (per LESSONS 2026-05-26). The fixture
      writes synthetic events.jsonl + runs.jsonl + a sequence of
      `prompts_pin_changed` and `prompts_drift` events spanning three
      SHAs across 14 days. Asserts table rendering via byte-exact
      comparison against a checked-in golden file
      (`tests/fixtures/prompts-score.golden.txt`) so any rendering
      regression fails CI.

## Out of scope

The dev agent will NOT do these even if they seem related.

- Auto-rolling back a regressing prompt revision. The whole point is
  operator-in-the-loop — the score informs, the operator decides.
  Auto-revert on a metric threshold is a future ticket and would
  need `fleet rollback` (0017) extended to prompt commits.
- Cross-project scoring (`fleet prompts-score --all`). Each project
  pins its own SHA; aggregating across projects would conflate
  different prompts. v1 is per-slug. A future ticket can render a
  meta-table.
- Scoring the LESSONS.md additions themselves. Lessons live outside
  prompts/ and don't appear in `PROMPTS_SHA`. They influence prompts
  at runtime but are not the unit of measure here.
- A web/HTML rendering. JSONL output is the contract; fleet-control
  can render later. Adding a chart this round bloats the ticket.
- Scoring against the kit-wide canonical `PROMPTS_SHA` (the value
  `bin/fleet prompts-sha` prints). The score uses the per-project
  pin because that's what was running when the runs happened. If the
  pin lags behind the kit, that's `prompts_drift` (ticket 0005) and
  outside this ticket's scope.
- A "send the score to ntfy / email" pipe. Output is stdout; the
  operator pipes themselves. v1 is the data, not the notification.

## Engineering notes

- `bin/fleet` — new `prompts_score()` function and a dispatcher case
  alongside `replay()` (line ~2433) and `prompts_diff_cmd()` (line
  ~346). Heavy lift is awk over events.jsonl + runs.jsonl. Reuses
  `digest_parse_since` (line ~1133), `digest_iso_to_epoch` (line
  ~1150), `digest_spend_since` (line ~1162), and the JSON-line awk
  patterns from `digest_event_count_since` (line ~1195).
- `bin/fleet` — `prompts_score_assemble_timeline()` reads
  `events.jsonl` once, extracts `prompts_pin_changed` events (the
  authoritative pin-change record from this ticket) and falls back
  to `prompts_drift` events when no `prompts_pin_changed` exists for
  a window's start. Output is an awk array `sha_at[epoch] = sha`
  consumed by the second pass over runs.jsonl.
- `lib/install.sh` — at the top of the manifest-rewrite block, read
  the existing `PROMPTS_SHA=` (if any), compute the new one via
  `fleet_prompts_sha`, and if they differ call `fleet_emit_event
  prompts_pin_changed "old=$old" "new=$new"`. Set
  `FLEET_PHASE=install` first so the event carries the right phase.
  Single-shot per install — guarded by writing the new SHA only after
  the event lands.
- `lib/common.sh` — no API changes; `fleet_emit_event` and
  `fleet_log_init` already accept arbitrary phase strings. The new
  `phase=install` value is purely a label.
- AGENTS.md § Telemetry — append `prompts_pin_changed {old, new}` in
  the same style as the existing entries (one line, payload spec,
  the runner that emits it, when).
- `prompts/CHANGELOG.md` — NOT touched by this ticket directly.
  `lib/install.sh` is not under `prompts/`, so the
  `check-prompts-changelog.mjs` gate does not fire on its own. But
  this ticket COULD add a `2026-05-30 — install.sh emits
  prompts_pin_changed` entry as documentation; defer that decision
  to the dev agent — note the option, don't mandate.
- `tests/prompts-score.sh` — `mktemp -d` fixture under `$HOME`,
  stubbed `git rev-parse` only if needed (the prompts SHA is read
  from kit `prompts/`; the test bypasses by hand-writing the
  events.jsonl with pre-computed SHA strings). Asserts via golden
  file. The golden lives at `tests/fixtures/prompts-score.golden.txt`.
  Run-time budget: <10s.
- New deps: none. Pure shell + awk + the existing JSONL parsing
  helpers.
- Public API: additive — `bin/fleet prompts-score` is a new
  subcommand, `prompts_pin_changed` is a new event type. No
  `fleet_*` signature changes.
- BREAKING flag: NO. Affirm "no `fleet_*` signature changes" in the
  PR body.
- Reinstall required: YES — `lib/install.sh` changes. PR body MUST
  include `Reinstall: all projects`. The new event begins to fire
  only after each project re-runs install.sh, which is the natural
  trigger anyway (install.sh is what changed the pin).
- Per-project compat: projects that have NEVER run the updated
  install.sh see only `prompts_drift` events in their timeline and
  the fallback path covers them. The test fixtures that case.
- This ticket compounds 0013 (CHANGELOG names changes) + 0021
  (replay tests a future change) + 0022 (sendback emits drafts).
  Together they form a complete prompt-governance loop:
  diff → predict → ship → score.

## Implementation log

- 2026-05-30 — implementation-dev: branch `feat/0024-fleet-prompts-score`
  opened. Plan: write `tests/prompts-score.sh` first against the synthetic
  fixture, then implement `prompts_score()` in `bin/fleet` reusing
  `digest_parse_since`, `digest_iso_to_epoch`, and the JSONL awk patterns
  from `digest_event_count_since`; add the `prompts_pin_changed` emit in
  `lib/install.sh` guarded by an old/new SHA diff; append the new event to
  AGENTS.md § Telemetry.
