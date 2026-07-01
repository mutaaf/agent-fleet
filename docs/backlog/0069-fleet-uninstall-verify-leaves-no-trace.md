---
id: 0069
title: fleet uninstall --verify confirms a slug reversed cleanly
status: groomed
priority: P2
area: engine
created: 2026-07-01
owner: gtm-innovation
---

## User story

As a fleet operator (or a peer evaluating the kit) who has just run
`bash lib/uninstall.sh <repo>` on a slug, I want `fleet uninstall --verify`
to prove that install left no residue — no lingering launchd label, no
`~/.local/share/agent-fleet/<slug>` tree, no `~/.cache/<slug>-agent`
staging — so I trust that trying the kit is genuinely reversible instead
of a one-way `.zshrc`-style commitment.

## Why now (four lenses)

### Product Owner
0011 `fleet onboard` and 0032 `fleet preflight` make trying the kit easy;
0041 `fleet onboarding-check` confirms an install is healthy. There is
NO surface that confirms an uninstall is clean. Today a peer evaluator has
to trust `lib/uninstall.sh` blind, or manually `find` for artifacts. The
smallest meaningful unit of value is one command that walks the four known
install artifacts (launchd label, `~/.local/share/agent-fleet/<slug>`,
`~/.cache/<slug>-agent`, any prepush hook symlinks) and prints exactly
which ones remain and how to remove them.

### Stakeholder
This widens the "easy onboarding of a new project" moat named in the agent
brief — but on the REVERSE arc. Any second-operator adoption is one
reversibility-fear away from a stall; a verifiable uninstall is the
cheapest confidence-building capability the kit can ship. Per P-6, the
verify pass is a pure reader — no writes, no new event types (reuses
existing failure surface).

### Operator (9am glance)
Rare-path, but load-bearing when hit. On the days the operator does try
`uninstall.sh` (typically before an `install.sh` re-run to prove
idempotency, per LESSONS 2026-05-25 reinstall dance), the verify command
answers "did that actually leave no trace?" in three seconds instead of a
`find $HOME` walk.

### Extensibility — earned by capability, NOT marketing
Pure capability. A second operator adopting the kit inherits a
demonstrable "install and uninstall both work cleanly" — trust follows
directly from the CAPABILITY, not from a README claim. The verify walk
also documents the four known artifacts in ONE place (the checklist)
instead of scattered across install.sh.

## Acceptance criteria

- [ ] `bin/fleet uninstall --verify <slug>` walks four known install
      artifact locations and prints one line per checked artifact with
      `OK` or `RESIDUE: <path>`. The four locations are (1)
      `launchctl print gui/$UID/$NAMESPACE.<slug>-agent-ship`
      returning non-zero, (2) `~/.local/share/agent-fleet/<slug>/`
      absent, (3) `~/.cache/<slug>-agent/` absent, (4)
      `~/.local/share/agent-fleet/<slug>/prepush-hook` symlink
      absent from the project's `.git/hooks/pre-push`. Test asserts
      via a fixture with each artifact independently stubbed present
      or absent.
- [ ] `fleet uninstall --verify <slug>` exits `0` when every artifact
      shows `OK` and `2` when any shows `RESIDUE:`, so
      `&& fleet install.sh …` composition works in scripts. Per
      LESSONS 2026-06-01 (dispatcher fall-through) every code path
      ends with an explicit `exit`.
- [ ] With no `<slug>` argument, `fleet uninstall --verify` fails
      gracefully with `uninstall: --verify requires a slug` to stderr,
      exit `2`. Test asserts via `grep -qF -- "$kw"` per LESSONS
      2026-05-30.
- [ ] `fleet uninstall --verify <slug> --json` emits an object
      `{"slug": "…", "residues": [{"kind": "launchd|share|cache|hook",
      "path": "…"}], "clean": true|false}`. JSON escape via
      `preflight_json_escape` per LESSONS 2026-06-03 called directly
      (no `*_json_escape` wrapper) per LESSONS 2026-06-13. Test
      validates via `node -e 'JSON.parse(…)'`.
- [ ] Pure reader — the verify command does NOT remove any residue
      itself, does NOT `launchctl bootout` any label. Test asserts by
      seeding a residue artifact, running verify, then asserting the
      artifact still exists byte-identical afterward.
- [ ] `bin/fleet uninstall --verify --help` prints USAGE mentioning
      `--json` and `<slug>`. Help block ends with `exit 0` per
      LESSONS 2026-06-01. Adding the `--verify` sub-flag does not
      change the existing `bin/fleet uninstall` dispatcher shape (if
      present) or add a new default codepath. No change to
      `lib/uninstall.sh` public behavior — verify is a read-only
      complement.

## Out of scope

- Auto-removing detected residue (`fleet uninstall --verify --fix`).
  v1 nudges; removal stays with `lib/uninstall.sh` and manual
  `rm -rf` per README.
- Verifying a WHOLE fleet in one call (`fleet uninstall --verify
  --all`). v1 is per-slug. `--all` is a v2 candidate.
- Detecting shell-init edits (`.zshrc`, `.bashrc`) — install.sh does
  NOT touch those today per LESSONS 2026-05-25 and the operator's
  own doctrine ("editing the operator's shell config silently
  violates the idempotent-install principle"). If that ever
  changes, this ticket grows a fifth check.
- Integrating the verify pass into `fleet onboarding-check` (0041).
  They share concepts but onboarding-check verifies the FORWARD
  arc; verify covers the REVERSE. Composability is a v2 candidate.
- Emitting a new event type. Verify is pure diagnostic; no telemetry
  writes.

## Engineering notes

- `bin/fleet` — new `uninstall_verify` helper defined ABOVE the
  dispatcher block per LESSONS 2026-06-05. Extend the existing
  `uninstall` dispatcher (or add one) to route `--verify` to the
  helper. Per LESSONS 2026-05-26 (`tail` shadow) `uninstall` does
  not collide with any coreutils binary.
- `bin/fleet` — text renderer uses `printf -- '%s\n'` per LESSONS
  2026-05-28. Any counting via `awk … END { print n+0 }` per
  LESSONS 2026-06-01.
- `tests/uninstall-verify.sh` — new test file. Stubs live under
  `$HOME/.local/bin` per LESSONS 2026-05-26 (PATH reset).
  Backup/restore via `cp` per LESSONS 2026-05-27. Fixtures under
  `tests/fixtures/uninstall-verify/` (one clean slug, one slug with
  each of the four residues, one slug with two simultaneous
  residues).
- `AGENTS.md § Hard NOs` — NO content change (verify is a
  read-only complement to `lib/uninstall.sh`, whose idempotency
  Hard NO stays intact).
- New deps: none. Public API: additive — `fleet uninstall
  --verify` is a new subcommand mode. ZERO new event types, ZERO
  `lib/common.sh` changes, ZERO `prompts/` changes.
- Reinstall required: NO. `lib/` and `prompts/` untouched.

## Implementation log

(Appended by the implementation-dev agent during execution.)
