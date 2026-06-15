---
id: 0052
title: fleet add <repo> compresses a second-project install by inheriting one existing slug's manifest defaults
status: groomed
priority: P1
area: engine
created: 2026-06-15
owner: gtm-innovation
---

## User story

As a fleet operator who has been running `agent-fleet` against ONE project
(`courtiq`) for a month — whose `courtiq/agents.config.sh` already encodes
the values that took them a week to dial in (`BUDGET_DAILY_USD=4.50`,
`CROSS_LESSONS="$HOME/.local/share/agent-fleet/CROSS_LESSONS.md"`,
`QUIET_HOURS="22-07"`, `LOCAL_GATE_CMD="…"`, prompt pin SHA) — and who now
wants to put a SECOND project (`sidebrew`) under the same fleet without
re-living the dial-in — I want `bin/fleet add <repo>` to (1) infer those
inherited values from an existing slug the operator names with
`--inherit-from <slug>` (or auto-detect the single-slug case), (2) run the
same scaffold `fleet onboard` does but pre-fill the inherited fields, (3)
print a one-screen diff of "what was inherited" before calling
`lib/install.sh`, so adding project #2 stops being a 10-minute manual
re-derivation and becomes one command + one confirmation.

## Why now (four lenses)

### Product Owner
The acquisition arc today is solid for the FIRST project: `fleet kickstart
--demo` (0023) shows the loop, `fleet onboard <repo>` (0011) scaffolds the
contract, `fleet preflight` (0032) dry-adopts and prints what install would
do, `fleet onboarding-check` (0041) verifies the install end-to-end. That
arc converts a curious stranger into an operator running one slug. But
the SECOND project a working operator wants to add costs them roughly as
much manual work as the first: `fleet onboard` writes a fresh
`agents.config.sh` that does NOT carry over the values they spent a week
tuning on slug #1. The operator hand-copies `BUDGET_DAILY_USD`,
`CROSS_LESSONS`, `QUIET_HOURS`, the `LOCAL_GATE_CMD`, and the prompts pin
SHA from `courtiq/agents.config.sh` into `sidebrew/agents.config.sh` — by
which point they have either skipped a value (silent regression: the new
slug has no budget cap), gotten one wrong (typo on the path), or given
up. The smallest meaningful unit of value is one wrapper that says "here
is the slug you already trust; clone its non-project-specific values onto
the new one" and prints the diff before applying. Subtraction: the
operator stops re-deriving values they already derived. Per P-5 (operator
confidence over feature richness), the win is converting "I need to
remember every knob I tuned" into "the kit remembers; I just confirm."

### Stakeholder
This is **moat-deepening on the retention axis** — the kit's first
surface that treats an operator's existing fleet as a TEMPLATE for the
next slug, instead of treating every slug as a greenfield. Per P-6
(telemetry is the source of truth), the inherit logic is a PURE READER
of the source slug's `agents.config.sh` (parsed via the same
`fleet_load_manifest` shape the runners use — no new parser) and writes
only to the new project's working tree (the same files `fleet onboard`
already writes). No new event types. No `lib/common.sh` change. The diff
is a thin composer over the existing `onboard_render_manifest` /
`onboard_write_one` helpers plus an inheritance table that names exactly
which manifest fields are SAFE to copy across slugs (`BUDGET_DAILY_USD`,
`CROSS_LESSONS`, `QUIET_HOURS`, `LOCAL_GATE_CMD`, `PROMPTS_PIN_SHA`,
`SHIP_PAUSE_THRESHOLD`, `TRAINEE_REMAINING`) versus which are PROJECT-
SPECIFIC and must be re-derived (`SLUG`, `REPO_URL`, `GATING_CHECKS` —
the new project has its own CI). The inheritance table IS the moat: it
codifies "what is fleet-level policy" vs "what is project mechanics."
That distinction has been implicit in AGENTS.md until now; `fleet add`
makes it executable.

