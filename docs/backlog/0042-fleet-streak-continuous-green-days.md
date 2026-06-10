---
id: 0042
title: fleet streak shows the longest continuous green-day run per project
status: in-progress
priority: P2
area: observability
created: 2026-06-09
owner: gtm-innovation
---

## User story

As a fleet operator returning to the portal on a Tuesday after a
quiet long-weekend where I didn't touch any project, who already gets
`fleet morning` (0036), `fleet inbox` (0026), and `fleet weekly`
(0025) — but whose autonomous loops have been QUIETLY shipping clean
PRs in the background and that "the loop just works" feeling has no
surface — I want `bin/fleet streak` to print a single table with one
row per project showing the current and longest "continuous green
day" run (a green day = at least one merged ship PR AND zero
`ship_paused` events AND zero `budget_block` events AND zero
unresolved `gate_failed` events for that UTC day), so that on a quiet
Tuesday I see a positive signal that justifies trusting the loop
through the NEXT quiet week — not just a list of unresolved
problems.

## Why now (four lenses)

### Product Owner
Every existing daily/weekly surface is centered on what NEEDS the
operator's attention: `fleet inbox` (the daily TODO the loop owes the
operator), `fleet morning` (the briefing of what changed overnight),
`fleet weekly` (the ROI rollup that surfaces draft-promotion debt),
`fleet diff` (which two projects diverged), `fleet incident` (a
single window assembled into a post-mortem). The surface for
"everything is fine and you don't need to do anything" is
structurally MISSING from the kit, by design — every read so far
optimizes for "what owes you a click."

The retention failure mode of an autonomous loop is the OPPOSITE
problem: when the loop is healthy, the operator doesn't see anything,
so they stop checking, so they miss the moment the loop GOES
unhealthy. A streak counter is a tiny positive signal that says
"this loop has been GREEN for 11 consecutive days; the longest
streak on record is 23." A 30-second glance answers "do I need to
worry about THIS project?" without opening events.jsonl. Per P-5
(operator confidence over feature richness), the win is converting
"silence" from an absence-of-signal (anxiety-inducing) into a
positive signal (trust-reinforcing).

The smallest meaningful unit of value is one table per project:

```
fleet streak

SLUG          CURRENT  LONGEST  LAST GREEN   BROKEN BY
agent-fleet   11d ✓    23d      2026-06-09   —
courtiq       0d       12d      2026-06-04   2026-06-05 ship_paused
digitalcraft  4d ✓     8d       2026-06-09   —
almanac       0d       3d       2026-05-30   2026-05-31 budget_block

streak: 2 of 4 projects currently on a green streak.
        longest active streak: agent-fleet (11d).
        longest all-time streak: agent-fleet (23d, 2026-05-15..2026-06-06).
```

Subtraction: the operator stops mentally aggregating "I haven't
seen a red event for project X in a while" into a confidence
score. The streak counter IS the score.

### Stakeholder
This is **moat-deepening on the retention axis** — the
kit's first surface optimized for "the loop is fine, please keep
trusting it" rather than "the loop needs your attention." Every
other autonomous-coding-agent project the operator could adopt
optimizes for the OPPOSITE: notifications, alerts, dashboards full
of red banners. The kit's bet is that an operator who runs a fleet
for six months trusts the loop more, not less — and the streak
counter is the rendered proof.

Per P-6 (telemetry is the source of truth), `streak` is a PURE
reader of `events.jsonl` — no new event types, no state file. The
computation is deterministic: walk every day in the window, mark
green/red based on the four predicates (≥1 merged ship PR, 0
`ship_paused`, 0 `budget_block`, 0 unresolved `gate_failed`),
collapse runs of green days into streaks. The "unresolved
`gate_failed`" predicate dedupes against the SAME-DAY heal
recovery: a `gate_failed` followed by a `run_completed` exit=0
within the same UTC day counts as RESOLVED (the heal worked). This
is the same shape as `fleet diff`'s ship_paused/ship_resumed
pairing helper (ticket 0038) — the LESSONS 2026-06-08 awk
empty-key trap applies directly.

