# AGENTS.md — demo fixture (read-only, do not edit)

This is the synthetic AGENTS.md that `bin/fleet kickstart --demo` drops
into the fixture project. Its purpose is to model the real shape an
operator would write — one § Agent parameters block, one Hard NOs list,
one Telemetry pointer — without making any commitments about a real
repository (there isn't one — the demo never pushes anywhere).

## Agent parameters

- **Gating checks** — these GitHub check names would gate a merge if
  this were a real project:
  - `shellcheck`
  - `validate`
- **Agent branch prefixes**:
  - `feat/` — feature work (ship agent)
  - `chore/gtm-` — backlog refresh (groom agent)
- **Local gate command**: `bash -n agents.config.sh`
- **Backlog areas**: `docs`

## Hard NOs

- Never push to `main` directly.
- Never bypass branch protection.
- Never disable a passing test.

## Telemetry

The demo writes `events.jsonl` to `$CACHE_DIR/events.jsonl` under the
re-rooted `$HOME` per AGENTS.md (real project) § Telemetry. Every event
carries `ts`, `slug`, `phase=demo`, `type`.