Compounds 0011 (`fleet onboard` — `fleet add` reuses
`onboard_render_manifest` / `onboard_write_one` verbatim with a different
default-resolver), 0032 (`fleet preflight` — `fleet add` calls the same
preflight as a dry-run subroutine before applying), 0041 (`fleet
onboarding-check` — runs as the final step of `fleet add` automatically),
0004 (`BUDGET_DAILY_USD` — the headline value being inherited), 0033
(`QUIET_HOURS` — another inherited value), 0005 (`PROMPTS_PIN_SHA` —
inherited so the new slug starts pinned to the same prompts revision the
operator trusts).

### User (operator on a Tuesday evening, deciding to put `sidebrew` under the loop)
The operator already trusts `courtiq` after a month of clean runs. They
clone `sidebrew` locally and want to put it under the same loop without
re-tuning every knob. They run `fleet add ~/projects/sidebrew
--inherit-from courtiq`. The kit prints a one-screen "inherited from
courtiq" diff:

```
fleet add: ~/projects/sidebrew
  inherit-from: courtiq

  inherited values (will land in sidebrew/agents.config.sh):
    BUDGET_DAILY_USD         4.50
    CROSS_LESSONS            $HOME/.local/share/agent-fleet/CROSS_LESSONS.md
    QUIET_HOURS              22-07
    LOCAL_GATE_CMD           shellcheck lib/*.sh && bash -n lib/*.sh && …
    PROMPTS_PIN_SHA          a3f1c2d (matches courtiq's pinned revision)
    SHIP_PAUSE_THRESHOLD     3
    TRAINEE_REMAINING        0

  project-specific (you must confirm or edit after):
    SLUG                     sidebrew     (from basename)
    REPO_URL                 git@github.com:you/sidebrew.git
                              (from `git remote get-url origin`)
    GATING_CHECKS            unit-tests, lint    (auto-discovered from
                              the most recent successful CI run; edit
                              sidebrew/AGENTS.md if wrong)

  next: lib/install.sh + fleet onboarding-check ~/projects/sidebrew

proceed? [y/N]
```

One `y`, ~90 seconds, and project #2 is running under the same fleet
policy as project #1. The operator does not have to remember that
QUIET_HOURS exists. Per P-5, the win is the absent re-tuning step.

Sub-scenario: an operator with THREE slugs runs `fleet add` without
`--inherit-from`. The kit prints `fleet add: multiple slugs eligible to
inherit from: courtiq, sidebrew, hedgehog. pass --inherit-from <slug>
or run \`fleet rank\` to pick the healthiest one.` exit 2. No
auto-guessing.

### Growth
This is the surface that closes the loop on "show me YOUR fleet" —
today, an operator who wants to evangelize the kit at the office can
only really show ONE working slug because adding a friend's repo
under their loop is too much work to demo live. With `fleet add`, the
operator can say "let me show you" and have a friend's repo running
under the same fleet policy in two minutes. That converts the kit
from "look at my one impressive slug" to "watch me onboard yours
into mine." Per the brief's "the second-project friction… an operator
who can't easily extend to project #2 churns at project #1" — this
is the direct answer.

Differentiated from `fleet onboard` (0011): `onboard` is for the FIRST
slug or for a greenfield install with no template. `add` is for the
N-th slug under an existing fleet. The two share the rendering helpers
but diverge on the default-resolver: `onboard` derives defaults from
the kit's static `_template_agents.config.sh`; `add` derives them from
a named existing slug.

## Acceptance criteria

Each box maps 1:1 to a test scenario in `tests/add.sh`.

- [ ] `bin/fleet add <project-path>` is a new subcommand. Required arg
      is the project path (must be an existing git repo with an
      `origin` remote, same shape as `fleet onboard`). Missing path:
      prints `fleet add: missing <project-path>. usage: fleet add
      [--inherit-from <slug>] [--dry-run] [--force] <project-path>` to
      stderr, exit 2 per LESSONS 2026-06-01. Path that is not a
      directory: prints `fleet add: <path> is not a directory` to
      stderr, exit 2. Path with no `origin` remote: prints `fleet
      add: <path> has no git origin remote — run \`git remote add
      origin\` first` to stderr, exit 2. Test asserts all three
      refusals.
