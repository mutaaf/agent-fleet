---
id: 0055
title: fleet pulse prints a one-line daily heartbeat suitable for a shell prompt or terminal banner
status: shipped
priority: P1
area: observability
created: 2026-06-17
owner: gtm-innovation
---

## User story

As a fleet operator who is three weeks into running `agent-fleet` across
4 slugs, who LOVES `fleet morning` (0036) on Mondays but doesn't want to
re-read the full briefing on Wednesday at 2pm — who has already noticed
they keep "forgetting the fleet exists" between Monday briefings and only
remembering when a launchd run goes red on Thursday — I want `bin/fleet
pulse` to emit ONE radically compressed line per slug (or one line for
the whole fleet) that I can stick into my zsh prompt
(`PROMPT='%n@%m %1~ $(fleet pulse --prompt-line) %# '`) or into a
launchd-fired Terminal banner that pops in iTerm every morning, so the
fleet's state is PASSIVELY visible in my shell without me having to type
a single subcommand. Where `fleet morning` is the full briefing, `fleet
inbox` (0026) is the TODO list, and `fleet overview` (0019) is the
table, `fleet pulse` is the GLANCE — three to five characters per slug,
no headings, no preamble, designed to be ignored 95% of the time and
caught the 5% of moments when a streak breaks or an inbox grows.

## Why now (four lenses)