Per P-3 (heal in-flight before new work), `streak` is read-only
and cheap (~one awk pass per project's events.jsonl) — it never
blocks heal work.

Compounds 0027 (`fleet badge` — the streak number becomes a
candidate badge field; out of scope for v1 but a one-line
extension), 0036 (`fleet morning` — the verdict line on a quiet
day grows a "11d green streak ✓" suffix when nothing changed; v2),
0025 (`fleet weekly` — the Sunday rollup grows a "streaks" column;
v2). All v2 — v1 is just the standalone `streak` reader.

### User (operator at 9am Tuesday after a quiet weekend)
Operator runs `fleet streak`. Sees `agent-fleet: 11d ✓ current,
23d longest`. Closes terminal. Goes back to actual work. The
loop has earned 30 seconds of operator trust without consuming any.

vs. broken-streak case: operator runs `fleet streak`, sees
`courtiq: 0d current, broken by 2026-06-05 ship_paused`. Knows to
open `fleet incident --slug courtiq --since 2026-06-05` next.
The streak counter is a ROUTING signal — it tells the operator
which project to investigate without making them open events.jsonl
first.

The operator's emotional surface for a 5-project fleet shifts
from "five projects, none of which I checked, all of which COULD
be broken" to "five projects, four on green streaks of 4+ days,
one broken with a known cause." Per P-5, this is operator
confidence in its most distilled form.

### Growth
The streak counter is the kit's first surface designed to be
SCREENSHOT-SHARED. An operator who tweets "my agent-fleet just
hit a 30-day green streak" is doing acquisition work for the kit
that no docs page can match. The shape is universal: GitHub
contribution graphs, Duolingo streaks, github-actions success
ribbons — the streak is a culturally-legible positive signal that
the operator's fleet is healthy.

A friend running their own claude loop reads the `streak` output
and immediately understands the kit's bet on long-running
autonomy: the unit of pride is not "I shipped X PRs," it's "the
loop has been green for X days." That mental model is contagious.

Per the brief's "what keeps an operator who already ships PRs
DAILY from drifting away during a quiet week?" — the streak
counter is the answer. It rewards the operator for trusting the
loop through a quiet week, instead of punishing them for not
checking.

Compounds the acquisition path: a friend who installed via
`onboarding-check` (ticket 0041) and starts shipping immediately
has their streak counter at 1d on day 1, 2d on day 2, etc. The
streak is the first surface that GROWS with continued use —
every other surface is bounded (number of PRs, $ spend, etc.).
Growth-shaped by construction.

## Acceptance criteria

Each box maps 1:1 to a test scenario in `tests/streak.sh`.

- [ ] `bin/fleet streak` is a new subcommand. With no flags it
      walks every project discovered via `agents.config.sh`
      under the kit's standard discovery roots (same set as
      `fleet overview`'s discovery), computes the current and
      longest streak per project from a window of 90 days
      (default), and prints the table from the User lens above.
      Exit 0 always. Test asserts the table render via a
      fixture events.jsonl set.
- [ ] A "green day" predicate is: for a given UTC day Y-M-D and
      slug S, the slug's events.jsonl contains AT LEAST ONE
      `phase=ship` event with `type=run_completed exit=0`
      AND ZERO `type=ship_paused`, ZERO `type=budget_block`,
      AND every `type=gate_failed` is followed within the same
      UTC day by a `type=run_completed exit=0` for the same
      phase. Days with ZERO ship events at all (the loop did
      not fire that day) are NEUTRAL — they neither extend nor
      break the streak (a quiet day is not a regression). Test
      asserts each of the four predicates via fixture
      events.jsonl variants.
- [ ] The "current streak" is the number of consecutive green
      days ending TODAY (UTC, or `FLEET_NOW_OVERRIDE` if set).
      If today is itself broken, the current streak is 0d. If
      today is neutral (no ship fired today yet), the current
      streak is the streak as of yesterday — a quiet day in
      progress is not yet a regression. The "longest" streak
      is the maximum over the 90-day window. Test asserts both
      branches.
- [ ] `bin/fleet streak --since <Nd|YYYY-MM-DD>` overrides the
      default 90-day window. `--slug <name>` restricts to one
      project. `--json` emits one JSON object per project
      `{"slug": <name>, "current": <int>, "longest": <int>,
      "last_green": "<YYYY-MM-DD>", "broken_by":
      "<YYYY-MM-DD type=... | null>"}`. Test asserts each flag
      via fixture sets.
- [ ] The "broken by" column names the FIRST event type that
      broke the most recent streak: `ship_paused`,
      `budget_block`, or `gate_failed` with the date. When the
      current streak is 0d AND the previous day was green,
      `broken by` cites today's break. When the current streak
      is N > 0 days, `broken by` is `—` (the dash) for the
      current streak and the most recent break is in the
      "previous streak" history (out of scope for v1; a v2
      `--history` flag). Test asserts the broken-by column on
      fixtures designed to exercise each break type.
- [ ] The summary line counts projects on a current green
      streak (`current > 0`) and names the longest-active +
      longest-all-time project with date range. Empty fleet:
      `streak: no projects discovered. run \`fleet
      onboard\` to adopt one.` exit 0. Test asserts both
      branches.
- [ ] `bin/fleet streak --help` prints USAGE mentioning
      `--since`, `--slug`, `--json`. Test asserts via
      `grep -qF -- "$kw" "$help_out"` per LESSONS 2026-05-30.
      Help block ends with `exit 0` per LESSONS 2026-06-01.
- [ ] `bin/fleet streak` is a PURE READER. NO `events.jsonl`
      writes, NO `fleet_emit_event` calls. Test asserts the
      kit's events channel has unchanged byte size before
      and after invocation (`stat -f %z` on macOS).
- [ ] The awk script that walks per-day events uses an
      EXPLICIT `BEGIN { day_count = 0; streak = 0; longest = 0
      }` block per LESSONS 2026-06-08 (POSIX awk
      empty-string-key trap). Test asserts via fixture
      events.jsonl whose first event would otherwise land
      under `arr[""]`.
- [ ] The window walk uses `date -u -j -f '%Y-%m-%d' <date>
      -v +1d '+%Y-%m-%d'` (BSD date) for day arithmetic per
      the kit's macOS target. Per LESSONS 2026-06-05 (bash
      3.2 LC_ALL caching), NO bash-arithmetic-on-dates.
      Test asserts day arithmetic correctness across a
      month boundary.
