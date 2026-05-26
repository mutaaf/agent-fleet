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

## 2026-05-26 — `gh pr create` needs `--head <user>:<branch>` from agent runs

`gh pr create` without `--head` sometimes refuses with "you must first push
the current branch to a remote" even after a successful `git push -u origin
HEAD` — the upstream tracking ref doesn't always survive whatever isolates
the agent's checkout. Workaround: pass `--repo mutaaf/agent-fleet
--head mutaaf:<branch>` explicitly. Also include `--base main` to be safe.
