---
id: 0050
title: fleet tour walks a new operator through their first events.jsonl annotated by PRINCIPLES
status: shipped
priority: P2
area: docs
created: 2026-06-13
owner: gtm-innovation
---

## User story

As a brand-new operator who just ran `fleet onboard <repo>` (0011) and
`fleet onboarding-check <repo>` (0041), watched their first
`agent-ship` cycle fire at `:37`, and is now staring at a fresh
`events.jsonl` with ~12 lines they don't fully understand — who CAN
read `AGENTS.md § Telemetry` (the per-type schema) and `PRINCIPLES.md`
(the doctrine) separately, but has no surface that JOINS the two — I
want `bin/fleet tour [<repo>]` to walk through the project's
events.jsonl chronologically, explain each event in plain English,
cite the relevant `P-N` from PRINCIPLES.md per event, and end with a
"what to read next" footer pointing at the three most-leveraged
follow-up commands, so my first hour with the kit converts from
"reading three docs and grepping a JSONL by hand" to "running one
guided tour command."

## Why now (four lenses)

### Product Owner
`fleet onboard` (0011) gets the kit installed. `fleet onboarding-check`
(0041) confirms the install is end-to-end healthy. `fleet kickstart
--demo` (0023) lets a credential-less stranger SEE the loop run.
NONE of those answer the next question the new operator actually has:
"I just watched a real ship cycle fire on my real project; what did
each line in events.jsonl mean and why?"

The current answer is: read `AGENTS.md § Telemetry` (which lists every
event type's schema, but in alphabetical/feature order, not in the
order events fire), AND read `PRINCIPLES.md` (which lists the nine
principles, but isn't cross-referenced from telemetry), AND map them
together by hand. That's a 30-minute task the new operator does once,
then never revisits — and they often DON'T do it (the events stay
opaque, the principles stay abstract, and the operator never builds
the mental model "this event type exists because P-N matters").

The smallest meaningful unit of value is one command, one guided
narration:

```
fleet tour ~/projects/courtiq

tour: walking events.jsonl for courtiq (12 lines, ~1h of runtime)

[1] 2026-06-13T09:37:09Z  run_started {pid=12384, phase=ship}
    The ship runner just fired (launchd schedule :37). Every run
    starts here. The pid lets you grep launchd logs if a run
    silently disappears.
    Why this event exists: P-6 (telemetry is the source of truth).
    Without it you can't tell apart "launchd never fired" from
    "the run started but died early."

[2] 2026-06-13T09:37:12Z  pr_opened {number=14, branch=
    feat/0003-add-stripe-webhook-retry, phase=ship}
    The agent picked the top groomed ticket (0003) and opened PR
    #14. The branch prefix `feat/` matches your AGENTS.md's
    `Agent branch prefixes` contract.
    Why this event exists: P-4 (ship the top groomed ticket,
    never the convenient one). Every pr_opened is auditable
    evidence the agent obeyed the priority queue.

[3] 2026-06-13T09:41:55Z  gate_failed {check=unit-tests, phase=ship}
    CI's `unit-tests` job failed on PR #14. This is the heal
    signal — the next ship run will heal the PR before picking a
    new ticket.
    Why this event exists: P-3 (heal in-flight before new work).
    Without this signal the loop would pile up red PRs.

...

[12] 2026-06-13T10:53:22Z  run_completed {exit=0, duration_ms=
     7813, phase=ship}
     This cycle ended cleanly. The PR ended up merged via
     auto-merge on the heal path.
     Why this event exists: P-6 — every run pairs an
     `run_started` with a `run_completed`. A `run_started` with
     no matching `run_completed` is the operator's signal that
     a run crashed.

what to read next:
  • fleet morning            — your daily one-paragraph briefing
  • fleet streak             — does this project have a streak yet?
  • fleet doctor             — is the kit installation healthy?

reference docs:
  • AGENTS.md § Telemetry    — every event type's schema
  • prompts/PRINCIPLES.md    — the nine principles cited above
  • docs/LESSONS.md          — the kit's operational memory
```

Subtraction: the new operator stops doing the three-document
manual join. The tour IS the join. They walk away with an EXPLICIT
mental model: "events.jsonl is the source of truth; each event
type exists because some P-N says it must; here are the three
commands I'll actually run tomorrow."

