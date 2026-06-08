---
id: 0038
title: fleet diff <slug-a> <slug-b> calls out cross-project ROI and posture divergence
status: shipped
priority: P2
area: observability
created: 2026-06-07
owner: gtm-innovation
---

## User story

As a fleet operator running both `agent-fleet` and `courtiq` on the
SAME pinned `PROMPTS_SHA` and noticing that `courtiq`'s send-back rate
is 3x `agent-fleet`'s over the last 14 days, I want `bin/fleet diff
<slug-a> <slug-b> [--since 14d]` to render a side-by-side table of the
two projects' ROI metrics (ships, merges, send-backs, spend, paused
hours, draft-promotion debt, atlas-pattern fires) AND a short
"DIVERGENCE:" section that calls out the metrics where one project is
≥2x the other — so I can SEE the divergence in 5 seconds and start the
investigation (is it the manifest, the AGENTS.md, a project-specific
prompt? prompts/CHANGELOG says the SHA is the same), instead of
running `fleet overview`, jotting numbers into a notepad, and doing
the math by hand.

## Why now (four lenses)

### Product Owner
`fleet overview` (ticket 0019) is the executive snapshot — one row
per project, every project. `fleet weekly` (0025) is the per-project
Sunday rollup. Neither answers the question that shows up the moment
the operator runs more than one project: **"why is one of these
behaving worse than the other?"** Today the operator's recovery is
`fleet overview` → copy two rows into a text file → manually
subtract → run `fleet prompts-score` per slug → compare → form a
hypothesis. The smallest meaningful unit of value is one command
that does the subtraction and surfaces the deltas worth chasing:

```
fleet diff agent-fleet courtiq --since 14d

METRIC                    agent-fleet    courtiq        Δ
ships                     19             21             +2 (+11%)
merges                    18             14             -4 (-22%)
sendbacks                 3              11             +8 (+267%)
spend ($)                 8.42           14.91          +6.49 (+77%)
paused hours              0              26             +26 (∞)
draft promotion debt      1              7              +6 (+600%)
prompts SHA               8a20547        8a20547        =
top atlas pattern (fires) gh_graphql_502:2 actions_silent:5 differ

DIVERGENCE (≥2x)
  sendbacks: courtiq is 3.7x agent-fleet
  paused hours: courtiq accrued 26h vs 0h
  draft promotion debt: courtiq is 7x agent-fleet
  top atlas pattern: differs (gh_graphql_502 vs actions_silent)

HYPOTHESES
  - prompts SHA matches — not a prompts regression.
  - courtiq's atlas pattern differs — investigate per-project
    CI flakes, not the kit.
  - courtiq's draft debt suggests reviewer is firing more
    `request-changes` — check courtiq/AGENTS.md § Hard NOs.
