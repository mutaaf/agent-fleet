---
id: 0040
title: fleet self-check greps the kit's own shell for known LESSONS-documented call-shape traps
status: groomed
priority: P1
area: safety
created: 2026-06-09
owner: gtm-innovation
---

## User story

As a fleet operator whose `docs/LESSONS.md` already documents 14+ shell
call-shape traps the loop has eaten over six weeks (printf leading-dash,
awk -v multi-line, `$(cat file)` newline-stripping, `grep -F --` flag
collision, `grep -c | echo 0` double-print, dispatcher fall-through,
dispatcher forward-reference, UTF-8 sign-extension in `_json_escape`,
`IFS=$'\t' read` middle-empty-field, bash 3.2 LC_ALL caching, `export`
inside `$(...)` not leaking, `tail()` function shadowing `/usr/bin/tail`,
backticks inside SCHEMA template literals, and more), and who watches
the `implementation-dev` agent re-discover one of these traps about
once a fortnight despite the LESSON existing — I want `bin/fleet
self-check` to statically grep the kit's own shell (`lib/*.sh`,
`bin/fleet`, `scripts/*.mjs`) for the EXACT call-shape footprints those
LESSONS warn against, print a per-trap pass/fail table keyed to the
LESSON date, and exit non-zero on any hit — so the next ticket that
ships a new helper using `awk -v body="$multi_line"` fails the local
gate AND the `validate` CI check BEFORE the trap teaches the loop the
same lesson a second time and burns a heal slot recovering from it.

## Why now (four lenses)

### Product Owner
The LESSONS file is the kit's most distinctive asset. Every other
autonomous-coding-agent project the operator could adopt instead writes
its operational memory into a postmortem doc no future commit ever
reads; this kit reads its LESSONS at PHASE 0 of every ship and groom
run AND now prunes the stale ones via `lessons-prune` (ticket 0039).
But the value of a written rule is bounded by whether the next
contributor actually applies it. A LESSON that reads "any `printf` whose
first argument starts with `-` MUST be `printf -- '%s' …`" is honored
during code review by the human operator and the review subagent, but
the ship agent writes the code BEFORE the reviewer sees it — so the
LESSON's defense kicks in late, after the heal counter has already
advanced. The smallest meaningful unit of value is a STATIC linter that
encodes each LESSONS-documented trap as one grep pattern and fires at
the local gate, before push. Subtraction: the operator stops watching
the dev agent re-discover the same trap. Per P-1 (smallest viable
change), the v1 ships exactly the patterns the LESSONS file already
documents — no novel rules, no "best-practice shell" creep, no
shellcheck rule additions. The catalog is the LESSONS file; the linter
is the reader.

Concretely the table looks like:

```
fleet self-check

TRAP                                  LESSON         FILES SCANNED   HITS
printf leading-dash                   2026-05-28     17              0
$(cat file) round-trip                2026-05-27     17              0
awk -v multi-line value               2026-06-01     17              0
grep -F flag pattern                  2026-05-30     17              0
grep -c result feeding shell math     2026-06-01     17              1  ← bin/fleet:9412
dispatcher missing exit 0             2026-06-01     17              0
dispatcher forward-reference          2026-06-05     17              0
_json_escape sign-extension           2026-06-03     17              0
IFS=$'\t' read with empty middles     2026-06-08     17              0
bash 3.2 ${#s} on UTF-8               2026-06-05     17              0
export inside $(...)                  2026-06-05     17              0
tail()/head()/cat() function shadow   2026-05-26     17              0

self-check: 1 hit across 12 patterns (LESSONS 2026-05-26..2026-06-08)
```

Operator sees the hit, opens `bin/fleet` at line 9412, refactors the
`grep -c … || echo 0` into `awk … END { print n+0 }`, re-runs, sees
zero hits, pushes. The local gate now blocks the regression.

