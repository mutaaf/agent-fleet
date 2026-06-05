---
id: 0033
title: QUIET_HOURS manifest knob suppresses ship/groom/eng during operator-declared windows
status: in-progress
priority: P1
area: governance
created: 2026-06-05
owner: gtm-innovation
---

## User story

As an operator running 5 projects whose ship runs every hour at :37
and whose Anthropic spend on a stuck PR cascade can quietly burn $30
overnight while I sleep, I want a `QUIET_HOURS="22:00-07:00"` line in
each project's `agents.config.sh` that makes `ship`, `groom`, and
`eng` no-op cleanly (one `quiet_hours_skip` event emitted, exit 0)
during the operator-declared local-time window — leaving `review` to
keep grading PRs unaffected — so that I can sleep without checking
the fleet-control portal at 2am to confirm nothing's looping on a
broken PR, and wake up to a fleet that simply waited until 7am to
start its day.

## Why now (four lenses)

### Product Owner
`SELF_CANCEL` (D10) bounds the project's TOTAL lifetime; `MAX_DAILY_
USD` (ticket 0004) bounds today's spend; `ship_paused` (0006) stops
the loop after N send-backs. None of these address the simpler human
worry: "I don't want it running while I sleep." The current workaround
is for the operator to `launchctl disable gui/$UID/com.<slug>.agent-
ship` at bedtime and `enable` it in the morning across N projects —
an unreasonable ritual. The smallest unit of value is a one-line
manifest knob plus a 20-line check in `lib/common.sh` that every
runner already calls (`fleet_self_cancel`, `fleet_check_budget`,
`fleet_check_sendback_streak`). The new check, `fleet_check_quiet_
hours`, slots in next to those three with the same shape: emit one
event, exit 0, do not advance the heal counter. Review is exempt by
design — it is a poller, not a worker, and continuing to grade
in-flight PRs overnight is a feature, not a bug.

### Stakeholder
This is moat-deepening on the governance layer in a way no other
autonomous-agent kit ships: a per-project quiet window that is
DECLARATIVE (lives in the manifest, not in a cron tweak), AUDITABLE
(every skipped run emits an event the consumer can see), and
ASYMMETRIC (workers pause, review polls — matches the operator's
actual desire). The event channel gets one new type (`quiet_hours_
skip`) that doubles as the "did the kit respect my quiet hours
yesterday?" signal — `fleet weekly` (0025) can render a "quiet
respected: Y/N" column, `fleet inbox` (0026) can flag a "broken
quiet hours" state if a run fires inside the window. It is also the
first manifest knob with a TIME-OF-DAY semantic, which sets the
precedent for any future "only between business hours" or
"only on weekdays" knob the operator might want later — but those
are NOT in this ticket (per P-1, ship the smallest window primitive
first).

### User (operator at 11pm, about to sleep)
Edits `agents.config.sh`:

```bash
# --- quiet hours ---
# Local time (the runner reads the OS TZ). Workers no-op during this
# window; review keeps grading. Set empty to disable.
QUIET_HOURS="22:00-07:00"
```

Runs `bash lib/install.sh ~/code/widgets` once. Sleeps. At 2:37am
local time, the ship launchd job fires, sources `lib/common.sh`,
calls `fleet_check_quiet_hours` which returns "yes, suppress":
emits one `quiet_hours_skip {phase:ship, window:"22:00-07:00",
now_local:"2026-06-06T02:37:09-07:00"}` event, prints `quiet hours
active (22:00-07:00 local) — ship no-op until 07:00`, exits 0. At
7:37am the same job runs normally — no special handling, no resume
command. The operator wakes up to `fleet overview` showing five
projects in `WAIT` / `OK` state and zero spend overnight on broken
PRs. They never typed `launchctl disable`, never had to remember the
incantation, never had to do per-project work.

If the operator left `QUIET_HOURS` empty (the default), the runner
behaves exactly as today — no change. The knob is opt-in.

### Growth
Every operator past week 2 hits this. The fleet's whole posture is
"set it and forget it," but until you can declaratively say "and
don't burn while I sleep," operators learn to babysit it instead.
Adding QUIET_HOURS is the difference between "this is a tool I let
run all day" and "this is a tool I let run all night." Friends
running their own loop pick this up in the first conversation
because the alternative — five `launchctl disable` aliases in
their shell — is the visible friction they ALL have. It is also the
first manifest knob that maps cleanly onto a fleet-control toggle
("quiet hours: on") — the portal flips a stored value, install.sh
copies it through, common.sh reads it at fire time.

## Acceptance criteria

Each box maps 1:1 to a test scenario in `tests/quiet-hours.sh`.

- [ ] A project whose `agents.config.sh` defines `QUIET_HOURS=
      "22:00-07:00"` and whose runner is invoked (via the
      ship/groom/eng entry point) at a local time INSIDE the
      window emits one `quiet_hours_skip` event to
      `$CACHE_DIR/events.jsonl`, prints `quiet hours active
      (22:00-07:00 local) — <phase> no-op until 07:00` to the
      log, and exits 0. The runner does NOT advance the heal
      counter, NOT call `claude --print`, NOT touch `gh`. Test
      stubs the system clock via `FLEET_NOW_OVERRIDE` (a new
      test-only env, parsed by the new helper — same shape as
      `FLEET_HEAL_CATALOG` override from ticket 0020).
- [ ] A project whose `QUIET_HOURS=""` (empty — the default for
      backward compatibility) runs normally at any time. The
      new check returns "do not suppress" and the runner
      proceeds. Test asserts no `quiet_hours_skip` event is
      emitted and the existing claude invocation happens.
- [ ] A project with `QUIET_HOURS="22:00-07:00"` invoked at
      14:00 local time runs normally (outside the window). Test
      asserts no event, normal claude invocation.
- [ ] A WINDOW THAT CROSSES MIDNIGHT (`22:00-07:00`) is parsed
      correctly: the suppression range is `[22:00, 24:00) ∪
      [00:00, 07:00)`. Test covers four boundary points:
      21:59 (run), 22:00 (skip), 06:59 (skip), 07:00 (run).
- [ ] A WINDOW THAT DOES NOT CROSS MIDNIGHT (`09:00-17:00`)
      is parsed correctly: the suppression range is
      `[09:00, 17:00)`. Test covers 08:59 (run), 09:00 (skip),
      16:59 (skip), 17:00 (run).
- [ ] The `review` phase is EXEMPT — `fleet_check_quiet_hours`
      reads the `$FLEET_PHASE` env (already set by `fleet_log_
      init`) and returns "do not suppress" whenever phase is
      `review`, regardless of clock time. Test asserts that the
      review entry point at 02:00 local time still polls.
- [ ] An INVALID `QUIET_HOURS` value (e.g. `25:00-07:00`,
      `22-7`, `22:00`) is treated as if empty (do not suppress)
      AND a one-time `quiet_hours_invalid` log line (NOT an
      event — invalid config is operator error, not telemetry
      truth) is printed to stderr. The runner continues; we
      never silently ALLOW a misconfigured window to leave the
      loop unable to fire. Test asserts the stderr line and
      normal-run behavior across all three invalid values.
- [ ] `quiet_hours_skip` event payload: `{phase: <ship|groom|
      eng>, window: "<HH:MM-HH:MM>", now_local: "<ISO8601 with
      offset>"}`. Event lands in the SOURCE project's
      `$CACHE_DIR/events.jsonl` (per P-6 project is the unit of
      telemetry). Fires AT MOST ONCE per process (guarded by
      `FLEET_QUIET_HOURS_EMITTED`, same shape as `FLEET_PROMPTS
      _DRIFT_EMITTED` from ticket 0005).
- [ ] `AGENTS.md § Telemetry` is updated in the same PR with a
      new bullet for `quiet_hours_skip {phase, window,
      now_local}` following the existing entry style
      (verbatim shape: see ticket 0028's `lesson_promoted`
      paragraph and 0030's `ship_resumed` paragraph). Reviewer's
      telemetry-contract check requires this in the same diff.
- [ ] `manifest.example.sh` gets a new commented-out section
      `# --- quiet hours ---` with `QUIET_HOURS=""` and the
      explanatory comment from the User lens above. Documents
      the knob without changing default behavior for the
      already-installed fleet.
- [ ] `lib/install.sh` carries the new `QUIET_HOURS=` line
      through to the per-project copy under
      `~/.local/share/agent-fleet/projects/<slug>/agents.
      config.sh` exactly the way it carries `SELF_CANCEL` and
      `MAX_DAILY_USD`. No new generation step; the manifest is
      copied verbatim. Idempotent re-install with no change is
      still a no-op. Test asserts the copy contains the
      QUIET_HOURS line byte-for-byte.
- [ ] `tests/quiet-hours.sh` covers all 11 boxes. The
      `FLEET_NOW_OVERRIDE` env is the test's clock injector
      (`YYYY-MM-DDTHH:MM:SS[+/-HHMM]`). Per LESSONS
      2026-05-27, the test uses `cp` for backup/restore. Per
      LESSONS 2026-05-26 stubs go under `$HOME/.local/bin`.
      Run-time budget: <10s.

## Out of scope

The dev agent will NOT do these even if they seem related.

- A `WEEKDAYS_ONLY` knob. v1 is one window primitive. Multi-knob
  scheduling (weekdays, holidays, vacation mode) belongs in a
  follow-up once the operator has lived with QUIET_HOURS for a few
  weeks and named which next axis matters.
- A "quiet hours UI" in fleet-control. That ships in the portal's
  own repo; this ticket exposes the substrate (manifest knob +
  event type) the portal will read.
- Auto-resuming on quiet-hours exit. The launchd schedule already
  fires the next interval; there is no "resume" action needed. The
  command surface from ticket 0030 (`fleet resume`) is specifically
  for `ship_paused`, NOT for `quiet_hours_skip` (which is not a
  pause — the next interval runs normally).
- A per-phase `QUIET_HOURS_SHIP=` / `QUIET_HOURS_GROOM=` split.
  v1 is one window for all three workers; review is exempt by
  design. If an operator wants groom to run during their quiet
  hours but ship to wait, that's a future ticket.
- Suppressing `fleet kickstart` (the operator-initiated manual
  trigger). The whole point of kickstart is to bypass the
  schedule — quiet hours should not gate an explicit operator
  ask. The check returns "do not suppress" when `FLEET_PHASE` is
  unset OR when `FLEET_KICKSTART=1` is set (kickstart_cmd already
  sets it).
- Timezone DST handling beyond what `date` does natively. The
  runner reads the OS TZ; if the system rolls back/forward, the
  window follows. Operators who want UTC-fixed windows can set
  `TZ=UTC` in launchd; documenting that is fine, but no special
  DST math in this ticket.

## Engineering notes

Files / patterns the dev should touch. Specific enough that the dev
doesn't have to re-discover the architecture.

- `lib/common.sh` — new `fleet_check_quiet_hours()` next to
  `fleet_self_cancel`, `fleet_check_budget`, and
  `fleet_check_sendback_streak`. Reads `QUIET_HOURS` from the
  already-loaded manifest, reads `FLEET_NOW_OVERRIDE` if set
  else `date +%H%M%z` for the current local time. Echoes
  `suppress` / `ok` / `invalid` and returns 0/0/0 (the caller
  branches on the echoed value, not the return code, matching
  `fleet_check_budget`'s shape).
- `lib/common.sh` — invoked from `lib/ship.sh`, `lib/groom.sh`,
  `lib/eng.sh` right after `fleet_check_budget` and right
  before the claude invocation. On `suppress`, the runner calls
  `fleet_emit_event quiet_hours_skip phase=$FLEET_PHASE
  window="$QUIET_HOURS" now_local="<iso>"` and `exit 0`. On
  `invalid`, the runner prints to stderr and continues
  (treats as if `QUIET_HOURS=""`). On `ok`, the runner
  proceeds.
- `lib/common.sh` — `FLEET_QUIET_HOURS_EMITTED` guard env,
  same shape as `FLEET_PROMPTS_DRIFT_EMITTED` from ticket
  0005, ensures the event fires at most once per process even
  if the helper is called twice.
- `lib/review.sh` — NO new check call. The function `fleet_
  check_quiet_hours` ITSELF returns `ok` when `$FLEET_PHASE`
  is `review`, so even if a future maintainer adds the
  invocation by accident it is a no-op. Belt and suspenders.
- `lib/install.sh` — verify the manifest-copy block already
  preserves arbitrary lines (it should — it's a `cp`, not a
  field-aware writer). If it filters fields, extend the
  allow-list to include `QUIET_HOURS`. Test asserts the
  installed copy contains the line byte-for-byte.
- `manifest.example.sh` — new commented section as described
  in AC#10.
- `AGENTS.md` — append the new bullet to § Telemetry per
  AC#9, mirroring the shape of `lesson_promoted` and
  `ship_resumed` paragraphs.
- `bin/fleet` — NO required changes in this PR. `fleet
  weekly` / `fleet inbox` rendering of the new event type
  belongs in a follow-up; the event type is additive and
  consumers tolerate unknown types per the existing
  contract.
- `prompts/` — NO changes. The check is in the runner's
  shell layer; prompts are never read in the suppressed
  branch.
- `tests/fixtures/quiet-hours/` — NEW directory under
  `tests/fixtures/` holding one synthetic project with a
  manifest carrying `QUIET_HOURS="22:00-07:00"`, plus one
  variant with the value `""`, plus three invalid-value
  variants for AC#7.
- `tests/quiet-hours.sh` — top of file mirrors
  `tests/budget.sh`: stub `claude`, `gh`, `git` under
  `$HOME/.local/bin` (`$HOME=$TMP/home` per LESSONS
  2026-05-26). The `FLEET_NOW_OVERRIDE` env is set per
  test case to inject the clock. The event assertion reads
  the source project's `events.jsonl` and parses the last
  line via `node -e 'JSON.parse(...)'`.
- New deps: none. Pure shell + date.
- Public API: additive — ONE new helper
  (`fleet_check_quiet_hours`) added to `lib/common.sh`, one
  new env (`FLEET_NOW_OVERRIDE`) for tests only, ONE new
  event type (`quiet_hours_skip`). The existing five
  public `fleet_*` functions are unchanged.
- BREAKING flag: NO. PR body affirms "no change to the
  five public `fleet_*` signatures (load_manifest,
  self_cancel, log_init, checkout, run_claude)," names
  the new event type, and notes that the manifest knob
  is opt-in (empty default preserves today's behavior).
- Reinstall required: YES — anything that touches
  `lib/` triggers a fleet-wide reinstall per LESSONS
  2026-05-25. PR body includes `Reinstall: all
  projects`.
- LESSONS to defend against: 2026-05-26 (`tail` shadow —
  no new subcommand binary; helper name is namespaced
  `fleet_check_quiet_hours`). LESSONS 2026-05-26 (PATH
  reset — stubs go in `$HOME/.local/bin`). LESSONS
  2026-05-27 (`$(cat)` trap — fixture reads use `cp`).
  LESSONS 2026-05-28 (printf leading-dash trap — the
  window string starts with a digit; no risk, but the
  `now_local` value goes through `printf -- '%s'` for
  consistency). LESSONS 2026-06-01 (awk -v multiline
  trap — the time-parse uses single-line tokens only).
  LESSONS 2026-06-03 (UTF-8 sign-extension trap — the
  event emit reuses `_json_escape` which a follow-up
  will harden; the window/iso/phase values are all
  ASCII so this is safe for THIS event type, but the
  PR body notes the follow-up debt).
- This ticket compounds 0004 (per-slug daily budget caps
  are the spend-axis safety; quiet hours is the
  time-of-day-axis safety), 0006 (`ship_paused` is the
  failure-mode safety; quiet hours is the
  schedule-policy one), 0010 (`AGENT_DRY_RUN` is also
  read at fire time and short-circuits the runner; same
  shape). Per P-1 the diff is small: ~80 lines in
  `lib/common.sh`, ~5 lines per runner (3 runners),
  ~250 lines of test, ~10 lines of manifest example,
  one AGENTS.md paragraph.

## Implementation log

(Appended by the implementation-dev agent during execution.)

- 2026-06-05 — branch `feat/0033-quiet-hours-suppress-launchd-runs` opened; status flipped to in-progress.
- YYYY-MM-DD — failing test added in `tests/quiet-hours.sh`
- YYYY-MM-DD — PR #N opened, CI [state]
- YYYY-MM-DD — merged to main