```

Subtraction: the operator stops doing arithmetic on per-project
snapshots and stops guessing which metric matters. The verdict
section names the ≥2x metrics and the hypothesis section names the
most likely root cause categories. Per P-5 (operator confidence
over feature richness), the win is removing the question "where do
I look first?"

### Stakeholder
This is moat-deepening of a kind no other autonomous-agent kit
ships: **cross-project divergence detection as a first-class read
of the event channel.** The kit's bet is that one operator runs N
projects through the SAME engine — and the value of that
uniformity COMPOUNDS only when divergence becomes visible as a
signal, not just as a guess. `fleet diff` is the surface that
turns "I have a feeling project A behaves differently" into a
quantified comparison with named hypotheses. Every signal the kit
emits today (`pr_opened`, `lesson_draft_emitted`, `ship_paused`,
`budget_block`, `infra_flake_rerun`, `prompts_pin_changed`) is a
per-project counter; `fleet diff` is the first reader to subtract
two of them and call out the deltas. The hypothesis section grounds
the comparison in actionable categories: prompts SHA match means
it is NOT a prompt regression; AGENTS.md drift is a per-project
spec divergence; atlas pattern difference is a CI/infra
divergence; manifest drift (`MAX_DAILY_USD`, `SELF_CANCEL`,
`QUIET_HOURS`) is an operator-policy divergence. Each hypothesis
points at a specific file in the project the operator can open.
The moat compounds because the answer to "why is one of these
worse" is now a 30-second exercise instead of a 30-minute one,
and the kit can be trusted at scale — N projects is no longer
N separate mental models.

### User (operator after `fleet overview` raises a red flag)
Reads `fleet overview` Tuesday morning. Notices `courtiq` is
THROTTLED while everything else is OK. Types `fleet diff
agent-fleet courtiq --since 14d`. Reads the divergence
section in 5 seconds: sendbacks 3.7x, paused hours 26 vs 0,
draft debt 7x. Reads the hypotheses: prompts SHA matches, so
not a prompts regression; atlas pattern differs, so investigate
courtiq-specific CI flakes. Opens courtiq's `agents.config.sh`
to check `MAX_DAILY_USD` — fine. Opens courtiq's `AGENTS.md §
Hard NOs` — finds one was tightened two weeks ago without an
accompanying prompts update. Loosens the Hard NO. Total
elapsed: 8 minutes from `overview` to root cause. Compare with
today's path: 45 minutes of mental subtraction, two false
leads, one ignored hypothesis. The divergence detector
collapses the investigation step from 45 minutes to 8.

### Growth
"Cross-project divergence detection" is a feature operators of
multiple repos beg for the moment they're running more than one
loop. Every kit's growth path crosses the moment the operator
goes from one project to two — and that is the moment uniformity
either pays off (`diff` makes the divergence cheap to spot) or
silently rots (every project drifts into its own snowflake). A
friend running two projects on the kit sees `fleet diff` in a
shared screenshot and immediately understands why the kit's
"plumbing is shared, semantics live in the repo" doctrine is
valuable — because divergence is now a SIGNAL, not a guess. The
README screenshot ("Why N projects on one engine?") becomes
trivially shareable. Compounds 0019 (`fleet overview` is the row-
per-project table; `diff` is the two-row-side-by-side detail),
0024 (`fleet prompts-score` is the per-project prompts-revision
grade; `diff` is the cross-project comparison), 0025 (`fleet
weekly`'s per-project rollup is the input metric), 0031
(`fleet atlas`'s per-pattern fires are the input).

## Acceptance criteria

Each box maps 1:1 to a test scenario in `tests/diff.sh`.

- [ ] `bin/fleet diff <slug-a> <slug-b>` (no flags) defaults to
      `--since 14d` and renders a header row `METRIC  <slug-a>
      <slug-b>  Δ` followed by exactly 8 metric rows in this
      order: `ships`, `merges`, `sendbacks`, `spend ($)`,
      `paused hours`, `draft promotion debt`, `prompts SHA`,
      `top atlas pattern (fires)`. The Δ column is the absolute
      delta + the percent change (or `=` if identical, `differ`
      if the two values are non-numeric and unequal, or `∞` if
      one side is zero and the other is not). Test fixtures
      two synthetic project event channels (one healthy, one
      with a sendback cluster + budget throttle) and asserts
      the assembled table against a checked-in golden
      `tests/fixtures/diff.text.golden.txt`.
- [ ] The DIVERGENCE section follows the table and lists ONE
      bullet per metric where the ratio
      `max(a,b) / max(min(a,b), 1)` is `>= 2.0` (the `max(...,
      1)` denominator prevents division-by-zero noise on
      tiny counts). For non-numeric metrics (`prompts SHA`,
      `top atlas pattern`), the bullet fires when the values
      differ. Empty divergence: prints `DIVERGENCE (>=2x)\n
      no metric diverges; the two projects are behaving
      similarly.` Test asserts a populated and an empty
      divergence case.
- [ ] The HYPOTHESES section follows DIVERGENCE and emits up
      to 4 short hypotheses keyed off the diverging metrics:
      `prompts SHA differs` → `prompts revision regression;
      run \`fleet prompts-score\` per slug`;
      `top atlas pattern differs` → `per-project CI/infra
      drift; investigate <slug>'s gh actions, not the kit`;
      `sendbacks diverge AND prompts SHA matches` →
      `per-project AGENTS.md drift; compare \`<slug-a>/
      AGENTS.md\` and \`<slug-b>/AGENTS.md\` § Hard NOs`;
      `spend ($) diverges AND ships are similar` →
      `per-project manifest drift; compare MAX_DAILY_USD
      and model choice in the two \`agents.config.sh\``.
      Empty hypothesis list (rare — happens when only
      non-keyed metrics diverged): `no hypotheses surface
      from the divergence; inspect by hand.` Test asserts
      each of the four hypothesis branches via a separate
      fixture.