### Stakeholder
This is **moat-deepening on the safety axis** in a way no other
autonomous-coding-agent kit currently has: a self-referential lint that
treats the project's own operational memory as the rule set. The bet
the kit makes is "ship a hardened loop once, and every project gets
the hardening." That bet only holds if a CONTRIBUTION to the loop
cannot silently weaken it. `shellcheck` catches generic shell bugs;
`bash -n` catches parse errors; `validate` catches backlog/index drift.
None of them know that `printf -- '%s' "$x"` is the kit's rule and
`printf "$fmt" "$x"` is not. `self-check` is the bridge.

It is also a forcing function for LESSONS discipline. Today a LESSON
is added when a trap is discovered; whether the linter catches future
recurrences is up to the human. With `self-check` in the local gate
and `validate` CI job, every NEW LESSON the operator promotes via
`lessons-promote` (0028) MUST come with a corresponding `self-check`
pattern — OR the LESSON ships unenforced. The reviewer's contract
becomes "any LESSON that documents a syntactic call-shape MUST land
with a pattern in `self-check`," same shape as the reviewer's existing
"new event type MUST land with an AGENTS.md § Telemetry bullet" rule.
The kit's most valuable asset (LESSONS) gets a load-bearing reader.

Per P-6 (telemetry is the source of truth), `self-check` emits one
`self_check_failed {pattern, lesson_date, file, line}` event per hit
when run from the local gate path (`FLEET_SELF_CHECK_GATE=1`), so
fleet-control and `fleet weekly` can render "lint debt over time"
without scraping stdout. Per P-3 (heal in-flight before new work), the
linter is read-only and cheap (~12 greps, ~17 files, <1s on a typical
checkout) — it never blocks a heal run.

