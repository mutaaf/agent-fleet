---
id: 0051
title: fleet skill-gap <slug> diffs a project's PHASE 0 reads against the fleet-wide CROSS_LESSONS coverage
status: groomed
priority: P2
area: governance
created: 2026-06-13
owner: gtm-innovation
---

## User story

As a fleet operator whose `courtiq` project has been hitting the same
test-isolation send-back four times this month, AND whose
`agent-fleet` project documented the EXACT SAME failure mode in
LESSONS three weeks ago (`2026-05-26 — tests own their own
filesystem`), AND whose `CROSS_LESSONS.md` (auto-synced from ticket
0009) ALREADY carries the agent-fleet lesson under the
`## agent-fleet` section — but whose `courtiq` runner's PHASE 0 reads
are NOT actually picking it up because nothing diffs "what lessons
exist in CROSS_LESSONS" against "what lessons THIS project's runner
ACTUALLY READ in recent runs" — I want `bin/fleet skill-gap <slug>`
to print one block per CROSS_LESSONS entry the named project's runs
appear to have missed (recurring send-back headlines in the slug's
events that map to a CROSS_LESSON paragraph the slug's runner never
cited in PHASE 0), so I can fix the gap structurally (point the
slug's `agents.config.sh` at the right CROSS_LESSONS scope, or
re-promote the lesson with broader scope) rather than re-litigate
the same send-back next month.

## Why now (four lenses)

### Product Owner
`fleet lessons-sync` (0009) and `fleet lessons-promote` (0028) put
the FEED in place: every project's LESSONS.md drains into
`~/.local/share/agent-fleet/CROSS_LESSONS.md` (the shared feed)
or into a per-slug override (`projects/<slug>/CROSS_LESSONS.md.
override`). PHASE 0 reads of every runner consume the feed at
the start of every ship/groom/eng cycle. The promotion chain
(`event → LESSONS draft → LESSONS final → CROSS_LESSONS feed
→ PHASE 0 read`) is end-to-end working.

But there's NO surface that detects FALSE NEGATIVES: a lesson
that EXISTS in CROSS_LESSONS but is failing to influence a
particular slug's runs. The failure modes are:

- The slug's CROSS_LESSONS scope is wrong (e.g. the lesson was
  promoted with `--scope agent-fleet` but should have been
  `--scope all`).
- The slug's agents.config.sh CROSS_LESSONS path is unset and
  PHASE 0 never reads the file.
- The lesson lives under another slug's section but the
  send-back headline doesn't textually match enough to
  trigger reuse.
- The lesson is in CROSS_LESSONS but its prose doesn't
  generalize beyond the original slug.

Each of those is fixable IF the operator notices. Today they
notice ONLY by re-experiencing the same send-back twice in
two different projects — by which point the loop has spent
2-4 dollars heal'ing a failure mode the kit already KNEW.

The smallest meaningful unit of value is one command, one
coverage diff per slug:

```
fleet skill-gap courtiq

skill-gap: courtiq has 3 recurring send-back headlines that map
           to CROSS_LESSONS entries it appears to have missed.

  [1] 2026-05-26 — tests own their own filesystem
      cross_lesson source: agent-fleet (## agent-fleet section)
      courtiq recurring headline: "test wrote to a non-isolated
        path" (×4 send-backs in the trailing 30d)
      coverage check: courtiq's agents.config.sh CROSS_LESSONS=
        "$HOME/.local/share/agent-fleet/CROSS_LESSONS.md" — file
        IS read at PHASE 0. The lesson section IS present in the
        feed. The slug's runner appears to read the file but the
        prose is agent-fleet-specific ("shell-only kit, no
        runtime deps") and may not generalize.
      suggested fix: `fleet lessons-promote courtiq --scope all
        --source 2026-05-26` to re-promote the lesson with broader
        scope language, OR `fleet lessons-promote agent-fleet
        --scope all --source 2026-05-26 --rewrite` to rewrite the
        cross-version's prose to generalize beyond shell-only.

  [2] 2026-06-01 — printf leading-dash trap
      cross_lesson source: agent-fleet
      courtiq recurring headline: "printf consumed flag arg as
        option" (×2 send-backs in the trailing 30d)
      coverage check: courtiq's CROSS_LESSONS path is UNSET in
        agents.config.sh — PHASE 0 NEVER reads the feed for this
        slug.
      suggested fix: add CROSS_LESSONS=
        "$HOME/.local/share/agent-fleet/CROSS_LESSONS.md" to
        courtiq/agents.config.sh and re-install.

  [3] 2026-06-08 — IFS=$'\t' middle-empty-field trap
      cross_lesson source: agent-fleet
      courtiq recurring headline: "awk treated empty middle field
        as missing column" (×3 send-backs in the trailing 30d)
      coverage check: courtiq's CROSS_LESSONS path is set, feed is
        read, lesson IS in the feed under ## agent-fleet, BUT the
        slug-specific override file
        projects/courtiq/CROSS_LESSONS.md.override EXISTS and may
        be shadowing the shared feed.
      suggested fix: `cat projects/courtiq/CROSS_LESSONS.md.
        override` to inspect the override; remove it if not
        needed.

skill-gap: 3 false-negative coverage gaps detected. open the
           fixes above one at a time and re-run skill-gap on
           the next ship cycle to confirm the gap closed.
```