- [ ] `lib/common.sh` — NO changes. `streak` is a pure
      reader. NO new `fleet_*` helpers, NO signature
      changes. Test asserts via `git diff --name-only
      main…HEAD -- lib/common.sh` returns empty.
- [ ] `prompts/` — NO changes. Test asserts via `git diff
      --name-only main…HEAD -- prompts/` returns empty.
- [ ] `tests/streak.sh` covers all 12 boxes above using
      `$HOME/.local/bin` stubs per LESSONS 2026-05-26.
      Fixture events.jsonl files live under
      `tests/fixtures/streak/` with files exercising:
      30-day clean streak, single-day break in middle of
      window, ship_paused break, budget_block break,
      gate_failed-but-resolved (still green),
      gate_failed-and-unresolved (broken),
      no-events-today (neutral), and a month-boundary
      streak. Per LESSONS 2026-05-27 backup/restore via
      `cp`. Counts use `awk … END { print n+0 }` per
      LESSONS 2026-06-01. The clock is frozen via
      `FLEET_NOW_OVERRIDE`. Run-time budget: <8s.

## Out of scope

The dev agent will NOT do these even if they seem related.

- A `--history` flag listing prior streaks and their breaks. The
  v1 surface is JUST "current and longest." History is a follow-up
  ticket.