Per P-5 (operator confidence over feature richness), the win is
converting the first-hour learning curve from "read three docs and
grep a JSONL by hand" to "run one command." A new operator who
finishes the tour has internalized the kit's mental model; a new
operator who never reads the docs churns.

### Stakeholder
This is **moat-deepening on the onboarding axis** — the kit's
first DOCS-AS-CODE surface. Every other docs file (`AGENTS.md`,
`PRINCIPLES.md`, `README.md`, `LESSONS.md`) is static text the
operator reads in their browser; `fleet tour` is text rendered
THROUGH THE OPERATOR'S OWN DATA so the principles cite the
operator's own events.

Per P-6 (telemetry is the source of truth), the tour is a PURE
COMPOSER over `events.jsonl` and the static
`prompts/PRINCIPLES.md` file. The events.jsonl is the input;
the static event-type → P-N mapping is the lookup table
(authored once in `lib/tour-catalog.sh`, kept next to
`lib/heal-catalog.sh` from ticket 0020). The composer:

1. Reads the project's `events.jsonl` (or
   `events.jsonl.archive/` if `--archive` is set) in
   chronological order.
2. For each event, looks up its `type` in the static catalog
   and renders the matching `principle_id` + plain-English
   gloss + "why this event exists" line.
3. Folds consecutive duplicate-type events with the same body
   into a single "× N occurrences" summary (so 4 identical
   `infra_flake_rerun` events don't render 4 times).
4. At the end, prints the "what to read next" footer
   pointing at the three most-leveraged follow-up commands
   based on what the operator's events showed (e.g. if any
   `lesson_draft_emitted` events fired, the footer suggests
   `fleet lessons-promote`).

The catalog is the moat-deepener: every new event type added in
a future ticket REQUIRES an entry in `lib/tour-catalog.sh` (the
gating check in `scripts/check-tour-catalog.mjs` rejects PRs
that add an event type without a matching catalog entry). That
forces every future telemetry change to also ship the
"how do I explain this to a new operator" answer in the same PR.

Per P-1 (smallest viable change), the diff is the catalog +
the composer + the catalog gate. ~350 lines total.

Compounds 0011 (`fleet onboard` — the prerequisite),
0018 (`prompts/PRINCIPLES.md` — the doctrine being cited),
0023 (`fleet kickstart --demo` — the credential-less
predecessor), 0041 (`fleet onboarding-check` — the
post-install verifier).

Per P-3 (heal in-flight before new work), `tour` is read-only
and never blocks heal work.

### User (new operator on a Saturday afternoon, kit
just installed)
Operator finished `fleet onboard` 90 minutes ago and watched
their first ship cycle fire. Curious but a little lost. Runs
`fleet tour`. Walks through 12 annotated lines over 5 minutes.
At the end the operator has internalized:

- Event types are the contract; transcripts are not.
- Each event has a principle behind it.
- These three commands are the daily ones to remember.
- Read LESSONS when something feels wrong.

Without the tour, the same operator either spent 30 minutes
grepping events.jsonl + reading docs (which most don't), or
spent 0 minutes and stayed permanently in the "I don't really
get what these events are" state. Per P-5, the win is the
NEW operator's first-week confidence.

Sub-scenario: an EXPERIENCED operator who's been running the
kit for months may STILL run `fleet tour` after the loop
emits a new event type they don't recognize (e.g. after a
prompts revision adds a new event). The tour is also the
docs-as-data surface for an UPGRADED operator, not just a
new one.

### Growth
The acquisition path so far covers "see the loop" (kickstart),
"install the loop" (onboard + preflight), "trust the loop"
(pr-footer), "share the loop" (recap + milestone). What's
missing is "LEARN the loop." `fleet tour` is the learning
moment.