- [ ] `bin/fleet add --inherit-from <slug>` resolves the source slug
      via the same `overview_discover_slugs` discovery `fleet
      overview` (0019) uses. Unknown slug: prints `fleet add:
      inherit-from slug \`<name>\` not found. discovered slugs:
      <list>` to stderr, exit 2. Test asserts via fixture with
      multiple slugs.
- [ ] When `--inherit-from` is omitted AND exactly one slug is
      discovered, `fleet add` auto-selects that slug (prints `fleet
      add: inheriting from <slug> (only discovered slug)`). When
      `--inherit-from` is omitted AND ≥2 slugs are discovered, refuses
      with `fleet add: multiple slugs eligible to inherit from:
      <comma-list>. pass --inherit-from <slug> or run \`fleet rank\`
      to pick the healthiest one.` exit 2. Test asserts both branches.
- [ ] The inheritance table is the static list:
      `BUDGET_DAILY_USD`, `CROSS_LESSONS`, `QUIET_HOURS`,
      `LOCAL_GATE_CMD`, `PROMPTS_PIN_SHA`, `SHIP_PAUSE_THRESHOLD`,
      `TRAINEE_REMAINING`. The PROJECT-SPECIFIC table is `SLUG`,
      `REPO_URL`, `GATING_CHECKS`. The two lists are declared as
      shell arrays at the top of the `add` block and the test
      asserts via `grep -E '^add_inherit_fields=' bin/fleet` that
      they match the lists in this AC exactly (no drift).
- [ ] The inherited-value resolution reads the source slug's
      `agents.config.sh` via the same parser used by
      `fleet_load_manifest`, NOT by re-implementing a sed/awk
      walk. Per LESSONS 2026-06-05 (export-in-subshell trap), the
      manifest is sourced inside a `( … )` subshell and the values
      are echoed out as TSV `key<TAB>value` rows that the parent
      reads — no leak into the kit's own shell. Test asserts via
      fixture manifest with each inheritable key set.
- [ ] The project-specific resolution: `SLUG` from
      `basename "$proj_dir"`, `REPO_URL` from `git remote get-url
      origin` inside the project dir, `GATING_CHECKS` from the most
      recent successful CI run on the project's default branch via
      `gh run list --branch <default> --status success --limit 1
      --json jobs --jq '.[].jobs[].name'` — stubbed by the test
      harness. When the `gh` discovery fails (no successful runs,
      no network), the field falls back to the literal placeholder
      `shellcheck, validate` plus a printed warning `add: could
      not auto-detect gating checks for <slug>; using placeholders
      — edit <path>/AGENTS.md after.` Test asserts both branches.
- [ ] The diff render prints the "inherited values" table followed
      by the "project-specific" table in the exact column shape
      shown in the User-lens example, padded via
      `preflight_visible_width` per LESSONS 2026-06-05. Every
      printf of a field name or value goes through `printf -- '%s'`
      per LESSONS 2026-05-28. The render exits 0 IFF the operator
      confirms `y` at the prompt; on `n` (or empty) it prints
      `fleet add: aborted; nothing written.` exit 0. Test asserts
      both branches via stdin pipe.
- [ ] `bin/fleet add --dry-run` skips the confirmation prompt AND
      the file writes AND the install call — it prints the diff and
      exits 0. Useful for `fleet preflight`-style inspection before
      committing. Test asserts.
- [ ] `bin/fleet add --force` skips the confirmation prompt and
      proceeds. Useful for scripted multi-add. Already-existing
      `agents.config.sh` at the destination still refuses (per the
      `fleet onboard` guard) unless `--force` is set; the refusal
      text is `fleet add: <path>/agents.config.sh already exists —
      pass --force to overwrite, or run \`fleet onboard --force\`
      if you want the full greenfield scaffold instead.` Test
      asserts.
