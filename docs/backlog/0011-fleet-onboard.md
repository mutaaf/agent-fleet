---
id: 0011
title: fleet onboard bootstraps a new project in one command
status: groomed
priority: P1
area: engine
created: 2026-05-26
owner: gtm-innovation
---

## User story

As a fleet operator adding my 4th project to the loop, I want to run
`fleet onboard /path/to/new-repo` and have everything wired up in one
command, so that the time from "I have a new repo I want to automate" to
"the first agent PR is open" is minutes instead of an hour of copy/paste.

## Why now (four lenses)

### Product Owner
The README's "Onboarding a brand-new repo" section is 8 manual steps spread
across 5 files. That's the single biggest acquisition friction in the kit —
the operator already KNOWS they want to use it and we make them grep
templates and copy them by hand. One subcommand collapses the whole flow.
Subtraction: the operator does nothing the kit could do for them.

### Stakeholder
Widens the moat on *adoption speed*. The kit's value compounds with the
number of projects on it (shared lessons, shared engine fixes), so the
fastest path from "new repo" to "loop installed" directly grows the moat.
Pairs with `fleet doctor` (0003) — onboard creates the state, doctor
validates it.

### User (operator at 9am)
"I just spun up a side project. Let me put it on the fleet." Today: 20-30
minutes and a checklist. After: `fleet onboard ~/code/side-project` and
the next `ship :41` fire opens PR #1. The operator's daily-driver workflow
gets a new gear.

### Growth
This is the showable demo. "Here's a fresh repo. Watch me put it on
autonomous coding in 30 seconds." Anyone evaluating the kit will look for
this. Without it the kit is a power-user-only toolkit; with it, it's a
product.

## Acceptance criteria

Each box maps 1:1 to a test scenario in `tests/onboard.sh`.

- [ ] `bin/fleet onboard <project-path>` runs against a fresh `mktemp -d`
      that already contains `.git`, a `main` branch, and a remote configured
      to a placeholder URL. After the command exits 0, the directory
      contains: `agents.config.sh`, `AGENTS.md` (with `## Agent parameters`
      and `## Hard NOs` sections), `docs/LESSONS.md` (empty stub),
      `docs/backlog/README.md`, `docs/backlog/_template.md`,
      `scripts/check-backlog.mjs`, and `.claude/agents/{implementation-dev,
      gtm-innovation,review}.md`.
- [ ] The generated `agents.config.sh` has `SLUG` set to the basename of
      `<project-path>`, `NAMESPACE="com.<slug>"`, `REPO_URL` pulled from
      `git remote get-url origin`, and `SELF_CANCEL` set to today + 21 days
      (UTC). Other vars match `manifest.example.sh` defaults.
- [ ] The generated `AGENTS.md § Agent parameters` is the contents of
      `templates/AGENTS.section.md` with `<slug>` substituted into the
      bracket placeholders where possible (gating checks remain bracketed
      since they're repo-specific; operator must edit).
- [ ] `bin/fleet onboard --dry-run <project-path>` prints the list of files
      it WOULD create without writing anything. Exit 0.
- [ ] Given a project-path that already has an `agents.config.sh`,
      `fleet onboard` exits 1 with `already onboarded — use 'fleet onboard
      --force' to overwrite` and writes nothing.
- [ ] With `--force`, existing files are overwritten and a one-line
      `[OK] reset` per file is printed.
- [ ] `--skip-install` skips calling `lib/install.sh`. Default behavior
      DOES call `bash $KIT_ROOT/lib/install.sh <project-path>` at the end,
      so the operator gets a fully installed project. The test asserts
      install.sh was invoked (stub it on PATH).
- [ ] After onboarding completes, the printed output ends with the exact
      string `next: 'launchctl kickstart -k gui/$UID/com.<slug>.agent-ship'
      to trigger the first run`.
- [ ] `tests/onboard.sh` exercises the happy path, the
      already-onboarded-without-force path, and the dry-run path.

## Out of scope

- A guided / interactive prompt. v1 is fully non-interactive — flags only.
- Bootstrapping the GitHub branch protection rules (those require API
  calls the operator may want to review).
- Detecting the project's test framework and pre-filling the local gate
  command. Leave the bracket placeholder for the operator.
- Onboarding `eng-dev.md` subagent. Add later when ENG_ENABLED is set.

## Engineering notes

- `bin/fleet` — add `onboard()` function plus the top-level case branch.
- Templates already exist under `templates/`. The onboard command copies
  them with light substitution (`sed -e "s/<slug>/$slug/g"` etc.).
- The three `.claude/agents/*.md` subagents are not yet in `templates/` —
  this ticket needs to add them under `templates/claude-agents/`. Use the
  existing `templates/claude-agents/eng-dev.md` as a structural model;
  fill in implementation-dev / gtm-innovation / review with the same voice
  as the agent-fleet repo's own `.claude/agents/` if those exist locally,
  else write fresh stubs from the README's role descriptions.
- The `docs/LESSONS.md` stub is just `# LESSONS\n\nOperational memory.\n`.
- `tests/onboard.sh` — `mktemp -d`, init a git repo with a fake remote,
  invoke `bin/fleet onboard $tmpdir`, stub `install.sh` and `launchctl`
  on PATH, assert filesystem state.
- Public API: additive (`bin/fleet onboard`). No `lib/` public function
  signature changes.
- Reinstall: not strictly required (this is `bin/` only), but the new
  `templates/claude-agents/*.md` files need to ship with the kit.

## Implementation log

(Appended by the implementation-dev agent during execution.)
