---
id: 0057
title: fleet lessons-rank surfaces the most-cited LESSONS entries to feed promote / prune decisions
status: shipped
priority: P2
area: governance
created: 2026-06-17
owner: gtm-innovation
---

## User story

As a fleet operator who has been grinding the kit for two months,
who has watched `docs/LESSONS.md` grow from 4 entries to 34 entries
(via 0009 cross-project sync, 0022 reviewer send-back drafts, and
0028 lessons-promote) — who knows that some LESSONS are
load-bearing (the agent cites them in every PR description) and
others are dormant (they earned their entry once and have not been
referenced since) — but who has NO way to TELL which is which
without grepping the whole repo by hand — I want `bin/fleet
lessons-rank` to count, for every `## YYYY-MM-DD` heading in
`docs/LESSONS.md`, how many times that date string appears in
`bin/fleet`, `lib/*.sh`, `prompts/*.md`, AND in every backlog
ticket's `LESSONS to defend against:` block, then print a ranked
list with `→ promote-candidate` next to the most-cited entries
(so they graduate to `prompts/PRINCIPLES.md` via 0018) and
`→ prune-candidate` next to the never-cited ones (so they expire
via 0039's `EXPIRES` marker), so I can close the third leg of
the LESSON-promotion triangle and stop the kit's operational
memory from silently bloating.

## Why now (four lenses)

### Product Owner
The LESSONS pipeline today has TWO halves and a missing middle.
The IN-flow is excellent: 0022 drops a `<!-- DRAFT -->` block
when a reviewer sends back, 0009 syncs the cross-project feed,
0028 promotes a draft into a real lesson, 0045 proposes
PRINCIPLES additions from recurring `lesson_draft` clusters.
The OUT-flow exists: 0039 lets the operator mark a lesson with
`EXPIRES: YYYY-MM-DD` and the PHASE 0 reader skips stale
entries. What does NOT exist is the MIDDLE: a surface that
tells the operator WHICH lessons are load-bearing
(promote-to-PRINCIPLES candidates) and WHICH are dormant
(expiry candidates). Without this, LESSONS grows monotonically,
PHASE 0 reads slow down, and the operator has no signal for
which entries to graduate or retire. The smallest meaningful
unit of value is one ranked list:

```
$ fleet lessons-rank --top 10
lessons-rank — 34 entries, scanned 4,217 citations across 87 files

  1. LESSONS 2026-06-13 — preflight_json_escape wrapper trap
     cited 24× across 18 files                → promote-candidate
       bin/fleet:           17 hits
       lib/common.sh:        2 hits
       prompts/*.md:         0 hits
       docs/backlog/*.md:    5 hits

  2. LESSONS 2026-06-08 — awk arr[count]= empty-string-key
     cited 19× across 14 files                → promote-candidate
       bin/fleet:           11 hits
       lib/common.sh:        1 hit
       prompts/*.md:         0 hits
       docs/backlog/*.md:    7 hits

  …

 31. LESSONS 2026-05-26 — `lib/common.sh` resets PATH
     cited  2× across  2 files
       bin/fleet:            0 hits
       lib/common.sh:        1 hit
       prompts/*.md:         0 hits
       docs/backlog/*.md:    1 hit

 32. LESSONS 2026-05-27 — `$(cat file)` strips trailing newlines
     cited  1× across  1 file
       docs/backlog/*.md:    1 hit
                                                 → prune-candidate
                                                 (EXPIRES 2026-07-15
                                                  suggested)
```

Subtraction: the operator stops guessing which lesson is
load-bearing. Per P-5 (operator confidence over feature
richness), the win is the absent ambiguity about what to do
with each entry. Per P-8 (append memory; never reorder) the
ranker is a PURE READER — it never edits LESSONS.md itself,
it only suggests.

### Stakeholder
This is **moat-deepening on the governance axis** — closing
the third leg of the LESSON-promotion triangle. Per P-6
(telemetry is the source of truth — but doctrine is the
durable layer above it), the value of LESSONS depends on
the operator's ability to MAINTAIN it. A monotonically-
growing append-only memory store eventually drowns its
own signal. The ranker is the signal that tells the
operator where to act.

The promote-vs-prune rubric IS the moat: a lesson cited
≥10 times across ≥5 files is doctrine-shaped (it has
proven itself worth remembering) and should graduate to
PRINCIPLES so the agent reads it as constitutional rather
than situational. A lesson cited 0 or 1 times within 60
days of its date is dormant (the kit has moved past the
trap that caused it) and is a candidate for the EXPIRES
marker per 0039.

Per P-6 (telemetry is the source of truth), the ranker is
a PURE READER over `docs/LESSONS.md` (for the headings),
`bin/fleet`, `lib/*.sh`, `prompts/*.md`, and
`docs/backlog/*.md` (for the citations). No new event
types. No writes. No `lib/common.sh` changes. The diff
is the heading-extractor + the grep-counter + the renderer.
~270 lines.

Compounds 0018 (PRINCIPLES.md — promote-candidate
recommendations feed the operator's PRINCIPLES additions),
0039 (LESSONS expiry markers — prune-candidate
recommendations feed the operator's EXPIRES additions),
0045 (`fleet prompts-suggest` — proposes PRINCIPLES
additions from `lesson_draft_emitted` event clusters; this
ticket proposes them from CODEBASE-CITATION clusters,
which is complementary signal: one looks at "what
reviewer-send-backs cluster," the other looks at "what
the kit ALREADY cites a lot in shipped code"), 0009
(`fleet lessons-sync` — the cross-project feed the
ranker reads), 0028 (`fleet lessons-promote` — promotes
a draft into the file the ranker scans), 0040 (`fleet
self-check` — lints CURRENT shell against pattern
catalog; this ticket ranks the pattern catalog ITSELF).

Per LESSONS 2026-06-15 (per-day shellout inside per-slug
loops) the ranker is operator-invoked, not called from
`--all`-style loops, so the grep can use `grep -F --` on
each LESSONS date without the per-slug subprocess
concern. Each LESSONS date triggers ONE grep per file
tree it scans (four trees), so 34 entries × 4 trees =
136 greps — well under the per-invocation budget.

### User (operator on a Sunday afternoon, doing LESSONS hygiene)
The operator has set aside 20 minutes Sunday to "clean up
LESSONS." Without this ticket they would manually open each
of the 34 entries, manually grep the codebase, manually
decide. With this ticket they run `fleet lessons-rank`,
scan the ranked list, see that the top 8 entries are
cited 15+ times each (clear PRINCIPLES candidates), and
the bottom 12 entries are cited ≤2 times (clear EXPIRES
candidates). They open `prompts/PRINCIPLES.md`, append
P-10 / P-11 / P-12 from the top three. They open
`docs/LESSONS.md`, add `EXPIRES: 2026-07-15` headers to
the bottom 12. The middle 14 entries stay as-is. Total
elapsed time: 12 minutes. Per P-5, the win is the
LESSONS-hygiene chore taking 12 minutes instead of an
hour.

Sub-scenario: a NEW operator running `fleet lessons-
rank` for the first time on a 1-week-old install sees
"lessons-rank — 0 entries promotable, your LESSONS
catalog is small (4 entries). Run again in 30 days
when the catalog has grown." This is the "warm
welcome" branch for an operator who hasn't yet
accumulated enough citations to need the ranker.

Sub-scenario: an EXPERIENCED operator runs `fleet
lessons-rank --bottom 5` to see only the prune
candidates (the bottom 5 by citation count). The output
is the same shape, restricted to the bottom of the
list. Useful when the operator is in "prune mode" not
"promote mode."

### Growth
This is the surface that makes the kit's "we
self-improve" claim CREDIBLE. Today the kit ships
LESSONS as append-only memory with no maintenance
story. A friend evaluating the kit who asks "won't
LESSONS bloat over time?" can be shown
`fleet lessons-rank` — the answer is "the kit
tells you which entries are load-bearing and
which to retire; you run the ranker once a month."
That converts a maintenance objection into a
demonstrated feature.

Differentiated from `fleet prompts-suggest` (0045):
prompts-suggest proposes PRINCIPLES additions from
`lesson_draft_emitted` event clusters (i.e. "what
do reviewer send-backs keep clustering on"). This
ticket proposes PRINCIPLES additions from
CODEBASE-CITATION counts (i.e. "what does the
kit's own shell already cite a lot"). Both feed
the same promote pipeline; they look at different
signals. Per P-9, prompts-suggest looks at the
reviewer-send-back loop; lessons-rank looks at
the static codebase.

Differentiated from `fleet self-check` (0040):
self-check LINTS the current shell against the
LESSONS pattern catalog (i.e. "does this code
violate a known pattern"). This ticket RANKS the
catalog itself (i.e. "which patterns are doing
the heavy lifting"). Self-check is the consumer;
lessons-rank is the meta-view OF the catalog.

Differentiated from `fleet atlas` (0031): atlas
ranks FAILURE MODES the loop has hit. This ranks
LESSONS the loop has cited. Atlas is run-time
incident-shaped; lessons-rank is doctrine-shaped.

## Acceptance criteria

Each box maps 1:1 to a test scenario in
`tests/lessons-rank.sh`.

- [ ] `bin/fleet lessons-rank` is a new subcommand.
      With no flags, prints the full ranked list to
      stdout. Empty LESSONS.md (zero `## YYYY-MM-DD`
      headings): prints `lessons-rank: no LESSONS
      entries found. add one via reviewer send-back
      (0022) or \`fleet lessons-promote\` (0028).`
      exit 0. Per LESSONS 2026-06-01 (dispatcher
      fall-through) every code path ends with `exit 0`.
      Test asserts both branches via fixtures.
- [ ] LESSONS headings are extracted via one awk
      pass over `docs/LESSONS.md` matching the
      regex `^## ([0-9]{4}-[0-9]{2}-[0-9]{2}) —
      (.+)$`. The capture stores both the date
      and the headline. Per LESSONS 2026-06-08 the
      awk pass declares `BEGIN { count = 0 }`. Per
      LESSONS 2026-06-05 (bash 3.2 LC_ALL caching)
      the awk runs under `LC_ALL=C`. Test asserts
      via a fixture LESSONS.md with 5 headings.
- [ ] Each heading's citation count is the sum of
      `grep -c -F -- "$date" <path>` across four
      file trees: `bin/fleet`, `lib/*.sh`,
      `prompts/*.md`, `docs/backlog/*.md`. Per
      LESSONS 2026-05-30 (`grep -F --` trap) the
      pattern is passed via `-F -- "$date"`. Per
      LESSONS 2026-06-01 (`grep -c file || echo
      0` double-print) the per-file count uses
      `awk … END { print n+0 }` shape OR the
      summing awk handles the missing-file
      branch internally — NOT `grep -c file ||
      echo 0` to avoid the double-print. Test
      asserts via fixture that an entry cited
      11× in bin/fleet, 1× in lib/common.sh, 0×
      in prompts/*.md, 7× in docs/backlog/*.md
      renders `cited 19× across 14 files` (the
      19 is the sum; the 14 is the unique
      file-count, computed via `sort -u`).
- [ ] The output excludes self-citations (the
      heading's own occurrence in
      `docs/LESSONS.md`). Test asserts via fixture
      that an entry cited only in LESSONS.md
      itself renders `cited 0× across 0 files`.
- [ ] The promote-candidate threshold is
      `cited ≥10× across ≥5 files`. Entries
      meeting both thresholds render the
      `→ promote-candidate` tag. Test asserts
      via fixtures at the boundaries: 9× / 5
      files (no tag), 10× / 4 files (no tag),
      10× / 5 files (tag), 24× / 18 files
      (tag).
- [ ] The prune-candidate threshold is `cited
      ≤1× AND the heading date is more than 30
      days before today`. Entries meeting both
      render `→ prune-candidate (EXPIRES
      <today+30d> suggested)`. Per LESSONS
      2026-06-11 (BSD `date -j -f` fills missing
      time fields with NOW-of-day) the
      30-day-ago and today+30d math uses `date
      -v -30d +%Y-%m-%d` and `date -v +30d
      +%Y-%m-%d` (no `-j -f` involved — we
      walk from today's date forward/backward,
      not from a parsed string). Test asserts
      via fixtures at the boundaries: 2× cited
      35d ago (no tag — citation count too
      high), 0× cited 25d ago (no tag — too
      recent), 1× cited 35d ago (tag).
- [ ] The output is sorted by descending
      citation count, ties broken by ascending
      date (older entries first). Test asserts
      via fixture with two entries both cited
      5× — the older one ranks higher.
- [ ] `bin/fleet lessons-rank --top N` shows
      only the top N entries by citation count.
      `bin/fleet lessons-rank --bottom N` shows
      only the bottom N. Default (no flag) is
      "all entries." `--top 0` / `--bottom 0`
      prints `lessons-rank: --top/--bottom
      requires a positive integer` to stderr,
      exit 2 per LESSONS 2026-06-01. Test
      asserts all four branches.
- [ ] `bin/fleet lessons-rank --json` emits
      one structured JSON array, one element
      per entry: `[{"date": "YYYY-MM-DD",
      "headline": "<text>", "total_citations":
      <int>, "files_cited": <int>, "by_tree":
      {"bin/fleet": <int>, "lib": <int>,
      "prompts": <int>, "docs/backlog": <int>},
      "recommendation": "promote|prune|keep"},
      …]`. JSON escape via
      `preflight_json_escape` per LESSONS
      2026-06-03 called directly per LESSONS
      2026-06-13 (no `*_json_escape` wrapper).
      Test asserts JSON validity via Node.
- [ ] `bin/fleet lessons-rank --include-tests`
      adds `tests/*.sh` as a fifth file tree
      counted. Default behavior EXCLUDES tests
      (because a test that asserts "lesson X
      is defended against" cites the lesson
      for verification, not for use; counting
      it would inflate the score). Test asserts
      both modes via fixture.
- [ ] `bin/fleet lessons-rank --help` prints
      USAGE mentioning `--top`, `--bottom`,
      `--json`, `--include-tests`. Per LESSONS
      2026-05-30 test asserts via `grep -qF
      -- "$kw" "$help_out"`. Help block ends
      with `exit 0` per LESSONS 2026-06-01.
- [ ] `bin/fleet lessons-rank` is a PURE
      READER. NO `events.jsonl` writes, NO
      `fleet_emit_event` calls, NO writes
      to `docs/LESSONS.md`, NO writes to
      PRINCIPLES.md, NO writes to any
      backlog ticket. Test asserts the byte
      size of `docs/LESSONS.md`,
      `prompts/PRINCIPLES.md`, and a
      sampled backlog ticket is unchanged
      before and after invocation.
- [ ] `lib/common.sh` — NO changes.
      `prompts/` — NO changes. No new event
      types. Test asserts via `git diff
      --name-only main...HEAD -- lib/common.sh
      prompts/` returns empty.
- [ ] `tests/lessons-rank.sh` covers all 13
      boxes above using `$HOME/.local/bin`
      stubs per LESSONS 2026-05-26 (PATH
      reset). Fixture `LESSONS.md`,
      `bin/fleet`, `lib/common.sh`,
      `prompts/principles.md`, and a small
      `docs/backlog/` subdir live under
      `tests/fixtures/lessons-rank/`. Per
      LESSONS 2026-05-27 backup/restore via
      `cp` (NOT `$(cat)`). Counts use `awk …
      END { print n+0 }` per LESSONS
      2026-06-01. Per LESSONS 2026-06-08
      every awk script declares `BEGIN {
      count = 0 }`. Per LESSONS 2026-06-08
      IFS=$'\t' middle-empty-field uses `-`
      sentinel. Per LESSONS 2026-06-15
      no per-slug day-walk concern (this
      reader is repo-tree-grep-shaped, not
      per-slug-events-walk-shaped). The
      clock is frozen via
      `FLEET_NOW_OVERRIDE` for the
      prune-candidate 30-day math.
      Run-time budget: <10s.

## Out of scope

The dev agent will NOT do these even if they
seem related.

- AUTOMATICALLY editing `prompts/PRINCIPLES.md`
  to append a `P-N` block for each
  promote-candidate. v1 only RECOMMENDS; the
  operator does the edit. Auto-editing
  doctrine violates the "operator stays
  responsible for what doctrine says"
  principle in P-9.
- AUTOMATICALLY adding `EXPIRES: <date>`
  headers to prune-candidates in
  `docs/LESSONS.md`. Same reason — v1
  suggests, the operator applies.
- A `fleet lessons-rank --apply` flag that
  edits the file in-place. Hard NO for v1;
  see above.
- A CONFIGURABLE promote/prune threshold
  (`--promote-min N`). v1 hardcodes 10×/5
  files for promote and ≤1×/30d for prune
  so the score is comparable across
  operators. Custom thresholds are v2 if
  asked.
- A WEEKLY launchd schedule that runs the
  ranker and emails the operator. v1 is
  operator-invoked only. Launchd is the
  operator's choice.
- RANKING the CROSS_LESSONS feed (0009)
  separately. v1 ranks
  `docs/LESSONS.md` only — the
  CROSS_LESSONS file is a derived feed,
  and citation counts there double-count
  the same canonical entry. Cross-feed
  ranking is v2.
- A `--diff <since>` mode showing which
  lessons have RISEN or FALLEN in the
  ranking since a prior run. v1 is point-
  in-time. Trend tracking is v2 if asked
  (it would also need a persisted
  rank-history channel).
- RANKING PRINCIPLES citations. P-N
  citations are a separate ranking,
  served by 0024 `fleet prompts-score`
  in spirit (which grades prompt
  revisions). v1 is LESSONS-only.
- A GITHUB Action / pre-commit hook that
  blocks merges of PRs that would push
  a lesson above the EXPIRES window
  without action. Out of scope; the
  operator stays in the loop.
- A launchd schedule. Operator-invoked
  only.

## Engineering notes

Files / patterns the dev should touch.

- `bin/fleet` — new `lessons_rank()`
  dispatcher function placed next to the
  existing `lessons_promote()` block (find
  via `grep -n '^lessons_promote()'
  bin/fleet`). Per LESSONS 2026-05-26
  (`tail` shadow) `lessons_rank` does not
  collide with any coreutils binary.
- `bin/fleet` — seven helpers, ALL defined
  ABOVE the dispatcher block per LESSONS
  2026-06-05 (forward-reference trap):
  - `lessons_rank_extract_headings` — one
    awk pass over `docs/LESSONS.md`
    matching `^## ([0-9]{4}-[0-9]{2}-[0-9]
    {2}) — (.+)$`. Per LESSONS 2026-06-08
    `BEGIN { count = 0 }`. Per LESSONS
    2026-06-05 runs under `LC_ALL=C`.
  - `lessons_rank_count_citations` — for
    one date string, grep across the four
    file trees, returning per-tree count
    and unique-file count. Per LESSONS
    2026-05-30 the pattern is `grep -F --
    "$date"`. Per LESSONS 2026-06-01 the
    summing uses `awk … END { print n+0 }`
    or handles missing-file branch
    internally (NOT `grep -c file ||
    echo 0`).
  - `lessons_rank_classify` — given
    citation count and date age,
    returns `promote|prune|keep`. Per
    LESSONS 2026-06-11 the 30-day-ago
    math uses `date -v -30d +%Y-%m-%d`
    (no `-j -f`).
  - `lessons_rank_sort` — sorts by
    descending citation, ties broken by
    ascending date. Per LESSONS
    2026-06-08 IFS=$'\t' middle-empty-
    field uses `-` sentinel.
  - `lessons_rank_render_text` — text
    formatter per the Product-Owner
    example. Width via
    `preflight_visible_width` per
    LESSONS 2026-06-05. Per LESSONS
    2026-05-28 the printf of the
    headline goes through `printf
    -- '%s'`.
  - `lessons_rank_render_json` — JSON
    formatter. JSON escape via
    `preflight_json_escape` per LESSONS
    2026-06-03 called directly per
    LESSONS 2026-06-13 (no
    `*_json_escape` wrapper).
  - `lessons_rank_parse_topbottom` —
    validates `--top N` / `--bottom N`
    args per AC #8.
- `bin/fleet` — `lessons_rank()`
  end-state must be `exit 0` / `exit 2`
  on every code path per LESSONS
  2026-06-01.
- `bin/fleet` — dispatcher block: `if
  [ "$CMD" = "lessons-rank" ]; then
  lessons_rank "$@"; fi`. Place AFTER
  the `lessons_promote` dispatcher.
- `bin/fleet` — help banner block at
  the top of the file gets ONE new
  line: `fleet lessons-rank surface
  the most-cited LESSONS entries for
  promote/prune decisions`. README
  "Daily ops" code block gets the
  same line, appended via the same
  single-edit pattern that avoided
  LESSONS 2026-05-25.
- `AGENTS.md` — NO content change.
- `lib/common.sh` — NO changes.
- `prompts/` — NO changes.
- `docs/LESSONS.md` — NO changes
  (this is a READER over LESSONS;
  it never writes the file).
- `tests/fixtures/lessons-rank/` —
  NEW directory holding a fixture
  `LESSONS.md` with 8 headings of
  varying age (some <30 days old,
  some >30 days old), a fixture
  `bin/fleet` with embedded citation
  counts for each date, a fixture
  `lib/common.sh`, a fixture
  `prompts/principles.md`, and a
  fixture `docs/backlog/` with 4
  ticket files (each citing a
  different distribution of
  lessons). One fixture ticket
  cites a `LESSONS YYYY-MM-DD`
  inside a `LESSONS to defend
  against:` block — the canonical
  citation shape ranker must
  recognize.
- `tests/lessons-rank.sh` — top
  of file mirrors
  `tests/self-check.sh` (closest
  prior ticket; shares the
  repo-tree-grep shape). Stubs
  live under `$HOME/.local/bin`
  per LESSONS 2026-05-26 (PATH
  reset). Counts use `awk … END
  { print n+0 }` per LESSONS
  2026-06-01. Per LESSONS
  2026-05-27 backup/restore via
  `cp`. The clock is frozen via
  `FLEET_NOW_OVERRIDE` for the
  prune-candidate 30-day math.
  Run-time budget: <10s.
- New deps: none. Pure shell +
  awk + grep + Node (for JSON
  validation in tests).
- Public API: additive — `bin/fleet
  lessons-rank` is a new
  subcommand. ZERO new event
  types, ZERO event writes, ZERO
  `lib/common.sh` changes, ZERO
  `prompts/` changes, ZERO
  `docs/LESSONS.md` changes.
- BREAKING flag: NO. PR body
  affirms "pure reader, no
  LESSONS.md writes, no PRINCIPLES
  writes, no `fleet_*` signature
  changes, no runtime hot-path
  changes."
- Reinstall required: NO. `lib/`
  and `prompts/` are untouched.
- LESSONS to defend against:
  2026-05-25 (README "Daily ops"
  code block addition), 2026-05-26
  (`tail` shadow), 2026-05-26
  (PATH reset — stubs in
  `$HOME/.local/bin`), 2026-05-27
  (`$(cat)` trap — use `cp` for
  backup/restore in tests),
  2026-05-28 (printf leading-dash
  — every headline printf goes
  through `printf -- '%s'`),
  2026-05-30 (`grep -F --` trap —
  the date-citation grep passes
  the pattern via `grep -F --
  "$date"`), 2026-06-01 (`grep
  -c file || echo 0` double-print
  — per-file counts use `awk …
  END { print n+0 }` or handle
  missing-file branch internally),
  2026-06-01 (dispatcher
  fall-through — every code path
  ends `exit 0/2`), 2026-06-03
  (UTF-8 sign-extension — JSON
  escape via
  `preflight_json_escape`),
  2026-06-05 (dispatcher
  forward-reference — all
  `lessons_rank_*` helpers
  defined ABOVE the dispatcher),
  2026-06-05 (bash 3.2 LC_ALL
  caching — heading-extract awk
  runs under `LC_ALL=C`),
  2026-06-05 (export-in-subshell
  trap — any agents.config.sh
  read happens inside `( … )`),
  2026-06-08 (awk empty-string-
  key — `BEGIN { count = 0 }`),
  2026-06-08 (IFS=$'\t' middle-
  empty-field — sentinel `-`),
  2026-06-11 (BSD `date -j -f`
  fills missing time fields
  with NOW-of-day — the 30-day-
  ago math uses `date -v -30d`
  / `date -v +30d`, no `-j -f`
  involved), 2026-06-13 (no
  `*_json_escape` wrapper
  around `preflight_json_escape`
  — called directly).
- This ticket compounds 0018
  (`prompts/PRINCIPLES.md` —
  promote-candidates feed the
  operator's P-N additions),
  0039 (LESSONS expiry markers
  — prune-candidates feed
  EXPIRES additions), 0045
  (`fleet prompts-suggest` —
  the OTHER promotion signal,
  from event clusters), 0009
  (`fleet lessons-sync` —
  reads the same LESSONS file
  this ranks), 0028 (`fleet
  lessons-promote` — promotes
  drafts into the file
  ranked), 0040 (`fleet
  self-check` — consumer of
  the pattern catalog this
  ranks; ranker is the meta-
  view), 0031 (`fleet atlas`
  — failure-mode taxonomy
  cousin; ranks runs not
  doctrine), 0024 (`fleet
  prompts-score` — grades
  prompt revisions, the P-N
  ranker cousin in spirit).
  Per P-1 the diff is small:
  ~270 lines of `lessons_
  rank_*` helpers + ~250
  lines of test + 10 fixture
  files + one help-text line
  + one README line.

## Implementation log

(Appended by the implementation-dev agent during execution.)

### 2026-06-17 — in-progress

Branch `feat/0057-fleet-lessons-rank-citation-frequency` opened off
main. Status flipped from `groomed` to `in-progress`. README index row
0057 updated to match. About to write `tests/lessons-rank.sh` with the
13 acceptance-criteria scenarios, then add the seven `lessons_rank_*`
helpers + dispatcher + help banner line + README "Daily ops" line.

### 2026-06-17 — implementation

Test-first: `tests/lessons-rank.sh` written with 13 assertion blocks,
one per AC checkbox. Failing-first confirmed (the default invocation
fell through to `fleet status` because no dispatcher existed yet).

Implementation: 11 helpers (the 7 required + 4 scaffolding) inserted
into `bin/fleet` immediately after the `lessons-promote` dispatcher
and before the `lessons-prune` section. The hot path uses a single-pass
awk aggregator over a pre-built citations index (one awk invocation
per file in the four trees, not per-date × per-file) so the test
suite stays under the 10s budget — first cut at N_dates × N_files
greps ran 35s; the single-pass refactor brought it to 7.7s.

Date math is pure-awk Julian-day in `lessons_rank_ymd_shift`, so the
LESSONS 2026-06-11 `date -j -f` trap is structurally impossible.

Help banner line and README "Daily ops" line both added in the
single-edit shape per LESSONS 2026-05-25. Zero changes to
`lib/common.sh`, `prompts/`, or `docs/LESSONS.md`.

Local gate green: `shellcheck -S warning lib/*.sh bin/fleet`,
`bash -n lib/*.sh bin/fleet`, `node scripts/check-backlog.mjs`,
`FLEET_SELF_CHECK_GATE=1 bin/fleet self-check` (3 pre-existing
hits, zero new). `bash tests/lessons-rank.sh` reports all 13 ACs
PASSED.

### 2026-06-17 — shipped

PR #120 merged on `main` with both gating checks (`shellcheck`,
`validate`) green. Status flipped to `shipped` here and in the
README index row.