- [ ] On confirmed apply, `fleet add` writes the project's contract
      files via the same `onboard_write_one` helper `fleet onboard`
      (0011) uses, with the inherited and project-specific values
      pre-filled. The same six files are written:
      `agents.config.sh`, `AGENTS.md`, `docs/backlog/README.md`,
      `docs/backlog/_template.md`, `docs/LESSONS.md`, and a
      placeholder `prompts/CHANGELOG.md`. Test asserts the byte
      contents match the rendered diff via fixture.
- [ ] On confirmed apply, after the writes, `fleet add` invokes
      `lib/install.sh <project-path>` (overridable via
      `FLEET_INSTALL_CMD` for tests, same convention as `fleet
      onboard`). On install failure: prints `fleet add: install.sh
      failed — see install.log` to stderr, exit 1, but does NOT
      delete the scaffolded files (operator can re-run install
      after fixing). Test asserts via failing stub.
- [ ] On install success, `fleet add` automatically invokes `fleet
      onboarding-check <project-path>` (0041) and forwards its
      exit code. The operator sees a single composed "scaffold →
      install → verify" run from one command. Test asserts via
      stub asserting the call order.
- [ ] `bin/fleet add --help` prints USAGE mentioning the path arg,
      `--inherit-from`, `--dry-run`, `--force`. Test asserts via
      `grep -qF -- "$kw" "$help_out"` per LESSONS 2026-05-30.
      Help block ends with `exit 0` per LESSONS 2026-06-01
      (dispatcher fall-through).
- [ ] `bin/fleet add` is ALMOST a pure reader of the source slug
      and a PURE WRITER of the destination project. It emits ZERO
      events into either slug's `events.jsonl`. Test asserts the
      source slug's `events.jsonl` byte size is unchanged before
      and after invocation, AND the destination project has no
      `events.jsonl` written by `fleet add` itself (the first
      event lands when `lib/install.sh` wires launchd and the
      first run fires).
- [ ] `lib/common.sh` — NO changes. `prompts/` — NO changes. No
      new event types. Test asserts via `git diff --name-only
      main...HEAD -- lib/common.sh prompts/` returns empty.
- [ ] `tests/add.sh` covers all 14 boxes above using
      `$HOME/.local/bin` stubs (for `gh` and `FLEET_INSTALL_CMD`)
      per LESSONS 2026-05-26 (PATH reset). Fixture
      `agents.config.sh` source manifests and stubbed installs
      live under `tests/fixtures/add/`. Per LESSONS 2026-05-27
      backup/restore via `cp` (NOT `$(cat)`). Counts use `awk …
      END { print n+0 }` per LESSONS 2026-06-01. The confirmation
      prompt is fed via `echo y | bin/fleet add …`. Run-time
      budget: <12s.

## Out of scope

The dev agent will NOT do these even if they seem related.

- AUTO-INHERITING from the healthiest slug when `--inherit-from` is
  omitted in a multi-slug fleet. v1 refuses and tells the operator to
  pick. Auto-picking violates the operator-confidence Hard NO (the
  operator must consciously choose which slug is the template).
- INHERITING the source slug's BACKLOG. The new project starts with
  the empty backlog template. Cross-slug backlog import is a separate
  concern.
- INHERITING the source slug's `events.jsonl` history. Each slug owns
  its own telemetry channel.
- A REVERSE direction: `fleet add --export-template <slug>` that
  dumps the inherit values to a file for sharing. v1 is local
  copy-from-existing only.
- A `fleet add --all-repos-in <dir>` batch mode. v1 is one project at
  a time. Batch mode is a v2 composition.
- Modifying `fleet onboard` to share the inheritance logic. v1
  duplicates ~20 lines of glue to keep `onboard` as the greenfield
  surface and `add` as the inherit surface — the two will diverge.
