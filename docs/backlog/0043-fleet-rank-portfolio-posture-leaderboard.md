---
id: 0043
title: fleet rank orders every project on a single posture metric in one leaderboard
status: shipped
priority: P2
area: observability
created: 2026-06-09
owner: gtm-innovation
---

## User story

As a fleet operator running 5+ projects (agent-fleet, courtiq,
digitalcraft, almanac, fleet-control, plus whatever new project I
adopted last week via `onboarding-check` from ticket 0041), who
already has `fleet diff <a> <b>` (ticket 0038) to compare two slugs
side-by-side but no surface that orders ALL of them on one metric, I
want `bin/fleet rank --by <metric>` to print a single leaderboard
showing every project in the fleet ranked best-to-worst on one of:
ROI ($ shipped / $ spent), heal-rate (merges / heal-attempts),
draft-promotion debt (open DRAFT blocks in LESSONS.md), paused-hours
(cumulative ship_paused minutes in the window), or send-back rate
(send-backs / pr_opened) — so I can SEE in 5 seconds which project is
the portfolio-level outlier worth investigating, instead of running
`fleet diff` pairwise N choose 2 times and doing the ranking in my
head.

## Why now (four lenses)

### Product Owner
The kit's cross-project surfaces today are TWO-AT-A-TIME (`fleet
diff <slug-a> <slug-b>` from ticket 0038) or ALL-SUMMARY (`fleet
overview` from 0019 — one row per project, no ordering). Neither
answers "of my N projects, which one is the worst on metric M?"
without the operator doing the rank-sorting in their head.

For a fleet of 2 projects this is trivial. For a fleet of 5+ it is
the first surface that breaks down. The operator's recovery today
is `fleet overview | sort -k4` — but the overview table has fixed
column ordering, no per-metric sort flag, and the metrics most
useful for ranking (ROI, heal-rate, send-back rate) are not in
overview at all because they're per-window computations, not
point-in-time states.

The smallest meaningful unit of value is one command, one metric
flag, one ranked table:

```
fleet rank --by roi --since 14d

#  SLUG          ROI       SHIPPED  SPENT($)  Δ FROM MEDIAN
1  agent-fleet   2.34x     19       8.42      +0.91
2  digitalcraft  1.78x     11       6.18      +0.35
3  almanac       1.43x     7        4.92      median
4  courtiq       0.81x     14       17.30     -0.62
5  fleet-control 0.62x     5        8.10      -0.81

rank: 5 projects ranked by ROI (best=top) over 14d.
        outlier (>2x median spread): courtiq (-0.62 from median).
        recommend: `fleet diff courtiq agent-fleet --since 14d` next.
