---
id: 0035
title: fleet prompts-revert pins the kit's prompts/ tree back to a known-good SHA
status: shipped
priority: P2
area: governance
created: 2026-06-05
owner: implementation-dev
---

## User story

As an operator who just opened `fleet prompts-score` and saw the
newest prompts revision (`prompts_sha=8a20547`) carrying a 40%
send-back rate against the prior revision's 12%, I want `bin/fleet
prompts-revert <sha>` to check out the named SHA's `prompts/` tree
into the kit's working copy, regenerate the prompts SHA, and emit
one `prompts_reverted` event so every installed project's next ship
run picks up the older (better) prompts — without me having to
remember which file changed, run a manual `git checkout
<sha> -- prompts/`, re-run `install.sh` across 5 projects, and pray
I got it right — so that recovering from a bad prompts merge is one
command, the same shape as `fleet rollback` is for a bad code merge.

## Why now (four lenses)

### Product Owner
Ticket 0013 shipped `prompts/CHANGELOG.md` + `fleet prompts-diff`
(explain drift). Ticket 0024 shipped `fleet prompts-score` (grade
each revision from real event history). Ticket 0017 shipped `fleet
rollback` for code. The missing piece is the parallel of rollback
for PROMPTS: when prompts-score says "revision Z is worse than Y,"
the operator's recovery today is to (1) `git log --oneline -- prompts/`,
(2) figure out which SHA was Y, (3) `git checkout Y -- prompts/`,
(4) commit, (5) push a branch through CI, (6) re-run `install.sh`
across every project. Six steps, three of them error-prone. The
smallest unit of value is one command that does the checkout, opens
a `revert/prompts-<sha>` PR (per `revert/` branch prefix already in
AGENTS.md), and emits the audit event. Subtraction: the operator
stops having to memorize the prompts file layout to recover. The
command is the recovery; the PR is the audit trail.

### Stakeholder
This closes the last symmetric gap in the kit's safety model. The
PAUSE/RESUME pair is closed (ticket 0030). The CODE rollback path
is closed (ticket 0017). The PROMPTS revert path is the third leg;
its absence has been felt every time prompts-score has flagged a
regression and the operator has had to script the recovery by hand.
After this ticket, every kind of "bad merge" the loop can produce
(bad code → `fleet rollback`, bad prompts → `fleet prompts-revert`,
bad send-back streak → ship_paused + `fleet resume`) has a
one-command recovery. That's the moat: not just "the loop pauses
when broken" but "the loop has a single-command undo for every
class of breakage." The `prompts_reverted` event also feeds into
`fleet prompts-score`'s timeline (ticket 0024 already consumes
`prompts_pin_changed` for the revision boundary; `prompts_
reverted` slots in next to it as the "the operator deliberately
walked back" marker).

### User (operator after `fleet prompts-score` shows the regression)
Reads the score table, sees:

```
PROMPTS_SHA   FROM           SHIPS  SENDBACKS  RATE   NOTE
8a20547       2026-06-03     15     6          40%    current
ee94b3a       2026-05-28     42     5          12%    prev
3db48f7       2026-05-21     38     6          16%    prev
```

Types `fleet prompts-revert ee94b3a --reason "8a20547 regression,
see prompts-score 2026-06-05"`. Sees:

```
fleet prompts-revert: checking out prompts/ at ee94b3a …
  current prompts_sha: 8a20547
  target prompts_sha:  ee94b3a
  files restored: prompts/ship.prompt.md, prompts/review.prompt.md
  diff: 47 lines (use `git diff --cached -- prompts/` to inspect)

opening revert PR …
  branch:  revert/prompts-ee94b3a
  PR:      #91 https://github.com/mutaaf/agent-fleet/pull/91
  body:    [FLEET prompts-revert] pin prompts/ back to ee94b3a
           reason: 8a20547 regression, see prompts-score 2026-06-05

emitted prompts_reverted from=8a20547 to=ee94b3a pr=91 reason="…"

NEXT: the review subagent will grade this PR like any other.
      After merge, run install.sh across every project per the
      'Reinstall: all projects' convention (LESSONS 2026-05-25).
```