- AUTO-EDITING the source slug's `agents.config.sh` (e.g. to record
  that it was used as a template). The source is read-only.
- A launchd schedule. Operator-invoked only.

## Engineering notes

Files / patterns the dev should touch.

- `bin/fleet` — new `add()` dispatcher function placed next to the
  existing `onboard()` block (find via `grep -n '^onboard()'
  bin/fleet`). Per LESSONS 2026-05-26 (`tail` shadow) `add` does
  not collide with any coreutils binary.
- `bin/fleet` — six helpers, ALL defined ABOVE the dispatcher
  block per LESSONS 2026-06-05 (forward-reference trap):
  - `add_resolve_source_slug` — given `--inherit-from <slug>` or
    auto-detect from `overview_discover_slugs`, returns the
    resolved slug name or refuses per AC #3.
  - `add_read_source_manifest` — sources the source slug's
    `agents.config.sh` in a `( … )` subshell per LESSONS
    2026-06-05 (export-in-subshell), echoes the inheritable
    fields as TSV `key<TAB>value` rows. Per LESSONS 2026-06-08
    the awk script declares `BEGIN { count = 0 }`. Per LESSONS
    2026-06-08 IFS=$'\t' middle-empty-field uses `-` sentinel.
  - `add_discover_gating_checks` — calls `gh run list` per AC
    #6, falls back to the literal placeholder when discovery
    fails. Per LESSONS 2026-05-28 every printf of a check name
    goes through `printf -- '%s'`.
  - `add_render_diff` — composes the two-table diff per AC #7.
    Width via `preflight_visible_width` per LESSONS 2026-06-05.
  - `add_confirm_or_abort` — reads stdin for `y/n`, returns 0
    on `y` and 1 otherwise. Per LESSONS 2026-06-01 every code
    path ends `exit 0` or `exit 1`.
  - `add_run_install_and_verify` — invokes `lib/install.sh`
    then `onboarding_check`, forwards exit codes.
- `bin/fleet` — `add()` end-state must be `exit 0` / `exit 1` /
  `exit 2` on every code path per LESSONS 2026-06-01.
- `bin/fleet` — dispatcher block: `if [ "$CMD" = "add" ]; then
  add "$@"; fi`. Place AFTER the `onboard` dispatcher.
- `bin/fleet` — help banner block at the top of the file gets
  ONE new line: `fleet add <repo> add a project to your fleet
  by inheriting another slug's policy`. README "Daily ops" code
  block gets the same line, appended via the same single-edit
  pattern that avoided LESSONS 2026-05-25.
- `bin/fleet` — `add` reuses `onboard_render_manifest`,
  `onboard_render_agents_md`, `onboard_render_backlog_readme`,
  and `onboard_write_one` verbatim. The only divergence is the
  default-resolver: `add` calls `add_read_source_manifest` to
  populate the inheritable fields before
  `onboard_render_manifest` runs, instead of leaving them as
  template placeholders.
- `AGENTS.md` — NO content change.
- `lib/common.sh` — NO changes. The source-manifest read uses
  `fleet_load_manifest` SEMANTICS (subshell-sourced
  `agents.config.sh`) without altering its signature.
- `lib/install.sh` — NO changes. `fleet add` invokes the
  existing install.sh unchanged.
- `prompts/` — NO changes.
- `tests/fixtures/add/` — NEW directory holding:
  - `source-manifest-courtiq.sh` — a fully-populated source
    `agents.config.sh` with every inheritable field set.
  - `source-manifest-minimal.sh` — a source manifest with only
    the required fields (no `QUIET_HOURS`, no
    `PROMPTS_PIN_SHA`) — `add` must handle the missing-field
    case by skipping the row in the diff and writing the
    template default into the destination.
  - `multi-slug-fleet/` — a fixture fleet with three discovered
    slugs to exercise the multi-slug refusal.
  - `dest-with-existing-config/` — a destination project that
    already has an `agents.config.sh` for the refusal test.
  - `dest-clean/` — a fresh git repo with only `origin` remote
    set, no existing kit files.
  - Stub `gh` and stub `install.sh` for the install-success
    and install-failure scenarios.
