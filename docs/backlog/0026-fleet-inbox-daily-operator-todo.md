---
id: 0026
title: fleet inbox prints the daily TODO list the operator owes the loop
status: in-progress
priority: P1
area: observability
created: 2026-06-01
owner: gtm-innovation
---

## User story

As a fleet operator opening fleet-control at 9am on a weekday with five
minutes before standup, deciding which (if any) of the fleet's needs I am
actually going to action before my day starts, I want
`bin/fleet inbox` to print a single TODO checklist — drafts I owe a
promotion pass, projects whose `SELF_CANCEL` is expiring this week,
projects auto-paused after send-back streaks, agent PRs sitting open
beyond the heal cap, and projects whose budget hit `budget_block` since
the last inbox run — so that I can decide in 30 seconds what (if
anything) requires my hands today, instead of opening five subcommands
or scrolling fleet-control's history tab.

## Why now (four lenses)

### Product Owner
`fleet weekly` (0025) answers "was this week worth it?" — a Sunday
rear-view-mirror. `fleet overview` (0019) answers "what is the fleet
doing RIGHT NOW?" — a real-time snapshot. Neither answers the question
that actually matters on a Tuesday at 9:01am: **"what do I owe the
loop today?"** That question is the leading cause of retention failure
in the kit's third and fourth week — the operator looks at fleet-control,
sees nothing screaming red, closes the tab, and the draft-promotion
debt silently grows until they stop trusting the loop. `inbox` is the
smallest meaningful unit of value: one command, one prioritized
checklist, one decision per item. Subtraction: the operator stops
guessing what's on their plate.

### Stakeholder
This is the retention compound. Every gauge the kit already emits
(`lesson_draft_emitted` from 0022, `ship_paused` from 0006,
`budget_block` from 0004, `pr_opened` from 0002, the `SELF_CANCEL`
countdown the manifest already carries) is a SIGNAL today; none of
them is a DEMAND on the operator. `inbox` is the first surface to
re-cast those signals as a single ordered demand list with explicit
remediation hints next to each item. The moat widens because the
question "what does my fleet need from me?" gets a canonical
shell-only answer the kit can ship today and fleet-control can
mirror tomorrow — same JSON contract, same source-of-truth events
channel (P-6). It also creates the natural anchor point for any
future "needs your eyes" interrupt source (a CI flake the loop can't
classify, a `prompts_drift` warning that lasted >24h, a project that
emitted zero `pr_opened` for >7 days). The first version surfaces
five concrete debts; the channel scales without renaming an event
(P-6: never repurpose; only compose).

### User (operator Tuesday 9:01am, three slugs in front of them)
Runs `bin/fleet inbox`. Sees:

```
FLEET INBOX — 2026-06-02 (since last run 18h ago)

drafts to promote                 3 across 2 projects
  agent-fleet      2 drafts        docs/LESSONS.md
  digitalcraft     1 draft         docs/LESSONS.md

self-cancel expiring (<=7d)       1
  digitalcraft     5d              bump SELF_CANCEL in agents.config.sh

paused projects                   1
  courtiq          paused 14d ago  launchctl enable gui/$UID/com.courtiq.agent-ship

budget tripped today              0
in-flight agent PRs >24h old      0

nothing else owes you a click. last weekly: 3d ago — try `fleet weekly`.
```

They see exactly three things to do, in priority order, with the
remediation command sitting next to each row. Two are 30-second jobs
(bump SELF_CANCEL, promote 3 drafts); one is a deliberate choice
(do I un-pause courtiq?). The "did I miss something?" anxiety the kit
quietly accrues over weeks goes to zero in 30 seconds. Confidence
moves from "I hope I'm not behind" to "I know the list."

### Growth
"What does my fleet need from me today?" is the question every operator
running multiple agents asks, and it is the question NO existing
agent-orchestration tool answers in one screen. A friend running their
own loop sees `fleet inbox` once and immediately gets the shape — TODO
list, prioritized, remediation hints inline. It is also a perfect daily
demo for the kit's pitch ("five minutes, one screen, the whole fleet
asks for help"). The screenshot a curious adopter takes after running
`fleet kickstart --demo` becomes a real artifact instead of a column
of zeroes.

## Acceptance criteria

Each box maps 1:1 to a test scenario in `tests/inbox.sh`.

