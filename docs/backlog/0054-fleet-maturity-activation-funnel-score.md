---
id: 0054
title: fleet maturity <slug> scores how far one project has walked the post-install activation funnel
status: groomed
priority: P2
area: observability
created: 2026-06-15
owner: gtm-innovation
---

## User story

As a fleet operator who installed `agent-fleet` on a new project two weeks
ago — who completed `fleet onboard` (0011), passed `fleet onboarding-check`
(0041), took the `fleet tour` (0050) — and who now wants to answer the
question "is this slug ACTUALLY getting value from the kit, or is it
sitting there burning launchd timers while I do nothing?" — I want
`bin/fleet maturity <slug>` to score the slug against a fixed 7-step
activation funnel (was `morning` ever run? was a `lesson_draft` ever
promoted? did the slug ship ≥3 PRs cleanly? did a streak ever start? did
`pr-footer` fire on ≥1 PR? did the slug recover from at least one
`ship_paused`? did the slug consume a CROSS_LESSON in PHASE 0?) and print
ONE line per step with PASS / PENDING / STUCK plus a "next nudge"
suggestion, so I can tell at a glance whether a new slug is stalled, on
the rails, or fully activated — without having to manually re-derive
that from `fleet inbox` plus `fleet streak` plus my own memory.

## Why now (four lenses)

### Product Owner
The onboarding arc today gets the operator INSTALLED (`fleet onboard`,
`fleet preflight`, `fleet onboarding-check`) and TAUGHT (`fleet tour`,
`fleet kickstart --demo`) — both at install moment-zero. After that the
kit assumes the operator will naturally activate (run morning, promote
a lesson, watch a streak start). In practice some slugs DO activate
quickly; some sit there for 30 days emitting only `run_started` /
`run_completed` events because the operator forgot they installed the
loop or hasn't yet trusted it enough to look at the PRs it opens.
Today there is NO surface that says "this slug is week-4-stalled at
step 3 of 7" — the operator either notices on their own (rare) or
the slug quietly burns ~$1/week in launchd ship runs that never
produce a merged PR because the operator never reviews them.

The smallest meaningful unit of value is one command, one score per
slug, one suggested next-action per pending step:

```
fleet maturity sidebrew

maturity: sidebrew — installed 14 days ago, score 3/7
  [PASS] step 1: events.jsonl has ≥1 run_completed
         (last completion: 11 hours ago)
  [PASS] step 2: a real PR was opened by the loop
         (1 pr_opened event in the last 14d)
  [PASS] step 3: you ran `fleet morning` at least once
         (last run: 6 days ago — drifting)
  [STUCK] step 4: no merged PR yet
         the loop has opened 1 PR but it sits unmerged. run
         `fleet doctor sidebrew` to check for a stuck send-back
         OR review the PR — the loop won't auto-merge without
         you signing off if trainee mode is on.
  [PENDING] step 5: no lesson promoted yet
         the loop will emit a `lesson_draft_emitted` event the
         first time a send-back warrants one. then run
         `fleet lessons-promote sidebrew` to lock it in.
  [PENDING] step 6: no streak started yet
         requires 7 consecutive green days. you're 0/7.
  [PENDING] step 7: no CROSS_LESSON cited at PHASE 0 yet
         your `agents.config.sh` has CROSS_LESSONS set, but no
         lesson_promoted event has fired across the fleet for
         sidebrew to consume. this step activates passively
         once another slug promotes a relevant lesson.

next nudge: address step 4 first — that's blocking everything
downstream. open PR #1 in github and either approve it or
request changes.
```

Subtraction: the operator stops having to ask "is sidebrew actually
working or is it just running?" Per P-5 (operator confidence over
feature richness), the win is the absent guesswork about whether a
new slug is on track.

The seven steps are FIXED in v1 (not configurable) so the activation
funnel reads the same across every operator's fleet — which makes
the score a comparable artifact across slugs (and feeds into 0043
`fleet rank` as a column in a follow-up).

