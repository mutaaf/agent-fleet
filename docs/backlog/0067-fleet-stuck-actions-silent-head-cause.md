---
id: 0067
title: fleet stuck fifth cause — flag PRs whose head SHA never got a check-run
status: groomed
priority: P1
area: safety
created: 2026-07-01
owner: gtm-innovation
---

## User story

As a fleet operator who has watched a `feat/` PR sit for 40+ minutes with an
EMPTY `statusCheckRollup` (LESSONS 2026-05-26 — "GitHub Actions can silently
stop firing for a PR", recurring in fleet-control CROSS_LESSONS 2026-05-26), I
want `fleet stuck` to classify this as its own cause with the one-line recovery
(push to a fresh `<branch>-v2` name), so I stop wasting `heal:` attempts and
`gh pr comment` escalations on a PR the loop never had a fair chance to
process.

## Why now (four lenses)

### Product Owner
0059 shipped four stuck causes and explicitly deferred a fifth ("each new cause
is its own LESSONS reference + fixture + classifier branch in a follow-up
ticket"). The `actions_silent_head` shape is the highest-frequency deferred
cause: it has bitten agent-fleet AND fleet-control, is already in the heal
catalog as `actions_silent` (ticket 0020) for the RUN path, but is invisible on
the PR-open-no-CI-ever-fired path where the loop cannot self-heal because there
is no failed run to rerun. The smallest meaningful unit of value is one extra
row in `fleet stuck` and one memorized recovery command.

### Stakeholder
Widens the "fast recovery from a stuck PR" moat named in the agent brief. This
cause is systemic — it recurs across projects on random GitHub queue
transients, and neither `stuck` nor `overview` currently distinguishes it from
`healthy in-flight`. Closing this makes the loop's "self-diagnose before it
burns tokens" promise honest: today the loop retries `heal:` twice against a
PR that has no CI, then escalates with a confused comment. After this ticket,
the operator sees the row, runs one command, unsticks.

### Operator (9am glance)
The morning briefing already lists open PRs. Without this cause, an
`actions_silent_head` PR looks IDENTICAL to a healthily-in-flight PR — both
show "opened Xh ago, no checks yet." After the ticket, `fleet stuck` shows
`slug PR #N actions_silent_head — push to feat/<id>-<slug>-v2 (fresh branch
name)` and the operator is unblocked in one paste. Silent 6-hour blind spot
becomes a 60-second clear.

### Extensibility — earned by capability, NOT marketing
Pure capability. The classifier grows by one branch, the operator sees one
more diagnosable state. A second operator adopting the kit inherits a
detector that already knows about the recurring GitHub transient — one less
"why did nothing happen?" support tap on the shoulder.

## Acceptance criteria

- [ ] `stuck_classify_one_pr` (in `bin/fleet`) recognizes a fifth cause
      `actions_silent_head` when the PR's `statusCheckRollup` is EMPTY AND
      `createdAt` is > 30 minutes ago AND the PR is NOT draft. Threshold
      knob `FLEET_STUCK_ACTIONS_SILENT_MIN` (default 30) overrideable per test.
      Test asserts via a fixture PR that trips all three conditions gets the
      new classification and via a <30-min PR that does not.
- [ ] The action string for this cause is exactly
      `git push origin HEAD:feat/<id>-<slug>-v2  # LESSONS 2026-05-26` where
      `<id>-<slug>` is parsed from the current `headRefName`. Per LESSONS
      2026-05-28 the render goes through `printf -- '%s'`. Test asserts the
      exact string.
- [ ] `bin/fleet stuck --json` includes the new cause under the same schema
      as the existing four (`{"cause": "actions_silent_head", "action": "…"}`).
      JSON escape via `preflight_json_escape` per LESSONS 2026-06-03. Test
      validates JSON via `node -e 'JSON.parse(…)'`.
- [ ] Regression: the four existing causes (`BEHIND`, `DRAFT_armed`,
      `account_suspended`, `infra_flake_loop`) still classify identically for
      the fixtures shipped with 0059 — no cross-contamination. Test re-runs
      the 0059 fixtures unchanged and asserts each expected cause.
- [ ] `bin/fleet stuck --help` USAGE mentions the new cause name. Per LESSONS
      2026-05-30 the test check uses `grep -qF -- "$kw" "$help_out"`.
- [ ] Pure reader — no `events.jsonl` writes, no `fleet_emit_event` calls, no
      `lib/common.sh` change, no `prompts/` change. Test asserts via
      `git diff --name-only main...HEAD -- lib/common.sh prompts/` returning
      empty and every fixture slug's `events.jsonl` byte size unchanged before
      and after invocation.

## Out of scope

- Auto-pushing the recovery branch. The operator types the command — the
  contract is nudge, not act.
- Adding a SIXTH cause (e.g. `secret_scan_reject`, `pre-push-hook-fail`). Each
  cause is its own ticket per 0059's explicit convention.
- Changing the heal path to auto-open the fresh-name PR after N minutes of
  head-SHA-silence. That's a v2 with its own risk surface (writes vs. reads).
- Emitting a new event type — reuse `fleet stuck --json` for consumers.

## Engineering notes

- `bin/fleet` — extend `stuck_classify_one_pr` with ONE branch before the
  `healthy` fall-through. All new helpers (if any) defined ABOVE the dispatcher
  per LESSONS 2026-06-05 (forward-reference trap).
- `bin/fleet` — parse `<id>-<slug>` from `headRefName` via awk (single pass,
  `BEGIN { split(""); }` per LESSONS 2026-06-08). Threshold parse via
  `FLEET_STUCK_ACTIONS_SILENT_MIN`, defaulting via `${VAR:-30}`.
- `tests/stuck.sh` — one new fixture slug under `tests/fixtures/stuck/actions-
  silent-head/` mirroring the existing shape (events.jsonl, agents.config.sh,
  gh-fixture.json). Reuse the frozen-clock `FLEET_NOW_OVERRIDE` seam. Backup/
  restore via `cp` per LESSONS 2026-05-27.
- New deps: none. Public API: additive — no signature change to any `fleet_*`
  function. `lib/common.sh` untouched.
- Reinstall required: NO (`lib/` and `prompts/` untouched).

## Implementation log

(Appended by the implementation-dev agent during execution.)
