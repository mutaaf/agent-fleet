---
id: 0039
title: LESSONS expiry markers let PHASE 0 reads skip stale operational memory
status: groomed
priority: P2
area: governance
created: 2026-06-07
owner: gtm-innovation
---

## User story

As a fleet operator whose `docs/LESSONS.md` has grown to 24 paragraphs
in 6 weeks — half of which document workarounds for traps that newer
helpers (`provenance_json_escape`, `replay_batch_json_escape`,
`fleet_check_quiet_hours` no-substitution call pattern) already
defuse — and who watches every ship and groom run pay a couple
hundred tokens to re-read every retired paragraph at PHASE 0, I want a
`<!-- EXPIRES: YYYY-MM-DD -->` HTML-comment marker convention on
LESSONS paragraphs PLUS a `bin/fleet lessons-prune --dry-run` reader
that lists expired entries the operator can promote to `LESSONS-
ARCHIVE.md` with one command, so PHASE 0 reads stay focused on
live operational memory rather than a growing scroll of historical
artifacts — without ever DELETING a lesson (lessons are
append-only by AGENTS.md contract; archival is the right semantic).

## Why now (four lenses)

### Product Owner
LESSONS.md is the kit's operational memory. Per AGENTS.md every ship
and groom run reads it at PHASE 0 — and the file is append-only by
contract (no reordering, no deletes). That contract is correct: the
moment lessons can be silently removed, the loop loses its
collective memory. But "append-only" and "PHASE 0 reads everything"
are NOT the same constraint. Today the loop pays the read cost on
every paragraph forever, even for paragraphs that document a trap
the kit has since defused at the helper level (the UTF-8 sign-
extension trap, the awk -v multiline trap, several others). The
smallest meaningful unit of value is:

1. **A convention** — a `<!-- EXPIRES: YYYY-MM-DD -->` marker the
   operator can add to a paragraph when its trap is defused (e.g.
   when a helper now defends against it). Marker placement: on the
   line immediately AFTER the paragraph's `## YYYY-MM-DD — title`
   heading, before the body.
2. **A reader** — `bin/fleet lessons-prune --dry-run` walks
   LESSONS.md, lists every paragraph whose EXPIRES date is past
   today, and prints the dates + headlines. Operator inspects.
3. **A mover** — `bin/fleet lessons-prune --commit` moves the
   expired paragraphs into a new file `docs/LESSONS-ARCHIVE.md`,
   appended with a `## archived YYYY-MM-DD — (originally
   YYYY-MM-DD)` heading, and opens a PR on a `chore/lessons-prune-
   <date>` branch. The PR body explains the move and links
   each expired paragraph to the kit commit / PR that defused
   it (operator-supplied via `--cause "<text>"`).
4. **A defense** — the prompts/PHASE-0 reader only reads
   `docs/LESSONS.md`, NOT the archive file. So the archive
   preserves history without paying the every-run read cost.

Subtraction: PHASE 0 stops paying for stale memory. The contract
("never delete a lesson") stays. The archive is the safety valve.
Per P-5 (operator confidence over feature richness), the win is
removing the operator's anxiety that "trimming LESSONS would lose
the trap memory" — the archive PROVES the memory is preserved,
just out of the hot read path.

### Stakeholder
This is moat-deepening in the cheap-runs and uniform-telemetry
axes simultaneously. **Cheap runs:** every ship and groom run today
re-reads every paragraph in LESSONS.md; on a fleet of 5 projects
running 4 ship cycles + 4 groom cycles + 288 review polls per day,
that is ~17k paragraph-reads per day spent on memory that has been
defused. Expiry pruning collapses that cost without changing the
contract. **Uniform telemetry:** the archival ACT itself emits a
typed event (`lessons_pruned {archived_count, since_date, pr}`) so
fleet-control and `fleet provenance` can reconstruct "why does
LESSONS.md look shorter this month?" months later. The convention
is also a forcing function: when the kit adds a new helper that
defuses an old trap, the same PR adds the `EXPIRES:` marker on
the originating LESSON — making the relationship between
"helper exists" and "lesson retired" a single auditable change.
Per P-6 (telemetry is the source of truth), the archive event
makes the pruning auditable; per P-3 (heal in-flight before new
work), the PHASE 0 read budget directly affects how much
heal context the runner has room for in a budget-capped run.