A friend who's been pitched on agent-fleet runs `fleet
kickstart --demo` (sees a synthetic cycle), then `fleet
onboard ~/my-repo` (installs), then `fleet tour ~/my-repo`
(LEARNS the events). That's the full acquisition flow in
three commands and ~15 minutes. Today the middle step
("LEARN") has no command; the friend either reads three
markdown files or doesn't really understand what they
installed.

Per the brief's "Onboarding asymmetry: `fleet onboard`
bootstraps mechanically, but a NEW operator looking at their
first events.jsonl line has no annotated tour — `fleet
first-run` or `fleet tour` could walk them through their
first ship/groom/review cycle with explanatory text pulled
from PRINCIPLES.md" — this is the direct answer.

Differentiated from `fleet kickstart --demo` (0023):
kickstart RUNS a synthetic cycle; tour EXPLAINS a real
cycle. Both are credential-friendly (tour reads existing
files only); together they form the full
"see→install→learn" arc.

## Acceptance criteria

Each box maps 1:1 to a test scenario in `tests/tour.sh`.

- [ ] `bin/fleet tour [<repo>]` is a new subcommand. With no
      argument, walks the kit's OWN `events.jsonl` (the
      agent-fleet kit-as-project). With a repo path argument,
      walks that repo's `events.jsonl` (resolved via the same
      manifest discovery `overview_discover_slugs` uses).
      Missing repo and no kit events.jsonl: prints `tour: no
      events.jsonl found. run \`fleet onboard <repo>\` to
      install, OR \`fleet kickstart --demo\` to see a synthetic
      cycle.` exit 0. Test asserts via fixture.
- [ ] `lib/tour-catalog.sh` is a NEW shell file (NOT a runtime
      lib — never sourced by ship.sh/eng.sh/groom.sh/review.sh
      — only by `bin/fleet tour`). Defines one shell function
      per event type returning a `principle_id` + `gloss` +
      `why_this_event_exists` triple. Covers EVERY event type
      enumerated in `AGENTS.md § Telemetry`: `run_started`,
      `run_completed`, `gate_failed`, `pr_opened`,
      `self_cancel_trip`, `lock_blocked`, `budget_block`,
      `prompts_drift`, `ship_paused`, `rollback_opened`,
      `events_rotated`, `infra_flake_rerun`,
      `lesson_draft_emitted`, `prompts_pin_changed`,
      `lesson_promoted`, `trainee_pr_opened`,
      `quiet_hours_skip`, `prompts_reverted`, `ship_resumed`,
      `lessons_pruned`, `vacation_skip`,
      `vacation_returned`, `self_check_failed`. Test asserts
      every type in AGENTS.md has a matching catalog entry
      via `grep -E '^[[:space:]]+- \`([a-z_]+)\`' AGENTS.md`
      against `grep -E '^tour_catalog_([a-z_]+)\(\)
      \{' lib/tour-catalog.sh`.
- [ ] `scripts/check-tour-catalog.mjs` is a NEW gate wired
      into the `validate` CI job. Fails when AGENTS.md
      defines an event type with no matching
      `tour_catalog_*` function in `lib/tour-catalog.sh`.
      The gate is the same shape as
      `scripts/check-backlog.mjs` and
      `scripts/check-prompts-changelog.mjs`. Test asserts
      via a fixture AGENTS.md with an unknown event type.
- [ ] The render walks events.jsonl in chronological order
      and prints one annotated block per event:
      `[<idx>] <ts>  <type> {<fields>}` (the raw event line)
      followed by 2-3 sentences of plain-English gloss and
      one line `Why this event exists: P-<N> (<short
      principle title>). <one-line elaboration>.` per the
      User-lens example. Test asserts the render via
      fixture events.jsonl.
- [ ] Consecutive duplicate-type events with byte-identical
      bodies are FOLDED into a single annotated block with
      `× <N> occurrences (<first_ts> → <last_ts>)`. Test
      asserts via fixture with 4 identical `infra_flake_rerun`
      events.
- [ ] The "what to read next" footer is composed from the
      events the operator's tour just covered: if any
      `lesson_draft_emitted` fired, suggests `fleet
      lessons-promote`; if any `ship_paused` fired, suggests
      `fleet resume`; if any `infra_flake_rerun` fired,
      suggests `fleet incident`; the daily three (`fleet
      morning`, `fleet streak`, `fleet doctor`) are always
      suggested. Test asserts each conditional via fixtures
      that exercise each event type.
- [ ] `bin/fleet tour --archive` ALSO walks
      `events.jsonl.archive/*.jsonl` files (from ticket 0016
      rotation) in chronological order before the live file.
      The archive walk shows a `--- archive boundary ---`
      separator between each archive segment. Test asserts
      via fixture archive directory.