The operator never edited a prompt file by hand. The audit trail
lives in the revert PR and the event log. If `fleet prompts-revert`
were unavailable, recovery would have taken 15 minutes and one
chance of typoing the SHA.

### Growth
Every operator who ships prompts edits past week 2 hits the moment
where one of them regresses. Today the kit catches the regression
(`prompts-score`) but does not offer the undo. Adding the undo
closes the second half of the "edit prompts confidently" story:
edit → score → if bad, revert. Friends running their own loop pick
this up immediately because the alternative (a hand-edited revert
across N installs) is the most-error-prone operation in the kit's
lifecycle. The output is also a screenshot-perfect demo for the
README: "here's how recovery from a bad prompts merge works in one
command." Compounds 0013 (`prompts/CHANGELOG.md` is the human-
readable history the SHA points into), 0017 (`fleet rollback` is
the code analogue), 0024 (`fleet prompts-score` produces the
SIGNAL that triggers the revert), 0029 (`fleet provenance` is the
forensic analogue that READS the revert event from the channel).

## Acceptance criteria

Each box maps 1:1 to a test scenario in `tests/prompts-revert.sh`.

- [ ] `bin/fleet prompts-revert <sha> --reason "<one-line>"`
      on a clean working tree resolves `<sha>` against the
      kit's git history, runs `git checkout <sha> -- prompts/`,
      verifies the working tree's prompts SHA (per `fleet
      prompts-sha`) now matches the target, commits with
      message `revert: pin prompts/ back to <sha>\n\nreason:
      <reason>\n\nCo-Authored-By: …`, pushes the branch
      `revert/prompts-<short-sha>`, opens a PR via `gh pr
      create --head mutaaf:revert/prompts-<short> --base main
      --body "<body>"`, emits one `prompts_reverted` event,
      and exits 0. Test fixtures a synthetic git repo with a
      two-commit prompts history and asserts the checkout +
      commit + push happened against stubbed `git`/`gh`.
- [ ] `<sha>` argument accepts a full 40-char SHA, a short
      SHA (>=7 chars), or a CHANGELOG date stamp
      (`YYYY-MM-DD` — the first commit whose CHANGELOG entry
      matches). The date-stamp branch resolves via `git log
      --format=%H -G "^## $date" -- prompts/CHANGELOG.md`.
      All three forms tested.
- [ ] `--reason "<one-line>"` is MANDATORY (per safety
      precedent from ticket 0030's `--force --reason`
      pattern). Missing reason: `prompts-revert: --reason
      "<one-line>" is required (auditable override)` to
      stderr, exit 2. Test asserts the missing-reason branch.
- [ ] `--reason` value with leading `-` (operators paste
      `--reason "-regression on heal phase"`) parses
      correctly per LESSONS 2026-05-28 (printf leading-dash
      trap). The reason is recorded verbatim in the PR body,
      the commit message, AND the event payload. Test
      asserts the leading-dash reason rendered correctly in
      all three places.
- [ ] Revert to a SHA whose prompts tree is BYTE-IDENTICAL
      to the current one (operator typoed and asked to
      revert to current): the command prints
      `prompts-revert: <sha>'s prompts/ tree is identical to
      the current working tree (sha=<current>) — nothing to
      do.` and exits 0. Does NOT commit, does NOT push, does
      NOT emit an event. Idempotent no-op.
- [ ] Revert with a DIRTY working tree (uncommitted changes
      to any tracked file): the command refuses with
      `prompts-revert: working tree has uncommitted changes
      — commit, stash, or discard them first` to stderr,
      exit 2. Test asserts via a stub-seeded dirty state.
- [ ] Unknown SHA: `prompts-revert: <sha> is not a valid
      git ref in this kit checkout` to stderr, exit 2.
- [ ] `prompts_reverted` event payload: `{from: <current-
      sha-before>, to: <target-sha>, pr: <pr-number>,
      reason: <string>}`. Event lands in the AGENT-FLEET
      project's `$CACHE_DIR/events.jsonl` (kit-as-project,
      per the pattern `lesson_promoted` from ticket 0028
      established). Event carries `phase=revert`.
- [ ] `AGENTS.md § Telemetry` is updated in the same PR
      with a new bullet for `prompts_reverted {from, to,
      pr, reason}` following the existing entry style
      (verbatim shape: see ticket 0028's `lesson_promoted`
      paragraph and 0030's `ship_resumed` paragraph).
      Reviewer's telemetry-contract check requires this in
      the same diff.
- [ ] The opened PR's body includes:
      `Reinstall: all projects` (per LESSONS 2026-05-25 —
      anything touching `prompts/` requires fleet-wide
      reinstall after merge). Test asserts the line is
      present in the `gh pr create --body` argument the
      stub recorded.
- [ ] Help: `bin/fleet prompts-revert --help` prints a
      USAGE block mentioning `<sha>`, `--reason`,
      `--help`. Test asserts via `grep -qF -- "$kw"
      "$help_out"` per LESSONS 2026-05-30. Help block
      ends with `exit 0` per LESSONS 2026-06-01
      (dispatcher fall-through trap).
- [ ] `tests/prompts-revert.sh` covers all 11 boxes using
      `$HOME/.local/bin` stubs (per LESSONS 2026-05-26)
      for `git`, `gh`. The stub records every invocation
      to a temp file the test asserts against. Per
      LESSONS 2026-05-27, the test uses `cp` for
      backup/restore — never `$(cat …)`. Run-time
      budget: <10s.

## Out of scope

The dev agent will NOT do these even if they seem related.

- AUTO-reverting based on `fleet prompts-score`'s WARN/FAIL
  verdict. Autopilot revert defeats the safety — the
  operator must judge the regression rationale. The command
  is operator-invoked only.
- Running `install.sh` across every installed project as
  part of the revert. The revert opens a PR; merging it goes
  through CI; the post-merge reinstall is the operator's
  call (or fleet-control's "keep-running" action, which
  already exists). Adding a `--reinstall` flag would
  collapse a PR-gated merge into a one-step prod push —
  contrary to the kit's "every change goes through a PR"
  posture.
- A `--undo` companion that reverts the revert. Standard git
  semantics (`fleet prompts-revert <newer-sha>`) already
  handle this; a special flag adds surface for zero new
  capability.
- Touching anything outside `prompts/` (e.g. `lib/` or
  `AGENTS.md`). The command is strictly for prompts SHA
  pinning; mixing in `lib/` reverts is `fleet rollback`'s
  job (per-PR), not this command's.
- A launchd schedule. Like `rollback` and `resume`, this is
  operator-run.
- CHANGELOG editing. The CHANGELOG already records every
  prompts edit chronologically; the revert PR adds the
  newest entry for the revert itself, and that entry is
  written BY the dev/review subagent per the existing
  `prompts/CHANGELOG.md` discipline. No special-case
  CHANGELOG writer in this command.

## Engineering notes

Files / patterns the dev should touch. Specific enough that the dev
doesn't have to re-discover the architecture.

- `bin/fleet` — new `prompts_revert()` dispatcher next to
  the existing `prompts_diff()` / `prompts_score()` /
  `prompts_sha()` block (find via `grep -n
  'prompts_diff\|prompts_score\|prompts_sha' bin/fleet`).
  Shape mirrors `rollback()` (line ~3564): same `--reason`
  parsing per LESSONS 2026-05-28, same dispatcher exit
  pattern.
- `bin/fleet` — four helpers:
  - `prompts_revert_resolve_sha()` — accept full SHA,
    short SHA (≥7), or date-stamp; resolve to a full
    SHA via `git rev-parse <input>` (full/short) or
    `git log --format=%H -G "^## $date" -- prompts/
    CHANGELOG.md | head -1` (date). Echo the resolved
    SHA or exit 2 on unknown.
  - `prompts_revert_compute_target_tree_sha()` —
    `git rev-parse <sha>:prompts` (the tree object SHA
    of `prompts/` at that commit). Used to short-circuit
    AC#5 (target byte-identical to current).
  - `prompts_revert_compose_pr_body()` — assembles the
    PR body: the title, the `from`/`to` SHA line, the
    `--reason` value, the `Reinstall: all projects`
    trailer. Per LESSONS 2026-06-01 (awk -v multiline
    trap), the body is written to a tmp file and passed
    via `gh pr create --body-file`, never `--body
    "$body"` (a multi-line body via `-v` is the same
    family of trap).
  - `prompts_revert_emit_event()` — wraps `fleet_emit_
    event prompts_reverted from=$from to=$to pr=$pr
    reason="$reason"`. The reason value passes through
    `_json_escape` via `fleet_emit_event` — the
    follow-up to LESSONS 2026-06-03 must land before
    this command ships if the reason can be UTF-8.
    Reason is restricted to ASCII for v1 (validated by
    the dispatcher: non-ASCII → `prompts-revert:
    --reason must be ASCII for v1 (see ticket 0035
    note)`, exit 2).
- `bin/fleet` — `prompts_revert()` end-state must be
  `exit 0` (success), `exit 2` (usage error), or `exit
  1` (git/gh failure) on every code path per LESSONS
  2026-06-01 (dispatcher fall-through trap). Copy the
  exit-N pattern from `rollback()` (line ~3564)
  verbatim.
- `bin/fleet` — dispatcher block at the bottom of the
  file: `if [ "$CMD" = "prompts-revert" ]; then
  prompts_revert "$@"; fi`. Placed next to the existing
  `prompts-diff` / `prompts-score` / `prompts-sha`
  blocks.
- `bin/fleet` — help banner block at the top of the
  file (around line ~14) gets a new line: `fleet
  prompts-revert <sha>  pin prompts/ back to a known-
  good SHA (opens revert/ PR)`. README "Daily ops" code
  block gets the same.
- `lib/common.sh` — NO changes. `prompts-revert` is a
  pure caller of `fleet_emit_event` (existing). NO new
  helpers, NO `fleet_*` signature changes.
- `AGENTS.md § Telemetry` — append a new bullet for
  `prompts_reverted {from, to, pr, reason}` — emitted
  by `bin/fleet prompts-revert` once per successful
  revert. Carries `phase=revert`. Payload as defined in
  AC#8. Mirrors the shape of `lesson_promoted` (0028),
  `rollback_opened` (0017), `ship_resumed` (0030).
- `prompts/` — NO direct edits in THIS PR. The command
  itself is the editor; future revert PRs will modify
  `prompts/` via `git checkout`. No `Reinstall: all
  projects` line is needed on THIS PR's body because
  THIS PR only adds `bin/fleet` + tests + AGENTS.md
  paragraph — no `prompts/` content change.
- `prompts/CHANGELOG.md` — NO direct edit in THIS PR
  (no `prompts/` content change in THIS PR per
  `check-prompts-changelog.mjs`). Future revert PRs
  will add a CHANGELOG entry of the form
  `## YYYY-MM-DD — revert prompts/ to <short-sha>`.