- [ ] `--since <Nh|Nd>` overrides the default. Invalid
      value: `diff: invalid --since "<v>" (use Nh or
      Nd)` to stderr, exit 2. Reuses `digest_parse_since`.
- [ ] Missing arguments: `bin/fleet diff` with zero or
      one positional argument prints `diff: usage:
      bin/fleet diff <slug-a> <slug-b> [--since Nh|Nd]
      [--json]` to stderr, exit 2.
- [ ] One or both slugs not found under
      `FLEET_DISCOVERY_ROOT`: `diff: slug "<slug>" not
      installed (no events.jsonl found)` to stderr,
      exit 2. The error names which slug was missing.
      Test asserts both missing-slug branches (a-missing,
      b-missing) AND the both-missing branch.
- [ ] `<slug-a>` and `<slug-b>` MUST differ —
      same-slug-twice is a usage error:
      `diff: <slug-a> and <slug-b> must differ; use
      \`fleet weekly --slug <slug>\` for the same-project
      historical comparison` to stderr, exit 2.
- [ ] `--json` emits one JSON object combining table +
      divergence + hypothesis sections:
      `{"window":{"start":"<iso>","end":"<iso>"},
      "a":"<slug-a>","b":"<slug-b>","metrics":[{"name":
      "ships","a":N,"b":N,"delta":N,"pct":"<...>"},...],
      "divergence":[{"metric":"sendbacks","ratio":3.7,
      "direction":"b>a"},...],"hypotheses":["<one-line>",
      ...]}`. Parsed via `node -e 'JSON.parse(...)'`. Per
      LESSONS 2026-06-03 (UTF-8 sign-extension trap) the
      JSON renderer uses the UTF-8-safe escape pattern.
      Per LESSONS 2026-06-01 (awk -v multiline trap) any
      hypothesis built from a multi-line capture goes
      through a tmp file via `getline line < file`.
- [ ] Help: `bin/fleet diff --help` prints a USAGE
      block mentioning `<slug-a>`, `<slug-b>`,
      `--since`, `--json`. Test asserts via
      `grep -qF -- "$kw" "$help_out"` per LESSONS
      2026-05-30. Help block ends with `exit 0` per
      LESSONS 2026-06-01.
- [ ] The dispatcher block and the `diff_cmd()`
      function each end with explicit `exit N` on
      every code path per LESSONS 2026-06-01. The
      dispatcher function is named `diff_cmd` (NOT
      `diff`) per LESSONS 2026-05-26 (`tail` shadow:
      shell function name MUST NOT shadow the
      system `diff` binary, which the test harness
      and several other subcommands shell out to —
      e.g. `prompts_diff` calls `diff -u` on
      installed-vs-current prompts trees). Per
      LESSONS 2026-06-05 (dispatcher forward-
      reference trap), `diff_cmd` either sits below
      every helper it calls (`digest_parse_since`,
      `provenance_json_escape`, the events-walk
      helpers shared with `weekly` and `incident`)
      OR inlines the helpers it needs.
- [ ] `tests/diff.sh` covers all 10 boxes using
      `$HOME/.local/bin` stubs (per LESSONS
      2026-05-26) for `gh`. The clock is frozen
      via `FLEET_NOW_OVERRIDE`. Per LESSONS
      2026-05-27 the test uses `cp` for fixture
      backup/restore. Per LESSONS 2026-06-01
      (`grep -c file || echo 0` double-print trap)
      every metric count uses
      `awk … END { print n+0 }`. The division-
      by-zero guard for the ratio is asserted by
      a fixture where slug-a has zero sendbacks
      and slug-b has 4 (expected ratio `4 /
      max(0, 1) = 4.0`, NOT a shell math error).
      Run-time budget: <12s.

## Out of scope

The dev agent will NOT do these even if they seem related.

- N-way comparison (`fleet diff a b c d`). Pairwise
  comparison is the smallest meaningful unit; an N-way
  matrix is a separate ticket once 2-way ships and
  proves the metric set is right. Adding N>=3 in v1
  inflates the table width past one screen.
- A `--metric NAME` filter to compare a single metric
  in isolation. Standard shell composition (`fleet
  diff a b --json | jq '.metrics[] |
  select(.name=="sendbacks")'`) already covers it; a
  built-in filter adds surface for no new capability.