Subtraction: the operator stops experiencing the same
send-back across two projects. The kit's promise of
"compounding lessons across the fleet" actually delivers
because the kit DIAGNOSES coverage gaps instead of leaving
them invisible.

Per P-5 (operator confidence over feature richness), the win
is converting "I keep seeing this same send-back in different
projects and I can't figure out why" into "here's the
specific config gap; here's the fix command."

### Stakeholder
This is **moat-deepening on the cross-project axis** — the
kit's first surface that diagnoses the GAP between
"cross-project knowledge exists" and "cross-project knowledge
is being USED." The CROSS_LESSONS feed is the moat;
`skill-gap` is the surface that ensures the moat isn't
silently leaking.

Per P-6 (telemetry is the source of truth), the gap detector
is a PURE READER of three sources:

1. The fleet-wide `CROSS_LESSONS.md` feed (resolved via
   `$FLEET_CROSS_LESSONS` env or the standard
   `~/.local/share/agent-fleet/CROSS_LESSONS.md` path).
2. The named slug's `events.jsonl` for the
   `lesson_draft_emitted` events in the window (recurring
   send-back headlines).
3. The named slug's `agents.config.sh` (CROSS_LESSONS path
   + override file existence).

The algorithm:

1. Read every `## YYYY-MM-DD — <title>` heading in
   CROSS_LESSONS; that's the set of cross-project lessons
   available.
2. Read the slug's `lesson_draft_emitted` events in the
   trailing 30d, normalize headlines via the same helper
   `fleet prompts-suggest` (0045) uses, cluster by
   normalized headline.
3. For each cluster with ≥3 occurrences, check whether the
   normalized headline FUZZY-MATCHES any CROSS_LESSONS
   heading (lowercase + substring match in either
   direction). A match means: this slug is REPEATEDLY
   hitting a failure mode the fleet already documented.
4. For each matched (cluster, cross_lesson) pair, run the
   four coverage checks (CROSS_LESSONS path set? feed file
   exists? lesson section present in feed? per-slug
   override file shadowing?) and emit the appropriate
   suggested fix.

Per P-1 (smallest viable change), the diff is the headline
normalizer (reused from 0045) + the CROSS_LESSONS parser +
the four coverage checks + the render. ~300 lines.

Per P-8 (append memory; never reorder), `skill-gap` ALSO
detects the inverse failure mode: lessons in CROSS_LESSONS
that have NEVER been cited in any slug's PHASE 0 transcript
(noise lessons consuming read-cost). v1 surfaces this as a
secondary "no-signal entries" footer; pruning them is
ticket 0039 (`lessons-prune`)'s job.

Compounds 0009 (`fleet lessons-sync` — produces the
CROSS_LESSONS feed), 0028 (`fleet lessons-promote` — the
suggested fix command), 0039 (`fleet lessons-prune` — the
no-signal followup), 0045 (`fleet prompts-suggest` — shares
the headline normalizer helper).

Per P-3 (heal in-flight before new work), `skill-gap` is
read-only and cheap (~one events.jsonl read for the slug,
one CROSS_LESSONS read) — never blocks heal work.

### User (operator on a Friday night, two months in,
puzzled by repeating send-backs)
Operator opens `fleet inbox`, sees 4 unpromoted
`lesson_draft_emitted` events on courtiq, all with similar
headlines. Runs `fleet skill-gap courtiq`. Sees three
coverage gaps. The middle one ("CROSS_LESSONS path UNSET")
is the highest-leverage fix — one line in
`agents.config.sh` + a re-install — and the operator does it
in 90 seconds. The next ship cycle's PHASE 0 reads the feed
for the first time. The recurring headline stops recurring
two weeks later.

