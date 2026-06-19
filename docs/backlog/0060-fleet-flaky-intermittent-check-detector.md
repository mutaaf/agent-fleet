---
id: 0060
title: fleet flaky surfaces CI checks that have failed-then-passed without a code change so the kit stops mis-attributing infra noise to ticket regressions
status: in-progress
priority: P1
area: observability
created: 2026-06-19
owner: gtm-innovation
---

## User story

As a fleet operator who has watched cross-LESSONS accumulate at least
SEVEN distinct "infra flake" reports in the last 6 weeks (CourtIQ
2026-05-25 Supabase port-bind on docs-only PR, CourtIQ 2026-05-26
account-suspended at `actions/checkout`, CourtIQ 2026-06-08 Supabase
CLI rate-limit, CourtIQ 2026-06-14 service_role grants regression on
seeded e2e, agent-fleet 2026-05-26 GitHub Actions silent-fire on PR
#7, plus the 4-pattern catalog already in `lib/heal-catalog.sh`) —
who knows the loop has 0020's `infra_flake_rerun` event for the
in-flight detection — but who has NO ROLLUP view of "which CI check
across my fleet has been the FLAKIEST in the last N days, and is
the kit's `heal-catalog.sh` keeping up with what's actually
breaking?" — I want `bin/fleet flaky` to walk every slug's
events.jsonl AND `gh run list --json` per slug, classify each
gating-check failure as either "passed on a follow-up run with no
code change" (flake) or "passed only after a heal commit"
(regression), and rank the gating-check NAMES that flake most
often, so the heal-catalog grows in response to evidence rather
than reacting one PR at a time.

## Why now (four lenses)

### Product Owner
The kit's stance on infra flakes is currently:
RE-RUN-then-classify-LATER. 0020's `fleet_match_infra_flake`
classifies a failing job log against a 4-pattern catalog
(`actions_silent`, `supabase_port_bind`, `account_suspended`,
`gh_graphql_502`) and emits `infra_flake_rerun`, and the
operator manually grows the catalog when a new pattern hits.
There is NO surface that asks the inverse question: "across my
fleet, which CHECK NAME has been the most expensive flake
source AND does the kit's catalog cover it yet?" Cross-LESSONS
shows the answer is "no, not for service_role grants, not for
Supabase CLI rate-limits, not for date-substring false
positives". Every uncovered flake costs the operator at least
one mis-attributed heal cycle ("the loop thinks my code broke
when actually Supabase broke") — exactly the symptom the
brief warns against: "the fleet must self-pause when it's
broken, not keep burning tokens against red CI." The smallest
meaningful unit of value is one ranked list:

```
$ fleet flaky --since 30d
flaky — 47 failed gating-check runs across 4 slugs in 30d

  rank  check name           failures  flaked  in-catalog?  next action
  1     e2e-tests            12        9 (75%) partial      add: service_role_403
  2     unit-tests            8        6 (75%) yes          —
  3     lint                  4        4 (100%) yes          —
  4     install-supabase-cli  3        3 (100%) NO          add: supabase_cli_rate_limit
  5     check-supabase-port   2        2 (100%) yes          —

  flake budget burned: ~14 heal cycles, ~$0.62 (estimated)
  recommendation: 2 new catalog entries pay for themselves in <2 weeks
```

Subtraction: the operator stops manually grepping every red
CI run to figure out if the kit needs a new pattern. Per
P-5 (operator confidence over feature richness), the win is
the heal-catalog evolving from EVIDENCE, not anecdote.

A check that "flaked" means: the same SHA's run-with-the-
same-check went from `failure` to `success` between two
runs that share the same commit SHA (i.e. the operator or
the loop reran without changing code, and the second run
passed). A check that "regressed" means: the check went
from `failure` to `success` only after a new commit landed
on the branch. The flake-to-failure ratio is the actionable
signal.

The `next action` column maps each flaky check to a SUGGESTED
catalog entry name — the operator graduates it by adding one
line to `lib/heal-catalog.sh` (and one fixture log to
`tests/heal-infra-flake.sh` per the catalog convention from
0020). v1 emits the suggestion; v2 (separate ticket) could
auto-PR the catalog entry.

### Stakeholder
This is **moat-deepening on the "self-pause when broken,
don't burn tokens" axis** — the kit's central safety
proposition. Per P-6 (telemetry is the source of truth),
`flaky` is a PURE READER over each slug's `events.jsonl`
(for `infra_flake_rerun` events AND `gate_failed` events)
PLUS one `gh run list --workflow=ci.yml --status=failure
--json` per slug PLUS one `gh run view <id> --json` per
candidate run. NO writes, NO `lib/common.sh` changes, NO
new event types. The diff is the per-check classifier
plus the catalog-coverage cross-reference plus the
renderer. ~330 lines.

The "flake-vs-regression" classifier IS the moat: it
codifies the cross-LESSONS distinction every project hits
into a single shared algorithm. Once stable, the
classifier informs three things: (a) the catalog grows
from evidence; (b) the heal-cap math (2 attempts) can
become CHECK-NAME-AWARE in v2 — a check known to flake
30% of the time gets one extra rerun before the cap
trips; (c) the operator's nightly read of `fleet flaky`
ranks where their kit/upstream-stack pain actually is.

Per LESSONS 2026-06-15 (per-day shellout inside per-slug
loops is O(window × N_slugs)) the per-slug walk batches
its `gh` calls: ONE `gh run list --limit 100 --json` per
slug, THEN ONE `gh run view <id> --json` per candidate
run. With 4 slugs and ~30 candidate runs total over 30d
that's 4 + 30 = 34 `gh` calls per invocation, ~8s. The
events.jsonl scan is ONE awk pass per slug.

Compounds 0020 (`infra_flake_rerun` event — the source
signal), 0037 (`fleet incident` — flaky is the rollup,
incident is the per-window forensic), 0019 (`fleet
overview` — reuses `overview_discover_slugs`), 0029
(`fleet provenance` — flaky cross-refs heal-catalog
entries to LESSONS entries via provenance's
catalog-walk), 0031 (`fleet atlas` — atlas is the
per-pattern frequency surface; flaky is the per-check-
name complement), 0058 (`fleet trends` — flaky is to
trends what `incident` is to `recap`: pattern-shape vs.
trajectory).

Differentiated from `fleet atlas` (0031): atlas ranks
catalog-MATCHED failure modes; flaky ranks CHECK NAMES
regardless of catalog coverage and SURFACES uncovered
flakes as new catalog candidates. Differentiated from
`fleet incident` (0037): incident is a window-shaped
narrative for ONE slug at one moment; flaky is the
fleet-wide check-name leaderboard over a window.

### User (operator at 9am Friday, reviewing the week)
The operator sits down Friday morning, runs `fleet flaky
--since 7d`. They see `install-supabase-cli` flaked 3
times this week with no catalog coverage. They open
`lib/heal-catalog.sh`, add a 4-line pattern entry for
`supabase_cli_rate_limit`, copy a real log into
`tests/heal-infra-flake.sh` as a fixture, push the
chore PR. Tuesday's first ship run hits a Supabase CLI
rate-limit; the new pattern matches; the loop re-runs
without a heal commit; the 2-attempt cap stays
unburned. The cycle of "operator notices recurring
flake → catalog grows → loop heals more cheaply" is
now a 4-line surface, not a one-off detective
exercise. Per P-5 the win is the kit growing
SMARTER each week from the evidence the operator
already has.

Sub-scenario: a HEALTHY week with zero classified
flakes — `fleet flaky --since 7d` prints `flaky —
0 failed gating-check runs in 7d (healthy CI)` and
exits 0. The empty list IS the answer.

Sub-scenario: `fleet flaky --json` returns the
classification as a machine-readable array so a
fleet-control browser widget can render a colored
table.

Sub-scenario: `fleet flaky --slug courtiq` restricts
the walk to one slug — useful when the operator is
already debugging that project.

### Growth
A peer evaluating the kit asks: "how does this thing
know when it's CI's fault vs. the code's fault?" Today
the answer is "0020's catalog and 2-attempt heal cap";
with `flaky`, the answer becomes "and there's a
weekly rollup that tells me when my catalog is
falling behind." That kind of self-aware tooling is
the difference between a kit that DEGRADES SILENTLY
as upstream stacks change vs. one that BENDS ITSELF
to fit. Per the brief's "the kit must self-pause
when it's broken, not keep burning tokens against
red CI" — flaky is the closed-loop completion: the
kit doesn't just self-pause, it also tells the
operator WHAT TO TEACH IT so the next bend doesn't
trip the pause.

## Acceptance criteria

Each box maps 1:1 to a test scenario in `tests/flaky.sh`.

- [ ] `bin/fleet flaky` is a new subcommand. With no flags
      and at least one discovered slug, walks every slug's
      events.jsonl + the last 30 days of `gh run list` per
      slug and prints the ranked table per the Product-
      Owner example. Exit 0 in both flake-found and all-
      healthy branches. Per LESSONS 2026-06-01 (dispatcher
      fall-through) every code path ends with `exit 0` /
      `exit 2`. Test asserts both branches via fixtures.
- [ ] The flake classifier: a check NAME is counted as
      "flaked once" when two `gh run` records exist for
      the SAME commit SHA + workflow + check name where
      the earlier one is `conclusion:failure` and the
      later one is `conclusion:success`. A check that
      went from failure to success only after a new
      commit landed on the branch counts as "regressed,
      not flaked." Test asserts via fixture with three
      shapes: (a) flake (same SHA, fail→pass), (b)
      regression (different SHA, fail→pass), (c) genuine
      failure (no later pass on any SHA on the branch).
- [ ] The catalog-coverage cross-reference reads
      `lib/heal-catalog.sh` and the slug's events.jsonl
      `infra_flake_rerun` events for the same window. A
      check whose failures match an `infra_flake_rerun`
      event's `pattern` field counts as `in-catalog?
      yes`. A check whose failures partially match (some
      runs caught, some not) counts as `partial`. A
      check whose failures NEVER produced an
      `infra_flake_rerun` event counts as `NO`. Test
      asserts all three branches via fixture.
- [ ] The `next action` column emits a SUGGESTED catalog
      entry name (snake_case, derived from the check
      name + the first 3-5 words of the failing log's
      title) for every row where `in-catalog? = NO` OR
      `partial`. Rows with `yes` print `—`. Per LESSONS
      2026-05-28 every printf of a check name goes
      through `printf -- '%s'`. Test asserts via fixture
      that the suggested name matches the expected
      `add: <snake_case_name>` shape.
- [ ] `bin/fleet flaky --since <window>` accepts
      `Nd|Nw` (days or weeks). Default is `30d`. Min
      is `1d`, max is `90d`. Values outside this range
      print `flaky: --since must be 1d-90d (got X)` to
      stderr, exit 2 per LESSONS 2026-06-01. Per
      LESSONS 2026-06-11 (BSD `date -j -f` fills missing
      time fields) any since-anchor math uses `date +%s`
      minus `days * 86400`, NO `date -j -f` involved.
      Test asserts the boundary values via `grep -qF
      -- "$kw"` per LESSONS 2026-05-30.
- [ ] `bin/fleet flaky --slug <name>` restricts the walk
      to one slug. Unknown slug: prints `flaky: slug
      <name> not found. discovered slugs: <list>` to
      stderr, exit 2. Missing `--slug` arg value: prints
      `flaky: --slug requires a value` to stderr, exit
      2. Test asserts both refusals.
- [ ] The `gh` calls are batched: ONE `gh run list
      --workflow=ci.yml --status=failure --limit 100
      --json
      databaseId,conclusion,headSha,workflowName` per
      slug, THEN ONE `gh run view <id> --json
      jobs,conclusion,headSha,workflowName,createdAt`
      per candidate run. Per LESSONS 2026-06-15 (per-
      day shellout inside per-slug loops is O(window ×
      N_slugs)) the test asserts via a `$HOME/.local/
      bin/gh` stub that records every invocation: the
      recorded count is exactly `N_slugs + N_candidate_runs`
      for the fixture, NOT `N_slugs × N_candidate_runs`.
- [ ] `bin/fleet flaky --json` emits one structured
      JSON object: `{"since": "<window>", "slugs":
      <int>, "total_failures": <int>, "rows":
      [{"check_name": "<str>", "failures": <int>,
      "flaked": <int>, "flake_pct": <number>,
      "in_catalog": "yes|partial|no", "next_action":
      "<str>" or null}, …], "estimated_cost_usd":
      <number>}`. JSON escape via `preflight_json_escape`
      per LESSONS 2026-06-03 called directly per
      LESSONS 2026-06-13 (no `*_json_escape` wrapper).
      Test asserts JSON validity via `node -e
      'JSON.parse(require("fs").readFileSync(0, "utf8"))'`.
- [ ] `bin/fleet flaky` is RESILIENT to a `gh` failure
      for one slug — if `gh run list` for slug A
      errors, that slug renders as `<slug>: gh failed
      — skipped` in the text output and appears under
      a top-level `errors` array in `--json` mode.
      Other slugs still walk. Exit 0. Test asserts via
      a stubbed `gh` that errors for one of the four
      fixture slugs.
- [ ] `bin/fleet flaky --help` prints USAGE mentioning
      `--since`, `--slug`, `--json`. Per LESSONS
      2026-05-30 test asserts via `grep -qF -- "$kw"
      "$help_out"`. Help block ends with `exit 0` per
      LESSONS 2026-06-01.
- [ ] `bin/fleet flaky` is a PURE READER. NO
      `events.jsonl` writes, NO `fleet_emit_event`
      calls, NO writes to `lib/heal-catalog.sh` (the
      suggested catalog entries are PRINTED, never
      WRITTEN — operator promotes manually). Test
      asserts every slug's `events.jsonl` byte size
      AND `lib/heal-catalog.sh` byte size is unchanged
      before and after invocation.
- [ ] `lib/common.sh` — NO changes. `prompts/` — NO
      changes. No new event types. Test asserts via
      `git diff --name-only main...HEAD -- lib/common.sh
      prompts/` returns empty.
- [ ] The flake/regression classifier uses a single
      awk pass per slug to group runs by `(headSha,
      workflowName, checkName)` and detect the
      fail→pass transition. Per LESSONS 2026-06-08
      `BEGIN { count = 0; flake_count = 0 }`. Per
      LESSONS 2026-06-08 IFS=$'\t' middle-empty-
      field uses `-` sentinel when the `checkName`
      column is empty (a job-level conclusion with no
      step-level checks). Per LESSONS 2026-06-15 the
      one awk pass replaces what a naive per-run-pair
      shell loop would do. Per LESSONS 2026-06-15
      (`match()` infinite-loop trap) any `while
      (match(s, /pat/))` regex use in the parser uses
      the CURSOR-based walk pattern, NOT
      `s = before repl after` recursion.
- [ ] `tests/flaky.sh` covers all 13 boxes above using
      `$HOME/.local/bin` stubs per LESSONS 2026-05-26
      (PATH reset). Fixture `events.jsonl`,
      `agents.config.sh`, `gh-runlist.json`, and
      `gh-runview.json` files live under
      `tests/fixtures/flaky/`. Per LESSONS 2026-05-27
      backup/restore via `cp` (NOT `$(cat)`). Counts
      use `awk … END { print n+0 }` per LESSONS
      2026-06-01. Per LESSONS 2026-06-08 every awk
      script declares `BEGIN { count = 0 }`. Per
      LESSONS 2026-06-11 since-window math uses
      `date +%s` minus `N * 86400`, no `date -j -f`
      involved. The clock is frozen via
      `FLEET_NOW_OVERRIDE`. Run-time budget: <10s.

## Out of scope

The dev agent will NOT do these even if they seem related.

- AUTO-WRITING the suggested catalog entry into
  `lib/heal-catalog.sh` and opening the chore PR. v1
  PRINTS the suggestion; the operator promotes it
  manually. Auto-PR is a v2 ticket and lives behind a
  manifest opt-in.
- WIDENING the 2-attempt heal cap based on check-name
  flake history (a "this check flakes 75%, allow 3
  reruns" policy). v1 is observational only. The
  cap-aware-of-flake-rate policy is a v2 with its own
  risk surface.
- AUTO-NOTIFYING (osascript / email / Slack webhook)
  when a new uncovered flake appears. v1 is operator-
  pulled.
- A `--include-non-gating` flag to count checks
  outside the AGENTS.md gating-checks list. v1 ranks
  ONLY gating checks (per the AGENTS.md contract);
  non-gating noise is by definition ignorable.
- A HISTORICAL TRAJECTORY view ("this check was 80%
  flaky last month, 30% this month, kit is fixing
  it"). That's 0058 `fleet trends` territory in v2;
  out of scope here.
- A CROSS-PROJECT pattern-mining surface ("this
  check name appears in 3 of 4 slugs as flaky"). v1
  ranks per slug + per check name; cross-project
  rollup is a v2 candidate.
- A `--diff` mode comparing two windows (this week
  vs last week). v1 is one window. Diffing is v2.
- WIRING flaky into `fleet inbox` (0026) so the
  operator's daily TODO list includes "promote new
  catalog entries." Composability is good but v1 is
  a standalone surface; the inbox integration is a
  follow-up ticket once flaky's recommendations are
  stable.
- CHANGING `lib/heal-catalog.sh`'s shape to be
  data-driven (e.g. JSON instead of shell case
  branches). v1 reads the existing shell shape via
  `grep` for the pattern tokens; refactoring the
  catalog is a separate ticket with its own
  install.sh / public-API risk.

## Engineering notes

Files / patterns the dev should touch.

- `bin/fleet` — new `flaky()` dispatcher function placed
  next to the existing `atlas()` block (find via `grep
  -n '^atlas()' bin/fleet`). Per LESSONS 2026-05-26
  (`tail` shadow) `flaky` does not collide with any
  coreutils binary.
- `bin/fleet` — eight helpers, ALL defined ABOVE the
  dispatcher block per LESSONS 2026-06-05 (forward-
  reference trap):
  - `flaky_discover_slugs` — wraps
    `overview_discover_slugs`, returns alphabetical
    order.
  - `flaky_read_catalog` — reads `lib/heal-catalog.sh`
    via `grep` for the catalog pattern tokens (e.g.
    `actions_silent`, `supabase_port_bind`); returns
    the set as a newline-separated list.
  - `flaky_list_runs` — ONE `gh run list
    --workflow=ci.yml --status=failure --limit 100
    --json …` per slug. Returns TSV
    `<slug>\t<run_id>\t<head_sha>\t<workflow>\t<check_name>\t<conclusion>`
    per LESSONS 2026-06-08 (sentinel `-` on empty
    columns).
  - `flaky_view_one_run` — ONE `gh run view <id>
    --json jobs,conclusion,headSha,workflowName,createdAt`
    per candidate run. Per LESSONS 2026-06-11 any
    since-window math uses `date +%s` minus `N *
    86400`, no `date -j -f` involved.
  - `flaky_classify_runs` — ONE awk pass per slug
    that groups runs by `(headSha, workflowName,
    checkName)` and detects the fail→pass transition
    (flake) vs fail→pass-only-on-newer-SHA
    (regression). Per LESSONS 2026-06-08
    `BEGIN { count = 0; flake_count = 0 }`. Per
    LESSONS 2026-06-15 (`match()` infinite-loop)
    any regex use in the parser uses the CURSOR-
    based walk pattern.
  - `flaky_suggest_catalog_name` — derives a
    snake_case suggested catalog entry name from
    the check name + the first 3-5 words of the
    failing log's title.
  - `flaky_render_text` — text formatter. Width via
    `preflight_visible_width` per LESSONS 2026-06-05
    (bash 3.2 LC_ALL caching). Per LESSONS 2026-05-28
    every printf of a check name goes through
    `printf -- '%s'`.
  - `flaky_render_json` — JSON formatter. JSON escape
    via `preflight_json_escape` per LESSONS 2026-06-03
    called directly per LESSONS 2026-06-13 (no
    `*_json_escape` wrapper).
- `bin/fleet` — `flaky()` end-state must be `exit 0`
  / `exit 2` on every code path per LESSONS 2026-06-01.
- `bin/fleet` — dispatcher block: `if [ "$CMD" =
  "flaky" ]; then flaky "$@"; fi`. Place AFTER the
  `atlas` dispatcher.
- `bin/fleet` — help banner block at the top of the
  file gets ONE new line: `fleet flaky rank CI
  checks that fail-then-pass without a code change`.
  README "Daily ops" code block gets the same line,
  appended via the same single-edit pattern that
  avoided LESSONS 2026-05-25.
- `AGENTS.md` — NO content change.
- `lib/common.sh` — NO changes.
- `lib/heal-catalog.sh` — READ ONLY; NEVER WRITTEN by
  this subcommand.
- `prompts/` — NO changes.
- `tests/fixtures/flaky/` — NEW directory holding
  four slug subdirs (`flake-covered`, `flake-uncovered`,
  `regression`, `healthy`) each with `events.jsonl`,
  `agents.config.sh`, `gh-runlist.json`, and
  `gh-runview.json`. A fifth `gh-fails` slug
  exercises AC #9's resilience.
- `tests/flaky.sh` — top of file mirrors
  `tests/atlas.sh` (closest prior reader; shares the
  catalog-walk pattern). Stubs live under
  `$HOME/.local/bin` per LESSONS 2026-05-26 (PATH
  reset). The `gh` stub records its invocation count
  + argv to a side file so AC #7's exact-count
  assertion fires. Counts use `awk … END { print
  n+0 }` per LESSONS 2026-06-01. Per LESSONS
  2026-05-27 backup/restore via `cp`. The clock is
  frozen via `FLEET_NOW_OVERRIDE`. Run-time budget:
  <10s.
- New deps: none. Pure shell + awk + Node (already
  a kit dep for JSON validation in the test).
- Public API: additive — `bin/fleet flaky` is a new
  subcommand. ZERO new event types, ZERO event
  writes, ZERO `lib/common.sh` changes, ZERO
  `prompts/` changes, ZERO `lib/heal-catalog.sh`
  writes.
- BREAKING flag: NO. PR body affirms "pure reader,
  no events.jsonl writes, no heal-catalog writes,
  no `fleet_*` signature changes."
- Reinstall required: NO. `lib/` and `prompts/` are
  untouched.
- LESSONS to defend against: 2026-05-25 (README
  "Daily ops" code block addition), 2026-05-26
  (`tail` shadow), 2026-05-26 (PATH reset — stubs
  in `$HOME/.local/bin`), 2026-05-27 (`$(cat)`
  trap — use `cp` for backup/restore in tests),
  2026-05-28 (printf leading-dash — every check-
  name printf goes through `printf -- '%s'`),
  2026-05-30 (`grep -F --` trap), 2026-06-01
  (`grep -c file || echo 0` double-print — counts
  use `awk … END { print n+0 }`), 2026-06-01
  (dispatcher fall-through — every code path ends
  `exit 0/2`), 2026-06-03 (UTF-8 sign-extension —
  JSON escape via `preflight_json_escape`),
  2026-06-05 (dispatcher forward-reference — all
  `flaky_*` helpers defined ABOVE the dispatcher),
  2026-06-05 (bash 3.2 LC_ALL caching), 2026-06-08
  (awk empty-string-key — `BEGIN { count = 0 }`),
  2026-06-08 (IFS=$'\t' middle-empty-field —
  sentinel `-`), 2026-06-11 (BSD `date -j -f`
  fills missing time fields with NOW-of-day —
  since-window math uses `date +%s` minus `N *
  86400`, no `date -j -f` involved), 2026-06-13
  (no `*_json_escape` wrapper around
  `preflight_json_escape` — called directly),
  2026-06-15 (per-day shellout inside per-slug
  loops is O(window × N_slugs) — the gh batching
  is one list-call per slug plus one view-call
  per candidate run; the events.jsonl walk is one
  awk pass per slug), 2026-06-15 (awk `while
  (match(s, /pat/)) { s = before repl after }`
  infinite-loop — any regex use in the parser
  uses the CURSOR-based walk pattern).
- This ticket compounds 0020 (`infra_flake_rerun`
  event — the source signal), 0037 (`fleet
  incident` — flaky is the rollup, incident is
  the per-window forensic), 0019 (`fleet
  overview` — reuses `overview_discover_slugs`),
  0029 (`fleet provenance` — flaky cross-refs
  heal-catalog entries to LESSONS entries),
  0031 (`fleet atlas` — atlas ranks catalog-
  matched failures; flaky ranks check names),
  0058 (`fleet trends` — flaky is the pattern-
  shape complement to trends' trajectory shape).
  Per P-1 the diff is small: ~330 lines of
  `flaky_*` helpers + ~290 lines of test + 5
  fixture slug subdirs + one help-text line +
  one README line.

## Implementation log

- 2026-06-19 — implementation-dev: started on `feat/0060-fleet-flaky`. Plan
  follows the engineering notes verbatim: eight `flaky_*` helpers defined
  ABOVE the dispatcher (LESSONS 2026-06-05); `gh` calls batched ONE list
  per slug + ONE view per candidate run (LESSONS 2026-06-15);
  per-(headSha, workflowName, checkName) groups detect fail→pass on same
  SHA (flake) vs fail→pass after newer SHA (regression); JSON escape via
  `preflight_json_escape` called directly (LESSONS 2026-06-03, no
  wrapper per 2026-06-13); window math uses `date +%s - N*86400`, no
  `date -j -f` (LESSONS 2026-06-11); all five fixture slug subdirs
  (`flake-covered`, `flake-uncovered`, `regression`, `healthy`,
  `gh-fails`) live under `tests/fixtures/flaky/`.