Compounds 0039 (`lessons-prune` — a LESSON whose `self-check` pattern
ships and stays green for 30 days is a high-confidence candidate for
an `<!-- EXPIRES: -->` marker), 0028 (`lessons-promote` — promoting a
LESSON with a call-shape footprint becomes one PR, not two), 0029
(`fleet provenance` — `self_check_failed` events become a column in
the per-PR forensics view, "did the heal step recover from a known
trap?").

### User (operator at 9am after the dev agent pushed `feat/0043` overnight)
Operator runs `git pull && bin/fleet self-check`. Sees:

```
TRAP                                  LESSON         FILES SCANNED   HITS
...
awk -v multi-line value               2026-06-01     17              1  ← bin/fleet:11842
...

self-check: 1 hit across 12 patterns (LESSONS 2026-05-26..2026-06-08)
exit 1
```

Opens `bin/fleet` at 11842 — sees the dev agent introduced
`awk -v rationale="$body" 'BEGIN { ... }'` where `$body` was captured
from a multi-line PR description. Recognizes the trap from LESSONS
2026-06-01. Either re-rolls the PR (`gh pr close <n>; gh pr ready
<n>`) or pushes a heal commit themselves that buffers `$body` through
a tmp file per the LESSON. PR re-CI's green. The trap never reaches
main. The OPERATOR'S heal effort is one minute, not one PR slot.

The dev agent's pre-push hook ALSO runs `self-check`, so the trap is
ideally caught before the operator sees it at all — but operator
visibility is the safety net. Per LESSONS 2026-05-22 (fleet-control)
"local gate must include `node scripts/check-backlog.mjs`" — same
principle: any check the reviewer relies on MUST run locally first.

### Growth
A friend running their own claude loop reads the `self-check` table
and immediately understands the kit's discipline: every operational
trap is named (LESSONS date), enforced (grep pattern), and visible
(table row). They install the kit and run `bin/fleet self-check`
against THEIR project; the table runs against the kit's shell, not
theirs, but they see the rules they're inheriting. The mental model
"my codebase's operational memory is a graph of typed, defensible
rules" is contagious — a friend who adopts agent-fleet adopts this
discipline, and the next operational lesson THEY learn becomes a
pattern in their own `self-check` extension.

This is the kind of asset that travels in a conference talk slide:
"here is the lint that reads our own postmortems." Compounds the
acquisition path that started with `kickstart --demo` (0023) and
`preflight` (0032) — the prospect who tried the demo now sees that
the kit DEFENDS itself against the LESSONS it documents.

## Acceptance criteria

Each box maps 1:1 to a test scenario in `tests/self-check.sh`.

- [ ] `bin/fleet self-check` is a new subcommand. With no flags it scans
      `bin/fleet`, every file under `lib/`, and every `.mjs` file under
      `scripts/` (the union of "kit shell-and-script source"), runs the
      catalog of 12 LESSONS-derived grep patterns described in
      Engineering notes, and prints the table from the User lens above.
      Exit 0 on zero hits, exit 1 on any hit. Test asserts both
      branches via a fixture kit-source tree.
- [ ] `bin/fleet self-check --json` prints one JSON object per hit
      `{"pattern": <name>, "lesson": "YYYY-MM-DD", "file": "<rel>",
      "line": <int>, "match": "<snippet>"}`, one per line. Empty result
      = no output, exit 0. Hits = N lines, exit 1. The JSON escape
      goes through the existing `preflight_json_escape` helper (line
      ~726 of `bin/fleet`) to dodge the LESSONS 2026-06-03 UTF-8
      sign-extension trap AND the LESSONS 2026-06-05 dispatcher
      forward-reference trap (the helper is defined before the
      `self-check` dispatcher). Test asserts JSON validity via
      `node -e 'process.stdin.on("data", d => d.toString().split("\n")
      .filter(Boolean).forEach(l => JSON.parse(l)))'`.
- [ ] `bin/fleet self-check --pattern <name>` restricts the scan to a
      single named pattern (e.g. `--pattern awk-v-multiline`). Unknown
      pattern: print `self-check: unknown pattern "<name>" (run
      --list to see available)` to stderr, exit 2. Test asserts both
      the filtered-success and unknown-name branches.
- [ ] `bin/fleet self-check --list` prints the catalog of patterns —
      one row per pattern with the pattern name, LESSON date, and
      one-line description — and exits 0. NO scan runs. Used by
      operators discovering the surface and by `lessons-promote` to
      check whether a promoted LESSON already has coverage. Test
      asserts the catalog row count matches Engineering notes (12
      patterns at v1) and that every row carries an LESSONS date.
- [ ] Patterns whose call-shape genuinely cannot be reliably statically
      grep'd (`tail()`/`head()`/`cat()` function shadow needs a follow-up
      check that the SAME file ALSO shells out to the binary; the bash
      3.2 LC_ALL caching trap needs context past a single line) print
      a `≈` ("approximate") column suffix in the text table and carry
      `"approximate": true` in `--json`. Test asserts the `≈` rendering
      on at least one pattern and the JSON shape.
- [ ] `bin/fleet self-check --help` prints a USAGE block mentioning
      `--list`, `--pattern`, `--json`. Test asserts via `grep -qF --
      "$kw" "$help_out"` per LESSONS 2026-05-30. Help block ends with
      `exit 0` per LESSONS 2026-06-01.
- [ ] When `FLEET_SELF_CHECK_GATE=1` is exported (the local-gate /
      pre-push call shape), every hit ALSO emits one
      `self_check_failed {pattern, lesson_date, file, line}` event to
      the AGENT-FLEET project's `$CACHE_DIR/events.jsonl`
      (kit-as-project, per ticket 0028 / `lesson_promoted` and 0035 /
      `prompts_reverted`). Event carries `phase=self-check`. Unset env
      = no event (`fleet self-check` from an operator's prompt is a
      diagnostic read; only the gate call writes telemetry). Test
      asserts the event payload via `node -e 'JSON.parse(...)'` on the
      last channel line under the gate env, and asserts NO event under
      the unset env.
