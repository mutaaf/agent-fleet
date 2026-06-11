---
id: 0046
title: fleet vacation suspends ship/eng work during operator PTO and prints a return briefing
status: shipped
priority: P2
area: governance
created: 2026-06-11
owner: gtm-innovation
---

## User story

As a fleet operator going on a 10-day vacation (or a long weekend, or
any window where I can't tend the loop), who today has THREE bad
options — (a) leave the fleet running and pray nothing breaks, (b)
manually `launchctl disable` every project's ship/eng job and forget
to re-enable some, (c) bump every project's `SELF_CANCEL` short and
then forget to extend it — I want `bin/fleet vacation --until
YYYY-MM-DD --reason "<one-line>"` to gracefully suspend ship/eng
work across the WHOLE fleet (review keeps polling so any in-flight
PR finishes), schedule an automatic resume on the return date, and
print a one-paragraph "what happens while you're away" briefing, so
that I leave for vacation in 30 seconds with full confidence that
the loop is bounded and self-recovering.

## Why now (four lenses)

### Product Owner
The kit's existing pause/resume surfaces are PER-PROJECT and
PER-INCIDENT:
- `ship_paused` (ticket 0006) fires automatically after 3
  send-back streak hits.
- `fleet resume <slug>` (ticket 0030) re-enables one paused
  project.
- `QUIET_HOURS` (ticket 0033) suppresses one project during a
  fixed daily window.

None of these answer "I am going AWAY for 10 days; suspend
everything tonight and resume on the 21st." The operator's
recovery today is to manually `launchctl disable
gui/$UID/<namespace>.agent-ship` on every slug, set a calendar
reminder for the return date, and re-enable each one by hand.
On a 5-project fleet that's 10 launchctl invocations before
vacation and 10 after — both of which are easy to forget,
especially the after.

The smallest meaningful unit of value is one command, one state
file, one auto-resume:

```
fleet vacation --until 2026-06-21 --reason "10-day trip, back Sat"

vacation: suspending 5 projects until 2026-06-21 (10 days from
          now).

  agent-fleet    ship + eng     disabled until 2026-06-21
  courtiq        ship           disabled until 2026-06-21
  digitalcraft   ship + eng     disabled until 2026-06-21
  almanac        ship           disabled until 2026-06-21
  fleet-control  ship + eng     disabled until 2026-06-21

  review keeps polling for all 5 (in-flight PRs will finish).

while you're away:
  • 3 open PRs will continue healing via the existing 2-attempt
    cap; escalation comments will accumulate on the PRs if
    they exceed the cap.
  • budget caps (MAX_DAILY_USD) remain in force per project.
  • SELF_CANCEL dates remain in force; agent-fleet expires
    2026-07-12 (21 days after your return — safe).
  • no new tickets will be picked up.
  • CROSS_LESSONS feed continues to fold any new draft
    promotions emitted during the trip.

return checklist (auto-resume runs 2026-06-21 00:00 UTC):
  fleet vacation --return   # cancels suspension early if needed
  fleet morning             # see what happened while away
```

Subtraction: the operator stops doing per-project launchctl
operations and stops worrying about whether they remembered to
re-enable. The vacation command IS the calendar reminder + the
launchctl operator + the return briefing in one.

Per P-5 (operator confidence over feature richness), the win is
converting "I'm dreading the vacation re-enable" into
"vacation is one command before and one auto-resume after."

### Stakeholder
This is **moat-deepening on the retention axis** — the kit's
first surface designed for the operator who has been running
the loop for MONTHS and now wants to take a real break
without dismantling it. Per the brief's "Operator handoff /
vacation mode. The kit assumes one human watching; what
happens during PTO?" — this is the direct answer.

Per P-6 (telemetry is the source of truth), the vacation
state is a SINGLE FILE under `$HOME/.cache/fleet/
vacation-state` (parallel to the inbox-state file from
ticket 0026): `{since: <ts>, until: <ts>, reason: <text>,
slugs_suspended: [<list>]}`. Every runner reads this file
at PHASE 0 (right after `fleet_self_cancel`) — if the file
exists AND `until` has not passed, ship/eng `exit 0`
immediately with a `vacation_skip` event. Review and groom
ignore the file (groom is harmless; review needs to keep
running for in-flight PRs).

The auto-resume mechanism uses launchd's `StartCalendarInterval`
on a dedicated `com.agent-fleet.vacation-resume` plist that
fires once at `until 00:00 UTC` and runs `bin/fleet vacation
--return`. On a successful return the state file is deleted
AND the plist is `launchctl bootout`-ed.

Per P-1 (smallest viable change), the diff is the state file
+ the PHASE 0 hook + the launchd resume plist + the briefing
composer. No per-slug launchctl disable/enable — the runner
self-suppresses based on the state file (cheaper, more
reliable, single source of truth).

Compounds 0006 (`ship_paused` — the suspension shape is the
same as the auto-pause, just operator-initiated and fleet-wide
instead of streak-triggered and per-project), 0030 (`fleet
resume` — the return path borrows the resume-confirmation
shape), 0033 (`QUIET_HOURS` — the PHASE 0 suppression hook
is the same place this code lives), 0036 (`fleet morning` —
the return briefing leverages morning's verdict composer).

Per P-3 (heal in-flight before new work), vacation
suppresses PHASE 2 (new ticket pickup) but NOT PHASE 1
(heal in-flight). In-flight PRs continue to heal during
vacation up to the 2-attempt cap; the operator returns to
either merged PRs or human-escalated comments, never to a
silently-burning loop.

### User (operator on a Friday evening packing for vacation)
Operator runs `fleet vacation --until 2026-06-21 --reason
"10-day trip"`. Sees the briefing. Reads the 5 lines of
"while you're away" + the return checklist. Closes
terminal. Goes to vacation knowing:

- Ship will NOT pick up new tickets.
- Eng will NOT pick up new tickets.
- Review WILL continue to grade any in-flight PRs.
- Budget caps remain in force.
- SELF_CANCEL remains in force.
- Auto-resume fires on 2026-06-21 00:00 UTC.

Vacation day: the operator's PR notifications quiet by ~24
hours after departure (last in-flight PR finishes). Inbox
is empty for 9 days. The operator's anxiety surface goes
from "is the loop OK?" to confident silence.

Return day: operator opens laptop on 2026-06-21. Runs
`fleet morning`. Sees a verdict line like "8 PRs healed +
merged while you were away; 1 PR escalated to human
(needs your attention)." Operator triages the one
escalated PR, runs nothing else, and the fleet is
self-resumed.

Per P-5, the win is converting vacation from a
fleet-paralyzing event into a graceful suspension +
auto-resume.

### Growth
A friend evaluating the kit who asks "what happens when
I go away for a week?" gets a one-sentence answer:
"`fleet vacation --until <date>` and the kit takes
care of it." Every competing autonomous-coding-agent
kit answers this question with either "we don't
support that" or "you have to manually disable
everything." The kit's answer is a built-in command
with auto-resume.

This is also the surface that converts power-user
operators (who already have a kit they like) into
agent-fleet users. The vacation command is a
RETENTION feature for current operators AND an
ACQUISITION feature for evaluator operators who have
been burned by a kit they couldn't safely leave.

Per the brief's "what specific pain does it cure that
justifies the work?" — the pain is operator burnout
from running a loop they can't safely pause. The cure
is a 30-second command before vacation and zero
cleanup after.

The acquisition path now has six moments:
`kickstart --demo` (see the loop), `preflight +
onboarding-check` (install it), `pr-footer`
(0044, trust artifact), `prompts-suggest` (0045,
self-improvement), and now `vacation` (retention).
Each one answers a different operator question at a
different point in the lifecycle.

## Acceptance criteria

Each box maps 1:1 to a test scenario in `tests/vacation.sh`.

- [ ] `bin/fleet vacation --until <YYYY-MM-DD> --reason
      "<one-line>"` is a new subcommand. Both flags are
      REQUIRED. Missing `--until`: print `vacation: usage:
      bin/fleet vacation --until YYYY-MM-DD --reason
      "<one-line>"` to stderr, exit 2 per LESSONS
      2026-06-01. Missing `--reason`: print `vacation:
      --reason is required (one-line ASCII) for the audit
      trail` to stderr, exit 2. Reason containing
      non-ASCII bytes: print `vacation: --reason must be
      ASCII for v1 (per LESSONS 2026-06-03
      sign-extension guard)` to stderr, exit 2. Test
      asserts all three refusals.
- [ ] On a successful invocation, the command writes
      `$HOME/.cache/fleet/vacation-state` as a single
      JSON line `{"since": "<iso>", "until": "<iso>",
      "reason": "<text>", "slugs_suspended":
      ["slug1", "slug2", ...]}`. JSON escape via
      `preflight_json_escape` per LESSONS 2026-06-03.
      The file is owned by the operator (mode 0644).
      Test asserts the file shape via Node JSON.parse.
- [ ] The command installs a one-shot launchd job
      `com.agent-fleet.vacation-resume` whose
      `StartCalendarInterval` fires once at
      `<until> 00:00 UTC` and runs
      `bin/fleet vacation --return`. The plist is
      idempotent: re-invoking `fleet vacation` with
      a different `--until` updates both the state
      file and the plist. Test asserts the plist's
      `StartCalendarInterval` matches the requested
      `until` date AND that a re-invocation
      replaces (not duplicates) the prior plist.
- [ ] `lib/ship.sh` and `lib/eng.sh` PHASE 0 (right
      after `fleet_self_cancel`) reads
      `$HOME/.cache/fleet/vacation-state`. If the
      file exists AND the current UTC time is
      between `since` and `until`, the runner emits
      one `vacation_skip {until, reason}` event and
      `exit 0`s immediately — no claude, no gh, no
      git, no heal-counter advance. Mirrors the
      `QUIET_HOURS` skip shape from ticket 0033. The
      one-event-per-process guard is
      `FLEET_VACATION_SKIP_EMITTED` (export shape
      matches ticket 0033's `FLEET_QUIET_HOURS_
      EMITTED`). Test asserts both runners
      suppress AND emit the event AND the
      multi-call dedup via fixtures.
- [ ] `lib/review.sh` and `lib/groom.sh` IGNORE
      the vacation state — review keeps polling
      (in-flight PRs need to finish), groom keeps
      grooming (backlog refresh is harmless during
      vacation). Test asserts both runners pass
      through unchanged when the state file exists.
- [ ] `bin/fleet vacation --return` ends the
      suspension early (or fires from the
      auto-resume plist). Deletes the state file,
      runs `launchctl bootout
      gui/$UID/com.agent-fleet.vacation-resume`
      to clean up the plist, and emits one
      `vacation_returned {since, duration_h,
      forced}` event per slug whose
      `slugs_suspended` list included it.
      `forced=1` when invoked manually before
      `until`; `forced=0` when invoked by the
      auto-resume plist. Test asserts the cleanup
      + the per-slug event emission.
- [ ] `bin/fleet vacation --status` prints the
      current vacation state if active (the
      original briefing block from the user
      story above with elapsed/remaining hours)
      OR `vacation: not active` if no state file.
      Exit 0 always. Test asserts both branches.
- [ ] `bin/fleet vacation --help` prints USAGE
      mentioning `--until`, `--reason`,
      `--return`, `--status`. Test asserts via
      `grep -qF -- "$kw" "$help_out"` per
      LESSONS 2026-05-30. Help block ends with
      `exit 0`.
- [ ] The state file path `$HOME/.cache/fleet/
      vacation-state` follows the same shape as
      the `inbox-state` file from ticket 0026.
      The directory `$HOME/.cache/fleet/` is
      created with `mkdir -p` if absent. Test
      asserts via fixture HOME path.
- [ ] An `until` date in the past prints
      `vacation: --until <date> is in the past
      (today is <today> UTC); use a future
      date.` to stderr, exit 2. An `until` date
      more than 90 days in the future prints
      a WARNING but proceeds (extended vacations
      are valid): `vacation: warning — <date>
      is <N>d away; this is unusually long. If
      this is a true long absence consider
      bumping SELF_CANCEL on each project
      manually instead. Continuing.` to stderr,
      exit 0. Test asserts both branches.
- [ ] The `vacation_skip` and `vacation_returned`
      event types are documented in `AGENTS.md
      § Telemetry` following the existing pattern
      (one paragraph per type per the LESSONS
      2026-06-08 contract for new event types).
      `phase=vacation` on both. Test asserts
      via `grep -qF -- "vacation_skip"
      AGENTS.md`.
- [ ] `lib/common.sh` MAY gain a new internal
      helper `_fleet_check_vacation` (underscore-
      prefixed, private). Mirrors
      `fleet_check_quiet_hours` from ticket 0033
      in shape. NO changes to the public
      `fleet_*` API. Test asserts via `git diff
      main…HEAD -- lib/common.sh` shows only
      additions whose function names start with
      `_`.
- [ ] `tests/vacation.sh` covers all 12 boxes
      above using `$HOME/.local/bin` stubs per
      LESSONS 2026-05-26. `launchctl` is
      stubbed; the plist install is asserted
      via the stub's invocation log. Per
      LESSONS 2026-05-27 backup/restore via
      `cp`. The clock is frozen via
      `FLEET_NOW_OVERRIDE`. Per LESSONS
      2026-06-05 (export-in-subshell trap),
      the `_fleet_check_vacation` helper is
      called WITHOUT `$(...)` from production
      runners so the
      `FLEET_VACATION_SKIP_EMITTED` guard
      persists. Run-time budget: <10s.

## Out of scope

The dev agent will NOT do these even if they seem related.

- A per-project vacation (suspend only some slugs).
  v1 is fleet-wide; per-project pause is already
  available via `ship_paused` + `fleet resume`.
- A vacation MODE that LOWERS budget caps during the
  trip ("$1/day cap instead of $5/day"). v1 is
  binary suspend; budget-modulation is a follow-up.
- A vacation NOTIFICATION (email / Slack / push)
  when the auto-resume fires. v1 is silent —
  `fleet morning` on return surfaces what
  happened. v2 may add a notification hook.
- A "soft vacation" where ship still runs but only
  works on tickets marked `area=safety` or
  `priority=P0`. v1 is hard suspend.
- A multi-operator handoff (mark a second human as
  the on-call during vacation). v1 is single-
  operator; multi-operator handoff is a separate
  ticket.
- Backfilling per-project SELF_CANCEL adjustments
  during the trip. v1 leaves SELF_CANCEL alone;
  if the operator's vacation crosses a
  SELF_CANCEL date they're expected to bump it
  before leaving (and the briefing surfaces
  this).
- A vacation HISTORY log (the last N vacations
  with their durations). v1 is one active
  vacation at a time; history is the event
  channel.
- A vacation MODE for the kit's CI gates (e.g.
  weaker rules during vacation). v1 leaves
  CI gates untouched — they're the load-bearing
  safety net.
- A launchd-Schedule-based vacation (rather than
  a state file) that re-disables ship/eng on a
  cron. v1 uses the state file + PHASE 0 read
  pattern because it's idempotent across
  manifest re-installs.

## Engineering notes

Files / patterns the dev should touch. Specific enough that the dev
doesn't have to re-discover the architecture.

- `bin/fleet` — new `vacation()` dispatcher function
  placed next to the existing `resume()` block
  (find via `grep -n '^resume()' bin/fleet`,
  currently ~line 13953). Per LESSONS 2026-05-26
  (`tail` shadow) `vacation` does not collide with
  any coreutils binary.
- `bin/fleet` — six helpers, ALL defined ABOVE the
  dispatcher block per LESSONS 2026-06-05
  (forward-reference trap):
  - `vacation_discover_slugs` — reuses the existing
    `overview_discover_slugs` helper.
  - `vacation_write_state` — composes and writes
    the `vacation-state` JSON file. Per LESSONS
    2026-06-03 JSON escape via
    `preflight_json_escape`. Per LESSONS
    2026-05-27 the file write goes through `cp`
    of a tmp file (NOT `> file`) so a mid-write
    interruption never leaves a half-written
    state.
  - `vacation_install_resume_plist` — generates
    a launchd plist with
    `StartCalendarInterval` for the `until`
    date and `bootstrap`s it via `launchctl
    bootstrap gui/$UID
    ~/Library/LaunchAgents/<plist>`. Idempotent
    (bootout first, then bootstrap). Mirrors
    the install.sh launchd pattern.
  - `vacation_remove_resume_plist` — `bootout`s
    and removes the plist. Idempotent (silent
    on already-absent).
  - `vacation_compose_briefing` — assembles the
    user-story-style text block from the state
    file + per-slug manifest data. Width via
    `preflight_visible_width` per LESSONS
    2026-06-05.
  - `vacation_emit_returned_per_slug` — emits
    one `vacation_returned` event per slug
    whose `slugs_suspended` list included it
    on `--return`.
- `bin/fleet` — `vacation()` end-state must be
  `exit 0` / `exit 2` on every code path per
  LESSONS 2026-06-01.
- `bin/fleet` — dispatcher block: `if
  [ "$CMD" = "vacation" ]; then vacation "$@";
  fi`. Place AFTER the `resume` dispatcher
  (~line 13953).
- `bin/fleet` — help banner block at the top
  of the file (around line ~14) gets a new
  line: `fleet vacation --until D suspend
  ship/eng across the fleet; auto-resume on
  D`. README "Daily ops" code block gets the
  same line.
- `lib/common.sh` — new internal helper
  `_fleet_check_vacation` mirroring
  `fleet_check_quiet_hours` (ticket 0033).
  Reads `$HOME/.cache/fleet/vacation-state`,
  sets `FLEET_VACATION_VERDICT` to one of
  `skip` / `pass`, exports
  `FLEET_VACATION_SKIP_EMITTED=1` after the
  first emit. Per LESSONS 2026-06-05
  (export-in-subshell trap), the helper is
  called WITHOUT `$(...)` from production
  runners.
- `lib/ship.sh` and `lib/eng.sh` — PHASE 0
  hook right after `fleet_self_cancel`. Mirror
  the existing `fleet_check_quiet_hours` call
  pattern. NO call from `lib/review.sh` or
  `lib/groom.sh` (vacation does not suspend
  these).
- `AGENTS.md § Telemetry` — append two new
  bullets documenting `vacation_skip` and
  `vacation_returned` following the existing
  per-event paragraph pattern (one block each
  with the field schema and the rationale).
- `prompts/` — NO changes.
- `tests/fixtures/vacation/` — NEW directory
  holding `vacation-state` fixture JSON files,
  `events.jsonl` fixtures for the post-resume
  assertions, and stub manifest files for the
  multi-slug discovery.
- `tests/vacation.sh` — top of file mirrors
  `tests/quiet-hours.sh` (the closest prior
  ticket). Stubs `launchctl` and `gh` under
  `$HOME/.local/bin` per LESSONS 2026-05-26.
  Counts use `awk … END { print n+0 }` per
  LESSONS 2026-06-01. Per LESSONS 2026-05-27
  backup/restore via `cp`. The clock is
  frozen via `FLEET_NOW_OVERRIDE`. Per
  LESSONS 2026-06-05 the
  `_fleet_check_vacation` helper is called
  without `$(...)` so the dedup guard
  persists. Run-time budget: <10s.
- New deps: none. Pure shell + awk +
  `launchctl` + existing helpers.
- Public API: additive — `bin/fleet
  vacation` is a new subcommand AND
  `lib/ship.sh` / `lib/eng.sh` gain a PHASE 0
  hook AND `lib/common.sh` gains a private
  `_fleet_check_vacation` helper. TWO new
  event types
  (`vacation_skip`, `vacation_returned`).
- BREAKING flag: NO. The new event types are
  additive per the AGENTS.md "consumers MUST
  tolerate unknown types gracefully" contract.
  The PHASE 0 hook is no-op when the state
  file is absent (the default case for every
  existing install).
- Reinstall required: YES — `lib/ship.sh`,
  `lib/eng.sh`, `lib/common.sh`, `AGENTS.md`
  all change. PR body affirms `Reinstall:
  all projects` per LESSONS 2026-05-25.
- LESSONS to defend against: 2026-05-25
  (load-bearing docs — AGENTS.md edit +
  README "Daily ops" code block addition),
  2026-05-25 (lib/ reinstall —
  `Reinstall: all projects`), 2026-05-26
  (`tail` shadow), 2026-05-26 (PATH reset
  — stubs in `$HOME/.local/bin`),
  2026-05-27 (`$(cat)` trap — state file
  write goes through `cp` of tmp),
  2026-05-28 (printf leading-dash —
  reason text goes through `printf --
  '%s'`), 2026-05-30 (`grep -F --`),
  2026-06-01 (`grep -c` double-print),
  2026-06-01 (dispatcher fall-through),
  2026-06-03 (UTF-8 sign-extension —
  reason ASCII-only for v1, JSON escape
  via `preflight_json_escape`), 2026-06-05
  (dispatcher forward-reference),
  2026-06-05 (bash 3.2 LC_ALL caching —
  width via `preflight_visible_width`),
  2026-06-05 (export-in-subshell trap —
  `_fleet_check_vacation` called without
  `$(...)`), 2026-06-08 (awk
  empty-string-key —
  `vacation_compose_briefing` BEGIN block
  initializes counters), 2026-06-08
  (IFS=$'\t' middle-empty-field —
  per-slug TSV uses `-` sentinels).
- This ticket compounds 0006 (`ship_paused`
  — shares the suspension semantics),
  0030 (`fleet resume` — shares the
  resume-confirmation shape), 0033
  (`QUIET_HOURS` — shares the PHASE 0
  suppression hook AND the
  `_fleet_check_*` helper pattern), 0036
  (`fleet morning` — the return briefing
  leverages morning's verdict composer).
  Per P-1 the diff is small: ~250 lines
  of `vacation_*` helpers + ~150 lines
  of `_fleet_check_vacation` in
  common.sh + ~80 lines of PHASE 0 hook
  in ship.sh and eng.sh + ~300 lines
  of test + 5 fixture files + 2 new
  AGENTS.md bullets + one help-text
  line + one README line.

## Implementation log

(Appended by the implementation-dev agent during execution.)

- 2026-06-11 — ticket filed by gtm-innovation
- 2026-06-11 — implementation-dev: started on feat/0046-fleet-vacation-pto-mode. Plan: write `tests/vacation.sh` first (12 ACs), then add `vacation()` dispatcher + six helpers in `bin/fleet` above the dispatcher, `_fleet_check_vacation` in `lib/common.sh`, PHASE 0 hooks in `lib/ship.sh` + `lib/eng.sh`, AGENTS.md telemetry entries for `vacation_skip` and `vacation_returned`, README "Daily ops" line, and `bin/fleet` help banner line.
- 2026-06-11 — implementation-dev: shipped. Local gate green (shellcheck, bash -n, check-backlog, vacation.sh 12/12 ACs, quiet-hours.sh regression-free). Self-check hits are pre-existing on main (not from this PR). PR body carries `Reinstall: all projects` per LESSONS 2026-05-25.
