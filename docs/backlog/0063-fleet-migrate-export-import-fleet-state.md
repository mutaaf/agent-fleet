---
id: 0063
title: fleet migrate --export / --import packages an operator's whole fleet into one tarball so a fresh MacBook is restored in 60 seconds
status: groomed
priority: P1
area: engine
created: 2026-06-23
owner: gtm-innovation
---

## User story

As a fleet operator who has been running `agent-fleet` against four
slugs (`sidebrew`, `courtiq`, `digitalcraft`, `levelup-kids`) for 14
weeks on my work MacBook — who has spent that time dialing in four
separate `agents.config.sh` files (each carrying its own
`BUDGET_DAILY_USD`, `QUIET_HOURS`, `LOCAL_GATE_CMD`,
`MANUAL_PR_MINUTES`, `CONTRACTOR_USD_PER_HOUR`, `PROMPTS_PIN_SHA`,
`TRAINEE_REMAINING`, `SHIP_PAUSE_THRESHOLD`), accumulating four
per-slug `events.jsonl` channels (the only audit trail of every
`pr_footer_posted`, `lesson_promoted`, `prompts_pin_changed`, etc.
that justifies every `fleet invoice`, `fleet why`, `fleet trends`,
`fleet streak` rendering), and curating the cross-fleet
`CROSS_LESSONS.md` that 0009/0028/0051 all read — who just bought
a new MacBook Air and finds the path from "fresh laptop" to "the
loop is back on every project" requires re-cloning every repo,
re-running `bash lib/install.sh` per slug, manually re-copying
every `agents.config.sh` value out of a screenshot or git history,
and crucially LOSING the per-slug `events.jsonl` history (which
makes `fleet invoice --ytd`, `fleet trends`, `fleet streak`, and
every "this month vs last month" rollup blank for the next 8
weeks) — I want `bin/fleet migrate --export <path.tar.gz>` to
package my whole fleet into one timestamped, manifest-validated,
optionally-encrypted tarball, and `bin/fleet migrate --import
<path.tar.gz>` to restore it onto a fresh machine in one command
(re-cloning each repo if missing, re-running `lib/install.sh` per
slug, re-populating each `$CACHE_DIR/events.jsonl` and
`runs.jsonl`, re-installing `CROSS_LESSONS.md` under
`$FLEET_CROSS_LESSONS`), so that the fear of "if this MacBook
dies I lose 14 weeks of telemetry" stops being a reason to defer
upgrading hardware and `fleet why <slug>` keeps rendering on the
new machine with byte-identical citations the moment migration
completes.

## Why now (four lenses)

### Product Owner

The kit's existing acquisition surface assumes a brand-new
operator on a fresh install: 0023 `fleet kickstart --demo`
walks a credential-less synthetic loop, 0011 `fleet onboard`
scaffolds the first project, 0052 `fleet add` adds the second
project on the SAME machine inheriting from the first, 0032
`fleet preflight` dry-adopts to print what install.sh would
do, 0041 `fleet onboarding-check` verifies a freshly-installed
project. NONE of those handle the SECOND-MACHINE problem: an
operator who already trusts the kit and wants to move it (new
MacBook, home laptop + work laptop, post-disk-failure restore,
giving a peer a 1:1 reproducible "here is exactly my fleet"
demo). The smallest meaningful unit of value is one tarball
that round-trips on a fresh machine:

```
$ fleet migrate --export ~/Desktop/fleet-2026-06-23.tar.gz
fleet migrate — exporting 4 slugs to /Users/op/Desktop/fleet-2026-06-23.tar.gz

  sidebrew         agents.config.sh + events.jsonl (412 KB) + runs.jsonl (87 KB)
  courtiq          agents.config.sh + events.jsonl (1.2 MB) + runs.jsonl (203 KB)
  digitalcraft     agents.config.sh + events.jsonl (88 KB)  + runs.jsonl (14 KB)
  levelup-kids     agents.config.sh + events.jsonl (52 KB)  + runs.jsonl (8 KB)

  cross-fleet      CROSS_LESSONS.md (44 KB)
  manifest         fleet-export.json (sha256 + version + created_at)

  written: /Users/op/Desktop/fleet-2026-06-23.tar.gz (2.1 MB)
  next step: copy to the new machine, run `fleet migrate --import <path>`

$ fleet migrate --import ~/Downloads/fleet-2026-06-23.tar.gz
fleet migrate — importing fleet from /Users/op/Downloads/fleet-2026-06-23.tar.gz

  verified: sha256 matches manifest
  verified: export schema version 1 (compatible)
  detected: 4 slugs not yet on this machine

  sidebrew         repo at ~/code/sidebrew         CLONE ~/code/sidebrew
  courtiq          repo at ~/code/courtiq          CLONE ~/code/courtiq
  digitalcraft     repo at ~/code/digitalcraft     SKIP (already cloned)
  levelup-kids     repo at ~/code/levelup-kids     CLONE ~/code/levelup-kids

  confirm (Y/n)? Y

  cloning... done (4/4)
  installing... done (4/4 via lib/install.sh)
  restoring events.jsonl... done (4/4, 1.7 MB total)
  restoring runs.jsonl... done (4/4, 312 KB total)
  restoring CROSS_LESSONS.md... done (44 KB)

  verify: fleet invoice sidebrew --month 2026-05  -> 14 PRs, $7.84 (matches export)
  verify: fleet streak courtiq                    -> 23 days (matches export)
  next step: launchctl bootstrap fires on the next schedule tick
```

