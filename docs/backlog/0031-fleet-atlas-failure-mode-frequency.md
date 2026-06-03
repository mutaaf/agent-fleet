---
id: 0031
title: fleet atlas prints the fleet-wide failure-mode taxonomy with per-pattern frequency
status: shipped
priority: P2
area: observability
created: 2026-06-03
owner: gtm-innovation
---

## User story

As a fleet operator who has been running 4 projects through the kit
for 30+ days and wants to see — at a glance — which of the four
heal-catalog infra-flake patterns actually fired in the wild,
how often each fired, when each was last seen, and which projects
each bit (so I can decide whether
`gh_graphql_502` deserves a wider regex or `actions_silent` is
healed enough to demote), I want
`bin/fleet atlas [--since 30d] [--json] [--slug NAME]` to render a
single table joining `lib/heal-catalog.sh` patterns with the
`infra_flake_rerun` events across every project's
`events.jsonl`, so that the kit's collective resilience knowledge
becomes a visible asset instead of a hand-curated config the
operator never sees executed.

## Why now (four lenses)

### Product Owner
The heal catalog at `lib/heal-catalog.sh` is a thirty-seven-line
artifact that powers a load-bearing safety: the runner detects
infra flakes (per ticket 0020) and self-heals via `gh run rerun`
instead of burning tokens on a code fix. Each pattern is annotated
inline with the LESSON that birthed it. But: the operator has NO
surface that joins "patterns in the catalog" with "patterns that
actually fired in the wild." The catalog is INPUT-only today. The
smallest meaningful unit of value is one table that closes that
loop:

```
PATTERN              FIRED  LAST SEEN     PROJECTS         LESSON
actions_silent           4  2h ago        agent-fleet      2026-05-26
supabase_port_bind       1  21d ago       courtiq          2026-05-25
account_suspended        0  —             —                2026-05-26
gh_graphql_502           7  3h ago        courtiq,almanac  2026-05-21
```

Subtraction: the operator stops having to grep four `events.jsonl`
files to see which patterns are pulling their weight. The output is
also the natural deciding surface for "should this pattern be
demoted/tightened/widened" — frequency + last-seen are the inputs
to that decision. Per P-5 (operator confidence), this is the
catalog earning its keep visibly.

### Stakeholder
This is moat-deepening of a kind no other autonomous-agent kit
ships: the kit's collective immune system becomes a per-pattern
report card. The catalog already references LESSONS dates inline
(`lib/heal-catalog.sh` lines 21, 26, 30, 34); `fleet atlas` reads
those references through and renders them as columns. The result
is a small but durable artifact that says "agent-fleet learned
these failures from these projects on these dates and has fired
the heal N times since." That is the kit's resilience layer
made public. A natural follow-up (out of scope here) is
`fleet atlas --propose` that suggests a new pattern from
unmatched send-back transcripts, but v1 is reader-only — the
audit before the activism. Compounds 0020 (catalog +
`infra_flake_rerun` event) and 0019 (cross-project table
rendering style). The catalog file is the substrate; atlas is
the dashboard.

