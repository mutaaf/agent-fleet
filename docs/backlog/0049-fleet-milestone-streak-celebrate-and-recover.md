---
id: 0049
title: fleet milestone celebrates streak milestones and composes a one-line recovery nudge on streak break
status: in-progress
priority: P1
area: observability
created: 2026-06-13
owner: gtm-innovation
---

## User story

As a fleet operator who has been running the loop for two months and
whose `fleet streak` (0042) currently shows a 23-day green run on
`agent-fleet` and a 0-day broken streak on `courtiq` — but who has NO
moment when the kit ACKNOWLEDGES the 23 days as a milestone worth
celebrating AND no moment when the kit ACKNOWLEDGES the break and
suggests a recovery posture — I want `bin/fleet milestone` to emit one
line per project that just crossed a configurable milestone threshold
(default 10/30/100 days) OR just broke a streak that was ≥ a configurable
floor (default 7 days), composed so I can paste it into a calendar event,
a journal entry, or a public post, so the loop's longest-running positive
signal stops being silent and the kit's biggest negative signal stops
being shame-shaped.

## Why now (four lenses)

### Product Owner
`fleet streak` (0042) shipped on 2026-06-09. Two days after ship, the
kit has a streak counter but no MOMENT when crossing a meaningful
threshold becomes a thing the operator notices. The kit's daily
surfaces (`fleet morning`, `fleet inbox`) show the current streak in
a small column; the weekly rollup (`fleet weekly`) shows the
30-day count. Neither says "today is special."

The retention failure mode of a silent positive signal is: the
operator stops checking. The first 10-day streak feels like an
accident. The 30-day streak is when the operator should start
trusting the loop enough to actually take the vacation `fleet
vacation` (0046) ships. But there's no MOMENT that converts
"23 consecutive green days" into "you can actually trust this."

Similarly: a streak BREAK after 23 green days is currently a
silent transition from a `23d` column to a `0d` column. The
operator opens `fleet streak` on Tuesday morning, sees `0d`, and
the dominant emotion is "I failed the streak." That's the WRONG
shape for the recovery moment. The kit's job is to convert "I
broke the streak" into "the loop healed a new failure mode;
here's the LESSON it dropped; that's why the streak broke,
that's the data, do not feel bad about it."

The smallest meaningful unit of value is one command, one line
per threshold-crossing event:

```
fleet milestone

milestone: 2 events in the trailing 24h.

  [1] agent-fleet  · NEW LONGEST STREAK 23d
      previous best: 18d (2026-05-12 → 2026-05-30)
      today's run started: 2026-05-21
      paste-ready: "agent-fleet just hit a new longest green-day
      streak: 23 days of merged-without-ship-paused autonomous
      ship cycles. powered by agent-fleet."

  [2] courtiq      · STREAK BROKEN at 14d
      broken by: ship_paused on 2026-06-12 (3 consecutive
      send-backs on PR #214)
      lesson drafted: "test wrote to a non-isolated path" — already
      a draft in docs/LESSONS.md (PR #214). promote via
      `fleet lessons-promote` to compound the next streak.
      recovery posture: `fleet resume courtiq` once the underlying
      test isolation is fixed; the streak floor resets to 0 but
      the longest-recorded streak (14d) is preserved.

milestone: next thresholds active — agent-fleet 30d (7d away),
           courtiq 7d (7d away from a recovered streak).
```

Subtraction: the operator stops doing the manual "wait, did I just
cross 10 days?" mental math and stops experiencing a streak break
as a personal failure. The milestone command IS the celebration
AND the recovery framer.

Per P-5 (operator confidence over feature richness), the win is
converting two structurally invisible events (a quietly-crossed
milestone, a quietly-broken streak) into two surfaced moments
that EITHER reinforce the trust the operator has built OR convert
the loss into a forward-pointing action.