### User (operator after `fleet lessons-promote` has run 6 weeks)
LESSONS.md has 24 paragraphs. Operator marks 5 of them with
`<!-- EXPIRES: 2026-06-07 -->` (today) because the inline
notes already say "defused by `replay_batch_json_escape`" or
"superseded by ticket 0035 ASCII-restricted reason." Runs
`bin/fleet lessons-prune --dry-run`. Sees:

```
lessons-prune: 5 paragraphs expired as of 2026-06-07

  EXPIRES   DATE         HEADLINE
  2026-06-07  2026-05-26   bash scripts launched with & cannot be SIGINT-tested
  2026-06-07  2026-05-27   $(cat file) strips trailing newlines
  2026-06-07  2026-05-28   printf '- foo\n' treats the leading dash as a flag
  2026-06-07  2026-06-01   awk -v var rejects newlines
  2026-06-07  2026-06-03   doctor_json_escape sign-extends multi-byte UTF-8

(re-run with --commit --cause "<text>" to archive)
```

Operator runs `bin/fleet lessons-prune --commit --cause
"defused by inline helpers + LESSONS 2026-06-05 dispatcher rule"`.
Sees a `chore/lessons-prune-2026-06-07` PR open with the move.
After merge, LESSONS.md drops from 24 paragraphs to 19. The next
ship run pays the read cost for 19 paragraphs, not 24. The 5
moved paragraphs are still in the repo under
`docs/LESSONS-ARCHIVE.md`, ready for `git blame` / search / a
future autopsy. Nothing was lost.

### Growth
Every successful append-only system eventually grows an archive
discipline — sentry's "issue resolution," datadog's "monitor
mute reasons," even git's `.gitattributes export-ignore`. The
pattern is universal: append-only as the contract, scope-bounded
as the read. The kit's LESSONS file converges on the same
pattern. A friend running their own loop reads the EXPIRES
convention once and understands the model: lessons are
permanent; their relevance to the live read is not. The kit
becomes shareable BECAUSE it shows a credible answer to "what
do you do when your operational memory grows past the model
context budget?" — without resorting to summarization or
silent deletion. Compounds 0009 (`cross-project LESSONS
aggregation` — the same EXPIRES convention applies to
`CROSS_LESSONS.md`; out of scope for v1 but a one-line
extension), 0022 (`reviewer send-back drafts` — drafts in
LESSONS.md are exempt from EXPIRES because they have no date
yet), 0028 (`fleet lessons-promote` — promotion is the
WRITE-side of LESSONS; pruning is the READ-side curation).

## Acceptance criteria

Each box maps 1:1 to a test scenario in `tests/lessons-prune.sh`.

- [ ] The EXPIRES marker convention is documented in
      `AGENTS.md § Lessons` as: "an optional
      `<!-- EXPIRES: YYYY-MM-DD -->` HTML comment on the
      line immediately following a paragraph's
      `## YYYY-MM-DD — <title>` heading marks the paragraph
      for archival on or after the named date. The PHASE 0
      LESSONS read STILL includes the paragraph until the
      operator runs `fleet lessons-prune --commit` —
      EXPIRES is a candidate marker, not an automatic
      removal." Test asserts the section is present via
      `grep -qF -- "EXPIRES: YYYY-MM-DD" AGENTS.md`.
- [ ] `bin/fleet lessons-prune --dry-run` walks
      `docs/LESSONS.md`, identifies every paragraph whose
      EXPIRES date is `<= today` (today is
      `FLEET_NOW_OVERRIDE` if set, else
      `date -u '+%Y-%m-%d'`), and prints a 4-column table:
      `EXPIRES`, `DATE`, `HEADLINE`, plus a leading
      summary line `lessons-prune: N paragraphs expired
      as of <today>`. Empty result: `lessons-prune: no
      paragraphs expired as of <today>` and exit 0. Test
      asserts both populated and empty branches via a
      fixture LESSONS file.
