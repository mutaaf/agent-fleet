---
id: 0013
title: prompts/CHANGELOG.md + fleet prompts-diff explain drift
status: proposed
priority: P2
area: governance
created: 2026-05-26
owner: gtm-innovation
---

## User story

As a fleet operator who just got a `prompts_drift` warning (from 0005), I
want to see WHAT changed in the prompts since my pin — not just THAT
something changed — so that I can decide intelligently whether to bump the
pin or revert.

## Why now (four lenses)

### Product Owner
Ticket 0005 ships drift detection but stops at "the SHA differs." The
operator still has to manually diff `~/.local/share/agent-fleet/prompts/`
against the kit repo's `prompts/`, and even then a diff doesn't tell them
the *intent* of a change. A small operator-curated CHANGELOG plus a
`fleet prompts-diff` command closes the loop: the operator gets both the
mechanical diff AND the why-it-changed in one place.

### Stakeholder
Widens the moat on `governance`. The prompts ARE the product — they
encode every behavioral choice the loop makes. A changelog turns "the
prompts shift under your feet" (a risk) into "the prompts have a release
history" (a feature). It's the difference between a black-box LLM
wrapper and an auditable autonomous-coding contract.

### User (operator after a reinstall)
`fleet doctor` says `prompts_pinned FAIL`. The operator runs
`fleet prompts-diff` and sees: "ship.prompt.md: PHASE 1 healing now
honors `HEAL_MAX=2` from manifest (CHANGELOG entry 2026-05-30: bounded
heal). PR diff: <patch>." They bump the pin in 10 seconds.

### Growth
This is what makes the kit feel like a serious shared standard rather than
a personal experiment. A CHANGELOG signals "this is maintained, the
behavioral choices are documented, you can pick a known-good revision."
That's a property worth showing to anyone evaluating the kit.

## Acceptance criteria

Each box maps 1:1 to a test scenario in `tests/prompts-changelog.sh`.

- [ ] `prompts/CHANGELOG.md` exists at the kit root with an initial entry
      headed `## <today's-date> — initial entry` capturing the SHA the
      file is born at and a one-line "no behavioral changes since
      bootstrap" note.
- [ ] `bin/fleet prompts-diff` compares the installed prompts at
      `~/.local/share/agent-fleet/prompts/` against the kit's current
      `prompts/` (resolved via `KIT_ROOT`), prints a unified diff per
      file, and exits 1 if there's any difference (0 otherwise).
- [ ] `bin/fleet prompts-diff --since <SHA>` prints the diff against a
      historical pin (passed by the operator from their old
      `agents.config.sh`). The implementation walks `git log -- prompts/`
      to find the commit whose tree matches that SHA, then `git diff
      <commit>..HEAD -- prompts/`.
- [ ] `bin/fleet prompts-diff --changelog` prints all CHANGELOG entries
      since the installed-prompts SHA — i.e. only the entries newer than
      the operator's current pin. Format: copy markdown verbatim from
      the CHANGELOG between matching headings.
- [ ] `scripts/check-backlog.mjs` is unchanged; a NEW validator
      `scripts/check-prompts-changelog.mjs` is added to the `validate` CI
      gating job: it fails CI when a PR modifies any file under
      `prompts/` without also adding a new entry to
      `prompts/CHANGELOG.md`. (Detects the prompt-changed-but-changelog-
      didn't case.)
- [ ] `tests/prompts-changelog.sh` exercises: clean state (no diff, exit 0),
      drifted state (diff present, exit 1), `--changelog` filtering against
      a synthetic CHANGELOG with three entries.
- [ ] `AGENTS.md` gets a `## Prompts changelog` section pointing operators
      at `CHANGELOG.md` + the `prompts-diff` subcommand.

## Out of scope

- Auto-generated changelog from commit messages. v1 is operator-curated
  prose — that's the whole point.
- A web view. Markdown is enough.
- Per-project prompt customization. The kit's prompts are uniform across
  the fleet — that's doctrine.

## Engineering notes

- `prompts/CHANGELOG.md` — operator-curated, append-only, headings of the
  form `## YYYY-MM-DD — <one-line title>`.
- `bin/fleet` — `prompts-diff()` subcommand using `diff -u`. Reads
  `~/.local/share/agent-fleet/prompts/` vs `$KIT_ROOT/prompts/`.
- `scripts/check-prompts-changelog.mjs` — new validator. In CI it compares
  the PR's changed-file list (passed via `git diff --name-only main...HEAD`
  or `GITHUB_BASE_REF`/`GITHUB_HEAD_REF`) to detect a prompts-touched-but-
  CHANGELOG-untouched mismatch. Wire into the `validate` workflow job in
  the same step as `check-backlog.mjs`.
- `tests/prompts-changelog.sh` — `mktemp -d` fake kit root, write a
  synthetic CHANGELOG, invoke `bin/fleet prompts-diff` with patched env.
- Public API: additive (`bin/fleet prompts-diff`). No `lib/` changes.
- Reinstall: required (the new CHANGELOG must be copied to
  `~/.local/share/agent-fleet/` by `install.sh`).
- Status `proposed`, not `groomed`: the new validator script's interaction
  with the existing `validate` CI job needs the ship agent to confirm the
  GitHub Actions workflow shape before committing to the exact wiring.

## Implementation log

(Appended by the implementation-dev agent during execution.)
