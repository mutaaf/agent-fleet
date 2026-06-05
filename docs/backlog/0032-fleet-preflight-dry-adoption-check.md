---
id: 0032
title: fleet preflight <repo> dry-adopts a project and prints what install.sh would do
status: shipped
priority: P1
area: docs
created: 2026-06-05
owner: gtm-innovation
---

## User story

As a curious operator who just `git clone`d agent-fleet on a Sunday
afternoon and is staring at their main side-project wondering "what
happens if I point this loop at code I actually care about?", I want
`bin/fleet preflight <repo-path>` to read the candidate repo's
`agents.config.sh` + `AGENTS.md` + backlog scaffolding + `gh auth
status` + `claude` CLI presence, simulate the launchd plist that
`install.sh` WOULD generate, and print a green / yellow / red verdict
for each precondition WITHOUT writing one file under
`~/.local/share/agent-fleet/`, `~/Library/LaunchAgents/`, or
`~/.cache/<slug>-agent/`, so that I can decide to adopt the fleet on
this repo with the same confidence a `--dry-run` migration would give
me — and back out by closing the terminal if any check is red.

## Why now (four lenses)

### Product Owner
Adoption today is a confidence cliff. `install.sh` is idempotent and
safe, but the operator does not know that on first contact — they see
"this writes plists under `~/Library/LaunchAgents/` and copies an
engine into `~/.local/share/`" and the friction is real even though
the action is reversible. `fleet kickstart --demo` (ticket 0023)
already removed the credential cliff for the LOOP itself, but the
INSTALL still lacks a "what would this do to MY repo" preview.
`preflight` is the inverse of `doctor` (which validates AFTER
install): same checks, same output shape, run BEFORE install and
against a candidate path rather than the discovery roots. Smallest
unit of value: one command, one verdict, zero side effects, zero
launchd labels. The operator who runs preflight and sees nine greens
runs install.sh next; the operator who sees a yellow on `AGENTS.md
section missing` fixes that first instead of debugging a half-installed
project later.

### Stakeholder
This is the missing acquisition primitive. The README's "Quickstart"
section assumes the operator will just trust install.sh and run it;
in practice many will not, and the fleet loses adopters at exactly
the moment we have their attention. `preflight` is a one-paragraph
addition to README that turns "adopt the fleet" from a five-step
checklist into a two-step one (`preflight`, then `install.sh` if
green). It also doubles as the install.sh's own test surface: every
check `install.sh` does at runtime — manifest validity, AGENTS.md
agent-parameters section presence, backlog index well-formedness,
plist namespace not already taken by another label, `gh auth status`,
`claude` on PATH, write access to `~/.local/share/agent-fleet/` — gets
extracted into a named helper that BOTH preflight and install.sh
invoke. This deepens the moat on the install path: one source of truth
for "is this repo ready," reused by the preview AND the action.

### User (operator at 9am, candidate project in `~/code/widgets`)
Runs `bin/fleet preflight ~/code/widgets`. Sees:

```
fleet preflight: dry-adopting ~/code/widgets …

  manifest (agents.config.sh):          PASS  (SLUG=widgets, NAMESPACE=com.widgets)
  AGENTS.md § Agent parameters:         PASS  (gating checks: lint, unit-tests)
  backlog scaffolding:                  PASS  (docs/backlog/README.md, 3 tickets)
  backlog validator:                    PASS  (scripts/check-backlog.mjs exists)
  subagents under .claude/agents/:      WARN  (eng-dev.md missing — ENG_ENABLED=0 in manifest, OK)
  gh auth status:                       PASS  (mutaaf, scopes: repo, read:org)
  claude CLI on PATH:                   PASS  (/Users/mutaaf/.local/bin/claude)
  ~/.local/share/agent-fleet writable:  PASS
  launchd namespace free:               PASS  (no existing com.widgets.* labels)
  SELF_CANCEL >= today + 7d:            WARN  (SELF_CANCEL=20260612 — only 7 days; consider 30d+ for a new project)

verdict: 8 PASS, 2 WARN, 0 FAIL — safe to install.
next:   bash lib/install.sh ~/code/widgets
```

No file was written. No launchd label was loaded. The verdict line
encodes the install decision; the operator runs install.sh next, or
fixes the warns first.

