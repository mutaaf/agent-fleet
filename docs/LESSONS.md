# LESSONS

Operational memory for the autonomous loop. Append, never reorder. Each entry
is one paragraph: symptom → cause → fix. Lessons here are read at the start of
every ship/groom run.

## 2026-05-25 — bootstrap

The kit is dogfooding itself for the first time. The seatbelts: CI gates on
`shellcheck` + `validate`, branch protection requires both contexts, and the
review subagent enforces AGENTS.md § Hard NOs. Lessons below are the agents'
collective memory across all runs on this repo.

## 2026-05-25 — `lib/` changes need a fleet-wide reinstall

When a PR modifies anything under `lib/` or `prompts/`, the change only lands
in this repo on merge — every installed project still runs the old engine from
`~/.local/share/agent-fleet/`. The post-merge action is to re-run
`bash lib/install.sh /path/to/project` for every project in the fleet. Until a
ticket automates this, ship PRs that touch `lib/` should add a one-liner to
the PR body: `Reinstall: all projects`.
