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

- [ ] `lib/ship.sh` checks before PHASE 2 (shipping a new ticket): query the
      last 5 merged-or-closed PRs from agent branch prefixes that received
      a `REQUEST_CHANGES` review and were never resolved before close. If
      3 or more of those happened in the last 24h, abort PHASE 2.
- [ ] On abort, emit `fleet_emit_event ship_paused reason=sendback_streak
      count=<n>` and post (or update if it exists) a GitHub Issue titled
      `[FLEET] ship paused after N send-backs` containing the PR numbers.
- [ ] `launchctl disable gui/$UID/$NAMESPACE.agent-ship` is invoked so the
      pause persists across runner invocations. Resume is the operator's
      explicit `launchctl enable` or the fleet-control "Resume" action.
- [ ] PHASE 1 (heal the in-flight PR) is NOT disabled by the pause — only
      shipping new tickets is. An in-flight PR can still heal.
- [ ] `tests/sendback-pause.sh` stubs `gh` with canned responses and asserts
      the pause path triggers when 3+ recent send-backs are present and
      does NOT trigger when fewer.

## Out of scope

- Pausing the groom phase (groom doesn't have send-backs in the same way).
- Auto-resume after some time window. Manual resume only.

## Engineering notes

- `lib/ship.sh` — add a `_check_sendback_streak` function before PHASE 2
  invokes the dev subagent.
- The `gh` query: `gh pr list --state closed --search "review:changes-requested" --json number,closedAt,headRefName` (filter to agent prefixes from AGENTS.md is HARD here since ship.sh runs before the claude agent reads AGENTS.md; for v1, hardcode the prefix list `feat/ eng/ chore/gtm-` — these are fleet-standard).
- Issue title is idempotent: search for an open issue with the exact title
  before creating a new one.
- Blocked-by: 0002 (events channel).
- Public API: additive.

## Implementation log

(Appended by the implementation-dev agent during execution.)
