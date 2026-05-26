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

- [ ] `bin/fleet lessons-sync` discovers every project's `docs/LESSONS.md`,
      concatenates them into `agent-fleet/CROSS_LESSONS.md` with one
      `## <slug>` heading per project, deduped by line.
- [ ] `prompts/ship.prompt.md` and `prompts/groom.prompt.md` get a one-line
      addition in PHASE 0: "also read `<KIT>/CROSS_LESSONS.md` if it exists;
      it contains lessons from other projects in the fleet."
- [ ] `lib/common.sh` exports `FLEET_CROSS_LESSONS` pointing to the synced
      file under `~/.local/share/agent-fleet/CROSS_LESSONS.md` so the prompt
      can resolve it from inside a checkout.
- [ ] `bin/fleet lessons-sync` runs idempotently and writes nothing if the
      output would be byte-identical to the existing file.
- [ ] `tests/lessons-sync.sh` creates two fixture project trees with sample
      LESSONS.md files and asserts the merged output contains both sources
      under the right headings.
- [ ] `lib/install.sh` calls `bin/fleet lessons-sync` at the end of its run,
      so reinstalling refreshes the cross-lessons file.

## Out of scope

- Conflict resolution between contradictory lessons. The aggregator is
  string-level — duplicates are dropped, opinions stay separate.
- A "promote to CROSS_LESSONS" workflow. v1 syncs everything.

## Engineering notes

- `bin/fleet` — add `lessons-sync` subcommand.
- `prompts/*.md` — minimal additions, do not bloat the prompt.
- `lib/install.sh` — append the call at the end (after launchctl bootstrap).
- Reinstall: all projects (so the export is set).
- Public API: additive.

## Implementation log

(Appended by the implementation-dev agent during execution.)
