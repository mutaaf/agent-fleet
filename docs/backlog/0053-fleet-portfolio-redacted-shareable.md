---
id: 0053
title: fleet portfolio --redact emits a leak-safe one-pager of the whole fleet for a blog post or peer demo
status: in-progress
priority: P1
area: observability
created: 2026-06-15
owner: gtm-innovation
---

## User story

As a fleet operator who has been running `agent-fleet` for a quarter
across 3-5 projects, who WANTS to evangelize the kit (post a one-pager on
their blog, paste a screenshot in a Slack DM to a peer, show their
co-founder over coffee) BUT who CANNOT safely share any of the existing
artifacts — `fleet recap` (0048), `fleet badge` (0027), `fleet milestone`
(0049), and `fleet pr-footer` (0044) all surface real slug names, real
PR numbers, real dollar amounts, real repo URLs — I want `bin/fleet
portfolio --redact` to compose ONE deterministically-redacted page that
preserves the SHAPE of the data (event-type counts, principle citations,
lesson hit-rate, streak length distribution, the kit's footer line)
while replacing every leakable string with a stable pseudonym
(`courtiq` → `project-a`, `PR #143` → `PR #aaa`, `$4.50` →
`$<budget-a>`), so I can share a leak-safe snapshot of "what this kit
does for me" without having to manually scrub seven artifacts every
time.

## Why now (four lenses)

### Product Owner
The kit's sharing surfaces today are all PER-SLUG and IDENTIFIED:
`fleet badge` paints a real-slug shields.io line; `fleet recap`
narrates the last N days with real PR numbers; `fleet milestone`
celebrates real streaks; `fleet pr-footer` posts on real PRs. These
are excellent for the operator's own record-keeping and for the
operator's PR reviewers — they are useless for evangelism because
they leak. An operator who wants to post "here's what running a
fleet of autonomous agents looks like" has to either (a) hand-scrub
every artifact (which most won't), (b) post unscrubbed and accept
the leak (which the careful operator won't), or (c) settle for
prose. The smallest meaningful unit of value is one command that
takes the operator's whole fleet, runs a deterministic redaction
pass over slug names, repo URLs, PR numbers, and cost figures, and
emits a one-page composed narrative shaped exactly like `fleet
recap` (0048) but safe to post. Subtraction: the operator stops
hand-scrubbing seven artifacts to make a blog post. Per P-5
(operator confidence over feature richness), the win is the absent
manual scrub.

The redaction is deterministic (the same slug always maps to the
same pseudonym in the same session) so the narrative reads
coherently — "project-a shipped 14 PRs while project-b shipped 6,
and project-a's streak crossed 21 days" makes sense to a reader
even though `project-a` is opaque. The pseudonym map is held in
memory only; the redacted output never leaks a real slug name and
the kit never writes a "redaction map" file (because if it did,
the operator would eventually post both files by accident).

### Stakeholder
This is **moat-deepening on the growth axis** — the kit's first
surface designed FOR the operator to share with NON-OPERATORS.
Per P-6 (telemetry is the source of truth), the portfolio is a
PURE READER over each slug's `events.jsonl`, the kit's
`runs.jsonl` cost channel (read by 0047 `fleet ticket-cost`), and
the static `prompts/PRINCIPLES.md`. No new event types. No writes
to any slug. The redaction is a thin pre-processor over the same
data `fleet recap` already composes — same composer, different
input filter.

The redaction table IS the moat: it codifies the kit's stance on
"what is shareable" — event-type COUNTS are shareable (no per-
event detail leaks), principle CITATIONS are shareable (PRINCIPLES
is public doctrine), streak LENGTHS are shareable, cost ORDER-OF-
MAGNITUDE is shareable, lesson HIT-RATE is shareable. What is
NOT shareable: slug names (replaced by `project-a`/`project-b`),
repo URLs (replaced by `<repo-a>`), PR numbers (replaced by
`PR #aaa`/`PR #bbb` — alphabetic pseudonyms preserve the "small
number" feel without revealing it), exact dollar amounts (rounded
to the nearest $5 OR replaced by `<budget-a>` band), lesson
headlines (TRUNCATED to first 6 words + ellipsis), file paths
inside engineering-notes blocks (replaced by `<path>`).

Per P-1 (smallest viable change), the diff is the redaction table
+ the pseudonym-allocator + the composer (reused from `fleet
recap` 0048 verbatim). ~400 lines. Compounds 0048 (`fleet recap`
— shares the narrative-composer helper), 0027 (`fleet badge` —
the badge line at the top of the portfolio is its redacted
form), 0042 (`fleet streak` — the streak-distribution table),
0043 (`fleet rank` — the leaderboard mid-section, redacted),
0044 (`fleet pr-footer` — one-line PR digest, redacted),
0049 (`fleet milestone` — the celebratory line if any slug just
crossed a threshold, redacted), 0047 (`fleet ticket-cost` —
the cost-magnitude band), 0009 (`fleet lessons-sync` — the
CROSS_LESSONS hit-rate row), 0018 (PRINCIPLES.md — the cited
principles).

### User (operator on a Sunday morning, writing a blog post about their loop)
The operator has been wanting to write up "how I run a fleet of
autonomous agents on my personal projects" for a month but keeps
not doing it because composing the post means manually scrubbing
seven artifacts. They run `fleet portfolio --redact > post.md`.
The output is one ~40-line markdown page:

```markdown
# my agent fleet — 90 days

I run an agent-fleet across 4 personal projects. Here's the
shape of the last 90 days.

## the loop, by the numbers
  PRs shipped (clean):           38  across all projects
  PRs healed in-flight:           7  (heal succeeded)
  PRs reverted by reviewer:       2  (rollback fired)
  send-backs requiring promotion: 12 (lesson_draft_emitted)
  CROSS_LESSONS hit-rate:        67% (lessons cited at PHASE 0)
  longest green streak:          21 days (project-a)
  total kit spend, this window:  ~$<budget-a band: 1-2x daily cap>

## the principles, by frequency cited
  P-3 (heal in-flight before new work)    cited 24 times
  P-5 (operator confidence over richness) cited 18 times
  P-1 (smallest viable change)            cited 14 times
  P-6 (telemetry is the source of truth)  cited 11 times
  …

## the slugs, redacted
  project-a  streak 21d  ROI +14 PRs/quarter  cost-band 1
  project-b  streak  7d  ROI  +6 PRs/quarter  cost-band 1
  project-c  streak  3d  ROI  +9 PRs/quarter  cost-band 2
  project-d  streak  0d  ROI  +4 PRs/quarter  cost-band 1
                       (paused — auto-resume via fleet resume)

## the kit
  source: github.com/<redacted>/agent-fleet
  install: one shell file (lib/install.sh, idempotent)
  schedule: launchd, hourly at :37
  generated by: fleet portfolio --redact
```

One paste into their blog. Zero scrubbing. Zero risk of leaking
"sidebrew" or `PR #14`. Per P-5, the win is the operator
finally publishing the post they have been not-writing for a
month.

Sub-scenario: the operator runs `fleet portfolio --redact
--keep-slug-names` for a peer they trust (the redaction still
strips PR numbers and dollar amounts but keeps the slug names
readable for the conversation). The pseudonym map is bypassed
for slug names only. Test asserts the flag.

### Growth
This is the surface that DIRECTLY widens the kit's funnel.
Today, an operator who wants to evangelize agent-fleet has
nothing leak-safe to share — the README pitches the kit but
"here's what MY fleet looks like" is the more persuasive
artifact. `fleet portfolio --redact` makes that artifact
producible in one command. Every redacted portfolio posted to
a blog or Slack thread is a new acquisition surface that links
back to the kit. Per the brief's "Operator GROUP / fleet
PORTFOLIO sharing — an operator who wants to evangelize the
kit to a peer has nothing they can safely share. A `fleet
portfolio --redact` mode that anonymizes slug names / PR
numbers / costs while preserving the SHAPE of the data" —
this is the direct answer.

Differentiated from `fleet recap` (0048): recap is for
the operator's own narrative consumption WITH real names;
portfolio is for shareable distribution WITHOUT them. The
two share the composer and diverge on the redaction filter.

Differentiated from `fleet badge` (0027): badge is one
shields.io-style line for a single project's README;
portfolio is a fleet-wide multi-section markdown page for
a blog post.

## Acceptance criteria

Each box maps 1:1 to a test scenario in `tests/portfolio.sh`.

- [ ] `bin/fleet portfolio` is a new subcommand. With no flags
      and at least one discovered slug, prints the portfolio
      page to stdout WITHOUT redaction (real slug names, real
      PR numbers, real dollar amounts) — same UX as `fleet
      recap` (0048) but fleet-wide instead of per-slug. With
      `--redact`, applies the redaction pass per AC #4–AC #9.
      With zero discovered slugs, prints `portfolio: no
      slugs discovered. run \`fleet onboard <repo>\` to add
      the first project to your fleet.` exit 0. Test asserts
      via fixture with zero slugs.
- [ ] `bin/fleet portfolio --redact` deterministically maps
      each discovered slug to a stable pseudonym
      `project-a`, `project-b`, … in the alphabetical order
      the slug names appear in `overview_discover_slugs`'s
      output. The mapping is held in memory only — NO
      file is written that pairs real names with pseudonyms.
      Test asserts via fixture with three slugs (`alpha`,
      `beta`, `gamma`) that the output contains `project-a`,
      `project-b`, `project-c` and NEVER contains `alpha` /
      `beta` / `gamma` anywhere in the rendered output.
- [ ] The redaction rewrites every occurrence of a real
      slug name in PR titles, branch names, and lesson
      headlines to its pseudonym. The match is whole-word
      `\<slug\>` so partial substrings (e.g. a slug named
      `apt` doesn't rewrite occurrences of `aptitude`) are
      preserved. Per LESSONS 2026-06-05 (bash 3.2 LC_ALL
      caching) the boundary match uses `LC_ALL=C awk`.
      Test asserts via fixture with overlapping-name slugs.
- [ ] PR numbers in the rendered output are replaced by
      pseudonyms `PR #aaa`, `PR #bbb`, `PR #ccc` …
      deterministically (the same real PR number always
      maps to the same pseudonym in the same session). The
      pseudonym preserves the "small natural number" feel
      without revealing it. Test asserts via fixture that
      the real PR numbers (e.g. `#14`, `#143`, `#1024`) do
      not appear anywhere in `--redact` output.
- [ ] Dollar amounts in the rendered output are bucketed
      into bands: `<$1`, `~$1`, `~$2`, `~$5`, `~$10`,
      `~$25`, `~$50`, `~$100`, `>$100`. Each amount is
      replaced by the nearest band string. Test asserts
      via fixture with `$0.42`, `$4.50`, `$11.20`,
      `$47.00`, `$118.00`.
- [ ] Repo URLs in the kit's footer are replaced by
      `github.com/<redacted>/<repo-pseudonym>` (where
      `<repo-pseudonym>` is the same slug pseudonym from
      AC #2). Test asserts that no real GitHub org / user
      / repo name appears in `--redact` output via fixture
      with `git@github.com:realuser/courtiq.git`.
- [ ] Lesson headlines surfaced in the portfolio (from
      `lesson_draft_emitted` events, citing the lesson
      hit-rate) are truncated to the first 6 words plus
      `…` to prevent verbatim leakage of an operator's
      private prose. Per LESSONS 2026-05-28 the printf of
      each truncated headline goes through `printf -- '%s'`.
      Test asserts via fixture lesson headlines of varying
      lengths.
- [ ] File paths inside lesson bodies are replaced by
      `<path>`. Per LESSONS 2026-05-30 (`grep -F --` trap),
      the path-detection regex uses `grep -E --` with the
      anchored pattern `(/[a-zA-Z_][a-zA-Z0-9_./-]*)`.
      Test asserts via fixture lesson with absolute paths.
- [ ] `bin/fleet portfolio --redact --keep-slug-names`
      bypasses the slug-name rewrite (real slug names
      appear in the output) BUT still applies all OTHER
      redactions (PR numbers, dollar amounts, repo URLs,
      lesson truncation, paths). Useful for sharing with
      a peer who already knows the slug names but not
      the cost numbers. Test asserts.
- [ ] `bin/fleet portfolio --since <Nd|YYYY-MM-DD>`
      overrides the default 90-day window for the events
      walk. Per LESSONS 2026-06-11 (BSD `date -j -f` fills
      missing time fields with NOW-of-day) the `--since
      YYYY-MM-DD` value appends `T00:00:00` before any
      date math. Test asserts both formats.
- [ ] `bin/fleet portfolio --json` emits one structured
      JSON object with three top-level keys: `summary`
      (the by-the-numbers block), `principles` (the
      frequency-cited list), `slugs` (the per-slug
      one-liner with the pseudonym OR real slug
      depending on `--redact` / `--keep-slug-names`). JSON
      escape via `preflight_json_escape` per LESSONS
      2026-06-03 and called directly per LESSONS
      2026-06-13 (no `*_json_escape` wrapper). Test
      asserts JSON validity via Node.
- [ ] `bin/fleet portfolio --help` prints USAGE
      mentioning `--redact`, `--keep-slug-names`,
      `--since`, `--json`. Per LESSONS 2026-05-30 test
      asserts via `grep -qF -- "$kw" "$help_out"`. Help
      block ends with `exit 0` per LESSONS 2026-06-01
      (dispatcher fall-through).
- [ ] `bin/fleet portfolio` is a PURE READER. NO
      `events.jsonl` writes, NO `fleet_emit_event` calls,
      NO writes to any file in any slug. Test asserts
      every slug's `events.jsonl` byte size is unchanged
      before and after invocation.
- [ ] The pseudonym map is NEVER written to disk. Test
      asserts via fixture that after `fleet portfolio
      --redact` runs in a `TMPDIR`, no file under
      `TMPDIR` or anywhere else newly created contains
      both a real slug name AND its pseudonym. The
      assertion grep is `grep -F -- "$real_slug" $newly_
      created_files` returns empty.
- [ ] `lib/common.sh` — NO changes. `prompts/` — NO
      changes. No new event types. Test asserts via
      `git diff --name-only main...HEAD -- lib/common.sh
      prompts/` returns empty.
- [ ] `tests/portfolio.sh` covers all 14 boxes above
      using `$HOME/.local/bin` stubs per LESSONS
      2026-05-26 (PATH reset). Fixture `events.jsonl`
      and `runs.jsonl` per slug live under
      `tests/fixtures/portfolio/`. Per LESSONS
      2026-05-27 backup/restore via `cp` (NOT
      `$(cat)`). Counts use `awk … END { print n+0 }`
      per LESSONS 2026-06-01. Per LESSONS 2026-06-08
      every awk script declares `BEGIN { count = 0 }`.
      Per LESSONS 2026-06-08 IFS=$'\t' middle-empty-
      field uses `-` sentinel. The clock is frozen via
      `FLEET_NOW_OVERRIDE`. Run-time budget: <12s.

## Out of scope

The dev agent will NOT do these even if they seem related.

- AUTO-POSTING the portfolio to a blog / GitHub Gist /
  Slack. v1 prints to stdout; the operator pipes to a
  file. Auto-posting violates the "no auto-upload"
  Hard NO from the brief.
- A WEB-rendered portfolio (HTML/CSS). Shell-only kit;
  HTML is out of scope.
- A `--diff` mode comparing two windows ("this quarter
  vs last quarter"). v1 is one window. Cross-window
  diff is v2.
- An `--upload` flag that posts the redacted portfolio
  to a public aggregator for cohort benchmarking.
  Explicit anti-goal per the brief: "any cohort
  surface MUST be opt-in and MUST NOT auto-upload."
  Cohort comparison is a separate ticket (gap #5 in
  the brief).
- INCLUDING the kit's CROSS_LESSONS feed verbatim. The
  feed contains operator-specific lesson prose that
  the redaction can't safely scrub at sentence level.
  v1 includes only COUNTS (hit-rate %, total entries),
  not bodies. Including bodies is a v2 if asked.
- REDACTING the kit's PRINCIPLES.md citations (`P-3`,
  `P-5`, etc). PRINCIPLES is public doctrine; citation
  is not a leak. Test asserts that `P-N` citations are
  preserved verbatim.
- A `fleet portfolio <slug>` per-slug mode. v1 is
  fleet-wide only. Per-slug narrative is already
  served by `fleet recap` (0048).
- Modifying `fleet recap` (0048) to share the
  redaction filter. v1 duplicates the composer call
  to keep recap as the un-redacted surface and
  portfolio as the redacted one. Convergence is a v2
  refactor if both prove stable.
- A launchd schedule. Operator-invoked only.
- AUTO-MEMORIZING the pseudonym map across runs (so
  `project-a` in tomorrow's portfolio refers to the
  SAME real slug as today's). The pseudonyms are
  per-invocation; a reader of two redacted portfolios
  from different days cannot cross-reference them.
  Test asserts that two consecutive `fleet portfolio
  --redact` runs in different processes produce the
  SAME alphabetic mapping (because the slug
  discovery order is stable) but NEVER serialize the
  mapping to disk.

## Engineering notes

Files / patterns the dev should touch.

- `bin/fleet` — new `portfolio()` dispatcher function
  placed next to the existing `recap()` block (find
  via `grep -n '^recap()' bin/fleet`). Per LESSONS
  2026-05-26 (`tail` shadow) `portfolio` does not
  collide with any coreutils binary.
- `bin/fleet` — eight helpers, ALL defined ABOVE the
  dispatcher block per LESSONS 2026-06-05 (forward-
  reference trap):
  - `portfolio_discover_slugs` — wraps
    `overview_discover_slugs`, returns alphabetical
    order.
  - `portfolio_allocate_pseudonyms` — given the
    sorted slug list, returns a TSV
    `real_slug<TAB>pseudonym` table in memory (held
    in a shell array; NEVER written to a file).
    Per LESSONS 2026-06-08 IFS=$'\t' uses `-`
    sentinel; per LESSONS 2026-06-08 the awk script
    declares `BEGIN { count = 0 }`.
  - `portfolio_redact_text` — given input text and
    the pseudonym table, rewrites slug names,
    PR numbers, dollar amounts, repo URLs, file
    paths, and truncates lesson headlines. Per
    LESSONS 2026-06-05 (bash 3.2 LC_ALL caching)
    the boundary match uses `LC_ALL=C awk`.
  - `portfolio_walk_events` — reads each slug's
    `events.jsonl` in the window, emits TSV rows
    consumed by the composer. Per LESSONS
    2026-06-08 IFS=$'\t' uses `-` sentinel.
  - `portfolio_aggregate_costs` — reads each
    slug's `runs.jsonl` (the cost channel from
    ticket 0047), sums and bands per AC #5.
  - `portfolio_compose_summary` — renders the
    "by the numbers" block.
  - `portfolio_compose_principles` — counts
    `principle_id` citations across the window,
    renders the frequency list.
  - `portfolio_render_text` and
    `portfolio_render_json` — formatters. Width
    via `preflight_visible_width` per LESSONS
    2026-06-05; JSON escape via
    `preflight_json_escape` per LESSONS 2026-06-03
    called directly per LESSONS 2026-06-13 (no
    `*_json_escape` wrapper).
- `bin/fleet` — `portfolio()` end-state must be
  `exit 0` on every code path per LESSONS
  2026-06-01.
- `bin/fleet` — dispatcher block: `if [ "$CMD"
  = "portfolio" ]; then portfolio "$@"; fi`. Place
  AFTER the `recap` dispatcher.
- `bin/fleet` — help banner block at the top of
  the file gets ONE new line: `fleet portfolio
  --redact emit a leak-safe fleet-wide one-pager`.
  README "Daily ops" code block gets the same
  line, appended via the same single-edit pattern
  that avoided LESSONS 2026-05-25.
- `bin/fleet` — `portfolio` REUSES the composer
  helper from `fleet recap` (0048) via a shared
  function. Find via `grep -n '^recap_compose'
  bin/fleet` and pass the redacted-vs-original
  input to it. The composer itself is unchanged
  (zero edits to `recap_*` helpers).
- `AGENTS.md` — NO content change.
- `lib/common.sh` — NO changes.
- `prompts/` — NO changes.
- `tests/fixtures/portfolio/` — NEW directory
  holding three slug subdirs (`alpha`, `beta`,
  `gamma`) each with `events.jsonl`,
  `runs.jsonl`, and `agents.config.sh`; the
  events include a mix of `pr_opened`,
  `run_completed`, `lesson_draft_emitted` with
  varied PR numbers, varied dollar amounts in
  runs.jsonl, varied lesson headlines, a repo
  URL with the org name `realuser`, and lesson
  bodies with absolute file paths.
- `tests/portfolio.sh` — top of file mirrors
  `tests/recap.sh` (the closest prior ticket;
  shares the composer call shape). Stubs live
  under `$HOME/.local/bin` per LESSONS
  2026-05-26 (PATH reset). Counts use `awk …
  END { print n+0 }` per LESSONS 2026-06-01.
  Per LESSONS 2026-05-27 backup/restore via
  `cp`. The clock is frozen via
  `FLEET_NOW_OVERRIDE`. Run-time budget: <12s.
- New deps: none. Pure shell + awk + existing
  helpers (`preflight_json_escape`,
  `preflight_visible_width`, the `recap_*`
  composer).
- Public API: additive — `bin/fleet portfolio`
  is a new subcommand. ZERO new event types,
  ZERO event writes, ZERO `lib/common.sh`
  changes, ZERO `prompts/` changes.
- BREAKING flag: NO. PR body affirms "pure
  reader, no events.jsonl writes, no
  `fleet_*` signature changes, no runtime
  hot-path changes, no pseudonym map written
  to disk."
- Reinstall required: NO. `lib/` and
  `prompts/` are untouched.
- LESSONS to defend against: 2026-05-25
  (README "Daily ops" code block addition),
  2026-05-26 (`tail` shadow), 2026-05-26
  (PATH reset — stubs in `$HOME/.local/bin`),
  2026-05-27 (`$(cat)` trap — use `cp` for
  backup/restore in tests), 2026-05-28
  (printf leading-dash — every truncated-
  headline printf goes through `printf -- '%s'`),
  2026-05-30 (`grep -F --` trap — path-
  detection grep uses `grep -E --`),
  2026-06-01 (`grep -c file || echo 0`
  double-print — counts use `awk … END
  { print n+0 }`), 2026-06-01 (dispatcher
  fall-through), 2026-06-03 (UTF-8
  sign-extension — JSON escape via
  `preflight_json_escape`), 2026-06-05
  (dispatcher forward-reference), 2026-06-05
  (bash 3.2 LC_ALL caching — boundary match
  via `LC_ALL=C awk`), 2026-06-05 (export-
  in-subshell trap — source-manifest reads
  inside `( … )`), 2026-06-08 (awk empty-
  string-key — `BEGIN { count = 0 }`),
  2026-06-08 (IFS=$'\t' middle-empty-field
  — sentinel `-`), 2026-06-11 (BSD `date
  -j -f` fills missing time fields with
  NOW-of-day — `--since YYYY-MM-DD` appends
  `T00:00:00`), 2026-06-13 (no `*_json_escape`
  wrapper around `preflight_json_escape` —
  called directly).
- This ticket compounds 0048 (`fleet recap`
  — shares the composer), 0027 (`fleet
  badge` — the top-of-portfolio badge
  line, redacted), 0042 (`fleet streak`
  — the streak-distribution row), 0043
  (`fleet rank` — the leaderboard mid-
  section, redacted), 0044 (`fleet
  pr-footer` — the one-line PR digest,
  redacted), 0049 (`fleet milestone` —
  the celebratory line if any slug crossed
  a threshold), 0047 (`fleet ticket-cost`
  — reads `runs.jsonl` for the cost
  band), 0009 (`fleet lessons-sync` —
  reads CROSS_LESSONS for the hit-rate),
  0018 (`prompts/PRINCIPLES.md` — the
  cited principles list), 0019 (`fleet
  overview` — reuses
  `overview_discover_slugs`). Per P-1
  the diff is small: ~350 lines of
  `portfolio_*` helpers + ~300 lines
  of test + 9 fixture files (3 slugs
  × 3 files each) + one help-text line
  + one README line.

## Implementation log

(Appended by the implementation-dev agent during execution.)

### 2026-06-15 — implementation-dev pickup
- Branch: `feat/0053-fleet-portfolio-redact`.
- Status flipped to `in-progress` in the same branch; backlog index row updated to match (per LESSONS 2026-05-22 README index/file drift).
- Approach: a new `portfolio()` dispatcher placed next to `recap()` (~line 8806) sharing the per-slug walkers from `recap_*` for events/runs/streak math but adding a fleet-wide redaction pre-processor before render. Pure reader: no `lib/`, no `prompts/`, no `events.jsonl` writes, no new event types. ~350 lines of `portfolio_*` helpers + ~350 lines of test + fixtures + one README/help line.