- [ ] `AGENTS.md § Telemetry` is updated in the same PR with a new
      bullet for `self_check_failed {pattern, lesson_date, file, line}`
      following the existing entry style (verbatim shape: see ticket
      0039's `lessons_pruned` paragraph). Reviewer's telemetry-
      contract check requires this in the same diff.
- [ ] `AGENTS.md § Local gate command` (the `## Agent parameters`
      bullet) is updated to APPEND `&& FLEET_SELF_CHECK_GATE=1 bin/
      fleet self-check`. The PR body MUST call out this widening as a
      non-BREAKING contract change (per AGENTS.md § Hard NOs: the
      local gate is the heal/dev pre-push command — widening it
      affects every installed project's `Reinstall` cycle even though
      no `lib/` or `prompts/` byte changed). Test asserts the new
      command via `grep -qF -- "FLEET_SELF_CHECK_GATE=1" AGENTS.md`.
- [ ] The 12 v1 patterns are exactly the catalog in Engineering notes
      and each one is keyed to its LESSONS date. A pattern whose
      fixture (`tests/fixtures/self-check/<pattern>.sh`) does NOT
      currently exist FAILS the test, so every catalog entry is
      proven by a positive (matches the trap) and negative (matches
      the defended call shape) fixture. Test runs each catalog
      pattern against both fixtures and asserts exactly one match per
      pattern.
- [ ] Performance budget: a full `bin/fleet self-check` scan against
      the kit's current source (1 `bin/fleet` ~11.6k lines, ~10 files
      under `lib/`, ~6 files under `scripts/`) finishes in <2 seconds
      on a stock macOS laptop. Test asserts via `t0=$EPOCHREALTIME; …;
      t1=$EPOCHREALTIME; awk "BEGIN { exit !($t1-$t0 < 2.0) }"` (the
      arithmetic uses awk per LESSONS 2026-06-01 to dodge the `bc`
      dep). v1 ships as 12 sequential greps — no parallelism, no
      caching. If a future v2 wants caching, do it then.
- [ ] `lib/common.sh` — NO changes. `self-check` is a pure caller of
      `fleet_emit_event` (existing) under the gate env. NO new
      `fleet_*` helpers, NO signature changes. Test asserts via
      `git diff --name-only main…HEAD -- lib/common.sh` returns
      empty.
- [ ] `prompts/` — NO changes. PHASE 0 readers continue to read
      `docs/LESSONS.md` and `docs/CROSS_LESSONS.md` exactly as they
      do today; `self-check` is a build-time/local-gate-time reader,
      not a runtime reader. No `Reinstall: all projects` line needed
      because `lib/` and `prompts/` are untouched. Test asserts via
      `git diff --name-only main…HEAD -- prompts/` returns empty.
- [ ] `tests/self-check.sh` covers all 13 boxes above using
      `$HOME/.local/bin` stubs per LESSONS 2026-05-26 (PATH reset).
      Per LESSONS 2026-05-27 the test backs up/restores any fixture
      file via `cp`, never `$(cat …)`. Counts use `awk … END { print
      n+0 }` per LESSONS 2026-06-01. Run-time budget: <8s total
      (well inside the 2s per-scan budget plus event/json
      assertions).

## Out of scope

The dev agent will NOT do these even if they seem related.

- AUTO-promoting new LESSONS into `self-check` patterns. The
  relationship between "a paragraph in LESSONS.md" and "a grep
  pattern" is operator judgment, not pattern matching. A v2 might
  add a `lessons-promote --with-pattern` flag, but v1 ships the
  catalog manually.
- Replacing `shellcheck`. `self-check` is ADDITIVE — it catches
  kit-specific traps that shellcheck doesn't know about. The local
  gate runs BOTH.
- Catching SEMANTIC bugs (e.g. "this `if` branch is unreachable,"
  "this variable is unused"). Pattern matching is for SYNTACTIC
  call-shape traps from LESSONS only.
- A `--fix` flag. Auto-rewriting a call shape silently is exactly
  the kind of change the AGENTS.md "never weaken a check to make a
  PR green" Hard NO is designed to prevent. The operator (or
  implementation-dev agent in a heal commit) writes the fix.
- Scanning project source OTHER than the kit's own. `self-check`
  reads `bin/fleet`, `lib/*.sh`, `scripts/*.mjs` from the CHECKOUT
  it runs in. An operator running it against their own project
  scans the installed copy of the kit, not their project's code.
  A "scan my own project's shell" flag is a follow-up ticket.
