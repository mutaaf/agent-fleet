# AGENTS.md — agent-fleet (the kit itself)

This file is the **contract** between the autonomous loop and this repo. The
shared engine in `lib/` reads `agents.config.sh`; the `claude` agent that runs
each ship/groom/review cycle reads **this file**, in a fresh checkout, every
single time.

## What this repo is

The shared shell engine + standard that powers the autonomous coding agents
across the fleet (Almanac, CourtIQ, Digital Craft, fleet-control, agent-fleet
itself). Plumbing lives here in `lib/*.sh` and `prompts/`; semantics live in
each project's `AGENTS.md`.

This is **the kit dogfooding itself**: changes the agents merge to `lib/`
modify the same engine that runs them. The CI gate + branch protection are the
seatbelt. Hand-merge the first few PRs to be safe, then trust the loop.

## Agent parameters

> Read by the shared `agent-fleet` runners at runtime. The one place the generic
> ship/groom/review prompts look for this project's specifics.

- **Gating checks** — EXACTLY these GitHub check names gate a merge. Every other
  check is informational and MUST be ignored when deciding mergeability or what
  to "fix":
  - `shellcheck`
  - `validate`
- **Agent branch prefixes**:
  - `feat/` — feature work (ship agent)
  - `chore/gtm-` — backlog refresh (groom agent)
  - `eng/` — engineering work (eng agent, only if ENG_ENABLED)
- **Local gate command** — what the heal/dev step runs locally before pushing
  (must be green):
  `shellcheck lib/*.sh bin/fleet && bash -n lib/*.sh bin/fleet && node scripts/check-backlog.mjs`
- **Subagents** (in `.claude/agents/`): `implementation-dev`, `gtm-innovation`,
  `review`
- **Backlog areas**: `engine | telemetry | governance | safety | observability | docs`
- **Backlog validator**: `node scripts/check-backlog.mjs` (wired into the
  `validate` gating job — keeps ticket files and the index in sync)

## Hard NOs

The reviewer treats any of these as an automatic `--request-changes`. They are
the contract, not suggestions.

- Never push to `main` directly; never bypass branch protection; never merge
  with a red gating check.
- Never disable, weaken, or skip a passing test or shellcheck rule to make a PR
  green. Fix the script instead.
- Never "fix" a non-gating check — ignore it.
- Never exceed 2 `heal:` attempts on one PR — escalate via a human comment.
- Never break the **public shell API** of `lib/common.sh` (`fleet_load_manifest`,
  `fleet_self_cancel`, `fleet_log_init`, `fleet_checkout`, `fleet_run_claude`)
  without a `BREAKING:` line in the PR body — every installed project depends
  on it.
- Never edit installed copies under `~/.local/share/agent-fleet/` — the source
  of truth is `lib/` in this repo, and `install.sh` is the only thing that
  copies.
- Never modify `lib/install.sh` to skip `launchctl bootstrap`/`bootout` without
  preserving idempotency — every installed project re-runs install.sh.
- Never commit values that look like API keys, tokens, or `gh` PATs.

## How the loop runs on this repo

- `ship` fires hourly at `:37`. It heals the in-flight PR if one exists,
  otherwise picks the top groomed ticket and ships it via `implementation-dev`.
- `groom` fires at `:11` on hours 2/8/14/20. It refreshes the backlog index,
  proposes new tickets via `gtm-innovation`, and never edits `lib/` or
  `prompts/` (those are dev territory).
- `review` polls every 5 min. When an open agent PR exists, it grades the diff
  against this file via the `review` subagent and either signs off with
  `--comment` (auto-merge proceeds on CI-green) or `--request-changes`.

## Local development (humans)

```
# clone, edit lib/*.sh or prompts/*.md
shellcheck lib/*.sh bin/fleet
bash -n lib/*.sh bin/fleet
node scripts/check-backlog.mjs
# open a PR — CI gates, auto-merge fires on green
```

After a merge to `main` that touches `lib/` or `prompts/`, every project that
has the kit installed needs to re-run `install.sh` to refresh the TCC-safe copy
under `~/.local/share/agent-fleet/`. The `keep-running` action in fleet-control
does this; or run it by hand.
