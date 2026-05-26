---
id: 0001
title: Per-slug flock prevents overlapping launchd runs
status: in-progress
priority: P0
area: safety
created: 2026-05-26
owner: gtm-innovation
---

## User story

As a fleet operator, I want two launchd jobs for the same project to never run
at the same time, so that a long ship doesn't get clobbered by the next :41
firing and corrupt the checkout.

## Why now (four lenses)

### Product Owner
The simplest unit of safety — one project, one runner at a time. Removes a
class of bugs (half-applied heal, lost commit) before it bites. The operator
doesn't have to think about cadence vs run duration.

### Stakeholder
Widens the moat on `safety`. Today the kit relies on launchd's default
behavior, which happily fires the next ship while the previous one is still
holding a checkout open. This is the kind of silent corruption that's easy
to ship a bad PR through.

### Operator (Tuesday 9am, glance at the portal)
"Why does this project have two `agent-ship` PIDs running?" — they shouldn't.
After this, the second invocation no-ops cleanly with a logged reason in the
launchd .out, and the portal's run list shows zero false-double-counted runs.

### Growth
The kit feels safer to install on a new repo. "Long runs won't trample each
other" is the kind of property a person running their own loop will check
for before committing.

## Acceptance criteria

- [ ] `common.sh` exposes `fleet_acquire_lock` and `fleet_release_lock`
      helpers, both called by `ship.sh`, `groom.sh`, `review.sh`, and `eng.sh`
      around the `fleet_run_claude` call.
- [ ] The lock file lives at `$CACHE_DIR/lock` (per slug). The implementation
      uses macOS-portable `mkdir`-as-mutex semantics (since macOS has no
      `flock(1)` by default).
- [ ] When a second runner for the same slug fires while the first holds the
      lock, the second prints `"<slug>-<phase> skipped — locked by <pid>"` to
      the launchd .out, appends an event (depends on ticket 0002 once shipped;
      until then write a plain log line), and exits 0.
- [ ] If the lock file is older than 6 hours, the next runner treats it as
      stale (the previous run crashed without releasing), logs
      `"stale lock: claiming"`, and proceeds.
- [ ] A bash-level test in `tests/lock.sh` exercises the contention case by
      forking two background invocations of a stub runner and asserting only
      one wrote to a shared output.
- [ ] `lib/install.sh` is unchanged (no new plist field needed). Idempotent.
- [ ] No change to the `fleet_*` public API signatures — only additions.

## Out of scope

- Cross-slug locking (project A locking project B is intentionally allowed).
- Replacing launchd with a different scheduler.
- A lock-status field in the manifest.

## Engineering notes

- `lib/common.sh` — add the two helpers near the bottom, after
  `fleet_run_claude`. Use `mkdir "$lock_dir"` as the mutex (atomic on macOS
  HFS+/APFS); release with `rm -rf "$lock_dir"`.
- `lib/ship.sh`, `lib/groom.sh`, `lib/review.sh`, `lib/eng.sh` — wrap
  `fleet_run_claude` with `fleet_acquire_lock "$PHASE" || exit 0` and add a
  `trap fleet_release_lock EXIT`.
- `tests/lock.sh` — bash test that exercises the contention path. The test
  itself must not require launchd or `claude` to be installed; stub
  `fleet_run_claude` with a sleep+echo.
- Public API: additive. No `BREAKING:` line needed.
- Reinstall: all projects. The lock semantics only kick in after install.sh
  has copied the new `lib/` to `~/.local/share/agent-fleet/`.

## Implementation log

- 2026-05-26 — picked up by implementation-dev. Branch
  `feat/0001-flock-per-slug`. Plan: add `fleet_acquire_lock` /
  `fleet_release_lock` to `lib/common.sh` using `mkdir`-as-mutex at
  `$CACHE_DIR/lock`; wire into ship/groom/review/eng around
  `fleet_run_claude` with `trap` for release; treat lock dirs older than
  6 hours as stale. Write `tests/lock.sh` first to exercise contention
  with two background stub runners and a shared output file.
