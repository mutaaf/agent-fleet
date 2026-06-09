---
id: 0041
title: fleet onboarding-check verifies a freshly-installed project is end-to-end healthy
status: groomed
priority: P1
area: docs
created: 2026-06-09
owner: gtm-innovation
---

## User story

As a friend who just adopted agent-fleet on their personal SaaS side
project by running `bash install.sh /path/to/their-repo` and is now
staring at the terminal wondering "did that actually wire anything
up?", I want `bin/fleet onboarding-check <repo-path>` to walk a single
synthetic ship cycle against the freshly-installed project — confirm
the `events.jsonl` channel writes, the launchd plist resolved its
namespace, the `gh` CLI has push access to the project's remote, the
prompts SHA pinned in `agents.config.sh` matches the installed copy,
and the `AGENTS.md § Agent parameters` block parses — and print a
green/yellow/red table for each precondition WITHOUT firing the real
launchd job or opening a real PR, so I close the install loop with the
same "everything is wired" confidence that `kickstart --demo` gave me
for the kit itself, and back out by uninstalling if any check is red.

## Why now (four lenses)

### Product Owner
The kit's acquisition flow has TWO confidence cliffs and one is now
covered. `kickstart --demo` (0023) answers "what does the loop DO?"
without touching the operator's machine. `preflight` (0032) answers
"what WOULD install.sh do to my repo?" without writing anything. But
the third cliff — "I ran install.sh; is it actually working?" —
currently has no first-class command. The operator's recovery today
is: open `~/Library/LaunchAgents/` to confirm the plist landed,
`launchctl print gui/$UID/<label>` to confirm the label is enabled,
`ls ~/.cache/<slug>-agent/` to confirm the cache dir exists, `gh auth
status` in the project, `tail -F` the events.jsonl waiting for the
next hourly fire to PROVE the loop runs end-to-end — five terminals,
~one hour of waiting.

The smallest meaningful unit of value is one command that simulates
a single PHASE 1 + PHASE 2 fire against the installed project (NO real
`gh pr create`, NO real `claude` spawn, NO heal-counter advance) and
prints:

```
fleet onboarding-check /Users/me/code/myproject

CHECK                                  RESULT
agents.config.sh present + parses      GREEN
AGENTS.md § Agent parameters block     GREEN
docs/backlog/README.md index present   GREEN
~/.local/share/agent-fleet/lib copied  GREEN
launchd plist installed (ship/groom)   GREEN
launchd labels enabled                 GREEN
$CACHE_DIR/events.jsonl writable       GREEN
gh CLI auth + push to remote           GREEN
claude CLI on $PATH                    GREEN
prompts SHA pinned + matches installed GREEN
synthetic ship cycle (NO real PR)      GREEN — 4 events emitted
  • run_started     phase=onboarding-check
  • pr_opened       phase=onboarding-check (synthetic #0)
  • lesson_draft_emitted phase=onboarding-check
  • run_completed   phase=onboarding-check exit=0

onboarding-check: 11/11 green; loop is ready to fire.
exit 0
```

Subtraction: the operator stops waiting an hour for the first hourly
ship fire to PROVE the install worked. They KNOW within ~10s. Per
P-5 (operator confidence over feature richness), the win is converting
the post-install hour of anxiety into one command and one verdict.

### Stakeholder
This is **moat-deepening on the acquisition path** — the
capstone of the trio (`kickstart --demo` → `preflight` →
`onboarding-check`) that takes a stranger from "what is this?" to
"this is installed and working" in under five minutes of total
operator time. The kit's pitch competes against two real
alternatives: (a) the operator's existing hand-rolled single-agent
loop (high switching cost, sunk-cost emotional weight), and (b)
doing nothing. The acquisition trio attacks (a) directly: the
hand-rolled loop has no demo, no preflight, no post-install
verifier — every step the kit ships closes a credibility gap that
the hand-rolled loop has open by construction.

