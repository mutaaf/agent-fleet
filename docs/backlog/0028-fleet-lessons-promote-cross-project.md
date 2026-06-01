---
id: 0028
title: fleet lessons-promote curates a local lesson into the cross-project feed
status: groomed
priority: P1
area: engine
created: 2026-06-01
owner: gtm-innovation
---

## User story

As a fleet operator who just promoted a draft lesson in
`docs/LESSONS.md` of one project and recognized that the same trap
will bite my OTHER projects (a `printf '-foo'` flag-parsing trap, a
`gh pr create --head` quirk, a `node:sqlite` narrowing rule), I want
`bin/fleet lessons-promote <slug> --lesson "<headline-substring>"
[--scope <slug-or-all>]` to copy that one paragraph from the source
project's LESSONS.md and append it (or replace its match) in
`~/.local/share/agent-fleet/CROSS_LESSONS.md` so that the very NEXT
run of any other fleet project picks it up at PHASE 0 — instead of
waiting for `fleet lessons-sync` (ticket 0009) to do a wholesale,
opinionated, dedup-aware rebuild, OR worse, waiting for the other
project to re-learn the same lesson on its own runtime.

## Why now (four lenses)

### Product Owner
`fleet lessons-sync` (0009) is one direction and one shape: it
RE-BUILDS `CROSS_LESSONS.md` from every project's LESSONS.md as a
deduped, demoted-heading concatenation. It is correct and complete
but it is also OPINIONATED — every promoted lesson from every
project shows up. That is the right default for an automated sync.
What is missing is the operator's CURATION pass: "this one specific
lesson is worth pushing NOW; this other one is local-only noise."
`lessons-promote` is the smallest meaningful curation primitive:
one operator decision per lesson, one append, one immediate effect
(the next run of every other project reads the new line at PHASE 0).
Subtraction: the operator stops waiting for the next `lessons-sync`
cron cycle to see a specific lesson reach the cross-project channel,
AND they get a knob to push only the lessons they think generalize.

### Stakeholder
This widens the moat in a precise way the existing surfaces do not.
The cross-project LESSONS file is the kit's single most leveraged
artifact — it is the substrate every project's PHASE 0 reads, and
the substrate that makes the kit's "the loop reads LESSONS and gets
better" claim concrete. Today the operator's only control over what
goes in is "edit the source LESSONS.md and wait for sync." With
`lessons-promote`, an explicit operator promotion becomes a typed
event the rest of the kit can build on (`lesson_promoted {source,
text_sha, scope}`) — future tickets can score which promotions
correlated with send-back rate dropping, or surface "you promoted
this but no other project read it yet" debt. This is also the first
ticket that gives the operator a WRITER role into the cross-project
channel; until now the cross-project channel was a READER's tool.
That asymmetry was a gap. Closing it is moat-deepening: the kit now
treats the operator as a first-class participant in cross-fleet
knowledge, not just a passive consumer of automated dedup.

### User (operator just finished promoting a draft for `agent-fleet`)
Just merged a `feat/0029-...` PR. The promotion added a lesson titled
`grep -qF "--flag" treats the pattern as an option too` to
`docs/LESSONS.md`. They recognize this exact trap will bite courtiq's
test suite next week. They run:

```
$ fleet lessons-promote agent-fleet --lesson "grep -qF"
fleet lessons-promote: matched 1 lesson in /Users/.../agent-fleet/docs/LESSONS.md
  ## 2026-05-30 — grep -qF "--flag" treats the pattern as an option too
appending to /Users/.../.local/share/agent-fleet/CROSS_LESSONS.md (scope=all)
emitted lesson_promoted source=agent-fleet text_sha=8c20ae… scope=all
done — every project's next PHASE 0 will read this lesson.
```

They check `CROSS_LESSONS.md` — the lesson is appended under
`## agent-fleet` (the existing section per the sync convention), with
a `<!-- promoted by operator 2026-06-01 -->` marker. Confidence:
"I just shortened the half-life of this trap from weeks to one run."
No CI cycle, no PR. The kit's cross-project knowledge layer just got
a new line because the operator decided it should.

### Growth
"You can promote a lesson once and the whole fleet picks it up at the
next run" is the kind of story that makes the kit feel like a small
governed knowledge platform instead of a launchd wrapper. A friend
running their own loop sees the workflow — local lesson → operator
curation → cross-fleet broadcast → telemetry-traceable promotion —
and immediately understands why the kit's LESSONS layer is
load-bearing. It also flips the kit's positioning from "automation
that reads lessons" to "lessons that automation reads, curated by the
operator." That is the more durable claim.