- A launchd schedule. Operator and pre-push gate only.
- Modifying `prompts/PHASE-0` to make the readers consult the
  catalog. PHASE 0 reads LESSONS.md; the linter is a SEPARATE
  layer that does not change the prompts.

## Engineering notes

Files / patterns the dev should touch. Specific enough that the dev
doesn't have to re-discover the architecture.

- `bin/fleet` — new `self_check()` dispatcher function placed
  next to the existing `preflight()` block (find via
  `grep -n '^preflight()' bin/fleet`, currently ~line 1438). Shape
  mirrors `preflight()` for the `--json` / `--list` / `--help`
  flag handling and the table-vs-json render split.
- `bin/fleet` — five helpers, ALL defined ABOVE the dispatcher
  block per LESSONS 2026-06-05 (forward-reference trap):
  - `self_check_catalog` — emits one TSV line per pattern
    `name<TAB>lesson_date<TAB>description<TAB>grep_pattern<TAB>
    approximate(0|1)` from a heredoc. The TSV is consumed by
    `IFS=$'\t' read` — per LESSONS 2026-06-08 (middle-empty-field
    trap), every column carries a `-` sentinel when empty and is
    remapped to empty in the consumer.
  - `self_check_scan_one` — given a pattern name, greps the
    catalog row, then greps the kit's source set for the pattern,
    emits one JSON line per hit via `preflight_json_escape` per
    LESSONS 2026-06-03.
  - `self_check_render_text` — formats the scan output as the
    aligned table from the AC, including the `≈` suffix on
    approximate patterns. Width computation goes through
    `preflight_visible_width` (line ~666 of `bin/fleet`) per
    LESSONS 2026-06-05 (bash 3.2 LC_ALL caching trap — never use
    `${#s}` for UTF-8 width).
  - `self_check_render_json` — emits the per-hit JSON lines from
    the AC, one per line.
  - `self_check_emit_event` — wraps `fleet_emit_event
    self_check_failed pattern=$name lesson_date=$date file=$f
    line=$ln`. Only called when `FLEET_SELF_CHECK_GATE=1`.
- `bin/fleet` — the 12 v1 catalog patterns (each is one grep
  regex). The DEV writes these, but the FOOTPRINT each catches is:
  - `printf-leading-dash` (LESSONS 2026-05-28) — `printf '[^-]`
    or `printf "[^-]` where the first byte of the format is `-`
    AND `--` does not precede. False-positive defense: skip lines
    containing `printf -- `.
  - `cat-roundtrip` (LESSONS 2026-05-27) — `\$\(cat ` followed
    later in the same file by a `printf '%s' "\$VAR" > ` on the
    captured var. Two-line context; emits as `≈ approximate`.
  - `awk-v-multiline` (LESSONS 2026-06-01) — `awk -v [A-Za-z_]
    +="\$\(` where the capture is multi-line by inspection of
    the source's own multi-line nature. Conservative grep:
    flag any `awk -v X="$(cat`, `awk -v X="$(< `, `awk -v X="$
    {VAR}` where VAR is later assigned from a multi-line source.
    Emits as `≈ approximate`.
  - `grep-F-flag-pattern` (LESSONS 2026-05-30) — `grep -F
    "--[A-Za-z]` or `grep -qF "--[A-Za-z]` where `--` end-of-
    options marker is absent.
  - `grep-c-double-print` (LESSONS 2026-06-01) — `grep -c[A-Za-z]*
    .* || echo 0` on a single line.
  - `dispatcher-missing-exit` (LESSONS 2026-06-01) — a subcommand
    function body (`^[a-z_]\+()` to next `^\}`) that does NOT
    contain `^[[:space:]]*exit [0-2]$` on its last 5 lines. Emits
    as `≈ approximate` because the static check can't tell
    whether the last branch is unreachable.
  - `dispatcher-forward-reference` (LESSONS 2026-06-05) — a
    subcommand function body that calls a name defined later in
    the file. Two-pass grep: build name→line index of all
    `^[a-z_]\+()` headers, then for each subcommand function,
    grep its body for any name index whose definition line is
    later than the dispatcher's `if [ "$CMD" = "<name>" ]` line.
    Emits as `≈ approximate`.
  - `json-escape-sign-extension` (LESSONS 2026-06-03) — any
    `_json_escape` or `*_json_escape` helper that does NOT
    contain the `code -ge 0` guard before the `code -lt 32`
    branch. Emits as `≈ approximate` (matches the helper body,
    not the caller).
  - `IFS-tab-empty-middle` (LESSONS 2026-06-08) — `IFS=\$'\\t'
    read -r [A-Za-z_]+ [A-Za-z_]+ [A-Za-z_]+` with 3+ field
    names where the awk script feeding the read is in the same
    file AND does NOT emit a `-` sentinel. Emits as `≈
    approximate`.
  - `bash-32-lc_all-string-length` (LESSONS 2026-06-05) — `\${#
    [A-Za-z_]+}` or `\${[A-Za-z_]+:[0-9]+:1}` inside a function
    that ALSO reads `LC_ALL=`. Emits as `≈ approximate`.
  - `export-in-command-substitution` (LESSONS 2026-06-05) —
    `export [A-Z_]+_EMITTED=1` inside `\$(` … `)`. Emits as
    `≈ approximate`.
  - `function-shadow-coreutils` (LESSONS 2026-05-26) — a
    function definition `^(tail|head|cat|sort|uniq|find|grep|
    awk|sed|cut|tr|wc)\(\)` in a file that ALSO shells out to
    the binary `\b<same-name> [-a-z]`. Emits as `≈ approximate`.
