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

## Doctrine

[`prompts/PRINCIPLES.md`](prompts/PRINCIPLES.md) is the constitutional layer.
It names the behavioral principles every agent in the loop follows (`P-1`
smallest viable change; `P-2` tests-first; `P-3` heal in-flight before new
work; `P-4` ship the top groomed ticket; `P-5` operator confidence over
feature richness; `P-6` telemetry is the source of truth; plus extras).
The Hard NOs above are automatic rejections; the per-phase prompts in
`prompts/*.prompt.md` are mechanics; PRINCIPLES.md is the layer reviewers
and authors grade contested decisions against. Agents cite the `P-N` id
they're acting under whenever a decision is non-obvious.

## Telemetry

Every runner appends typed events to a single JSONL file per slug so that
fleet-control (and any future consumer) reads one source of truth instead of
scraping `claude` transcripts. The contract is small enough to fit on a
postcard.

- **File**: `$CACHE_DIR/events.jsonl` (i.e. `~/.cache/<slug>-agent/events.jsonl`)
- **Format**: one JSON object per line, append-only, never truncated. Rotates
  at `FLEET_EVENTS_MAX_BYTES` (default 1 MiB) into
  `events.jsonl.archive/<UTC-stamp>.jsonl`; the contract above applies to all
  files in the channel including archives.
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
  - `events_rotated {archived, bytes}` — emitted by `fleet_rotate_events`
    (ticket 0016) when `events.jsonl` reaches `FLEET_EVENTS_MAX_BYTES`
    and is moved into `events.jsonl.archive/<UTC-stamp>.jsonl`. `archived`
    is the absolute path of the rotated-out file; `bytes` is its size in
    bytes at the moment of rotation. The marker is written as the FIRST
    line of the new (empty) events.jsonl, so consumers tailing the
    channel see an explicit rotation boundary without having to compare
    inode numbers.
  - `infra_flake_rerun {pattern, run_id, pr}` — emitted by the ship
    runner's PHASE 1 RED branch (driven from `prompts/ship.prompt.md`)
    when `fleet_match_infra_flake` (ticket 0020) classifies the failed
    job log as one of the four catalog patterns: `actions_silent`,
    `supabase_port_bind`, `account_suspended`, `gh_graphql_502`. On a
    match the runner invokes `gh run rerun <run_id> --failed` exactly
    once, emits this event, prints `INFRA_FLAKE <token> — rerunning
    run <id>`, and exits cleanly — no `heal:` commit is created and
    the 2-attempt heal-cap is NOT advanced. Dedupe: a second match
    on the same `pattern`+`run_id` within 2h (scanned from this
    channel) falls through to the normal heal path so a genuinely-
    broken infra cannot trap the runner in a rerun loop. The catalog
    lives in `lib/heal-catalog.sh`; adding a new pattern is one line
    + a fixture log in `tests/heal-infra-flake.sh` + an inline LESSON
    reference (date + repo).
  - `lesson_draft_emitted {pr, headline}` — emitted by
    `_review_emit_lesson_draft` (ticket 0022) from `lib/common.sh` whenever
    the reviewer posts a `--request-changes` verdict. The helper prepends
    (or dedupe-replaces) a date-stamped, HTML-comment-marked DRAFT block
    in `docs/LESSONS.md` so the operator can promote it later. `pr` is
    the PR number; `headline` is the first 80 chars of the review body's
    first line. Dedupe key is the PR number — a second send-back on the
    same PR updates the existing block in place and emits a second event
    (the event log preserves the streak). Sign-off (`--comment`) reviews
    do NOT emit this event. Consumer guidance: counts here vs.
    `pr_opened` give a "draft promotion debt" metric — every emitted
    event corresponds to one draft block waiting for an operator pass.
  - `prompts_pin_changed {old, new}` — emitted by `lib/install.sh` (ticket
    0024) once per install when the `PROMPTS_SHA=` value the project would
    end up running differs from the previously-installed pin. `old` is
    the prior copy's SHA (empty on a first install — falls back to the
    SOURCE manifest's value as the comparison anchor); `new` is the SHA
    computed from the kit's current `prompts/`. Carries `phase=install`
    so consumers can distinguish bootstrap pin transitions from runtime
    `prompts_drift` warnings. Consumed by `fleet prompts-score` to
    assemble the per-revision timeline: every transition in this channel
    becomes a row boundary in the score table. Idempotent: a re-install
    with no kit/source edits finds `old == new` and stays silent.
  - `lesson_promoted {source, text_sha, scope, dup_under?}` — emitted by
    `bin/fleet lessons-promote` (ticket 0028) on every successful,
    non-idempotent promotion of a single lesson from a project's
    `docs/LESSONS.md` into the cross-project feed. `source` is the
    slug whose LESSONS.md was the source; `text_sha` is the 8-char
    SHA of the normalized paragraph body; `scope` is `all` (the
    default — appends to the shared `CROSS_LESSONS.md`) or a consumer
    slug (writes `projects/<slug>/CROSS_LESSONS.md.override` instead).
    `dup_under` is present ONLY when the cross-section dedup branch
    fires: the paragraph body already exists in the target under a
    DIFFERENT slug section, so the command writes a
    `> Already seen under ## <other-slug>` reference line under the
    source slug's section and carries the other slug in `dup_under`.
    Idempotent re-runs (body already present under the SAME slug
    section) are silent — no event emitted, no file change. Carries
    `phase=promote` and lives in the source project's `events.jsonl`
    (per P-6: project is the unit of telemetry, not the kit).
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
  - `quiet_hours_skip {phase, window, now_local}` — emitted by
    `lib/ship.sh`, `lib/groom.sh`, and `lib/eng.sh` (ticket 0033) on
    every fire that lands INSIDE the operator-declared `QUIET_HOURS`
    window in the project's `agents.config.sh`. `phase` is the runner
    that suppressed (`ship` | `groom` | `eng`); `window` is the raw
    manifest value (`HH:MM-HH:MM` local time); `now_local` is the
    runner's wall-clock at decision time as ISO8601 with offset
    (e.g. `2026-06-06T02:37:09-0700`). The runner emits exactly one
    event per process (guarded by `FLEET_QUIET_HOURS_EMITTED`, same
    shape as `FLEET_PROMPTS_DRIFT_EMITTED` from ticket 0005) and
    `exit 0`s immediately after — no claude, no gh, no git, no
    `heal:` counter advance. `review` is exempt by design (it is a
    poller, not a worker, and continuing to grade in-flight PRs
    overnight is a feature, not a bug) so this event NEVER carries
    `phase=review`. `FLEET_KICKSTART=1` and unset `FLEET_PHASE`
    paths are also exempt — an explicit operator-initiated
    `bin/fleet kickstart` bypasses the schedule by design. Invalid
    manifest values (out-of-range hours, missing colons, partial
    windows) are operator config errors, not telemetry truth, so
    they print a one-time stderr warning AND DO NOT emit this
    event. Mirrors the shape of `lesson_promoted` (0028) and
    `ship_resumed` (0030): one operator-declared policy, one typed
    event, no transcript scraping required to reconstruct why a
    run no-op'd at 2am.
  - `prompts_reverted {from, to, pr, reason}` — emitted by
    `bin/fleet prompts-revert` (ticket 0035) once per successful
    revert of the kit's `prompts/` tree to a known-good SHA. `from`
    is the prompts SHA on disk BEFORE the checkout (per `fleet
    prompts-sha`'s formula); `to` is the target full 40-char SHA
    the operator pinned back to (resolved from a full SHA, ≥7-char
    short SHA, or `YYYY-MM-DD` CHANGELOG date stamp); `pr` is the
    revert PR's number; `reason` is the mandatory `--reason
    "<one-line>"` value, recorded verbatim. Carries `phase=revert`
    and lives in the AGENT-FLEET kit-as-project `events.jsonl`
    (per the `lesson_promoted` pattern from ticket 0028 — the kit
    IS a project for telemetry purposes). Idempotent no-op path
    (target's prompts/ tree byte-identical to current) emits NO
    event; refusal paths (dirty tree, unknown SHA, missing
    `--reason`, non-ASCII `--reason`) emit NO event — only
    successful revert PRs do. Mirrors the shape of
    `rollback_opened` (0017) and `ship_resumed` (0030): one
    operator-initiated action, one typed event, no transcript
    scraping required to reconstruct the recovery. Consumed by
    `fleet prompts-score` as a revision boundary alongside
    `prompts_pin_changed` (0024).
  - `ship_resumed {source, paused_for, reason, forced}` — emitted by
    `bin/fleet resume <slug>` (ticket 0030) on every successful resume
    of a previously `ship_paused` project. `source` is the slug whose
    `agent-ship` launchd label was re-enabled; `paused_for` is the
    human-formatted age ("23h", "3d", `unknown` when no `ship_paused`
    event exists in the channel) of the most recent `ship_paused`
    event the resume cleared; `reason` is the `--reason` value on the
    `--force` path or the literal string `streak cleared` on the
    default (streak-check-passed) path; `forced` is `0` on the
    default path and `1` on `--force`. Carries `phase=resume` and
    lives in the source project's `events.jsonl` (per P-6: project is
    the unit of telemetry, not the kit). Idempotent no-op path
    (label already enabled) and refusal path (streak still active,
    no `--force`) emit NO event — only successful resumes do. Mirrors
    the shape of `rollback_opened` (0017) and `lesson_promoted`
    (0028): one operator-initiated action, one typed event, no
    transcript scraping required to reconstruct the recovery.
  - `lessons_pruned {archived_count, since_date, pr, cause}` — emitted
    by `bin/fleet lessons-prune --commit` (ticket 0039) once per
    successful archival run that moves one or more
    `<!-- EXPIRES: YYYY-MM-DD -->`-marked paragraphs out of
    `docs/LESSONS.md` and into `docs/LESSONS-ARCHIVE.md`. `archived_count`
    is the number of paragraphs moved; `since_date` is the operator's
    effective "today" (the `FLEET_NOW_OVERRIDE` test seam or
    `date -u '+%Y-%m-%d'`); `pr` is the new chore PR's number; `cause`
    is the mandatory `--cause "<one-line>"` value, recorded verbatim
    (ASCII for v1, per the LESSONS 2026-06-03 sign-extension guard).
    Carries `phase=prune` and lives in the AGENT-FLEET kit-as-project
    `events.jsonl` (per the `lesson_promoted` / `prompts_reverted`
    pattern — the kit IS a project for telemetry purposes). Dry-run
    paths (`--dry-run`, `--help`) emit NO event; refusal paths
    (missing `--cause`, non-ASCII `--cause`) emit NO event — only
    successful archival PRs do. Mirrors the shape of `prompts_reverted`
    (0035) and `lesson_promoted` (0028): one operator-initiated
    curation action, one typed event, no transcript scraping required
    to reconstruct why `docs/LESSONS.md` shrank in a given week.
    Consumed by `fleet provenance` and any future
    "LESSONS read-cost over time" rollup.

**Demo path (ticket 0023).** `bin/fleet kickstart --demo` walks a
credential-less synthetic ship cycle and emits the four core event
types (`run_started`, `pr_opened`, `lesson_draft_emitted`,
`run_completed`) with `phase=demo` and `slug=demo-XXXX`. No new event
type is introduced — the demo is a CONSUMER of the existing channel
contract, not a new channel. Consumers can filter `phase=demo` to
exclude synthetic traffic from real-project rollups; `fleet digest`
and `fleet weekly` already do this implicitly by discovering projects
via `agents.config.sh` rather than scanning `$HOME/.cache` blindly.

Add new event types in the same file; consumers MUST tolerate unknown types
gracefully. Do not rename or repurpose an existing type — the contract is the
moat.

## Lessons

`docs/LESSONS.md` is the loop's operational memory — every ship and
groom run reads it at PHASE 0. The file is **append-only by contract**:
never reorder, never delete a paragraph. A paragraph that documents a
trap the kit has since defused at the helper level can still carry
read-cost on every run forever, so paragraphs MAY carry an optional
`<!-- EXPIRES: YYYY-MM-DD -->` HTML comment on the line immediately
following the paragraph's `## YYYY-MM-DD — <title>` heading.

The marker means: "on or after this date, this paragraph is a candidate
for archival via `bin/fleet lessons-prune --commit`." It is a candidate
marker, **not** an automatic removal — PHASE 0 still reads the
paragraph until the operator runs `lessons-prune --commit` and the
resulting `chore/lessons-prune-<date>` PR merges. The command moves
expired paragraphs byte-for-byte into `docs/LESSONS-ARCHIVE.md` (a
separate file that PHASE 0 readers DO NOT read), preserves history
through git, and emits one `lessons_pruned` event per run (see
§ Telemetry). A paragraph WITHOUT an EXPIRES marker is silent — never
pruned regardless of age.

```
fleet lessons-prune --dry-run               # list expired paragraphs
fleet lessons-prune --commit --cause "<text>"  # open chore PR moving them
fleet lessons-prune --help                  # USAGE
```

Operator-invoked only. No launchd schedule, no auto-prune during
`fleet groom` — the EXPIRES marker forces a deliberate human pass
("this trap is defused, here is the helper that defuses it"), and
the archive PR is the auditable trail. Restoration is standard git
semantics: `git revert <prune-pr>`.

## Prompts changelog

Operator-curated record of behavioral changes to `prompts/` lives in
[`prompts/CHANGELOG.md`](prompts/CHANGELOG.md). Every PR that touches
any file under `prompts/` MUST also add a new
`## YYYY-MM-DD — <one-line title>` entry — the `validate` CI gate runs
`node scripts/check-prompts-changelog.mjs` and fails when the two move
out of step. The CHANGELOG is part of the prompts SHA input (the
`find prompts -type f -name '*.md'` glob covers it), so any entry here
surfaces as drift in `fleet doctor`'s `prompts_pinned` check — that
is intentional. When the operator sees `prompts_drift`, the recovery
path is one command:

```
bin/fleet prompts-diff             # unified diff installed vs current
bin/fleet prompts-diff --changelog # entries newer than the pin
bin/fleet prompts-diff --since SHA # diff against a specific old pin
```

`prompts-diff` exits 1 on any difference (so `&&` composition works
in shell scripts) and 0 when the installed tree matches the kit.

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
