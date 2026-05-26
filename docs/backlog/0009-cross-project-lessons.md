---
id: 0009
title: Cross-project LESSONS aggregation
status: groomed
priority: P2
area: engine
created: 2026-05-26
owner: gtm-innovation
---

## User story

As a fleet operator, I want lessons learned in one project to be visible to
the agents running every other project, so that a mistake the courtiq agent
made last week doesn't get re-made by the digitalcraft agent this week.

## Why now (four lenses)

### Product Owner
Lessons today are per-project. A bug pattern hits Almanac, gets a lesson
appended, and Digital Craft's agents have no idea. Aggregating costs almost
nothing and pays compound dividends.

### Stakeholder
Widens the moat on the loop's collective memory. The kit gets smarter every
time any project ships a postmortem.

### Operator
Doesn't have to copy/paste lessons between projects. One file lives in
`agent-fleet/CROSS_LESSONS.md` and is consulted by every ship prompt.

### Growth
"All my agents share what they've learned" is a memorable property.

## Acceptance criteria

Each box maps 1:1 to a test scenario in `tests/lessons-sync.sh`.

- [ ] Given a fixture with two projects (`almanac` and `courtiq`), each
      with a `docs/LESSONS.md` containing 2 unique paragraphs, running
      `bin/fleet lessons-sync` produces
      `~/.local/share/agent-fleet/CROSS_LESSONS.md` containing both
      `## almanac` and `## courtiq` headings with each project's lessons
      underneath.
- [ ] Given two projects with one byte-identical lesson line, the merged
      output contains that line exactly once (de-duped) under one heading
      with a `(also seen in <other-slug>)` annotation.
- [ ] Running `bin/fleet lessons-sync` twice in a row produces a
      byte-identical output file on the second run (idempotent); the
      file's mtime is NOT updated when content would be identical.
- [ ] `lib/common.sh` exports `FLEET_CROSS_LESSONS` pointing to the synced
      file path so prompts running inside a fresh checkout can resolve it.
      The test sources `common.sh` and asserts the variable is set.
- [ ] `prompts/ship.prompt.md` and `prompts/groom.prompt.md` reference
      `FLEET_CROSS_LESSONS` in PHASE 0 (read-if-exists). Grep both files
      for the exact string `FLEET_CROSS_LESSONS`.
- [ ] `lib/install.sh` invokes `bin/fleet lessons-sync` at the end of its
      run. The test stubs `bin/fleet` and asserts the call is made
      exactly once.
- [ ] When a project has no `docs/LESSONS.md`, sync skips it without error.

## Out of scope

- Conflict resolution between contradictory lessons. The aggregator is
  string-level — duplicates are dropped, opinions stay separate.
- A "promote to CROSS_LESSONS" workflow. v1 syncs everything.
- Lesson tagging / categorization. Plain markdown for now.

## Engineering notes

- `bin/fleet` — add `lessons-sync` subcommand. Discovery uses the same
  two-root pattern as `doctor`: `$FLEET_DISCOVERY_ROOT` (default
  `~/Desktop/projects`) AND `~/.local/share/agent-fleet/projects`.
- The merged file lives at `~/.local/share/agent-fleet/CROSS_LESSONS.md`
  (installed location — survives working-tree deletion).
- `prompts/*.md` — minimal additions, do not bloat the prompts.
- `lib/install.sh` — append the call at the end (after launchctl bootstrap).
- `lib/common.sh` — single `export FLEET_CROSS_LESSONS=...` line.
- Reinstall: all projects (so the export is set and `install.sh` runs sync).
- Public API: additive.

## Implementation log

(Appended by the implementation-dev agent during execution.)