- [ ] `bin/fleet tour --type <name>` filters to one event
      type (e.g. `--type lesson_draft_emitted` walks only
      lesson drafts across the whole channel). Useful for
      an experienced operator who wants to deep-read one
      type without re-reading the rest. Test asserts.
- [ ] `bin/fleet tour --json` emits one JSON object per
      annotated event: `{"idx": <int>, "ts": "<iso>",
      "type": "<name>", "fields": {<original>},
      "principle_id": "P-<N>", "principle_title":
      "<text>", "gloss": "<text>", "why_exists": "<text>",
      "fold_count": <int>}`. JSON escape via
      `preflight_json_escape` per LESSONS 2026-06-03.
      Test asserts JSON validity via Node.
- [ ] `bin/fleet tour --help` prints USAGE mentioning the
      optional repo arg, `--archive`, `--type`, `--json`.
      Test asserts via `grep -qF -- "$kw" "$help_out"` per
      LESSONS 2026-05-30. Help block ends with `exit 0`.
- [ ] Empty events.jsonl (file exists but is zero bytes)
      prints `tour: events.jsonl is empty. wait for the
      next \`:37\` ship cycle, or run \`fleet kickstart
      --demo\` to generate a synthetic cycle.` exit 0.
      Test asserts.
- [ ] Unknown event type in the events.jsonl (a type
      AGENTS.md documents but `tour-catalog.sh` is missing —
      should be impossible under the gate but defended for
      malformed files) prints `[<idx>] <ts>  <type>
      {<fields>}` plus `Why this event exists: not in the
      catalog yet (probably a prompts revision newer than
      this kit). file an issue or run \`fleet tour --json\`
      to inspect raw.` and continues. Test asserts via
      fixture event with unknown type.
- [ ] `bin/fleet tour` is a PURE READER. NO `events.jsonl`
      writes, NO `fleet_emit_event` calls. Test asserts the
      kit's events channel has unchanged byte size before
      and after invocation.
- [ ] `lib/common.sh` — NO changes. Test asserts via `git
      diff --name-only main…HEAD -- lib/common.sh` returns
      empty.
- [ ] `prompts/` — NO changes (the principle text is
      QUOTED into `lib/tour-catalog.sh`, not re-read at
      runtime). Test asserts via `git diff --name-only
      main…HEAD -- prompts/` returns empty.
- [ ] `tests/tour.sh` covers all 14 boxes above using
      `$HOME/.local/bin` stubs per LESSONS 2026-05-26.
      Fixture `events.jsonl`, `events.jsonl.archive/`,
      and one fixture `AGENTS.md` (for the
      check-tour-catalog gate) live under
      `tests/fixtures/tour/`. Per LESSONS 2026-05-27
      backup/restore via `cp`. Counts use `awk … END
      { print n+0 }` per LESSONS 2026-06-01. Run-time
      budget: <8s.

## Out of scope

The dev agent will NOT do these even if they seem related.

- An INTERACTIVE tour (prompts the operator for input,
  pages through events). v1 is single-shot text output. An
  interactive mode is v2 if asked.
- A WEB-based tour (HTML/CSS rendered in a browser).
  Shell-only kit; HTML is out of scope.
- Translating the gloss into other languages. v1 is
  English only.
- Walking the kit's `runs.jsonl` (cost data). v1 walks
  `events.jsonl` only. A `fleet tour --runs` for the cost
  channel is v2.
- Walking `prompts/CHANGELOG.md` (ticket 0013 territory)
  or `docs/LESSONS.md`. v1 is events-only.
- A `--play` mode that animates the tour at human-readable
  speed (line per second). v1 is one-shot dump; pacing is
  v2.
- Auto-running `fleet tour` at the end of `fleet onboard`
  (0011). v1 is operator-pull only — the operator should
  CHOOSE to take the tour, not be force-fed it.
- A diff mode comparing this slug's tour to another's
  (`fleet tour --vs <slug>`). v1 is single-slug; cross-slug
  is `fleet diff` (0038)'s pattern, separate ticket.
- Auto-folding the catalog into `AGENTS.md § Telemetry`
  itself (making PRINCIPLES.md cross-references part of
  the static doc). v1 keeps the catalog in
  `lib/tour-catalog.sh` so AGENTS.md stays the contract,
  not the docs.
