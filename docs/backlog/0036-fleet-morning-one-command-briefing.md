---
id: 0036
title: fleet morning collapses the daily briefing into one composed command
status: shipped
priority: P1
area: observability
created: 2026-06-07
owner: gtm-innovation
---

## User story

As a fleet operator who at 9am on a weekday currently runs `bin/fleet
digest`, then `bin/fleet inbox`, then (on a Sunday) `bin/fleet weekly`,
then `bin/fleet atlas --since 7d` to see the top resilience patterns,
and who has started skipping the second or third command on rushed
mornings — silently growing draft-promotion debt as a result — I want
`bin/fleet morning` to print all four of those views, in priority
order, in one screen, with a single-line verdict at the top
(`MORNING — 1 thing owes you a click, 0 paused, fleet OK`) so I can
decide in 15 seconds whether to keep my coffee uninterrupted or open
fleet-control, instead of remembering which sub-command goes first
and which one I forgot last Thursday.

## Why now (four lenses)

### Product Owner
Tickets 0012 (`fleet digest`), 0026 (`fleet inbox`), 0025 (`fleet
weekly`), and 0031 (`fleet atlas`) each answer a different daily
question — "what happened?", "what do I owe?", "was the week worth
it?", "what survived?" — and each is one command. The retention
failure I am defending against is not the absence of any of those
surfaces; it is the operator getting tired of typing four commands in
a row every morning. Eighty percent of mornings the operator only
needs the digest line and a check that the inbox is empty; twenty
percent they actually need to take action. The smallest meaningful
unit of value is one composed command that produces the same screen
the operator was assembling by hand:

```
MORNING — 2026-06-07 Sun · 1 owes you a click · 0 paused · fleet OK

DIGEST (24h)
  agent-fleet     OK         3 opened / 3 merged   $1.41   ticket 0035 shipped
  courtiq         OK         1 opened / 1 merged   $0.62   feat: add metrics card
  almanac         THROTTLED  0 opened / 0 merged   $0.00   budget_block 6h ago

INBOX
  drafts to promote                 1 across 1 project
    agent-fleet      1 draft         docs/LESSONS.md
  self-cancel expiring (<=7d)       0
  paused projects                   0
  budget tripped today              1 (see almanac digest line)

WEEKLY (Sunday-only — last 7d)
  ships  21    merges 21    sendbacks 3    spend $9.84    ROI 7.0/day
  top atlas patterns: gh_graphql_502 (4)  actions_silent (2)

NEXT: `fleet lessons-promote` for the agent-fleet draft.
```

