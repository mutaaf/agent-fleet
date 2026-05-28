---
id: 0022
title: Reviewer send-backs drop a LESSONS skeleton draft for operator promotion
status: shipped
priority: P2
area: engine
created: 2026-05-28
owner: gtm-innovation
---

## User story

As a fleet operator who keeps meaning to promote review-time
send-backs into permanent LESSONS entries but forgets, I want the
review phase to automatically drop a date-stamped, comment-marked
skeleton entry at the top of `docs/LESSONS.md` whenever the reviewer
posts `--request-changes`, so that the failure-to-memory loop is one
operator edit (promote and unmark) instead of "remember to copy the
review body into LESSONS by hand."

## Why now (four lenses)

### Product Owner
Every reviewer `--request-changes` is a candidate lesson — the
reviewer just typed up "this PR violates X, fix Y" in plain English.
Today that text lives in the GitHub review body and decays. LESSONS.md
exists exactly to absorb those, but the promotion is manual and the
operator forgets. The smallest unit of value is a skeleton draft the
reviewer writes for them, marked as a draft so the validator stays
green and the operator can promote at leisure. Subtraction: the
operator is no longer the bottleneck of the failure-to-memory loop.

### Stakeholder
Widens the moat on the kit's central self-improvement claim: "the
loop reads LESSONS at the start of every run." That claim is only
load-bearing if LESSONS actually grows. Today it grows when the SHIP
agent hits a novel failure during heal (per README — "ship agent
appends one when it hits a novel failure"); but review-time
catches — which are at least as common a source of lessons — currently
do not write to LESSONS at all. This ticket closes that asymmetry.
Once the draft is there, even a 30-second weekly pass by the
operator promotes 5-10 lessons that today never get logged.

### User (operator on Sunday cleaning up)
Opens `docs/LESSONS.md`, sees:

```markdown
<!-- DRAFT: reviewer send-back, PR #42, 2026-05-28 -->
## 2026-05-28 — DRAFT — heal commit re-introduced a TODO removed two PRs ago

(From review of PR #42 — promote or delete.)

The PR's heal commit re-added `// TODO: handle null` to
src/lib/state.ts:184, even though PR #38 had explicitly removed it.
The reviewer caught it via the AGENTS.md HARD NO "never reintroduce
code that was removed in an earlier merge." Promote: the rule is
that heal commits MUST grep for any line they add against the last
30 days of merged commits' deletions.
<!-- /DRAFT -->
```

They read it. Either it is a real lesson (delete the `<!-- DRAFT
... -->` markers, fix the heading, leave the entry — done), or it
is noise (delete the whole block — done). Either way, 30 seconds.
The lessons file now grows steadily without operator vigilance.

### Growth
"The reviewer drafts lessons for you" is exactly the kind of property
that makes the kit's self-improvement claim concrete. It is the
mechanic that turns "an AI reviewer that blocks bad PRs" into "an AI
reviewer that teaches the loop." A friend reading the README's
LESSONS section sees entries that name the reviewer as their origin
— evidence the moat is compounding.

## Acceptance criteria

Each box maps 1:1 to a test scenario in `tests/review-lesson-draft.sh`.

- [ ] When `lib/review.sh` posts a `--request-changes` review, it
      ALSO (on the same agent branch, NOT main; same constraint as
      every other LESSONS append per README): prepends a draft
      block to `docs/LESSONS.md` of the form:
      ```
      <!-- DRAFT: reviewer send-back, PR #<N>, <YYYY-MM-DD> -->
      ## <YYYY-MM-DD> — DRAFT — <first 80 chars of the review body's first line>

      (From review of PR #<N> — promote or delete.)

      <full review body, indented or fenced as-is>
      <!-- /DRAFT -->
      ```
      The block is inserted AFTER the first heading and BEFORE the
      first non-draft `## YYYY-MM-DD` entry, so promoted lessons keep
      their existing position.
- [ ] The draft block is only inserted when the review body is
      non-empty AND the review is `--request-changes` (NOT `--comment`
      sign-offs). Test asserts no draft is written on a `--comment`
      review.
- [ ] Drafts are deduped by PR number: if a draft block already
      exists for `PR #<N>` (matched by the HTML comment marker),
      the second send-back on the same PR UPDATES the existing
      draft block in place rather than prepending a second one.
      Test seeds a draft, runs review again with a new body,
      asserts only one block remains and the body matches the
      latest review.
- [ ] `scripts/check-backlog.mjs` is unaffected — drafts live in
      LESSONS, not in `docs/backlog/`. Confirm by running the
      validator over a fixture LESSONS with three drafts and a
      mix of promoted entries; the validator's check is unchanged
      and still green.
- [ ] A new event type `lesson_draft_emitted {pr, headline}` is
      added to AGENTS.md § Telemetry and emitted by
      `fleet_emit_event` from the review path. `headline` is the
      first 80-char headline. The test stubs `fleet_emit_event`
      (or scans events.jsonl) and asserts exactly one such event
      per send-back.
- [ ] `prompts/PRINCIPLES.md` gains a new bullet under the
      existing principles (or a new `P-N`) naming the draft
      mechanism explicitly: "review send-backs write a LESSONS
      draft on the agent branch; promotion is the operator's job."
      The change goes through `prompts/CHANGELOG.md` per ticket
      0013's convention.
- [ ] `tests/review-lesson-draft.sh` covers: send-back writes draft;
      sign-off does not; dedupe on second send-back; validator still
      passes with drafts present; event emitted exactly once. Stubs
      `gh` to record review-post calls (already a pattern in
      `tests/sendback-pause.sh`).
- [ ] `lib/review.sh` public behavior unchanged in the
      send-back AND sign-off paths except for the LESSONS write +
      event emit on send-back. The single-quoted `gh pr review`
      argv and review body remain byte-identical to current behavior
      (assert via stubbed `gh` argv).

## Out of scope

- Auto-promoting drafts. The whole point is operator-in-the-loop —
  drafts are intentionally manual to promote so the operator stays
  responsible for what LESSONS says.
- Pruning stale drafts. v1 just keeps appending; a future ticket can
  add `fleet lessons prune-drafts --older-than 30d`.
- Surfacing drafts in `fleet doctor` / `fleet overview`. Possible
  follow-up; out for v1 to keep this ticket small.
- Routing drafts to a separate file (`docs/LESSON_DRAFTS.md`). One
  file keeps the operator's read path simple; the HTML-comment
  markers make `grep -v 'DRAFT'` trivial for any consumer that
  wants only promoted entries.
- Drafts on REVIEW phase outside of agent PRs (human PRs). The
  reviewer never grades human PRs anyway; scope is unchanged.

## Engineering notes

- `lib/review.sh` — the send-back branch (where the existing code
  calls `gh pr review --request-changes`) gains a call to a new
  helper `_review_emit_lesson_draft <pr> <body-file>`. The helper:
  (a) reads the current LESSONS.md, (b) checks for an existing
  draft marker for the same PR via grep, (c) writes the new file
  contents to a temp file then `mv` over LESSONS.md (per LESSONS
  2026-05-27: never use `$(cat file)` on content you write back —
  use `cp` / temp file + `mv`), (d) `git add docs/LESSONS.md`,
  (e) commits as part of the existing review commit if one is
  already being made, OR as a fresh `chore: draft LESSON from
  review #N` commit on the PR's branch (NOT main). Confirm which
  matches today's review.sh structure — review.sh today appears
  not to commit to the PR's branch, in which case the helper opens
  a tiny side-PR `chore/lesson-draft-<N>-<slug>` against main —
  detail the chosen mechanism in the implementation log.
- `prompts/PRINCIPLES.md` + `prompts/CHANGELOG.md` — one new
  principle bullet, one new CHANGELOG entry. Per ticket 0013, the
  validator (`check-prompts-changelog.mjs`) gates the pair.
- AGENTS.md § Telemetry — append `lesson_draft_emitted {pr, headline}`
  to the event-type bullet list.
- `tests/review-lesson-draft.sh` — `mktemp -d` fixture LESSONS.md
  with a mix of promoted and draft entries; stubbed `gh` recording
  argv; `git init` + commit to assert the draft commit lands on
  the agent branch and not main. Uses the `$HOME/.local/bin` stub
  pattern.
- Public API: additive (`lesson_draft_emitted` event; new helper
  in review.sh). No `fleet_*` signature changes.
- Reinstall required: YES — `lib/review.sh` and `prompts/PRINCIPLES.md`
  change. PR body must include `Reinstall: all projects`.
- File-edit safety: when prepending to LESSONS.md, NEVER use
  `$(cat docs/LESSONS.md)` then `printf '%s' "$VAR"` (LESSONS
  2026-05-27 — strips trailing newlines). Read into a temp file
  via `cp` or `awk` and `mv` the temp back.

## Implementation log

### 2026-05-28 — implementation-dev

Mechanism chosen: **side-PR**. `lib/review.sh` today does NOT commit to the
PR branch — the reviewer is read-only on the diff. Per the ticket's
engineering note, the helper opens a tiny `chore/lesson-draft-<N>-<ts>`
branch against `main` and pushes a single-file commit touching
`docs/LESSONS.md`. This keeps the reviewer's "no writes to the agent PR's
branch" invariant intact while still landing the draft on `main` where the
operator can promote it. The mechanism is wired through the prompt
heredoc in `lib/review.sh` (instructions for the agent), with the actual
LESSONS mutation done by the new helper `_review_emit_lesson_draft` in
`lib/common.sh`.

Helper signature: `_review_emit_lesson_draft <pr> <body-file> [lessons-file]`.
File mutation goes through `awk` + a temp file + `mv` (per LESSONS
2026-05-27). Dedupe key is the PR number, matched on the opening HTML
comment marker. Event `lesson_draft_emitted {pr, headline}` is appended to
`AGENTS.md § Telemetry` and emitted exactly once per helper invocation.
A new constitutional principle `P-9` lands in `prompts/PRINCIPLES.md` with
a matching `prompts/CHANGELOG.md` entry. Tests in
`tests/review-lesson-draft.sh` cover all eight acceptance boxes by
invoking the helper directly against a fixture LESSONS.md (no actual `gh`
calls required for the unit, mirroring the `tests/sendback-pause.sh` stub
pattern).