- Sourcing `lib/tour-catalog.sh` from any runner
  (`ship.sh`, `eng.sh`, `groom.sh`, `review.sh`). v1
  keeps it loaded ONLY by `bin/fleet tour` to keep the
  runtime hot path unaffected.
- A launchd schedule. Operator-invoked only.

## Engineering notes

Files / patterns the dev should touch.

- `bin/fleet` — new `tour()` dispatcher function placed near
  the existing `kickstart()` block (find via `grep -n
  '^kickstart()' bin/fleet`). Per LESSONS 2026-05-26
  (`tail` shadow) `tour` does not collide with any
  coreutils binary.
- `bin/fleet` — five helpers, ALL defined ABOVE the
  dispatcher block per LESSONS 2026-06-05 (forward-
  reference trap):
  - `tour_discover_target` — resolves the target slug's
    `events.jsonl` path. With no arg, walks
    `agents.config.sh` in the kit checkout itself.
  - `tour_walk_events` — reads events.jsonl line by
    line, deduplicates consecutive identical bodies per
    AC #5, emits one TSV row per annotated block. Per
    LESSONS 2026-06-08 the awk script declares `BEGIN
    { count = 0 }`. Per LESSONS 2026-06-08 IFS=$'\t'
    middle-empty-field, uses `-` sentinel.
  - `tour_lookup_catalog` — given an event type,
    sources `lib/tour-catalog.sh` (once per process)
    and dispatches to the matching `tour_catalog_<type>`
    function. The catalog functions echo a 3-field
    TAB-separated record. Per LESSONS 2026-06-05
    (export-in-subshell trap), the source happens at
    the top of `tour()`, not inside `$(...)`.
  - `tour_compose_footer` — given the set of event
    types seen in this walk, composes the
    "what to read next" footer per AC #6. Per LESSONS
    2026-05-28 every printf goes through
    `printf -- '%s'`.
  - `tour_render_text` and `tour_render_json` —
    formatters. Width via `preflight_visible_width`
    per LESSONS 2026-06-05; JSON escape via
    `preflight_json_escape` per LESSONS 2026-06-03.
- `bin/fleet` — `tour()` end-state must be `exit 0` on
  every code path per LESSONS 2026-06-01.
- `bin/fleet` — dispatcher block: `if [ "$CMD" =
  "tour" ]; then tour "$@"; fi`. Place AFTER the
  `kickstart` dispatcher.
- `bin/fleet` — help banner block at the top of the
  file gets a new line: `fleet tour walk events.jsonl
  with PRINCIPLES.md annotations`. README "Daily ops"
  code block gets the same line.
- `lib/tour-catalog.sh` — NEW file under `lib/`. ONE
  shell function per event type (`tour_catalog_<type>()`)
  echoing `principle_id<TAB>gloss<TAB>why_this_event_
  exists`. Header comment cites that every event in
  `AGENTS.md § Telemetry` must have a matching function
  AND that the `check-tour-catalog.mjs` gate enforces
  this. NEVER sourced from any runtime runner (the
  hot-path stays as-is) — only from `bin/fleet tour`.
- `scripts/check-tour-catalog.mjs` — NEW gate.
  Reads `AGENTS.md`, extracts the event-type list,
  reads `lib/tour-catalog.sh`, asserts every event
  type has a matching `tour_catalog_<type>()`
  function. Exit 1 on mismatch with a clear list
  of missing types. Wired into the `validate` job.
- `.github/workflows/ci.yml` — `validate` job gets
  one new line invoking
  `node scripts/check-tour-catalog.mjs` next to the
  existing `check-backlog.mjs` invocation.
- `AGENTS.md` — NO content change. The file IS the
  source of truth that the gate reads.
- `prompts/` — NO changes (the principle TITLES are
  quoted into `lib/tour-catalog.sh` as static strings,
  not re-read at runtime).
- `lib/common.sh` — NO changes.
- `tests/fixtures/tour/` — NEW directory under
  `tests/fixtures/` holding `events.jsonl` files
  covering the test scenarios above plus a fixture
  `AGENTS.md` with a deliberately-missing event type
  for the check-tour-catalog gate test.