- [ ] Paragraphs WITHOUT an EXPIRES marker are NEVER
      listed (silent paragraphs are never pruned).
      Paragraphs with an EXPIRES marker whose date is
      strictly `> today` are NEVER listed (future-dated
      EXPIRES is a planned retirement, not a current
      one). Test asserts a fixture with three paragraphs:
      one unmarked, one EXPIRES=tomorrow, one
      EXPIRES=yesterday — only the third appears.
- [ ] Invalid EXPIRES date (not `YYYY-MM-DD`): print
      `lessons-prune: paragraph "<headline>" has
      invalid EXPIRES "<value>" (use YYYY-MM-DD); skipped`
      to stderr, but DO NOT exit nonzero (a malformed
      marker is an operator error, not a tool error —
      surface it without breaking the run). Test asserts
      a fixture with one malformed EXPIRES and confirms
      the warning + nonzero-exempt behavior.
- [ ] `bin/fleet lessons-prune --commit --cause
      "<one-line>"` MOVES every expired paragraph from
      `docs/LESSONS.md` to `docs/LESSONS-ARCHIVE.md`,
      preserving the paragraph BYTE-FOR-BYTE (including
      the original `## YYYY-MM-DD — <title>` heading)
      under a new `## archived <today> — originally
      <original-date>` wrapper heading. The archive file
      is created if it does not exist. The move uses
      `cp` + truncate (NOT `$(cat …)`) per LESSONS
      2026-05-27. Then the command commits with message
      `chore: archive N expired lessons (<cause>)`,
      pushes the branch `chore/lessons-prune-<today>`,
      and opens a PR via `gh pr create`. Test asserts
      the byte-exact paragraph move via a `cmp` against
      a checked-in golden archive file.
- [ ] `--cause` is MANDATORY on `--commit` (per the
      same safety precedent as ticket 0030 and 0035's
      `--reason`). Missing: `lessons-prune: --commit
      requires --cause "<one-line>" explaining why
      these lessons are now safe to archive (e.g. "kit
      now defuses at helper level")` to stderr, exit 2.
      Test asserts the missing-cause branch.
- [ ] `--cause` value with leading `-` parses
      correctly per LESSONS 2026-05-28 (printf leading-
      dash trap). The cause is recorded in the PR body,
      the commit message, AND the event payload. Test
      asserts the leading-dash cause rendered correctly
      in all three places.
- [ ] `lessons_pruned` event emitted on every
      successful `--commit` run: `{archived_count,
      since_date, pr, cause}`. Event lands in the
      AGENT-FLEET project's `$CACHE_DIR/events.jsonl`
      (kit-as-project, per ticket 0028 /
      `lesson_promoted` and 0035 / `prompts_reverted`).
      Event carries `phase=prune`. Dry-run paths emit
      NO event. Test asserts the event payload via
      `node -e 'JSON.parse(...)'` on the last channel
      line.