### User (operator, Sunday morning, deciding whether to PR a
new catalog pattern)
Runs `bin/fleet atlas --since 30d`. Sees the table above.
Notices `account_suspended` has fired ZERO times in 30 days
(matches their experience — that pattern hit once, never again).
Considers demoting it but reads the inline LESSON and keeps it
(rare-but-real failures are the catalog's whole point).
Notices `gh_graphql_502` is the most-frequent pattern (7 fires
in 30d across two projects). Confidence: "the catalog is working
— two projects' worth of GraphQL flakes self-healed past instead
of burning a heal: attempt apiece." Pipes through `--json` to
fleet-control's "Resilience" pane and gets a same-shape
machine-readable artifact.

### Growth
"Show me where the kit's safety net actually catches something"
is a credibility question every adopter eventually asks. The
catalog is a list; the atlas turns it into a report. A friend
running their own loop sees the atlas and immediately gets why
the kit's catalog file is hand-curated rather than ML-mined —
small, auditable, dated to a specific LESSON, with a frequency
that proves each entry is doing work. The output also doubles
as the cheapest possible "show, don't tell" demo for the kit's
resilience claim — much like `fleet badge` (0027) became the
acquisition surface for the ROI claim, atlas becomes the
acquisition surface for the resilience claim. The two pair
naturally in a README ("here's what the fleet shipped, here's
what it survived").

## Acceptance criteria

Each box maps 1:1 to a test scenario in `tests/atlas.sh`.

- [ ] `bin/fleet atlas` (no flags) defaults to `--since 30d`
      and surveys EVERY project under `FLEET_DISCOVERY_ROOT`.
      Exits 0. Prints a header row `PATTERN  FIRED  LAST SEEN
      PROJECTS  LESSON` followed by one row per pattern in
      `lib/heal-catalog.sh`'s `FLEET_HEAL_PATTERNS` array
      ORDER (not alphabetical — the order in the catalog is
      the priority, per `fleet_match_infra_flake`'s
      first-win semantics). Test fixtures three projects with
      a synthetic `events.jsonl` each and asserts the
      ordered output via a checked-in golden
      `tests/fixtures/atlas.text.golden.txt`.
- [ ] `FIRED` column is the count of `infra_flake_rerun`
      events with `pattern=<token>` in the window across
      every surveyed project. Reuses the JSON-scan awk
      pattern from `inbox_budget_block_today` (bin/fleet
      ~2246) — no `jq`. Patterns with zero matches still
      render with `FIRED=0` and `LAST SEEN=—`. Test asserts
      both nonzero and zero-row branches.
- [ ] `LAST SEEN` is `human_age` (bin/fleet line ~60)
      against the newest matching event's ts. For a zero-
      match pattern, the column reads `—`. Test asserts both
      branches.
- [ ] `PROJECTS` is a comma-joined sorted list of slugs that
      contributed at least one event in the window. Capped
      at 3 slugs followed by `+N` when more match (avoids a
      runaway column on wide deployments). Per LESSONS
      2026-05-28 (printf leading-dash trap), the column is
      rendered via `printf -- '%-16s'` so a slug starting
      with `-` is harmless. Test fixtures a 5-project match
      and asserts the `+2` truncation.
- [ ] `LESSON` is the YYYY-MM-DD date parsed from the inline
      `# LESSON: <repo> YYYY-MM-DD …` comment immediately
      preceding each pattern entry in `lib/heal-catalog.sh`.
      Parsed via awk against the catalog file at run time —
      NOT hard-coded in `bin/fleet`. Caller resolves the
      catalog path via `${FLEET_HEAL_CATALOG:-<kit-root>/lib/
      heal-catalog.sh}` (same env override
      `fleet_match_infra_flake` honors — common.sh ~1033).
      Patterns with no preceding LESSON comment render the
      column as `(no lesson)`. Test asserts both branches.
- [ ] `--since <Nh|Nd>` parses via `digest_parse_since`
      (bin/fleet ~1140). Invalid value: `atlas: invalid
      --since "<v>" (use Nh or Nd)` to stderr, exit 2. Test
      covers `30d`, `7d`, `48h`, and an invalid `forever`.
- [ ] `--slug NAME` restricts the survey to ONE project.
      Header and all rows render as if the only project was
      `<NAME>`. Unknown slug: `atlas: no project with
      SLUG=<slug> found (looked under
      FLEET_DISCOVERY_ROOT=<path>)` to stderr, exit 2. Test
      asserts both the happy path and the error.
- [ ] `--json` emits one JSON object per pattern row plus
      one summary row at the end (matches `inbox`'s JSON
      shape from line ~2585): `{"pattern":"<token>",
      "fired":N,"last_seen_ts":"<iso8601|null>","projects":[
      "<slug>",...],"lesson_date":"<YYYY-MM-DD|null>"}` per
      row, then `{"summary":true,"patterns":<N>,"window":
      "30d","fired_total":<M>}`. Parsed via `node -e
      'JSON.parse(...)'`. Test asserts the full document
      structure.
- [ ] Empty fleet (no projects discovered): the text path
      still renders the header + one row per catalog pattern
      with `FIRED=0`, `LAST SEEN=—`, `PROJECTS=—`. JSON path
      renders one object per pattern with `fired=0`,
      `last_seen_ts=null`, `projects=[]`, plus the summary
      row. Exit 0. The atlas is honest about a cold fleet
      rather than failing.
- [ ] Catalog file missing or unreadable: `atlas: heal
      catalog not found at <path> (set FLEET_HEAL_CATALOG to
      override)` to stderr, exit 2. Test asserts the error
      branch with `FLEET_HEAL_CATALOG=/nonexistent`.
- [ ] No new event types. `atlas` is a pure consumer of the
      existing telemetry channel + the existing catalog file
      (P-6: telemetry is the source of truth; readers
      compose, they do not invent). The PR body affirms "no
      new event types added; no AGENTS.md § Telemetry
      append needed."
- [ ] Help: `bin/fleet atlas --help` prints a USAGE block
      mentioning `--since`, `--slug`, `--json`, `--help`,
      plus a one-line description per flag. Test asserts via
      `grep -qF -- "$kw" "$help_out"` per LESSONS
      2026-05-30. Help block ends with `exit 0` per LESSONS
      2026-06-01 (dispatcher fall-through trap).
- [ ] `tests/atlas.sh` covers all 11 boxes using
      `$HOME/.local/bin` stubs (per LESSONS 2026-05-26) for
      any command shelled out to. `FLEET_DISCOVERY_ROOT`
      redirected to `tests/fixtures/atlas/` and
      `FLEET_HEAL_CATALOG` redirected to
      `tests/fixtures/atlas.catalog.sh` (a copy of the real
      catalog plus one synthetic 5th pattern to exercise the
      "pattern not in real catalog" path). Per LESSONS
      2026-05-27, the test uses `cp` for backup/restore —
      never `$(cat …)`. Run-time budget: <10s.

## Out of scope

The dev agent will NOT do these even if they seem related.

- Proposing a NEW catalog pattern (`fleet atlas --propose`).
  ML-mining patterns from send-back transcripts is OUT OF
  SCOPE per ticket 0020's own out-of-scope clause. v1 reads;
  v2 may propose.
- Editing the catalog in place. The catalog is hand-curated;
  the atlas READS it. Edits stay PR-gated.
- Demoting a pattern automatically based on frequency. The
  whole point of a hand-curated catalog is human judgment —
  a rare-but-real failure (account_suspended) should stay
  even if its frequency is 0 in a 30d window.
- Heal-attempt aggregation (counts of `heal:` commits per
  pattern, send-back rate per pattern). The atlas's job is
  the INFRA-FLAKE side — the safe self-rerun. Send-backs are
  `fleet weekly`'s and `fleet provenance`'s territory.
- A cron / launchd schedule. Like `weekly`, `inbox`, `badge`,
  the operator runs it by hand or pipes through their own
  cron. Adding a launchd surface adds an uninstall surface
  for zero added value.
- Multi-window comparison (e.g. "30d vs prior 30d"). v1 is
  one window. Comparison belongs in a sibling ticket once
  the single-window primitive ships and an operator has
  asked for it.
- Filtering by pattern token (`--pattern gh_graphql_502`).
  The full table is small (4 rows today; one screen even at
  N=20). Filtering is `grep | head` territory and adds a
  flag for no real benefit at v1.

## Engineering notes

Files / patterns the dev should touch. Specific enough that
the dev doesn't have to re-discover the architecture.

- `bin/fleet` — new `atlas()` dispatcher next to
  `overview()` (line ~4889) and `prompts_score()` (line
  ~2906). Shape mirrors `overview()`: cross-project survey
  + table render + `--json` toggle.
- `bin/fleet` — five helpers, all pure readers:
  - `atlas_parse_catalog()` — awk over the catalog file:
    extracts each `<token>|<ERE>` entry from the
    `FLEET_HEAL_PATTERNS=( … )` array, plus the
    YYYY-MM-DD from the comment line immediately
    preceding the entry. Echoes one `<token>\t<lesson-
    date>` line per pattern in catalog order. Reuses
    awk's first-match-wins reading shape, NOT
    `source`-ing the catalog (sourcing would pull
    `FLEET_HEAL_PATTERNS` into the shell, which is
    correct, but parsing the comments REQUIRES reading
    the file as text anyway — awk handles both in one
    pass).
  - `atlas_count_pattern()` — count `infra_flake_rerun`
    events for one pattern across all surveyed projects'
    `events.jsonl`, within the window. Reuses
    `inbox_budget_block_today` (bin/fleet ~2246) JSON-scan
    awk shape (no jq).
  - `atlas_last_seen_pattern()` — newest matching event's
    ts → `human_age` (bin/fleet ~60).
  - `atlas_projects_for_pattern()` — list of distinct
    slugs that contributed at least one matching event,
    sorted, capped at 3 + `+N` overflow marker.
  - `atlas_render_row_text/json()` — one per output mode.
    Per LESSONS 2026-05-28, every `printf` format begins
    with `printf -- '%s\n' …` style. Per LESSONS
    2026-06-01 awk-newline trap, NO multi-line value
    goes through `awk -v` — every awk call works with
    file paths or single-line tokens.
- `bin/fleet` — `atlas()` end-state must be `exit 0` (or
  `exit 2` per AC) on every code path per LESSONS
  2026-06-01 (dispatcher fall-through trap). Copy the
  exit-0 pattern from `overview()` (line ~4889 — verify
  its exit-0 by reading the file) verbatim.
- `bin/fleet` — dispatcher block at the bottom of the
  file: `if [ "$CMD" = "atlas" ]; then atlas "$@"; fi`.
  Placed after the existing `lessons-promote` block (line
  ~5920).
- `bin/fleet` — help banner block at the top of the file
  (around line ~14) gets a new line: `fleet atlas
  fleet-wide infra-flake catalog with per-pattern
  frequency (text/json)`. README "Daily ops" code block
  gets the same.
- `lib/common.sh` — NO changes. `atlas` is a pure reader;
  per P-6 it does not emit new events. The PR body
  affirms this so the reviewer's telemetry-contract check
  stays satisfied. NO `fleet_*` signature changes.
- `lib/heal-catalog.sh` — NO changes. `atlas` reads it
  via the same `FLEET_HEAL_CATALOG` env override
  `fleet_match_infra_flake` already honors (common.sh
  ~1033). Catalog stays hand-curated and PR-gated.
- `prompts/` — NO changes. The command is operator-facing
  only; no agent prompt reads `fleet atlas`. No
  `Reinstall: all projects` line is needed because
  `lib/` and `prompts/` are untouched.
- `tests/fixtures/atlas/` — NEW directory under
  `tests/fixtures/` holding:
  - three synthetic `<slug>/agents.config.sh` files
  - three synthetic `events.jsonl` files seeded with a
    mix of `infra_flake_rerun` events across two of the
    four real patterns plus one synthetic 5th pattern
    (covers the 5-project `+N` cap test and the lesson-
    missing branch)
  - one `tests/fixtures/atlas.catalog.sh` — a copy of
    `lib/heal-catalog.sh` with one extra pattern that
    has NO preceding LESSON comment (exercises the
    `(no lesson)` branch from AC#5)
  - one golden `tests/fixtures/atlas.text.golden.txt`
    with the exact expected output for the default
    invocation
- `tests/atlas.sh` — top of file mirrors
  `tests/overview.sh`: redirect `FLEET_DISCOVERY_ROOT`,
  redirect `FLEET_HEAL_CATALOG`, stub `gh` and any
  network-shelling tool under `$HOME/.local/bin`
  (`$HOME=$TMP/home` per LESSONS 2026-05-26) — the
  command must succeed reading only local channel
  files. The JSON test parses output via `node -e
  'JSON.parse(require("fs").readFileSync(0,"utf8"))'`.
- New deps: none. Pure shell + awk + existing
  `digest_parse_since` (bin/fleet ~1140), `human_age`
  (bin/fleet ~60), and the `inbox_budget_block_today`-
  style JSON-scan awk pattern (bin/fleet ~2246).
- Public API: additive — `bin/fleet atlas` is a new
  subcommand, no new event types, no `fleet_*`
  signature changes.
- BREAKING flag: NO. PR body affirms "no `fleet_*`
  signature changes" and "no new event types added."
- Reinstall required: NO. `lib/` and `prompts/` are
  untouched.
- LESSONS to defend against: 2026-05-26 (`tail` shadow —
  `atlas` does not collide with any common binary;
  verified via `command -v atlas`). LESSONS 2026-05-27
  ($(cat) trap — every fixture read uses `cp`/awk).
  LESSONS 2026-05-28 (printf leading-dash trap — every
  `printf` of a slug or pattern token uses `printf --
  '%s'`). LESSONS 2026-05-30 (`grep -F --` flag trap —
  the help-text assertion and any pattern-token grep
  use `grep -qF --`). LESSONS 2026-06-01 (awk -v
  multiline trap — every awk -v value here is a
  single-line token; the catalog body is read by file
  path). LESSONS 2026-06-01 (`grep -c file || echo 0`
  double-print trap — counts use awk, never `grep -c
  || echo 0`). LESSONS 2026-06-01 (dispatcher
  fall-through trap — `atlas()` ends with explicit
  `exit 0` on every path including the help block).
- This ticket compounds 0002 (events.jsonl as the
  source of truth), 0019 (cross-project table render
  style), 0020 (heal catalog + `infra_flake_rerun`
  event). It introduces ZERO new substrate; every
  primitive it reads already exists. Per P-1 the diff
  is small: ~250 lines of `atlas*` helpers + ~120
  lines of test fixture content + one golden + one
  help-text line.

## Implementation log

- 2026-06-03 — implementation-dev: branched
  `feat/0031-fleet-atlas-failure-mode-frequency` off `main`; status flipped
  to in-progress. Plan: write `tests/atlas.sh` + fixtures
  (`tests/fixtures/atlas/<slug>/agents.config.sh` ×3, three
  `events.jsonl` files seeded with `infra_flake_rerun` events across two
  real patterns + one synthetic 5th pattern; `tests/fixtures/atlas.catalog.sh`
  with one extra `(no lesson)` pattern; one
  `tests/fixtures/atlas.text.golden.txt` golden). Implement the
  `atlas()` dispatcher + five helpers (`atlas_parse_catalog`,
  `atlas_count_pattern`, `atlas_last_seen_pattern`,
  `atlas_projects_for_pattern`, `atlas_render_row_text`/`_json`)
  next to `overview()` / `prompts_score()`. Defensive habits per the
  LESSONS-to-defend-against list: every `printf` of a token/slug uses
  `printf -- '%s'`, every `grep -F` against a `--`-prefix-able token
  uses `grep -qF --`, no `awk -v` value is multi-line, counts use
  `awk … END { print n+0 }`, every code path ends with explicit
  `exit 0`/`exit 2`. No `lib/` or `prompts/` changes; no new event
  types.
- 2026-06-03 — implementation-dev: tests/atlas.sh covers AC#1–AC#12
  (the ticket's 12 checkboxes; the 13th was the meta "tests/atlas.sh
  covers them all" which `tests/atlas.sh` itself satisfies by passing).
  Local gate green: `shellcheck -S warning lib/*.sh bin/fleet` clean,
  `bash -n` clean, `node scripts/check-backlog.mjs` ✓, `bash
  tests/atlas.sh` 12/12 ok. Status flipped to shipped in this same PR
  so the merge lands the feature and the index update atomically.