Subtraction: the operator types `fleet morning` instead of `fleet
digest && fleet inbox && fleet weekly && fleet atlas --since 7d`.
The verdict line at the TOP encodes the keep-going / take-action
decision — same shape as `replay --batch`'s `OK / WARN / FAIL`
verdict (ticket 0034) and `prompts-score`'s verdict band (ticket
0024). On a non-Sunday the WEEKLY section is suppressed entirely
(per ticket 0025's Sunday-only contract); the verdict line still
prints, the digest + inbox still print. The retention shape is "one
muscle memory, every morning."

### Stakeholder
This is retention-deepening, not feature richness. The kit already
emits every signal `morning` reads; the daily briefing is a pure
composition of existing readers. Per P-1 (smallest viable change),
the implementation is a dispatcher that shells through to the four
existing functions and assembles the verdict from their outputs —
NOT a re-implementation. Per P-5 (operator confidence over feature
richness), the win is removing a daily question, not adding a daily
data point. The moat compounds because every future signal the kit
adds (a new event type, a new readiness check) only has to wire into
ONE of the four existing surfaces and it lands in the morning
briefing automatically. The cost of adding telemetry stays flat as
the kit grows; the cost of READING that telemetry every morning
trends toward zero. That is the right ratio for a kit a single
operator is meant to run for years.

### User (operator Tuesday 9:02am, three slugs)
Types `fleet morning`. Reads the verdict line: `1 owes you a click,
0 paused, fleet OK`. Scrolls 20 lines of screen. Sees one DRAFT to
promote in agent-fleet. Runs `fleet lessons-promote` (per the NEXT
hint at the bottom). Closes the terminal. Three commands, all
remembered, none skipped. Compare with today's path: open terminal,
type `fleet digest`, read, type `fleet inbox`, read, debate whether
to bother with `fleet atlas`, skip it, close terminal, forget about
the draft for three days. The composed command removes the friction
point AND removes the decision point about which sub-command to
skip.

### Growth
"Type one command in the morning, decide in 15 seconds" is the
shape every successful daily-driver CLI converges on (`git status`
in the dev's hands, `kubectl get pods` in the SRE's hands). The kit
needs that anchor. A friend running their own loop sees `fleet
morning` once and immediately understands the daily ritual — no
README scavenger hunt to find which four commands to compose.
README screenshots become trivially shareable because one screen
shows the whole loop's posture. Compounds 0012 (digest), 0025
(weekly), 0026 (inbox), 0031 (atlas) — all four already produce the
text that `morning` lays out; this ticket is the binding.

## Acceptance criteria

Each box maps 1:1 to a test scenario in `tests/morning.sh`.

- [ ] `bin/fleet morning` (no flags) prints, in order: (1) a single
      VERDICT line (format defined below), (2) the `fleet digest`
      output under a `DIGEST (24h)` heading, (3) the `fleet inbox`
      output under an `INBOX` heading, (4) on Sundays ONLY, the
      `fleet weekly` summary line + the top-3 atlas patterns
      under a `WEEKLY (Sunday-only — last 7d)` heading,
      (5) one `NEXT: <hint>` footer (next concrete action or
      `nothing else owes you a click. enjoy your day.`). Exits 0
      on success. Test fixtures three projects (one healthy, one
      throttled, one with an unpromoted draft) and asserts the
      assembled output against a checked-in golden
      `tests/fixtures/morning.text.golden.txt`.
- [ ] The VERDICT line format is exactly:
      `MORNING — <YYYY-MM-DD> <Sun|Mon|...> · <N> owes you a click ·
      <P> paused · fleet <OK|WARN|FAIL>` where `N` is the inbox
      row count (drafts + self-cancel + paused + budget_block +
      stale-PR rows, summed), `P` is the count of `ship_paused`
      projects currently active (per `fleet inbox`'s "paused
      projects" section), and the fleet band is `OK` when `N==0
      AND P==0`, `WARN` when `N>=1 AND P==0`, `FAIL` when `P>=1`.
      Test asserts the verdict line under all three fixture
      configurations.
- [ ] The composition path SHELLS THROUGH to the existing
      `digest()`, `inbox()`, `weekly()`, `atlas()` functions via
      internal calls (not subprocess re-invocations of
      `bin/fleet` — they share the same process so the
      `fleet_load_manifest` state is amortized). Per P-1 the
      `morning()` body is purely orchestration — no new readers,
      no duplicated math. Test asserts via `bash -x` trace that
      no `bin/fleet digest` / `bin/fleet inbox` subprocess is
      spawned (`grep -c "+ exec.*bin/fleet" trace.log` is 0).
- [ ] `--no-weekly` skips the WEEKLY block even on a Sunday.
      `--weekly` forces the WEEKLY block to print on a non-
      Sunday. Both branches tested under a frozen-clock fixture
      (the test pre-sets `FLEET_NOW_OVERRIDE` to a known
      `YYYY-MM-DD HH:MM` per the existing pattern in
      `tests/weekly.sh`).
- [ ] `--json` emits one JSON object combining the four
      sections:
      `{"date":"<iso>","verdict":"<OK|WARN|FAIL>","owes_click":N,
      "paused":P,"digest":[...],"inbox":{...},"weekly":{...|null},
      "atlas_top":[...|null]}`. Parsed via
      `node -e 'JSON.parse(...)'`. The `weekly` and `atlas_top`
      keys are JSON `null` on non-Sundays unless `--weekly` was
      passed. Per LESSONS 2026-06-03 (UTF-8 sign-extension trap)
      any string fields go through the `provenance_json_escape`
      UTF-8-safe pattern, NOT bare `doctor_json_escape`. Per
      LESSONS 2026-06-01 (awk -v multiline trap), multi-line
      digest lines accumulate to a tmp file and read back via
      `getline line < file`.
- [ ] `--slug NAME` narrows the digest and inbox sections to a
      single project (matches the existing `--slug` filter on
      `fleet weekly`). Test asserts the single-slug branch
      produces a digest with one row and an inbox scoped to that
      slug.
- [ ] The NEXT footer hint follows this priority ordering, first
      match wins: paused project → `fleet resume <slug>` (per
      ticket 0030); draft to promote → `fleet lessons-promote`
      (per 0028); SELF_CANCEL expiring → `bump SELF_CANCEL in
      <slug>/agents.config.sh`; budget_block today → `inspect
      <slug>'s spend or raise MAX_DAILY_USD`; stale agent PR
      >24h → `gh pr view <N> --comment` (escalate); else →
      `nothing else owes you a click. enjoy your day.`. Test
      asserts each priority branch via a separate fixture.
- [ ] Empty fleet (no discovered projects): `morning: no
      projects found under FLEET_DISCOVERY_ROOT — run
      install.sh on at least one repo first.` to stderr, exit
      0 (this is not an error, same posture as
      `replay --batch`'s empty-window message from ticket
      0034). Verdict line is NOT printed.
- [ ] Help: `bin/fleet morning --help` prints a USAGE block
      mentioning `--no-weekly`, `--weekly`, `--json`,
      `--slug`. Test asserts via `grep -qF -- "$kw"
      "$help_out"` per LESSONS 2026-05-30. Help block ends
      with `exit 0` per LESSONS 2026-06-01 (dispatcher
      fall-through trap).
- [ ] The dispatcher block (`if [ "$CMD" = "morning" ]; then
      morning "$@"; fi`) and the `morning()` function each end
      with explicit `exit N` on every code path per LESSONS
      2026-06-01. The `morning()` body MUST NOT reference any
      function defined LATER in `bin/fleet` than the
      dispatcher block — per LESSONS 2026-06-05 (dispatcher
      forward-reference trap), `morning` calls `digest`,
      `inbox`, `weekly`, `atlas` only after confirming those
      functions are defined ABOVE the `if [ "$CMD" =
      "morning" ]` dispatcher line.
- [ ] `tests/morning.sh` covers all 10 boxes using
      `$HOME/.local/bin` stubs (per LESSONS 2026-05-26) for
      `gh`, `claude`, `git`. The clock is frozen via
      `FLEET_NOW_OVERRIDE` (same fixture as
      `tests/weekly.sh`). Per LESSONS 2026-05-27, the test
      uses `cp` for fixture backup/restore. Per LESSONS
      2026-06-01 (`grep -c file || echo 0` double-print
      trap), every count in the verdict comes from
      `awk … END { print n+0 }`. Run-time budget: <15s
      (more than usual because the composed command touches
      four readers).

## Out of scope

The dev agent will NOT do these even if they seem related.

- A `--watch` mode that re-renders the briefing every N seconds.
  `fleet morning` is intentionally a one-shot read; a live
  dashboard is `fleet tail` (ticket 0015) and fleet-control's
  job, not this command's. Adding `--watch` reintroduces the
  problem this ticket solves (which command to leave running).
- An interactive prompt to action the NEXT hint (e.g. "Promote
  the draft now? [y/n]"). Standard shell composition (`fleet
  morning && fleet lessons-promote`) already covers this;
  interactive prompts break headless cron usage that operators
  rely on per the `fleet digest` growth lens (ticket 0012).
- A launchd schedule that emails the briefing daily. The
  growth path is the operator wiring `crontab` themselves
  (same pattern as `fleet digest` from ticket 0012); a
  built-in launchd entry is a separate ticket once enough
  operators ask.
- Reading from fleet-control's portal database for any field.
  Per P-6 (telemetry is the source of truth), every field
  comes from `events.jsonl` and `runs.jsonl` directly — the
  portal is a CONSUMER of the same channel, not an upstream.
- A `--since N` flag on `morning` itself. The four
  sub-commands already have their own windowing
  (`digest`=24h, `weekly`=7d, `atlas`=30d default); making
  `morning` take a unified `--since` would force one of those
  to lie. Each section keeps its native window.
- Coalescing the digest output into a single multi-project
  table (vs the existing per-project line). That is `fleet
  overview`'s job (ticket 0019); `morning` is the daily
  briefing, `overview` is the executive snapshot. Both
  ship; both stay distinct.

## Engineering notes

Files / patterns the dev should touch. Specific enough that the dev
doesn't have to re-discover the architecture.

- `bin/fleet` — new `morning()` dispatcher function placed
  BELOW the `digest()`, `inbox()`, `weekly()`, `atlas()`
  definitions (locate via `grep -n '^digest()\|^inbox()\|
  ^weekly()\|^atlas()' bin/fleet`) AND ABOVE the existing
  `if [ "$CMD" = "morning" ]` dispatcher block placement.
  Per LESSONS 2026-06-05 (dispatcher forward-reference
  trap), the function order in the file matters because the
  inline dispatcher pattern parses top-down at execution
  time. Confirm via `grep -n` that each of the four
  delegated functions is defined ABOVE the new dispatcher
  line.
- `bin/fleet` — `morning()` body composes by calling the
  four reader functions in process (NOT by spawning
  `bin/fleet digest` subprocesses) and assembling the
  verdict line from a small in-memory tally
  (`morning_count_owes_click`, `morning_count_paused`).
  Per P-1 the body is ~120 lines of orchestration; no
  new event types, no new manifest fields.
- `bin/fleet` — `morning_render_text()` and
  `morning_render_json()` output helpers. The JSON helper
  uses `provenance_json_escape` (defined later in
  `bin/fleet`) — per LESSONS 2026-06-05 (dispatcher
  forward-reference trap), either move `morning()` BELOW
  `provenance_json_escape` OR inline a local
  `morning_json_escape` copy bit-for-bit identical to the
  later helper (the same shape ticket 0034's
  `replay_batch_json_escape` resolved). Pick the inline
  copy: it keeps the dispatcher order simple and avoids
  reshuffling the file.
- `bin/fleet` — `morning_clock_now` reads
  `FLEET_NOW_OVERRIDE` if set (test seam, same pattern as
  `weekly_clock_now` from ticket 0025), else
  `date -u '+%Y-%m-%d %H:%M'`. The day-of-week is derived
  from `date -j -f '%Y-%m-%d' "$date" '+%a'` on macOS
  (BSD date) — the same incantation `weekly` uses.
- `bin/fleet` — help banner block at the top of the file
  (around line ~14) gets a new line: `fleet morning
  one-command daily briefing (digest + inbox [+ Sunday
  weekly])`. README "Daily ops" code block gets the same
  line.
- `lib/common.sh` — NO changes. `morning` is a pure
  composition of existing readers; no new helpers, no
  `fleet_*` signature changes, no new event types.
- `lib/install.sh` — NO changes.
- `prompts/` — NO changes. No `Reinstall: all projects`
  line needed because `lib/` and `prompts/` are
  untouched.
- `AGENTS.md` — NO new telemetry bullet (no new event
  types). One README sentence under "Daily ops" pointing
  at `fleet morning` as the recommended starting command.
- `tests/fixtures/morning/` — NEW directory under
  `tests/fixtures/` holding three synthetic project
  fixtures (`events.jsonl` + `runs.jsonl` + manifest
  values), plus a frozen-clock value, plus a golden
  text file and a golden JSON file. The fixtures
  pre-stage one DRAFT in agent-fleet's LESSONS, a
  budget_block event in almanac, and no paused projects.
- `tests/morning.sh` — top of file mirrors
  `tests/weekly.sh`: stub the discovered-projects
  iteration via `FLEET_DISCOVERY_ROOT="$TMP/projects"`,
  freeze the clock via `FLEET_NOW_OVERRIDE`, stub `gh`
  (no network calls needed because all data comes from
  fixture files). Per LESSONS 2026-05-26 stubs go in
  `$HOME/.local/bin`. Per LESSONS 2026-05-27 use `cp`
  for fixture backup/restore. Run-time budget: <15s.
- New deps: none. Pure shell + awk + existing
  `digest_parse_since`, `weekly_clock_now`,
  `provenance_json_escape` (inlined locally per the
  forward-reference workaround above).
- Public API: additive — `bin/fleet morning` is a new
  subcommand. NO new event types. NO `fleet_*`
  signature changes. NO new manifest fields.
- BREAKING flag: NO. PR body affirms "no change to the
  five public `fleet_*` signatures," "no new event
  types added," and "composition only — `digest`,
  `inbox`, `weekly`, `atlas` outputs are byte-identical
  to their standalone invocations (regression-tested
  via the existing `tests/digest.sh`, `tests/inbox.sh`,
  `tests/weekly.sh`, `tests/atlas.sh`)."
- Reinstall required: NO. `lib/` and `prompts/` are
  untouched.
- LESSONS to defend against: 2026-05-26 (`tail` shadow
  — `morning` is namespaced, no collision). LESSONS
  2026-05-26 (PATH reset — stubs go in
  `$HOME/.local/bin`). LESSONS 2026-05-27 (`$(cat)`
  trap — fixture reads use `cp`). LESSONS 2026-05-28
  (printf leading-dash trap — every slug / hint /
  date goes through `printf -- '%s'`). LESSONS
  2026-05-30 (`grep -F --` flag trap — help text and
  verdict-section greps use `grep -qF --`). LESSONS
  2026-06-01 (awk -v multiline trap — composed
  digest lines accumulate to a tmp file). LESSONS
  2026-06-01 (`grep -c file || echo 0` double-print
  trap — every count uses `awk … END { print n+0 }`).
  LESSONS 2026-06-01 (dispatcher fall-through trap
  — `morning()` ends with explicit `exit N`).
  LESSONS 2026-06-03 (UTF-8 sign-extension trap —
  the JSON renderer uses the inlined
  `morning_json_escape` copy of
  `provenance_json_escape`, not bare
  `doctor_json_escape`). LESSONS 2026-06-05
  (dispatcher forward-reference trap —
  `morning()` either sits below all four
  delegated readers, or inlines any later
  helper it needs).
- This ticket compounds 0012 (`fleet digest`),
  0019 (`fleet overview` — different question,
  same channel), 0025 (`fleet weekly`), 0026
  (`fleet inbox`), 0031 (`fleet atlas`). Per
  P-1 the diff is small: ~150 lines of `morning*`
  helpers + ~250 lines of test + one README
  line + one help-text line. Net new SLOC ~400.

## Implementation log

(Appended by the implementation-dev agent during execution.)

- 2026-06-07 — branch `feat/0036-fleet-morning-one-command-briefing` opened
- 2026-06-07 — `tests/morning.sh` added covering all 10 AC boxes; failing
  baseline confirmed (no `morning` subcommand falls through to `fleet
  status`).
- 2026-06-07 — `morning()` + helpers (`morning_clock_now`, `morning_dow`,
  `morning_json_escape`, `morning_count_owes_click`,
  `morning_count_paused`, `morning_any_projects`, `morning_next_hint`,
  `morning_atlas_top3`, `morning_render_text`, `morning_render_json`)
  added in `bin/fleet` BELOW the four delegated readers per LESSONS
  2026-06-05 (forward-reference trap). Dispatcher block uses explicit
  `exit $?` per LESSONS 2026-06-01. `morning_json_escape` is a
  bit-for-bit copy of `provenance_json_escape` with the `code -ge 0`
  UTF-8 guard from LESSONS 2026-06-03 — same shape ticket 0034 used.
- 2026-06-07 — golden text fixture at
  `tests/fixtures/morning/morning.text.golden.txt`. The composition
  strips inbox's own banner + trailing line (which depends on
  wall-clock state-file mtime) so the golden stays byte-stable across
  CI runs regardless of when the test fires.
- 2026-06-07 — PR #74 opened and squash-merged green
  (commit `ed1db64`). Ticket shipped.