- [ ] `bin/fleet inbox` (no flags) prints a banner
      `FLEET INBOX — <YYYY-MM-DD> (since last run <Nh|Nd> ago)`, exits 0,
      and is followed by five named sections in this exact order:
      `drafts to promote`, `self-cancel expiring (<=7d)`,
      `paused projects`, `budget tripped today`,
      `in-flight agent PRs >24h old`. Sections render their headline
      count even when zero (so the operator visually confirms the
      check ran).
- [ ] `drafts to promote` counts `lesson_draft_emitted` events
      (ticket 0022) per project where the event's `ts` is newer than
      the project's latest `<!-- DRAFT: reviewer send-back, PR #<N>,
      <date> -->` block in `docs/LESSONS.md` was promoted (i.e. the
      block still exists in the file). When the file is absent, every
      emitted event counts. The implementation MAY simplify v1 to "count
      every `<!-- DRAFT: ` marker present in LESSONS.md" — the events
      channel is the cross-check, not the source. Test fixtures a
      LESSONS.md with two DRAFT blocks and a third already promoted
      (no marker) and asserts the count is 2.
- [ ] `self-cancel expiring (<=7d)` lists every discovered project
      whose `SELF_CANCEL` (YYYYMMDD in `agents.config.sh`) is between
      today and 7 days out, inclusive. Rows render `<slug>  <N>d
      bump SELF_CANCEL in agents.config.sh`. Expired projects appear
      under the SAME section with `EXPIRED` instead of `<N>d` (we do
      not split into two sections for v1 — the operator's job is the
      same). Test fixtures a 5d-out project and an EXPIRED project
      and asserts both rows render.
- [ ] `paused projects` lists every project whose `agent-ship`
      launchd label is currently in `launchctl print-disabled
      gui/$UID` output. Reuses `weekly_is_paused()` (line ~1591) and
      `weekly_paused_days()` (line ~1576) from ticket 0025. The
      remediation hint reads `launchctl enable
      gui/$UID/<namespace>.agent-ship`. Test stubs `launchctl` to
      report one paused slug and asserts the row.
- [ ] `budget tripped today` counts `budget_block` events
      (ticket 0004) emitted today (UTC, `00:00:00`-`23:59:59`) per
      project. Rows render `<slug>  $<spent>/$<cap>  bump
      MAX_DAILY_USD or wait for tomorrow`. Test fixtures a
      `budget_block` event in today's window and asserts the row;
      a second event in yesterday's window MUST NOT count.
- [ ] `in-flight agent PRs >24h old` lists open PRs whose head ref
      starts with `feat/`, `chore/gtm-`, or `eng/` and whose
      `createdAt` is more than 24h ago, computed via `gh pr list
      --repo <REPO> --state open --base main --json
      headRefName,number,createdAt`. The section degrades gracefully
      when `gh` is absent or unauth'd: it prints `(skipped: gh not
      available)` and counts as 0. Test stubs `gh` (per LESSONS
      2026-05-26 — stub in `$HOME/.local/bin`) to return one
      eligible PR and asserts the row.
- [ ] Trailing line: `nothing else owes you a click. last weekly:
      <Nh|Nd> ago — try \`fleet weekly\`.` The "last weekly" age is
      the mtime of any cached weekly run marker (`$XDG_CACHE_HOME/
      fleet/inbox-state` — see Engineering notes for the marker
      file). When no cache marker exists, the line prints `last
      weekly: never — try \`fleet weekly\`.` Test asserts both
      branches.
- [ ] "since last run <Nh|Nd> ago" header field reads
      `$XDG_CACHE_HOME/fleet/inbox-state` (default
      `$HOME/.cache/fleet/inbox-state`); the file is written on EVERY
      `fleet inbox` invocation with the current epoch as the only
      content. First run prints `since last run: never`. Test asserts
      both first-run and second-run branches (the second invocation
      should report `0h ago` or `0m ago` per `human_age()`).
- [ ] `--json` flag prints one JSON object per section plus one
      summary object. Section schema:
      `{"section":"drafts","count":N,"items":[{"slug":"...",
      "count":N,"hint":"..."}, ...]}`.
      Summary schema: `{"summary":true,"sections":5,"items":N,
      "since_last_run_seconds":N|null}`. Test parses every line
      through `node -e 'JSON.parse(...)'`.
