---
id: 0018
title: prompts/PRINCIPLES.md codifies the loop's unwritten behavioral doctrine
status: in-progress
priority: P2
area: governance
created: 2026-05-26
owner: gtm-innovation
---

## User story

As a fleet operator (and as the next agent reading the repo from a fresh
checkout), I want a single short file that names the behavioral
principles every agent in the loop is meant to follow — separately from
the per-phase prompt files and the hard NOs — so that "why did the agent
do that?" has a one-page answer and so that ANY future prompt change is
gradeable against an explicit standard.

## Why now (four lenses)

### Product Owner
Today the loop's behavioral doctrine is implicit: scattered across
`AGENTS.md § Hard NOs`, the four prompts in `prompts/`, the `.claude/
agents/*.md` subagent voice files, and the lessons in `docs/LESSONS.md`.
A new operator (or a new prompt author) has to triangulate. One curated
`prompts/PRINCIPLES.md` — under 100 lines, the operator can read it in
two minutes — gives the loop a constitutional layer that every other
prompt cites. Subtraction: nobody has to re-derive "why does the agent
prefer the smallest viable change" from five sources.

### Stakeholder
Widens the moat on `governance`. Right now the prompts ARE the product
(per ticket 0013's framing) and they're going to drift by design as the
loop refines itself. Without an explicit principles file, drift is
detectable (0005, 0013) but not gradeable — the reviewer can say "the
prompt changed" but not "the prompt changed in a way that violates
principle P-3." With this file, every PR that touches `prompts/` gets
an automatic rubric: does it still honor the principles? That's the
auditability moat.

### User (operator after a confusing PR)
The operator looks at an agent PR and asks "why did it pick THIS ticket
over the higher-priority one?" Today they grep the prompt and the
backlog. After: they open `prompts/PRINCIPLES.md`, see `P-4: ship the
top groomed P0/P1 ticket; demote on absence of clear acceptance
criteria, NEVER on convenience`, and either accept the agent's call or
file a heal: ticket. The principles are the courtroom.

### Growth
"Here are the 8 principles every agent in this kit follows" is the
single most shareable artifact the kit can produce. It's the line a
prospective adopter screenshots. Pairs with the CASE_STUDIES idea (see
README) and with 0013 (prompts CHANGELOG) — together they turn the
prompts subfolder from a black box into a published doctrine.

## Acceptance criteria

Each box maps 1:1 to a test scenario in `tests/principles.sh`.

- [ ] `prompts/PRINCIPLES.md` exists at the kit root and contains at
      least 6 numbered principles (`P-1` through `P-N`), each with a
      one-sentence statement and a one-paragraph "what this looks like
      in practice" expansion. The file is under 150 lines total.
- [ ] Each principle is grep-able by its `P-N` id (the test asserts
      `grep -E '^## P-[0-9]+\b' prompts/PRINCIPLES.md | wc -l` is >= 6).
- [ ] The principles include at minimum (these are non-negotiable;
      additional ones are welcome): (P-1) smallest viable change;
      (P-2) tests-first; (P-3) heal the in-flight PR before shipping
      new work; (P-4) ship top groomed ticket, never the convenient
      one; (P-5) operator confidence over feature richness;
      (P-6) telemetry is the source of truth, transcripts are not.
      The test greps for each principle's keyword phrase.
- [ ] `prompts/ship.prompt.md`, `prompts/groom.prompt.md`, and
      `prompts/eng.prompt.md` each gain a one-line `PHASE 0` directive:
      `Read prompts/PRINCIPLES.md before doing anything else; cite
      the principle id (P-N) you're acting under in any contested
      decision.` The test greps each prompt for that exact directive.
- [ ] `lib/review.sh` inline prompt (the review rubric) gains a
      one-line `principles` check: "Does the diff violate any principle
      in `prompts/PRINCIPLES.md`? If yes, request changes and cite the
      `P-N` id." The test greps `lib/review.sh` for `PRINCIPLES.md`.
- [ ] `AGENTS.md` § Telemetry (or a new `## Doctrine` section, author's
      choice) cross-references `prompts/PRINCIPLES.md` as the canonical
      behavioral layer, distinct from the Hard NOs (which are
      automatic rejections) and the per-phase prompts (which are
      mechanics).
- [ ] The PRINCIPLES.md update is included in `bin/fleet prompts-sha`
      output — i.e. the SHA changes when PRINCIPLES.md changes. The
      test verifies this by snapshotting the SHA, appending a no-op
      comment to PRINCIPLES.md, and asserting the SHA changes. (This
      means PRINCIPLES.md must be in the same shasum input as the
      other prompts files; the existing `find prompts -type f -name
      '*.md'` glob already covers it.)
- [ ] `tests/principles.sh` greps the file shape and the cross-
      references in the four downstream files. No state, no `mktemp`
      needed — pure file content assertions.

## Out of scope

- A formal verification of every PR against every principle. That's
  the reviewer's judgment call; this ticket just gives them a stable
  vocabulary.
- Per-project principles. PRINCIPLES.md is uniform across the fleet —
  that's doctrine (and matches how prompts are shared, per D7).
- Principle-versioning (a principle that gets deprecated). v1 is
  append-and-edit-in-place; if a principle gets retired, the
  CHANGELOG entry per 0013 captures the why.
- Translating the principles into machine-checkable lint rules.
  Aspirational, separate ticket if ever.

## Engineering notes

- `prompts/PRINCIPLES.md` — operator-authored prose; the implementing
  agent drafts the initial 6+ principles from existing material in
  `AGENTS.md § Hard NOs`, `DOCTRINE.md`, and `docs/LESSONS.md`. The
  goal is summary, not invention — every principle should already be
  visible in the codebase's behavior.
- The four prompts files each get a single line at the top of PHASE 0
  (or equivalent first phase). Do NOT bloat the prompts beyond that
  one line — the principles file is the load-bearing reference.
- `lib/review.sh` inline rubric: ONE additional grading bullet, near
  the existing AGENTS.md and Hard NOs bullets.
- `tests/principles.sh` — pure-grep test, no mktemp fixtures needed.
  Each acceptance box maps to a grep + count assertion.
- Public API: no changes. This ticket is documentation + prompt
  edits + one inline review-rubric line.
- Reinstall: required (touches `prompts/` and `lib/review.sh`). The
  `Reinstall: all projects` line goes in the PR body per LESSONS.
- Cross-ticket: pairs naturally with 0013 (prompts CHANGELOG). If
  0013 ships first, the initial PRINCIPLES.md introduction gets its
  own CHANGELOG entry. If this ships first, 0013 inherits a richer
  baseline to track changes against.

## Implementation log

- 2026-05-27 — implementation-dev started. Branched `feat/0018-prompts-principles`.
  Plan: tests-first (pure-grep `tests/principles.sh`, one assertion per AC box),
  then author `prompts/PRINCIPLES.md` with P-1..P-6 (plus extras as warranted),
  add the PHASE 0 directive to the three prompt files, add the rubric bullet
  to `lib/review.sh`, add a `## Doctrine` cross-reference to `AGENTS.md`, and
  log the entry in `prompts/CHANGELOG.md`. PR body must carry
  `Reinstall: all projects`.
