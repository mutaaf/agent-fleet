---
id: 0045
title: fleet prompts-suggest proposes PRINCIPLES.md additions from recurring lesson_draft clusters
status: groomed
priority: P1
area: governance
created: 2026-06-11
owner: gtm-innovation
---

## User story

As the operator of a fleet that has been emitting `lesson_draft_emitted`
events for weeks (ticket 0022) and curating them into LESSONS.md via
`lessons-promote` (0028) and out via `lessons-prune` (0039), but whose
`prompts/PRINCIPLES.md` (the constitutional layer from ticket 0018) has
NOT been updated in the same period despite the loop clearly having
new things to remember, I want `bin/fleet prompts-suggest` to read the
last N days of `lesson_draft_emitted` events across the whole fleet,
cluster recurring headlines, and propose ONE COPY-PASTEABLE
draft addition to `PRINCIPLES.md` (or an EXPIRES marker for an existing
principle that's been superseded), so that the operator can promote
hard-won operational memory from "ephemeral LESSONS.md prose" to
"durable PRINCIPLES.md doctrine" without re-reading 6 weeks of events
by hand.

## Why now (four lenses)

### Product Owner
The kit's self-improvement loop is currently HALF-CLOSED:
- `lesson_draft_emitted` events FLOW from reviewer send-backs (ticket
  0022).
- `lessons-promote` (0028) MOVES them into the cross-project feed.
- `lessons-prune` (0039) ARCHIVES the stale ones.
- BUT no surface exists for the next step: "which of these recurring
  draft headlines is no longer a one-off — it's a principle the loop
  should have known from day one?"

`PRINCIPLES.md` was ticket 0018's bet that the LOOP's behavioral
doctrine should be a tiny set of P-N items every agent cites, NOT
the full LESSONS scroll. But the doctrine has no UPDATE mechanism
— since 0018 shipped on 2026-05-27, the file has been static while
LESSONS.md has grown from ~7 entries to ~30. Some of those LESSONS
are obviously one-shot traps (the printf leading-dash one is a
shell-specific footgun, not a principle); others recur often enough
that they probably belong in the doctrine itself. The operator has
no read that distinguishes the two.

The smallest meaningful unit of value is one command, one suggestion,
one operator decision (accept/reject):

```
fleet prompts-suggest --since 30d

prompts-suggest: 3 candidate additions found in the trailing 30d.

[1] FREQUENCY 7 events · agent-fleet (4) · courtiq (3)
    HEADLINE: "test wrote to a non-isolated path"
    PROPOSED ADDITION TO PRINCIPLES.md:
      ## P-13 — Tests own their own filesystem
      Every test creates its working tree under `mktemp -d` AND
      restores any host-side mutation on cleanup. No test reads
      or writes outside its tmpdir. Cite this principle in heal
      commits when a test pollutes shared state.

[2] FREQUENCY 5 events · agent-fleet (5)
    HEADLINE: "subcommand fell through to default status block"
    SUPERSEDES: P-N/A (this is a new principle)
    PROPOSED ADDITION TO PRINCIPLES.md:
      ## P-14 — Every subcommand function ends with explicit exit
      The bin/fleet dispatcher's inline `if [ "$CMD" = "..." ]
      ; then sub "$@"; fi` pattern falls through to the default
      `status` rendering when a subcommand returns without
      exiting. Every subcommand function MUST end with `exit 0`
      on success and `exit N` on every error path.

[3] FREQUENCY 4 events · digitalcraft (4)
    HEADLINE: "agent assumed claude CLI was on PATH"
    PROPOSED EXPIRES on existing principle:
      ## P-6 — telemetry is the source of truth
      <!-- EXPIRES: 2026-09-01 -->
      (reason: every recent send-back citing P-6 actually
       points to a missing-CLI assumption, not a telemetry
       miss. EXPIRES candidate; consider new P-N specifically
       for "the runner verifies its tool surface before
       phase 0.")

next: open prompts/PRINCIPLES.md, paste candidate [1], commit on
      a chore/prompts-principles-2026-06-11 branch.
```

Subtraction: the operator stops doing the manual "let me grep
the events channel for headlines that come up a lot" pattern-
matching. The kit IS the pattern-matcher.

Per P-5 (operator confidence over feature richness), the win is
NOT that the kit auto-edits PRINCIPLES.md (that would violate
the doctrine "principles are operator-authored"). The win is
the kit COMPOSES the candidate addition so the operator's
choice is paste/don't paste, not write-from-scratch.

### Stakeholder
This is **moat-deepening on the self-improvement axis** — the
kit's first surface that closes the feedback loop from
"agent observed a failure" → "loop's constitutional doctrine
changed" without the operator hand-curating the bridge. Every
other surface ENDS at LESSONS.md (the ephemeral memory); this
one PROMOTES from LESSONS.md to PRINCIPLES.md (the durable
doctrine).

Per P-6 (telemetry is the source of truth), the suggestion
algorithm is a PURE READER of `lesson_draft_emitted` events
across every discovered slug. The clustering is:
1. Walk every `lesson_draft_emitted` event in the window.
2. Group by normalized headline (lowercase, strip
   leading PR number, collapse whitespace).
3. Filter to groups with ≥3 occurrences (the v1 recurrence
   threshold; configurable via `--threshold N`).
4. For each cluster, compose a candidate principle block:
   - Headline normalized into a short imperative title.
   - Body taken from the most-recent LESSON paragraph
     whose first line matches the cluster's normalized
     headline (cite the LESSON, don't paraphrase).
   - Cluster frequency + per-slug breakdown.
5. ALSO scan existing `PRINCIPLES.md` for principles that
   recent send-backs OVERWHELMINGLY MIS-CITE (P-N appears
   in send-back bodies but the headline doesn't match the
   principle's intent) and propose an EXPIRES marker.

Per P-1 (smallest viable change), the diff is the cluster +
compose pipeline. The render is text-only for v1; the JSON
mode is one composer reformatter.

Compounds 0018 (`prompts/PRINCIPLES.md` — the destination
file), 0022 (`reviewer-sendback-drafts-lesson-skeleton` —
the event source), 0024 (`fleet prompts-score` — the
prompts-revision timeline contextualizes which
PRINCIPLES.md changes worked), 0028 (`fleet
lessons-promote` — the prior step in the promotion
chain), 0039 (`fleet lessons-prune` — the EXPIRES-marker
mechanism this command reuses).

Per P-3 (heal in-flight before new work),
`prompts-suggest` is read-only and cheap (~one events.jsonl
read per slug, ~5 slugs typical) — never blocks heal work.

### User (operator on a Saturday afternoon, deciding what
to update in PRINCIPLES.md before the next month)
Operator has been postponing "review PRINCIPLES.md" for
three weeks because the question "what should change?" is
the hard part — writing the prose is easy. Runs
`fleet prompts-suggest --since 30d`. Sees three candidates.
Reads candidate [1] (test-own-its-filesystem). Decides:
"yes, P-13 is real; I've seen this fail four times this
month." Opens `prompts/PRINCIPLES.md`. Pastes the candidate
verbatim. Commits on `chore/prompts-principles-2026-06-11`.
Per LESSONS 2026-05-25 `prompts/` changes need a fleet-wide
reinstall — the commit body says `Reinstall: all projects`.
Done in 15 minutes; would have taken an hour of grepping
events.

Per P-5, the win is converting "what should the doctrine
say?" from a 1-hour synthesis task into a 15-minute
edit task.

### Growth
A friend running their own claude loop reads about this
command and immediately sees the kit's bet on
PROMPT-EVOLUTION as a first-class operator surface. Most
autonomous-coding kits treat prompts as static config;
this one treats them as a living, version-pinned,
ROI-graded, operator-curated artifact. The promotion
chain `event → LESSONS draft → LESSONS final →
PRINCIPLES candidate → PRINCIPLES principle` is unique
to this kit.

The acquisition path so far covers "see the loop"
(kickstart --demo), "install the loop" (onboard +
preflight + onboarding-check), and "trust the loop"
(pr-footer from ticket 0044). This ticket adds the
fifth: "the loop improves itself, and here's how."
That's the moment a power-user-shaped operator commits
to the kit over rolling their own.

Per the brief's "Self-improving loop signals... Is there
a prompts-suggest command that proposes an EXPIRES
marker or a one-line addition to PRINCIPLES.md based on
recurring `lesson_draft_emitted` events?" — this is the
direct answer to that prompt.

## Acceptance criteria

Each box maps 1:1 to a test scenario in `tests/prompts-suggest.sh`.

- [ ] `bin/fleet prompts-suggest` is a new subcommand. With no flags
      walks every project discovered via `agents.config.sh` under
      the standard discovery roots (same set as `fleet overview`),
      reads each project's `events.jsonl` for
      `type=lesson_draft_emitted` events in the trailing 30 days
      (default), clusters by normalized headline, and prints the
      candidates table from the User lens above. Exit 0 always.
      Test asserts the render via fixture events.jsonl files.
- [ ] The headline normalization is: lowercase, strip the leading
      `pr=#N ` prefix, collapse runs of whitespace to single
      space, strip trailing punctuation. Two events whose
      normalized headlines are byte-identical cluster together.
      Test asserts via fixtures where the same headline appears
      in different cases / with different PR numbers.
- [ ] The recurrence threshold is 3 events per cluster by default.
      Clusters below threshold are SILENTLY dropped (not listed
      as "below threshold"). `--threshold N` overrides the
      default. `--threshold 1` lists every cluster. Test asserts
      both branches.
- [ ] `bin/fleet prompts-suggest --since <Nd|YYYY-MM-DD>`
      overrides the default 30-day window. The default is
      30d (not 14d as in `fleet diff` / `rank`) because
      principle-shaped patterns recur over longer windows.
      Test asserts each format.
- [ ] Each candidate's PROPOSED ADDITION TO PRINCIPLES.md is
      composed by: (a) finding the most-recent
      `docs/LESSONS.md` paragraph from any discovered project
      whose first heading line's normalized text matches the
      cluster's normalized headline; (b) extracting the
      paragraph body; (c) formatting it under a placeholder
      `## P-NEXT — <imperative title>` heading where
      `<imperative title>` is the cluster's headline
      Title-Cased and stripped of the leading verb's
      tense. The next `P-N` integer is computed by reading
      the existing `PRINCIPLES.md` and finding the max P-N,
      then adding 1. Test asserts the composition against
      a fixture LESSONS.md + PRINCIPLES.md pair.
- [ ] The EXPIRES-marker branch fires when an existing
      `## P-N` line in `PRINCIPLES.md` is cited in
      `lesson_draft_emitted` bodies in the window but the
      recurring headline matches a DIFFERENT principle (the
      P-N is being mis-cited because the loop's doctrine
      has drifted from what the events actually show). The
      candidate proposes a `<!-- EXPIRES: YYYY-MM-DD -->`
      marker on the existing principle (reusing the
      LESSONS expiry-marker convention from ticket 0039)
      with a one-line REASON citing the mismatch. Test
      asserts via a fixture where 4+ events cite P-6
      with a headline that semantically maps to a
      different principle.
- [ ] `bin/fleet prompts-suggest --json` emits one JSON
      object per candidate
      `{"cluster_id": <N>, "headline": "<text>",
      "frequency": <int>, "per_slug": {"slug": <int>},
      "kind": "addition" | "expires", "target_p_n":
      "P-N | null", "proposed_text": "<markdown>",
      "lesson_source_pr": <int | null>}`, one per line,
      followed by a summary object `{"summary":
      {"window": "<Nd>", "threshold": <int>,
      "candidates_found": <int>,
      "principles_md_p_max": <int>}}`. JSON escape goes
      through `preflight_json_escape` per LESSONS
      2026-06-03. Test asserts JSON validity via Node.
- [ ] `bin/fleet prompts-suggest --help` prints USAGE
      mentioning `--since`, `--threshold`, `--json`, and
      the EXPIRES-marker behavior. Test asserts via
      `grep -qF -- "$kw" "$help_out"` per LESSONS
      2026-05-30. Help block ends with `exit 0` per
      LESSONS 2026-06-01.
- [ ] Empty fleet (zero projects discovered) prints
      `prompts-suggest: no projects discovered. run
      \`fleet onboard\` to adopt one.` exit 0. No
      events in the window prints
      `prompts-suggest: no lesson_draft_emitted events
      in the trailing <Nd>; nothing to suggest.`
      exit 0. No clusters above threshold prints
      `prompts-suggest: <N> events found but none
      recur ≥<threshold> times; the loop is learning
      one-shot lessons, not principle-shaped patterns.`
      exit 0. Test asserts all three branches.
- [ ] `bin/fleet prompts-suggest` is a PURE READER. NO
      `events.jsonl` writes, NO `fleet_emit_event`
      calls, NO writes to `PRINCIPLES.md` (the
      operator owns the paste). Test asserts the kit's
      events channel has unchanged byte size before and
      after invocation, AND that `prompts/PRINCIPLES.md`
      is byte-identical before and after invocation.
- [ ] The composer NEVER suggests a principle whose
      proposed text contains a `<!-- DRAFT: ` marker
      (those are unpromoted drafts from ticket 0022;
      promoting an UNPROMOTED draft is the operator's
      job via `lessons-promote`, not the kit's). The
      composer filters them out at the source-lookup
      step. Test asserts via a fixture LESSON
      paragraph that starts with a DRAFT marker.
- [ ] `lib/common.sh` — NO changes. `prompts-suggest`
      is a pure caller of existing helpers. NO new
      `fleet_*` helpers, NO signature changes. Test
      asserts via `git diff --name-only main…HEAD --
      lib/common.sh` returns empty.
- [ ] `prompts/` — NO changes (the candidate is
      printed to stdout; the operator does the
      paste). Test asserts via `git diff --name-only
      main…HEAD -- prompts/` returns empty.
- [ ] `tests/prompts-suggest.sh` covers all 13 boxes
      above using `$HOME/.local/bin` stubs per
      LESSONS 2026-05-26. Fixture `events.jsonl`
      and `LESSONS.md` files live under
      `tests/fixtures/prompts-suggest/`. Per
      LESSONS 2026-05-27 backup/restore via `cp`.
      Counts use `awk … END { print n+0 }` per
      LESSONS 2026-06-01. The clock is frozen via
      `FLEET_NOW_OVERRIDE`. Run-time budget: <10s.

## Out of scope

The dev agent will NOT do these even if they seem related.

- AUTO-EDITING `PRINCIPLES.md`. The kit composes the
  candidate; the operator pastes. Auto-editing the
  constitutional layer violates the operator-confidence
  Hard NO and the "principles are operator-authored"
  spirit of ticket 0018.
- A `--commit` flag that opens a chore PR with the
  candidate pre-pasted. v2 — first ship the candidate
  composer and let it bake on real operator
  promotions.
- Multi-cluster MERGING (e.g. "these 3 clusters are
  semantically the same principle"). v1 normalizes
  headlines BYTE-EQUAL; semantic clustering is a
  follow-up.
- An ML / NLP step for clustering. v1 is
  Lowercase-then-byte-equal; no model in the loop.
- A scoring rubric that ranks candidates by
  estimated impact. v1 lists candidates in
  frequency-descending order; the operator decides
  which to promote.
- Suggesting changes to per-phase prompts
  (`ship.prompt.md`, `groom.prompt.md`,
  `eng.prompt.md`). v1 is PRINCIPLES.md only — the
  constitutional layer. Per-phase prompts are
  mechanics, not doctrine.
- Reading the `lessons_promoted` channel from
  ticket 0028 as an additional signal. v1 uses
  `lesson_draft_emitted` only — the
  send-back-as-doctrine signal. A v2 may add
  promoted-lesson signal weighting.
- Running against the kit's `agent-fleet` slug
  only. v1 is FLEET-WIDE (every discovered slug).
- A launchd schedule. Operator-invoked only —
  composing a doctrine update is an operator
  decision, not a background task.
- Modifying `fleet weekly` (0025) or `fleet
  morning` (0036) to surface a "principles owe
  you a review" hint. v1 is standalone;
  composition is v2 once the operator has
  promoted ≥1 candidate and has a sense of the
  surface's signal-to-noise.

## Engineering notes

Files / patterns the dev should touch. Specific enough that the dev
doesn't have to re-discover the architecture.

- `bin/fleet` — new `prompts_suggest()` dispatcher
  function placed next to the existing
  `prompts_score()` block (find via `grep -n
  '^prompts_score()' bin/fleet` — currently around
  the `prompts-score` dispatcher at ~line 5391).
  Per LESSONS 2026-05-26 (`tail` shadow)
  `prompts_suggest` and helpers do not collide with
  any coreutils binary.
- `bin/fleet` — seven helpers, ALL defined ABOVE the
  dispatcher block per LESSONS 2026-06-05 (forward-
  reference trap):
  - `prompts_suggest_discover_slugs` — reuses the
    existing `overview_discover_slugs` helper.
  - `prompts_suggest_collect_drafts` — walks every
    discovered slug's `events.jsonl`, filters
    `type=lesson_draft_emitted` events in the
    window, emits one TSV line per event
    `slug<TAB>ts<TAB>pr<TAB>headline_normalized`.
    Per LESSONS 2026-06-08, the awk script
    declares `BEGIN { count = 0 }`. Per LESSONS
    2026-06-08 IFS=$'\t' middle-empty-field, the
    consumer uses `-` sentinel for missing PR
    numbers.
  - `prompts_suggest_normalize_headline` — given
    a raw `headline=<text>` event field, lowercase
    + strip leading `pr=#N ` + collapse whitespace
    + strip trailing punct. Per LESSONS 2026-05-28
    every internal `printf` of the headline goes
    through `printf -- '%s'`.
  - `prompts_suggest_cluster` — reads the TSV list
    from `collect_drafts` and groups by normalized
    headline, computes frequency + per-slug
    breakdown, filters by threshold.
  - `prompts_suggest_find_source_lesson` — for one
    cluster's normalized headline, scans every
    discovered project's `docs/LESSONS.md` for the
    most-recent paragraph whose heading
    normalizes to the same text. Returns the
    paragraph body verbatim (per LESSONS
    2026-05-27, file reads use `cat` AND the
    composer never `$(cat …)`-roundtrips).
  - `prompts_suggest_compose_candidate` —
    assembles the markdown candidate block from
    the cluster + source-lesson. Computes the
    next `P-N` by reading `prompts/PRINCIPLES.md`
    and finding the max `## P-N` integer. Per
    LESSONS 2026-06-05 (bash 3.2 LC_ALL caching),
    NO bash arithmetic on multi-byte strings; use
    `LC_ALL=C awk` for any character-level work.
  - `prompts_suggest_render_text` and
    `prompts_suggest_render_json` — formatters.
    Width via `preflight_visible_width` per
    LESSONS 2026-06-05; JSON escape via
    `preflight_json_escape` per LESSONS
    2026-06-03.
- `bin/fleet` — `prompts_suggest()` end-state must
  be `exit 0` on every code path per LESSONS
  2026-06-01.
- `bin/fleet` — dispatcher block: `if [ "$CMD" =
  "prompts-suggest" ]; then prompts_suggest "$@";
  fi`. Place AFTER the `prompts-score`
  dispatcher. Per LESSONS 2026-06-05 (forward-
  reference trap), confirm every helper
  `prompts_suggest` calls is defined ABOVE the
  dispatcher block.
- `bin/fleet` — help banner block at the top of
  the file (around line ~14) gets a new line:
  `fleet prompts-suggest propose PRINCIPLES.md
  additions from recurring send-back drafts`.
  README "Daily ops" code block gets the same
  line.
- `AGENTS.md § Telemetry` — NO new bullet.
  `prompts-suggest` is a pure reader. Test
  asserts via `git diff --name-only main…HEAD --
  AGENTS.md` returns empty.
- `lib/common.sh` — NO changes.
- `prompts/` — NO changes.
- `tests/fixtures/prompts-suggest/` — NEW
  directory under `tests/fixtures/` holding
  `events.jsonl` files for 3-4 synthetic slugs
  (some with recurring headlines, one with only
  unique headlines, one with the
  P-6-misciting fixture), plus paired
  `docs/LESSONS.md` fixtures (one with the
  matching paragraph, one with a DRAFT-prefixed
  paragraph that must be filtered out), plus a
  `prompts/PRINCIPLES.md` fixture used to compute
  the `next P-N`.
- `tests/prompts-suggest.sh` — top of file
  mirrors `tests/prompts-score.sh` and
  `tests/lessons-promote.sh`: stub `gh` under
  `$HOME/.local/bin` per LESSONS 2026-05-26.
  Counts use `awk … END { print n+0 }` per
  LESSONS 2026-06-01. Per LESSONS 2026-05-27
  backup/restore via `cp`. The clock is frozen
  via `FLEET_NOW_OVERRIDE`. Run-time budget:
  <10s.
- New deps: none. Pure shell + awk + existing
  helpers.
- Public API: additive — `bin/fleet
  prompts-suggest` is a new subcommand. ZERO new
  event types, ZERO event writes.
- BREAKING flag: NO. PR body affirms "pure
  reader, no events.jsonl writes, no
  PRINCIPLES.md writes, no `fleet_*` signature
  changes."
- Reinstall required: NO. `lib/` and `prompts/`
  are untouched.
- LESSONS to defend against: 2026-05-25
  (load-bearing docs — README "Daily ops" code
  block addition), 2026-05-26 (`tail` shadow),
  2026-05-26 (PATH reset — stubs go in
  `$HOME/.local/bin`), 2026-05-27 (`$(cat)`
  trap — composer uses temp files for
  paragraph bodies, not `$(cat)`), 2026-05-28
  (printf leading-dash — every headline goes
  through `printf -- '%s'`), 2026-05-30
  (`grep -F --` trap — every grep of
  PRINCIPLES.md uses `grep -E --` or
  `grep -F --`), 2026-06-01 (`grep -c file
  || echo 0` double-print — counts use `awk …
  END { print n+0 }`), 2026-06-01 (dispatcher
  fall-through), 2026-06-03 (UTF-8
  sign-extension — JSON escape goes through
  `preflight_json_escape`), 2026-06-05
  (dispatcher forward-reference), 2026-06-05
  (bash 3.2 LC_ALL caching — character work
  via `LC_ALL=C awk`), 2026-06-08 (awk
  empty-string-key — every awk script
  initializes counters), 2026-06-08 (IFS=$'\t'
  middle-empty-field — sentinel for missing
  PR numbers).
- This ticket compounds 0018 (`prompts/
  PRINCIPLES.md` — the destination file), 0022
  (`reviewer-sendback-drafts-lesson-skeleton`
  — the event source), 0024 (`fleet
  prompts-score` — the prompts-revision
  timeline that contextualizes which
  PRINCIPLES.md changes worked), 0028
  (`fleet lessons-promote` — the prior step
  in the promotion chain), 0039 (`fleet
  lessons-prune` — the EXPIRES-marker
  mechanism this command reuses). Per P-1 the
  diff is small: ~350 lines of
  `prompts_suggest_*` helpers + ~250 lines of
  test + 6 fixture files + one help-text line
  + one README line. The clustering pipeline
  is the main novelty; the source-lesson
  lookup and the render reuse existing
  patterns.

## Implementation log

(Appended by the implementation-dev agent during execution.)

- 2026-06-11 — ticket filed by gtm-innovation
