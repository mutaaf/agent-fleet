---
id: 0064
title: fleet catchup composes a re-orientation briefing after the operator's been away >72h so returning to a 4-slug fleet stops feeling like triage
status: shipped
priority: P1
area: observability
created: 2026-06-23
owner: gtm-innovation
---

## User story

As a fleet operator who has been running `agent-fleet` against
four slugs for 4 months — who took a 5-day weekend to attend a
wedding, came back Tuesday morning, and opened `fleet morning`
out of habit, only to see a briefing that assumes "you saw
yesterday's state" and renders today's delta against it (a
delta that's meaningless when "yesterday" is "Thursday last
week") — and who then ran `fleet recap --since 7d` and got a
narrative that's optimized for "what happened" but not for
"what you missed THAT NEEDS YOU NOW" and is 18 paragraphs
long and bury-the-lede — and who ultimately closed the
terminal and did NOT come back until Friday because the
cognitive cost of re-loading 4 slugs of context felt larger
than just letting them keep cooking — I want `bin/fleet
catchup` to detect (from the `fleet morning` state file mtime,
the `fleet inbox` state file mtime, OR an explicit
`--since <when>`) that I've been away ≥72h, and emit a
re-orientation briefing that opens with one sentence saying
how long I was away and the verdict on the fleet
("everything cooked clean for 5 days; nothing needs you" OR
"3 things broke while you were out — here they are in
priority order"), then THREE ranked items that ACTUALLY need a
human glance (not 15, not "interesting things that happened"),
each with the one-line operator action, so the path from
"flight home landed" to "I know what needs me" is under 60
seconds instead of an evening of catching up.

## Why now (four lenses)

### Product Owner

The kit's existing daily/window observability surface is
EXCELLENT at "the operator is here every day" — 0012 digest
is the one-line per-project daily summary, 0019 overview is
the always-on cross-project table, 0025 weekly is the Sunday
ROI snapshot, 0026 inbox is today's TODO list, 0036 morning
is the composed daily briefing, 0048 recap is a window
narrative, 0055 pulse is the prompt-line heartbeat, 0058
trends is the 12-week sparkline, 0059 stuck flags non-
actionable PRs, 0060 flaky catches infra noise. EVERY one of
those assumes the operator has CONTINUOUS attention. NONE of
them handle the DISCONTINUITY case: the operator who returns
after 3+ days away. The closest is `fleet morning` (0036),
but morning's "since last run Nh ago" header degrades to
silliness when N is 120h ("since last run 5d ago") and
morning's verdict line and section ordering are designed for
the "I was here yesterday" cadence. The smallest meaningful
unit of value is one paragraph + three ranked items:

```
$ fleet catchup
catchup — you were away 5d 14h (last seen 2026-06-18T18:32Z)

  verdict: 2 things need you now. nothing on fire — the loop
  self-paused sidebrew on day 3 of your absence after 3
  send-backs (P-5 self-pause working as designed) and
  digitalcraft hit its monthly budget cap on day 4 and has
  been quiet since. courtiq and levelup-kids each shipped
  cleanly in your absence (7 PRs total).

  needs you, in priority order:

  1. resume sidebrew (paused 2d ago after 3 send-backs)
     → fleet resume sidebrew --reason "back from PTO, drafts
       reviewed"
     → 3 lesson drafts waiting: fleet inbox --slug sidebrew

  2. raise or accept the digitalcraft budget cap (hit 4d ago)
     → currently $4.50/day; June spend was $138 vs invoice
       $135 cap. consider $5.00/day OR confirm the cap is
       intentional. last `fleet invoice digitalcraft --month
       2026-05`: net positive $12/mo (kit pays for itself).

  3. one stuck PR: courtiq #214 (DRAFT, auto-merge not armed)
     → fleet stuck (courtiq #214 has been DRAFT 28h)

  what happened while you were away (7 PRs, $4.21 spent):
    sidebrew      0 PRs (paused), 3 lesson_drafts pending
    courtiq       5 PRs ($2.81 — net positive vs alt)
    digitalcraft  1 PR  ($0.94 — capped after)
    levelup-kids  1 PR  ($0.46)

  next: fleet morning (your normal daily briefing)
```

Subtraction: the operator stops dreading the come-back. Per
P-5 (operator confidence over feature richness), the win is
that being-away costs the operator less mental tax, which
means they ACTUALLY take longer breaks, which means they
trust the loop more, which means they keep using the kit.
This is the kit's first surface explicitly designed for
the operator's DISCONTINUOUS attention model.

The threshold for "you were away" is configurable via
`--since <when>` (`5d`, `2026-06-18`, `120h`) but defaults
to the most recent `morning`/`inbox`/`overview` state-file
mtime per the convention 0036 already established. If the
most-recent mtime is <72h, `fleet catchup` exits 0 with
the message `catchup: you were last here Nh ago. you
haven't been away. run \`fleet morning\` for your daily
briefing.` — this protects against operators reflexively
running `catchup` every day and getting useless output.

The "things that need you" list is RANKED, not exhaustive.
The ranking algorithm:
  1. `ship_paused` events that have NOT been resumed
     (operator's `fleet resume` action is missing).
  2. `budget_block` events from the trailing window
     (operator may need to raise the cap or confirm
     the spend pattern).
  3. PRs flagged by `fleet stuck` (0059).
  4. PRs with lesson drafts unpromoted (`lesson_draft_
     emitted` events without a subsequent
     `lesson_promoted`).
  5. Slugs where the trailing-window `$/PR` jumped >25%
     over the prior window (cost regression nudge).

The output stops at THREE items. A `--all` flag lifts the
cap. The default cap is the win: the operator gets the
three highest-leverage actions in 60 seconds, not 50
maybe-actions in 15 minutes.

### Stakeholder

This is **moat-deepening on the RETENTION axis** — the
kit's first surface explicitly designed to defuse the
attrition pattern "operator went on vacation, never
came back". That pattern is the cross-project killer of
every autonomous-coding-tool subscription past month 6:
the cost of re-acquiring context exceeds the value of
the next session. Per P-6 (telemetry is the source of
truth), `catchup` is a PURE READER over each slug's
`events.jsonl` (for `ship_paused`, `budget_block`,
`lesson_draft_emitted`, `lesson_promoted`,
`pr_footer_posted`, `run_completed`), the
`stuck`/`flaky` per-slug computations (re-using the
helpers 0059/0060 already export), and the
`morning`/`inbox`/`overview` state-file mtimes. NO
writes, NO new event types, NO `lib/common.sh`
changes. The diff is the absence detector + the
ranker + the renderer. ~360 lines.

The "ranked three items" shape IS the moat: it
codifies "what an operator actually needs to do
RIGHT NOW after being away" into a pure-data
ranking. Competing autonomous-agent tools assume
continuous attention; agent-fleet ships an explicit
discontinuity surface. That recognition of
operator real-life rhythm is the kind of design
choice the kit is known for.

Per LESSONS 2026-06-15 (per-day shellout inside
per-slug loops is O(window × N_slugs)) the per-
slug walk is ONE awk pass over events.jsonl PLUS
ONE awk pass over runs.jsonl PLUS one call to the
existing `stuck_classify_one_pr` helper per open
PR per slug — total budget <2s for a 6-slug fleet.

Per LESSONS 2026-06-11 (BSD `date -j -f` fills
missing time fields with NOW-of-day) the
`--since <date>` parser uses the full
`'%Y-%m-%dT%H:%M:%S'` format with `T00:00:00`
appended to a `YYYY-MM-DD` input; the
`--since Nh`/`Nd` form goes through `date +%s`
arithmetic (no `date -j -f` involved).

Per LESSONS 2026-06-08 (`IFS=$'\t'` middle-empty-
field) every TSV record from the ranker uses a
`-` sentinel for empty middle columns
(priority/category/slug/action can all be
empty in edge cases).

Per LESSONS 2026-06-13 (no `*_json_escape`
wrapper) the JSON renderer calls
`preflight_json_escape` directly at every site.

Per LESSONS 2026-06-15 (awk `while (match(s,
/pat/))` infinite-loop trap) the template-
substitution composer for the verdict paragraph
uses the CURSOR-based walk pattern — citation
values may include `$<digits>` substrings
matching the dollar regex.

Compounds 0036 (`fleet morning` — catchup reads
morning's state-file mtime as the "last seen"
anchor), 0026 (`fleet inbox` — catchup reads
inbox's state-file mtime), 0019 (`fleet overview`
— reuses `overview_discover_slugs`), 0059
(`fleet stuck` — catchup uses the same per-PR
classifier), 0060 (`fleet flaky` — catchup
surfaces flake-driven send-backs as lower-
priority than real ones), 0006 (`ship_paused`
event — catchup's #1 ranking input), 0004
(`budget_block` event — catchup's #2 ranking
input), 0022 (`lesson_draft_emitted` event —
catchup's #4 ranking input), 0028 (`lesson_
promoted` event — catchup pairs drafts and
promotions to find unresolved drafts), 0048
(`fleet recap` — catchup is the "I was away"
version of recap's "here's a window"), 0061
(`fleet invoice` — catchup's cost-regression
nudge cites the prior month's invoice),
0030 (`fleet resume` — catchup's #1 action
links directly to it), 0046 (`fleet vacation`
— catchup is the inverse: vacation tells the
loop "I'm out"; catchup tells the operator
"here's what you missed").

Differentiated from `fleet morning` (0036):
morning is "what's new TODAY"; catchup is "what
happened WHILE I WAS OUT and what needs me
NOW". Differentiated from `fleet recap` (0048):
recap is window narrative (descriptive, no
operator-action ranking); catchup is action-
ranked (≤3 items). Differentiated from `fleet
inbox` (0026): inbox is "today's TODO";
catchup is "the longer absence's TODO ranked
across slugs". Differentiated from `fleet
vacation --return` (0046): vacation's return
briefing fires when the operator's PTO state
file expires; catchup is operator-pulled and
works regardless of vacation mode (the
operator may have been "just busy" rather
than formally on PTO).

### User (operator returning Tuesday from a 5-day weekend)

Tuesday 7:42am. Coffee, MacBook, terminal. The
operator types `fleet catchup`. In 1.4 seconds
they read: "you were away 5d 14h. verdict: 2
things need you now. nothing on fire." Three
items. Item 1: `fleet resume sidebrew --reason
"back from PTO"`. They run it. Item 2: confirm
the digitalcraft budget cap is still right. They
glance at last month's `fleet invoice
digitalcraft` (also rendered in catchup's
footer), conclude $4.50/day is fine, ignore.
Item 3: `gh pr ready 214` for the courtiq draft.
They run it. Total elapsed: 90 seconds. They
move on. Per P-5 the win is the operator's
post-break reentry costing them 90 seconds
instead of an evening.

Sub-scenario: an operator who has been
continuously attending (last morning was 18h
ago) runs `fleet catchup` reflexively. The
command exits 0 with the message "you were last
here 18h ago. you haven't been away. run `fleet
morning` for your daily briefing." No noise, no
ranked-action paragraph, no false work. The
opportunity for a sub-72h `catchup` to redirect
to `morning` keeps the surface honest.

Sub-scenario: an operator just returned from a
2-week parental leave. `fleet catchup --since
14d` walks 14 days of events. The verdict
paragraph is longer ("everything cooked clean
for 14 days") and the ranked-actions list may
have more than three items (the operator can
add `--all` if they want the long version). The
`--since` flag is the escape hatch for absences
the state-file mtimes can't infer (e.g. the
operator did a `fleet morning` accidentally on
day 1 of vacation, which would reset the
auto-detected window).

Sub-scenario: an operator runs `fleet catchup
--json` to feed a Slack bot that posts the
ranked actions to their personal channel on
Mondays. The JSON shape is documented in the
README.

### Growth

This is the surface that retains operators
through the "I went on vacation" attrition
window — the single most common churn driver
for any autonomous tool past month 3. Per the
brief's "checks in once a day from the fleet-
control portal" and "Don't want to babysit
launchd": catchup explicitly accommodates the
operator NOT being here every day, which makes
the kit safer to RECOMMEND to a peer ("you
don't have to babysit it; when you come back,
`fleet catchup` shows you what needs you").

Differentiated from competing autonomous-agent
tools that assume continuous attention: catchup
is the kit's "I went on vacation" handshake. A
peer evaluating the kit who hears "and when you
come back from a week away, one command shows
you the three things that need you" sees a real
operator-rhythm benefit no dashboard can
replicate.

A redacted catchup output (via a future
`--redact` mode in a follow-up ticket) is a
shareable artifact for blog posts about "what
running an autonomous coding fleet for 6 months
actually FEELS like" — the come-back ritual
is part of the kit's lived experience.

## Acceptance criteria

Each box maps 1:1 to a test scenario in `tests/catchup.sh`.

- [ ] `bin/fleet catchup` is a new subcommand. NO required
      args. Default behavior: detect "last seen" from the
      newer of `morning-state` and `inbox-state` mtimes per
      the 0036/0026 convention (resolved via the same
      `${XDG_CACHE_HOME:-$HOME/.cache}/fleet/` path 0036
      uses). If both files are missing, default to "you
      have not run `fleet morning` or `fleet inbox` yet —
      run those first, then `fleet catchup`" message,
      exit 0. Per LESSONS 2026-05-30 the test assertion
      uses `grep -qF -- "$kw"`. Test asserts the
      default-detect branch AND the both-files-missing
      branch.

- [ ] When detected "away" duration is <72h, prints
      `catchup: you were last here Nh ago. you haven't
      been away. run \`fleet morning\` for your daily
      briefing.` to stderr, exit 0. The 72h threshold is
      a constant `CATCHUP_AWAY_THRESHOLD_HOURS=72` near
      the top of the helpers. Test asserts via fixture
      with mtimes 18h, 36h, 71h59m (all redirect) and
      72h, 5d, 14d (all proceed).

- [ ] `bin/fleet catchup --since <when>` overrides the
      auto-detect. Accepted shapes: `Nh` (hours), `Nd`
      (days), `YYYY-MM-DD` (date). Per LESSONS 2026-06-11
      (BSD `date -j -f` fills missing time fields with
      NOW-of-day) the `YYYY-MM-DD` form normalizes to
      `YYYY-MM-DDT00:00:00` and uses the full
      `'%Y-%m-%dT%H:%M:%S'` format. The `Nh`/`Nd` forms
      go through `date +%s` minus `N * 3600` or
      `N * 86400`, no `date -j -f` involved. Invalid
      shape: prints `catchup: --since must be Nh|Nd|
      YYYY-MM-DD (got X)` to stderr, exit 2 per LESSONS
      2026-06-01. Test asserts all three valid shapes
      AND the refusal.

- [ ] The verdict sentence is composed via template
      substitution: `you were away <DURATION>. verdict:
      <N> things need you now. <FIRE_STATE>.` `DURATION`
      is humanized (`5d 14h`, `8h`, `2w 3d`). `N` is the
      count of items in the ranked-actions list (capped
      at 3 unless `--all`). `FIRE_STATE` is `nothing on
      fire` if no item is priority 1 (a
      `ship_paused`-without-resume); else `1 thing on
      fire`/`N things on fire`. Per LESSONS 2026-06-15
      (awk `while (match(s, /pat/)) { s = before repl
      after }` infinite-loop trap — `repl` values may
      contain `$<digits>` substrings matching a
      dollar regex used elsewhere in the same composer)
      the substitution uses the CURSOR-based walk
      pattern. Test asserts via fixture that a `repl`
      value containing `$5.00` substring renders without
      infinite-looping AND the resulting string contains
      the literal value.

- [ ] The ranked-actions list orders by category
      priority: (1) `ship_paused` without `ship_resumed`
      in the window, (2) `budget_block` in the window,
      (3) `fleet stuck` flags (call into the existing
      `stuck_classify_one_pr` helper per LESSONS
      2026-06-05 forward-reference guard — if forward-
      reference blocks reuse, inline the minimal
      classifier per the LESSONS 2026-06-05 inline-copy
      escape hatch), (4) `lesson_draft_emitted` events
      with no subsequent `lesson_promoted` for the
      same PR, (5) slugs where the trailing-window
      `$/PR` jumped >25% over the prior window. Per
      LESSONS 2026-06-08 every awk pass declares
      `BEGIN { count = 0; promoted = 0 }`. Per
      LESSONS 2026-06-08 `IFS=$'\t'` middle-empty-
      field uses `-` sentinel. Test asserts via
      fixture that all five categories surface in
      priority order.

- [ ] By default the ranked-actions list is capped at
      THREE items total across all slugs. `--all` lifts
      the cap. The cap operates AFTER the priority
      sort, so the 3 emitted items are the top-3
      ranked across all slugs. Test asserts via
      fixture with 8 candidates that only 3 render by
      default AND all 8 render under `--all`.

- [ ] Each ranked action carries a `→ <one-line
      operator action>` and (optionally) a `→ <follow-
      up nudge>` line. The action is a literal command
      the operator can copy-paste (e.g. `fleet resume
      sidebrew --reason "back from PTO, drafts
      reviewed"`, `gh pr ready 214 && gh pr merge 214
      --auto --squash`, `fleet inbox --slug sidebrew`).
      The follow-up is contextual (e.g. "3 lesson
      drafts waiting"). Per LESSONS 2026-05-28
      (printf leading-dash) every printf of a slug
      name or command goes through `printf -- '%s'`.
      Test asserts the action line is a valid shell
      command (parses via `bash -n`).

- [ ] The "what happened while you were away" footer
      walks every slug and prints one row per slug with
      `PR count`, `dollars spent`, and a one-word
      verdict (`shipped clean`, `paused`, `capped`,
      `slowdown`, `quiet`). The footer ALSO prints a
      `total spend` summary. The footer is omitted on
      a `nothing happened` window (all slugs quiet).
      Per LESSONS 2026-06-15 the per-slug walk is ONE
      awk pass over events.jsonl AND ONE awk pass
      over runs.jsonl per slug — NOT per-day
      shellouts. Test asserts via fixture with 4
      slugs that the footer renders correctly AND
      the no-activity branch omits it.

- [ ] `bin/fleet catchup --json` emits one structured
      JSON object: `{"away_seconds": <int>,
      "away_human": "<str>", "verdict": {"items_count":
      <int>, "fire": <bool>, "summary": "<paragraph>"},
      "actions": [{"priority": <int>, "category":
      "<str>", "slug": "<str>", "headline": "<str>",
      "command": "<str>", "followup": "<str>|null"}],
      "footer": [{"slug": "<str>", "prs": <int>,
      "spent_usd": <number>, "verdict": "<str>"}],
      "total_spent_usd": <number>}`. JSON escape via
      `preflight_json_escape` per LESSONS 2026-06-03
      called directly per LESSONS 2026-06-13. Test
      asserts JSON validity via Node.

- [ ] `bin/fleet catchup --all` lifts the 3-item cap.
      `bin/fleet catchup --slug <name>` restricts
      ranked actions AND the footer to one slug.
      Unknown slug: `catchup: slug <name> not found.
      discovered slugs: <list>` to stderr, exit 2.
      Test asserts via fixture both paths.

- [ ] `bin/fleet catchup --help` prints USAGE
      mentioning `--since`, `--all`, `--slug`,
      `--json`. Per LESSONS 2026-05-30 test asserts
      via `grep -qF -- "$kw" "$help_out"`. Help block
      ends with `exit 0` per LESSONS 2026-06-01.

- [ ] `bin/fleet catchup` is a PURE READER. NO
      `events.jsonl` writes, NO `fleet_emit_event`
      calls, NO writes to `runs.jsonl`,
      `agents.config.sh`, the cross-LESSONS file, or
      any state-file (the morning/inbox state files
      are READ for mtime, never touched). Test
      asserts every slug's `events.jsonl`,
      `runs.jsonl`, the cross-LESSONS file, and the
      morning/inbox state files have unchanged
      mtimes AND byte sizes before and after
      invocation.

- [ ] `lib/common.sh` — NO changes. `prompts/` —
      NO changes. No new event types. Test asserts
      via `git diff --name-only main...HEAD --
      lib/common.sh prompts/` returns empty.

- [ ] `tests/catchup.sh` covers all 13 boxes above
      using `$HOME/.local/bin` stubs (`gh` if any
      is invoked) per LESSONS 2026-05-26 (PATH
      reset). Fixture `events.jsonl`, `runs.jsonl`,
      `agents.config.sh`, a synthetic
      `morning-state` and `inbox-state` file (with
      controllable mtimes via `touch -t`) live
      under `tests/fixtures/catchup/`. The four-
      slug fleet covers all five priority
      categories. Per LESSONS 2026-05-27 (`$(cat)`
      trap) backup/restore via `cp`. Counts use
      `awk … END { print n+0 }` per LESSONS
      2026-06-01. Per LESSONS 2026-06-08 every awk
      script declares `BEGIN { count = 0 }`. Per
      LESSONS 2026-06-08 `IFS=$'\t'` middle-empty-
      field uses `-` sentinel. Per LESSONS
      2026-06-11 any window math uses `date +%s`
      minus `Nh*3600`/`Nd*86400`, the
      `YYYY-MM-DD` form normalizes to
      `YYYY-MM-DDT00:00:00`. Per LESSONS
      2026-06-15 the events walk is ONE awk pass
      per slug. The clock is frozen via
      `FLEET_NOW_OVERRIDE`. State-file mtimes
      are set via `touch -t` to controlled
      timestamps. Run-time budget: <8s.

## Out of scope

The dev agent will NOT do these even if they seem related.

- AUTO-RUNNING `fleet catchup` on the next
  launchd tick after a detected absence. v1 is
  operator-pulled. Adding auto-run is a separate
  ticket with its own notification surface.
- SENDING the catchup briefing to email / Slack /
  ntfy. v1 prints to stdout; the operator pipes
  it. Notifications are a separate ticket per
  channel.
- A `--include <category>` / `--exclude <category>`
  flag to tune the ranking. v1 ranks all five
  categories with a fixed priority order. Tuning
  is a v2 candidate.
- RESETTING the morning/inbox state-file mtimes
  on `catchup` run. v1 does NOT touch those
  files — the operator's normal `morning`/`inbox`
  invocation owns those mtimes. catchup is read-
  only on every input.
- A `--redact` mode. v1 ships plain output;
  redaction is a follow-up ticket (per the 0053
  / 0061 convention each shareable surface gets
  redact in a separate pass).
- AUTO-INVOKING the ranked actions (e.g.
  `--auto-resume` to run `fleet resume` on every
  paused slug). v1 prints commands the operator
  copy-pastes. Auto-action is a separate ticket
  with its own safety surface.
- AN `--audience` flag analogous to 0062's
  peer/manager/self. v1 ships one prose register
  (terse, action-ranked). Audience tuning is a
  v2 candidate.
- COMPOSING catchup INTO `fleet morning` (e.g.
  morning detects "you were away" and
  delegates). v1 is standalone. Composition is
  a v2 candidate after catchup proves the shape.
- A `--diff <last-catchup> <now>` mode comparing
  two catchup runs. v1 is one window.
- WRITING the catchup briefing to a state file
  the operator can `cat` later. v1 prints
  fresh every time; the operator pipes to a
  file if they want to keep it.
- TRACKING the operator's "average absence
  duration" as a histogram in events.jsonl. v1
  is read-only and does not emit telemetry
  about its own use.

## Engineering notes

Files / patterns the dev should touch.

- `bin/fleet` — new `catchup()` dispatcher
  function placed next to the existing
  `morning()` block (find via `grep -n
  '^morning()' bin/fleet`). Per LESSONS
  2026-05-26 (`tail` shadow) `catchup` does
  not collide with any coreutils binary.
- `bin/fleet` — eleven helpers, ALL defined
  ABOVE the dispatcher block per LESSONS
  2026-06-05 (forward-reference trap):
  - `catchup_discover_slugs` — wraps
    `overview_discover_slugs`, returns
    alphabetical order.
  - `catchup_resolve_last_seen` — reads the
    newer of `morning-state` and
    `inbox-state` mtimes per the 0036/0026
    convention. Returns epoch seconds or
    `none` when both files are missing.
  - `catchup_humanize_duration` — converts
    a duration in seconds to a string like
    `5d 14h`, `2w 3d`, `8h`. Uses pure
    shell arithmetic; per LESSONS
    2026-06-11 NOT `date -j -f`.
  - `catchup_parse_since` — handles
    `Nh`/`Nd`/`YYYY-MM-DD`. Per LESSONS
    2026-06-11 the `YYYY-MM-DD` form
    normalizes to `YYYY-MM-DDT00:00:00`
    and uses the full
    `'%Y-%m-%dT%H:%M:%S'` format.
  - `catchup_collect_paused_unresumed` —
    ONE awk pass per slug over
    events.jsonl finding `ship_paused`
    events with no subsequent
    `ship_resumed` within the absence
    window. Per LESSONS 2026-06-08
    `BEGIN { count = 0; paused = 0 }`.
  - `catchup_collect_budget_blocks` —
    ONE awk pass per slug over
    events.jsonl finding `budget_block`
    events.
  - `catchup_collect_stuck_prs` — either
    delegates to the existing
    `stuck_classify_one_pr` (forward-
    reference-safe via the inline-copy
    escape hatch per LESSONS 2026-06-05)
    or re-implements the minimal
    classifier (DRAFT / BEHIND /
    account-suspended) inline. The
    follow-up ticket can consolidate.
  - `catchup_collect_unpromoted_drafts`
    — ONE awk pass per slug over
    events.jsonl pairing
    `lesson_draft_emitted` with
    subsequent `lesson_promoted` for
    the same PR.
  - `catchup_collect_cost_regressions`
    — ONE awk pass per slug over
    runs.jsonl computing `$/PR` for
    the absence window vs the prior
    equal-length window; flags
    slugs where the absence-window
    median jumped >25%. Per LESSONS
    2026-06-15 the bucket math is
    pure awk arithmetic.
  - `catchup_rank_and_cap` — merges
    all five collector outputs,
    sorts by priority then by
    severity (paused-count, budget-
    excess, stuck-duration, drafts-
    count, cost-pct), caps at 3
    unless `--all`.
  - `catchup_compose_verdict` —
    template substitution using the
    CURSOR-based walk pattern per
    LESSONS 2026-06-15.
  - `catchup_compose_action_line` —
    formats one ranked-action block
    (action + follow-up).
  - `catchup_render_text` — text
    formatter. Width via
    `preflight_visible_width` per
    LESSONS 2026-06-05. Per LESSONS
    2026-05-28 every printf of a
    slug name or command goes
    through `printf -- '%s'`.
  - `catchup_render_json` — JSON
    formatter. JSON escape via
    `preflight_json_escape` per
    LESSONS 2026-06-03 called
    directly per LESSONS 2026-06-13
    (no `*_json_escape` wrapper).
- `bin/fleet` — `catchup()` end-state
  must be `exit 0` / `exit 2` on every
  code path per LESSONS 2026-06-01.
- `bin/fleet` — dispatcher block: `if
  [ "$CMD" = "catchup" ]; then catchup
  "$@"; fi`. Place AFTER the `morning`
  dispatcher.
- `bin/fleet` — help banner block at
  the top of the file gets ONE new
  line: `fleet catchup re-orientation
  briefing after a >72h absence —
  ranked actions, three at a time`.
  README "Daily ops" code block gets
  the same line, appended via the
  same single-edit pattern that
  avoided LESSONS 2026-05-25.
- `AGENTS.md` — NO content change.
- `lib/common.sh` — NO changes.
- `prompts/` — NO changes.
- `tests/fixtures/catchup/` — NEW
  directory holding four slug
  subdirs (`paused-no-resume`,
  `budget-hit`, `stuck-pr`,
  `clean-shipper`) each with
  `events.jsonl`, `runs.jsonl`,
  `agents.config.sh`. A fifth
  `cost-regression` slug exercises
  the priority-5 category. Two
  control state-files
  (`morning-state`, `inbox-state`)
  with controllable mtimes
  (`touch -t`) cover the auto-
  detect AND the both-missing
  branches.
- `tests/catchup.sh` — top of file
  mirrors `tests/morning.sh`
  (closest prior composer — shares
  the state-file mtime convention).
  Stubs live under `$HOME/.local/
  bin` per LESSONS 2026-05-26 (PATH
  reset). Counts use `awk … END {
  print n+0 }` per LESSONS
  2026-06-01. Per LESSONS
  2026-05-27 backup/restore via
  `cp`. Per LESSONS 2026-06-08
  every awk script declares
  `BEGIN { count = 0 }`. Per
  LESSONS 2026-06-08 `IFS=$'\t'`
  middle-empty-field uses `-`
  sentinel. Per LESSONS
  2026-06-11 any window math
  uses `date +%s` minus
  `Nh*3600`/`Nd*86400`. Per
  LESSONS 2026-06-15 the events
  walk is ONE awk pass per
  slug. The clock is frozen via
  `FLEET_NOW_OVERRIDE`. State-
  file mtimes are set via
  `touch -t` to controlled
  timestamps. Per LESSONS
  2026-06-07 (`morning` reader
  mtime-banner trap) the
  test does NOT compose
  catchup's output into a
  golden-byte-match against
  state-file mtimes; instead
  it asserts STRUCTURED
  per-AC properties (verdict
  sentence shape, items
  count, footer rows). The
  test design AVOIDS the
  golden-byte trap entirely.
  Run-time budget: <8s.
- `bin/fleet` — local variables
  inside `catchup()` whose names
  match other subcommand functions
  MUST be prefixed (per LESSONS
  2026-06-19 self-check false-
  positive trap). The catalog of
  names to avoid as plain `local`
  names: `morning`, `inbox`,
  `recap`, `digest`, `weekly`,
  `rank` (used as local in 0060
  flaky originally), `stuck`,
  `flaky`, `incident`, `diff`,
  `replay`, `tour`, `add`,
  `migrate`, `pulse`, `share`,
  `invoice`, `why`, `resume`,
  `vacation`. Use `catchup_*`-
  prefixed locals throughout.
- New deps: NONE. Pure shell +
  awk + Node (already a kit dep
  for JSON validation in the
  test).
- Public API: additive —
  `bin/fleet catchup` is a new
  subcommand. ZERO new event
  types, ZERO event writes,
  ZERO `lib/common.sh`
  changes, ZERO `prompts/`
  changes, ZERO new manifest
  knobs. ONE new constant
  (`CATCHUP_AWAY_THRESHOLD_
  HOURS=72`) inside `bin/
  fleet` only.
- BREAKING flag: NO. PR body
  affirms "pure reader, no
  events.jsonl writes, no
  `fleet_*` signature
  changes, no `lib/common.sh`
  changes, no `prompts/`
  changes."
- Reinstall required: NO.
  `lib/` and `prompts/` are
  untouched.
- LESSONS to defend against:
  2026-05-25 (README "Daily
  ops" code block addition),
  2026-05-26 (`tail` shadow —
  `catchup` is safe),
  2026-05-26 (PATH reset —
  stubs in `$HOME/.local/
  bin`), 2026-05-27 (`$(cat)`
  trap — use `cp` for
  backup/restore in tests),
  2026-05-28 (printf
  leading-dash — every slug-
  name / command printf
  goes through `printf --
  '%s'`), 2026-05-30 (`grep
  -F --` trap), 2026-06-01
  (`grep -c file || echo 0`
  double-print — counts
  use `awk … END { print
  n+0 }`), 2026-06-01
  (dispatcher fall-through
  — every code path ends
  `exit 0/2`), 2026-06-03
  (UTF-8 sign-extension —
  JSON escape via
  `preflight_json_escape`),
  2026-06-05 (dispatcher
  forward-reference — all
  `catchup_*` helpers
  defined ABOVE the
  dispatcher; if reusing
  `stuck_classify_one_pr`
  from 0059, inline the
  minimal classifier per
  the LESSONS 2026-06-05
  inline-copy escape
  hatch), 2026-06-05
  (bash 3.2 LC_ALL caching
  — any string-length op
  via `LC_ALL=C awk`),
  2026-06-05 (export-in-
  subshell trap — per-slug
  manifest reads inside
  `( … )`), 2026-06-07
  (morning reader mtime-
  banner trap — tests do
  NOT golden-byte-match
  catchup's output against
  mtime-dependent lines),
  2026-06-08 (awk empty-
  string-key — `BEGIN {
  count = 0 }`), 2026-06-08
  (`IFS=$'\t'` middle-
  empty-field — sentinel
  `-`), 2026-06-11 (BSD
  `date -j -f` fills
  missing time fields —
  `Nh`/`Nd` use `date +%s`
  arithmetic, `YYYY-MM-DD`
  uses full
  `'%Y-%m-%dT%H:%M:%S'`),
  2026-06-13 (no
  `*_json_escape` wrapper
  around
  `preflight_json_escape`
  — called directly),
  2026-06-15 (per-day
  shellout inside per-slug
  loops is O(window ×
  N_slugs) — events walk
  is one awk pass per
  slug), 2026-06-15 (awk
  `while (match(s, /pat/))
  { s = before repl after
  }` infinite-loop trap —
  template substitution
  uses CURSOR-based walk
  pattern because verdict
  values may include
  `$<digit>` substrings),
  2026-06-19 (`local`
  shadows subcommand-
  function name self-check
  false positive — all
  `catchup()` locals
  prefixed `catchup_*`).
  Cross-LESSONS courtiq
  2026-05-21/#14 (DRAFT +
  auto-merge fails to
  arm) informs the stuck
  classifier; cross-
  LESSONS digitalcraft
  2026-05-26 (account
  suspended at
  actions/checkout)
  informs the stuck
  classifier. Cross-
  LESSONS fleet-control
  2026-05-26 (`Set<string>`
  test seam) is irrelevant
  here — catchup keeps no
  process-lifetime state.
- This ticket compounds 0036
  (`fleet morning` —
  catchup reads morning's
  state-file mtime), 0026
  (`fleet inbox` — catchup
  reads inbox's state-file
  mtime), 0019 (`fleet
  overview` — reuses
  `overview_discover_slugs`),
  0059 (`fleet stuck` —
  catchup uses the same
  per-PR classifier), 0060
  (`fleet flaky` — catchup
  surfaces flake-driven
  send-backs as lower-
  priority), 0006
  (`ship_paused` event —
  catchup's #1 ranking
  input), 0004
  (`budget_block` event —
  catchup's #2 ranking
  input), 0022
  (`lesson_draft_emitted`
  event — catchup's #4
  ranking input), 0028
  (`lesson_promoted`
  event — catchup pairs
  drafts and promotions),
  0048 (`fleet recap` —
  recap is the
  descriptive window;
  catchup is the
  prescriptive ranking),
  0061 (`fleet invoice`
  — catchup's cost-
  regression nudge
  cites prior month's
  invoice), 0030 (`fleet
  resume` — catchup's #1
  action links directly
  to it), 0046 (`fleet
  vacation` — catchup is
  the inverse). Per P-1
  the diff is small:
  ~360 lines of
  `catchup_*` helpers +
  ~290 lines of test +
  5 fixture slug subdirs
  + 2 control state-
  files + one help-text
  line + one README
  line.

## Implementation log

- 2026-06-23 — implementation-dev: feat/0064-fleet-catchup-reorientation
  opened. Tests-first per P-2: `tests/catchup.sh` with one block per
  AC checkbox, then `catchup()` + helpers in `bin/fleet`. Pure reader,
  no `lib/` / `prompts/` / event-type changes.
- 2026-06-23 — implementation-dev: all 13 ACs pass; local gate green
  (shellcheck -S warning rc=0, bash -n rc=0, check-backlog rc=0,
  self-check 3 hits = on-main baseline). No new event types, no
  `lib/common.sh` / `prompts/` diff. Status flipped to `shipped`.
