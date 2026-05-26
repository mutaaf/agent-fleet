---
id: 0017
title: fleet rollback reverts the last agent-shipped commit
status: groomed
priority: P1
area: safety
created: 2026-05-26
owner: gtm-innovation
---

## User story

As a fleet operator who just noticed a bad agent merge from last night, I
want `fleet rollback <slug>` to identify the most recent agent-authored
squash merge to `main` and open a revert PR with the same gating contract,
so that recovery is one command instead of `git log --author`, `git
revert`, branch, push, PR ceremony.

## Why now (four lenses)

### Product Owner
Today's recovery path is manual git surgery on the operator's laptop or a
hand-cranked revert PR via the GitHub UI. Both are friction at exactly the
moment the operator wants to remove friction: "the agent shipped something
I don't want; reverse it now." One subcommand turns a 5-minute panic
sequence into a 5-second one. Subtraction. Pairs naturally with trainee
mode (0014) — trainee mode keeps the operator IN THE LOOP before merges;
rollback handles the case where a merge slipped through and needs to come
back out after the operator graduated.

### Stakeholder
Widens the moat on `safety` AND on operator confidence. The kit becomes
forgiving: "if it ships something wrong, I can undo it cleanly." Without
rollback, the worst case of trusting the loop is "I have to do git
surgery on a Saturday." With it, the worst case is "one extra revert PR
in the history." That's the difference between "I'm scared to leave it
running" and "I'm fine with it running while I'm out."

### User (operator at 9am after a bad merge)
`fleet rollback almanac` prints:

```
Last agent merge to main: 2026-05-25T23:14:02Z
  commit:   1976339
  PR:       #42 feat/0019-broken-thing (merged by agent)
  message:  feat/0019 broken thing (#42)

Opening revert PR on branch revert/0019-broken-thing...
PR #45 opened: https://github.com/.../pull/45
Auto-merge armed; waiting for CI green.
```

One command, full audit trail, normal CI gate (so the revert itself can't
silently break things).

### Growth
"`fleet rollback` if it ships something you don't like" is exactly the
property that converts "I'm not sure I trust autonomous merges" into "ok,
the undo button is real." A demo where the operator types `fleet
rollback` and watches a clean revert PR appear is more reassuring than
any amount of documentation about the heal loop.

## Acceptance criteria

Each box maps 1:1 to a test scenario in `tests/rollback.sh`.

- [ ] `bin/fleet rollback <slug>` queries
      `gh pr list --repo <repo> --state merged --base main --limit 20
      --search "head:feat/ OR head:eng/" --json
      number,title,mergeCommit,headRefName,mergedAt` (the search filter
      mirrors the agent-branch prefixes; `chore/gtm-` is excluded because
      groom PRs are pure backlog churn and reverting them just re-floods
      the index).
- [ ] The most recent matching PR becomes the target. If none exists,
      print `no agent-merged feature PR found in the last 20 merges`
      and exit 1.
- [ ] Without flags, `fleet rollback <slug>` prints the target's metadata
      (commit, PR number, title, branch, mergedAt) and asks for
      confirmation: `proceed with revert? [y/N]`. Test asserts the
      prompt text and that pressing N exits 0 without opening a PR.
- [ ] With `--yes` (or `-y`), no prompt; proceeds directly.
- [ ] On proceed, the implementation: clones the repo into a fresh
      `$CACHE_DIR/rollback-checkout/`, branches `revert/<id>-<slug>`
      (where `<id>-<slug>` is the leading `id-slug` parsed from the
      target's headRefName, e.g. `0019-broken-thing`), runs `git revert
      --no-edit <mergeCommit>` (the squash commit), pushes, opens the PR
      via `gh pr create --fill --base main --head <branch>` with body
      `Reverts #<N>. Issued by fleet rollback <slug>.`, and arms `gh pr
      merge --auto --squash`.
- [ ] `fleet_emit_event rollback_opened pr=<N> reverts=<original-pr>
      merge_commit=<sha>` is emitted to the slug's events.jsonl.
- [ ] `bin/fleet rollback <slug> --pr <N>` overrides the auto-pick and
      reverts the specific PR number. The test asserts the override
      path (the `gh pr list` for the latest is NOT called when `--pr`
      is given; instead `gh pr view <N>` is).
- [ ] `bin/fleet rollback <slug> --dry-run` prints the same metadata
      plus the exact `git revert` and `gh pr create` commands it would
      run, but does not clone, branch, push, or call gh. Exit 0.
- [ ] Given a target PR that was NOT actually merged by squash (e.g.
      merge commit), the revert command may fail. The implementation
      detects this from `gh pr view <N> --json mergeMethod` and falls
      back to `git revert -m 1 <mergeCommit>` for true merge commits.
      The test covers both squash and merge cases.
- [ ] `README.md` "Daily ops" section gains a one-line callout for
      `fleet rollback` next to `fleet doctor`.

## Out of scope

- Rolling back multiple commits at once. v1 reverts exactly one PR.
- Rolling back a `chore/gtm-` (groom) PR. Backlog drift is recovered by
  the next groom run; a revert just re-floods.
- An "auto-rollback on smoke-test failure" daemon. That's a separate
  ticket — this one is operator-initiated only.
- Rewriting history (e.g. `git reset --hard`). Hard NO; the kit never
  bypasses branch protection.

## Engineering notes

- `bin/fleet` — `rollback()` function plus the top-level case branch.
- The fresh checkout under `$CACHE_DIR/rollback-checkout/` mirrors the
  pattern from `lib/common.sh` `fleet_checkout` but is one-shot and
  isolated (a revert that touches the same files as an in-flight ship
  must NOT race the ship's checkout). Use `git clone --depth 50` so the
  merge commit is reachable.
- Confirmation prompt: a plain `read -r -p` on stdin. The test pipes
  `N\n` (or `y\n` for the --yes-equivalent path) on stdin.
- `tests/rollback.sh` — `mktemp -d`, stub `gh` and `git` on PATH (so the
  test doesn't need a real GitHub remote), assert the exact command
  sequence and the emitted event. The `gh` stub records its argv to a
  file; assertions diff that file against expected fixtures.
- The `revert/` branch prefix is NEW. AGENTS.md `## Agent parameters`
  lists `feat/`, `chore/gtm-`, `eng/` today. The review subagent's
  branch-prefix regex (per AGENTS.md and `templates/AGENTS.section.md`)
  must extend to include `revert/` so the resulting revert PR is graded
  by the same reviewer. Add `revert/` to AGENTS.md § Agent parameters
  "Agent branch prefixes" with a note: "(emitted by `fleet rollback`)."
- Public API: additive (`bin/fleet rollback`,
  `rollback_opened` event type). No `lib/` public function signature
  changes.
- Reinstall: not required (this is `bin/` only). The AGENTS.md edit IS
  required and ships in the same PR.
- New dependency: none. Uses existing `git`, `gh`, `bash`.

## Implementation log

(Appended by the implementation-dev agent during execution.)