- `tests/tour.sh` — top of file mirrors
  `tests/onboarding-check.sh` (the closest prior
  ticket). Stubs `node` under `$HOME/.local/bin` per
  LESSONS 2026-05-26 for the
  `scripts/check-tour-catalog.mjs` gate test. Counts
  use `awk … END { print n+0 }` per LESSONS
  2026-06-01. Per LESSONS 2026-05-27 backup/restore
  via `cp`. The clock is frozen via
  `FLEET_NOW_OVERRIDE`. Run-time budget: <8s.
- New deps: none. Pure shell + awk + Node
  (already a kit dep for the validate job).
- Public API: additive — `bin/fleet tour` is a new
  subcommand, `lib/tour-catalog.sh` is a new file
  loaded ONLY by `bin/fleet tour`. ZERO new event
  types, ZERO event writes.
- BREAKING flag: NO. PR body affirms "pure reader,
  no events.jsonl writes, no `fleet_*` signature
  changes, no runtime hot-path changes."
- Reinstall required: NO. `lib/common.sh`,
  `lib/ship.sh`, `lib/eng.sh`, `lib/groom.sh`,
  `lib/review.sh` are untouched. `lib/tour-catalog.sh`
  is new but loaded only by the operator-invoked
  `bin/fleet tour` (the runtime runners never source
  it).
- LESSONS to defend against: 2026-05-25 (README
  "Daily ops" code block addition), 2026-05-26
  (`tail` shadow), 2026-05-26 (PATH reset — stubs in
  `$HOME/.local/bin`), 2026-05-27 (`$(cat)` trap),
  2026-05-28 (printf leading-dash — every event-type
  printf goes through `printf -- '%s'`), 2026-05-30
  (`grep -F --` trap), 2026-06-01 (`grep -c file ||
  echo 0` double-print), 2026-06-01 (dispatcher
  fall-through), 2026-06-03 (UTF-8 sign-extension —
  JSON escape via `preflight_json_escape`),
  2026-06-05 (dispatcher forward-reference),
  2026-06-05 (bash 3.2 LC_ALL caching), 2026-06-05
  (export-in-subshell trap — `tour_catalog_*`
  source happens at function-entry, not inside
  `$(...)`), 2026-06-08 (awk empty-string-key — the
  walk awk script declares `BEGIN { count = 0 }`),
  2026-06-08 (IFS=$'\t' middle-empty-field —
  sentinel for missing fields), 2026-06-11 (BSD
  `date -j -f` fills missing time fields with
  NOW-of-day — every chronological compare uses
  ISO8601 lex-compare).
- This ticket compounds 0011 (`fleet onboard` — the
  prerequisite the tour assumes ran), 0016
  (`events_rotated` — the archive walk reads the
  rotated-out files), 0018
  (`prompts/PRINCIPLES.md` — the principles being
  cited), 0023 (`fleet kickstart --demo` — the
  credential-less predecessor whose synthetic
  cycle the tour can also walk), 0041 (`fleet
  onboarding-check` — the verifier that runs
  before the tour). Per P-1 the diff is small:
  ~250 lines of `tour_*` helpers + ~200 lines of
  `lib/tour-catalog.sh` (one function per event
  type) + ~80 lines of `check-tour-catalog.mjs`
  + ~250 lines of test + 5 fixture files +
  one help-text line + one README line.

## Implementation log

- 2026-06-13: `implementation-dev` started on `feat/0050-fleet-tour`. Plan: write
  failing `tests/tour.sh` (14 AC blocks) first, then add `bin/fleet tour` +
  helpers ABOVE the dispatcher (LESSONS 2026-06-05), `lib/tour-catalog.sh`
  (one function per AGENTS.md event type), `scripts/check-tour-catalog.mjs`
  (validate-gate parity), and the CI wire-up. Pure reader. No
  `*_json_escape` wrapper (LESSONS 2026-06-13) — call
  `preflight_json_escape` directly.
- 2026-06-13: PR #104 merged via auto-merge on green CI (shellcheck +
  validate both pass). All 15 AC boxes covered by `tests/tour.sh` in
  ~7.7s. `FLEET_SELF_CHECK_GATE=1 bin/fleet self-check` stayed at the
  3-hit on-main baseline (no `*_json_escape` wrapper added). The
  `check-tour-catalog` validate step now gates every future PR that
  touches `AGENTS.md § Telemetry` to also update
  `lib/tour-catalog.sh`.