If a critical check fails (no AGENTS.md section, no manifest, plist
namespace already taken by ANOTHER slug, `gh` unauthenticated), the
verdict reads `2 PASS, 1 WARN, 3 FAIL — DO NOT install yet.` and
exit code is 1, so the operator can chain into a shell `&&`.

### Growth
The README has one paragraph today inviting newcomers to try
`fleet kickstart --demo`. `preflight` adds the second invitation:
"try the demo, then preflight your own repo." Both are zero-risk,
both produce a structured artifact the operator can paste into a
friend's DM ("here's what preflight said about my repo"). This is
the shape every successful CLI adoption funnel takes —
`terraform plan` before `terraform apply`, `gh repo create
--dry-run`, `npm install --dry-run`. We have the engine; we did not
have the preview. Friends running their own loop pick this up
immediately because the alternative (running install.sh against an
unfamiliar repo and praying) is the friction they ALL feel on the
first try.

## Acceptance criteria

Each box maps 1:1 to a test scenario in `tests/preflight.sh`.

- [ ] `bin/fleet preflight <repo-path>` on a fully-correct fixture
      project prints the 10 check rows above (PASS/WARN/FAIL each),
      a verdict line `N PASS, N WARN, N FAIL — <safe|DO NOT> install`,
      and exits 0 when zero FAILs. Test fixtures a happy-path project
      under `tests/fixtures/preflight/widgets/` and asserts the
      golden output via `tests/fixtures/preflight.golden.txt`.
- [ ] On a project missing `agents.config.sh`, the row reads `FAIL
      (no agents.config.sh at <path>)`, verdict carries `1 FAIL`,
      exit code is 1. Test asserts the exact failure row and the
      exit code.
- [ ] On a project whose `AGENTS.md` exists but does NOT contain a
      `## Agent parameters` heading (the contract anchor the runners
      read), the row reads `FAIL (AGENTS.md missing '## Agent
      parameters' section)`, verdict carries the FAIL, exit code is 1.
- [ ] On a project whose `NAMESPACE` already has a loaded
      `com.<ns>.agent-ship` label under `launchctl print-disabled
      gui/$UID` / `launchctl list` for a DIFFERENT slug, the row
      reads `FAIL (launchd namespace com.<ns>.* already claimed by
      <other-slug>)`, exit code is 1. Test stubs `launchctl` under
      `$HOME/.local/bin` per LESSONS 2026-05-26 and seeds two
      conflicting labels.
- [ ] On a project whose `SELF_CANCEL` is fewer than 7 days from
      today, the row reads `WARN (SELF_CANCEL=YYYYMMDD — only Nd;
      consider 30d+ for a new project)`. WARN does NOT block; exit
      code is 0 if no FAILs.
- [ ] `--json` emits one JSON object per check row plus one summary
      row at the end. Shape mirrors `fleet inbox --json` and `fleet
      atlas --json`: `{"check":"<name>","status":"PASS|WARN|FAIL",
      "detail":"<one-line>"}` per row, then `{"summary":true,
      "pass":N,"warn":N,"fail":N,"verdict":"safe|do_not_install"}`.
      Parsed via `node -e 'JSON.parse(...)'`. Test asserts the full
      document structure.
- [ ] `preflight` writes ZERO files outside `$TMPDIR` and the
      working tree of the test fixture itself. Test asserts via
      `find $HOME/.local/share/agent-fleet $HOME/Library/LaunchAgents
      $HOME/.cache -newer $TMPDIR/start_marker 2>/dev/null` returning
      empty. The `$HOME=$TMP/home` isolation (LESSONS 2026-05-26)
      makes this a clean assertion.
- [ ] `preflight` does NOT invoke `launchctl bootstrap`,
      `launchctl enable`, or any `launchctl` mutation — only
      read-only `launchctl print` / `launchctl list`. Test asserts
      via the stub's recorded invocation log that no mutation verb
      was called.
- [ ] Unknown path: `preflight: no such directory <path>` to
      stderr, exit 2. Test asserts the exact error.
- [ ] Help: `bin/fleet preflight --help` prints a USAGE block
      mentioning `<repo-path>`, `--json`, `--help`. Test asserts via
      `grep -qF -- "$kw" "$help_out"` per LESSONS 2026-05-30. Help
      block ends with `exit 0` per LESSONS 2026-06-01 (dispatcher
      fall-through trap).