- `tests/add.sh` — top of file mirrors `tests/onboarding-check.sh`
  (the closest prior ticket; shares the stub-`gh` pattern). Stubs
  live under `$HOME/.local/bin` per LESSONS 2026-05-26 (PATH
  reset). Counts use `awk … END { print n+0 }` per LESSONS
  2026-06-01. Per LESSONS 2026-05-27 backup/restore via `cp`.
  Run-time budget: <12s.
- New deps: none. Pure shell + awk + existing helpers + the
  same `gh` dep the rest of the kit relies on.
- Public API: additive — `bin/fleet add` is a new subcommand.
  ZERO new event types, ZERO event writes, ZERO `lib/common.sh`
  changes, ZERO `prompts/` changes.
- BREAKING flag: NO. PR body affirms "additive subcommand,
  reuses `onboard_*` helpers verbatim, no `fleet_*` signature
  changes, no runtime hot-path changes, no install.sh
  changes."
- Reinstall required: NO. Existing slugs are untouched. The
  new slug runs `lib/install.sh` as part of `fleet add` itself.
- LESSONS to defend against: 2026-05-25 (README "Daily ops"
  code block addition — append one line, do not insert mid-
  block), 2026-05-26 (`tail` shadow), 2026-05-26 (PATH reset
  — stubs in `$HOME/.local/bin`), 2026-05-27 (`$(cat)` trap
  — use `cp` for backup/restore), 2026-05-28 (printf leading-
  dash — every field-name printf goes through `printf -- '%s'`),
  2026-05-30 (`grep -F --` trap), 2026-06-01 (`grep -c file ||
  echo 0` double-print — counts use `awk … END { print n+0 }`),
  2026-06-01 (dispatcher fall-through — every `add` code path
  ends `exit 0/1/2`), 2026-06-03 (UTF-8 sign-extension — JSON
  escape via `preflight_json_escape` IF a `--json` mode is
  added in a follow-up; v1 has no `--json`), 2026-06-05
  (dispatcher forward-reference — all `add_*` helpers defined
  ABOVE the dispatcher), 2026-06-05 (bash 3.2 LC_ALL caching
  — character work via `LC_ALL=C awk`), 2026-06-05 (export-in-
  subshell trap — source-manifest read happens inside `( … )`
  per `add_read_source_manifest`), 2026-06-08 (awk empty-
  string-key — `BEGIN { count = 0 }`), 2026-06-08 (IFS=$'\t'
  middle-empty-field — sentinel for missing fields), 2026-06-11
  (BSD `date -j -f` fills missing time fields with NOW-of-day
  — N/A here; no date math), 2026-06-13 (no `*_json_escape`
  wrapper around `preflight_json_escape` — N/A; v1 has no JSON).
- This ticket compounds 0011 (`fleet onboard` — reuses its
  rendering helpers verbatim), 0019 (`fleet overview` — reuses
  its slug discovery), 0032 (`fleet preflight` — the dry-run
  surface that `--dry-run` resembles), 0041 (`fleet
  onboarding-check` — invoked as the final verify step), 0004
  (`BUDGET_DAILY_USD` — the inherited budget), 0033
  (`QUIET_HOURS` — the inherited PTO knob), 0005
  (`PROMPTS_PIN_SHA` — the inherited prompts pin), 0042
  (`fleet streak` — referenced in the multi-slug refusal text
  as a way to pick the healthiest slug), 0043 (`fleet rank` —
  same). Per P-1 the diff is small: ~250 lines of `add_*`
  helpers + ~300 lines of test + 8 fixture files + one
  help-text line + one README line.

## Implementation log

(Appended by the implementation-dev agent during execution.)