- [ ] `AGENTS.md § Telemetry` is updated in the same
      PR with a new bullet for `lessons_pruned
      {archived_count, since_date, pr, cause}` following
      the existing entry style (verbatim shape: see
      ticket 0028's `lesson_promoted` paragraph and
      0035's `prompts_reverted` paragraph). Reviewer's
      telemetry-contract check requires this in the
      same diff.
- [ ] The prompts under `prompts/` (PHASE 0 readers)
      are UNCHANGED in this PR. The contract that PHASE
      0 reads `docs/LESSONS.md` (and IGNORES
      `docs/LESSONS-ARCHIVE.md`) is enforced by NOT
      adding any prompts edit that references the
      archive file. Test asserts via `git diff --name-
      only main…HEAD -- prompts/` that the PR touches
      zero prompts files (run inside the test as a
      bash assertion against `git ls-files` since the
      test is offline).
- [ ] Help: `bin/fleet lessons-prune --help` prints
      a USAGE block mentioning `--dry-run`,
      `--commit`, `--cause`. Test asserts via
      `grep -qF -- "$kw" "$help_out"` per LESSONS
      2026-05-30. Help block ends with `exit 0` per
      LESSONS 2026-06-01.
- [ ] `tests/lessons-prune.sh` covers all 11 boxes
      using `$HOME/.local/bin` stubs (per LESSONS
      2026-05-26) for `git`, `gh`. Per LESSONS
      2026-05-27 the test uses `cp` for backup/restore
      of LESSONS.md (NEVER `$(cat …)` — the
      round-trip in the test itself must preserve
      trailing newlines). The clock is frozen via
      `FLEET_NOW_OVERRIDE`. Per LESSONS 2026-06-01
      (`grep -c file || echo 0` double-print trap)
      every paragraph count uses
      `awk … END { print n+0 }`. Run-time budget:
      <10s.

## Out of scope

The dev agent will NOT do these even if they seem related.

- AUTO-pruning during `fleet groom` or any other
  scheduled runner. Pruning is operator-invoked only —
  an automated prune defeats the safety. Operators
  decide when a trap is defused enough to retire its
  lesson.
- Deleting lessons (no `--delete` flag). Lessons are
  append-only forever; the archive file IS the
  retirement path. A `--delete` flag would violate
  the AGENTS.md contract.
- A `lessons-unarchive` companion. Standard git
  semantics (`git revert <prune-pr>`) handle
  restoration; a special flag adds surface for zero
  new capability.
- Editing `docs/LESSONS-ARCHIVE.md`'s heading style or
  re-numbering paragraphs. The archive is append-only
  too; new pruning runs add new `## archived <today>
  — originally …` blocks without touching prior ones.
- Pruning `docs/CROSS_LESSONS.md` (the cross-project
  feed from ticket 0009 / 0028). The same convention
  applies and the same reader works on it, but the
  separate cross-project archive flow is a follow-up
  ticket once single-project ships.
- Pruning a paragraph by HEADLINE rather than by
  EXPIRES marker (`--paragraph "<title>"`). The
  EXPIRES marker is the SOLE retirement signal — it
  forces the operator to commit to a date and to
  edit the LESSONS file with intent. A by-headline
  flag would invite accidental pruning.
- Auto-adding the EXPIRES marker when a helper that
  defuses the trap is merged (e.g. when
  `replay_batch_json_escape` lands, auto-stamping
  the 2026-06-03 UTF-8 lesson). The semantic
  relationship between helper and lesson is operator
  judgment, not pattern matching. Maybe a v2.
- A launchd schedule. Operator-run only.

## Engineering notes

Files / patterns the dev should touch. Specific enough that the dev
doesn't have to re-discover the architecture.

- `bin/fleet` — new `lessons_prune()` dispatcher
  function placed next to the existing
  `lessons_promote()` block (find via `grep -n
  '^lessons_promote' bin/fleet`). Shape mirrors
  `prompts_revert()` (ticket 0035) and
  `lessons_promote()` (ticket 0028) for the
  `--dry-run` / `--commit` / `--cause` flag
  handling and the PR-opening branch.
- `bin/fleet` — five helpers:
  - `lessons_prune_scan` — walks LESSONS.md and
    emits one JSON line per paragraph
    `{date, headline, expires, body_start_line,
    body_end_line}`. Multi-line paragraph bodies
    are buffered to a tmp file per LESSONS
    2026-06-01 (awk -v multiline trap).
  - `lessons_prune_filter_expired` — reads the
    scan output, filters to entries with EXPIRES
    `<=` today, prints a JSON line per match.
  - `lessons_prune_render_dry_run` — formats the
    filtered list as the 4-column table from
    AC#2.
  - `lessons_prune_apply_move` — for each
    expired paragraph, appends the original
    bytes (wrapped in the `## archived ...`
    heading) to `docs/LESSONS-ARCHIVE.md` and
    removes the original block from LESSONS.md.
    Both writes use `cp` + truncate per LESSONS
    2026-05-27; NEVER `$(cat …)`.
  - `lessons_prune_emit_event` — wraps
    `fleet_emit_event lessons_pruned
    archived_count=$n since_date=$today
    pr=$pr cause=$cause`. The cause value
    passes through `_json_escape` via
    `fleet_emit_event` and is restricted to
    ASCII for v1 per LESSONS 2026-06-03
    (same constraint as ticket 0035's
    `--reason`).
- `bin/fleet` — `lessons_prune()` end-state must
  be `exit 0` (success / dry-run hit), `exit 2`
  (usage error), or `exit 1` (git/gh failure) on
  every code path per LESSONS 2026-06-01
  (dispatcher fall-through trap). Copy the
  exit-N pattern from `prompts_revert()` (ticket
  0035, ~line 6000) verbatim.
- `bin/fleet` — dispatcher block at the bottom
  of the file: `if [ "$CMD" = "lessons-prune" ];
  then lessons_prune "$@"; fi`. Placed next to
  the existing `lessons-promote` block. Per
  LESSONS 2026-06-05 (dispatcher forward-
  reference trap), confirm every helper
  `lessons_prune` calls is defined ABOVE the
  dispatcher block OR inlined.
- `bin/fleet` — help banner block at the top of
  the file (around line ~14) gets a new line:
  `fleet lessons-prune --dry-run  list expired
  LESSONS entries (operator-invoked archival)`.
  README "Daily ops" code block gets the same
  line.
- `lib/common.sh` — NO changes. `lessons-prune`
  is a pure caller of `fleet_emit_event`
  (existing). NO new helpers, NO `fleet_*`
  signature changes.
- `AGENTS.md § Lessons` — NEW short section (or
  appended to an existing section) documenting
  the `<!-- EXPIRES: YYYY-MM-DD -->` convention
  per AC#1. ~6 lines.
- `AGENTS.md § Telemetry` — append a new bullet
  for `lessons_pruned {archived_count,
  since_date, pr, cause}` — emitted by
  `bin/fleet lessons-prune --commit` once per
  successful archival run. Carries `phase=prune`.
  Payload as defined in AC#7. Mirrors the
  shape of `lesson_promoted` (0028),
  `prompts_reverted` (0035).
- `docs/LESSONS-ARCHIVE.md` — NEW empty file
  committed in this PR with one header line
  `# LESSONS — ARCHIVE` and a one-paragraph
  preamble explaining that this file is the
  retirement target for expired LESSONS
  entries and is NOT read by PHASE 0. Per
  LESSONS 2026-05-25 (load-bearing docs), the
  file MUST NOT be empty on commit — the
  preamble is the load-bearing content.
- `docs/LESSONS.md` — NO direct edit in THIS
  PR (no expired markers to apply yet; the
  command itself is the editor). The PR
  introduces the CONVENTION; future operator-
  invoked PRs apply it.
- `prompts/` — NO changes. The PHASE 0
  prompts READ `docs/LESSONS.md`; they MUST
  continue to do so. Adding a check that
  the prompts do NOT reference
  `LESSONS-ARCHIVE.md` is enforced via the
  AC#9 assertion. No `Reinstall: all
  projects` line needed because `lib/` and
  `prompts/` are untouched.
- `tests/fixtures/lessons-prune/` — NEW
  directory under `tests/fixtures/` holding:
  - one synthetic `LESSONS.md` with FIVE
    paragraphs: one unmarked, one
    EXPIRES=today (yesterday-relative-to-
    frozen-clock), one EXPIRES=tomorrow,
    one EXPIRES=malformed, one EXPIRES=
    `2024-01-01` (long-past).
  - one expected `LESSONS-ARCHIVE.md`
    golden after archival.
  - one expected `LESSONS.md` golden after
    archival (the unmarked + the EXPIRES=
    tomorrow + the EXPIRES=malformed
    paragraphs remain).
- `tests/lessons-prune.sh` — top of file
  mirrors `tests/lessons-promote.sh`: stub
  `git`, `gh` under `$HOME/.local/bin`
  (`$HOME=$TMP/home` per LESSONS
  2026-05-26). The stub `git` records every
  invocation. The event assertion reads
  the kit's events channel (under
  `$TMP/cache/agent-fleet-agent/
  events.jsonl`) and parses the last line
  via `node -e 'JSON.parse(...)'`. Per
  LESSONS 2026-05-27, the test uses `cp`
  for backup/restore — never `$(cat …)`.
  Per LESSONS 2026-06-01 (`grep -c …` 0-
  match double-print trap), counts use
  `awk … END { print n+0 }`. Run-time
  budget: <10s.
- New deps: none. Pure shell + awk + existing
  `fleet_emit_event` (lib/common.sh ~975),
  `_json_escape` (common.sh ~849) used
  indirectly.
- Public API: additive — `bin/fleet
  lessons-prune` is a new subcommand. ONE new
  event type added (`lessons_pruned`) —
  consumers MUST tolerate unknown types per
  the AGENTS.md § Telemetry contract. NO
  `fleet_*` signature changes.
- BREAKING flag: NO. PR body affirms "no
  `fleet_*` signature changes" and names the
  new event type so the reviewer's telemetry-
  contract check passes. Affirms also "no
  prompts/ changes, no PHASE 0 read-target
  change — `docs/LESSONS.md` is still the sole
  read target."
- Reinstall required: NO. `lib/` and `prompts/`
  are untouched.
- LESSONS to defend against: 2026-05-25
  (load-bearing docs — `LESSONS-ARCHIVE.md`
  ships with a preamble, NOT empty).
  LESSONS 2026-05-26 (`tail` shadow —
  `lessons_prune` is namespaced). LESSONS
  2026-05-26 (PATH reset — stubs go in
  `$HOME/.local/bin`). LESSONS 2026-05-27
  (`$(cat)` trap — the LESSONS.md and
  ARCHIVE.md writes use `cp` + truncate, the
  test's backup/restore uses `cp`). LESSONS
  2026-05-28 (printf leading-dash trap —
  every cause / headline / EXPIRES value
  goes through `printf -- '%s'`). LESSONS
  2026-05-30 (`grep -F --` flag trap —
  help text uses `grep -qF --`). LESSONS
  2026-06-01 (awk -v multiline trap —
  paragraph bodies buffer to a tmp file
  and read back via `getline line < file`).
  LESSONS 2026-06-01 (`grep -c file || echo
  0` double-print trap — counts use
  `awk … END { print n+0 }`). LESSONS
  2026-06-01 (dispatcher fall-through trap
  — `lessons_prune()` ends with explicit
  `exit N`). LESSONS 2026-06-03 (UTF-8
  sign-extension trap — the cause value
  is restricted to ASCII for v1; AC
  validates).  LESSONS 2026-06-05
  (dispatcher forward-reference trap —
  every helper is defined above the
  dispatcher line or inlined).
- This ticket compounds 0009 (cross-
  project LESSONS aggregation — same
  EXPIRES convention will apply to
  CROSS_LESSONS.md in a follow-up
  ticket), 0022 (reviewer send-back
  drafts — drafts are exempt from
  EXPIRES because they have no
  retirement date yet), 0028 (`fleet
  lessons-promote` — the write-side of
  LESSONS; pruning is the read-side
  curation). Per P-1 the diff is
  small: ~200 lines of `lessons_
  prune*` helpers + ~250 lines of
  test + one AGENTS.md paragraph
  (Telemetry) + one AGENTS.md
  section (Lessons / EXPIRES
  convention) + one LESSONS-ARCHIVE.md
  preamble + one help-text line +
  one README line.

## Implementation log

(Appended by the implementation-dev agent during execution.)

- YYYY-MM-DD — branch `feat/0039-...` opened
- YYYY-MM-DD — failing test added in `tests/lessons-prune.sh`
- YYYY-MM-DD — PR #N opened, CI [state]
- YYYY-MM-DD — merged to main