### Stakeholder
This is **moat-deepening on the retention axis** — the kit's
first surface that emits a HABIT-REINFORCING signal rather than a
WORK-OWED signal. Every prior daily surface (`inbox`, `morning`,
`weekly`) is shaped like "here's what owes you a click." The
milestone command is the first surface shaped like "here's what
the loop did FOR you that is worth noticing." That asymmetry is
the retention compound: an operator who only ever gets nagged
churns; an operator who occasionally gets celebrated stays.

Per P-6 (telemetry is the source of truth), the milestone
detection is a PURE READER of `events.jsonl` + the streak
compute from ticket 0042 (`streak_compute_for_slug`). The
algorithm:

1. For each discovered slug, compute current streak via
   `streak_compute_for_slug` (reused as-is from 0042).
2. Compute the historical longest-streak per slug by walking
   every contiguous green-day run in the channel.
3. Compare current streak length to a configurable threshold
   ladder (default `10,30,100` days from `agents.config.sh`'s
   optional `MILESTONE_THRESHOLDS` knob). When the current
   streak's day count CROSSED a threshold WITHIN the trailing
   24h window (i.e. yesterday's compute was below the
   threshold and today's is at or above it), emit a
   threshold-crossing line.
4. Detect a streak break by comparing today's streak (0) to
   the streak length at the moment the most recent
   streak-breaking event (`ship_paused`, `budget_block`,
   `gate_failed` without recovery) was emitted; if that
   length ≥ `MILESTONE_BREAK_FLOOR` (default 7), emit a
   streak-break recovery line that includes the breaking
   event AND the most-recent unpromoted lesson draft (if
   any) AND the recovery posture command.

Per P-1 (smallest viable change), the diff is the
threshold-crossing detector + the recovery composer + the
render. No new event types, no new state file, no launchd
hook.

Compounds 0042 (`fleet streak` — the streak compute is the
load-bearing input), 0022 (`reviewer-sendback-drafts-lesson-
skeleton` — the recovery line surfaces the drafted LESSON),
0030 (`fleet resume` — the recovery posture command), 0046
(`fleet vacation` — a 30-day milestone is the moment the
operator can start trusting the loop enough to take real PTO).

Per P-3 (heal in-flight before new work), `milestone` is
read-only and cheap (~one events.jsonl read per slug) — never
blocks heal work.

### User (operator on a Wednesday, two scenarios)
SCENARIO A (CELEBRATION): operator runs `fleet morning`,
notices the streak column climbed to 23d, doesn't think much
of it. Later in the day on a curiosity-driven `fleet
milestone` invocation, sees `NEW LONGEST STREAK 23d` with a
paste-ready line. Pastes the line into their daily journal.
Two months later when they review their journal, the 23-day
streak is documented evidence the loop works. Without this
surface, the moment is invisible and the evidence is
unsourced.

SCENARIO B (RECOVERY): operator runs `fleet morning` on a
Tuesday, sees `courtiq · 0d ✗ broken by ship_paused`.
Initial mental state: "I failed the streak; I have to debug
why." Then runs `fleet milestone` and sees:

```
courtiq · STREAK BROKEN at 14d
  broken by: ship_paused on 2026-06-12 (3 consecutive
  send-backs on PR #214)
  lesson drafted: "test wrote to a non-isolated path" —
  already a draft in docs/LESSONS.md (PR #214). promote
  via `fleet lessons-promote` to compound the next streak.
  recovery posture: `fleet resume courtiq` once the
  underlying test isolation is fixed; the streak floor
  resets to 0 but the longest-recorded streak (14d) is
  preserved.
```

Mental state flips from shame ("I failed") to action ("the
loop learned a new failure mode, here's the lesson, here's
the resume command"). The 14d longest-recorded streak is
PRESERVED in the next-day's `fleet streak` output as a
durable artifact.

Per P-5, the win is converting two emotionally-flat signals
(silent milestone, silent break) into two emotionally-correct
moments (celebration, recovery framing).

### Growth
The paste-ready line is the social-share primitive: an
operator who's just hit a 30-day streak can paste the line
into a Mastodon / Twitter / Slack post in 10 seconds. Every
posted line ends with the literal string `powered by
agent-fleet`, which is the lightest-weight attribution
primitive the kit can ship. This is differentiated from
`fleet recap` (0048): `recap` is a full snapshot block;
`milestone` is a one-liner an operator posts mid-day on a
phone.

The recovery composer is also the LANGUAGE primitive the
kit teaches operators to use when talking about agent
loops to others: "the streak broke because the loop hit a
new failure mode; the lesson is X; here's the recovery."
That framing — failure as data, not as shame — is the
moat the kit deepens every time the recovery composer
fires. Per the brief's "Operator retention / habit
reinforcement: streaks exist but there's no celebratory
moment when the streak hits a milestone (10/30/100 days)
and no recovery nudge when a streak breaks" — this is the
direct answer.

The retention path now has: `vacation` (0046, leave-the-
loop safety) and `milestone` (0049, stay-engaged signal).
Together they bracket the "operator who runs the loop for
months and never burns out" outcome.

## Acceptance criteria

Each box maps 1:1 to a test scenario in `tests/milestone.sh`.

- [ ] `bin/fleet milestone` is a new subcommand. With no flags
      walks every project discovered via `agents.config.sh` under
      the standard discovery roots (same set as `fleet overview`),
      computes current + longest streak per slug via the existing
      `streak_compute_for_slug` helper (ticket 0042), detects
      threshold crossings in the trailing 24h AND streak breaks
      in the trailing 24h, and prints one block per detected
      event. Exit 0 always. Test asserts the render via fixture
      events.jsonl files.
- [ ] The threshold ladder is read from `agents.config.sh`'s
      optional `MILESTONE_THRESHOLDS` knob (comma-separated
      integers in days, e.g. `10,30,100`). When unset, the
      default is `10,30,100`. When set to empty string,
      threshold-crossing detection is disabled (only
      streak-break events are emitted). Test asserts via
      fixtures with each variant.
- [ ] A threshold-crossing line is emitted when the current
      streak length is at or above a threshold value AND
      yesterday's same-compute (frozen via
      `FLEET_NOW_OVERRIDE` shifted by 24h) was strictly
      below the same threshold. Per LESSONS 2026-06-11 (BSD
      `date -j -f` fills missing time fields with NOW-of-
      day), the "yesterday" comparison uses ISO8601
      lex-compare on UTC dates only — never a `date -j -f
      '%Y-%m-%d'` subshell. Test asserts via a fixture
      that crosses 10d exactly today.
- [ ] A "NEW LONGEST STREAK" line fires when the current
      streak length strictly exceeds the previously-
      recorded longest streak for the slug. The
      threshold-crossing AND new-longest may both fire
      on the same slug in one run (rendered as two
      stacked blocks). Test asserts via a fixture where
      a 23d current streak exceeds an 18d prior longest.
- [ ] A streak-break line is emitted when (a) the current
      streak is 0, (b) the most-recent streak-ending event
      (`ship_paused`, `budget_block`, or an unresolved
      `gate_failed`) happened in the trailing 24h, and (c)
      the length of the streak immediately before the
      break was ≥ `MILESTONE_BREAK_FLOOR` (default 7,
      configurable via `agents.config.sh`). The line
      includes the breaking event type + date, the most
      recent unpromoted lesson draft (if any
      `lesson_draft_emitted` events fired in the trailing
      24h), and the recovery posture command (`fleet
      resume <slug>` for `ship_paused`; nothing for
      `budget_block` — the operator owns the budget).
      Test asserts via fixtures with each break type.
- [ ] The paste-ready line on a celebration block is
      composed as: `<slug> just hit a new longest
      green-day streak: <N> days of merged-without-ship-
      paused autonomous ship cycles. powered by
      agent-fleet.` Always ends with the literal `powered
      by agent-fleet` suffix. Per LESSONS 2026-05-28
      every `printf` of the slug name goes through
      `printf -- '%s'`. Test asserts the exact suffix
      via `grep -qF -- "powered by agent-fleet"`.
- [ ] `bin/fleet milestone --since <Nd|YYYY-MM-DD>`
      overrides the default 24h detection window (the
      typical operator runs the command daily). A
      `--since 7d` window picks up any milestone or
      break that happened in the trailing 7 days, useful
      for the operator returning from a Friday-Sunday
      gap. Test asserts each format.
- [ ] `bin/fleet milestone --slug <name>` restricts to
      one project. Test asserts.
- [ ] `bin/fleet milestone --json` emits one JSON
      object per detected event: `{"slug": <name>,
      "kind": "threshold_crossed" | "new_longest" |
      "broken", "value": <int>, "previous_best":
      <int | null>, "broken_by": "<event_type | null>",
      "broken_on": "<iso | null>", "drafted_lesson":
      "<text | null>", "recovery_command": "<text |
      null>", "paste_ready": "<text>"}`. JSON escape
      via `preflight_json_escape` per LESSONS
      2026-06-03. Test asserts JSON validity via Node.
- [ ] `bin/fleet milestone --help` prints USAGE
      mentioning `--since`, `--slug`, `--json`, the
      threshold-ladder knob, and the
      `MILESTONE_BREAK_FLOOR` knob. Test asserts via
      `grep -qF -- "$kw" "$help_out"` per LESSONS
      2026-05-30. Help block ends with `exit 0` per
      LESSONS 2026-06-01.
- [ ] Empty case (zero milestone events in the
      window across the fleet) prints `milestone: no
      threshold crossings or streak breaks in the
      trailing <Nd>. current longest active streak:
      <slug> (<Nd>).` exit 0. Test asserts via a
      fixture with no qualifying events.
- [ ] `bin/fleet milestone` is a PURE READER. NO
      `events.jsonl` writes, NO `fleet_emit_event`
      calls, NO writes to any state file. Test
      asserts the kit's events channel has unchanged
      byte size before and after invocation.
- [ ] The "next thresholds active" footer line lists
      every active slug's nearest unmet threshold and
      the days-to-reach (current streak length minus
      next threshold). When every threshold has been
      crossed on every active slug, the footer reads
      `next thresholds active — none; all active
      streaks have crossed every configured threshold.`
      Test asserts both branches.
- [ ] `lib/common.sh` — NO changes. `milestone` is a
      pure caller of existing helpers. Test asserts via
      `git diff --name-only main…HEAD -- lib/common.sh`
      returns empty.
- [ ] `prompts/` — NO changes. Test asserts via
      `git diff --name-only main…HEAD -- prompts/`
      returns empty.
- [ ] `tests/milestone.sh` covers all 14 boxes above
      using `$HOME/.local/bin` stubs per LESSONS
      2026-05-26. Fixture `events.jsonl` and
      `agents.config.sh` files live under
      `tests/fixtures/milestone/`. Per LESSONS
      2026-05-27 backup/restore via `cp`. Counts use
      `awk … END { print n+0 }` per LESSONS
      2026-06-01. The clock is frozen via
      `FLEET_NOW_OVERRIDE` AND a paired
      `FLEET_NOW_OVERRIDE_YESTERDAY` value for the
      "yesterday's compute" branch. Run-time budget:
      <8s.

## Out of scope

The dev agent will NOT do these even if they seem related.

- AUTO-POSTING the celebration line anywhere. v1 prints to
  stdout; the operator copies. Auto-posting violates the
  operator-confidence Hard NO.
- A NOTIFICATION (push / email / Slack) when a milestone
  crosses. v1 is operator-pull only. Notification hooks
  are a separate ticket.
- AUTO-MERGING streak milestones across slugs ("show me
  the fleet-wide combined streak"). v1 is per-slug;
  fleet-wide combined streak is a v2 ask.
- A CHART of streak history over time. v1 is text only.
- A MILESTONE LOG that records every historical crossing
  (a separate file). v1 reads `events.jsonl` and
  computes on demand. The events channel IS the log.
- A `--shame` mode that emits a "you broke a streak"
  message designed to nudge. v1's recovery line is
  framed-as-data, not framed-as-shame, by deliberate
  design.
- Promoting the drafted lesson AUTOMATICALLY when a
  streak break references one. v1 surfaces the draft
  and the promotion command; the operator promotes.
  Per P-9 (review send-backs draft LESSONS; the
  operator promotes).
- Modifying `fleet streak` (0042) to fold milestone
  lines into its render. v1 is standalone; the streak
  table stays as-is.
- Modifying `fleet morning` (0036) to fold milestone
  lines. v1 is standalone; the morning briefing stays
  as-is. A v2 may add a one-line milestone hint to
  morning.
- A launchd schedule. Operator-invoked only.

## Engineering notes

Files / patterns the dev should touch.

- `bin/fleet` — new `milestone()` dispatcher function placed
  next to the existing `streak()` block (find via `grep -n
  '^streak()' bin/fleet`). Per LESSONS 2026-05-26 (`tail`
  shadow) `milestone` does not collide with any coreutils
  binary.
- `bin/fleet` — seven helpers, ALL defined ABOVE the
  dispatcher block per LESSONS 2026-06-05 (forward-
  reference trap):
  - `milestone_discover_slugs` — reuses
    `overview_discover_slugs`.
  - `milestone_compute_today_streak` — reuses
    `streak_compute_for_slug` from ticket 0042 verbatim.
  - `milestone_compute_yesterday_streak` — calls
    `streak_compute_for_slug` with `FLEET_NOW_OVERRIDE`
    shifted by 24h via ISO8601 lex math (per LESSONS
    2026-06-11, NEVER `date -j -f '%Y-%m-%d'` — the
    missing-time-field fill makes the comparison off by
    a partial day).
  - `milestone_compute_historical_longest` — walks every
    contiguous green-day run in the slug's `events.jsonl`,
    returns the max length + start date + end date.
  - `milestone_detect_threshold_crossings` — given today's
    streak length, yesterday's streak length, and the
    threshold ladder, returns the list of crossed
    thresholds. Per LESSONS 2026-06-08 the awk script
    declares `BEGIN { count = 0 }`.
  - `milestone_detect_breaks` — walks the trailing 24h
    of events for the streak-ending types
    (`ship_paused`, `budget_block`, unresolved
    `gate_failed`) and pairs each with the streak length
    at the moment of break.
  - `milestone_compose_recovery_line` — given a break
    event type + the most-recent
    `lesson_draft_emitted` in the same window + the
    recovery posture command, composes the
    multi-line recovery block. Per LESSONS 2026-05-28
    every slug printf goes through `printf -- '%s'`.
  - `milestone_render_text` and
    `milestone_render_json` — formatters. Width via
    `preflight_visible_width` per LESSONS 2026-06-05;
    JSON escape via `preflight_json_escape` per
    LESSONS 2026-06-03.
- `bin/fleet` — `milestone()` end-state must be `exit 0`
  on every code path per LESSONS 2026-06-01.
- `bin/fleet` — dispatcher block: `if [ "$CMD" =
  "milestone" ]; then milestone "$@"; fi`. Place AFTER
  the `streak` dispatcher.
- `bin/fleet` — help banner block at the top of the
  file gets a new line: `fleet milestone celebrate
  streak crossings and frame recoveries`. README
  "Daily ops" code block gets the same line.
- `AGENTS.md § Telemetry` — NO new bullet. `milestone`
  is a pure reader. Test asserts via `git diff
  --name-only main…HEAD -- AGENTS.md` returns empty.
- `lib/common.sh` — NO changes.
- `prompts/` — NO changes.
- `tests/fixtures/milestone/` — NEW directory under
  `tests/fixtures/` holding `events.jsonl` files for 4
  synthetic slugs covering: (a) just-crossed 10d
  threshold today, (b) new longest streak at 23d, (c)
  streak broken from 14d by `ship_paused`, (d) no
  qualifying events.
- `tests/milestone.sh` — top of file mirrors
  `tests/streak.sh` (the closest prior ticket). Stubs
  `gh` under `$HOME/.local/bin` per LESSONS 2026-05-26.
  Counts use `awk … END { print n+0 }` per LESSONS
  2026-06-01. Per LESSONS 2026-05-27 backup/restore
  via `cp`. The clock is frozen via
  `FLEET_NOW_OVERRIDE` AND a paired
  `FLEET_NOW_OVERRIDE_YESTERDAY` value for the
  "yesterday's compute" branch (compute the
  yesterday override in shell via ISO8601 lex math
  per LESSONS 2026-06-11). Run-time budget: <8s.
- New deps: none. Pure shell + awk + existing helpers.
- Public API: additive — `bin/fleet milestone` is a
  new subcommand. ZERO new event types, ZERO event
  writes.
- BREAKING flag: NO. PR body affirms "pure reader, no
  events.jsonl writes, no `fleet_*` signature
  changes."
- Reinstall required: NO. `lib/` and `prompts/` are
  untouched.
- LESSONS to defend against: 2026-05-25 (README "Daily
  ops" code block addition), 2026-05-26 (`tail`
  shadow), 2026-05-26 (PATH reset — stubs in
  `$HOME/.local/bin`), 2026-05-27 (`$(cat)` trap),
  2026-05-28 (printf leading-dash — every slug
  printf goes through `printf -- '%s'`), 2026-05-30
  (`grep -F --` trap), 2026-06-01 (`grep -c file ||
  echo 0` double-print — counts use `awk … END
  { print n+0 }`), 2026-06-01 (dispatcher
  fall-through), 2026-06-03 (UTF-8 sign-extension —
  JSON escape via `preflight_json_escape`),
  2026-06-05 (dispatcher forward-reference),
  2026-06-05 (bash 3.2 LC_ALL caching), 2026-06-08
  (awk empty-string-key — every awk script
  declares `BEGIN { count = 0 }`), 2026-06-08
  (IFS=$'\t' middle-empty-field), 2026-06-11 (BSD
  `date -j -f` fills missing time fields with
  NOW-of-day — yesterday compute uses ISO8601
  lex-compare, NEVER a `date -j -f '%Y-%m-%d'`
  subshell).
- This ticket compounds 0022
  (`reviewer-sendback-drafts-lesson-skeleton` — the
  recovery line surfaces the drafted LESSON), 0030
  (`fleet resume` — the recovery posture command for
  `ship_paused` breaks), 0042 (`fleet streak` —
  reuses `streak_compute_for_slug` verbatim), 0046
  (`fleet vacation` — a 30-day milestone is the
  moment the operator trusts the loop enough to
  take real PTO). Per P-1 the diff is small: ~300
  lines of `milestone_*` helpers + ~250 lines of
  test + 5 fixture files + one help-text line +
  one README line.

## Implementation log

(Appended by the implementation-dev agent during execution.)

### 2026-06-13 — picked up for ship
- Branch `feat/0049-fleet-milestone-streak-celebrate-and-recover` opened off
  `main` (clean tree). Status flipped from `groomed` to `in-progress`; index
  row in `docs/backlog/README.md` mirrored.
- Plan: tests-first per AGENTS.md P-2. `tests/milestone.sh` with one
  assertion block per AC box (14 boxes), fixtures under
  `tests/fixtures/milestone/`, `$HOME/.local/bin` stub PATH per LESSONS
  2026-05-26, frozen clock via `FLEET_NOW_OVERRIDE` + paired
  `FLEET_NOW_OVERRIDE_YESTERDAY` per the ticket. Then implement
  `milestone_*` helpers + dispatcher in `bin/fleet` placed next to
  `streak()` per "Engineering notes". Reuse the existing
  `streak_discover`, `streak_walk_days`, `streak_collapse_runs` from
  ticket 0042 — there is no `streak_compute_for_slug` in the file;
  the equivalent compute is the `walk + collapse` pair.