Without `skill-gap`, the operator either keeps experiencing
the recurring send-back until they manually audit
agents.config.sh files (which most don't), or they assume
the lesson "just doesn't apply" to courtiq and move on. The
moat leaks invisibly.

Per P-5, the win is converting "why does my fleet keep
re-learning the same lesson?" into "here's the config gap,
here's the fix."

### Growth
This is the surface that makes the kit's "compounding
cross-project lessons" claim MEASURABLE. A friend evaluating
the kit who reads about the CROSS_LESSONS feed can ask
"sure, but how do I know the feed is actually being USED?"
The honest answer today is "you don't, until a send-back
recurs." With `skill-gap`, the answer is "run
`fleet skill-gap <slug>` and the kit tells you which
lessons aren't landing and why."

That's a TRUST artifact for cross-project knowledge — the
deepest part of the moat. Per the brief's "Cross-project
pattern emergence / moat-widening: there's no 'skill-gap
analysis' — which projects in MY fleet are missing lessons
their peers have absorbed? A `fleet skill-gap <slug>` that
diffs a project's PHASE 0 reads against the fleet-wide
CROSS_LESSONS coverage" — this is the direct answer.

This is also the surface that complements
`fleet prompts-suggest` (0045): suggest surfaces lessons
THAT SHOULD BECOME PRINCIPLES; skill-gap surfaces lessons
THAT ALREADY EXIST BUT AREN'T LANDING. Together they cover
both sides of the learning loop.

## Acceptance criteria

Each box maps 1:1 to a test scenario in `tests/skill-gap.sh`.

- [ ] `bin/fleet skill-gap <slug>` is a new subcommand. Required
      arg is the slug name. Missing slug: prints `skill-gap:
      usage: bin/fleet skill-gap <slug> [--since Nd]
      [--threshold N] [--json]` to stderr, exit 2 per LESSONS
      2026-06-01. Unknown slug (not in `agents.config.sh`
      discovery): prints `skill-gap: slug <name> not found.
      discovered slugs: <list>. ` to stderr, exit 2. Test
      asserts both refusals.
- [ ] The CROSS_LESSONS source is resolved via
      `$FLEET_CROSS_LESSONS` env override (for tests), then
      the slug's `agents.config.sh` `CROSS_LESSONS` value,
      then the default
      `~/.local/share/agent-fleet/CROSS_LESSONS.md`. When the
      file is missing entirely, prints `skill-gap: no
      CROSS_LESSONS feed found. run \`fleet lessons-sync\`
      to populate it.` exit 0. Test asserts via fixture.
- [ ] The CROSS_LESSONS parser walks `## YYYY-MM-DD —
      <title>` headings, returns one record per heading:
      `slug_section<TAB>date<TAB>title<TAB>body_first_80`.
      The `slug_section` is the closest preceding `## <slug>`
      heading (the per-slug grouping convention from ticket
      0009). Per LESSONS 2026-06-08 the awk script declares
      `BEGIN { count = 0 }`. Test asserts via fixture
      CROSS_LESSONS.md with multiple slug sections.
- [ ] The slug's recurring-headline detector walks the slug's
      `events.jsonl` for `lesson_draft_emitted` events in the
      trailing 30d (configurable via `--since`), normalizes
      headlines via the existing
      `prompts_suggest_normalize_headline` helper from ticket
      0045, clusters by normalized headline, filters to
      clusters with ≥`--threshold` (default 3) occurrences.
      Test asserts via fixture events.jsonl.
- [ ] The fuzzy match between a recurring headline and a
      CROSS_LESSON heading is: lowercase both, check whether
      EITHER one is a substring of the other (after stripping
      leading dates / verbs / prepositions). A match means:
      the slug is REPEATEDLY hitting a failure mode the fleet
      already documented. Test asserts via fixtures
      including a positive match ("test wrote to a non-
      isolated path" ↔ "tests own their own filesystem")
      AND a negative non-match.
- [ ] Coverage check 1 — `CROSS_LESSONS_PATH_UNSET`: fires
      when the slug's `agents.config.sh` has no
      `CROSS_LESSONS=` value. Suggested fix: `add
      CROSS_LESSONS="$HOME/.local/share/agent-fleet/
      CROSS_LESSONS.md" to <slug>/agents.config.sh and
      re-install.` Test asserts via fixture manifest with
      unset CROSS_LESSONS.
- [ ] Coverage check 2 — `CROSS_LESSONS_FILE_MISSING`: fires
      when the slug's CROSS_LESSONS path is set but the file
      doesn't exist. Suggested fix: `run \`fleet
      lessons-sync\` to populate
      <path>.` Test asserts via fixture with bad path.
- [ ] Coverage check 3 — `OVERRIDE_SHADOWING`: fires when
      `projects/<slug>/CROSS_LESSONS.md.override` exists and
      doesn't include the matched lesson's section. Suggested
      fix: `cat projects/<slug>/CROSS_LESSONS.md.override`
      to inspect; remove if not needed; if needed, append
      the matched lesson manually OR re-promote with
      \`fleet lessons-promote --scope <slug>\``. Test
      asserts via fixture with override file.
- [ ] Coverage check 4 — `LESSON_PROSE_NOT_GENERALIZED`:
      fires when the previous three checks PASS (feed is
      read, lesson is in feed under another slug's section,
      no override shadowing) but the recurring headline
      keeps firing. The diagnosis is that the
      cross-project prose is too slug-specific. Suggested
      fix: `fleet lessons-promote <slug> --scope all
      --source <date>` to re-promote with broader scope, OR
      `fleet lessons-promote <source-slug> --scope all
      --source <date> --rewrite` to rewrite the cross
      version. Test asserts via fixture.
- [ ] The "no-signal entries" footer lists every
      CROSS_LESSON heading that has ZERO matching recurring
      headlines across ANY slug in the trailing 30d
      (candidate to age out via ticket 0039's EXPIRES
      marker). Empty when every CROSS_LESSON has at least
      one matching headline in any slug. Test asserts both
      branches.
- [ ] `bin/fleet skill-gap <slug> --since <Nd|YYYY-MM-DD>`
      overrides the default 30-day window for both the
      recurring-headline scan AND the no-signal footer.
      Test asserts each format.
- [ ] `bin/fleet skill-gap <slug> --threshold N`
      overrides the recurrence threshold. Default is 3.
      `--threshold 1` lists every cluster. Test asserts.
- [ ] `bin/fleet skill-gap <slug> --json` emits one JSON
      object per coverage gap: `{"slug": "<name>",
      "cluster_headline": "<text>", "frequency": <int>,
      "cross_lesson_date": "<YYYY-MM-DD>",
      "cross_lesson_title": "<text>", "cross_lesson_
      source_slug": "<slug>", "coverage_check":
      "CROSS_LESSONS_PATH_UNSET" | "CROSS_LESSONS_FILE_
      MISSING" | "OVERRIDE_SHADOWING" |
      "LESSON_PROSE_NOT_GENERALIZED", "suggested_fix":
      "<text>"}` plus a summary `{"summary": {"slug":
      "<name>", "window": "<Nd>", "gaps_found": <int>,
      "no_signal_entries": <int>}}`. JSON escape via
      `preflight_json_escape` per LESSONS 2026-06-03.
      Test asserts JSON validity via Node.
- [ ] `bin/fleet skill-gap --help` prints USAGE
      mentioning the slug arg, `--since`, `--threshold`,
      `--json`. Test asserts via `grep -qF -- "$kw"
      "$help_out"` per LESSONS 2026-05-30. Help block
      ends with `exit 0`.
- [ ] Empty case (slug has zero recurring headlines in the
      window): prints `skill-gap: <slug> has no
      recurring send-back headlines (≥<threshold>
      occurrences) in the trailing <Nd>. The loop is
      either healthy or the window is too short.` exit 0.
      Test asserts.
- [ ] `bin/fleet skill-gap` is a PURE READER. NO
      `events.jsonl` writes, NO `fleet_emit_event` calls,
      NO writes to CROSS_LESSONS.md or agents.config.sh.
      Test asserts the kit's events channel has unchanged
      byte size before and after invocation AND the
      CROSS_LESSONS.md is byte-identical.
- [ ] `lib/common.sh` — NO changes. Test asserts via
      `git diff --name-only main…HEAD -- lib/common.sh`
      returns empty.
- [ ] `prompts/` — NO changes. Test asserts via `git
      diff --name-only main…HEAD -- prompts/` returns
      empty.
- [ ] `tests/skill-gap.sh` covers all 16 boxes above
      using `$HOME/.local/bin` stubs per LESSONS
      2026-05-26. Fixture `events.jsonl`,
      `CROSS_LESSONS.md`, and `agents.config.sh` files
      live under `tests/fixtures/skill-gap/`. Per
      LESSONS 2026-05-27 backup/restore via `cp`.
      Counts use `awk … END { print n+0 }` per LESSONS
      2026-06-01. The clock is frozen via
      `FLEET_NOW_OVERRIDE`. Run-time budget: <10s.

## Out of scope

The dev agent will NOT do these even if they seem related.

- AUTO-EDITING `agents.config.sh` to add the CROSS_LESSONS
  path. v1 prints the suggested fix; the operator edits.
  Auto-editing a project's manifest violates the operator-
  confidence Hard NO.
- AUTO-RUNNING `fleet lessons-promote` to re-promote with
  broader scope. v1 prints the suggested command; the
  operator runs.
- A FLEET-WIDE skill-gap ("show me every slug's coverage
  gaps in one table"). v1 is one slug at a time. The
  composition is `for slug in $(fleet discover-slugs); do
  fleet skill-gap "$slug"; done`. A `fleet skill-gap
  --all` is v2.
- An ML / NLP step for the fuzzy match. v1 is
  lowercase + substring in either direction; semantic
  matching is a follow-up.
- A "predict which slug will hit which CROSS_LESSON next"
  forecasting model. v1 is descriptive (gaps that have
  ALREADY happened); prediction is out.
- Modifying the per-runner PHASE 0 to LOG which
  CROSS_LESSONS sections it actually read (so skill-gap
  could verify reads directly instead of inferring from
  send-back recurrence). v1 infers from send-backs
  because adding PHASE 0 logging would change the
  runtime hot path (P-3 violation; non-additive).
- Auto-aging out CROSS_LESSONS entries with no signal.
  v1 surfaces them; the operator runs `fleet
  lessons-prune` (0039).
- A `fleet skill-gap --vs <other-slug>` mode showing the
  diff between two slugs' coverage. v1 is one slug;
  cross-slug is `fleet diff` (0038)'s pattern.
- A launchd schedule. Operator-invoked only.

## Engineering notes

Files / patterns the dev should touch.

- `bin/fleet` — new `skill_gap()` dispatcher function
  placed next to the existing
  `prompts_suggest()` block (find via `grep -n
  '^prompts_suggest()' bin/fleet`). Per LESSONS
  2026-05-26 (`tail` shadow) `skill_gap` does not collide
  with any coreutils binary.
- `bin/fleet` — seven helpers, ALL defined ABOVE the
  dispatcher block per LESSONS 2026-06-05 (forward-
  reference trap):
  - `skill_gap_resolve_cross_lessons_path` — resolves the
    CROSS_LESSONS file path per the env / manifest /
    default precedence.
  - `skill_gap_parse_cross_lessons` — walks the
    CROSS_LESSONS.md file, emits one TSV row per
    `## YYYY-MM-DD — <title>` heading
    `slug_section<TAB>date<TAB>title<TAB>body_first_80`.
    Per LESSONS 2026-06-08 the awk script declares
    `BEGIN { count = 0 }`. Per LESSONS 2026-06-08
    IFS=$'\t' uses `-` sentinel.
  - `skill_gap_collect_recurring_headlines` — for the
    named slug, walks `events.jsonl` for the trailing
    window's `lesson_draft_emitted` events, normalizes
    headlines via the existing
    `prompts_suggest_normalize_headline` from ticket
    0045 (sourced from same file; no duplication),
    clusters, filters by threshold.
  - `skill_gap_fuzzy_match` — given a recurring headline
    and a CROSS_LESSONS title, returns 0 (match) or 1
    (no match). Lowercase + substring in either
    direction, after stripping leading dates / verbs /
    prepositions. Per LESSONS 2026-06-05 (bash 3.2
    LC_ALL caching), character-level work via
    `LC_ALL=C awk`.
  - `skill_gap_run_coverage_checks` — given a matched
    pair, runs the four coverage checks against the
    slug's `agents.config.sh` and the file existence.
    Per LESSONS 2026-05-28 every `printf` of the slug
    name goes through `printf -- '%s'`.
  - `skill_gap_compose_no_signal_footer` — given the
    parsed CROSS_LESSONS records and the recurring
    headlines across the fleet, returns the list of
    CROSS_LESSONS headings with zero matching
    recurring headlines.
  - `skill_gap_render_text` and `skill_gap_render_json`
    — formatters. Width via `preflight_visible_width`
    per LESSONS 2026-06-05; JSON escape via
    `preflight_json_escape` per LESSONS 2026-06-03.
- `bin/fleet` — `skill_gap()` end-state must be
  `exit 0` / `exit 2` on every code path per LESSONS
  2026-06-01.
- `bin/fleet` — dispatcher block: `if [ "$CMD" =
  "skill-gap" ]; then skill_gap "$@"; fi`. Place
  AFTER the `prompts-suggest` dispatcher.
- `bin/fleet` — help banner block at the top of the
  file gets a new line: `fleet skill-gap <slug>
  diagnose CROSS_LESSONS coverage gaps for one
  project`. README "Daily ops" code block gets the
  same line.
- `AGENTS.md` — NO content change. `skill-gap` is a
  pure reader. Test asserts via `git diff --name-only
  main…HEAD -- AGENTS.md` returns empty.
- `lib/common.sh` — NO changes.
- `prompts/` — NO changes.
- `tests/fixtures/skill-gap/` — NEW directory under
  `tests/fixtures/` holding `CROSS_LESSONS.md`
  fixtures (one with multiple slug sections, one
  without the relevant lesson, one empty),
  `events.jsonl` fixtures for one slug with each
  coverage-check scenario, `agents.config.sh`
  fixtures (one with CROSS_LESSONS path set, one
  unset, one pointing at a missing file), and an
  override-file fixture for the OVERRIDE_SHADOWING
  scenario.
- `tests/skill-gap.sh` — top of file mirrors
  `tests/prompts-suggest.sh` (the closest prior
  ticket; shares the headline-normalizer helper).
  Stubs `gh` under `$HOME/.local/bin` per LESSONS
  2026-05-26. Counts use `awk … END { print n+0 }`
  per LESSONS 2026-06-01. Per LESSONS 2026-05-27
  backup/restore via `cp`. The clock is frozen via
  `FLEET_NOW_OVERRIDE`. Run-time budget: <10s.
- New deps: none. Pure shell + awk + existing
  helpers.
- Public API: additive — `bin/fleet skill-gap` is a
  new subcommand. ZERO new event types, ZERO event
  writes.
- BREAKING flag: NO. PR body affirms "pure reader,
  no events.jsonl writes, no CROSS_LESSONS.md
  writes, no agents.config.sh writes, no `fleet_*`
  signature changes."
- Reinstall required: NO. `lib/` and `prompts/` are
  untouched.
- LESSONS to defend against: 2026-05-25 (README
  "Daily ops" code block addition), 2026-05-26
  (`tail` shadow), 2026-05-26 (PATH reset — stubs in
  `$HOME/.local/bin`), 2026-05-27 (`$(cat)` trap —
  CROSS_LESSONS file reads via `cat` then passed by
  temp file, never `$(cat)`-roundtripped),
  2026-05-28 (printf leading-dash — every slug and
  headline printf goes through `printf -- '%s'`),
  2026-05-30 (`grep -F --` trap — every grep of
  CROSS_LESSONS uses `grep -F --` or `grep -E --`),
  2026-06-01 (`grep -c file || echo 0` double-print
  — counts use `awk … END { print n+0 }`),
  2026-06-01 (dispatcher fall-through), 2026-06-03
  (UTF-8 sign-extension — JSON escape via
  `preflight_json_escape`), 2026-06-05 (dispatcher
  forward-reference), 2026-06-05 (bash 3.2 LC_ALL
  caching — fuzzy-match character work via
  `LC_ALL=C awk`), 2026-06-08 (awk empty-string-key
  — every awk script declares `BEGIN { count = 0
  }`), 2026-06-08 (IFS=$'\t' middle-empty-field —
  sentinel for missing fields), 2026-06-11 (BSD
  `date -j -f` fills missing time fields with
  NOW-of-day — every window-boundary compare uses
  ISO8601 lex-compare).
- This ticket compounds 0009 (`fleet lessons-sync`
  — produces the CROSS_LESSONS feed this command
  reads), 0028 (`fleet lessons-promote` — the
  suggested fix command for the prose-not-
  generalized and override-shadowing branches),
  0039 (`fleet lessons-prune` — the followup for
  the no-signal-entries footer), 0045 (`fleet
  prompts-suggest` — shares the
  headline-normalization helper verbatim,
  zero duplication). Per P-1 the diff is small:
  ~300 lines of `skill_gap_*` helpers + ~250
  lines of test + 6 fixture files + one
  help-text line + one README line.

## Implementation log

(Appended by the implementation-dev agent during execution.)