### Product Owner
The kit's reader surfaces all assume the operator has at least one
intent ("brief me", "list what I owe the loop", "show me the
leaderboard"). They are all pulled by an explicit invocation. None of
them are pushed into the operator's awareness. The gap shows up at day
14-21 of a new install: the operator stops running `fleet morning`
every day because nothing has CHANGED today vs yesterday, and from then
on the fleet is invisible to them until a launchd run goes red or a
budget cap fires. The smallest meaningful unit of value is a one-line
heartbeat that sits in the shell prompt and shouts at the operator with
ONE character (a downward arrow, a number, a status sigil) the moment
anything moves. Subtraction: the operator stops having to remember to
check.

The default render is a single prompt-friendly line, 60-80 characters,
with one micro-cell per slug. The line is designed to be readable in
the corner of an iTerm window without context:

```
$ fleet pulse --prompt-line
courtiq 11d↑ sidebrew 0PR/wk↓ levelup-kids inbox=2 hedgehog ⏸
```

Each cell is `<slug> <signal>`. The signals (one per slug) are:
the live streak length with a trend arrow (↑ growing, → flat, ↓
broke); OR a PR-velocity dip (`0PR/wk↓` when the trailing-7-day
merged-PR count is zero AND last week's was non-zero); OR an inbox
debt count when 0026's `fleet inbox` reports ≥1 open item; OR a
pause sigil (`⏸`) when the slug is ship-paused per 0006. The
priority is: pause > inbox debt > streak break > PR-velocity dip
> streak length. The operator sees only the highest-priority
signal per slug, so the line stays short.

Default mode (without `--prompt-line`) is the three-to-five line
terminal-banner shape, for the launchd-fired iTerm pop:

```
$ fleet pulse
pulse — 4 slugs, Wed Jun 17 09:14
  courtiq      11d streak, growing (↑)         green
  sidebrew     0 PRs in last 7d (last wk: 3)   drifting
  levelup-kids inbox=2 (oldest item: 4d ago)   needs you
  hedgehog     paused — fleet resume to thaw   blocked
```

Per P-5 (operator confidence over feature richness), the win is the
absent guesswork about whether anything moved in the fleet today —
the line answers it without the operator typing a subcommand.

### Stakeholder
This is **moat-deepening on the retention axis** — the kit's first
surface designed to be CONSUMED PASSIVELY rather than pulled. Per
P-6 (telemetry is the source of truth), `pulse` is a PURE READER
over each slug's `events.jsonl`, plus the morning state file
(`$HOME/.local/state/agent-fleet/morning-last-run` from 0036) and
the inbox state file (0026's `inbox-last-snapshot.jsonl`). No new
event types. No writes. No `lib/common.sh` changes. The diff is the
signal-precedence walker + the two render modes. ~280 lines.

The pulse cell shape IS a small moat: it codifies "what the
operator needs to see in 3 characters" and becomes the shape every
future passive surface (a tmux status bar, a macOS menu bar item,
a fleet-control browser tab title) inherits. Once the precedence
order is stable, third-party integrations have one thing to call
(`fleet pulse --prompt-line`) and one shape to render. The kit
stops being only-pulled.

Per LESSONS 2026-06-15 (per-slug streak shellout is O(N) per day)
the inline streak math walks days in pure awk — `pulse` MUST NOT
shell out to `fleet streak` per slug because the prompt-line
shape is invoked on every shell prompt redraw, and even 200ms is
too slow for that hot path. The streak predicate is inlined as a
~30-line awk pass per slug, same shape `fleet maturity` (0054)
ships in step 6.

Compounds 0036 (`fleet morning` — reuses the morning state file
for the "drifting" signal), 0026 (`fleet inbox` — reads the
inbox debt count), 0042 (`fleet streak` — inlines the streak
predicate per the LESSONS 2026-06-15 warning), 0006 (`ship_paused`
— the pause sigil's source signal), 0019 (`fleet overview` —
reuses `overview_discover_slugs`), 0044 (`fleet pr-footer` —
reads `pr_footer_posted` events as the merged-PR count).

### User (operator with three iTerm tabs open, glancing at the prompt)
The operator has three iTerm tabs open at 2pm Wednesday — one in
the courtiq repo, one in the sidebrew repo, one a scratch shell —
and their PROMPT prints `fleet pulse --prompt-line` on every
redraw (cached for 90 seconds via a tiny state file so the shell
isn't shelling out every keypress). They glance up between
keystrokes and see `sidebrew 0PR/wk↓` flicker in the corner. They
think "huh, sidebrew hasn't shipped this week" and pull `fleet
morning sidebrew` to see why. The PR queue surfaces a stuck PR
they had forgotten. They review it, merge it, and tomorrow's
pulse shows `sidebrew 1PR/wk` again. Per P-5, the win is the
fleet earning back the operator's attention WITHOUT requiring
them to remember to check.

Sub-scenario: a launchd job fires every weekday at 8:55am running
`fleet pulse | osascript -e 'tell application "iTerm" to ...'`
to drop the multi-line banner shape into a new iTerm tab. The
operator sees the banner on first glance, decides nothing needs
their attention, closes the tab. The banner is consumed without
the operator typing anything. This is the cheapest possible
"fleet exists" reminder.

### Growth
This is the surface that makes the kit's MOMENT-N daily
re-engagement measurable. Most kits ship onboarding (we have
0011, 0023, 0050) and ROI dashboards (0019, 0025, 0027) but
NOTHING that lives in the operator's shell prompt 1000 times a
day. A friend evaluating the kit who pastes `fleet pulse
--prompt-line` into their `.zshrc` becomes someone whose shell
nudges them to keep using the kit; their retention curve bends.
Per the brief's "the kit must self-pause when it's broken, not
keep burning tokens against red CI" — pulse is the inverse:
the kit must self-announce when something moved, not wait for
the operator to remember.

Differentiated from `fleet morning` (0036): morning is the
intentional pull — operator types `fleet morning`, sits with
the briefing. Pulse is the passive ambient signal — no intent,
no time budget, just one line. Differentiated from `fleet
inbox` (0026): inbox lists items the operator owes the loop
explicitly. Pulse summarizes inbox debt with one number per
slug. Differentiated from `fleet overview` (0019): overview is
a table the operator pulls when they want the full posture.
Pulse is the always-on subset.

## Acceptance criteria

Each box maps 1:1 to a test scenario in `tests/pulse.sh`.

- [ ] `bin/fleet pulse` is a new subcommand. With no flags and at
      least one discovered slug, prints the multi-line banner shape
      per the Product-Owner example (one header line plus one
      slug-row each). With zero discovered slugs, prints `pulse:
      no slugs discovered. run \`fleet onboard <repo>\` to add the
      first project.` exit 0. Per LESSONS 2026-06-01 (dispatcher
      fall-through) every code path ends with `exit 0`. Test
      asserts both branches via fixtures.
- [ ] `bin/fleet pulse --prompt-line` prints ONE single line —
      no trailing newline if attached to a TTY, trailing newline
      if piped — with one cell per slug `<slug> <signal>`,
      separated by two spaces. The line is ≤120 characters when
      4 slugs are in fixtures; longer fleets truncate at the
      120-char boundary with `…` appended. Per LESSONS 2026-05-28
      every printf of a slug name goes through `printf -- '%s'`.
      Test asserts both the trailing-newline branch and the
      truncation branch.
- [ ] The per-slug signal precedence is: `paused` (slug has an
      unresolved `ship_paused` event with no later `ship_resumed`
      event per 0006/0030) > `inbox_debt` (the slug's inbox
      state file shows ≥1 open item per 0026) > `streak_break`
      (the slug had a streak ≥3d that ended within the last 24h
      per 0042) > `pr_velocity_dip` (the trailing-7-day merged-PR
      count is zero AND the prior-7-day count was ≥1 per 0044)
      > `streak_growing` (the live streak is ≥3d) > `flat` (none
      of the above). Exactly one signal renders per slug. Test
      asserts via six fixtures, each forcing a different
      precedence branch.
- [ ] The signal renders are: `⏸` for paused; `inbox=N` for
      inbox debt; `Nd streak↓` for streak break (where N is the
      LENGTH of the broken streak); `0PR/wk↓` for PR-velocity
      dip; `Nd↑` for streak growing; `·` for flat. Per LESSONS
      2026-05-28 the printf goes through `printf -- '%s'`. Test
      asserts each render shape.
- [ ] The live-streak predicate is INLINED as a single awk pass
      per slug — `bin/fleet pulse` MUST NOT shell out to `fleet
      streak <slug> --json` per LESSONS 2026-06-15 (per-day
      `date -j -v +1d` shellout is O(window × N_slugs)). Test
      asserts via `strace -f`-style stub: a `$HOME/.local/bin/
      date` stub increments a counter on every invocation; the
      test asserts the counter is < 20 across a 5-slug fixture
      run (i.e. NOT 5 × 90 = 450 calls).
- [ ] The merged-PR count is read from each slug's events.jsonl
      via one awk pass per slug counting `pr_footer_posted`
      events in the trailing 7 days and the prior 7 days. Per
      LESSONS 2026-06-08 (`awk arr[count] = v; count++` with no
      `BEGIN { count = 0 }` stores under empty-string key) the
      awk pass declares `BEGIN { current = 0; prior = 0 }`.
      Per LESSONS 2026-06-08 IFS=$'\t' middle-empty-field uses
      `-` sentinel when the timestamp field is empty (a
      corrupted event row). Test asserts via fixture.
- [ ] `bin/fleet pulse --slug <name>` restricts the render to
      one slug. Unknown slug: prints `pulse: slug <name> not
      found. discovered slugs: <list>` to stderr, exit 2 per
      LESSONS 2026-06-01. Missing `--slug` arg value: prints
      `pulse: --slug requires a value` to stderr, exit 2. Test
      asserts both refusals via `grep -qF -- "$kw"` per LESSONS
      2026-05-30 (`grep -F --` trap).
- [ ] `bin/fleet pulse --json` emits one structured JSON
      array, one element per slug: `[{"slug": "<name>",
      "signal": "<paused|inbox_debt|streak_break|pr_velocity_dip|
      streak_growing|flat>", "render": "<the cell text>",
      "detail": {...}}, …]`. JSON escape via
      `preflight_json_escape` per LESSONS 2026-06-03 called
      directly per LESSONS 2026-06-13 (no `*_json_escape`
      wrapper). Test asserts JSON validity via `node -e
      'JSON.parse(require("fs").readFileSync(0, "utf8"))'`.
- [ ] `bin/fleet pulse --prompt-line` is RESILIENT to a flaky
      slug — if one slug's `events.jsonl` is corrupted, missing,
      or unreadable, that slug's cell renders as `<slug> ?` and
      the rest of the line still prints. The exit code is still 0.
      Test asserts via fixture with one corrupted events.jsonl
      and three healthy ones.
- [ ] `bin/fleet pulse --prompt-line` caches its output to
      `$HOME/.cache/agent-fleet/pulse-prompt-line` with a 90-second
      TTL, so a shell-prompt redraw on every keypress does NOT
      re-walk every slug's events.jsonl. Stale cache (mtime > 90s
      ago) triggers a re-walk; fresh cache prints from the file.
      Per LESSONS 2026-06-11 (BSD `date -j -f` fills missing time
      fields with NOW-of-day) the cache age math computes via
      `date +%s` minus `stat -f %m` on the cache file (epoch
      seconds, no `date -j -f` involved). Test asserts via fixture
      that two consecutive invocations within 5s read the cache
      file (no events.jsonl re-read) and that an invocation 91s
      later (clock frozen via `FLEET_NOW_OVERRIDE`) re-walks.
- [ ] `bin/fleet pulse --no-cache` bypasses the cache and forces
      a re-walk. Useful for the launchd-fired banner job where a
      fresh read is always wanted. Test asserts via fixture that
      `--no-cache` re-walks even when the cache file is fresh.
- [ ] `bin/fleet pulse --help` prints USAGE mentioning
      `--prompt-line`, `--slug`, `--json`, `--no-cache`. Per
      LESSONS 2026-05-30 test asserts via `grep -qF -- "$kw"
      "$help_out"`. Help block ends with `exit 0` per LESSONS
      2026-06-01.
- [ ] `bin/fleet pulse` is a PURE READER. NO `events.jsonl`
      writes, NO `fleet_emit_event` calls, NO writes to any
      slug's `agents.config.sh` or any morning/inbox state file
      OTHER THAN the cache file at `$HOME/.cache/agent-fleet/
      pulse-prompt-line` (which is invalidatable, not source-of-
      truth telemetry). Test asserts every slug's `events.jsonl`
      byte size is unchanged before and after invocation.
- [ ] `lib/common.sh` — NO changes. `prompts/` — NO changes.
      No new event types. Test asserts via `git diff
      --name-only main...HEAD -- lib/common.sh prompts/`
      returns empty.
- [ ] `tests/pulse.sh` covers all 14 boxes above using
      `$HOME/.local/bin` stubs per LESSONS 2026-05-26 (PATH
      reset). Fixture `events.jsonl`, `agents.config.sh`,
      `morning-last-run`, and `inbox-last-snapshot.jsonl`
      files live under `tests/fixtures/pulse/`. Per LESSONS
      2026-05-27 backup/restore via `cp` (NOT `$(cat)`).
      Counts use `awk … END { print n+0 }` per LESSONS
      2026-06-01. Per LESSONS 2026-06-08 every awk script
      declares `BEGIN { count = 0 }`. Per LESSONS 2026-06-08
      IFS=$'\t' middle-empty-field uses `-` sentinel. Per
      LESSONS 2026-06-15 the streak-predicate awk walker uses
      pure awk day arithmetic — no `date -j -v +1d` shellout.
      The clock is frozen via `FLEET_NOW_OVERRIDE`. Run-time
      budget: <8s.

## Out of scope

The dev agent will NOT do these even if they seem related.

- A TMUX-status-bar render (`fleet pulse --tmux`) or a
  POWERLINE segment. v1 prints to stdout; the operator wires
  it into their own status bar. Renderer adapters are v2 if
  asked.
- A MACOS menu bar item (BitBar / SwiftBar plug). Same
  reason — shell-only kit, GUI surfaces are out of scope.
- A WATCH mode (`fleet pulse --watch`) that re-renders every N
  seconds. The operator wires it into their shell prompt OR
  into a launchd-fired one-shot banner. A foreground watch
  loop is the operator's job.
- AUTO-NOTIFYING via macOS `osascript display notification`
  when a signal escalates. Notifications are noisy; v1 is
  read-only. Notification channels are a v2 ticket.
- INTEGRATING pulse INTO the kit's shell prompt automatically
  (an `install.sh` step that edits `~/.zshrc`). Editing the
  operator's shell config silently violates the "idempotent
  install, never surprises the operator" principle in
  AGENTS.md. The README documents the snippet; the operator
  pastes it themselves.
- A FLEET-wide aggregate signal ("3 of 4 slugs are
  drifting"). v1 is one cell per slug. Aggregation is the
  caller's job.
- AUTO-PAUSING a slug whose signal has been `pr_velocity_dip`
  for 14+ days. That's 0006's job and would require pulse to
  write, breaking the pure-reader contract.
- A PERSISTENT pulse-history channel (one line per day
  written to `pulse-history.jsonl` so the operator can plot
  the trajectory). That's 0058 `fleet trends`'s job; pulse
  is point-in-time only.
- A launchd schedule wired by the kit. The operator wires
  the launchd job themselves; the README documents the
  plist snippet.

## Engineering notes

Files / patterns the dev should touch.

- `bin/fleet` — new `pulse()` dispatcher function placed
  next to the existing `morning()` block (find via `grep -n
  '^morning()' bin/fleet`). Per LESSONS 2026-05-26 (`tail`
  shadow) `pulse` does not collide with any coreutils
  binary.
- `bin/fleet` — eight helpers, ALL defined ABOVE the
  dispatcher block per LESSONS 2026-06-05 (forward-reference
  trap):
  - `pulse_discover_slugs` — wraps
    `overview_discover_slugs`, returns alphabetical order.
  - `pulse_evaluate_signal` — for one slug, walks the
    events.jsonl ONCE and returns the winning signal per
    AC #3's precedence. Per LESSONS 2026-06-08 the awk pass
    declares `BEGIN { count = 0; current = 0; prior = 0 }`.
    Per LESSONS 2026-06-08 IFS=$'\t' middle-empty-field uses
    `-` sentinel. Per LESSONS 2026-06-15 the streak day-walk
    is pure-awk Julian-day arithmetic, NOT a shellout to
    `date -j -v +1d`.
  - `pulse_check_paused` — reads the slug's events.jsonl for
    the latest `ship_paused` event AND any later
    `ship_resumed` event per 0006/0030.
  - `pulse_check_inbox_debt` — reads the slug's
    `inbox-last-snapshot.jsonl` (from 0026) and counts open
    items.
  - `pulse_check_pr_velocity` — counts `pr_footer_posted`
    events in the trailing 7d and prior 7d, returns dip
    boolean.
  - `pulse_render_prompt_line` — one-line render with two-
    space cell separator and 120-char truncation. Width via
    `preflight_visible_width` per LESSONS 2026-06-05. Per
    LESSONS 2026-05-28 the printf of each slug name goes
    through `printf -- '%s'`.
  - `pulse_render_banner` — three-to-five line render per
    the Product-Owner example.
  - `pulse_render_json` — JSON formatter. JSON escape via
    `preflight_json_escape` per LESSONS 2026-06-03 called
    directly per LESSONS 2026-06-13 (no `*_json_escape`
    wrapper).
  - `pulse_cache_read` / `pulse_cache_write` — the 90s TTL
    cache at `$HOME/.cache/agent-fleet/pulse-prompt-line`.
    The cache age math uses `date +%s` minus `stat -f %m`
    (no `date -j -f` involved per LESSONS 2026-06-11).
- `bin/fleet` — `pulse()` end-state must be `exit 0` / `exit
  2` on every code path per LESSONS 2026-06-01.
- `bin/fleet` — dispatcher block: `if [ "$CMD" = "pulse" ];
  then pulse "$@"; fi`. Place AFTER the `morning`
  dispatcher.
- `bin/fleet` — help banner block at the top of the file
  gets ONE new line: `fleet pulse one-line daily heartbeat
  for prompt or banner`. README "Daily ops" code block gets
  the same line, appended via the same single-edit pattern
  that avoided LESSONS 2026-05-25.
- `AGENTS.md` — NO content change.
- `lib/common.sh` — NO changes.
- `prompts/` — NO changes.
- `tests/fixtures/pulse/` — NEW directory holding five
  slug subdirs (`paused`, `inbox-debt`, `streak-break`,
  `pr-dip`, `growing`) each with `events.jsonl`,
  `agents.config.sh`, and where applicable
  `inbox-last-snapshot.jsonl`. A sixth `corrupted` slug
  has an unreadable events.jsonl for AC #9.
- `tests/pulse.sh` — top of file mirrors
  `tests/morning.sh` (closest prior reader; shares the
  state-file read pattern). Stubs live under
  `$HOME/.local/bin` per LESSONS 2026-05-26 (PATH reset).
  Counts use `awk … END { print n+0 }` per LESSONS
  2026-06-01. Per LESSONS 2026-05-27 backup/restore via
  `cp`. The clock is frozen via `FLEET_NOW_OVERRIDE`.
  Run-time budget: <8s.
- New deps: none. Pure shell + awk + Node (already a kit
  dep for JSON validation in the test).
- Public API: additive — `bin/fleet pulse` is a new
  subcommand. ZERO new event types, ZERO event writes
  to telemetry channels, ZERO `lib/common.sh` changes,
  ZERO `prompts/` changes. The pulse-prompt-line cache
  file at `$HOME/.cache/agent-fleet/` is an
  invalidatable cache, not telemetry.
- BREAKING flag: NO. PR body affirms "pure reader, no
  events.jsonl writes, no `fleet_*` signature changes,
  no runtime hot-path changes."
- Reinstall required: NO. `lib/` and `prompts/` are
  untouched.
- LESSONS to defend against: 2026-05-25 (README "Daily
  ops" code block addition), 2026-05-26 (`tail` shadow),
  2026-05-26 (PATH reset — stubs in `$HOME/.local/bin`),
  2026-05-27 (`$(cat)` trap — use `cp` for backup/restore
  in tests), 2026-05-28 (printf leading-dash — every
  slug-name printf goes through `printf -- '%s'`),
  2026-05-30 (`grep -F --` trap), 2026-06-01
  (`grep -c file || echo 0` double-print — counts use
  `awk … END { print n+0 }`), 2026-06-01 (dispatcher
  fall-through — every code path ends `exit 0/2`),
  2026-06-03 (UTF-8 sign-extension — JSON escape via
  `preflight_json_escape`), 2026-06-05 (dispatcher
  forward-reference — all `pulse_*` helpers defined
  ABOVE the dispatcher), 2026-06-05 (bash 3.2 LC_ALL
  caching — `LC_ALL=C awk` for any string-length
  operation), 2026-06-05 (export-in-subshell trap —
  any agents.config.sh read happens inside `( … )`),
  2026-06-08 (awk empty-string-key — `BEGIN { count
  = 0 }`), 2026-06-08 (IFS=$'\t' middle-empty-field
  — sentinel `-`), 2026-06-11 (BSD `date -j -f`
  fills missing time fields with NOW-of-day —
  cache-age math uses `date +%s` minus `stat -f
  %m`, no `date -j -f` involved), 2026-06-13 (no
  `*_json_escape` wrapper around
  `preflight_json_escape` — called directly),
  2026-06-15 (per-day `date -j -v +1d` shellout
  inside a per-slug loop is O(window × N_slugs) —
  the streak-predicate awk walker uses pure awk
  Julian-day arithmetic).
- This ticket compounds 0036 (`fleet morning` —
  reads the morning state file for the "drifting"
  signal), 0026 (`fleet inbox` — reads the
  inbox-last-snapshot state file), 0042 (`fleet
  streak` — inlines the streak predicate per the
  LESSONS 2026-06-15 warning rather than calling
  the binary), 0006 (`ship_paused` — pause sigil
  source), 0030 (`fleet resume` — the pause sigil
  nudge mentions it), 0019 (`fleet overview` —
  reuses `overview_discover_slugs`), 0044 (`fleet
  pr-footer` — reads `pr_footer_posted` events
  for the PR-velocity count), 0054 (`fleet
  maturity` — shares the inline-streak-predicate
  pattern). Per P-1 the diff is small: ~280 lines
  of `pulse_*` helpers + ~250 lines of test + 6
  fixture slug subdirs + one help-text line + one
  README line.

## Implementation log

- 2026-06-17 — implementation-dev: opened `feat/0055-fleet-pulse`. Flipped
  status to `in-progress`. Implementing `bin/fleet pulse` as a pure reader
  per AGENTS.md § Hard NOs (no lib/ or prompts/ edits, no new event types,
  no events.jsonl writes). Streak predicate inlined as a pure-awk Julian-
  day walker per LESSONS 2026-06-15 — no `fleet streak --json` shellout in
  the per-slug loop. Inbox-debt signal is the same drafts + self_cancel +
  budget composite the inbox subcommand renders (the ticket cites
  `inbox-last-snapshot.jsonl` aspirationally; the actual on-disk state
  file at `$HOME/.cache/fleet/inbox-state` is a single-epoch marker,
  so the cheapest hot-path inbox-debt check is to recompute the three
  cheap sections directly — `gh`-dependent stuck-PR section is
  intentionally skipped on the prompt-line hot path).
- 2026-06-17 — implementation-dev: PR #117 merged on green CI (shellcheck
  + validate). 14/14 ACs in tests/pulse.sh passed locally; no regression
  in tests/maturity.sh (16/16) or tests/streak.sh (13/13). Auto-merge
  squashed the implementation commit at 06:29:16Z (commit 17210cb)
  before the status-flip commit landed, so this follow-up PR carries
  the `shipped` index update. The kit-as-project `events.jsonl` got a
  `pr_opened number=117 branch=feat/0055-fleet-pulse` event per
  AGENTS.md § Telemetry.