- `bin/fleet` — `self_check()` end-state must be `exit 0` (clean),
  `exit 1` (hits found), or `exit 2` (usage error) on every code
  path per LESSONS 2026-06-01 (dispatcher fall-through trap). Copy
  the exit-N pattern from `preflight()` (~line 1438) verbatim.
- `bin/fleet` — dispatcher block: `if [ "$CMD" = "self-check" ];
  then self_check "$@"; fi`. Place AFTER the `preflight` dispatcher
  (~line 1548). Per LESSONS 2026-06-05 (forward-reference trap),
  confirm every helper `self_check` calls is defined ABOVE the
  dispatcher block. `preflight_json_escape` (~line 726) and
  `preflight_visible_width` (~line 666) are both safely above and
  reusable.
- `bin/fleet` — help banner block at the top of the file (around
  line ~14) gets a new line: `fleet self-check        run the
  LESSONS-derived static linter against the kit's own shell`.
  README "Daily ops" code block gets the same line.
- `AGENTS.md § Agent parameters` — the `Local gate command` bullet
  is appended with `&& FLEET_SELF_CHECK_GATE=1 bin/fleet
  self-check`. Per AC#9.
- `AGENTS.md § Telemetry` — append a new bullet for
  `self_check_failed {pattern, lesson_date, file, line}` — emitted
  by `bin/fleet self-check` when `FLEET_SELF_CHECK_GATE=1`. Carries
  `phase=self-check`. Mirrors the shape of `lessons_pruned`
  (0039), `prompts_reverted` (0035).
- `lib/common.sh` — NO changes. `self-check` is a pure caller of
  `fleet_emit_event` (existing). NO new helpers, NO `fleet_*`
  signature changes.
- `prompts/` — NO changes. PHASE 0 readers are untouched. No
  `Reinstall: all projects` line needed because `lib/` and
  `prompts/` are byte-unchanged.
- `tests/fixtures/self-check/` — NEW directory under
  `tests/fixtures/` holding one positive + one negative fixture
  per catalog pattern (24 small `.sh` files at v1). Each file is
  <20 lines.
- `tests/self-check.sh` — top of file mirrors `tests/preflight.sh`:
  stub `git`, `gh` under `$HOME/.local/bin` (`$HOME=$TMP/home` per
  LESSONS 2026-05-26). The event assertion reads the kit's events
  channel (under `$TMP/cache/agent-fleet-agent/events.jsonl`) and
  parses the last line via `node -e 'JSON.parse(...)'`. Per
  LESSONS 2026-05-27, the test uses `cp` for fixture restore —
  never `$(cat …)`. Per LESSONS 2026-06-01 every count uses `awk
  … END { print n+0 }`. Run-time budget: <8s.