Per P-6 (telemetry is the source of truth), the synthetic ship cycle
emits real events with `phase=onboarding-check` so consumers (`fleet
overview`, `fleet weekly`, fleet-control) can filter them out of ROI
rollups exactly the way `phase=demo` events are filtered (ticket
0023's discriminator). The discriminator is the contract: every
synthetic event the kit emits carries a non-default `phase=` value,
and every ROI consumer filters on `phase IN (ship, groom, review,
eng)`. This ticket doesn't add a new event type — it REUSES the
existing four core types with a new `phase` value. No telemetry
schema change.

Per P-3 (heal in-flight before new work), `onboarding-check` runs
synchronously and finishes in <10s, so an operator running it during
a stuck heal investigation gets a clean answer fast and doesn't
fight the autonomous loop for resources.

Compounds 0011 (`fleet onboard` — the WRITE side of new-project
adoption), 0032 (`preflight` — the BEFORE-install dry-run; this
ticket is the AFTER-install verifier), 0023 (`kickstart --demo` —
the kit-LOOP demo; this is the kit-INSTALLED-ON-MY-PROJECT verifier),
and 0003 (`fleet doctor` — the LIVE health check after the loop has
fired N times; `onboarding-check` is what the operator runs at N=0).

### User (friend who just ran `install.sh` 30 seconds ago)
Friend types `bin/fleet onboarding-check ~/code/myproject`. Sees
within 10 seconds:

```
onboarding-check: 11/11 green; loop is ready to fire.

NEXT
  • the next hourly :37 mark will fire your first real ship.
  • want to fire it now without waiting? `launchctl kickstart -k
    gui/$UID/<your-label>.agent-ship`.
  • want to watch the loop work? `fleet tail --slug myproject`.
```

vs. a yellow result:

```
CHECK                                  RESULT
...
launchd labels enabled                 YELLOW — agent-groom NOT
                                       enabled (agent-ship IS)
...

onboarding-check: 10/11 green, 1 yellow.

YELLOW: agent-groom is installed but not enabled. The groomer
won't refresh your backlog until you run:
  launchctl enable gui/$UID/<your-label>.agent-groom

This is sometimes intentional (you want to ship from a hand-curated
backlog) — if so, ignore.

exit 0
```

vs. a red result:

```
CHECK                                  RESULT
...
gh CLI auth + push to remote           RED — gh not authenticated
                                       for `mutaaf/myproject`. Run
                                       `gh auth login` and re-run.
...

onboarding-check: 9/11 green, 1 yellow, 1 red.
exit 1
```

The verdict is shaped EXACTLY like `preflight`'s for muscle-memory
consistency. The friend's recovery for any yellow/red is one
copy-pasteable command. Per LESSONS 2026-05-22 (fleet-control)
"loop docs pointed at a non-existent LESSONS path," the verifier
catches the most common install footgun (the launchd label
namespace clashing with a previously-uninstalled project) as a
GREEN/RED, not as a silent no-fire-at-`:37`.

### Growth
The acquisition demo recording becomes ONE terminal window:

```
$ git clone https://github.com/mutaaf/agent-fleet
$ cd agent-fleet
$ bin/fleet kickstart --demo            # 60s: SEE the loop
$ bin/fleet preflight ~/code/myproject  # 5s: WHAT WOULD install do
$ bash install.sh ~/code/myproject      # 30s: INSTALL
$ bin/fleet onboarding-check ~/code/myproject  # 10s: IS IT WIRED
$ launchctl kickstart -k gui/$UID/myproject.agent-ship  # 2s: FIRE
$ fleet tail --slug myproject           # streams the live run
```

Six commands, ~two minutes, end-to-end. A friend reading the README
sees the recording embedded and the mental model "I can adopt this
in two minutes" lands without trust transfer. This is the kind of
asset that ends in a tweet / a conference slide / a "show HN" link.

A friend running their own claude loop reads the `onboarding-check`
output table and immediately understands the kit's discipline: every
adoption-flow precondition is named (one row), enforced (the
synthetic cycle), and visible (color verdict). The mental model
"installing an autonomous loop is a deterministic process with a
verdict" is contagious. Per the brief's "what makes a friend WHO
ALREADY RUNS A CLAUDE LOOP say I want this kit instead of my
hand-rolled one" — the acquisition trio IS the answer.

## Acceptance criteria

Each box maps 1:1 to a test scenario in `tests/onboarding-check.sh`.

- [ ] `bin/fleet onboarding-check <repo-path>` is a new subcommand
      that REQUIRES a positional path argument. Missing: print
      `onboarding-check: usage: bin/fleet onboarding-check
      <repo-path>` to stderr, exit 2 per LESSONS 2026-06-01
      (dispatcher fall-through trap). Path not a directory: print
      `onboarding-check: <path>: not a directory` to stderr, exit
      2. Test asserts both branches.
- [ ] The verifier runs ELEVEN checks in order: agents.config.sh
      present + sources cleanly, AGENTS.md § Agent parameters
      block present, docs/backlog/README.md index present,
      `~/.local/share/agent-fleet/lib/` copied for this slug,
      launchd plists installed (`agent-ship` + `agent-groom`),
      launchd labels enabled, `$CACHE_DIR/events.jsonl` writable
      (touch + remove a sentinel file), `gh` CLI authenticated
      + has push to the project's remote, `claude` CLI on `$PATH`
      and runnable, prompts SHA in `agents.config.sh` matches
      `bin/fleet prompts-sha` on the installed copy, and a
      synthetic ship cycle that emits exactly the four core
      event types (`run_started`, `pr_opened`,
      `lesson_draft_emitted`, `run_completed`) with
      `phase=onboarding-check`. Test asserts each check
      independently against a fixture installed-project tree.
- [ ] Per-check verdict is GREEN (passed), YELLOW (passed but
      operator might intend the non-default state — e.g.
      agent-groom disabled), or RED (failed; loop will not fire
      end-to-end without operator action). One-line remediation
      hint accompanies every YELLOW and RED row. Exit code: 0
      if every check is GREEN or YELLOW; 1 if any check is RED.
      Test asserts the three-way verdict shape via fixture
      tampering (remove `agents.config.sh` → RED;
      `launchctl disable` agent-groom → YELLOW; clean tree →
      GREEN).
- [ ] The synthetic ship cycle emits EXACTLY the four core event
      types named in AC#2 with `phase=onboarding-check` and a
      synthetic `slug=onboarding-check-<6-hex>` value. NO real
      `gh pr create`, NO real `claude` spawn, NO heal-counter
      advance, NO `ship_paused` state change. The events land
      in the AGENT-FLEET project's `$CACHE_DIR/events.jsonl`
      (kit-as-project, per ticket 0028 / `lesson_promoted` and
      0035 / `prompts_reverted`) so the synthetic events do NOT
      pollute the verified project's ROI rollup. Test asserts
      via `node -e 'JSON.parse(...)'` on the last four channel
      lines.
- [ ] `bin/fleet onboarding-check --json <repo-path>` emits one
      JSON object per check `{"check": <name>, "result":
      "green|yellow|red", "hint": "<one-line>"}`, one per line,
      followed by a final summary object `{"summary":
      {"green": N, "yellow": N, "red": N, "exit": 0|1}}`. JSON
      escape goes through `preflight_json_escape` per LESSONS
      2026-06-03. Test asserts JSON validity via Node.
- [ ] `bin/fleet onboarding-check --help` prints USAGE
      mentioning `--json`, the positional `<repo-path>`, and the
      list of checks. Test asserts via `grep -qF -- "$kw"
      "$help_out"` per LESSONS 2026-05-30. Help block ends with
      `exit 0` per LESSONS 2026-06-01.
- [ ] When ANY check is RED, the summary printed to stdout
      includes a NEXT section listing exactly the
      copy-pasteable commands the operator needs to flip each
      red to green (one per red). Test asserts the NEXT block
      via a fixture forcing a RED row.
- [ ] When all checks are GREEN, the summary printed to stdout
      includes a NEXT section with three lines: the next hourly
      :37 fire, the `launchctl kickstart` command to fire NOW,
      and the `fleet tail --slug` command to watch. Test asserts
      the GREEN-path NEXT block byte-for-byte against a golden.
- [ ] The "prompts SHA pinned + matches installed" check
      reuses the existing `fleet prompts-sha` helper from
      ticket 0005 and compares it against the value in the
      target project's `agents.config.sh`. Unset PROMPTS_SHA in
      the target = YELLOW (warns "drift events will fire silently
      forever"), not RED (the kit ships without PROMPTS_SHA
      required). Test asserts both unset and matching branches.
- [ ] The synthetic ship cycle DOES NOT call `fleet_run_claude`
      (the public-API entrypoint that spawns the real claude
      binary). Instead it directly emits the four typed events
      via `fleet_emit_event`. Test asserts via a `claude` stub
      under `$HOME/.local/bin` per LESSONS 2026-05-26 (PATH
      reset trap) that recorded ZERO invocations.
- [ ] `lib/common.sh` — NO changes. `onboarding-check` is a
      pure caller of `fleet_emit_event` (existing) and
      `fleet_load_manifest` (existing) and `fleet_check_prompts
      _sha` (existing). NO new `fleet_*` helpers, NO public API
      changes. Test asserts via `git diff --name-only main…HEAD
      -- lib/common.sh` returns empty.
- [ ] `prompts/` — NO changes. PHASE 0 readers are untouched.
      No `Reinstall: all projects` line needed because `lib/`
      and `prompts/` are byte-unchanged. Test asserts via `git
      diff --name-only main…HEAD -- prompts/` returns empty.
- [ ] `tests/onboarding-check.sh` covers all 11 boxes above
      using `$HOME/.local/bin` stubs for `gh`, `launchctl`,
      `claude` per LESSONS 2026-05-26. The stub `gh` records
      every invocation so the "NO real PR" assertion is
      grep-checked. Per LESSONS 2026-05-27 the test backs
      up/restores fixture files via `cp`. Counts use `awk …
      END { print n+0 }` per LESSONS 2026-06-01. The clock is
      frozen via `FLEET_NOW_OVERRIDE`. Run-time budget: <10s.

## Out of scope

The dev agent will NOT do these even if they seem related.

- Actually firing the launchd job. The verifier simulates the
  ship cycle in-process; it never calls `launchctl kickstart`.
  The GREEN-path NEXT section TELLS the operator the command,
  but does not run it.
- Auto-fixing red checks. A `--fix` flag silently fixes things
  the operator might not want fixed (re-running install.sh on
  a YELLOW launchd state would re-enable agent-groom even when
  the operator intended it disabled). The verifier prints the
  hint; the operator runs the fix.
- Verifying the operator's `AGENTS.md § Agent parameters`
  SEMANTICS — only that the BLOCK is present + parses. A
  missing `Gating checks:` row in a project's AGENTS.md is a
  reviewer concern, not an onboarding-check concern.
- Running against multiple projects at once. The verifier is
  per-project. The fleet-wide rollup is `fleet overview` (ticket
  0019). Composition is one shell line.
- Modifying or deleting any file under `~/.local/share/agent-
  fleet/`, `~/Library/LaunchAgents/`, or `~/.cache/`. The
  verifier is READ-ONLY against the installed state.
- A network call to GitHub beyond the existing `gh auth status`
  + `gh repo view` the kit already uses. The verifier does NOT
  call `gh pr create`, `gh pr list`, or any write endpoint.
- A launchd schedule. Operator-invoked only — by definition
  the operator runs this once at install time and rarely
  after.
- Linting the target project's shell or source. That is
  `self-check`'s domain (ticket 0040), and even there it scans
  the KIT's source, not the operator's project.

## Engineering notes

Files / patterns the dev should touch. Specific enough that the dev
doesn't have to re-discover the architecture.

- `bin/fleet` — new `onboarding_check()` dispatcher function
  placed next to the existing `preflight()` block (find via
  `grep -n '^preflight()' bin/fleet`, currently ~line 1438).
  Shape mirrors `preflight()` for the `--json` / `--help` flag
  handling and the table-vs-json render split AND the per-check
  helper extraction (preflight already factors checks into named
  functions; copy that pattern).
- `bin/fleet` — eleven check helpers + one synthetic-cycle
  helper, ALL defined ABOVE the dispatcher block per LESSONS
  2026-06-05 (forward-reference trap):
  - `onboarding_check_agents_config`
  - `onboarding_check_agents_md_section`
  - `onboarding_check_backlog_index`
  - `onboarding_check_lib_copied`
  - `onboarding_check_plists_present`
  - `onboarding_check_labels_enabled`
  - `onboarding_check_events_writable`
  - `onboarding_check_gh_auth`
  - `onboarding_check_claude_cli`
  - `onboarding_check_prompts_sha`
  - `onboarding_check_synthetic_cycle`
  - `onboarding_check_render_text`
  - `onboarding_check_render_json`
  - Each check helper prints one TSV record `name<TAB>
    result<TAB>hint` to stdout. The consumer pipeline reads
    these via `IFS=$'\t' read -r name result hint` — per
    LESSONS 2026-06-08 (middle-empty-field trap), empty hints
    on GREEN rows emit a `-` sentinel and are remapped to
    empty in the consumer.
- `bin/fleet` — `onboarding_check_synthetic_cycle` is the
  load-bearing helper. It generates a synthetic slug
  (`onboarding-check-<6-hex>` from `od -An -tx1 -N3 /dev/urandom
  | tr -d ' '`), calls `fleet_log_init onboarding-check`, emits
  the four core events directly via `fleet_emit_event`
  (NOT via `fleet_run_claude` per AC#9), and exits cleanly.
  The `pr_opened` event carries `number=0 branch=synthetic`
  so any downstream consumer that filters
  `phase=onboarding-check` sees a self-consistent synthetic
  trace.
- `bin/fleet` — `onboarding_check()` end-state must be `exit 0`
  (all checks green/yellow), `exit 1` (any check red), or
  `exit 2` (usage error) on every code path per LESSONS
  2026-06-01 (dispatcher fall-through trap). Copy the exit-N
  pattern from `preflight()` (~line 1438) verbatim.
- `bin/fleet` — dispatcher block: `if [ "$CMD" = "onboarding-
  check" ]; then onboarding_check "$@"; fi`. Place AFTER the
  `preflight` dispatcher (~line 1548). Per LESSONS 2026-06-05
  (forward-reference trap), confirm every helper
  `onboarding_check` calls is defined ABOVE the dispatcher
  block.
- `bin/fleet` — help banner block at the top of the file
  (around line ~14) gets a new line: `fleet onboarding-check
  <repo>  verify a freshly-installed project end-to-end`.
  README "Adopting a project" section gets a new paragraph
  showing the three-step `kickstart → preflight → install →
  onboarding-check` flow.
- `AGENTS.md § Telemetry` — NO new bullet. This ticket REUSES
  the existing four core event types with a new `phase=
  onboarding-check` value. The phase-discriminator pattern is
  documented in the Demo path paragraph at the bottom of §
  Telemetry — extend that paragraph to name `onboarding-check`
  alongside `demo`. Test asserts via `grep -qF -- "phase=
  onboarding-check" AGENTS.md`.
- `lib/common.sh` — NO changes. `onboarding-check` is a pure
  caller of `fleet_emit_event` (existing), `fleet_log_init`
  (existing), `fleet_load_manifest` (existing),
  `fleet_check_prompts_sha` (existing). NO new helpers, NO
  `fleet_*` signature changes.
- `prompts/` — NO changes.
- `tests/fixtures/onboarding-check/` — NEW directory under
  `tests/fixtures/` holding one synthetic "installed project"
  tree: `agents.config.sh`, `AGENTS.md` (with the § Agent
  parameters block), `docs/backlog/README.md`, a fake `~/
  .local/share/agent-fleet/lib/common.sh` (1-line marker),
  two fake launchd plists. The test mutates this tree per
  AC#3 to force YELLOW and RED states.
- `tests/onboarding-check.sh` — top of file mirrors
  `tests/preflight.sh`: stub `gh`, `claude`, `launchctl` under
  `$HOME/.local/bin` (`$HOME=$TMP/home` per LESSONS
  2026-05-26). The stub `gh` records every invocation; the
  test asserts `[ "$(awk … END { print n+0 }" "$gh_log")" = 0
  ]` for the AC#9 "no real PR" assertion. The event assertion
  reads the kit's events channel and parses the last four
  lines via `node -e 'JSON.parse(...)'`. Per LESSONS
  2026-05-27, the test uses `cp` for fixture restore. Counts
  use `awk … END { print n+0 }` per LESSONS 2026-06-01.
  Run-time budget: <10s.
- New deps: none. Pure shell + awk + existing helpers.
- Public API: additive — `bin/fleet onboarding-check` is a new
  subcommand. ZERO new event types. NO `fleet_*` signature
  changes.
- BREAKING flag: NO. PR body affirms "no `fleet_*` signature
  changes, no new event types, REUSES four core types with
  `phase=onboarding-check` discriminator (same shape as
  `phase=demo` from ticket 0023)."
- Reinstall required: NO. `lib/` and `prompts/` are
  untouched. Operator runs `git pull` on the kit checkout
  and the new subcommand is immediately available.
- LESSONS to defend against: 2026-05-25 (load-bearing docs —
  the README adoption-flow paragraph is the docs surface).
  2026-05-26 (`tail` shadow — `onboarding_check` is
  namespaced; helpers are `onboarding_check_*`). 2026-05-26
  (PATH reset — stubs go in `$HOME/.local/bin`). 2026-05-27
  (`$(cat)` trap — fixture restore uses `cp`). 2026-05-28
  (printf leading-dash — every check name / hint goes through
  `printf -- '%s'`). 2026-05-30 (`grep -F --` trap — help
  text uses `grep -qF --`). 2026-06-01 (`grep -c file || echo
  0` double-print — counts use `awk … END { print n+0 }`).
  2026-06-01 (dispatcher fall-through —
  `onboarding_check()` ends with explicit `exit N`).
  2026-06-03 (UTF-8 sign-extension — JSON escape goes through
  `preflight_json_escape`). 2026-06-05 (dispatcher forward-
  reference — helpers above dispatcher block). 2026-06-05
  (export inside `$(...)` — the synthetic-cycle helper is
  invoked WITHOUT command substitution so its event-emit
  side effects land). 2026-06-08 (IFS=$'\t' middle-empty-
  field — check TSV uses `-` sentinels for empty hints).
- This ticket compounds 0011 (`fleet onboard` — the WRITE
  side; this is the AFTER-install verifier), 0032
  (`preflight` — the BEFORE-install dry-run), 0023
  (`kickstart --demo` — the kit-LOOP demo; this is the
  installed-on-my-project verifier), 0003 (`fleet doctor` —
  the LIVE health check after the loop has fired N times;
  `onboarding-check` is what the operator runs at N=0). Per
  P-1 the diff is small: ~350 lines of `onboarding_check_*`
  helpers + ~250 lines of test + fixture tree + one
  AGENTS.md Telemetry-paragraph edit + one help-text line
  + one README paragraph.

## Implementation log

(Appended by the implementation-dev agent during execution.)

- YYYY-MM-DD — branch `feat/0041-...` opened
- YYYY-MM-DD — failing test added in `tests/onboarding-check.sh`
- YYYY-MM-DD — PR #N opened, CI [state]
- YYYY-MM-DD — merged to main