```

Subtraction: the operator stops doing pairwise diffs to find the
outlier. The rank table FINDS the outlier and recommends the next
command (`fleet diff <outlier> <leader>`) that drills in. Per P-5
(operator confidence over feature richness), the win is converting
"which project should I worry about?" into a single read.

### Stakeholder
This is **moat-deepening on the portfolio-management axis** — the
kit's first surface that treats the FLEET as the unit of analysis,
not the project. Every other surface either treats one project at a
time (`fleet doctor`, `fleet weekly`, `fleet badge`) or summarizes
across them without ordering (`fleet overview`). The portfolio
metric is the first read that becomes MORE valuable as the operator
adopts MORE projects — every other surface stays the same value per
project regardless of fleet size.

Per P-6 (telemetry is the source of truth), `rank` is a PURE
reader of `events.jsonl` files across every discovered project —
no new event types, no state file. The metric computations REUSE
helpers already shipped:
- ROI: `weekly` (0025) shipped + spent per slug per window.
- heal-rate: `incident` (0037) heal-attempts per slug.
- draft-debt: `inbox` (0026) DRAFT marker count per project.
- paused-hours: `diff` (0038) ship_paused/ship_resumed pairing
  helper (the awk empty-key trap from LESSONS 2026-06-08 applies
  directly).
- send-back rate: `weekly` (0025) send-back count per slug.

The work for v1 is the FOLD across slugs and the OUTLIER detection,
not the per-slug metric. Per P-1 (smallest viable change), the diff
is the rank-and-render pipeline, not the metric pipeline.

Per P-3 (heal in-flight before new work), `rank` is read-only and
cheap (~one events.jsonl read per slug, ~5 slugs typical) — it
never blocks heal work.

Compounds 0038 (`fleet diff` — the rank surface's "recommend
next" footer routes the operator into `fleet diff outlier
leader` for the drill-down), 0019 (`fleet overview` — shares the
multi-slug discovery), 0025 (`fleet weekly` — shares the ROI
computation per slug), 0037 (`fleet incident` — provides the
heal-attempts metric).

### User (operator on a Sunday evening reviewing the portfolio)
Operator runs `fleet rank --by roi --since 14d`. Sees agent-fleet
at the top (2.34x) and fleet-control at the bottom (0.62x). The
footer says `recommend: fleet diff fleet-control agent-fleet
--since 14d next.` Operator runs that command, gets the
two-project side-by-side breakdown from ticket 0038, sees that
fleet-control's spend is concentrated on heal retries.

Total operator time: 30 seconds (rank) + 30 seconds (diff) = one
minute to go from "I have 5 projects, something feels off this
week" to "fleet-control is the outlier and the root cause is
heal retries." Without `rank`, the same investigation is
`fleet overview` (no ROI column) + `fleet weekly` × 5 slugs
(copy/paste ROI per slug into a notepad) + manual sort + `fleet
diff` of the top vs the bottom = ~10 minutes of glue work.

The 30-second floor is what makes the portfolio investigable on a
Sunday evening at all. Per P-5, the win is converting "I'll look
at this Tuesday when I have time" into "I'll look at this now."

### Growth
A friend running 1 or 2 projects on their own claude loop reads
the `fleet rank` output and sees the kit's structural answer to
"what happens as my fleet grows?" — the rank surface doesn't get
slower or less useful at 5 projects than 2; it gets more useful.
That answer is what migrates a friend from "I'll keep my
hand-rolled loop for now" to "I should adopt fleet because my
hand-rolled loop has no portfolio surface."

The acquisition path now has a "show me" moment specifically for
operators with EXISTING fleets: `fleet kickstart --demo`
(ticket 0023) is for "I've never run an autonomous loop"; `fleet
preflight + onboarding-check` (0032 + 0041) is for "I want to
adopt the kit on ONE project"; `fleet rank` is for "I already
run multiple agents and want to see them as a portfolio." Three
acquisition moments, three personas.

Per the brief's "what about a `fleet rank` that orders ALL fleet
projects on a single posture metric" — this is the direct answer
and the natural follow-on to `fleet diff` (0038).

## Acceptance criteria

Each box maps 1:1 to a test scenario in `tests/rank.sh`.

- [ ] `bin/fleet rank --by <metric>` is a new subcommand. `--by`
      is REQUIRED. Missing: print `rank: usage: bin/fleet rank
      --by <roi|heal-rate|draft-debt|paused-hours|sendback-rate>
      [--since Nd|YYYY-MM-DD] [--json]` to stderr, exit 2 per
      LESSONS 2026-06-01 (dispatcher fall-through trap).
      Unknown metric: print `rank: unknown metric "<name>"
      (valid: roi heal-rate draft-debt paused-hours sendback-
      rate)` to stderr, exit 2. Test asserts both branches.
- [ ] Five v1 metrics are supported: `roi`, `heal-rate`,
      `draft-debt`, `paused-hours`, `sendback-rate`. Each one
      computes one number per slug from that slug's
      events.jsonl over the window. ROI and sendback-rate use
      `weekly()`'s existing per-slug compute helpers
      (~line 2512); heal-rate uses `incident()`'s helper
      (~line 9640); draft-debt uses `inbox()`'s
      `inbox_count_drafts` (~line 3253); paused-hours uses
      `diff()`'s ship_paused/ship_resumed pairing helper
      (~line 8898). Test asserts each metric against a fixture
      events.jsonl set with known values.
- [ ] The rank order is BEST-AT-TOP, where "best" depends on
      the metric: ROI and heal-rate are higher-is-better
      (descending); draft-debt, paused-hours, and sendback-
      rate are lower-is-better (ascending). The rendered
      column always reads top-to-bottom as "least-concerning to
      most-concerning." Ties break alphabetically by slug.
      Test asserts the ordering for each metric direction
      against fixtures.
- [ ] The `Δ FROM MEDIAN` column shows each slug's distance
      from the median value in the same units as the metric.
      Even N: median = average of the two middle values; odd
      N: median = middle value. The median row prints `median`
      in the Δ column. Test asserts median computation for
      both odd and even N.
- [ ] The "outlier" line in the summary names any slug whose
      `|Δ FROM MEDIAN| > 2 × median absolute deviation (MAD)`
      OR whose value is the maximum in the wrong direction
      (the worst-ranked slug if the spread justifies). The
      outlier line is OMITTED when no slug crosses the
      threshold (the fleet is in a tight cluster). The
      `recommend:` line names `fleet diff <outlier>
      <leader>` for the drill-down (where leader = the
      best-ranked slug). Test asserts the outlier-present and
      outlier-absent branches via fixtures designed to
      exercise each.
- [ ] `bin/fleet rank --by <metric> --since <Nd|YYYY-MM-DD>`
      overrides the default 14-day window. Test asserts each
      format.
- [ ] `bin/fleet rank --by <metric> --json` emits one JSON
      object per slug `{"slug": <name>, "rank": <int>,
      "value": <num>, "delta_from_median": <num>,
      "is_outlier": <bool>}`, one per line, followed by a
      summary object `{"summary": {"metric": <name>, "window":
      "<Nd>", "median": <num>, "outlier": "<slug | null>",
      "leader": "<slug>"}}`. JSON escape goes through
      `preflight_json_escape` per LESSONS 2026-06-03. Test
      asserts JSON validity via Node.
- [ ] `bin/fleet rank --help` prints USAGE mentioning `--by`,
      `--since`, `--json`, and the five v1 metrics. Test
      asserts via `grep -qF -- "$kw" "$help_out"` per LESSONS
      2026-05-30. Help block ends with `exit 0` per LESSONS
      2026-06-01.
- [ ] Empty fleet (zero projects discovered) prints `rank: no
      projects discovered. run \`fleet onboard\` to adopt
      one.` exit 0. Single-slug fleet prints
      `rank: only 1 project; nothing to rank.` exit 0. Test
      asserts both branches.