- `tests/fixtures/prompts-revert/` — NEW directory
  under `tests/fixtures/` holding:
  - one stub `git` script that simulates a kit
    checkout with a known two-commit prompts history
    (commits A and B; current HEAD is B)
  - one stub `gh` script that records `pr create`
    invocations to `$TMP/gh.log` and returns a fake
    PR number
- `tests/prompts-revert.sh` — top of file mirrors
  `tests/rollback.sh`: stub `git`, `gh` under
  `$HOME/.local/bin` (`$HOME=$TMP/home` per LESSONS
  2026-05-26). The stub `git` accepts `rev-parse`,
  `checkout`, `add`, `commit`, `push`, `status`,
  `log`. The event assertion reads the kit's events
  channel (under `$TMP/cache/agent-fleet-agent/
  events.jsonl`) and parses the last line via
  `node -e 'JSON.parse(...)'`.
- New deps: none. Pure shell + git + gh + existing
  `fleet_emit_event` (lib/common.sh ~975), `_json_
  escape` (common.sh ~849) used indirectly.
- Public API: additive — `bin/fleet prompts-revert`
  is a new subcommand. ONE new event type added
  (`prompts_reverted`) — consumers MUST tolerate
  unknown types per the existing AGENTS.md §
  Telemetry contract, so this is additive, not
  breaking. NO `fleet_*` signature changes.
