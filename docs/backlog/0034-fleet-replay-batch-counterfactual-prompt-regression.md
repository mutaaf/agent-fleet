---
id: 0034
title: fleet replay --batch <since> grades current prompts against the last N merged PRs
status: groomed
priority: P2
area: governance
created: 2026-06-05
owner: gtm-innovation
---

## User story

As an operator who just edited `prompts/review.prompt.md` to tighten
the reviewer's "every src/ change needs a test" rule and is about to
ship the prompt change, I want `bin/fleet replay <slug> --batch
--since 14d [--phase review|ship]` to walk every agent-merged PR in
the window, replay each through the CURRENT prompts in dry-run, and
render a matrix of `would-have-approved / would-have-rejected /
would-have-shipped-differently` per PR — with the per-PR rationale
quoted in the JSON output — so that I can SEE the semantic delta of
my prompt edit against real historical behavior before letting the
new prompt fire on the live loop, instead of finding out tomorrow
that 7 of yesterday's 8 PRs would have been rejected.

## Why now (four lenses)

### Product Owner
Ticket 0021 shipped `fleet replay --pr <N>` — one PR, one verdict.
The operator's actual question is never about one PR; it is about a
WINDOW: "did my prompt edit break the loop's judgment on the last
week of real work?" Today the answer requires running replay 7-20
times by hand and reading verdicts one by one. The smallest unit of
value is one command that does the loop and renders a single matrix:

```
fleet replay agent-fleet --batch --since 14d --phase review

PR    TITLE                                    PAST    DRY-RUN  DELTA
#58   ticket 0030: fleet resume                MERGED  sign-off  =
#56   feat/0029 fleet provenance pr forensics  MERGED  reject    !
#52   fleet weekly ROI rollup                  MERGED  sign-off  =
#48   ticket 0026 fleet inbox                  MERGED  reject    !
...

summary: 9/12 unchanged, 3 DELTA (reject ←from→ sign-off)
verdict: WARN — 25% of past good PRs would now be rejected.
         review PRs #56, #48, #41 below before shipping prompts/.
```

Subtraction: the operator stops having to script the loop themselves.
The verdict line encodes the ship decision; `WARN` ≥10% delta, `FAIL`
≥30%, `OK` <10%. The `--json` output is consumed by `fleet prompts-
score` (ticket 0024) as a richer signal than the per-event tally it
has today.

### Stakeholder
This is moat-deepening of a kind genuinely no other autonomous-agent
kit ships: counterfactual prompt regression detection. Today's prompt
edits ship on a CI gate (`shellcheck`, `validate`) that cannot
measure semantic regression — the same blind spot 0021 partially
filled for one PR at a time. `--batch` turns the single-PR oracle
into a regression test SUITE for prompt changes, run on demand,
zero cost (dry-run mode is tool-locked — no commits, no merges, just
the claude verdict). The output IS the proof that the prompt edit is
safe: 9/12 unchanged, 3 reasoned deltas, operator decides. It is the
shape every successful "policy as code" workflow takes (terraform
plan, opa eval, semgrep --baseline) — replay the policy against the
historical corpus, count regressions, gate the change. The kit
already has the substrate (`runs.jsonl`, `events.jsonl`, `gh pr
view` / `gh pr diff`, the existing `replay()` dispatcher); this
ticket composes them.

### User (operator after editing prompts/review.prompt.md)
Types `fleet replay agent-fleet --batch --since 14d`. Sees the
matrix above. Notices PR #56 (provenance) was the most complex
recent merge, and the dry-run reject reads:

```
#56 rationale (current review prompt):
  The diff touches lib/common.sh (the public shell API) without a
  BREAKING: line in the PR body. AGENTS.md § Hard NOs requires
  BREAKING for any change to the five public fleet_* signatures.
  REJECT.
```

Operator inspects PR #56 by hand: the diff added an ADDITIVE helper
to common.sh, not a signature change. The new prompt is too strict;
the operator backs out the edit. The bad prompt never reached the
live loop. Net: one command, ~3 minutes (12 PRs × ~15s each in
dry-run claude --print), zero ship-time damage.