- Auto-posting the streak to GitHub via a commit-status check or
  badge endpoint. Composes with `fleet badge` (ticket 0027) but
  v1 is local-stdout only.
- Streak SUM across the fleet (one number for "the fleet's
  combined green-day count"). The fleet doesn't have a single
  streak — each project has its own. A v2 might compute "days
  on which EVERY project was green" but that's a different
  predicate.
- Per-phase streaks (one streak for ship, one for groom, one
  for review). v1 is ship-only. Groom and review have different
  "green day" predicates (groom doesn't fail; review polls
  forever) so they need a separate design.
- A streak in HOURS or MINUTES. The unit is days (UTC), to
  match how the operator thinks about "did the loop break
  yesterday or not?"
- A streak across `events.jsonl` rotation boundaries that
  exists in the archive but not the live file. v1 reads the
  LIVE events.jsonl only; if the streak is older than the
  rotation, the longest is bounded by what the live file
  contains. v2 may add archive-replay.
- Modifying `fleet morning` (0036), `fleet weekly` (0025), or
  `fleet badge` (0027) to embed the streak. v1 is standalone;
  composition is v2.
- A launchd schedule. Operator-invoked only.

## Engineering notes

Files / patterns the dev should touch. Specific enough that the dev
doesn't have to re-discover the architecture.

- `bin/fleet` — new `streak()` dispatcher function placed
  next to the existing `overview()` block (find via
  `grep -n '^overview()' bin/fleet`, currently ~line 6983).
  Shape mirrors `overview()` for the multi-slug walk + table
  rendering AND `weekly()` (~line 2512) for the per-slug
  events.jsonl walk + window math.
- `bin/fleet` — six helpers, ALL defined ABOVE the dispatcher
  block per LESSONS 2026-06-05 (forward-reference trap):
  - `streak_discover_slugs` — reuses the existing
    `overview_discover_slugs` helper (~line 6995 — already
    above the dispatcher block; safe to invoke).
  - `streak_walk_days` — awk script that walks one
    events.jsonl file day by day, applies the four-predicate
    "green day" rule, and emits one line per day
    `YYYY-MM-DD<TAB>green|red|neutral<TAB>break_type`
    where `break_type` is `-` for green/neutral days (per
    LESSONS 2026-06-08 sentinel rule). Per LESSONS 2026-06-08,
    the awk script starts with `BEGIN { day_count = 0;
    streak = 0; longest = 0 }`.
  - `streak_collapse_runs` — reads the day list, collapses
    consecutive green days into streaks, computes current
    (ending today) and longest. Per LESSONS 2026-06-05
    bash-3.2 LC_ALL caching, NO bash arithmetic on dates —
    day arithmetic via `date -u -j -f '%Y-%m-%d' "$d" -v
    +1d '+%Y-%m-%d'`.
  - `streak_render_text` — formats the table from the User
    lens. Width computation goes through
    `preflight_visible_width` (line ~666 of `bin/fleet`)
    per LESSONS 2026-06-05.
  - `streak_render_json` — emits one JSON object per slug
    per AC#4. JSON escape goes through
    `preflight_json_escape` per LESSONS 2026-06-03 (UTF-8
    sign-extension).
  - `streak_summary_line` — composes the final summary
    block from the per-slug results.
- `bin/fleet` — `streak()` end-state must be `exit 0` on
  every code path per LESSONS 2026-06-01 (dispatcher
  fall-through trap — `streak` never errors, but the
  helper still ends with explicit `exit 0`). `exit 2` on
  usage error.
- `bin/fleet` — dispatcher block: `if [ "$CMD" = "streak"
  ]; then streak "$@"; fi`. Place AFTER the `overview`
  dispatcher (~line 7146). Per LESSONS 2026-06-05 (forward-
  reference trap), confirm every helper `streak` calls is
  defined ABOVE the dispatcher block.
- `bin/fleet` — help banner block at the top of the file
  (around line ~14) gets a new line: `fleet streak
  current + longest continuous green-day run per project`.
  README "Daily ops" code block gets the same line.
- `AGENTS.md § Telemetry` — NO new bullet. `streak` is a
  pure reader. Test asserts via `git diff --name-only
  main…HEAD -- AGENTS.md` returns empty.
- `lib/common.sh` — NO changes.
- `prompts/` — NO changes.
- `tests/fixtures/streak/` — NEW directory under
  `tests/fixtures/` holding eight synthetic events.jsonl
  files exercising each test scenario from AC#13.
- `tests/streak.sh` — top of file mirrors `tests/
  overview.sh` and `tests/weekly.sh`: stub `gh` under
  `$HOME/.local/bin` (`$HOME=$TMP/home` per LESSONS
  2026-05-26). Counts use `awk … END { print n+0 }` per
  LESSONS 2026-06-01. Per LESSONS 2026-05-27 backup/
  restore via `cp`. The clock is frozen via
  `FLEET_NOW_OVERRIDE`. Run-time budget: <8s.
- New deps: none. Pure shell + awk + existing helpers.
- Public API: additive — `bin/fleet streak` is a new
  subcommand. ZERO new event types, ZERO event writes.
- BREAKING flag: NO. PR body affirms "pure reader, no
  events.jsonl writes, no `fleet_*` signature changes."
- Reinstall required: NO. `lib/` and `prompts/` are
  untouched. Operator runs `git pull` on the kit
  checkout and the new subcommand is immediately
  available.
- LESSONS to defend against: 2026-05-25 (load-bearing
  docs — README "Daily ops" code block addition).
  2026-05-26 (`tail` shadow — `streak` is namespaced;
  helpers are `streak_*`). 2026-05-26 (PATH reset —
  stubs go in `$HOME/.local/bin`). 2026-05-27 (`$(cat)`
  trap — fixture restore uses `cp`). 2026-05-28
  (printf leading-dash — every break-type value goes
  through `printf -- '%s'`). 2026-05-30 (`grep -F --`
  trap — help text uses `grep -qF --`). 2026-06-01
  (`grep -c file || echo 0` double-print — counts use
  `awk … END { print n+0 }`). 2026-06-01 (dispatcher
  fall-through — `streak()` ends with explicit `exit
  0`). 2026-06-03 (UTF-8 sign-extension — JSON escape
  goes through `preflight_json_escape`). 2026-06-05
  (dispatcher forward-reference — helpers above
  dispatcher block). 2026-06-05 (bash 3.2 LC_ALL
  caching — width via `preflight_visible_width`, date
  arithmetic via `date -u -j -f`). 2026-06-08 (awk
  empty-string-key — `streak_walk_days` BEGIN block
  initializes counters). 2026-06-08 (IFS=$'\t'
  middle-empty-field — break_type column uses `-`
  sentinel for green/neutral days).
- This ticket compounds 0019 (`fleet overview` —
  shares the multi-slug discovery), 0025 (`fleet
  weekly` — shares the events.jsonl window walk),
  0027 (`fleet badge` — v2 can embed the streak),
  0036 (`fleet morning` — v2 can show the streak on
  quiet days), 0038 (`fleet diff` — shares the awk
  empty-key defense pattern from LESSONS 2026-06-08).
  Per P-1 the diff is small: ~300 lines of `streak_*`
  helpers + ~250 lines of test + eight fixture
  events.jsonl files + one help-text line + one
  README line.

## Implementation log

(Appended by the implementation-dev agent during execution.)

- 2026-06-10 — branch `feat/0042-streak-green-days` opened; status flipped to in-progress
- YYYY-MM-DD — failing test added in `tests/streak.sh`
- YYYY-MM-DD — PR #N opened, CI [state]
- YYYY-MM-DD — merged to main