- [ ] `tests/preflight.sh` covers all 10 boxes using
      `$HOME/.local/bin` stubs for `launchctl`, `gh`, `claude`.
      `FLEET_DISCOVERY_ROOT` redirected. Per LESSONS 2026-05-27,
      the test uses `cp` for backup/restore — never `$(cat …)`.
      Run-time budget: <10s.

## Out of scope

The dev agent will NOT do these even if they seem related.

- Actually installing or modifying any launchd label. `preflight` is
  read-only by definition; the operator runs `install.sh` next as a
  separate, deliberate action. Adding an `--apply` flag would
  collapse two commands into one and erase the "preview, then act"
  shape the ticket is built around.
- Rewriting `install.sh` to use the new check helpers in the same PR.
  Extract the helpers as PURE FUNCTIONS so install.sh CAN adopt them
  in a follow-up ticket, but do NOT change `install.sh`'s behavior in
  THIS PR. Per P-1 (smallest viable change), the install.sh refactor
  is its own ticket once preflight has shipped and the helper shapes
  have stabilized.
- A `--fix` flag that mutates the candidate repo (creates the missing
  AGENTS.md section, bumps SELF_CANCEL, scaffolds backlog). The kit's
  posture is to TELL the operator what is wrong, not to silently fix
  their repo from a tool they have not yet invited to write.
- Network checks (e.g. `gh api repos/<owner>/<slug>` to verify the
  repo exists). preflight is offline by default; the existing `gh
  auth status` check is the only `gh` invocation. Adding a network
  reach would slow the command and add a flake mode.
- A launchd schedule for `preflight`. Like `doctor` and `inbox`, this
  is operator-run by hand.
- Multi-project preflight (`preflight all`). The command is per-repo
  by design — the operator is evaluating ONE candidate at a time.
  Bulk preflight belongs in `fleet doctor`, which already covers the
  POST-install case.

## Engineering notes

Files / patterns the dev should touch. Specific enough that the dev
doesn't have to re-discover the architecture.

- `bin/fleet` — new `preflight()` dispatcher next to `doctor()`
  (line ~1048) and `onboard()` (line ~611). Shape mirrors
  `doctor()`'s table render + `--json` toggle; the difference is
  preflight takes a path argument and runs against ONE candidate,
  not all discovered projects.
- `bin/fleet` — ten check helpers, all pure readers, one per AC
  row. Suggested names: `preflight_check_manifest`,
  `preflight_check_agents_md_section`,
  `preflight_check_backlog_scaffolding`,
  `preflight_check_backlog_validator`,
  `preflight_check_subagents`,
  `preflight_check_gh_auth`,
  `preflight_check_claude_on_path`,
  `preflight_check_share_writable`,
  `preflight_check_launchd_namespace`,
  `preflight_check_self_cancel_horizon`.
  Each echoes one line: `<status>\t<detail>` (tab-separated, parsed
  by the renderer). Each is INDEPENDENT — no shared mutable state
  — so the renderer can call them in fixed order.
- `bin/fleet` — `preflight_render_text` and `preflight_render_json`
  output helpers. Per LESSONS 2026-05-28 (printf leading-dash trap),
  every `printf` of a path or slug uses `printf -- '%s' "$val"`.
  Per LESSONS 2026-06-01 (awk -v multiline trap), no multi-line
  value goes through `awk -v`.
- `bin/fleet` — `preflight()` end-state must be `exit 0` (success
  with zero FAILs), `exit 1` (≥1 FAIL), or `exit 2` (usage error)
  on every code path per LESSONS 2026-06-01 (dispatcher
  fall-through trap). Copy the exit-N pattern from `doctor()`
  (line ~1048) verbatim.
- `bin/fleet` — dispatcher block at the bottom of the file:
  `if [ "$CMD" = "preflight" ]; then preflight "$@"; fi`. Placed
  next to the existing `doctor` / `onboard` blocks.
- `bin/fleet` — help banner block at the top of the file (around
  line ~14) gets a new line: `fleet preflight <repo>   dry-adopt
  a project; print what install.sh would do (read-only)`. README
  "Daily ops" code block and the "Quickstart" section get a
  one-paragraph mention of preflight as the recommended pre-step.