- [ ] `--slug <SLUG>` filters every section to one project. The
      header banner still prints; empty sections still render
      with `0` (so the operator can confirm there is genuinely
      nothing). Test asserts a single-slug invocation suppresses
      other projects.
- [ ] Exit code is 0 even when sections have items — `inbox` is a
      report, not a gate. Exit code is 2 only on usage error
      (`--slug` with empty value, unknown flag). Test asserts the
      exit codes.
- [ ] No new event types. `inbox` is a pure consumer of the
      existing telemetry channel (P-6: telemetry is the source of
      truth; readers compose, they do not invent). The PR body
      affirms "no new event types added; no AGENTS.md § Telemetry
      append needed."
- [ ] `tests/inbox.sh` covers all twelve boxes using
      `$HOME/.local/bin` stubs (per LESSONS 2026-05-26) for `gh`
      and `launchctl`, and `FLEET_DISCOVERY_ROOT` redirected to a
      `tests/fixtures/inbox/` tree seeding three synthetic projects
      with controlled `agents.config.sh`, `events.jsonl`, and
      `docs/LESSONS.md` content. Asserts via golden file
      `tests/fixtures/inbox.golden.txt`. Run-time budget: <15s.

## Out of scope

The dev agent will NOT do these even if they seem related.

- A scheduled launchd job for `inbox` (a "morning email"). The
  operator runs it by hand. Scheduling adds a plist, an uninstall
  surface, and a "did inbox fire?" failure mode for zero added value.
  `fleet weekly` (0025) made the same call deliberately.