Subtraction: the operator stops fearing hardware failure. Per
P-5 (operator confidence over feature richness), the win is
the absent "what if I lose this laptop" anxiety. Per the
brief's "Don't want to babysit launchd. install.sh +
uninstall.sh must be idempotent." — `migrate --import`
re-uses `lib/install.sh` per slug exactly the way 0011
onboard does; no new install primitive.

`--export` defaults to `~/Desktop/fleet-<YYYY-MM-DD>.tar.gz`
when no path is given. `--export --redact` strips slug names
and repo URLs (per 0053 portfolio-redact convention) so the
operator can share an EXPORT for demo purposes without
leaking project identity. `--export --encrypt` runs the
tarball through `openssl enc -aes-256-cbc -pbkdf2 -pass
env:FLEET_EXPORT_PASS` (operator sets the env var
beforehand; the README documents the recovery path). `--import
--dry-run` walks the same flow but prints "would clone…",
"would install…", "would restore…" without writing.
`--import --skip-clone` assumes the operator already cloned
the repos at the same paths (escape hatch for operators who
prefer manual `git clone` per slug).

The "verify" footer of `--import` runs THREE cheap pure-
reader assertions (`fleet invoice <one_slug> --month
<last_full_month>`, `fleet streak <one_slug>`, `wc -l
CROSS_LESSONS.md`) against both the export's recorded
expected outputs (in `fleet-export.json`) and the freshly-
imported state. A mismatch on any one of the three prints
`MIGRATION VERIFY FAILED` to stderr with the diff and
exits 3 — the operator knows immediately whether the
import is byte-faithful to the export.

### Stakeholder

This is **moat-deepening on the ACQUISITION axis** —
turning every existing operator into a potential
ambassador for a SECOND deployment (their own second
machine, a peer's first machine, a future-self after
disk failure). Per P-6 (telemetry is the source of
truth), `migrate` is a PURE PACKAGER over each slug's
`agents.config.sh` + `events.jsonl` + `runs.jsonl` + the
cross-LESSONS file, plus a thin orchestrator that calls
the EXISTING `lib/install.sh` per slug on import. NO
new event types, NO `lib/common.sh` changes, NO new
`fleet_*` public functions. The diff is the tar
composer + the manifest writer + the validator + the
import orchestrator + the verify pass. ~420 lines.

The tarball SHAPE is the moat: it codifies "what is the
state of a fleet" into a single audit-able artifact.
Every kit fact (PR count, cost, lessons promoted, prompts
pinned) is reproducible on the destination machine
because the EVENTS the kit reads to derive those facts
are part of the export. Competing autonomous-agent
toolkits ship per-project state in opaque process memory
or per-vendor cloud sync; agent-fleet ships it in a
hashable tarball the operator owns and can `tar tvf` at
will. That portability shape is unusual in the space.

Per LESSONS 2026-06-15 (per-day shellout inside per-slug
loops is O(window × N_slugs)) the per-slug export is ONE
`tar` append per slug PLUS ONE awk pass over each
events.jsonl/runs.jsonl to compute the expected-verify
checksums; no per-day `date -j -v` shellout. With four
slugs the export budget is <3s.

Per LESSONS 2026-06-11 (BSD `date -j -f` fills missing
time fields) the export timestamp uses
`date -u '+%Y-%m-%dT%H:%M:%SZ'` directly (no `date -j -f`
involved) and the export manifest's `created_at` carries
the full timestamp.

Per LESSONS 2026-06-08 (`IFS=$'\t'` middle-empty-field
collapse) any TSV manifest line whose middle column can
be empty uses a `-` sentinel.

Per LESSONS 2026-06-13 (no `*_json_escape` wrapper) the
manifest writer calls `preflight_json_escape` directly
at each site.

Per cross-LESSONS 2026-05-22 (courtiq, two-PR ship
ritual) `migrate --import` runs `lib/install.sh` per
slug exactly the way 0011 onboard already does — no
new install primitive, no manual launchctl bootstrap
beyond what install.sh already handles. That makes the
restore path byte-equivalent to a fresh install on the
new machine, plus the layered telemetry restore.