## Acceptance criteria

Each box maps 1:1 to a test scenario in `tests/lessons-promote.sh`.

- [ ] `bin/fleet lessons-promote <slug> --lesson "<substring>"`
      (no other flags) defaults to `--scope all`, exits 0 on a
      single match, and appends the matched lesson paragraph
      (heading + body, ending before the next `## ` or EOF) to
      `~/.local/share/agent-fleet/CROSS_LESSONS.md` under the
      slug's existing `## <slug>` section, BEFORE that section's
      next sibling `## ` header. Test fixtures a LESSONS.md with
      three lessons, one matching `<substring>`, and asserts the
      appended block lands under the right section in the right
      order.
- [ ] When the slug section does not yet exist in CROSS_LESSONS.md,
      `lessons-promote` creates the `## <slug>` section at the end
      of the file (preserves any trailing newline) and appends the
      lesson under it. Test asserts the section-creation branch.
- [ ] When the SAME lesson body (by SHA of normalized paragraph
      text) is already present in CROSS_LESSONS.md under the same
      `## <slug>` section, the command is a no-op: exits 0, prints
      `fleet lessons-promote: lesson already present in
      CROSS_LESSONS.md (sha=<short-sha>) — no change.`, does NOT
      append a duplicate, does NOT emit a `lesson_promoted` event.
      Test asserts the idempotent branch.
- [ ] When the lesson body matches under a DIFFERENT slug section
      (e.g. the operator is promoting a lesson agent-fleet
      first-learned but courtiq also has), the command appends a
      `> Already seen under ## <other-slug>` reference line under
      the source slug's section AND still emits the event with the
      `dup_under` payload key set to the other slug. Mirrors the
      dedup convention `fleet lessons-sync` (0009) already uses.
      Test asserts the cross-section dedup branch.
- [ ] `--scope <slug>` (instead of `--scope all`) limits the
      append to ONE consumer project's view by writing the lesson
      to `~/.local/share/agent-fleet/projects/<scope-slug>/
      CROSS_LESSONS.md.override` instead of the shared file. The
      consumer project's PHASE 0 reads the override-suffixed file
      AFTER the main file if it exists. (Override read is the
      project's responsibility — this ticket only writes the
      file; integrating PHASE 0 to read it is OUT OF SCOPE for v1,
      per Out of scope below.) Test asserts the override file
      lands at the right path with the right content.
- [ ] `--scope` accepts the special value `all` (the default) and
      any slug discovered under `FLEET_DISCOVERY_ROOT`. Unknown
      scope: `lessons-promote: no project with SLUG=<scope> found
      under <root>` to stderr, exit 2. Test asserts the error
      branch.
- [ ] Lesson match: `--lesson "<substring>"` does a
      case-INSENSITIVE substring match against the LESSON HEADLINE
      (the `## YYYY-MM-DD — <headline>` line). Match against body
      text is NOT supported v1 — operators are expected to identify
      a lesson by its title. Zero matches: `lessons-promote: no
      lesson matched "<substring>" in <path>` to stderr, exit 2.
      Multiple matches: `lessons-promote: <N> lessons matched
      "<substring>" in <path>; refine the substring or use
      --headline-exact "<full headline>"` to stderr, exit 2 (the
      command refuses to guess). Test asserts all three branches
      (single, zero, multiple).
- [ ] `--headline-exact "<full headline>"` is a stricter alternative
      to `--lesson <substring>` that matches the FULL headline text
      (after `## YYYY-MM-DD — `) exactly. Useful when the substring
      would be ambiguous. Test asserts an exact-match branch.
- [ ] `--dry-run` flag: print the proposed append (lesson body +
      target path + scope) to stdout, do NOT write any file, do NOT
      emit any event, exit 0. Test asserts no file mutation on
      `--dry-run`.
- [ ] Telemetry: a NEW event `lesson_promoted {source, text_sha,
      scope, dup_under?}` is added to `AGENTS.md § Telemetry`.
      `source` is the slug whose LESSONS.md was the source.
      `text_sha` is the short SHA (first 8 chars of
      `shasum` on the normalized paragraph). `scope` is `all`
      or the consumer slug. `dup_under` is optional and present
      only when the cross-section dedup branch fires. The event
      carries `phase=promote`. The PR body appends the event in
      the same style as the existing entries in
      `AGENTS.md § Telemetry`. Test asserts the event lands in the
      SOURCE project's `$CACHE_DIR/events.jsonl` (NOT a global
      one — the project is the unit of telemetry per P-6) and
      carries the right payload.
