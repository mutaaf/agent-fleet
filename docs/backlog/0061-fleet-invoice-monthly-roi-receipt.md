---
id: 0061
title: fleet invoice <slug> emits a monthly billing-style ROI receipt suitable for forwarding to a CFO or future-self
status: in-progress
priority: P1
area: governance
created: 2026-06-19
owner: gtm-innovation
---

## User story

As a fleet operator who has been running `agent-fleet` against
`sidebrew` for 11 weeks and against `courtiq` for 6 weeks — who
knows the loop is "working" because `fleet pulse` (0055) is mostly
green and `fleet weekly` (0025) shows Sunday ROI — but who is
asked at the dinner table "what does that thing actually cost you
a month, and is it worth it?" and has NO single answer-shaped
artifact to point at — I want `bin/fleet invoice <slug>` to compose
a billing-style monthly receipt for one slug (or `--all` for the
fleet): N PRs shipped, M hours of human-equivalent work
displaced, $X spent on Claude, $Y the alternative (Cursor Pro,
manual contractor) would have cost, NET savings, plus a one-line
verdict (`net positive: $42/mo, kit pays for itself in 0.4 weeks`
or `break-even: kit costs ≈ alternative — keep an eye on cost/PR`
or `net negative: $23/mo over alternative — investigate before
month 13`), so the question "is this worth it?" has a printable
answer the operator forwards to themselves on the 1st of every
month and never has to compose from scratch.

## Why now (four lenses)

### Product Owner
The kit's existing observability surfaces all answer "is the
loop healthy?" (overview, doctor, pulse, morning, inbox, stuck,
flaky). NONE of them answer "is the loop WORTH IT?" — the
single question that determines whether the operator keeps
running it past month 6. The closest surfaces are 0047 `fleet
ticket-cost` (per-ticket attribution), 0025 `fleet weekly`
(Sunday snapshot), 0027 `fleet badge` (one-line ROI shield),
0044 `fleet pr-footer` (per-merge ROI comment), 0048 `fleet
recap` (window narrative). None of them frame the question
the way an OPERATOR thinks about a recurring SaaS subscription:
"what did I get this month, what did it cost me, what would
the alternative have cost?" The smallest meaningful unit of
value is one receipt-shaped artifact:

```
$ fleet invoice sidebrew --month 2026-05
agent-fleet — invoice for sidebrew, May 2026

  PRs merged                                   14
  Heal cycles                                   3
  Send-backs requiring rework                   2
  Operator interventions (manual merges)        0
  Total runtime                            4h 12m

  Claude API spend                          $7.84
  Estimated human-equiv hours displaced     ~17h
  Cursor Pro alternative (1 seat)          $20.00
  Contractor alt (17h @ $80/h)            $1360.00

  NET vs Cursor Pro:           +$12.16   (kit ahead)
  NET vs contractor:         +$1352.16   (kit ahead)
  Cost per PR shipped:           $0.56   (median: $0.42)
  Cost per heal cycle:           $0.21

  verdict: net positive — kit pays for itself in 0.4 weeks
  this month vs last month:    PRs +27%   cost +12%   $/PR -12%
```

`--all` mode sums every slug into one fleet-wide invoice with
a per-slug breakdown table at the bottom. `--ytd` rolls up
every month-to-date. `--json` returns the same shape as a
machine-readable object for the fleet-control browser tile.

Subtraction: the operator stops mentally tallying "is this
still earning its keep" every few weeks. Per P-5 (operator
confidence over feature richness), the win is the loop's
ROI becoming PROVABLE without an evening of spreadsheet work.

The verdict line is OPINIONATED — it triggers `net positive`
when the kit beats the cheapest alternative by ≥10%,
`break-even` within ±10%, `net negative` below -10%. The
"investigate" nudge fires only on the negative side; the
operator should NOT be nudged to celebrate on the positive
side every month (that's the badge's job).