### Growth
Every operator past week 4 has the prompts-editing fear:
"if I tweak this, will I break the loop?" Today the answer is "yes,
possibly — and you'll find out by watching tomorrow's PRs go
sideways." `--batch` turns the fear into a quantified, fixable
signal. Friends running their own loop pick this up immediately
because the alternative (no regression detection on prompts) is
the most-stressful part of operating an autonomous agent. The
output is also a beautiful screenshot for the README: a real
matrix from a real fleet, showing the safety net catching a real
prompt mistake. Compounds 0021 (the single-PR replay primitive),
0024 (`fleet prompts-score` consumes the batch output as a
richer per-revision metric), and 0029 (`fleet provenance` is the
PR-level analogue; replay --batch is the prompt-level analogue).

## Acceptance criteria

Each box maps 1:1 to a test scenario in `tests/replay-batch.sh`.

- [ ] `bin/fleet replay <slug> --batch --since <Nh|Nd>` walks
      every agent-merged PR in the window (matched by the
      branch-prefix list from `AGENTS.md § Agent parameters`:
      `feat/`, `chore/gtm-`, `eng/`), replays each through the
      current prompts in dry-run (`AGENT_DRY_RUN=1` semantics
      reused from ticket 0010), and prints the matrix table
      shown in the User lens above. Exits 0 on OK, 1 on WARN
      (≥10% delta), 2 on FAIL (≥30% delta). Test fixtures three
      synthetic merged PRs (one sign-off-unchanged, one
      reject-from-sign-off, one sign-off-from-reject) and
      asserts the verdict line via a checked-in golden
      `tests/fixtures/replay-batch.text.golden.txt`.