- [ ] `tests/lessons-promote.sh` covers all ten boxes using
      `$HOME/.local/bin` stubs (per LESSONS 2026-05-26) for any
      command shelled out to. `FLEET_DISCOVERY_ROOT` redirected
      to `tests/fixtures/lessons-promote/`. The CROSS_LESSONS.md
      target is also redirected via a NEW
      `FLEET_CROSS_LESSONS_ROOT` env var (default
      `$HOME/.local/share/agent-fleet`) so the test does not
      mutate the host's real cross-lessons file. Asserts via
      golden file `tests/fixtures/lessons-promote.cross.golden.md`
      for the post-promote CROSS_LESSONS.md content. Per LESSONS
      2026-05-27, the test uses `cp` for backup/restore of any
      host file it touches — never `$(cat …)`. Run-time budget:
      <10s.

## Out of scope

The dev agent will NOT do these even if they seem related.

- Reading the override file from PHASE 0 of the consumer project.
  This ticket only WRITES the override file. Wiring PHASE 0 to
  layer the override on top of CROSS_LESSONS.md is a follow-up
  ticket — both because it touches `lib/` and `prompts/` (forcing
  a fleet-wide reinstall), and because v1 should let operators
  exercise the WRITE flow before the READ flow lands and adds
  another moving piece. (The `--scope all` path DOES land
  immediately because the main CROSS_LESSONS.md is already read.)
- Auto-promoting every promoted draft. The operator picks which
  lessons cross over — that is the entire point. An auto-pipe
  would defeat the curation primitive.
- Demoting a lesson (removing it from CROSS_LESSONS.md). v1 is
  append-only. A future `fleet lessons-demote` is a sibling
  ticket if anyone ever needs it.
- Editing the LESSON body during promotion. The text is copied
  byte-exact. Operators who want to reword promote with the
  reworded text already in their source LESSONS.md.
- Auto-running `fleet lessons-sync` afterwards. Sync is a
  separate operator action with its own semantics (full rebuild
  + dedup annotations). `lessons-promote` is the FAST path; sync
  is the SLOW canonical path. They coexist.
- A GUI / fleet-control button. The CLI is the contract;
  fleet-control can add a button later that shells out.
- Cross-promoting at install time. install.sh is for plumbing;
  promotion is for content. Mixing them would conflate two
  unrelated lifecycles.

## Engineering notes

Files / patterns the dev should touch. Specific enough that the dev
doesn't have to re-discover the architecture.

- `bin/fleet` — new `lessons_promote()` dispatcher next to
  `lessons_sync()` (line ~4322). Pattern lifts from `lessons_sync`:
  same discovery, same source-LESSONS path resolution
  (`$PROJECT_DIR/docs/LESSONS.md` then `$PROJECT_DIR/LESSONS.md`
  per the existing fallback at line ~4621).
- `bin/fleet` — three helpers:
  - `lessons_promote_extract_paragraph()` — reads the source
    LESSONS.md, finds the matching `## ` heading, captures up to
    the next `## ` (or EOF). Awk one-pass. Output is the paragraph
    body including the heading line.
  - `lessons_promote_paragraph_sha()` — normalizes whitespace
    (collapse runs of blank lines into one, strip trailing
    whitespace per line) and shas the result. First 8 chars of
    `shasum | awk '{print $1}'` — same convention as
    `prompts-score`'s SHA short-form (ticket 0024).
  - `lessons_promote_target_path()` — resolves the destination
    given `--scope`: either
    `${FLEET_CROSS_LESSONS_ROOT:-$HOME/.local/share/agent-fleet}/
    CROSS_LESSONS.md` (scope=all) or
    `${FLEET_CROSS_LESSONS_ROOT}/projects/<scope>/
    CROSS_LESSONS.md.override` (scope=slug).
- `bin/fleet` — `lessons_promote_insert_under_section()` opens the
  target file, locates the `## <source-slug>` heading (or creates
  it at EOF), and inserts the paragraph BEFORE the next sibling
  `## ` heading. The insertion is awk-based, NOT sed-based, to
  defend against the LESSONS 2026-05-27 trailing-newline trap. The
  edit writes to a temp file then `mv -f` over the target.
