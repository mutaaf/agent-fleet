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
  - `revert/` — operator-initiated rollback (emitted by `fleet rollback`)
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
  Enforced locally by the pre-push hook installed by `fleet_install_prepush_hook` — see ticket 0008.

## How the loop runs on this repo

- `ship` fires hourly at `:37`. It heals the in-flight PR if one exists,
  otherwise picks the top groomed ticket and ships it via `implementation-dev`.
- `groom` fires at `:11` on hours 2/8/14/20. It refreshes the backlog index,
  proposes new tickets via `gtm-innovation`, and never edits `lib/` or
  `prompts/` (those are dev territory).
- `review` polls every 5 min. When an open agent PR exists, it grades the diff
  against this file via the `review` subagent and either signs off with
  `--comment` (auto-merge proceeds on CI-green) or `--request-changes`.

## Telemetry

Every runner appends typed events to a single JSONL file per slug so that
fleet-control (and any future consumer) reads one source of truth instead of
scraping `claude` transcripts. The contract is small enough to fit on a
postcard.

- **File**: `$CACHE_DIR/events.jsonl` (i.e. `~/.cache/<slug>-agent/events.jsonl`)
- **Format**: one JSON object per line, append-only, never truncated. A future
  ticket will cover GC if size becomes an issue — for now the channel grows.
- **Writer**: `fleet_emit_event <type> [k=v ...]` in `lib/common.sh`. Shell-only,
  no `jq` dependency for writing (JSON is hand-composed via `_json_escape`).
  Readers may use `jq` freely.
- **Schema** — every event carries these four keys:
  - `ts` — ISO8601 UTC, e.g. `2026-05-26T14:37:09Z`
  - `slug` — the project slug from `agents.config.sh`
  - `phase` — `ship` | `groom` | `review` | `eng` (whatever
    `fleet_log_init` was called with)
  - `type` — the event type (see list below)
  Any extra `k=v` arguments are added as JSON keys with string values.
- **Event types** emitted by the kit today:
  - `run_started {pid}` — fired right after `fleet_log_init`
  - `run_completed {exit, duration_ms}` — fired right before final `exit`
  - `gate_failed {check}` — best-effort, from the heal path
  - `pr_opened {number, branch}` — fired by the dev agent after `gh pr create`
  - `self_cancel_trip {}` — fired when `SELF_CANCEL` has expired
  - `lock_blocked {phase, holder_pid}` — fired when `fleet_acquire_lock` loses
  - `budget_block {reason, spent, cap}` — emitted by `fleet_check_budget` when
    today's UTC spend for this slug has reached the manifest's `MAX_DAILY_USD`
    cap; all runners soft-abort (exit 0) immediately after.
  - `prompts_drift {pinned, actual}` — emitted by `fleet_check_prompts_sha`
    (ticket 0005) when the manifest's optional `PROMPTS_SHA` pin doesn't
    match the kit's current `prompts/` SHA. Fires AT MOST ONCE per process
    (guarded by `FLEET_PROMPTS_DRIFT_EMITTED`). The runner logs a warning
    and continues — drift is a signal, not an abort. Operator response: run
    `bin/fleet prompts-sha` to see the new value, re-run `install.sh` to
    bump the pin, or revert the prompt change. Unset `PROMPTS_SHA` = no
    event (current behavior preserved).
  - `ship_paused {reason, count, prs}` — emitted by
    `fleet_check_sendback_streak` (ticket 0006) when 3+ agent-branch PRs
    in the last 24h received `REQUEST_CHANGES` and closed without
    resolution. PHASE 2 (shipping a new ticket) is then forbidden for
    this run; PHASE 1 (heal) still runs. The function also opens or
    comments on a `[FLEET] ship paused after N send-backs` GitHub Issue
    and invokes `launchctl disable gui/$UID/$NAMESPACE.agent-ship` so the
    pause persists across runner invocations. Resume = explicit
    `launchctl enable gui/$UID/$NAMESPACE.agent-ship` (or fleet-control's
    "Resume" action).
  - `rollback_opened {pr, reverts, merge_commit}` — emitted by
    `bin/fleet rollback` after a successful `gh pr create` of the
    revert PR. `pr` is the new revert PR's number; `reverts` is the
    original (agent-merged) PR's number; `merge_commit` is the SHA of
    the squash/merge commit being reverted. Ticket 0017. Consumers can
    treat this like any other PR-related event (it carries `slug` +
    `phase=rollback` like the rest).
  - `trainee_pr_opened {number, remaining}` — emitted by the dev agent
    (driven from `prompts/ship.prompt.md`) immediately after `gh pr
    create` when `FLEET_TRAINEE_REMAINING > 0`, i.e. the project's
    `TRAINEE_PR_COUNT` cap has not yet graduated. The dev agent ALSO
    skips `gh pr merge --auto` in this state and posts a
    `[FLEET trainee mode K/N] Please review and merge manually.`
    comment on the PR. `number` is the PR number; `remaining` is the
    `FLEET_TRAINEE_REMAINING` value at emission time. Ticket 0014.
    Operator graduates the project by merging PRs until the cap is met
    — there is no manual reset.

Add new event types in the same file; consumers MUST tolerate unknown types
gracefully. Do not rename or repurpose an existing type — the contract is the
moat.

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