- BREAKING flag: NO. PR body affirms "no `fleet_*`
  signature changes" and explicitly names the new
  event type so the reviewer's telemetry-contract
  check passes.
- Reinstall required: NO for THIS PR (no `lib/` or
  `prompts/` content change). FUTURE PRs OPENED BY
  the command WILL need `Reinstall: all projects`
  because they touch `prompts/` — the
  `prompts_revert_compose_pr_body` helper adds the
  trailer automatically.
- LESSONS to defend against: 2026-05-25 (`lib/`
  changes need a fleet-wide reinstall — THIS PR is
  exempt because it does not touch `lib/`, but the
  PRs it OPENS do touch `prompts/` and the body
  trailer per AC#10 surfaces that). LESSONS
  2026-05-26 (`tail` shadow — `prompts_revert` is
  namespaced). LESSONS 2026-05-26 (PATH reset —
  stubs go in `$HOME/.local/bin`). LESSONS
  2026-05-27 (`$(cat)` trap — fixture reads use
  `cp`). LESSONS 2026-05-28 (printf leading-dash
  trap — every reason value goes through `printf
  -- '%s'`). LESSONS 2026-05-30 (`grep -F --` flag
  trap — help text uses `grep -qF --`). LESSONS
  2026-06-01 (awk -v multiline trap — the PR body
  goes through a tmp file via `gh pr create
  --body-file`, NEVER `--body "$body"`). LESSONS
  2026-06-01 (`grep -c file || echo 0` double-
  print trap — n/a, no counts here). LESSONS
  2026-06-01 (dispatcher fall-through trap —
  `prompts_revert()` ends with explicit `exit N`
  on every path including the help block).
  LESSONS 2026-06-03 (UTF-8 sign-extension trap —
  the reason value is restricted to ASCII for v1;
  AC validates).
- This ticket compounds 0013 (`prompts/
  CHANGELOG.md` is the human-readable history),
  0017 (`fleet rollback` is the code analogue),
  0024 (`fleet prompts-score` is the SIGNAL that
  triggers a revert), 0029 (`fleet provenance`
  reads the new event type for forensics). Per
  P-1 the diff is small: ~200 lines of
  `prompts_revert*` helpers + ~250 lines of test
  + one AGENTS.md paragraph + one help-text line.

## Implementation log

(Appended by the implementation-dev agent during execution.)

- 2026-06-05 — branch `feat/0035-prompts-revert-pin-to-sha` opened from `main`; ticket flipped `groomed` → `in-progress`.
- 2026-06-05 — failing tests-first added at `tests/prompts-revert.sh` (11 ACs, stubbed `git`/`gh` under `$HOME/.local/bin` per LESSONS 2026-05-26); ran red against `bin/fleet` baseline.
- 2026-06-05 — `prompts_revert()` + 4 helpers + AGENTS.md telemetry bullet + README "Daily ops" line landed; all 11 ACs green, `shellcheck -S warning` + `bash -n` + `check-backlog.mjs` + `check-prompts-changelog.mjs` PASS.
- 2026-06-05 — PR #71 opened (auto-merge armed via `gh pr merge --auto --squash`); both gating checks (`shellcheck`, `validate`) green; merged at 2026-06-05T23:55:57Z (commit `2af93b23`).