- [ ] `bin/fleet rank` is a PURE READER. NO `events.jsonl`
      writes, NO `fleet_emit_event` calls. Test asserts the
      kit's events channel has unchanged byte size before and
      after invocation (`stat -f %z` on macOS).
- [ ] The metric computation helpers REUSE the existing
      per-slug helpers from `weekly`, `incident`, `inbox`,
      `diff` rather than re-implementing them. The shape is
      one wrapper helper per metric that calls the existing
      helper for ONE slug at a time, then folds across slugs.
      Test asserts via a grep that `rank_compute_<metric>`
      calls into the existing per-slug helper namespace
      (`weekly_compute_*`, `incident_count_*`, etc.).
- [ ] `lib/common.sh` — NO changes. `rank` is a pure caller
      of existing helpers. NO new `fleet_*` helpers, NO
      signature changes. Test asserts via `git diff
      --name-only main…HEAD -- lib/common.sh` returns empty.
- [ ] `prompts/` — NO changes. Test asserts via `git diff
      --name-only main…HEAD -- prompts/` returns empty.
- [ ] `tests/rank.sh` covers all 13 boxes above using
      `$HOME/.local/bin` stubs per LESSONS 2026-05-26.
      Fixture events.jsonl files for 5 synthetic slugs live
      under `tests/fixtures/rank/`. Per LESSONS 2026-05-27
      backup/restore via `cp`. Counts use `awk … END {
      print n+0 }` per LESSONS 2026-06-01. Median computation
      via awk (sort + middle index — per LESSONS 2026-06-08
      the awk script declares `BEGIN { count = 0 }` so the
      first sample doesn't land under `arr[""]`). The clock
      is frozen via `FLEET_NOW_OVERRIDE`. Run-time budget:
      <10s.

## Out of scope

The dev agent will NOT do these even if they seem related.

- A `--all-metrics` flag that prints five tables in one
  invocation. v1 is one metric per call. Composition is
  one shell line (`for m in roi ...; do fleet rank --by $m;
  done`).
- Weighting metrics into a composite "fleet posture score."
  That requires operator-defined weights per metric and is
  a follow-up ticket; v1 is single-metric ranking only.
- Auto-routing the outlier into an action (e.g. "open a
  triage issue for the outlier"). The footer RECOMMENDS the
  next read; the operator runs it. Auto-action violates the
  AGENTS.md operator-confidence-over-richness Hard NO
  spirit.
- A "rank over time" mode (the slug whose rank has
  DEGRADED most over the window). v2.
- Combining `rank` with `streak` (ticket 0042) — e.g. "rank
  by current streak." Composes naturally but v1 is
  events.jsonl metrics only, not derived counters from
  another reader.
- Modifying `fleet weekly`, `fleet incident`, `fleet diff`
  to call into a unified metric library. v1 REUSES their
  helpers as-is; the unification is a follow-up if it's ever
  needed.
- A launchd schedule. Operator-invoked only.
- Sending the rank output to fleet-control's portal. v1 is
  stdout only; fleet-control's portal reads the same
  events.jsonl files and computes its own rendering.

## Engineering notes

Files / patterns the dev should touch. Specific enough that the dev
doesn't have to re-discover the architecture.

- `bin/fleet` — new `rank()` dispatcher function placed
  next to the existing `diff()` block (find via
  `grep -n '^diff()' bin/fleet`; the diff dispatcher is at
  ~line 8898 — note the LESSONS 2026-05-26 `tail` shadow
  trap: the existing implementation already names this
  function `diff()` which DOES NOT shadow a coreutils
  binary the script shells out to, so the pattern is safe;
  `rank` similarly doesn't shadow anything).
- `bin/fleet` — eight helpers, ALL defined ABOVE the
  dispatcher block per LESSONS 2026-06-05 (forward-
  reference trap):
  - `rank_discover_slugs` — reuses the existing
    `overview_discover_slugs` helper (~line 6995 — already
    above the dispatcher block; safe to invoke).
  - `rank_compute_roi` — wraps the existing
    `weekly_compute_roi_for_slug` helper (per AC#11), one
    slug at a time.
  - `rank_compute_heal_rate` — wraps the existing
    `incident_count_heal_attempts` helper, one slug at a
    time.
  - `rank_compute_draft_debt` — wraps the existing
    `inbox_count_drafts` helper, one slug at a time.
  - `rank_compute_paused_hours` — wraps the existing
    `diff_paused_hours` helper (~line 8950, the helper
    introduced in ticket 0038 with the LESSONS 2026-06-08
    fix), one slug at a time.
  - `rank_compute_sendback_rate` — wraps the existing
    `weekly_compute_sendback_rate_for_slug` helper, one
    slug at a time.
  - `rank_median_and_mad` — awk script that takes a list
    of numbers and emits `median<TAB>mad`. Per LESSONS
    2026-06-08 the awk script declares `BEGIN { count = 0
    }` so the first sample doesn't land under `arr[""]`.
    Per LESSONS 2026-06-08 IFS=$'\t' middle-empty-field,
    the consumer maps `-` sentinels for the empty-fleet
    case.
  - `rank_render_text` and `rank_render_json` — formatters
    per AC#1 and AC#7. Width via
    `preflight_visible_width` per LESSONS 2026-06-05; JSON
    escape via `preflight_json_escape` per LESSONS
    2026-06-03.
- `bin/fleet` — `rank()` end-state must be `exit 0`
  (success), `exit 2` (usage error) on every code path per
  LESSONS 2026-06-01.
- `bin/fleet` — dispatcher block: `if [ "$CMD" = "rank" ];
  then rank "$@"; fi`. Place AFTER the `diff` dispatcher
  (~line 8898). Per LESSONS 2026-06-05 (forward-
  reference trap), confirm every helper `rank` calls is
  defined ABOVE the dispatcher block — including the
  existing `weekly_compute_*`, `incident_count_*`,
  `inbox_count_*`, `diff_paused_hours` helpers (verify
  each is above the `rank` dispatcher line at write
  time).
- `bin/fleet` — help banner block at the top of the file
  (around line ~14) gets a new line: `fleet rank --by M
  rank every project on a single posture metric`. README
  "Daily ops" code block gets the same line.
- `AGENTS.md § Telemetry` — NO new bullet. `rank` is a
  pure reader. Test asserts via `git diff --name-only
  main…HEAD -- AGENTS.md` returns empty.
- `lib/common.sh` — NO changes.
- `prompts/` — NO changes.
- `tests/fixtures/rank/` — NEW directory under
  `tests/fixtures/` holding five synthetic events.jsonl
  files (one per slug) exercising each metric's full
  range plus an empty-fleet fixture and a single-slug
  fixture.
- `tests/rank.sh` — top of file mirrors `tests/diff.sh`
  and `tests/overview.sh`: stub `gh` under
  `$HOME/.local/bin` (`$HOME=$TMP/home` per LESSONS
  2026-05-26). Counts use `awk … END { print n+0 }` per
  LESSONS 2026-06-01. Per LESSONS 2026-05-27 backup/
  restore via `cp`. The clock is frozen via
  `FLEET_NOW_OVERRIDE`. Run-time budget: <10s.
- New deps: none. Pure shell + awk + existing helpers.
- Public API: additive — `bin/fleet rank` is a new
  subcommand. ZERO new event types, ZERO event writes.
- BREAKING flag: NO. PR body affirms "pure reader,
  reuses existing per-slug metric helpers from `weekly`,
  `incident`, `inbox`, `diff`. No `fleet_*` signature
  changes."
- Reinstall required: NO. `lib/` and `prompts/` are
  untouched.
- LESSONS to defend against: 2026-05-25 (load-bearing
  docs — README "Daily ops" code block addition).
  2026-05-26 (`tail` shadow — `rank` and `rank_*` helpers
  do not shadow coreutils). 2026-05-26 (PATH reset —
  stubs go in `$HOME/.local/bin`). 2026-05-27 (`$(cat)`
  trap — fixture restore uses `cp`). 2026-05-28 (printf
  leading-dash — every metric name and slug name goes
  through `printf -- '%s'`). 2026-05-30 (`grep -F --`
  trap — help text uses `grep -qF --`). 2026-06-01
  (`grep -c file || echo 0` double-print — counts use
  `awk … END { print n+0 }`). 2026-06-01 (dispatcher
  fall-through — `rank()` ends with explicit `exit N`).
  2026-06-03 (UTF-8 sign-extension — JSON escape goes
  through `preflight_json_escape`). 2026-06-05
  (dispatcher forward-reference — helpers above
  dispatcher block; verify EACH existing helper invoked
  is above the `rank` dispatcher line). 2026-06-05
  (bash 3.2 LC_ALL caching — width via
  `preflight_visible_width`). 2026-06-08 (awk
  empty-string-key — `rank_median_and_mad` BEGIN block
  initializes counters; same trap applies to every
  fold-across-slugs awk script). 2026-06-08
  (IFS=$'\t' middle-empty-field — consumer scripts use
  `-` sentinels).
- This ticket compounds 0019 (`fleet overview` — shares
  the multi-slug discovery), 0025 (`fleet weekly` —
  shares the ROI and sendback-rate compute helpers),
  0026 (`fleet inbox` — shares the draft-debt helper),
  0037 (`fleet incident` — shares the heal-attempts
  helper), 0038 (`fleet diff` — shares the
  paused-hours helper and is the recommended drill-down
  the rank footer routes the operator into). Per P-1
  the diff is small: ~350 lines of `rank_*` wrappers
  + median/MAD + render + ~250 lines of test +
  fixture set + one help-text line + one README
  line. The metric pipelines themselves are EXISTING
  helpers — zero reimplementation.

## Implementation log

(Appended by the implementation-dev agent during execution.)

- 2026-06-10 — branch `feat/0043-fleet-rank-portfolio-posture-leaderboard` opened
- 2026-06-10 — failing test added in `tests/rank.sh`
- 2026-06-10 — PR #88 opened, CI green (shellcheck + validate both pass)
- 2026-06-10 — merged to main