- Auto-promotion of LESSONS drafts. `inbox` flags the debt; the
  operator does the work (P-9: promotion is the operator's job).
- Auto-bumping a `SELF_CANCEL` value. The countdown is the kit's
  one self-cancel switch; bumping silently would undermine it.
- A "snooze" mechanism that hides a section until tomorrow.
  Snoozing introduces state that diverges from telemetry; the
  source of truth is the events channel, not an inbox-local opinion.
- Auto-cancelling a stuck PR. `fleet rollback` (0017) already
  exists; surfacing the stuck PR row IS the value here.
- Rendering the inbox as HTML / a desktop notification. Output is
  stdout; the operator pipes themselves. Fleet-control can render
  the JSON later.
- A "score" or "due-by" weighting per item. v1 lists by section in
  the fixed order above. Adding priorities is a future ticket once
  the data is in operators' hands.
- Cross-project deduplication of drafts (e.g. "this lesson was
  already promoted in courtiq"). `fleet lessons-sync` (0009) is
  the existing surface for cross-project semantics — don't
  reinvent here.

## Engineering notes

Files / patterns the dev should touch. Specific enough that the dev
doesn't have to re-discover the architecture.

- `bin/fleet` — new `inbox()` dispatcher next to `weekly()` (line
  ~1653). Pattern lifts directly from `weekly()`: same discovery via
  `weekly_discover()` (line ~1506), same `--json` / `--slug`
  parsing, same `$HOME/.local/bin` stub strategy in the test.
- `bin/fleet` — five new helpers, one per section. Name them
  `inbox_count_drafts()`, `inbox_self_cancel_rows()`,
  `inbox_paused_rows()` (reuses `weekly_paused_days` +
  `weekly_is_paused`), `inbox_budget_block_today()`,
  `inbox_stuck_prs()`. Each helper takes the manifest path + the
  resolved events.jsonl path and emits TSV rows the renderer
  formats — keeps the rendering separate from the data extraction.
- `bin/fleet` — `inbox_state_path()` returns
  `${XDG_CACHE_HOME:-$HOME/.cache}/fleet/inbox-state`. Read on
  entry, written on exit. Per LESSONS 2026-05-27, write via a
  temp-file + `mv` so a SIGINT mid-write does not corrupt the
  marker. Read via `cat` is fine — single line, no trailing-newline
  trap risk.
- `bin/fleet` — `inbox_render_human()` and `inbox_render_json()`
  separate. The JSON path emits one object per section + one
  summary object, JSONL style (same shape as `weekly --json` for
  consumer consistency). The human path uses fixed-width columns
  via `weekly_pad()` (line ~1624) where helpful, plain text
  where not (the section headlines are bold per the existing
  `c_bld` palette).
- `bin/fleet` — the help banner block at the top of the file gets
  a new line: `fleet inbox                what the fleet owes you
  today (drafts, expirations, paused, budgets, stuck PRs)`. The
  README "Daily ops" code block gets the same one-liner.
- `lib/common.sh` — NO changes. `inbox` is a pure reader; per P-6
  it does not emit new events. The PR body affirms this so the
  reviewer's telemetry-contract check stays satisfied. NO
  `fleet_*` signature changes — additive subcommand only.
- `prompts/` — NO changes. The command is operator-facing only;
  no agent prompt reads `fleet inbox`. No `Reinstall: all projects`
  line is needed because `lib/` and `prompts/` are untouched.
- `tests/fixtures/inbox/` — NEW directory under `tests/fixtures/`
  holding synthetic `agents.config.sh` files for three projects
  plus their `events.jsonl` and `docs/LESSONS.md` content. Pattern
  lifted from `tests/fixtures/weekly/` (ticket 0025). Golden file
  at `tests/fixtures/inbox.golden.txt`. Per LESSONS 2026-05-27,
  the test uses `cp` for backup/restore around any host file it
  touches — never `$(cat …)`.
- `tests/inbox.sh` — top of file mirrors `tests/weekly.sh`:
  redirect `FLEET_DISCOVERY_ROOT`, stub `gh` and `launchctl`
  under `$HOME/.local/bin` (per LESSONS 2026-05-26), `mktemp -d`
  for the fixture under `$HOME`. The test MUST run green twice in
  a row (the inbox-state marker should not cause idempotency
  drift between back-to-back invocations).
- New deps: none. Pure shell + awk + the existing JSONL parsing
  helpers (`digest_event_count_since`, `digest_iso_to_epoch`).
- Public API: additive — `bin/fleet inbox` is a new subcommand,
  no new event types, no `fleet_*` signature changes.
- BREAKING flag: NO. PR body affirms "no `fleet_*` signature
  changes" and "no new event types added."
- Reinstall required: NO. `lib/` and `prompts/` are untouched.
- LESSONS to defend against: 2026-05-26 (`tail` shadowed
  `/usr/bin/tail` — `inbox` does not collide with any common
  binary, confirmed via `command -v inbox` returning nothing,
  but the dev should sanity-check before naming any new helpers
  e.g. `head`, `find`, `kill`). LESSONS 2026-05-28 (`printf '-…'`
  trap) applies if any TSV row value can start with `-` — quote
  via `printf -- '%s' "$v"`. LESSONS 2026-05-30 (`grep -F` flag
  trap) applies to any DRAFT marker search using `grep -qF --
  "<!-- DRAFT:"`.
- Naming clash check: `command -v inbox` returns nothing on macOS
  and Ubuntu; safe to name the dispatcher `inbox()` directly.
- This ticket compounds 0004 (budget_block), 0006 (ship_paused
  → paused row), 0019 (overview's launchctl pattern), 0022
  (lesson_draft_emitted), and 0025 (weekly_discover, paused
  helpers). It introduces ZERO new substrate; every primitive
  it reads already exists. Per P-1 the diff is small: ~250 lines
  of `inbox*` helpers + ~80 lines of tests fixture content +
  one help-text line.

## Implementation log

(Appended by the implementation-dev agent during execution.)

### 2026-06-01 — implementation-dev

- Branch: `feat/0026-fleet-inbox-daily-operator-todo`.
- Read AGENTS.md "Agent parameters" and LESSONS.md before starting.
- Tests-first: wrote `tests/inbox.sh` with one assertion block per AC.
- Implemented `inbox()` + five helpers in `bin/fleet`, mirroring the
  `weekly()` shape: discovery via `weekly_discover`, paused via
  `weekly_is_paused` + `weekly_paused_days`, JSON via
  `doctor_json_escape`. Wrote inbox-state marker via temp-file + `mv`
  per LESSONS 2026-05-27. Used `printf -- '%s\n'` and
  `grep -F -- "<!-- DRAFT:"` everywhere a leading `-` was possible,
  per LESSONS 2026-05-28 / 2026-05-30. The dispatcher name `inbox`
  was confirmed clash-free via `command -v inbox` (per ticket notes).
- No `lib/` or `prompts/` changes — purely additive subcommand, no
  new event types (P-6), no `fleet_*` signature changes. No
  Reinstall line, no BREAKING flag.
- README "Daily ops" code block updated with one new line.