- `lib/common.sh` — NO changes. `preflight` is a pure consumer of
  existing helpers (`fleet_load_manifest` is invoked READ-ONLY in
  a subshell to avoid polluting the caller's env). NO `fleet_*`
  signature changes.
- `lib/install.sh` — NO changes in this PR. The check helpers are
  designed for FUTURE adoption by install.sh in a follow-up ticket
  (single source of truth for "is this repo ready"); for now they
  live only in `bin/fleet` and install.sh keeps its existing
  inline checks.
- `prompts/` — NO changes. The command is operator-facing only;
  no agent prompt reads `fleet preflight`. No `Reinstall: all
  projects` line is needed because `lib/` and `prompts/` are
  untouched.
- `tests/fixtures/preflight/` — NEW directory under `tests/
  fixtures/` holding three synthetic projects:
  - `widgets/` (happy path) — manifest, AGENTS.md with section,
    backlog scaffolding, no eng-dev subagent (WARN), SELF_CANCEL
    30d out.
  - `widgets-broken/` (missing AGENTS.md section) — manifest +
    AGENTS.md that lacks the contract anchor.
  - `widgets-collide/` (NAMESPACE collision) — manifest whose
    NAMESPACE matches a stubbed `launchctl list` row for another
    slug.
  - One golden `tests/fixtures/preflight.golden.txt` with the
    exact expected output for the happy path.
- `tests/preflight.sh` — top of file mirrors `tests/doctor.sh`:
  stub `launchctl` (read-only verbs only), `gh`, `claude` under
  `$HOME/.local/bin` (`$HOME=$TMP/home` per LESSONS 2026-05-26).
  The JSON test parses output via `node -e
  'JSON.parse(require("fs").readFileSync(0,"utf8"))'`.
- New deps: none. Pure shell + awk + existing `_json_escape`
  (common.sh ~849) used via `fleet_emit_event` — wait, `preflight`
  does NOT emit events (it is read-only), so it uses the
  `provenance_json_escape` UTF-8-safe escape pattern (per LESSONS
  2026-06-03 the bin/fleet local copy is UTF-8-safe; reuse it).
- Public API: additive — `bin/fleet preflight` is a new subcommand.
  NO new event types (read-only command per P-6: emitters write,
  readers compose). NO `fleet_*` signature changes.
- BREAKING flag: NO. PR body affirms "no `fleet_*` signature
  changes," "no new event types added," and "no install.sh
  behavior change in this PR."
- Reinstall required: NO. `lib/` and `prompts/` are untouched.
- LESSONS to defend against: 2026-05-26 (`tail` shadow —
  `preflight` is not a coreutils binary; confirmed via `command
  -v preflight` returning nothing). LESSONS 2026-05-26 (PATH
  reset — stubs go in `$HOME/.local/bin`). LESSONS 2026-05-27
  (`$(cat)` trap — fixture reads use `cp`/awk). LESSONS
  2026-05-28 (printf leading-dash trap — every path and slug
  goes through `printf -- '%s'`). LESSONS 2026-05-30 (`grep -F
  --` flag trap — help text and section anchors use `grep -qF
  --`). LESSONS 2026-06-01 (`grep -c file || echo 0` double-print
  trap — counts use `awk … END { print n+0 }`). LESSONS
  2026-06-01 (dispatcher fall-through trap — `preflight()` ends
  with explicit `exit N` on every path including the help block).
  LESSONS 2026-06-03 (UTF-8 sign-extension trap — the JSON
  renderer reuses the `provenance_json_escape` pattern, not the
  bare `doctor_json_escape` from before the fix).
- This ticket compounds 0003 (`fleet doctor` is the post-install
  analogue; preflight is the pre-install one), 0010 (`AGENT_
  DRY_RUN` is the runtime-dry analogue; preflight is the
  install-time-dry one), 0011 (`fleet onboard` actively
  scaffolds; preflight passively previews — the two pair).
  Per P-1 the diff is small: ~300 lines of `preflight*` helpers +
  ~150 lines of test fixture content + one golden + one
  help-text line + one README paragraph.

## Implementation log

(Appended by the implementation-dev agent during execution.)

- 2026-06-05 — branch `feat/0032-fleet-preflight-dry-adoption-check` opened
- 2026-06-05 — failing test added in `tests/preflight.sh` (11 ACs covered)
- 2026-06-05 — PR #62 opened, CI green (shellcheck + validate)
- 2026-06-05 — merged to main