The "human-equiv hours displaced" estimate is conservative
and documented: it counts merged PRs × `MANUAL_PR_MINUTES`
(a manifest knob, default 75min = "the time a careful human
would have spent writing the same diff including tests").
The operator can override it; the README explains the
default. This is the one estimated number on the invoice;
every other number is measured.

### Stakeholder
This is **moat-deepening on the retention axis** — the kit's
first surface designed to answer the question that determines
whether the operator KEEPS PAYING (in time, attention, and
API spend) to run the loop. Per P-6 (telemetry is the source
of truth), `invoice` is a PURE READER over each slug's
`events.jsonl` (for `pr_footer_posted`, `run_completed`,
`gate_failed`, `lesson_draft_emitted`) and `runs.jsonl` (the
0047 cost channel). NO writes, NO new event types, NO
`lib/common.sh` changes. The diff is the monthly bucket
walker + the alternative-cost math + the verdict + the
renderer. ~340 lines.

The invoice shape IS the moat: it codifies "how a fleet
operator thinks about a recurring autonomous-coding-agent
subscription" into a runnable artifact. Every future
`autonomous coding agent` competitor can ship a per-PR ROI
comment (0044's shape) but few will ship a monthly
defensible-against-a-CFO invoice. The shape itself becomes
the way the kit's ROI is discussed in the wider community.

Per LESSONS 2026-06-15 (per-day shellout inside per-slug
loops is O(window × N_slugs)) the per-slug walk is ONE
awk pass over events.jsonl plus ONE awk pass over
runs.jsonl. The month-bucket math is awk-internal
`strftime`-style arithmetic on the epoch, NOT per-day
`date -j -v` shellouts. The `--all` mode walks every
slug with the same budget per slug, so even a 12-slug
fleet stays under 2s.

Per LESSONS 2026-06-11 (BSD `date -j -f` fills missing
time fields) any month-to-epoch conversion uses the full
`'%Y-%m-%dT%H:%M:%S'` format with `T00:00:00` appended;
the `--month YYYY-MM` parser normalizes to
`YYYY-MM-01T00:00:00`.

Compounds 0047 (`fleet ticket-cost` — invoice's
per-PR cost row uses the same `runs.jsonl` source),
0025 (`fleet weekly` — invoice is the monthly version
of the Sunday snapshot), 0027 (`fleet badge` —
invoice's verdict line can be derived from the same
inputs the badge ROI uses), 0044 (`fleet pr-footer`
— invoice aggregates per-PR cost into monthly totals),
0058 (`fleet trends` — invoice's "this month vs last
month" line is the 2-week sparkline collapsed to two
scalars), 0019 (`fleet overview` — reuses
`overview_discover_slugs` for `--all`), 0048
(`fleet recap` — invoice is the financial complement
to recap's narrative).

Differentiated from `fleet weekly` (0025): weekly is
one Sunday of last week; invoice is one month's
billing summary. Differentiated from `fleet
ticket-cost` (0047): ticket-cost is per-PR;
invoice is per-month. Differentiated from `fleet
badge` (0027): badge is the always-on shield;
invoice is the periodic deliverable. Differentiated
from `fleet recap` (0048): recap is narrative;
invoice is numerical.

### User (operator on the 1st of the month, 7am)
The operator sits down on the 1st of July at 7am with
coffee, runs `fleet invoice --all --month 2026-06`.
The receipt prints. They read the verdict line:
`net positive across 3 of 4 slugs; investigate
levelup-kids (net negative $8/mo, $/PR rising)`.
They forward the output to their own email (via a
trivial `| mail -s "agent-fleet invoice"` pipe) so
future-self has the artifact. They open `fleet
ticket-cost levelup-kids --since 30d` and see two
specific tickets blew the budget — both involved a
human-promoted lesson that turned out to be wrong.
By 7:14am they've identified the cost driver,
demoted the lesson, and the next month's invoice
will be in the black again. Per P-5 the win is the
1-minute monthly answer to "is this worth it?"
replacing the 30-minute quarterly anxiety.

Sub-scenario: an operator forwards their invoice to
a friend who asks "what does it cost?" — the
receipt is COMPLETE on its own (no portal login
needed), so the friend reads it and the
conversation moves on.

Sub-scenario: `fleet invoice <slug> --ytd` rolls
up every month-to-date so the operator on Dec 31
gets the year's full bill.

Sub-scenario: `fleet invoice <slug> --redact`
emits the same shape but with slug name and exact
costs banded (per the 0053 portfolio-redact
convention) so the operator can share publicly.

### Growth
The receipt is a shareable artifact unlike anything
in the kit's growth surface today. A peer evaluating
the kit who sees a friend's `fleet invoice sidebrew
--month 2026-05` post on Twitter or in a Slack DM
sees a concrete COMPETITIVE comparison ("$7.84
beats $20 Cursor Pro") — the kind of evidence that
converts a curious bystander into an adopter
faster than any feature pitch. Per the brief's
"why does a friend running their own autonomous-
agent setup want to adopt it?" — invoice is the
proof point.

Differentiated from competing dashboards (Cursor's
usage, GitHub Copilot's stats): those frame
spending as a passive subscription line item.
Invoice frames it as a comparison to the
ALTERNATIVE, with savings made explicit. That
frame is the kit's marketing.

## Acceptance criteria

Each box maps 1:1 to a test scenario in `tests/invoice.sh`.

- [ ] `bin/fleet invoice <slug>` is a new subcommand.
      Required arg is the slug name (OR `--all`).
      Missing slug AND no `--all`: prints `invoice:
      usage: bin/fleet invoice <slug|--all> [--month
      YYYY-MM] [--ytd] [--redact] [--json]` to stderr,
      exit 2 per LESSONS 2026-06-01. Unknown slug:
      prints `invoice: slug <name> not found.
      discovered slugs: <list>` to stderr, exit 2.
      Per LESSONS 2026-05-30 (`grep -F --` trap) the
      test assertion uses `grep -qF -- "$kw" "$out"`.
      Test asserts both refusals.
- [ ] The default month is LAST CALENDAR MONTH (so
      `fleet invoice sidebrew` run on 2026-06-19
      defaults to `--month 2026-05`). Per LESSONS
      2026-06-11 (BSD `date -j -f` fills missing time
      fields) the month-to-epoch conversion appends
      `T00:00:00` to `YYYY-MM-01` and uses the full
      format `'%Y-%m-%dT%H:%M:%S'`. The month-end
      boundary is the LAST DAY OF THAT MONTH at
      23:59:59 UTC. Test asserts via fixture with
      `FLEET_NOW_OVERRIDE=2026-06-19T08:00:00Z` that
      the default window is `2026-05-01T00:00:00Z`
      through `2026-05-31T23:59:59Z`.
- [ ] `bin/fleet invoice <slug> --month YYYY-MM`
      overrides the default. Invalid month format
      (not `YYYY-MM`, month out of 01-12 range):
      prints `invoice: --month must be YYYY-MM (got
      X)` to stderr, exit 2. Future month (after
      today): prints `invoice: --month cannot be in
      the future (got X)` to stderr, exit 2. Test
      asserts both refusals.
- [ ] The "PRs merged" count reads
      `pr_footer_posted` events in the month
      window. The "heal cycles" count reads
      `gate_failed` events whose subsequent commit
      message starts with `heal:`. The "send-backs"
      count reads `lesson_draft_emitted` events.
      The "runtime" sum reads
      `run_completed.duration_ms` summed across
      all runs in the window. Per LESSONS 2026-06-08
      every awk pass declares `BEGIN { count = 0 }`.
      Per LESSONS 2026-06-08 IFS=$'\t' middle-
      empty-field uses `-` sentinel. Test asserts
      all four numbers via fixture.
- [ ] The "Claude API spend" reads each
      `runs.jsonl` row's `cost_usd` field per
      LESSONS 2026-06-15 (one awk pass per slug,
      NOT per row). The "human-equiv hours
      displaced" is computed as `PRs_merged ×
      MANUAL_PR_MINUTES / 60`, where
      `MANUAL_PR_MINUTES` is read from the slug's
      `agents.config.sh` (default 75 if unset).
      Per LESSONS 2026-06-05 (export-in-subshell)
      the manifest read happens inside `( … )`
      with the export persisting only inside the
      subshell. Test asserts via two fixtures
      (one with the default, one with an
      override).
- [ ] The "Cursor Pro alternative" line is the
      fixed `$20.00 / month / seat`. The
      "Contractor alternative" line is
      `displaced_hours × CONTRACTOR_USD_PER_HOUR`,
      where `CONTRACTOR_USD_PER_HOUR` is a
      manifest knob (default 80). Both rates are
      documented in the README. Test asserts via
      fixture with a non-default contractor rate.
- [ ] The "verdict" line emits `net positive` when
      kit_cost ≤ 0.9 × min(cursor_alt,
      contractor_alt); `break-even` when within
      ±10%; `net negative` when kit_cost > 1.1 ×
      min(cursor_alt, contractor_alt). The
      `investigate` nudge appears ONLY on the
      negative side. Test asserts all three
      branches via fixture.
- [ ] The "this month vs last month" diff line is
      computed by running the SAME aggregator over
      the previous month's window in the SAME
      invocation (one extra awk pass per slug per
      LESSONS 2026-06-15). The line shows the
      % delta for PRs, cost, and $/PR. A first-
      ever-month (no prior data) renders
      `this month vs last month:  (no prior
      month data)`. Test asserts both branches via
      fixture.
- [ ] `bin/fleet invoice --all` sums every
      discovered slug into ONE fleet-wide invoice
      with a per-slug breakdown table appended.
      The verdict is computed on the SUM. Per
      LESSONS 2026-06-15 the per-slug loop runs
      ONE awk pass over each slug's events.jsonl
      AND ONE awk pass over each runs.jsonl —
      NOT per-month re-walks. Test asserts via
      fixture with 3 slugs that the total `date`
      invocations is < 10 across the whole
      `--all` run.
- [ ] `bin/fleet invoice <slug> --ytd` rolls up
      every month from January through the
      current month-to-date. Output prints one
      row per month plus a "YTD totals" footer
      line. Test asserts via fixture with
      `FLEET_NOW_OVERRIDE=2026-06-19` that 6 month-
      rows render (Jan-Jun, June partial).
- [ ] `bin/fleet invoice <slug> --redact` emits
      the same shape but with slug name replaced
      with `project-a`, costs banded per 0053's
      `portfolio_redact_text` convention, and any
      repo URL stripped. Per LESSONS 2026-06-15
      (`while (match(s, /pat/)) { s = before repl
      after }` infinite-loop trap) the redaction
      uses the CURSOR-based walk pattern, NOT
      `s = before repl after` recursion. Test
      asserts the redacted output contains no
      slug name from the discovered list AND no
      exact dollar amount.
- [ ] `bin/fleet invoice <slug> --json` emits
      one structured JSON object: `{"slug":
      "<name>", "month": "YYYY-MM", "prs_merged":
      <int>, "heal_cycles": <int>, "sendbacks":
      <int>, "runtime_minutes": <number>,
      "claude_usd": <number>, "displaced_hours":
      <number>, "cursor_alt_usd": <number>,
      "contractor_alt_usd": <number>, "net_vs_cursor":
      <number>, "net_vs_contractor": <number>,
      "cost_per_pr": <number>, "verdict":
      "net_positive|break_even|net_negative",
      "prior_month": {…}}`. JSON escape via
      `preflight_json_escape` per LESSONS
      2026-06-03 called directly per LESSONS
      2026-06-13 (no `*_json_escape` wrapper).
      Test asserts JSON validity via Node.
- [ ] `bin/fleet invoice --help` prints USAGE
      mentioning `--all`, `--month`, `--ytd`,
      `--redact`, `--json`. Per LESSONS 2026-05-30
      test asserts via `grep -qF -- "$kw"
      "$help_out"`. Help block ends with `exit 0`
      per LESSONS 2026-06-01.
- [ ] `bin/fleet invoice` is a PURE READER. NO
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
- [ ] `tests/invoice.sh` covers all 14 boxes
      above using `$HOME/.local/bin` stubs per
      LESSONS 2026-05-26 (PATH reset). Fixture
      `events.jsonl`, `runs.jsonl`, and
      `agents.config.sh` files live under
      `tests/fixtures/invoice/`. Per LESSONS
      2026-05-27 backup/restore via `cp`.
      Counts use `awk … END { print n+0 }` per
      LESSONS 2026-06-01. Per LESSONS 2026-06-08
      every awk script declares `BEGIN { count
      = 0 }`. Per LESSONS 2026-06-08 IFS=$'\t'
      middle-empty-field uses `-` sentinel. Per
      LESSONS 2026-06-15 the month-bucket math
      is pure awk arithmetic — no per-day
      `date -j -v` shellout. The clock is
      frozen via `FLEET_NOW_OVERRIDE`. Run-time
      budget: <10s.

## Out of scope

The dev agent will NOT do these even if they seem related.

- A LAUNCHD schedule that fires `fleet invoice` on
  the 1st of every month and emails the operator.
  v1 is operator-pulled. The README documents the
  plist snippet.
- AUTO-FORWARDING the invoice to an email/Slack/
  webhook. v1 prints to stdout; the operator pipes
  it themselves.
- A CUSTOM ALTERNATIVE-COST model beyond the two
  defaults (Cursor Pro $20/seat/mo, contractor
  $80/h). Each new comparison is one manifest knob
  + one printed line in a follow-up ticket.
- A QUARTERLY or ANNUAL report shape. v1 ships
  per-month and `--ytd`; quarterly is trivial to
  derive from `--ytd` output.
- A SAVINGS-OVER-TIME chart (12-month sparkline of
  net savings). That's 0058 `fleet trends`
  territory in v2.
- A FORECASTING column ("at current burn rate,
  next month's invoice will be $X"). v1 is
  descriptive only.
- INTEGRATING invoice with a real billing system
  (Stripe, QuickBooks). v1 prints text; export to
  an accounting tool is the operator's job.
- A `--diff <month-a> <month-b>` mode comparing
  two arbitrary months. v1 always compares the
  selected month to the immediately-prior month.
  Arbitrary diffing is a v2 candidate.
- AUTO-WARNING the operator (osascript / email)
  when the verdict flips from `net positive` to
  `net negative`. v1 is read-only. Auto-alerts
  are a separate ticket.
- A LIFETIME-VALUE row (total spend since first
  ever PR vs total alternative spend). v1 caps
  at YTD; LTV is a v2 candidate.

## Engineering notes

Files / patterns the dev should touch.

- `bin/fleet` — new `invoice()` dispatcher function
  placed next to the existing `weekly()` block
  (find via `grep -n '^weekly()' bin/fleet`). Per
  LESSONS 2026-05-26 (`tail` shadow) `invoice`
  does not collide with any coreutils binary.
- `bin/fleet` — nine helpers, ALL defined ABOVE
  the dispatcher block per LESSONS 2026-06-05
  (forward-reference trap):
  - `invoice_discover_slugs` — wraps
    `overview_discover_slugs`, returns
    alphabetical order.
  - `invoice_parse_month` — `YYYY-MM` validator +
    normalizer to a `[start_epoch, end_epoch]`
    pair. Per LESSONS 2026-06-11 the month-to-
    epoch conversion uses the FULL format
    `'%Y-%m-%dT%H:%M:%S'` with `T00:00:00`
    appended.
  - `invoice_walk_events` — ONE awk pass per slug
    over events.jsonl, binning every
    `pr_footer_posted`, `gate_failed`,
    `lesson_draft_emitted`, `run_completed` into
    BOTH the target month bucket AND the prior
    month bucket. Per LESSONS 2026-06-08
    `BEGIN { count = 0; prev_count = 0 }`. Per
    LESSONS 2026-06-08 IFS=$'\t' middle-empty-
    field uses `-` sentinel. Per LESSONS
    2026-06-15 the bucket math is pure awk
    arithmetic.
  - `invoice_walk_costs` — ONE awk pass per slug
    over runs.jsonl, same bucket math.
  - `invoice_read_manifest_knobs` — reads
    `MANUAL_PR_MINUTES` and
    `CONTRACTOR_USD_PER_HOUR` from
    `agents.config.sh` inside `( … )` per LESSONS
    2026-06-05 (export-in-subshell). Defaults
    are 75 and 80 respectively.
  - `invoice_compute_verdict` — pure-shell
    classifier returning `net_positive |
    break_even | net_negative` per AC #7.
  - `invoice_redact` — applies the
    `portfolio_redact_text` (0053) convention
    to a single line. Per LESSONS 2026-06-15
    the redaction uses the CURSOR-based walk
    pattern, NOT `s = before repl after`
    recursion.
  - `invoice_render_text` — text formatter per
    the Product-Owner example. Width via
    `preflight_visible_width` per LESSONS
    2026-06-05. Per LESSONS 2026-05-28 every
    printf of a slug name goes through `printf
    -- '%s'`.
  - `invoice_render_json` — JSON formatter.
    JSON escape via `preflight_json_escape`
    per LESSONS 2026-06-03 called directly
    per LESSONS 2026-06-13 (no
    `*_json_escape` wrapper).
- `bin/fleet` — `invoice()` end-state must be
  `exit 0` / `exit 2` on every code path per
  LESSONS 2026-06-01.
- `bin/fleet` — dispatcher block: `if [ "$CMD"
  = "invoice" ]; then invoice "$@"; fi`. Place
  AFTER the `weekly` dispatcher.
- `bin/fleet` — help banner block at the top of
  the file gets ONE new line: `fleet invoice
  <slug> monthly ROI receipt vs Cursor and
  contractor alternatives`. README "Daily ops"
  code block gets the same line, appended via
  the same single-edit pattern that avoided
  LESSONS 2026-05-25. README gets a separate
  short paragraph documenting
  `MANUAL_PR_MINUTES` and
  `CONTRACTOR_USD_PER_HOUR` manifest knobs.
- `AGENTS.md` — NO content change.
- `lib/common.sh` — NO changes.
- `prompts/` — NO changes.
- `tests/fixtures/invoice/` — NEW directory
  holding four slug subdirs (`net-positive`,
  `break-even`, `net-negative`, `first-month`)
  each with `events.jsonl`, `runs.jsonl`, and
  `agents.config.sh`. The events span 3 months
  per slug so the "this month vs last month"
  comparison can fire. A fifth `redacted-target`
  slug exercises AC #11.
- `tests/invoice.sh` — top of file mirrors
  `tests/ticket-cost.sh` (closest prior reader;
  shares the runs.jsonl walk pattern). Stubs
  live under `$HOME/.local/bin` per LESSONS
  2026-05-26 (PATH reset). Counts use `awk …
  END { print n+0 }` per LESSONS 2026-06-01.
  Per LESSONS 2026-05-27 backup/restore via
  `cp`. The clock is frozen via
  `FLEET_NOW_OVERRIDE`. Per LESSONS
  2026-06-15 the month-bucket math is pure
  awk. Run-time budget: <10s.
- New deps: none. Pure shell + awk + Node
  (already a kit dep for JSON validation in
  the test).
- Public API: additive — `bin/fleet invoice`
  is a new subcommand. ZERO new event types,
  ZERO event writes, ZERO `lib/common.sh`
  changes, ZERO `prompts/` changes. Two new
  optional `agents.config.sh` knobs
  (`MANUAL_PR_MINUTES`, `CONTRACTOR_USD_PER_HOUR`)
  with documented defaults; existing manifests
  without these knobs render the default-
  weighted invoice — no breaking change.
- BREAKING flag: NO. PR body affirms "pure
  reader, no events.jsonl writes, no `fleet_*`
  signature changes, two optional manifest
  knobs with defaults that preserve current
  behavior."
- Reinstall required: NO. `lib/` and `prompts/`
  are untouched. Manifests without the two new
  knobs work unchanged.
- LESSONS to defend against: 2026-05-25
  (README "Daily ops" code block addition),
  2026-05-26 (`tail` shadow), 2026-05-26 (PATH
  reset — stubs in `$HOME/.local/bin`),
  2026-05-27 (`$(cat)` trap — use `cp` for
  backup/restore in tests), 2026-05-28 (printf
  leading-dash — every slug-name printf goes
  through `printf -- '%s'`), 2026-05-30
  (`grep -F --` trap), 2026-06-01 (`grep -c
  file || echo 0` double-print — counts use
  `awk … END { print n+0 }`), 2026-06-01
  (dispatcher fall-through — every code path
  ends `exit 0/2`), 2026-06-03 (UTF-8 sign-
  extension — JSON escape via
  `preflight_json_escape`), 2026-06-05
  (dispatcher forward-reference — all
  `invoice_*` helpers defined ABOVE the
  dispatcher), 2026-06-05 (bash 3.2 LC_ALL
  caching — any string-length op via
  `LC_ALL=C awk`), 2026-06-05 (export-in-
  subshell trap — manifest reads inside
  `( … )`), 2026-06-08 (awk empty-string-key
  — `BEGIN { count = 0 }`), 2026-06-08
  (IFS=$'\t' middle-empty-field — sentinel
  `-`), 2026-06-11 (BSD `date -j -f` fills
  missing time fields with NOW-of-day —
  month-to-epoch uses full
  `'%Y-%m-%dT%H:%M:%S'` format), 2026-06-13
  (no `*_json_escape` wrapper around
  `preflight_json_escape` — called
  directly), 2026-06-15 (per-day shellout
  inside per-slug loops is O(window ×
  N_slugs) — bucket math is pure awk
  arithmetic), 2026-06-15 (`while
  (match(s, /pat/)) { s = before repl
  after }` infinite-loop trap — redact uses
  CURSOR-based walk pattern).
- This ticket compounds 0047 (`fleet
  ticket-cost` — invoice's per-PR cost row
  uses the same `runs.jsonl` source), 0025
  (`fleet weekly` — invoice is the monthly
  version of the Sunday snapshot), 0027
  (`fleet badge` — invoice's verdict line
  uses the same ROI inputs), 0044 (`fleet
  pr-footer` — invoice aggregates per-PR
  cost), 0058 (`fleet trends` — "this
  month vs last month" line is the 2-week
  sparkline collapsed to two scalars),
  0019 (`fleet overview` — reuses
  `overview_discover_slugs` for `--all`),
  0048 (`fleet recap` — invoice is the
  financial complement to recap's
  narrative), 0053 (`fleet portfolio
  --redact` — invoice's `--redact` mode
  reuses the same redaction pattern). Per
  P-1 the diff is small: ~340 lines of
  `invoice_*` helpers + ~300 lines of
  test + 5 fixture slug subdirs + one
  help-text line + one README paragraph.

## Implementation log

(Appended by the implementation-dev agent during execution.)

- 2026-06-19 [implementation-dev] picked up ticket on `feat/0061-fleet-invoice-monthly-roi-receipt`. Plan: ~340 lines of `invoice_*` helpers in `bin/fleet` (pure reader of events.jsonl + runs.jsonl), 5 fixture slug subdirs under `tests/fixtures/invoice/`, `tests/invoice.sh` covering 14 ACs, +1 help-banner line + 1 README "Daily ops" line + 1 README paragraph documenting `MANUAL_PR_MINUTES` and `CONTRACTOR_USD_PER_HOUR` knobs. All helpers placed above the dispatcher per LESSONS 2026-06-05; awk-internal Julian-day month-bucket math per LESSONS 2026-06-15 (no per-day `date -j -v` shellout); `preflight_json_escape` called directly per LESSONS 2026-06-13; redact pass uses the cursor-walk pattern per LESSONS 2026-06-15. `invoice()` end-state is `exit 0`/`exit 2` on every code path per LESSONS 2026-06-01. NO `lib/common.sh` or `prompts/` changes.
