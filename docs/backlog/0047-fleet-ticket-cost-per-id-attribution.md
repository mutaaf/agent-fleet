---
id: 0047
title: fleet ticket-cost <id> attributes every dollar spent shipping one ticket
status: in-progress
priority: P2
area: observability
created: 2026-06-11
owner: gtm-innovation
---

## User story

As a fleet operator looking at last week's $8.42 spend and asking
"which ticket cost the most? was 0042 expensive because it was hard,
or because the loop healed it 5 times?" — who today has NO per-ticket
attribution despite every `runs.jsonl` row carrying a `result_head`
that references the ticket id and every PR having a ticket-id in its
title — I want `bin/fleet ticket-cost <id> [--slug <name>]` to print
one line per `runs.jsonl` row attributable to the ticket plus a total
("ticket 0042: 7 runs, 4 heals, $1.83 total — 3.2x the median ticket
cost in 30d"), so I can see which specific work is expensive and
decide whether to refine prompts, tighten the spec, or accept it as
inherent complexity.

## Why now (four lenses)

### Product Owner
The kit has TWO budget surfaces today:
- `MAX_DAILY_USD` cap (ticket 0004) — the bound.
- `fleet weekly` (0025) — the per-slug 7-day rollup.

Neither answers "how much did THIS TICKET cost?" — the smallest
unit a human operator naturally reasons about. The operator's
recovery today is to manually `grep "0042" runs.jsonl | jq
'.total_cost_usd' | awk 'sum+=$1 END print sum'` for each ticket
they wonder about. On a fleet with 40 shipped tickets per month,
that's not happening — the operator just doesn't know which
tickets are expensive.

The smallest meaningful unit of value is one command, one
attribution table:

```
fleet ticket-cost 0042 --slug agent-fleet

ticket 0042 — fleet streak shows the longest continuous green-day run per project

  2026-06-10 09:41:17  ship   $0.31  6m12s  pr=#87 result_head="branch feat/0042-streak-green-days opened..."
  2026-06-10 10:41:09  ship   $0.27  5m44s  pr=#87 result_head="HEAL #87 heal: shellcheck SC2086..."
  2026-06-10 11:41:22  ship   $0.18  3m21s  pr=#87 result_head="HEAL #87 heal: test fixture path..."
  2026-06-10 12:41:33  ship   $0.42  8m07s  pr=#87 result_head="all green, merged"
  2026-06-10 12:42:01  review $0.05  0m51s  pr=#87 result_head="--comment sign-off"

ticket-cost: $1.23 across 5 runs (1 ship-pickup + 2 heals + 1 merge + 1 review)
             vs median ticket cost in agent-fleet (30d): $0.47
             ratio: 2.6x — above median; heals account for 41% of cost
             open prompts-suggest? recurring "shellcheck SC2086" in cluster
```

Subtraction: the operator stops doing the per-ticket grep AND
gains a "which tickets cost most relative to median" routing
signal that points at prompts-suggest (0045) for follow-up.

Per P-5 (operator confidence over feature richness), the win is
converting "I have no idea where my $8.42 went" into "I know
ticket 0042 was 2.6x median and 41% of its cost was heals — I
should look at the heal cluster."

### Stakeholder
This is **moat-deepening on the cost-attribution axis** — the
kit's first surface that answers "which UNIT OF WORK was
expensive?" rather than "which day / week / project was
expensive?" The unit shifts from time-window to ticket because
ticket is the natural human-meaningful object.

Per P-6 (telemetry is the source of truth), the attribution
is a PURE READER of `runs.jsonl` plus the per-slug
`events.jsonl` (for the PR→ticket correlation when the
`result_head` doesn't cite the ticket directly). The
attribution algorithm:
1. Walk `runs.jsonl` for the slug.
2. Filter rows whose `result_head` contains the ticket id
   (`0042` or `#0042` or `ticket 0042`).
3. ALSO include rows whose `result_head` cites a PR number
   AND that PR number's `pr_opened` event in
   `events.jsonl` carries a branch matching the ticket id
   (`feat/0042-*`, `eng/0042-*`).
4. Sum `total_cost_usd` over the matching rows.
5. Compute the per-slug median ticket cost over the
   trailing 30 days for the ratio comparison.

Per P-1 (smallest viable change), the diff is the
filter + fold + render. No new event types, no new state
file.

Compounds 0004 (`MAX_DAILY_USD` — shares the
`runs.jsonl` cost source), 0025 (`fleet weekly` —
shares the median-cost compute), 0027 (`fleet badge` —
shares the per-slug cost fold), 0044 (`fleet pr-footer`
— if shipped, the per-PR receipt's `cost` value is one
input to this command's per-ticket sum).

Per P-3 (heal in-flight before new work), `ticket-cost`
is read-only and cheap (~one runs.jsonl read per slug) —
never blocks heal work.

### User (operator on a Sunday morning reviewing the
weekly ROI rollup)
Operator runs `fleet weekly`, sees total spend $8.42.
Asks "where did $8.42 go?" Runs `fleet ticket-cost
0042` (the most-talked-about ticket of the week). Sees
$1.23, 41% heals, ratio 2.6x. Runs `fleet ticket-cost
0043`. Sees $0.51, no heals, ratio 1.1x. Now the
operator knows: 0042 was the outlier. The follow-up
question "why?" is answered by the helpful footer
("recurring 'shellcheck SC2086' in cluster") which
routes the operator to `fleet prompts-suggest`
(ticket 0045) for the structural fix.

Total operator time: 90 seconds to know where the
week's spend went and what the next action is. Without
this command, the same investigation is grep + jq +
awk + manual sorting = ~10 minutes of glue.

Per P-5, the win is converting "$X was spent
somewhere" into "$X was spent here; do this next."

### Growth
A friend evaluating the kit who has been running a
hand-rolled claude loop and is curious about cost
gets a "show me" moment: `fleet ticket-cost 0042
--slug your-project` answers a question the friend's
hand-rolled loop CANNOT answer at all (because their
loop's cost log isn't ticket-keyed). The kit's
budget telemetry compounds with its ticket telemetry
in a way that no hand-rolled loop reproduces.

This is also the surface that makes the kit's "$X
total" claim CREDIBLE — `fleet badge` (0027) says
"$5.83 over 30 days" but the skeptical reader has
no way to drill in. `ticket-cost` IS the drill-in.

Per the brief's "Cost transparency. Budget caps
shipped, but is there per-ticket attribution
('ticket 0042 cost $X to ship')?" — this is the
direct answer.

The acquisition path now has six surfaces; this
ticket adds the seventh, the "drill into the
per-ticket cost" trust artifact. Different from
pr-footer (0044, which shows cost on the PR) —
ticket-cost shows cost on the TICKET (which is
the operator's mental model unit, distinct from
the PR which is GitHub's unit).

## Acceptance criteria

Each box maps 1:1 to a test scenario in `tests/ticket-cost.sh`.

- [ ] `bin/fleet ticket-cost <id>` is a new subcommand. Takes
      a single ticket id argument (`0042` or `42` or `#0042`
      — all normalize to the 4-digit zero-padded form).
      Missing id: print `ticket-cost: usage: bin/fleet
      ticket-cost <id> [--slug <name>] [--since Nd] [--json]`
      to stderr, exit 2 per LESSONS 2026-06-01.
- [ ] Default discovery: walks every project's `runs.jsonl`
      under the standard discovery roots. `--slug <name>`
      restricts to one project. If `--slug` is omitted AND
      the ticket id matches multiple projects' runs, print
      a disambiguation table:
      `ticket-cost: ticket <id> appears in 3 projects:` then
      one row per project. Test asserts via fixture
      `runs.jsonl` files across multiple slugs.
- [ ] The attribution filter is: a `runs.jsonl` row is
      attributable to ticket `<id>` if (a) its
      `result_head` field contains the substring `<id>`
      (zero-padded) OR (b) the row cites a PR number AND
      that PR's `pr_opened` event in the same slug's
      `events.jsonl` carries a `branch` field matching
      `^(feat|chore/gtm-|eng|revert)/<id>-`. Test asserts
      both filters against fixtures.
- [ ] The render lists one row per attributable run in
      chronological order: `<utc-date> <utc-time> <phase>
      $<cost> <duration> <result_head_first_80>`. The
      summary line is
      `ticket-cost: $<sum> across <N> runs (<breakdown>)`
      where `<breakdown>` counts phases (e.g. `1 ship +
      2 heals + 1 review`). Test asserts the render
      against a fixture set.
- [ ] The "vs median" comparison line computes the
      median ticket cost across all attributable
      tickets in the slug over the trailing 30 days
      (default; configurable via `--since`). For each
      ticket id appearing in the window, compute the
      sum of `total_cost_usd` over its attributable
      runs; the median is the middle value of those
      sums. The ratio is `<this_ticket_sum> /
      <median>` to one decimal. Test asserts the
      median computation via fixtures with known
      values.
- [ ] When the ratio is > 2.0x median, the summary
      line includes a helpful follow-up suggesting
      `fleet prompts-suggest --since 30d` for any
      heal-driven cost AND `fleet provenance <pr>`
      for any single-run-driven cost (ticket 0029).
      Test asserts via fixtures designed to
      exercise each.
- [ ] The HEAL breakdown attribution: each row whose
      `result_head` starts with `HEAL` (matching
      LESSONS 2026-05-25 "lib/ changes need a
      fleet-wide reinstall" convention from the ship
      runner's exit summary) is counted as a heal.
      The summary line reports
      "heals account for <N>% of cost" when heals
      contribute ≥ 25% of the ticket's total cost.
      Test asserts via a fixture with a known heal
      ratio.
- [ ] `bin/fleet ticket-cost <id> --json` emits one
      JSON object per attributable run plus a
      summary object. Schema:
      `{"slug": <name>, "ts": "<iso>", "phase":
      "<phase>", "cost": <num>, "duration_ms":
      <int>, "result_head": "<text>",
      "is_heal": <bool>}` per row,
      `{"summary": {"ticket": "<id>", "slug":
      "<name>", "total_cost": <num>, "run_count":
      <int>, "heal_count": <int>,
      "median_30d": <num>, "ratio": <num>}}`.
      JSON escape via `preflight_json_escape` per
      LESSONS 2026-06-03. Test asserts JSON
      validity via Node.
- [ ] `bin/fleet ticket-cost <id> --since <Nd|YYYY-MM-DD>`
      overrides the default 30-day median-comparison
      window AND restricts the attribution scan. Test
      asserts each format.
- [ ] `bin/fleet ticket-cost --help` prints USAGE
      mentioning the ticket id arg, `--slug`,
      `--since`, `--json`. Test asserts via
      `grep -qF -- "$kw" "$help_out"` per LESSONS
      2026-05-30. Help block ends with `exit 0`.
- [ ] Empty case (ticket id has zero attributable
      runs): `ticket-cost: ticket <id> has no
      attributable runs in <window>. Either it
      hasn't shipped yet, or runs.jsonl was rotated
      out (see `events.jsonl.archive/`).` exit 0.
      Test asserts.
- [ ] `bin/fleet ticket-cost` is a PURE READER.
      NO `events.jsonl` writes, NO
      `fleet_emit_event` calls. Test asserts the
      kit's events channel has unchanged byte size
      before and after invocation.
- [ ] `lib/common.sh` — NO changes. `ticket-cost`
      is a pure caller of existing reads. Test
      asserts via `git diff --name-only main…HEAD
      -- lib/common.sh` returns empty.
- [ ] `prompts/` — NO changes. Test asserts via
      `git diff --name-only main…HEAD --
      prompts/` returns empty.
- [ ] `tests/ticket-cost.sh` covers all 14 boxes
      above using `$HOME/.local/bin` stubs per
      LESSONS 2026-05-26. Fixture `runs.jsonl`
      and `events.jsonl` files live under
      `tests/fixtures/ticket-cost/`. Per LESSONS
      2026-05-27 backup/restore via `cp`.
      Counts use `awk … END { print n+0 }` per
      LESSONS 2026-06-01. Median computation
      via awk per LESSONS 2026-06-08 with
      explicit `BEGIN { count = 0 }`. The
      clock is frozen via `FLEET_NOW_OVERRIDE`.
      Run-time budget: <8s.

## Out of scope

The dev agent will NOT do these even if they seem related.

- A FLEET-WIDE ranking ("show me the 10 most expensive
  tickets across every project"). v1 is one ticket at
  a time. The composition is `fleet rank --by
  ticket-cost-of-<id>` (ticket 0043's pattern); a
  cross-project follow-up if asked.
- A `--diff` mode comparing this ticket's cost to a
  prior ticket's. Composition is two `ticket-cost`
  invocations.
- An ML / regression analysis predicting future
  ticket cost from spec characteristics. v1 is
  per-completed-ticket attribution only.
- Auto-flagging expensive tickets at SHIP time
  ("ticket 0042 will likely cost >$1; confirm?").
  v1 is post-hoc; the operator is the budget
  authority and `MAX_DAILY_USD` is the bound.
- Per-COMMIT cost attribution. v1 is per-ticket
  (the natural human unit). A v2 may break down
  per-commit if the rolled-up signal isn't
  enough.
- Integration with the GitHub PR labels system
  (auto-applying a `cost-outlier` label). v1 is
  stdout / JSON only. Composition with PR labels
  is a follow-up.
- A historical "cost over time" chart for one
  ticket. v1 is one cost number; chart is fleet-
  control's job.
- Per-LESSONS cost attribution ("LESSON X has
  been cited in N heal commits worth $Y"). v1 is
  per-ticket; per-lesson is a separate research
  ticket.
- A launchd schedule. Operator-invoked only.

## Engineering notes

Files / patterns the dev should touch. Specific enough that the dev
doesn't have to re-discover the architecture.

- `bin/fleet` — new `ticket_cost()` dispatcher function
  placed next to the existing `weekly()` block (find via
  `grep -n '^weekly()' bin/fleet`, currently ~line 4125).
  Shape mirrors `weekly()` for the per-slug
  `runs.jsonl` walk + median computation. Per LESSONS
  2026-05-26 (`tail` shadow) `ticket_cost` and helpers
  do not collide with any coreutils binary.
- `bin/fleet` — six helpers, ALL defined ABOVE the
  dispatcher block per LESSONS 2026-06-05
  (forward-reference trap):
  - `ticket_cost_normalize_id` — given `42`, `0042`, or
    `#0042` returns `0042` (the canonical 4-digit
    zero-padded form). Per LESSONS 2026-05-28 every
    `printf` of the input goes through `printf --
    '%s'`.
  - `ticket_cost_discover_slugs` — reuses
    `overview_discover_slugs`.
  - `ticket_cost_attribute_runs_for_slug` — walks one
    slug's `runs.jsonl`, applies the
    substring-or-pr-correlation filter, emits one
    TSV line per attributable row. Per LESSONS
    2026-06-08, the awk script declares `BEGIN {
    count = 0 }`. Per LESSONS 2026-06-08 IFS=$'\t'
    middle-empty-field, uses `-` sentinel for
    optional fields.
  - `ticket_cost_median_for_slug` — computes the
    per-slug median ticket cost over the trailing
    `<since>` window. Per LESSONS 2026-06-08
    declares `BEGIN { count = 0 }` so the first
    sample doesn't land under `arr[""]`.
  - `ticket_cost_render_text` — formats the per-run
    table + summary line. Width via
    `preflight_visible_width` per LESSONS
    2026-06-05.
  - `ticket_cost_render_json` — emits one JSON
    object per row + summary. JSON escape via
    `preflight_json_escape` per LESSONS
    2026-06-03.
- `bin/fleet` — `ticket_cost()` end-state must be
  `exit 0` / `exit 2` per LESSONS 2026-06-01.
- `bin/fleet` — dispatcher block: `if [ "$CMD" =
  "ticket-cost" ]; then ticket_cost "$@"; fi`.
  Place AFTER the `weekly` dispatcher (~line 4404).
  Per LESSONS 2026-06-05 confirm every helper
  `ticket_cost` calls is defined ABOVE the
  dispatcher block.
- `bin/fleet` — help banner block at the top of
  the file (around line ~14) gets a new line:
  `fleet ticket-cost <id> attribute every $
  spent shipping one ticket`. README "Daily
  ops" code block gets the same line.
- `AGENTS.md § Telemetry` — NO new bullet.
  `ticket-cost` is a pure reader of `runs.jsonl`
  (cost record, not the events channel) and
  the existing `pr_opened` events. Test
  asserts via `git diff --name-only main…HEAD
  -- AGENTS.md` returns empty.
- `lib/common.sh` — NO changes.
- `prompts/` — NO changes.
- `tests/fixtures/ticket-cost/` — NEW
  directory under `tests/fixtures/` holding
  synthetic `runs.jsonl` and `events.jsonl`
  files: one slug with a "cheap" ticket
  (single run, $0.20), one with an
  "expensive" ticket (5 runs incl. 3 heals,
  $1.83), one with a ticket cited only by
  PR-branch correlation (no `result_head`
  match but `pr_opened` carries the
  ticket-prefixed branch), and one
  multi-slug case for the disambiguation
  branch.
- `tests/ticket-cost.sh` — top of file
  mirrors `tests/weekly.sh` and
  `tests/badge.sh`. Stubs `gh` under
  `$HOME/.local/bin` per LESSONS
  2026-05-26. Counts use `awk … END { print
  n+0 }` per LESSONS 2026-06-01. Per
  LESSONS 2026-05-27 backup/restore via
  `cp`. The clock is frozen via
  `FLEET_NOW_OVERRIDE`. Run-time budget:
  <8s.
- New deps: none. Pure shell + awk + existing
  helpers.
- Public API: additive — `bin/fleet
  ticket-cost` is a new subcommand. ZERO new
  event types, ZERO event writes.
- BREAKING flag: NO. PR body affirms "pure
  reader, no events.jsonl writes, no
  `fleet_*` signature changes."
- Reinstall required: NO. `lib/` and
  `prompts/` are untouched.
- LESSONS to defend against: 2026-05-25
  (load-bearing docs — README "Daily ops"
  code block addition), 2026-05-26
  (`tail` shadow), 2026-05-26 (PATH reset
  — stubs go in `$HOME/.local/bin`),
  2026-05-27 (`$(cat)` trap — fixture
  restore uses `cp`), 2026-05-28 (printf
  leading-dash — every result_head goes
  through `printf -- '%s'`), 2026-05-30
  (`grep -F --` trap), 2026-06-01
  (`grep -c file || echo 0` double-print
  — counts use `awk … END { print n+0
  }`), 2026-06-01 (dispatcher
  fall-through), 2026-06-03 (UTF-8
  sign-extension — JSON escape goes
  through `preflight_json_escape`),
  2026-06-05 (dispatcher
  forward-reference), 2026-06-05 (bash
  3.2 LC_ALL caching — width via
  `preflight_visible_width`),
  2026-06-08 (awk empty-string-key —
  every awk script declares `BEGIN
  { count = 0 }`), 2026-06-08
  (IFS=$'\t' middle-empty-field —
  sentinel for missing fields).
- This ticket compounds 0004
  (`MAX_DAILY_USD` — shares the
  `runs.jsonl` cost source), 0025
  (`fleet weekly` — shares the
  median-cost compute), 0027 (`fleet
  badge` — shares the per-slug cost
  fold), 0029 (`fleet provenance` —
  the recommended drill-down for
  single-expensive-run tickets),
  0044 (`fleet pr-footer` — the
  per-PR receipt is one input to
  this command's per-ticket sum if
  shipped), 0045 (`fleet
  prompts-suggest` — the
  recommended drill-down for
  heal-driven-cost tickets). Per
  P-1 the diff is small: ~300
  lines of `ticket_cost_*` helpers
  + ~200 lines of test + 4
  fixture sets + one help-text
  line + one README line.

## Implementation log

(Appended by the implementation-dev agent during execution.)

- 2026-06-11 — ticket filed by gtm-innovation
- 2026-06-11 — picked by implementation-dev on feat/0047-ticket-cost; tests-first then dispatcher + 6 helpers above the inline `if` block (LESSONS 2026-06-05 forward-reference trap).
