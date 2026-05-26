---
id: 0006
title: Auto-pause ship after N consecutive send-backs
status: in-progress
priority: P1
area: safety
created: 2026-05-26
owner: gtm-innovation
---

## User story

As a fleet operator, I want the ship phase to pause itself when the last N
ship PRs all received `--request-changes`, so that a broken cycle stops
burning tokens against a problem it can't fix without me.

## Why now (four lenses)

### Product Owner
A failure mode the loop can detect with two `gh` calls — and the cost of
ignoring it is exactly the worst case (unbounded retries). Pause-and-alert
beats "we noticed at the end of the day."

### Stakeholder
Widens the moat on `safety`. The loop is now self-aware about being stuck.
Pairs with budget caps (0004) and fleet-control alerts (FC daemon).

### Operator
A pause is visible in the portal and the daily total stops creeping. The
meta-issue carries the context the operator needs to unblock.

### Growth
"It self-pauses when it can't make progress" is a property worth
demonstrating.

## Acceptance criteria

Each box maps 1:1 to a test scenario in `tests/sendback-pause.sh`.

- [ ] Given `gh pr list` returns 3+ closed agent PRs in the last 24h whose
      last review was `CHANGES_REQUESTED` and that closed without becoming
      `MERGED`, `lib/ship.sh` exits 0 before PHASE 2 (no new ticket is
      picked) and prints `ship paused: sendback streak N` to the log.
- [ ] Same precondition: `fleet_emit_event ship_paused reason=sendback_streak
      count=<n> prs=<comma-list>` lands in `$CACHE_DIR/events.jsonl`.
- [ ] Same precondition: an open GitHub Issue with the exact title
      `[FLEET] ship paused after N send-backs` exists; if one already exists
      it is updated (commented), not duplicated.
- [ ] Same precondition: `launchctl disable gui/$UID/$NAMESPACE.agent-ship`
      was invoked so the pause persists across launchd fires. The test
      stubs `launchctl` and asserts the exact call.
- [ ] Given the same streak BUT an open in-flight `feat/` PR exists, PHASE 1
      (heal) still runs to completion; only PHASE 2 (new ticket) is blocked.
- [ ] Given fewer than 3 send-backs in the last 24h, ship proceeds normally
      and neither the event nor the issue is emitted.
- [ ] Given a stale streak (3+ send-backs but >24h ago), ship proceeds
      normally — the window is sliding, not cumulative.

## Out of scope

- Pausing the groom phase (groom doesn't have send-backs in the same way).
- Auto-resume after some time window. Manual resume only.
- Re-enabling via the kit. Resume is the operator's explicit
  `launchctl enable gui/$UID/$NAMESPACE.agent-ship` or fleet-control's
  "Resume" action.

## Engineering notes

- `lib/ship.sh` — add a `_check_sendback_streak` function before PHASE 2
  invokes the dev subagent. PHASE 1 (heal) runs unconditionally.
- The `gh` query: `gh pr list --state closed --search "review:changes-requested" --json number,closedAt,headRefName,reviews,state` filtered to fleet-standard prefixes `feat/ eng/ chore/gtm-` (hardcoded — ship.sh runs before the agent reads AGENTS.md).
- Issue idempotency: `gh issue list --search "[FLEET] ship paused" --state open --json number,title` before `gh issue create`.
- `tests/sendback-pause.sh` — stub `gh` and `launchctl` on PATH via a tmpdir; assert exit code, event contents, and stubbed calls.
- Public API: additive.
- Reinstall: all projects.

## Implementation log

- 2026-05-26 — picked up by implementation-dev. Branch
  `feat/0006-auto-pause-on-sendbacks`. Plan: add a
  `fleet_check_sendback_streak` gate to `lib/common.sh` (peer of
  `fleet_check_budget`) that queries the last 5 closed agent-branch PRs via
  `gh pr list --state closed --search "review:changes-requested"
  --json number,closedAt,headRefName,reviews`, counts those that had
  `REQUEST_CHANGES` in the last 24h with no subsequent resolving review, and
  if `>= 3` (a) emits `ship_paused reason=sendback_streak count=<n>` via
  `fleet_emit_event`, (b) creates or updates a `[FLEET] ship paused after N
  send-backs` GitHub Issue with the PR numbers in the body, (c) runs
  `launchctl disable gui/$UID/$NAMESPACE.agent-ship` so the pause persists.
  `lib/ship.sh` calls this gate ONLY in PHASE 2 — PHASE 1 (heal) is
  implemented inside the ship.prompt.md by the claude agent itself, so the
  shell-level gate sits between `fleet_checkout` and `fleet_run_claude`,
  guarded by an env var the prompt can clear when it's healing. Simplest
  contract: the gate runs unconditionally before `fleet_run_claude ship`,
  and the ship prompt is told (via an exported `FLEET_SHIP_PAUSED=1` env
  var on trip) that PHASE 2 is forbidden this run. PHASE 1 reads the same
  channel and proceeds. Test: `tests/sendback-pause.sh` stubs `gh`,
  `launchctl`, and `date` to assert both the trip path (3+ recent
  send-backs → exit 0, event emitted, issue posted, launchctl disable run)
  and the no-trip path (2 recent + 1 old → no pause).
