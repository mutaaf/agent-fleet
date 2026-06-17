---
id: 0058
title: fleet trends <slug> renders 12-week sparkline-style trend lines for PRs / cost / send-backs
status: in-progress
priority: P1
area: observability
created: 2026-06-17
owner: gtm-innovation
---

## User story

As a fleet operator who has been running `sidebrew` through the
loop for 14 weeks — who knows from `fleet weekly` (0025) that last
week shipped 2 PRs and from `fleet recap` (0048) that the last 30
days narrate cleanly, but who has NO view of the SHAPE of the
last 12 weeks ("was PR velocity trending up before last week's
dip, or was last week the THIRD week of decay?") — I want
`bin/fleet trends <slug>` to render three sparkline rows over the
trailing 12 weeks: PRs merged per week, dollars spent per week,
and send-back rate per week, each as a Unicode block-glyph
sparkline (`▁▂▃▄▅▆▇█`) so I can SEE at a glance whether a
trend has reversed (e.g. `▆▇▇▇▆▅▄▃` means PR velocity peaked 5
weeks ago and is decaying — time to investigate before the slug
silently churns), without having to mentally diff seven `fleet
weekly` snapshots.

## Why now (four lenses)

### Product Owner
The kit's existing observability surfaces are EXCELLENT at points
and weak at trajectories. `fleet weekly` (0025) is a Sunday
snapshot of last week. `fleet recap` (0048) narrates a window of
days. `fleet milestone` (0049) celebrates streak crossings.
`fleet morning` (0036) summarizes today. `fleet badge` (0027) is
a one-line ROI shield. `fleet streak` (0042) shows the longest
continuous green run. None of them show the SHAPE of change over
time. An operator who wants to know "is sidebrew getting better
or worse over the last quarter?" has to manually open 12 weekly
files and visually diff. The smallest meaningful unit of value
is three sparkline rows:

```
$ fleet trends sidebrew
trends: sidebrew — 12 weeks ending 2026-06-15

  PRs merged/wk      ▁▂▃▅▆▇▇▇▆▅▄▃   range 0-7   last 4w slope:  ↓
  $ spent/wk         ▁▂▂▃▃▃▄▄▄▄▅▅   range $1-$8 last 4w slope:  →
  send-back rate/wk  ▃▂▂▁▁▁▁▂▂▃▄▄   range 0%-30% last 4w slope: ↑

  ⚠ PR velocity declining for 4 consecutive weeks AND send-back
  rate rising. consider running `fleet skill-gap sidebrew`
  (0051) to check CROSS_LESSONS coverage, OR `fleet incident`
  (0037) to triage the last red CI run.
```

Subtraction: the operator stops mentally diffing 12 weekly
snapshots. Per P-5 (operator confidence over feature richness),
the win is the absent guesswork about whether a trend has
reversed.

The advisory footer is OPINIONATED — it triggers only on the
two-axis signal (declining PR velocity AND rising send-back
rate, for ≥3 consecutive weeks). Single-axis trends print
without the footer, because one declining axis alone is noise.
Two declining axes together are signal worth surfacing.

### Stakeholder
This is **moat-deepening on the retention axis** — the kit's
first surface that watches trajectory rather than position. Per
P-6 (telemetry is the source of truth), `trends` is a PURE
READER over each slug's `events.jsonl` (for the `pr_footer_
posted` and `lesson_draft_emitted` counts per week) and
`runs.jsonl` (the 0047 cost channel). No new event types. No
writes. No `lib/common.sh` changes. The diff is the week-bucket
walker + the sparkline encoder + the renderer. ~290 lines.

The 12-week / 3-axis shape IS the moat: it codifies "what
matters in fleet trajectory" — PR velocity is the value
output, dollar cost is the budget pressure, send-back rate is
the quality signal. A slug that holds all three flat is
healthy; a slug that bends two of them is in trouble. Per
the brief's "the moat is: uniform telemetry, safe self-
modifying loop, cheap runs, fast recovery from a stuck PR,
easy onboarding of a new project" — trends is the surface
that makes "cheap runs" and "is the loop still delivering"
visible OVER TIME, not just AT A MOMENT.

Per LESSONS 2026-06-15 (per-day shellout inside per-slug
loops) the trends walker bins events by week in ONE awk pass
per slug — NOT 12 separate per-week passes. The week-bucket
math is awk-internal `(epoch - epoch_of_week_0) / 604800`
arithmetic, no per-bucket `date -j -v` shellout. The
`--all` mode walks every slug, so this matters: 20 slugs ×
12 weeks × 0 per-bucket subprocesses = 20 awk passes total,
each ~50ms. Per LESSONS 2026-06-15 the `--all` rule is
strict.

Compounds 0025 (`fleet weekly` — trends is the multi-week
view weekly is the single-week view of), 0048 (`fleet
recap` — narrative cousin; trends is the visual cousin),
0042 (`fleet streak` — the green-day predicate informs
the per-week health bucket), 0047 (`fleet ticket-cost` —
the cost channel `runs.jsonl` is read for the $/wk row),
0044 (`fleet pr-footer` — the `pr_footer_posted` event
is the PRs/wk source), 0022 (`lesson_draft_emitted` —
the send-back rate source), 0019 (`fleet overview` —
reuses `overview_discover_slugs` for `--all`),
0051 (`fleet skill-gap` — referenced by the advisory
footer), 0037 (`fleet incident` — also referenced by
the advisory footer).

### User (operator at 8am Monday, reviewing the quarter)
The operator sits down with their coffee Monday morning,
runs `fleet trends sidebrew`. They see the PR velocity row
shows `▆▇▇▇▆▅▄▃` — the last 4 weeks are clearly declining
from a peak. They flip to `fleet trends courtiq`. Courtiq
shows `▄▅▅▅▆▆▆▇▇▇▇▇` — steady climb, no concern. They
flip to `fleet trends --all` (sub-scenario below) to spot
which OTHER slugs are bending which way. By 8:12am they
know exactly which slug needs investigation today. They
open `fleet incident sidebrew --since 4w` and read the
forensic narrative. Per P-5, the win is the trend
becoming VISIBLE in 8 seconds rather than the operator
having to compose it themselves from twelve weeks of
weekly snapshots.

Sub-scenario: `fleet trends --all` prints one row per
slug — slug name plus the PR-velocity sparkline only
(the most-condensed view) — so a fleet operator can
scan-spot which slug is bending which way at a glance:

```
$ fleet trends --all
trends: 4 slugs — 12 weeks ending 2026-06-15 (PRs/wk only)

  courtiq        ▄▅▅▅▆▆▆▇▇▇▇▇   range 2-9   slope: ↑
  sidebrew       ▁▂▃▅▆▇▇▇▆▅▄▃   range 0-7   slope: ↓
  levelup-kids   ▃▃▃▃▃▃▃▃▃▃▃▃   range 1-2   slope: →
  hedgehog       ▁▁▁▁▁▁▁▁▁▁▁▁   range 0-0   slope: → (paused)
```

Sub-scenario: an operator running `fleet trends sidebrew
--axis sendbacks` restricts the render to ONE axis row
(useful for a focused investigation).

### Growth
This is the surface that converts "I trust the kit" into
"I trust the kit AND I can prove it." A friend evaluating
the kit who sees a `fleet trends courtiq` sparkline
showing 12 weeks of climbing PR velocity has a
PERSUASIVE artifact — not a snapshot but a TRAJECTORY.
That's the kind of artifact that ships into a Twitter
quote-tweet or a conference talk slide. Per the brief's
"the operator is on call once a day from the fleet-
control portal" — trends is the surface that lets that
once-a-day check answer the question "is anything
bending the wrong way?" in 15 seconds.

Differentiated from `fleet weekly` (0025): weekly is
ONE Sunday snapshot of last week. Trends is 12 of those
snapshots in a sparkline. Weekly is the data source;
trends is the multi-week view. Differentiated from
`fleet recap` (0048): recap is a narrative composed
from a window. Trends is a visual rendered from the
same window. Differentiated from `fleet milestone`
(0049): milestone celebrates a CROSSING (a streak
just hit 30 days). Trends shows the SHAPE that led to
or away from the crossing.

Differentiated from `fleet rank` (0043): rank is a
fleet-wide leaderboard at one moment. Trends is the
per-slug movie over 12 weeks. `--all` mode shows one
sparkline per slug so the fleet-wide trajectory is
visible without sacrificing the per-slug detail.

## Acceptance criteria

Each box maps 1:1 to a test scenario in
`tests/trends.sh`.

- [ ] `bin/fleet trends <slug>` is a new subcommand.
      Required arg is the slug name. Missing slug:
      prints `trends: usage: bin/fleet trends <slug |
      --all> [--axis prs|cost|sendbacks] [--weeks N]
      [--json]` to stderr, exit 2 per LESSONS
      2026-06-01. Unknown slug: prints `trends: slug
      <name> not found. discovered slugs: <list>` to
      stderr, exit 2. Per LESSONS 2026-05-30 (`grep
      -F --` trap) the test assertion uses `grep -qF
      -- "$kw" "$out"`. Test asserts both refusals.
- [ ] The default window is 12 weeks ending today.
      Week buckets are Mon-Sun ISO weeks. The
      bucket assignment is computed via ONE awk pass
      over the slug's events.jsonl: for each
      `pr_footer_posted` event, the week-bucket is
      `(epoch - epoch_of_today_minus_84_days) /
      604800`. Per LESSONS 2026-06-15 (per-day
      shellout is O(window × N_slugs)) the bucket
      math is pure awk arithmetic — NO per-bucket
      `date -j -v` shellout. Per LESSONS 2026-06-11
      (BSD `date -j -f` fills missing time fields)
      the today-anchor uses `date +%s` minus
      `84 * 86400`, no `-j -f` involved. Per LESSONS
      2026-06-08 the awk pass declares `BEGIN
      { count = 0 }`. Test asserts via fixture with
      events spread across 12 weeks.
- [ ] The PRs/wk row counts `pr_footer_posted`
      events per week-bucket. The $/wk row sums
      `runs.jsonl` `cost_usd` rows per week-bucket
      (same awk-bucket math). The send-back rate/wk
      row computes `lesson_draft_emitted` events
      DIVIDED by `pr_opened` events per bucket,
      rendered as a percentage. A bucket with zero
      `pr_opened` events renders the send-back rate
      as 0 (NOT division-by-zero). Per LESSONS
      2026-06-08 IFS=$'\t' middle-empty-field uses
      `-` sentinel. Test asserts all three rows
      via fixture.
- [ ] The sparkline encoder maps a bucket's value
      to one of 8 Unicode block glyphs
      `▁▂▃▄▅▆▇█` by linear interpolation between
      the row's min and max across the 12 buckets.
      A row whose min == max renders all glyphs as
      `▁`. Per LESSONS 2026-06-05 (bash 3.2
      LC_ALL caching) any string-index op uses
      `LC_ALL=C awk`. Per LESSONS 2026-06-03
      (UTF-8 sign-extension under LC_ALL=C) the
      block glyphs are emitted via printf `%s`
      from a pre-built string — NOT indexed
      byte-by-byte. Test asserts via fixture with
      a row of `0 1 2 3 4 5 6 7 6 5 4 3` mapping
      to `▁▂▃▄▅▆▇█▇▆▅▄`.
- [ ] The trailing-4-week slope arrow is `↑`
      (last 4 weeks' mean ≥ prior 4 weeks' mean +
      20%), `↓` (last 4 weeks' mean ≤ prior 4
      weeks' mean - 20%), `→` (within the 20%
      band). Per LESSONS 2026-06-08 the slope awk
      pass declares `BEGIN { last = 0; prior = 0
      }`. Test asserts via fixture with three
      branches (one ↑, one →, one ↓).
- [ ] The advisory footer prints ONLY when (a) the
      PR-velocity slope is `↓` for ≥3 consecutive
      weeks AND (b) the send-back-rate slope is
      `↑` for ≥3 consecutive weeks. "Consecutive"
      means each week's value is monotone in the
      relevant direction. Single-axis trends do
      NOT trigger the footer. Test asserts both
      the trigger branch (footer present) and the
      single-axis-only branch (footer absent).
- [ ] `bin/fleet trends <slug> --weeks N` overrides
      the default 12-week window. Min N is 4
      (anything shorter is noise); max N is 52 (a
      year). Values outside this range print
      `trends: --weeks must be 4-52 (got N)` to
      stderr, exit 2. Test asserts the boundaries.
- [ ] `bin/fleet trends <slug> --axis <prs|cost|
      sendbacks>` restricts the render to ONE row.
      Default (no `--axis`) prints all three.
      Unknown axis: prints `trends: --axis must be
      one of prs|cost|sendbacks (got X)` to stderr,
      exit 2. Per LESSONS 2026-05-30 the test
      assertion uses `grep -qF -- "$kw"`. Test
      asserts.
- [ ] `bin/fleet trends --all` prints one row per
      discovered slug — slug name plus the
      PR-velocity sparkline only (the most-condensed
      view). Sorted by descending last-4-week slope
      so the climbing slugs surface first. Per
      LESSONS 2026-05-28 every printf of a slug
      name goes through `printf -- '%s'`. Per
      LESSONS 2026-06-15 the `--all` walker runs
      ONE awk pass per slug for all three axes
      (NOT three awk passes per slug); the per-
      slug subprocess budget is 1 awk + 0 date
      calls. Test asserts via fixture with 4 slugs
      that the total `date` invocations is < 10
      across the whole `--all` run.
- [ ] `bin/fleet trends <slug> --json` emits one
      structured JSON object: `{"slug": "<name>",
      "weeks": [{"start": "YYYY-MM-DD", "prs":
      <int>, "usd": <number>, "sendbacks_pct":
      <number>}, …], "slopes": {"prs": "↑|→|↓",
      "cost": "↑|→|↓", "sendbacks": "↑|→|↓"},
      "advisory": "<text>" or null}`. JSON escape
      via `preflight_json_escape` per LESSONS
      2026-06-03 called directly per LESSONS
      2026-06-13 (no `*_json_escape` wrapper). Per
      LESSONS 2026-06-08 the slope arrows are
      emitted as ASCII strings (`"up"|"flat"|
      "down"`) in the JSON shape — NOT raw Unicode
      arrows — so downstream JSON consumers don't
      need UTF-8 handling. Test asserts JSON
      validity via Node AND that the slope field
      is `up|flat|down`.
- [ ] `bin/fleet trends --all --json` emits one
      JSON array with one element per slug, each
      element shaped like the single-slug JSON
      above. Test asserts via fixture with 4 slugs.
- [ ] `bin/fleet trends --help` prints USAGE
      mentioning slug + `--all`, `--axis`,
      `--weeks`, `--json`. Per LESSONS 2026-05-30
      test asserts via `grep -qF -- "$kw"
      "$help_out"`. Help block ends with `exit 0`
      per LESSONS 2026-06-01.
- [ ] `bin/fleet trends` is a PURE READER. NO
      `events.jsonl` writes, NO `fleet_emit_event`
      calls, NO writes to `runs.jsonl` or
      `agents.config.sh`. Test asserts every
      slug's `events.jsonl` and `runs.jsonl` byte
      size is unchanged before and after
      invocation.
- [ ] `lib/common.sh` — NO changes. `prompts/`
      — NO changes. No new event types. Test
      asserts via `git diff --name-only
      main...HEAD -- lib/common.sh prompts/`
      returns empty.
- [ ] `tests/trends.sh` covers all 14 boxes above
      using `$HOME/.local/bin` stubs per LESSONS
      2026-05-26 (PATH reset). Fixture
      `events.jsonl` and `runs.jsonl` per slug
      live under `tests/fixtures/trends/`. Per
      LESSONS 2026-05-27 backup/restore via `cp`
      (NOT `$(cat)`). Counts use `awk … END
      { print n+0 }` per LESSONS 2026-06-01. Per
      LESSONS 2026-06-08 every awk script
      declares `BEGIN { count = 0 }`. Per LESSONS
      2026-06-08 IFS=$'\t' middle-empty-field
      uses `-` sentinel. Per LESSONS 2026-06-15
      the week-bucket math is pure awk
      arithmetic — no per-week `date -j -v`
      shellout. The clock is frozen via
      `FLEET_NOW_OVERRIDE` so the 12-week
      window is deterministic. Run-time
      budget: <10s.

## Out of scope

The dev agent will NOT do these even if they seem
related.

- AUTO-PAUSING a slug whose PR-velocity trend has
  been `↓` for 4 consecutive weeks. That's
  0006's job and would require trends to WRITE,
  breaking the pure-reader contract. The
  advisory footer NUDGES — it does not act.
- A LONGER window (`--weeks 104` for two years).
  v1 caps at 52. Multi-year trends are v2; they
  also stress the inline awk's memory budget.
- ADDITIONAL axes (heal-cycle count, runtime
  minutes, cost-per-PR). v1 ships exactly three.
  Each new axis is an explicit add via a follow-
  up ticket so the rendered output stays
  scannable.
- A HEATMAP render (rows × axes × weeks as a
  grid of colored cells). Shell-only kit; ANSI
  colors are a v2 ask.
- AN HTML / SVG sparkline render. Shell-only.
- A `--csv` mode for spreadsheet import. v1
  ships `--json` only; CSV is trivial to
  derive from JSON via `node -e` for an
  operator who wants it.
- A `--diff <slug-a> <slug-b>` mode comparing
  two slugs' trends side-by-side. `fleet diff`
  (0038)'s pattern; out of scope here.
- A `--annotate` mode that overlays event
  markers (when did this slug ship its first
  PR? when did the streak break?) on the
  sparkline. Cute but adds complexity; v2.
- A WEEKLY launchd schedule that fires
  `fleet trends --all` and emails the operator.
  v1 is operator-invoked.
- A PREDICTIVE row ("forecast for next 4
  weeks"). v1 is descriptive. Forecasting is
  a v2 if asked (and requires a more
  considered model).
- AUTO-INVOKING `fleet skill-gap` or `fleet
  incident` from the advisory footer. v1
  SUGGESTS the command; the operator runs it
  manually.

## Engineering notes

Files / patterns the dev should touch.

- `bin/fleet` — new `trends()` dispatcher
  function placed next to the existing
  `weekly()` block (find via `grep -n
  '^weekly()' bin/fleet`). Per LESSONS
  2026-05-26 (`tail` shadow) `trends` does not
  collide with any coreutils binary.
- `bin/fleet` — eight helpers, ALL defined
  ABOVE the dispatcher block per LESSONS
  2026-06-05 (forward-reference trap):
  - `trends_discover_slugs` — wraps
    `overview_discover_slugs`, returns
    alphabetical order.
  - `trends_bucket_events` — ONE awk pass
    over the slug's events.jsonl, binning
    every `pr_footer_posted`, `pr_opened`,
    `lesson_draft_emitted` into a 12-week
    bucket array. Per LESSONS 2026-06-08
    `BEGIN { count = 0 }`. Per LESSONS
    2026-06-08 IFS=$'\t' middle-empty-
    field uses `-` sentinel. Per LESSONS
    2026-06-15 the bucket assignment is
    pure awk `(epoch - anchor) / 604800`,
    NO per-bucket `date -j -v` shellout.
  - `trends_bucket_costs` — ONE awk pass
    over `runs.jsonl`, same bucket math.
  - `trends_compute_slopes` — computes the
    last-4-week vs prior-4-week mean for
    each axis and emits `up|flat|down`
    per AC #5. Per LESSONS 2026-06-08
    `BEGIN { last = 0; prior = 0 }`.
  - `trends_encode_sparkline` — given an
    array of N values, returns the N-glyph
    sparkline string via linear
    interpolation. Per LESSONS 2026-06-03
    the glyphs are emitted via `printf
    '%s'` from a pre-built string —
    NOT byte-indexed (which would sign-
    extend under `LC_ALL=C`). Per LESSONS
    2026-06-05 (bash 3.2 LC_ALL caching)
    any string-index op runs via
    `LC_ALL=C awk`.
  - `trends_compose_advisory` — emits the
    advisory footer per AC #6 ONLY when
    both axes trigger.
  - `trends_render_text` — text formatter
    per the Product-Owner example. Width
    via `preflight_visible_width` per
    LESSONS 2026-06-05. Per LESSONS
    2026-05-28 every printf of a slug
    name goes through `printf -- '%s'`.
  - `trends_render_json` — JSON formatter.
    JSON escape via `preflight_json_escape`
    per LESSONS 2026-06-03 called directly
    per LESSONS 2026-06-13 (no
    `*_json_escape` wrapper). Slope arrows
    are emitted as `up|flat|down` ASCII
    strings, NOT raw Unicode arrows.
- `bin/fleet` — `trends()` end-state must be
  `exit 0` / `exit 2` on every code path per
  LESSONS 2026-06-01.
- `bin/fleet` — dispatcher block: `if [ "$CMD"
  = "trends" ]; then trends "$@"; fi`. Place
  AFTER the `weekly` dispatcher.
- `bin/fleet` — help banner block at the top of
  the file gets ONE new line: `fleet trends
  <slug> render 12-week sparklines for PRs /
  cost / send-backs`. README "Daily ops" code
  block gets the same line, appended via the
  same single-edit pattern that avoided LESSONS
  2026-05-25.
- `AGENTS.md` — NO content change.
- `lib/common.sh` — NO changes.
- `prompts/` — NO changes.
- `tests/fixtures/trends/` — NEW directory
  holding four slug subdirs (`climbing`,
  `declining`, `flat`, `bimodal`) each with
  `events.jsonl`, `runs.jsonl`, and
  `agents.config.sh`. The events cover 14
  weeks (so the default 12-week window has a
  buffer on either side) with shape-distinct
  PR / cost / send-back distributions per
  fixture. A fifth `paused` slug has only
  `ship_paused` events and zero PR events
  to exercise the all-zeros sparkline branch.
- `tests/trends.sh` — top of file mirrors
  `tests/weekly.sh` (closest prior ticket;
  shares the week-bucket math shape). Stubs
  live under `$HOME/.local/bin` per LESSONS
  2026-05-26 (PATH reset). The `date` stub
  records its invocation count to a side
  file so AC #9's < 10 calls assertion can
  fire. Counts use `awk … END { print n+0 }`
  per LESSONS 2026-06-01. Per LESSONS
  2026-05-27 backup/restore via `cp`. The
  clock is frozen via `FLEET_NOW_OVERRIDE`.
  Run-time budget: <10s.
- New deps: none. Pure shell + awk + Node
  (for JSON validation in tests).
- Public API: additive — `bin/fleet trends`
  is a new subcommand. ZERO new event
  types, ZERO event writes, ZERO
  `lib/common.sh` changes, ZERO `prompts/`
  changes.
- BREAKING flag: NO. PR body affirms "pure
  reader, no events.jsonl writes, no
  `fleet_*` signature changes, no runtime
  hot-path changes."
- Reinstall required: NO. `lib/` and
  `prompts/` are untouched.
- LESSONS to defend against: 2026-05-25
  (README "Daily ops" code block addition),
  2026-05-26 (`tail` shadow), 2026-05-26
  (PATH reset — stubs in
  `$HOME/.local/bin`), 2026-05-27 (`$(cat)`
  trap — use `cp` for backup/restore in
  tests), 2026-05-28 (printf leading-dash —
  every slug-name printf goes through
  `printf -- '%s'`), 2026-05-30 (`grep -F
  --` trap), 2026-06-01 (`grep -c file ||
  echo 0` double-print — counts use `awk …
  END { print n+0 }`), 2026-06-01
  (dispatcher fall-through — every code
  path ends `exit 0/2`), 2026-06-03 (UTF-8
  sign-extension — JSON escape via
  `preflight_json_escape`; sparkline glyphs
  emitted via `printf '%s'` from a pre-
  built string, NOT byte-indexed),
  2026-06-05 (dispatcher forward-reference
  — all `trends_*` helpers defined ABOVE
  the dispatcher), 2026-06-05 (bash 3.2
  LC_ALL caching — any string-index op
  via `LC_ALL=C awk`), 2026-06-05 (export-
  in-subshell trap — any agents.config.sh
  read happens inside `( … )`), 2026-06-08
  (awk empty-string-key — `BEGIN { count
  = 0 }`), 2026-06-08 (IFS=$'\t' middle-
  empty-field — sentinel `-`), 2026-06-11
  (BSD `date -j -f` fills missing time
  fields with NOW-of-day — the today-
  anchor uses `date +%s` minus
  `84 * 86400`, no `-j -f` involved),
  2026-06-13 (no `*_json_escape` wrapper
  around `preflight_json_escape` — called
  directly), 2026-06-15 (per-day shellout
  inside per-slug loops is O(window ×
  N_slugs) — the bucket math is pure awk
  arithmetic, NO per-bucket `date -j -v`
  shellout; `--all` mode is ONE awk pass
  per slug for all three axes).
- This ticket compounds 0025 (`fleet
  weekly` — trends is the multi-week
  view weekly is the single-week view
  of), 0048 (`fleet recap` — narrative
  cousin), 0042 (`fleet streak` — green-
  day predicate informs per-week health
  buckets), 0047 (`fleet ticket-cost` —
  reads `runs.jsonl` for the $/wk row),
  0044 (`fleet pr-footer` —
  `pr_footer_posted` is the PRs/wk
  source), 0022 (`lesson_draft_emitted`
  — send-back rate source), 0019
  (`fleet overview` — reuses
  `overview_discover_slugs`), 0043
  (`fleet rank` — at-a-moment cousin
  trends complements), 0049 (`fleet
  milestone` — celebrates crossings;
  trends shows the shape that led to
  them), 0051 (`fleet skill-gap` —
  advisory footer references it), 0037
  (`fleet incident` — advisory footer
  references it), 0054 (`fleet
  maturity` — shares the per-slug
  events-walk pattern). Per P-1 the
  diff is small: ~290 lines of
  `trends_*` helpers + ~280 lines of
  test + 10 fixture files (4 slugs × 2
  files + 2 extras) + one help-text
  line + one README line.

## Implementation log

2026-06-17: implementation-dev picked this ticket and flipped status
groomed → in-progress on `feat/0058-fleet-trends-12w-sparklines`. Plan
per AGENTS.md: tests-first under `tests/trends.sh` with fixtures at
`tests/fixtures/trends/<slug>/{events.jsonl,runs.jsonl,agents.config.sh}`,
then implement eight `trends_*` helpers + `trends()` dispatcher in
`bin/fleet` ALL above the dispatcher block per LESSONS 2026-06-05.
Pure reader: zero `lib/common.sh` / `prompts/` / events writes.
