---
id: 0006
title: Auto-pause ship after N consecutive send-backs
status: groomed
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

(Appended by the implementation-dev agent during execution.)