- `lib/common.sh` — NO changes to the public API. But: this
  ticket adds a small **typed event emission** (`lesson_promoted`)
  via the existing `fleet_emit_event` helper — no new helper
  function. The emission is INSIDE `bin/fleet`, not `lib/`. The
  emit path sources `lib/common.sh` (the existing pattern
  `bin/fleet` uses via the kit-root resolution at line ~109).
  Result: NO `fleet_*` signature changes; NO new helper functions
  in common.sh.
- `AGENTS.md` — append a new entry under `## Telemetry`:
  `lesson_promoted {source, text_sha, scope, dup_under?}` —
  emitted by `bin/fleet lessons-promote` once per successful
  promotion (idempotent dedup branches do NOT emit). Carries
  `phase=promote`. Payload: `source` = source slug;
  `text_sha` = 8-char SHA of normalized paragraph; `scope` =
  `all` or consumer slug; `dup_under` = optional, present only
  when the cross-section dedup branch fires.
- `prompts/` — NO changes. The command is operator-facing only;
  PHASE 0 wiring is OUT OF SCOPE (see Out of scope above). The
  follow-up ticket (sibling to this one) will be the one that
  touches `prompts/` and triggers a fleet-wide reinstall.
- `tests/fixtures/lessons-promote/` — NEW directory under
  `tests/fixtures/` holding:
  - one synthetic `<slug>/agents.config.sh` per project the test
    references
  - one `<slug>/docs/LESSONS.md` per project, each containing 2-3
    canned lessons with the date/headline shape the matcher reads
  - one starting `CROSS_LESSONS.md` to exercise the
    section-exists branch
  - the golden file the test diffs against
- `tests/lessons-promote.sh` — top of file mirrors
  `tests/lessons-sync.sh`: `mktemp -d` under `$HOME`, redirect
  `FLEET_DISCOVERY_ROOT` and the new `FLEET_CROSS_LESSONS_ROOT`,
  `cp` everything from the fixtures dir into the tmp, run
  `bin/fleet lessons-promote` with each AC's flag set, diff
  against the golden. The event-assertion box (AC#10) reads the
  source project's `events.jsonl` and asserts the JSON line by
  parsing with `node -e 'JSON.parse(...)'`.
- `bin/fleet` — help banner block at the top of the file gets a
  new line: `fleet lessons-promote <slug> --lesson "<title>"
  curate one lesson into cross-fleet`. README "Daily ops" code
  block gets the same.
- New deps: none. Pure shell + awk + the existing
  `fleet_emit_event` helper (already shell-only per ticket 0002).
- Public API: `fleet_*` signatures unchanged. ONE new event type
  added to AGENTS.md § Telemetry — consumers MUST tolerate
  unknown types per the existing contract, so this is additive,
  not breaking.
- BREAKING flag: NO. PR body affirms "no `fleet_*` signature
  changes" and explicitly names the new event type so the
  reviewer's telemetry-contract check passes.
- Reinstall required: NO. `lib/` and `prompts/` are untouched.
  (The follow-up PHASE 0 wiring ticket WILL require reinstall;
  flagging here so the operator knows what to expect when the
  sibling lands.)
- LESSONS to defend against: 2026-05-26 (`tail` shadow — `promote`
  is not a coreutils binary; safe to name the dispatcher).
  LESSONS 2026-05-27 (`$(cat file)` strips trailing newlines — the
  insertion path uses awk + `mv`, never `$(cat …)`). LESSONS
  2026-05-28 (`printf '-…'` trap — the `--lesson` value can start
  with `-` after a leading-dash project name; quote via `printf
  -- '%s'`). LESSONS 2026-05-30 (`grep -F --` flag trap — the
  substring matcher uses `grep -iF -- "$needle"`).
- This ticket compounds 0002 (events.jsonl + fleet_emit_event),
  0009 (lessons-sync's section/dedup conventions), 0022
  (lesson_draft_emitted — the upstream "this might be a lesson"
  signal that often precedes a promotion). It introduces ONE
  new event type and ZERO `lib/` changes. Per P-1 the diff is
  small: ~250 lines of `lessons_promote*` helpers + ~120 lines
  of test fixture content + one AGENTS.md line + one help-text
  line.

## Implementation log

(Appended by the implementation-dev agent during execution.)