- New deps: none. Pure shell + awk + existing
  `fleet_emit_event` (lib/common.sh ~975),
  `preflight_json_escape` (bin/fleet ~726),
  `preflight_visible_width` (bin/fleet ~666).
- Public API: additive — `bin/fleet self-check` is a new
  subcommand. ONE new event type added (`self_check_failed`) —
  consumers MUST tolerate unknown types per the AGENTS.md §
  Telemetry contract. NO `fleet_*` signature changes.
- BREAKING flag: NO on the public API, YES on the LOCAL GATE
  WIDENING. The PR body MUST mark "Local gate widened:
  &&FLEET_SELF_CHECK_GATE=1 bin/fleet self-check" so every
  installed project's `Reinstall: all projects` action picks up
  the new gate command on the next install.sh run. The
  contract change is documented in AGENTS.md (AC#9), not
  silent.
- Reinstall required: NO byte change to `lib/` or `prompts/`. YES
  document-only update to `AGENTS.md § Agent parameters` —
  installed projects do NOT mirror AGENTS.md (it lives in the kit
  checkout). Operator notes the new gate command and the next
  ship/heal run pre-push hook picks it up because the heal runs
  from a fresh checkout per AGENTS.md.
- LESSONS to defend against (the linter's own implementation must
  pass `self-check`): 2026-05-25 (load-bearing docs — the
  `--list` output is the catalog's canonical documentation).
  2026-05-26 (`tail` shadow — `self_check` is namespaced; helpers
  are `self_check_*`). 2026-05-26 (PATH reset — stubs go in
  `$HOME/.local/bin`). 2026-05-27 (`$(cat)` trap — fixture
  restore uses `cp`). 2026-05-28 (printf leading-dash — every
  catalog row that begins with `-` goes through `printf -- '%s'`).
  2026-05-30 (`grep -F --` trap — help text uses `grep -qF --`).
  2026-06-01 (awk -v multiline — the catalog body buffers to a
  tmp file via `getline line < file`). 2026-06-01 (`grep -c file
  || echo 0` double-print — counts use `awk … END { print n+0 }`).
  2026-06-01 (dispatcher fall-through — `self_check()` ends with
  explicit `exit N`). 2026-06-03 (UTF-8 sign-extension — JSON
  escape goes through `preflight_json_escape`). 2026-06-05
  (dispatcher forward-reference — helpers above dispatcher
  block). 2026-06-05 (bash 3.2 LC_ALL caching — width via
  `preflight_visible_width`). 2026-06-05 (export inside `$(...)`
  — the gate-env event-emit path is OUTSIDE any command
  substitution). 2026-06-08 (IFS=$'\t' middle-empty-field —
  catalog TSV uses `-` sentinels).
- This ticket compounds 0028 (`lessons-promote` — a promoted
  LESSON with a call-shape footprint should land with a
  `self-check` pattern in the same PR; the reviewer's contract
  enforces it), 0029 (`fleet provenance` —
  `self_check_failed` events become a per-PR forensics column),
  0039 (`lessons-prune` — a LESSON whose pattern has zero hits
  for 30 days is a high-confidence candidate for an `<!--
  EXPIRES: -->` marker, since the linter is now defending it).
  Per P-1 the diff is small: ~400 lines of `self_check_*` helpers
  + 12 grep patterns + ~250 lines of test + 24 fixture files +
  one AGENTS.md gate bullet + one AGENTS.md Telemetry bullet +
  one help-text line + one README line.

## Implementation log

(Appended by the implementation-dev agent during execution.)

- YYYY-MM-DD — branch `feat/0040-...` opened
- YYYY-MM-DD — failing test added in `tests/self-check.sh`
- YYYY-MM-DD — PR #N opened, CI [state]
- YYYY-MM-DD — merged to main