Per cross-LESSONS 2026-05-21 (courtiq #12, `gh pr
checks --watch` 502 fallback) the import's verify pass
does NOT shell out to `gh`; it walks the freshly-
restored events.jsonl with awk and compares to the
expected counts written into the export manifest, so
the verify is offline-safe (operator can import on a
plane without auth).

Compounds 0011 (`fleet onboard` — migrate import calls
the same `lib/install.sh` per slug), 0052 (`fleet add`
— migrate's clone+install flow mirrors the second-
project wrapper's), 0053 (`fleet portfolio --redact`
— migrate's `--redact` mode reuses the same
redaction convention), 0061 (`fleet invoice` —
migrate's verify pass calls invoice for one slug),
0042 (`fleet streak` — migrate's verify pass calls
streak for one slug), 0028 (`fleet lessons-promote` —
migrate packages the same CROSS_LESSONS.md the
promoter writes), 0019 (`fleet overview` — reuses
`overview_discover_slugs`), 0036 (`fleet morning` —
migrate's `--import` writes the same morning-state
mtime convention so the new machine starts at "fresh
since last run").

Differentiated from `fleet onboard` (0011): onboard
creates a NEW project from scratch; migrate restores
an EXISTING fleet's exact state. Differentiated from
`fleet add` (0052): add is intra-machine adding slug
#2; migrate is inter-machine moving the WHOLE fleet.
Differentiated from `fleet portfolio --redact`
(0053): portfolio is a one-pager shareable; migrate
is a complete restoration tarball. Differentiated
from raw `tar -czvf ~/.cache/sidebrew-agent`:
migrate's manifest is hash-verified, schema-
versioned, and the import path replays
`lib/install.sh` per slug — manual tar misses the
launchd bootstrap and the manifest validation.

### User (operator on a Saturday morning unboxing a new MacBook)

The operator unboxes a new MacBook Pro at 9am Saturday.
They install Homebrew, `gh auth login`, `claude
login`, set `FLEET_EXPORT_PASS=<their-passphrase>`,
copy the `fleet-2026-06-23.tar.gz` from their old
MacBook via AirDrop. They run `bin/fleet migrate
--import ~/Downloads/fleet-2026-06-23.tar.gz`. They
confirm `Y` to the clone prompt. Three minutes later
the script prints `verify: fleet invoice sidebrew
--month 2026-05  -> 14 PRs, $7.84 (matches export)`.
They open `fleet morning` — same briefing as
yesterday's old-MacBook morning, only the wall-clock
header differs. By 9:08am their fleet is back on the
new machine, with byte-identical telemetry. Per P-5
the win is the 5-minute "I have a new laptop" path
where there was previously a 2-hour scavenger hunt
through screenshots and gh history.

Sub-scenario: an operator runs `fleet migrate --export
--redact ~/Desktop/demo-fleet.tar.gz` and DMs it to a
peer who runs `fleet migrate --import --dry-run
~/Downloads/demo-fleet.tar.gz` to see exactly what a
real fleet looks like before committing. The dry-run
prints the verify pass against the export's expected
outputs but writes nothing.

Sub-scenario: an operator runs `fleet migrate --export
~/Dropbox/fleet-backup.tar.gz` weekly as a cron job.
The encrypted tarball lives in cloud storage; if the
MacBook dies the latest backup restores in one
command on the replacement.

Sub-scenario: an operator pre-imports a peer's
redacted demo fleet to learn from real telemetry
shapes ("here is what 6 months of operating a real
slug looks like — try `fleet trends` against it") and
then uninstalls with the existing `lib/uninstall.sh`
per slug.

### Growth

This is the surface that turns "evangelist with one
machine" into "evangelist who hands a peer a runnable
fleet." Per the brief's "why does a friend running
their own autonomous-agent setup want to adopt it?" —
migrate is the answer when the friend says "show me
what 4 months of running looks like." A 2.1 MB
tarball is more persuasive than a screenshot or a
README, because the peer can `fleet invoice --all
--ytd` against the imported state and SEE the real
ROI math. The kit's claim "your telemetry is yours
and is portable" becomes literally true and
demonstrable.

Differentiated from competing autonomous-agent
products that lock telemetry into a vendor cloud
(Cursor's usage, GitHub Copilot's stats, Claude
Code's per-session log): migrate proves the kit's
data is PORTABLE, OFFLINE, and AUDITABLE. That
portability frame is the kit's marketing.

The `--redact` mode is also a growth wedge for
public demo data: an operator posts a redacted
tarball on their blog and any reader can `fleet
migrate --import --dry-run` it to walk the same
data the operator describes in the post — turning
read-only blog content into runnable demo content.

## Acceptance criteria

Each box maps 1:1 to a test scenario in `tests/migrate.sh`.

- [ ] `bin/fleet migrate --export [<path>]` packages the
      fleet into a `.tar.gz`. Default path is
      `$HOME/Desktop/fleet-<YYYY-MM-DD>.tar.gz`. Missing
      `--export` AND missing `--import`: prints `migrate:
      usage: bin/fleet migrate --export [<path>] [--redact]
      [--encrypt] | --import <path> [--dry-run]
      [--skip-clone]` to stderr, exit 2 per LESSONS
      2026-06-01. Per LESSONS 2026-05-30 (`grep -F --` trap)
      the test assertion uses `grep -qF -- "$kw"`. Test
      asserts both refusal AND the default-path branch.

- [ ] The export tarball contains: one `fleet-export.json`
      manifest at the root, plus one subdirectory per
      discovered slug containing `agents.config.sh`,
      `events.jsonl`, `runs.jsonl`, and optionally
      `events.jsonl.archive/*` if present, plus a
      `cross-lessons/CROSS_LESSONS.md` if
      `$FLEET_CROSS_LESSONS` resolves to an existing
      file. Per LESSONS 2026-05-25 (`lib/` reinstall
      reminder) the tarball does NOT include any
      `~/.local/share/agent-fleet/lib/` copy — the
      destination machine re-installs from the kit's
      `lib/` source of truth. Test asserts via `tar tzf`
      that the layout matches and the kit lib is absent.

- [ ] The `fleet-export.json` manifest carries:
      `schema_version: 1`, `created_at` (ISO8601 UTC,
      from `date -u '+%Y-%m-%dT%H:%M:%SZ'` per LESSONS
      2026-06-11), `host` (one of `darwin`, `linux`, or
      `unknown`), `slugs[]` (each slug carries `slug`,
      `repo_path`, `repo_url`, `events_bytes`,
      `runs_bytes`, `events_sha256`, `runs_sha256`,
      `expected_verify` (a small object with
      `pr_footer_posted_count`, `streak_days`,
      `lessons_promoted_count`)), and the top-level
      `tarball_sha256` (computed AFTER all per-slug
      files are written but BEFORE the manifest is
      sealed; computed via `shasum -a 256 < <tarball-
      without-manifest>` per a deterministic build
      shape). Per LESSONS 2026-06-13 (no
      `*_json_escape` wrapper) the manifest writer
      calls `preflight_json_escape` directly at every
      site. Per LESSONS 2026-06-03 (UTF-8 sign-
      extension) JSON escape preserves UTF-8.
      Per LESSONS 2026-06-08 (awk empty-string-key)
      every awk pass declares `BEGIN { count = 0 }`.
      Test asserts manifest schema via Node's
      `JSON.parse` and walks every required field.

- [ ] `bin/fleet migrate --export --redact` replaces
      every slug name with `project-a`, `project-b`,
      `project-c` (alphabetical), every repo URL with
      `redacted://repo-<index>`, and every dollar
      amount in `runs.jsonl` is banded via the 0053
      `portfolio_redact_text` convention. Per LESSONS
      2026-06-15 (`while (match(s, /pat/)) { s = before
      repl after }` infinite-loop trap — `~$5` matches
      `/\$[0-9]+/`) the redaction uses the CURSOR-
      based walk pattern, NOT the recursive shape.
      Test asserts the redacted export contains no
      slug name from the discovered list AND no exact
      dollar amount, AND that `fleet migrate --import
      --dry-run` on the redacted tarball still emits
      a valid verify pass.

- [ ] `bin/fleet migrate --export --encrypt` requires
      `FLEET_EXPORT_PASS` env. Missing env: prints
      `migrate: --encrypt requires FLEET_EXPORT_PASS
      env var to be set` to stderr, exit 2. With env
      set, the tarball is wrapped through `openssl enc
      -aes-256-cbc -pbkdf2 -pass env:FLEET_EXPORT_PASS`
      and the output file extension is `.tar.gz.enc`.
      The manifest is encrypted alongside the rest.
      `migrate --import` auto-detects the `.tar.gz.enc`
      suffix and requires the same env. Test asserts
      round-trip with one correct pass AND one wrong
      pass (refuses to import).

- [ ] `bin/fleet migrate --import <path>` walks the
      reverse: validates the manifest sha256 first
      (refuses on mismatch with `migrate: tarball
      sha256 mismatch (expected <a>, got <b>) — file
      may be truncated or tampered with`, exit 3),
      validates `schema_version == 1` (refuses unknown
      versions with `migrate: schema_version <N> not
      supported — your kit installation may be older
      than this export`, exit 3), then enumerates each
      slug's destination. For each slug, if
      `repo_path` does not exist locally, prompts
      `clone <repo_url> into <repo_path>? (Y/n)` and
      runs `git clone` on Y; if `--skip-clone` is set
      OR `repo_path` already exists, skips the clone.
      Test asserts the three refusal paths AND the
      clone+skip branch via fixture (a fake `git`
      stub under `$HOME/.local/bin` per LESSONS
      2026-05-26 PATH reset records the clone argv).

- [ ] After clone, `migrate --import` runs `bash
      "$kit_root/lib/install.sh" "$repo_path"` per
      slug per the established 0011/0052 pattern. Per
      LESSONS 2026-06-05 (export-in-subshell trap)
      any per-slug env scoping happens inside `( … )`
      with the exports NOT leaking to the parent.
      Test asserts via fixture that `install.sh` is
      called once per slug with the resolved
      `repo_path` argv (using a stub `install.sh`
      under `$HOME/.local/bin` per LESSONS
      2026-05-26).

- [ ] After install, `migrate --import` restores
      each slug's `events.jsonl` and `runs.jsonl`
      into `$CACHE_DIR` (resolved from each slug's
      `agents.config.sh`). If the destination
      events.jsonl already exists AND is non-empty,
      prompts `events.jsonl for <slug> already has
      <N> lines on this machine. (k)eep local /
      (r)eplace with export / (m)erge? (k/r/m)`.
      Default on non-interactive shells is `k`
      (preserve local). The `m` branch concatenates
      and sorts by `ts` using ONE awk pass per slug
      per LESSONS 2026-06-15 (no per-day
      shellout). Test asserts all three branches via
      fixture.

- [ ] `bin/fleet migrate --import --dry-run` walks
      the same flow but writes NOTHING (no clone, no
      install, no events restore). Prints `would
      clone…`, `would install…`, `would restore…`,
      then the verify pass against the EXPORT's
      expected_verify numbers (read from the
      manifest, no extraction beyond it). Exit 0 on
      success. Per LESSONS 2026-06-01 (grep -c
      double-print) the verify line counts use `awk
      … END { print n+0 }`. Test asserts via fixture
      that the destination's `$CACHE_DIR` is byte-
      identical before and after dry-run.

- [ ] After restore, `migrate --import` runs THREE
      verify assertions per slug: (a) `awk` over the
      restored `events.jsonl` counting
      `pr_footer_posted` matches the manifest's
      `expected_verify.pr_footer_posted_count`; (b)
      the longest current green-day streak from the
      restored data matches `expected_verify.
      streak_days`; (c) the count of
      `lesson_promoted` events matches
      `expected_verify.lessons_promoted_count`. Per
      LESSONS 2026-06-08 every awk script declares
      `BEGIN { count = 0 }`. On ANY mismatch the
      command prints `MIGRATION VERIFY FAILED:
      <slug>: <metric> expected <X>, got <Y>` to
      stderr, exit 3. Test asserts the happy path
      AND a deliberate corruption (one events line
      removed post-export) triggers the failure.

- [ ] `bin/fleet migrate --import` restores
      `CROSS_LESSONS.md` to the path resolved from
      `${FLEET_CROSS_LESSONS:-$HOME/.local/share/
      agent-fleet/CROSS_LESSONS.md}` — the same
      precedence 0028/0051 use. If the destination
      already exists, the prompt is the same
      keep/replace/merge as events.jsonl. Test
      asserts all three branches via fixture.

- [ ] `bin/fleet migrate --export --json` emits a
      structured JSON object instead of the text
      table: `{"path": "<abs>", "schema_version": 1,
      "slugs": [{"slug": "<name>", "events_bytes":
      <int>, "runs_bytes": <int>}, ...],
      "cross_lessons_bytes": <int>, "tarball_bytes":
      <int>, "tarball_sha256": "<hex>"}`. Per
      LESSONS 2026-06-13 the JSON escape calls
      `preflight_json_escape` directly. Test asserts
      JSON validity via Node.

- [ ] `bin/fleet migrate --help` prints USAGE
      mentioning `--export`, `--import`, `--redact`,
      `--encrypt`, `--dry-run`, `--skip-clone`,
      `--json`. Per LESSONS 2026-05-30 test asserts
      via `grep -qF -- "$kw" "$help_out"`. Help
      block ends with `exit 0` per LESSONS
      2026-06-01.

- [ ] `bin/fleet migrate` does NOT modify
      `lib/common.sh`, `prompts/`, `AGENTS.md`, or
      introduce any new `fleet_emit_event` call.
      `migrate --export` writes ONLY to the
      operator-named output path (never to
      `$CACHE_DIR`, never to manifests). `migrate
      --import` writes ONLY to the destination's
      `$CACHE_DIR` per slug + the destination's
      project working trees per slug (the same set
      `lib/install.sh` already writes to). Test
      asserts: source `events.jsonl`/`runs.jsonl`
      byte sizes are unchanged before and after
      `--export`; non-target paths are unchanged
      before and after `--import`.

- [ ] `lib/common.sh` — NO changes. `prompts/` —
      NO changes. No new event types. Test asserts
      via `git diff --name-only main...HEAD --
      lib/common.sh prompts/ AGENTS.md` returns
      empty.

- [ ] `tests/migrate.sh` covers all 14 boxes above
      using `$HOME/.local/bin` stubs (`git`,
      `openssl`, `tar`, `install.sh`) per LESSONS
      2026-05-26 (PATH reset). Fixture
      `events.jsonl`, `runs.jsonl`,
      `agents.config.sh`, and a synthetic
      `CROSS_LESSONS.md` live under
      `tests/fixtures/migrate/`. The four-slug
      source fleet lives under `tests/fixtures/
      migrate/source/`. The destination fleet is
      a fresh `mktemp -d` per test. Per LESSONS
      2026-05-27 (`$(cat)` trap) backup/restore via
      `cp`. Counts use `awk … END { print n+0 }`
      per LESSONS 2026-06-01. Per LESSONS
      2026-06-08 (`IFS=$'\t'` middle-empty-field)
      sentinel `-`. Per LESSONS 2026-06-11 the
      timestamp helper uses `date -u
      '+%Y-%m-%dT%H:%M:%SZ'`. Per LESSONS
      2026-06-15 the events-merge awk is ONE pass.
      Per LESSONS 2026-06-15 the redaction uses
      the cursor-walk pattern. The clock is
      frozen via `FLEET_NOW_OVERRIDE`. Run-time
      budget: <12s.

## Out of scope

The dev agent will NOT do these even if they seem related.

- A LAUNCHD schedule that fires `fleet migrate
  --export` on a weekly cron. v1 is operator-
  pulled. The README documents the plist snippet.
- AUTO-UPLOAD to cloud storage (S3, Dropbox,
  iCloud). v1 writes a local file; the operator
  pipes/copies it. Cloud integration is a separate
  ticket per provider.
- A `--diff <export-a> <export-b>` mode comparing
  two exports of the same fleet across time.
  Useful but v2; the YTD comparison shape is in
  0061 invoice already.
- INTEGRATING the verify pass with `fleet
  onboarding-check` (0041). They share concepts
  but onboarding-check is a per-slug post-install
  validator; migrate's verify is a cross-slug
  byte-faithfulness check. Composability is a
  v2 candidate.
- A `--include-archive=false` flag to skip
  `events.jsonl.archive/*`. v1 always includes
  archives — the size cost is acceptable (<5 MB
  per slug) and the archives are part of "the
  fleet's full history" by contract.
- A WEB UI exposed by fleet-control for download
  / upload of exports. v1 is CLI-only. The
  fleet-control project can shell out to
  `bin/fleet migrate` if it ever wants a UI.
- A `--partial <slug,slug,...>` flag to export
  only a subset of slugs. v1 always exports the
  full fleet. Partial is a v2 candidate; the
  redact mode already covers the "share a subset
  publicly" use case.
- AN AUTO-RESTORE-ON-NEXT-LAUNCH path that
  detects a missing fleet and offers to import
  from a default location. v1 is explicit.
  Auto-recovery is a separate ticket with its
  own risk surface.
- A `fleet uninstall --all` complement that
  removes a whole fleet before re-importing. v1
  assumes the operator manages the destination's
  baseline; the README documents the
  `lib/uninstall.sh` per-slug recipe.
- SIGNING the tarball with a GPG key. v1 uses
  sha256 + optional symmetric encryption. PKI is
  a separate ticket if the operator community
  wants signed-publisher imports.

## Engineering notes

Files / patterns the dev should touch. Specific enough that the dev
doesn't have to re-discover the architecture.

- `bin/fleet` — new `migrate()` dispatcher function
  placed next to the existing `add()` block (find
  via `grep -n '^add()' bin/fleet`). Per LESSONS
  2026-05-26 (`tail` shadow) `migrate` does not
  collide with any coreutils binary.
- `bin/fleet` — twelve helpers, ALL defined ABOVE
  the dispatcher block per LESSONS 2026-06-05
  (forward-reference trap):
  - `migrate_discover_slugs` — wraps
    `overview_discover_slugs` (also used by 0019,
    0028, 0061), returns alphabetical order.
  - `migrate_resolve_cache_dir` — reads
    `agents.config.sh` inside `( … )` per LESSONS
    2026-06-05 (export-in-subshell trap) to
    derive `$CACHE_DIR` per slug.
  - `migrate_resolve_cross_lessons_path` — wraps
    the same precedence (`$FLEET_CROSS_LESSONS`
    env → manifest → default) 0028/0051 use.
  - `migrate_compute_expected_verify` — ONE awk
    pass per slug over events.jsonl producing
    `{pr_footer_posted_count, streak_days,
    lessons_promoted_count}`. Per LESSONS
    2026-06-08 `BEGIN { count = 0; promoted = 0 }`.
    Per LESSONS 2026-06-15 the streak math is
    pure awk arithmetic.
  - `migrate_compute_file_sha256` — wraps
    `shasum -a 256 < "$file"` with an error
    branch when the file is missing.
  - `migrate_render_manifest_json` — produces
    `fleet-export.json`. Per LESSONS 2026-06-13
    calls `preflight_json_escape` directly at
    every site. Per LESSONS 2026-06-03 the JSON
    escape preserves UTF-8.
  - `migrate_redact_one_line` — applies the 0053
    `portfolio_redact_text` convention to a
    single line. Per LESSONS 2026-06-15 the
    redaction uses the CURSOR-based walk
    pattern. Slug names are sorted descending-
    length-first to avoid prefix-collisions.
  - `migrate_pack_tarball` — runs `tar -czf` over
    a staging directory built under `mktemp -d`,
    then writes the sha256 INTO the manifest
    after the first pack pass, then re-packs once
    with the sealed manifest. Two-pack
    requirement: the manifest's `tarball_sha256`
    field is the hash of the tarball WITHOUT the
    manifest entry, computed by packing
    everything else first, hashing, then adding
    the manifest. This is the only way to ship a
    self-verifying manifest without circular
    hashing.
  - `migrate_encrypt_tarball` — wraps `openssl
    enc -aes-256-cbc -pbkdf2 -pass env:FLEET_
    EXPORT_PASS -in <plain> -out <enc>`. Refuses
    on missing env per AC #4.
  - `migrate_extract_tarball` — wraps `tar -xzf`
    into a staging `mktemp -d`. Handles the
    `.tar.gz.enc` suffix by decrypting first.
  - `migrate_validate_manifest` — re-computes
    the manifest's `tarball_sha256` against the
    extracted contents and compares; refuses on
    mismatch per AC #5.
  - `migrate_orchestrate_import` — the per-slug
    loop: prompt-or-skip clone, run install.sh,
    restore events.jsonl/runs.jsonl with the
    keep/replace/merge prompt, restore cross-
    lessons, then run verify pass.
  - `migrate_run_verify` — the verify pass per
    AC #9. ONE awk pass per slug over the
    restored events.jsonl.
  - `migrate_render_export_text` — text
    formatter for the export summary table. Width
    via `preflight_visible_width` per LESSONS
    2026-06-05. Per LESSONS 2026-05-28 every
    printf of a slug name or path goes through
    `printf -- '%s'`.
  - `migrate_render_export_json` — JSON
    formatter for `--export --json`. JSON escape
    via `preflight_json_escape` per LESSONS
    2026-06-03 called directly per LESSONS
    2026-06-13.
  - `migrate_render_import_text` — text
    formatter for the import progress table.
- `bin/fleet` — `migrate()` end-state must be
  `exit 0` / `exit 2` / `exit 3` on every code
  path per LESSONS 2026-06-01 (dispatcher
  fall-through trap). Exit codes: 0 = success,
  2 = usage / refuses-to-start, 3 = verify
  failed / sha mismatch / schema mismatch.
- `bin/fleet` — dispatcher block: `if [ "$CMD"
  = "migrate" ]; then migrate "$@"; fi`. Place
  AFTER the `add` dispatcher.
- `bin/fleet` — help banner block at the top of
  the file gets ONE new line: `fleet migrate
  --export | --import package the fleet for a new
  machine or restore it from a tarball`. README
  "Daily ops" code block gets the same line,
  appended via the same single-edit pattern that
  avoided LESSONS 2026-05-25 (the
  reinstall-reminder lesson — README mentions
  that `migrate --import` re-runs `lib/install.sh`
  per slug so a kit update on the source machine
  must precede the export for the destination to
  receive the latest lib).
- `bin/fleet` — local variables inside `migrate()`
  whose names match other subcommand functions
  MUST be prefixed (per LESSONS 2026-06-19 false-
  positive trap from ticket 0060 / 0062). The
  catalog of names to avoid as plain `local`
  names: `add`, `streak`, `stuck`, `flaky`,
  `digest`, `weekly`, `recap`, `incident`,
  `diff`, `morning`, `inbox`, `replay`, `tour`,
  `rank`, `invoice`, `why`, `pulse`, `share`,
  `onboard`, `doctor`, `resume`. Use
  `migrate_*`-prefixed locals throughout.
- `AGENTS.md` — NO content change. The export
  IS schema-versioned (manifest's `schema_version:
  1`) so a future bump is a separate ticket with
  its own migration story; v1 doesn't touch the
  contract.
- `lib/common.sh` — NO changes.
- `prompts/` — NO changes.
- `tests/fixtures/migrate/source/` — NEW
  directory holding four slug subdirs
  (`alpha-strong`, `beta-quiet`, `gamma-busy`,
  `delta-empty`) each with `agents.config.sh`,
  `events.jsonl`, `runs.jsonl`. A fifth
  `cross-lessons/CROSS_LESSONS.md` provides the
  cross-fleet file. The fixtures together
  produce a tarball under 200 KB so the test
  fits in the budget. A sixth
  `tampered-manifest/` directory holds a
  hand-edited copy of an export with a wrong
  sha256 to exercise AC #5's refusal branch.
- `tests/migrate.sh` — top of file mirrors
  `tests/onboard.sh` (closest prior orchestrator;
  shares the install-sh invocation pattern).
  Stubs live under `$HOME/.local/bin` per LESSONS
  2026-05-26 (PATH reset): `git` (records argv,
  creates a fake `.git` dir at the dest path
  per cross-LESSONS fleet-control 2026-05-26
  scaffoldAndInstall recognition), `openssl`
  (wraps real openssl when present, falls back
  to a fixture-based deterministic stub when
  not), `tar` (uses the system `tar` —
  available on macOS + Linux test runners),
  `install.sh` (records argv into a per-test
  log). Counts use `awk … END { print n+0 }`
  per LESSONS 2026-06-01. Per LESSONS
  2026-05-27 backup/restore via `cp`. Per
  LESSONS 2026-06-08 every awk script declares
  `BEGIN { count = 0 }`. Per LESSONS 2026-06-08
  `IFS=$'\t'` middle-empty-field uses `-`
  sentinel. Per LESSONS 2026-06-11 the
  timestamp helper uses `date -u
  '+%Y-%m-%dT%H:%M:%SZ'`. Per LESSONS
  2026-06-15 the events-merge awk is ONE pass.
  Per LESSONS 2026-06-15 the redaction uses
  the cursor-walk pattern. The clock is
  frozen via `FLEET_NOW_OVERRIDE`. Run-time
  budget: <12s.
- New deps: NONE that aren't shell-only or
  `node`-builtin. `tar` and `openssl` are
  pre-installed on macOS by default and on every
  reasonable Linux runner. The kit already
  depends on `node` (used for JSON validation in
  tests) and `shasum` (already used by 0029
  provenance and elsewhere). NO new top-level
  deps per the AGENTS.md hard constraint.
- Public API: additive — `bin/fleet migrate` is
  a new subcommand. ZERO new event types, ZERO
  event writes, ZERO `lib/common.sh` changes,
  ZERO `prompts/` changes, ZERO new manifest
  knobs. `FLEET_EXPORT_PASS` is an OPTIONAL env
  var read ONLY by `--encrypt` paths.
- BREAKING flag: NO. PR body affirms "pure
  packager/orchestrator, no events.jsonl
  writes, no `fleet_*` signature changes, no
  AGENTS.md changes, no new manifest knobs,
  re-uses existing `lib/install.sh` per slug."
- Reinstall required: NO. `lib/` and `prompts/`
  are untouched. The DESTINATION machine
  re-runs `lib/install.sh` per slug as part of
  `migrate --import` exactly the way 0011
  onboard already does.
- LESSONS to defend against: 2026-05-25
  (README "Daily ops" code block addition AND
  the reinstall-reminder — README explicitly
  notes that the kit must be updated on the
  source before exporting if the destination
  is to receive the latest lib), 2026-05-26
  (`tail` shadow — `migrate` is safe), 2026-
  05-26 (PATH reset — stubs in
  `$HOME/.local/bin`), 2026-05-27 (`$(cat)`
  trap — use `cp` for backup/restore in
  tests), 2026-05-28 (printf leading-dash —
  every slug-name / path / dollar-amount
  printf goes through `printf -- '%s'`),
  2026-05-30 (`grep -F --` trap), 2026-06-01
  (`grep -c file || echo 0` double-print —
  counts use `awk … END { print n+0 }`),
  2026-06-01 (dispatcher fall-through —
  every code path ends `exit 0/2/3`),
  2026-06-03 (UTF-8 sign-extension — JSON
  escape via `preflight_json_escape`),
  2026-06-05 (dispatcher forward-reference
  — all `migrate_*` helpers defined ABOVE
  the dispatcher), 2026-06-05 (bash 3.2
  LC_ALL caching — any string-length op
  via `LC_ALL=C awk`), 2026-06-05 (export-
  in-subshell trap — per-slug manifest
  reads inside `( … )`), 2026-06-08 (awk
  empty-string-key — `BEGIN { count = 0 }`),
  2026-06-08 (`IFS=$'\t'` middle-empty-
  field — sentinel `-`), 2026-06-11 (BSD
  `date -j -f` fills missing time fields —
  timestamp uses `date -u
  '+%Y-%m-%dT%H:%M:%SZ'`, no `date -j -f`
  involved), 2026-06-13 (no `*_json_
  escape` wrapper around
  `preflight_json_escape` — called
  directly), 2026-06-15 (per-day shellout
  inside per-slug loops is O(window ×
  N_slugs) — verify and events-merge
  passes are pure-awk one-pass), 2026-
  06-15 (awk `while (match(s, /pat/)) { s
  = before repl after }` infinite-loop
  trap — redaction uses CURSOR-based walk
  pattern), 2026-06-19 (`local` shadows
  subcommand-function name self-check
  false positive — all `migrate()` locals
  prefixed `migrate_*`). Cross-LESSONS
  2026-05-22 (courtiq, two-PR ship ritual
  — irrelevant; migrate is a runtime
  packager, not a backlog flow). Cross-
  LESSONS 2026-05-26 (fleet-control,
  shell-out modules need an injectable
  runner — test stubs are the injection
  point here, matching the convention).
- This ticket compounds 0011 (`fleet
  onboard` — migrate import calls the
  same `lib/install.sh` per slug), 0052
  (`fleet add` — migrate's clone+install
  flow mirrors the second-project
  wrapper's), 0053 (`fleet portfolio
  --redact` — migrate's `--redact` mode
  reuses the same redaction convention),
  0061 (`fleet invoice` — migrate's
  verify pass can call invoice for one
  slug as a smoke check), 0042 (`fleet
  streak` — migrate's verify pass
  cross-checks against the export's
  recorded streak), 0028 (`fleet
  lessons-promote` — migrate packages
  the same CROSS_LESSONS.md the promoter
  writes), 0019 (`fleet overview` —
  reuses `overview_discover_slugs`),
  0036 (`fleet morning` — migrate's
  `--import` writes the same morning-
  state mtime convention so the new
  machine's first `fleet morning` shows
  "since last run never" on a fresh
  start), 0010 (`AGENT_DRY_RUN` —
  migrate's `--dry-run` mirrors the
  same observable-nothing-written
  contract), 0050 (`fleet tour` —
  migrate's `--import --dry-run` on a
  peer's redacted export is a richer
  tour than tour's synthetic walk).
  Per P-1 the diff is small: ~420
  lines of `migrate_*` helpers + ~360
  lines of test + 5 fixture slug
  subdirs + one help-text line + one
  README "Daily ops" line + one README
  paragraph documenting the encryption
  recovery path and the source-machine
  kit-update prerequisite.

## Implementation log

(Appended by the implementation-dev agent during execution.)