- AUTO-emitting a `diff_divergence_detected` event
  when the divergence set is non-empty. v1 is reader-
  only; an autonomous emission pathway risks
  recursively self-incidenting on its own emissions
  (same posture as ticket 0037 `fleet incident`).
- Diffing two TIME WINDOWS of the SAME slug ("agent-
  fleet this week vs agent-fleet last week"). That is
  a same-slug temporal diff and is a separate ticket
  (`fleet weekly --compare-prev` would be the natural
  shape); the current ticket is cross-project at a
  fixed window.
- A `--watch` mode. The diff is a one-shot read; live
  updates belong to fleet-control's portal.
- Reading from fleet-control's portal database for
  any field. Per P-6 the source is `events.jsonl`.
- Cross-machine slugs. The two slugs must both be
  installed under this operator's
  `FLEET_DISCOVERY_ROOT`. Cross-machine federation
  is out of scope for the kit's solo-operator
  posture (D11, D9).

## Engineering notes

Files / patterns the dev should touch. Specific enough that the dev
doesn't have to re-discover the architecture.

- `bin/fleet` — new `diff_cmd()` dispatcher function
  (named `diff_cmd` NOT `diff` per LESSONS 2026-05-26
  shadow guard; the subcommand surface is still
  `bin/fleet diff …`). Dispatcher block:
  `if [ "$CMD" = "diff" ]; then diff_cmd "$@"; fi`.
  Placed BELOW the helpers it calls per LESSONS
  2026-06-05 (dispatcher forward-reference trap).
- `bin/fleet` — `diff_load_slug_metrics <slug>
  <since>` extracts the 8 metrics from one slug's
  `events.jsonl` + `runs.jsonl` and prints one
  JSON line. Reuses the per-project counters
  already implemented for `weekly` and `overview`
  — find via `grep -n
  'weekly_load_slug_metrics\|overview_count_'
  bin/fleet`. Per P-1 the new helper is a thin
  wrapper around the existing counters.
- `bin/fleet` — `diff_compute_delta` computes
  `(b - a)`, percent change, and the
  divergence ratio per metric. The percent
  formula is `100 * (b - a) / max(|a|, 1)`
  (truncating to integer). The ratio formula
  is `max(a,b) / max(min(a,b), 1)` — the
  `max(min(a,b), 1)` denominator is the
  division-by-zero guard asserted in AC#11.
- `bin/fleet` — `diff_render_text` and
  `diff_render_json` output helpers. Per
  LESSONS 2026-05-28 (printf leading-dash
  trap) every slug / metric name goes through
  `printf -- '%s'`. Per LESSONS 2026-06-03
  (UTF-8 sign-extension trap) the JSON
  renderer uses the UTF-8-safe escape
  pattern (inline copy of
  `provenance_json_escape` if forward-
  reference ordering forces it).
- `bin/fleet` — `diff_hypothesize` reads the
  divergence set + the two `prompts SHA`
  values + the two `top atlas pattern` values
  and emits up to 4 hypotheses per AC#3's
  rules. Each hypothesis is a single line
  built from a small `case ... esac` over
  the divergence set; no state, no
  side effects.
- `bin/fleet` — help banner block at the
  top of the file (around line ~14) gets a
  new line: `fleet diff <slug-a>
  <slug-b>  side-by-side ROI / posture
  comparison`. README "Daily ops" code block
  gets the same line.
- `lib/common.sh` — NO changes. `diff_cmd`
  is a pure consumer of `events.jsonl` and
  `runs.jsonl` (both existing). NO new
  helpers, NO `fleet_*` signature changes,
  NO new event types.
- `lib/install.sh` — NO changes.
- `prompts/` — NO changes. No `Reinstall:
  all projects` line needed because `lib/`
  and `prompts/` are untouched.
- `AGENTS.md` — NO new telemetry bullet
  (no new event types — the reader
  CONSUMES the contract, does not extend
  it).
- `tests/fixtures/diff/` — NEW directory
  under `tests/fixtures/` holding two
  synthetic project channels:
  - `slug-a/` — clean week: 19 ships, 18
    merges, 3 sendbacks, $8.42 spend, 0
    paused hours, 1 draft, prompts SHA
    `8a20547`, atlas pattern
    `gh_graphql_502:2`.
  - `slug-b/` — degraded week: 21 ships,
    14 merges, 11 sendbacks, $14.91 spend,
    26 paused hours, 7 drafts, prompts
    SHA `8a20547`, atlas pattern
    `actions_silent:5`.
  Plus the golden text file and JSON
  golden file. Plus a "same-prompts-SHA"
  fixture and a "differing-prompts-SHA"
  fixture for AC#3's hypothesis branches.
- `tests/diff.sh` — top of file mirrors
  `tests/weekly.sh`: stub the discovered-
  projects iteration via
  `FLEET_DISCOVERY_ROOT="$TMP/projects"`,
  freeze the clock via
  `FLEET_NOW_OVERRIDE`, stub `gh` (no
  network calls needed because all data
  comes from fixture files). Per LESSONS
  2026-05-26 stubs go in
  `$HOME/.local/bin`. Per LESSONS
  2026-05-27 use `cp` for fixture
  backup/restore. Per LESSONS 2026-06-01
  (`grep -c file || echo 0` double-print
  trap) counts use
  `awk … END { print n+0 }`. Run-time
  budget: <12s.
- New deps: none. Pure shell + awk +
  existing `digest_parse_since`,
  `provenance_json_escape`, the per-slug
  metric counters from `weekly` and
  `overview`.
- Public API: additive — `bin/fleet
  diff` is a new subcommand. NO new
  event types. NO `fleet_*` signature
  changes. NO new manifest fields.
- BREAKING flag: NO. PR body affirms
  "no change to the five public
  `fleet_*` signatures," "no new event
  types added," and "the dispatcher
  function is named `diff_cmd` to
  avoid the system `diff` binary
  shadow (LESSONS 2026-05-26)."
- Reinstall required: NO. `lib/` and
  `prompts/` are untouched.
- LESSONS to defend against:
  2026-05-26 (`tail` shadow — the
  dispatcher function is named
  `diff_cmd` to avoid shadowing
  `/usr/bin/diff`, which
  `prompts_diff` and several test
  fixtures shell out to). LESSONS
  2026-05-26 (PATH reset — stubs
  go in `$HOME/.local/bin`).
  LESSONS 2026-05-27 (`$(cat)`
  trap — fixture reads use `cp`).
  LESSONS 2026-05-28 (printf
  leading-dash trap — every slug
  / metric / hypothesis goes
  through `printf -- '%s'`).
  LESSONS 2026-05-30 (`grep -F
  --` flag trap — help text uses
  `grep -qF --`). LESSONS
  2026-06-01 (awk -v multiline
  trap — hypotheses with
  multi-line values use a tmp
  file). LESSONS 2026-06-01
  (`grep -c file || echo 0`
  double-print trap — every
  metric count uses
  `awk … END { print n+0 }`).
  LESSONS 2026-06-01 (dispatcher
  fall-through trap —
  `diff_cmd()` ends with
  explicit `exit N` on every
  path). LESSONS 2026-06-03
  (UTF-8 sign-extension trap —
  JSON renderer uses the
  UTF-8-safe escape pattern).
  LESSONS 2026-06-05
  (dispatcher forward-reference
  trap — `diff_cmd()` sits
  below every helper it calls
  OR inlines the helpers).
- This ticket compounds 0019
  (`fleet overview` is the
  per-project snapshot,
  `diff` is the two-slug
  detail), 0024 (`fleet
  prompts-score` is the
  per-project prompts grade,
  `diff` is the cross-project
  comparison), 0025 (`fleet
  weekly`'s per-project
  rollup is the input metric
  source), 0031 (`fleet
  atlas`'s per-pattern fires
  are the input). Per P-1
  the diff is moderate:
  ~200 lines of `diff_*`
  helpers + ~300 lines of
  test + one README line +
  one help-text line. Net
  new SLOC ~500.

## Implementation log

(Appended by the implementation-dev agent during execution.)

- 2026-06-08 — branch `feat/0038-fleet-diff-cross-project-divergence` opened; status flipped groomed → in-progress
- 2026-06-08 — failing test added in `tests/diff.sh` (11 AC blocks, run-time <12s)
- 2026-06-08 — PR #79 opened, CI green (shellcheck + validate both pass)
- 2026-06-08 — merged to main (squash commit 715ee4d)