### Stakeholder
This is **moat-deepening on the retention axis** — the kit's first
surface that watches whether a NEW slug is actually graduating from
"installed" to "activated." Per P-6 (telemetry is the source of
truth), the maturity score is a PURE READER of the slug's
`events.jsonl`, the slug's `agents.config.sh` (for CROSS_LESSONS
path), and the fleet-wide CROSS_LESSONS feed. No new event types.
No writes. No `lib/common.sh` change. The diff is the 7-step rubric
+ a per-step evaluator function + the renderer. ~300 lines.

The activation rubric IS the moat: it codifies "what does it MEAN
for a slug to be using the kit successfully" — until now this has
been implicit operator intuition. By making it explicit, the kit
can self-diagnose stalled adoptions before the operator notices,
and the rubric becomes the answer to "what should I expect in my
first 30 days?" for new operators reading the README.

Compounds 0011 (`fleet onboard` — the install whose installed-at
timestamp anchors the maturity window), 0026 (`fleet inbox` — the
daily-TODO surface that maturity refers operators to for pending
steps), 0036 (`fleet morning` — step 3 checks for at least one
invocation), 0028 (`fleet lessons-promote` — step 5's nudge),
0042 (`fleet streak` — step 6's data source), 0044 (`fleet
pr-footer` — step 4 reads `pr_footer_posted` events from this
ticket), 0006 (`ship_paused` — step 6's prerequisite signal),
0009 (`fleet lessons-sync` — step 7's CROSS_LESSON signal),
0041 (`fleet onboarding-check` — the moment-zero verifier that
maturity picks up FROM).

Per P-3 (heal in-flight before new work), `maturity` is read-only
and cheap (one events.jsonl walk per slug) — never blocks heal
work.

### User (operator on a Friday afternoon, three weeks after adding a slug, wondering if it's actually working)
The operator added `sidebrew` to their fleet on a Tuesday three
weeks ago and hasn't looked at it since. They run `fleet maturity
sidebrew`. They see 3/7 — and the [STUCK] line on step 4 tells
them PR #1 has been sitting open for two weeks because they never
reviewed it. They open it, review it, merge it. The next ship
cycle picks up the next ticket; the slug crosses into step 5
the next time a send-back lands. Two weeks later the slug is at
5/7 and starting to be useful.

Without `fleet maturity`, the same operator either notices the
stuck PR after 30 days (by which point the slug has burned $15
in ship runs that produced nothing), or never notices and silently
drops the slug. Per P-5, the win is converting "I forgot I
installed this" into "the kit reminded me at the right step."

Sub-scenario: an EXPERIENCED operator runs `fleet maturity --all`
across the whole fleet. The kit prints one line per slug:
`sidebrew 3/7 (stuck at step 4)` / `courtiq 7/7 (fully activated)`
/ `hedgehog 5/7 (pending step 6)`. The operator triages the
stalled ones from one table. This is the maturity-as-a-rank
view; it complements `fleet rank` (0043) which scores HEALTHY
slugs and `fleet diff` (0038) which compares two.

### Growth
This is the surface that makes the kit's "your first 30 days"
promise MEASURABLE. A friend evaluating the kit who reads the
README's "what does a working fleet look like?" section can be
pointed at the 7-step rubric and told "your slug should be at
4/7 by day 14; 6/7 by day 30; 7/7 once a peer slug promotes a
relevant CROSS_LESSON." That gives the new operator a concrete
expectation instead of vibes. Per the brief's "Onboarding
outcome score after week 1 / week 4… Nothing measures whether
the operator IS GETTING VALUE 7/30 days in. A `fleet first-week`
/ `fleet maturity <slug>` that scores how far along the
activation funnel the operator's slug actually is" — this is
the direct answer.

Differentiated from `fleet onboarding-check` (0041): the check
runs at moment-zero and asserts the install is healthy.
Maturity runs at day 7 / day 14 / day 30 and asserts the slug
is actually using what was installed. Onboarding-check is a
prerequisite for maturity step 1 (you can't have run_completed
events without a healthy install).

Differentiated from `fleet doctor` (0003): doctor checks
infrastructure health (is launchd loaded? is the gh CLI
authed?). Maturity checks behavioral activation (is the
operator actually USING the loop?).

## Acceptance criteria

Each box maps 1:1 to a test scenario in `tests/maturity.sh`.

- [ ] `bin/fleet maturity <slug>` is a new subcommand. Required
      arg is the slug name. Missing slug: prints `maturity:
      usage: bin/fleet maturity <slug> [--all] [--since Nd]
      [--json]` to stderr, exit 2 per LESSONS 2026-06-01.
      Unknown slug (not in `overview_discover_slugs`): prints
      `maturity: slug <name> not found. discovered slugs:
      <list>` to stderr, exit 2. Test asserts both refusals.
- [ ] The slug's installed-at anchor is the timestamp of the
      FIRST `run_started` event in the slug's `events.jsonl`,
      fallback to the file's mtime if no run has fired yet,
      fallback to NOW if both are missing. The "days since
      install" value drives the rendered "installed N days
      ago" header. Test asserts via three fixtures (events
      with run_started, events with no run_started but mtime,
      empty file).
- [ ] Step 1 (`HAS_RUN_COMPLETED`) PASSes when the slug's
      `events.jsonl` has ≥1 `run_completed` event in the
      trailing window (default 30d, configurable via
      `--since`). Score `[PASS]` or `[PENDING]`. The PASS
      render includes the human-friendly "last completion:
      <relative-time>". Test asserts both branches.
- [ ] Step 2 (`HAS_PR_OPENED`) PASSes when the slug has ≥1
      `pr_opened` event in the window. Score `[PASS]` or
      `[PENDING]`. Test asserts.
- [ ] Step 3 (`MORNING_INVOKED`) PASSes when the kit's
      per-operator state directory
      (`$HOME/.local/state/agent-fleet/morning-last-run`,
      written by ticket 0036) shows the operator has run
      `fleet morning` at least once in the trailing window.
      MISSING file is `[PENDING]`; file mtime >7 days old
      is `[PASS] (drifting — last run: <relative>)` per
      the User-lens example. Test asserts all three
      branches.
- [ ] Step 4 (`PR_MERGED`) PASSes when the slug has ≥1
      `pr_opened` event whose PR number ALSO appears in a
      `pr_footer_posted` event (the post-merge footer from
      ticket 0044). PENDING if `pr_opened` count is 0;
      STUCK if `pr_opened` count is ≥1 but
      `pr_footer_posted` count is 0 AND the oldest
      unmerged `pr_opened` is older than 48h. The STUCK
      render includes the nudge per the User-lens
      example. Test asserts all three branches.
- [ ] Step 5 (`LESSON_PROMOTED`) PASSes when the slug has
      ≥1 `lesson_promoted` event (from ticket 0028) in
      the trailing window. PENDING otherwise with the
      nudge per the User-lens example. Test asserts.
- [ ] Step 6 (`STREAK_STARTED`) PASSes when `fleet streak
      <slug> --json` returns a streak length ≥7. PENDING
      otherwise with the day-count (e.g. `you're 3/7`).
      Per LESSONS 2026-06-13 (no `*_json_escape` wrapper)
      the streak invocation parses `fleet streak --json`
      directly via `node -e`. Test asserts via fixture
      streak data.
- [ ] Step 7 (`CROSS_LESSON_CITED`) PASSes when the slug's
      `agents.config.sh` has `CROSS_LESSONS=` set AND the
      resolved CROSS_LESSONS file has ≥1 section whose
      `## YYYY-MM-DD — <title>` heading matches a
      `lesson_promoted` event in the slug's events
      (telemetry shape from ticket 0009). The match is
      lowercase substring in either direction (same
      logic as 0051 `fleet skill-gap`). PENDING with the
      passive-activation note per the User-lens example.
      Test asserts both branches.
- [ ] The "next nudge" footer points at the LOWEST-NUMBERED
      step whose status is STUCK, falling back to the
      lowest PENDING if no STUCK. The nudge text is the
      same nudge embedded in the per-step render. When
      every step is PASS, the footer is `next nudge:
      none — sidebrew is fully activated. run \`fleet
      portfolio --redact\` to share the shape.` Test
      asserts via fixtures for each branch.
- [ ] `bin/fleet maturity --all` runs the score for every
      discovered slug in one pass and prints a one-line
      summary per slug `<slug> <score>/7 (<status of
      lowest-numbered non-PASS step>)`. Per LESSONS
      2026-05-28 every printf of a slug name goes through
      `printf -- '%s'`. Sorted by ascending score so the
      stalled slugs surface at the top. Test asserts via
      fixture with three slugs of varying scores.
- [ ] `bin/fleet maturity <slug> --since <Nd|YYYY-MM-DD>`
      overrides the default 30-day window. Per LESSONS
      2026-06-11 (BSD `date -j -f` fills missing time
      fields with NOW-of-day) `--since YYYY-MM-DD`
      appends `T00:00:00` before any date math. Test
      asserts.
- [ ] `bin/fleet maturity <slug> --json` emits one
      structured JSON object: `{"slug": "<name>",
      "installed_days_ago": <int>, "score": <int>,
      "steps": [{"id": "HAS_RUN_COMPLETED", "status":
      "PASS"|"PENDING"|"STUCK", "nudge": "<text>"},
      …], "next_nudge": "<text>"}`. JSON escape via
      `preflight_json_escape` per LESSONS 2026-06-03
      called directly per LESSONS 2026-06-13 (no
      `*_json_escape` wrapper). Test asserts JSON
      validity via Node.
- [ ] `bin/fleet maturity --help` prints USAGE
      mentioning the slug arg, `--all`, `--since`,
      `--json`. Per LESSONS 2026-05-30 test asserts via
      `grep -qF -- "$kw" "$help_out"`. Help block ends
      with `exit 0` per LESSONS 2026-06-01 (dispatcher
      fall-through).
- [ ] `bin/fleet maturity` is a PURE READER. NO
      `events.jsonl` writes, NO `fleet_emit_event` calls,
      NO writes to `agents.config.sh` or CROSS_LESSONS
      or the morning-last-run state file. Test asserts
      the slug's `events.jsonl` byte size is unchanged
      before and after invocation.
- [ ] `lib/common.sh` — NO changes. `prompts/` — NO
      changes. No new event types. Test asserts via
      `git diff --name-only main...HEAD -- lib/common.sh
      prompts/` returns empty.
- [ ] `tests/maturity.sh` covers all 16 boxes above
      using `$HOME/.local/bin` stubs per LESSONS
      2026-05-26 (PATH reset). Fixture `events.jsonl`,
      `agents.config.sh`, `CROSS_LESSONS.md`, and
      `morning-last-run` state file live under
      `tests/fixtures/maturity/`. Per LESSONS
      2026-05-27 backup/restore via `cp` (NOT
      `$(cat)`). Counts use `awk … END { print n+0 }`
      per LESSONS 2026-06-01. Per LESSONS 2026-06-08
      every awk script declares `BEGIN { count = 0 }`.
      Per LESSONS 2026-06-08 IFS=$'\t' middle-empty-
      field uses `-` sentinel. The clock is frozen via
      `FLEET_NOW_OVERRIDE`. Run-time budget: <10s.

## Out of scope

The dev agent will NOT do these even if they seem related.

- A CONFIGURABLE rubric (`--rubric custom.sh`). v1 hardcodes
  the 7-step funnel so the score is comparable across
  operators. Custom rubrics are v2 if asked.
- A PREDICTIVE step ("you're on track to hit step 5 by day
  18"). v1 is descriptive (where you ARE on the funnel),
  not predictive. Prediction is out.
- An AUTO-NUDGE channel (email, Slack, push). v1 prints to
  stdout; the operator runs it on their own cadence.
  Auto-channels are a v2 ask.
- A FLEET-wide `--all --json` aggregated metric ("operator
  X has 4 slugs at average score 5.25"). v1 prints one
  line per slug; aggregation is the caller's job.
- INTEGRATING maturity into `fleet morning` (0036) as an
  auto-row. v1 is a separate command. Integration is a
  v2 once the rubric stabilizes.
- AUTO-PAUSING a slug whose maturity has been STUCK at
  step 4 for >14 days. v1 only diagnoses; auto-pause is
  ticket 0006's job and would require BREAKING the
  pure-reader contract.
- A MATURITY history channel (`maturity-snapshot` events
  written daily so the operator can plot a trajectory).
  v1 is point-in-time only. Adding a new event type
  requires BREAKING and a full reinstall — out of scope
  for v1.
- A `fleet maturity --vs <other-slug>` diff mode. v1 is
  single-slug or `--all`; cross-slug diff is `fleet diff`
  (0038)'s pattern.
- A launchd schedule. Operator-invoked only.

## Engineering notes

Files / patterns the dev should touch.

- `bin/fleet` — new `maturity()` dispatcher function placed
  next to the existing `streak()` block (find via `grep -n
  '^streak()' bin/fleet`). Per LESSONS 2026-05-26 (`tail`
  shadow) `maturity` does not collide with any coreutils
  binary.
- `bin/fleet` — nine helpers, ALL defined ABOVE the
  dispatcher block per LESSONS 2026-06-05 (forward-reference
  trap):
  - `maturity_resolve_install_anchor` — returns the
    installed-at timestamp per AC #2.
  - `maturity_step1_has_run_completed` — evaluates
    step 1, returns `PASS|PENDING` and a render line.
  - `maturity_step2_has_pr_opened` — same shape, step 2.
  - `maturity_step3_morning_invoked` — reads the
    morning state file from ticket 0036, returns
    `PASS|PASS_DRIFTING|PENDING` per AC #5.
  - `maturity_step4_pr_merged` — correlates `pr_opened`
    with `pr_footer_posted`, returns
    `PASS|PENDING|STUCK` per AC #6. Per LESSONS
    2026-06-08 the awk correlator declares
    `BEGIN { count = 0 }`. Per LESSONS 2026-06-08
    IFS=$'\t' middle-empty-field uses `-` sentinel.
  - `maturity_step5_lesson_promoted` — same shape,
    step 5.
  - `maturity_step6_streak_started` — invokes
    `fleet streak <slug> --json` and parses via
    `node -e` per AC #8. Per LESSONS 2026-06-13
    (no `*_json_escape` wrapper) does NOT wrap the
    streak invocation in a custom helper.
  - `maturity_step7_cross_lesson_cited` — reuses
    the fuzzy-match helper from ticket 0051
    (`skill_gap_fuzzy_match`) verbatim. Per LESSONS
    2026-06-05 (bash 3.2 LC_ALL caching) the match
    runs via `LC_ALL=C awk`.
  - `maturity_compose_next_nudge` — picks the
    lowest-numbered STUCK then PENDING step's nudge
    text per AC #10.
  - `maturity_render_text` and `maturity_render_json`
    — formatters. Width via `preflight_visible_width`
    per LESSONS 2026-06-05; JSON escape via
    `preflight_json_escape` per LESSONS 2026-06-03
    called directly per LESSONS 2026-06-13.
- `bin/fleet` — `maturity()` end-state must be `exit 0`
  / `exit 2` on every code path per LESSONS 2026-06-01.
- `bin/fleet` — dispatcher block: `if [ "$CMD"
  = "maturity" ]; then maturity "$@"; fi`. Place AFTER
  the `streak` dispatcher.
- `bin/fleet` — help banner block at the top of the
  file gets ONE new line: `fleet maturity <slug> score
  one project against the 7-step activation funnel`.
  README "Daily ops" code block gets the same line,
  appended via the same single-edit pattern that
  avoided LESSONS 2026-05-25.
- `AGENTS.md` — NO content change.
- `lib/common.sh` — NO changes.
- `prompts/` — NO changes.
- `tests/fixtures/maturity/` — NEW directory holding
  per-slug `events.jsonl` fixtures for each
  step-status combination, plus `agents.config.sh`
  fixtures (with and without `CROSS_LESSONS`),
  a fixture CROSS_LESSONS feed, and fixture
  `morning-last-run` state files (present,
  stale, missing).
- `tests/maturity.sh` — top of file mirrors
  `tests/streak.sh` (the closest prior ticket;
  shares the day-window logic). Stubs live under
  `$HOME/.local/bin` per LESSONS 2026-05-26
  (PATH reset). Counts use `awk … END { print
  n+0 }` per LESSONS 2026-06-01. Per LESSONS
  2026-05-27 backup/restore via `cp`. The clock
  is frozen via `FLEET_NOW_OVERRIDE`. Run-time
  budget: <10s.
- New deps: none. Pure shell + awk + Node (already
  a kit dep for `fleet streak --json` parsing).
- Public API: additive — `bin/fleet maturity` is
  a new subcommand. ZERO new event types, ZERO
  event writes, ZERO `lib/common.sh` changes,
  ZERO `prompts/` changes.
- BREAKING flag: NO. PR body affirms "pure reader,
  no events.jsonl writes, no `fleet_*` signature
  changes, no runtime hot-path changes."
- Reinstall required: NO. `lib/` and `prompts/`
  are untouched.
- LESSONS to defend against: 2026-05-25 (README
  "Daily ops" code block addition), 2026-05-26
  (`tail` shadow), 2026-05-26 (PATH reset —
  stubs in `$HOME/.local/bin`), 2026-05-27
  (`$(cat)` trap — use `cp` for backup/restore
  in tests), 2026-05-28 (printf leading-dash —
  every slug-name printf goes through `printf
  -- '%s'`), 2026-05-30 (`grep -F --` trap),
  2026-06-01 (`grep -c file || echo 0`
  double-print — counts use `awk … END { print
  n+0 }`), 2026-06-01 (dispatcher fall-through
  — every code path ends `exit 0/2`), 2026-06-03
  (UTF-8 sign-extension — JSON escape via
  `preflight_json_escape`), 2026-06-05
  (dispatcher forward-reference — all
  `maturity_*` helpers defined ABOVE the
  dispatcher), 2026-06-05 (bash 3.2 LC_ALL
  caching — fuzzy match via `LC_ALL=C awk`),
  2026-06-05 (export-in-subshell trap — any
  agents.config.sh read happens inside `( … )`),
  2026-06-08 (awk empty-string-key —
  `BEGIN { count = 0 }`), 2026-06-08
  (IFS=$'\t' middle-empty-field — sentinel `-`),
  2026-06-11 (BSD `date -j -f` fills missing
  time fields with NOW-of-day — `--since
  YYYY-MM-DD` appends `T00:00:00`), 2026-06-13
  (no `*_json_escape` wrapper around
  `preflight_json_escape` — called directly,
  and the `fleet streak --json` parser is
  inline `node -e`).
- This ticket compounds 0011 (`fleet onboard`
  — the install-anchor data), 0026 (`fleet
  inbox` — referenced in nudges), 0028
  (`fleet lessons-promote` — step 5's
  prerequisite signal), 0036 (`fleet morning`
  — step 3's state file), 0042 (`fleet
  streak` — step 6's data source), 0044
  (`fleet pr-footer` — step 4 reads
  `pr_footer_posted` events), 0006
  (`ship_paused` — referenced in step 4's
  STUCK nudge), 0009 (`fleet lessons-sync`
  — step 7's CROSS_LESSONS data),
  0041 (`fleet onboarding-check` —
  moment-zero verifier maturity picks up
  from), 0051 (`fleet skill-gap` — shares
  `skill_gap_fuzzy_match` helper verbatim,
  zero duplication), 0043 (`fleet rank` —
  v2 may add maturity-score as a column).
  Per P-1 the diff is small: ~300 lines
  of `maturity_*` helpers + ~280 lines of
  test + 10 fixture files + one help-text
  line + one README line.

## Implementation log

(Appended by the implementation-dev agent during execution.)