- [ ] `--phase review` (the default) replays the review prompt.
      `--phase ship` replays the ship prompt (asks "what would
      today's ship runner have done with this ticket?"). Both
      branches must work; the default is `review` because
      review is the higher-stakes prompt to regress. Test
      asserts both phases.
- [ ] `--since` parses via `digest_parse_since` (bin/fleet
      ~1140). Invalid value: `replay --batch: invalid --since
      "<v>" (use Nh or Nd)` to stderr, exit 2.
- [ ] `--limit N` caps the number of replayed PRs (default 20,
      max 50). Prevents a 14d window with 100 PRs from running
      the operator's machine for 30 minutes. Test asserts a
      window with 30 PRs and `--limit 10` replays exactly 10
      (the most-recent-first).
- [ ] Each per-PR replay reuses the EXISTING `replay()` helper
      stack from ticket 0021 — same prompt synthesis, same
      `claude --print --allowedTools none`, same dry-run cost
      accounting on `runs.jsonl`. The batch path is a LOOP
      around `replay_one_pr` (the extracted helper). Test
      asserts that `runs.jsonl` gains one row per replayed PR
      (each with `phase=replay`, the per-PR cost recorded).
- [ ] DELTA classification: a PR's `PAST` outcome is its
      historical merge state (`MERGED` if `gh pr view` shows
      `state:MERGED`, `REJECTED` if the PR was closed
      unmerged after a `--request-changes` review). Its
      `DRY-RUN` outcome is the verdict the current prompt
      returns. DELTA is `=` when they match, `!` when they
      differ. Summary line counts only the `!` rows. Test
      asserts the classification across the three fixture
      PRs.
- [ ] `--json` emits one JSON object per PR row plus one
      summary object. Shape:
      `{"pr":N,"title":"<one-line>","past":"<merged|rejected>",
      "dry_run":"<sign-off|reject>","delta":"=|!",
      "rationale":"<first-200-chars-of-verdict>"}` per row,
      then `{"summary":true,"replayed":N,"deltas":M,
      "verdict":"<OK|WARN|FAIL>","window":"<14d>"}`. Parsed
      via `node -e 'JSON.parse(...)'`. Test asserts the full
      document.
- [ ] No agent-merged PRs in the window: `replay --batch: no
      PRs matched in the last <window> for slug=<slug>` to
      stderr, exit 0 (this is not an error — a quiet 14d is a
      valid signal). Test asserts the message and exit code.
- [ ] `--since 1h` on a window with no PRs produces the
      empty-window message; `--since 365d` on a fixture with
      30 PRs and `--limit 10` replays 10 most-recent. Both
      asserted.
- [ ] DRY-RUN strictly respects ticket 0010: no `gh pr
      review`, no `gh pr merge`, no commits, no pushes. Test
      asserts via stub recording that NO gh-mutating verb
      and NO `git push` was invoked across the batch.
- [ ] Help: `bin/fleet replay --help` (the existing help
      block) gains a `--batch`, `--limit`, `--since` line.
      Test asserts via `grep -qF -- "$kw" "$help_out"` per
      LESSONS 2026-05-30. The help block STILL ends with
      `exit 0` per LESSONS 2026-06-01.
- [ ] `tests/replay-batch.sh` covers all 11 boxes using
      `$HOME/.local/bin` stubs (per LESSONS 2026-05-26) for
      `gh`, `claude`, `git`. The `claude` stub returns a
      seeded verdict per PR (the test pre-stages the
      verdicts so the batch loop is deterministic). Per
      LESSONS 2026-05-27, the test uses `cp` for
      backup/restore. Run-time budget: <15s (more than the
      usual <10s because the batch loop runs claude 3+
      times per test case).

## Out of scope

The dev agent will NOT do these even if they seem related.

- Auto-blocking a prompts/ PR when `--batch` reports `WARN`
  or `FAIL`. The CI gate already runs shellcheck + validate;
  adding a `prompts-regression` gate that requires a
  `--batch` run is plausible but is its own ticket (needs
  CI-side cost budgeting, batch caching, etc.). v1 is
  operator-run; CI integration is v2.
- Per-PR verdict CACHING. A 14d batch run today will replay
  the same 12 PRs every time. A future ticket can persist
  per-PR verdicts keyed by `(pr_sha, prompts_sha)` so
  unchanged-prompts re-runs are instant. For v1 the
  operator runs it on demand and pays the dry-run cost
  (still cheaper than a real ship cycle).
- Replaying NON-agent-merged PRs (human PRs, revert PRs).
  The point is to grade the LOOP's judgment against its
  own work; human PRs are not part of the regression
  corpus. Out of scope.
- A "diff the rationale" mode that compares the OLD prompt's
  rationale (from the historical review body in
  `events.jsonl` / `gh pr review --list`) against the NEW
  prompt's rationale verbatim. Useful but expensive;
  belongs in a follow-up.
- A launchd schedule. Like `replay --pr`, this is
  operator-run on the prompt-edit branch before merging.
- Cross-project batch (`fleet replay all --batch`). v1 is
  one slug; cross-project belongs in a follow-up once a
  single-project batch has shipped and proven the shape.

## Engineering notes

Files / patterns the dev should touch. Specific enough that the dev
doesn't have to re-discover the architecture.

- `bin/fleet` — extend the existing `replay()` dispatcher
  (line ~4391) to recognize `--batch`. When `--batch` is
  present, route to a new `replay_batch()` helper instead of
  the existing single-PR path.
- `bin/fleet` — REFACTOR (minimal-touch): extract the
  per-PR replay body from `replay()` into
  `replay_one_pr <slug> <pr-number> <phase>` echoing one
  JSON line `{pr, title, past, dry_run, delta, rationale}`.
  The existing single-PR `replay()` path then becomes a
  one-call wrapper that renders the single-line output.
  Per P-1 the extraction is purely mechanical; no semantic
  change to the single-PR path. Test that the existing
  `tests/replay.sh` continues to pass byte-identical
  output (regression check).
- `bin/fleet` — `replay_batch()` enumerates merged PRs in
  the window via `gh pr list --state merged --search
  "merged:>=<iso> head:feat/ OR head:chore/gtm- OR
  head:eng/" --json number,title,headRefName,closedAt
  --limit <limit>`. Iterates, calls `replay_one_pr` for
  each, accumulates the JSON rows, renders the matrix.
- `bin/fleet` — `replay_batch_render_text` and
  `replay_batch_render_json` output helpers. Per LESSONS
  2026-05-28 (printf leading-dash trap), every `printf` of
  a title or branch ref uses `printf -- '%s' "$val"`.
  Per LESSONS 2026-06-01 (awk -v multiline trap), no
  rationale value (which CAN be multi-line) goes through
  `awk -v` — accumulate rationales in a tmp file and read
  back via `getline line < file`, same fix as ticket
  0028's `lessons_promote_insert_under_section`.
- `bin/fleet` — `replay()` end-state must be `exit 0`
  (OK), `exit 1` (WARN), or `exit 2` (FAIL / usage error)
  on every code path per LESSONS 2026-06-01 (dispatcher
  fall-through trap). The existing `replay()` already
  ends with `exit 0`; preserve that for the single-PR
  branch.
- `bin/fleet` — help banner block: append `--batch`,
  `--limit`, `--since` to the existing `replay` help.
  README "Daily ops" code block gets the same line.
- `lib/common.sh` — NO changes. `replay --batch` is a
  pure consumer of `fleet_run_claude` in dry-run mode
  (existing) and `gh pr list` (existing). NO new
  helpers, NO `fleet_*` signature changes.
- `lib/install.sh` — NO changes.
- `prompts/` — NO changes. The prompts under test are
  read fresh from the working tree on each replay (same
  shape as `replay --pr` from ticket 0021). No `Reinstall:
  all projects` line needed because `lib/` and `prompts/`
  are untouched in THIS PR.
- `tests/fixtures/replay-batch/` — NEW directory under
  `tests/fixtures/` holding three synthetic PR fixtures
  (one each for sign-off-unchanged, reject-from-sign-off,
  sign-off-from-reject) and a stubbed `gh pr list` JSON
  response. The `claude` stub returns a per-PR seeded
  verdict so the batch loop is deterministic.
- `tests/replay-batch.sh` — top of file mirrors
  `tests/replay.sh`: stub `gh`, `claude`, `git` under
  `$HOME/.local/bin` (`$HOME=$TMP/home` per LESSONS
  2026-05-26). The `runs.jsonl` assertion reads the cost
  rows.
- New deps: none. Pure shell + awk + existing
  `digest_parse_since` (bin/fleet ~1140), `fleet_run_
  claude` (common.sh) in dry-run mode, `gh pr list /
  view / diff`.
- Public API: additive — `--batch`, `--limit` are new
  flags on the existing `replay` subcommand. NO new
  event types (the per-PR runs still write `runs.jsonl`
  rows the existing way; no events.jsonl writes from
  this command). NO `fleet_*` signature changes.
- BREAKING flag: NO. PR body affirms "no change to the
  five public `fleet_*` signatures," "no new event
  types added," and "the single-PR replay path is
  byte-identical (regression-tested via the existing
  tests/replay.sh)."
- Reinstall required: NO. `lib/` and `prompts/` are
  untouched.
- LESSONS to defend against: 2026-05-26 (`tail` shadow
  — `replay_batch` is namespaced, no collision).
  LESSONS 2026-05-26 (PATH reset — stubs go in
  `$HOME/.local/bin`). LESSONS 2026-05-27 (`$(cat)`
  trap — fixture reads use `cp`). LESSONS 2026-05-28
  (printf leading-dash trap — every title/branch/slug
  goes through `printf -- '%s'`). LESSONS 2026-05-30
  (`grep -F --` flag trap — help text uses `grep -qF
  --`). LESSONS 2026-06-01 (awk -v multiline trap —
  rationales go through a tmp file, NEVER `awk -v
  rationale="$rationale"`). LESSONS 2026-06-01 (`grep
  -c file || echo 0` double-print trap — counts use
  `awk … END { print n+0 }`). LESSONS 2026-06-01
  (dispatcher fall-through trap — `replay()` ends with
  explicit `exit N` on every path including the help
  block). LESSONS 2026-06-03 (UTF-8 sign-extension
  trap — the rationale renderer uses the
  `provenance_json_escape` UTF-8-safe pattern, not
  the bare `doctor_json_escape`).
- This ticket compounds 0010 (dry-run mode is the
  substrate), 0021 (single-PR replay is the
  primitive being looped), 0024 (`fleet prompts-
  score` is the natural consumer of `--json` batch
  output as a richer per-revision signal), 0029
  (`fleet provenance` is the PR-level forensic
  analogue; replay --batch is the prompt-level
  preview analogue). Per P-1 the diff is small:
  ~250 lines of `replay_batch*` helpers + the
  ~100-line extraction of `replay_one_pr` from
  the existing body + ~300 lines of test + one
  README line + one help-text line.

## Implementation log

(Appended by the implementation-dev agent during execution.)

- YYYY-MM-DD — branch `feat/0034-...` opened
- YYYY-MM-DD — failing test added in `tests/replay-batch.sh`
- YYYY-MM-DD — PR #N opened, CI [state]
- YYYY-MM-DD — merged to main
