---
id: 0070
title: Make the reviewer's verdict a required check so auto-merge waits for it
status: in-progress
priority: P0
area: governance
created: 2026-10-17
owner: operator
---

## User story

As the fleet operator, I want an agent PR to merge only after the independent
reviewer has signed off on its latest commit, so that "reviewed by an
independent grader" (Doctrine D4/D5) is true of every merged PR instead of a
quarter of them.

## Why now (four lenses)

### Product Owner
Measured on 2026-10-17 across six fleet repos (agent-fleet, almanac, courtiq,
digital-craft-architect, fleet-control, levelup-kids): **150 of 638 merged
agent PRs had a review before merging; 26 merged while the reviewer's last
verdict was BLOCKING.** The smallest fix that makes the gate real is one
required check that reads the reviewer's verdict on the head commit.

### Stakeholder
Doctrine D5 already says auto-merge lands code "on green gating + no blocking
review". The kit has been claiming a guarantee it didn't enforce. Making it
true is the governance moat: the one property an operator can't easily verify
by reading prompts.

### Operator (9am glance)
Merges get slower (≈6 min → one reviewer tick, 5–15 min), and that is the
point. A blocked PR now sits red with the reason in the check output instead
of merging silently over a comment nobody read.

### Growth
"My agents can't merge without the reviewer's sign-off, and a required check
proves it" is the screenshot that makes another engineering lead trust the kit.

## Root cause

1. The reviewer runs as the PR author. GitHub rejects both `--approve` and
   `--request-changes` from the author, so every blocking verdict was posted as
   a plain comment — which auto-merge ignores.
2. CI (and the repo's auto-merge workflow) usually finishes before the reviewer's
   5-minute poll, so most PRs merged before any review existed.

## Acceptance criteria

- [x] `templates/scripts/review-gate.sh` passes only when the reviewer's newest
      `FLEET-VERDICT:` on the CURRENT head commit is `clean`; fails on none,
      old-head-only, other users, missing marker, `blocking`, or unknown verdicts;
      human branches pass. (tests/review-gate.sh AC#1–4)
- [x] `templates/workflows/review-gate.yml` runs on `pull_request` and
      `pull_request_review`, checks out the BASE commit (a PR can't rewrite its
      own gate), and names the job `review-gate`. (AC#5)
- [x] `lib/review.sh` posts every verdict as `--comment` with the marker on the
      first line and re-grades any open agent PR whose head has no marked
      verdict from it. (AC#6, review-lesson-draft AC#2/AC#8 updated)
- [x] ship + eng prompts: no verdict yet → wait; blocking → bounded heal of what
      the review names, inside the two-attempt cap. P-10 + CHANGELOG entry. (AC#6)
- [ ] Rollout, one repo at a time: copy the template + script, add `review-gate`
      to main's required status checks and to AGENTS.md § Gating checks, re-run
      `lib/install.sh`. agent-fleet first, then the other five.

## Risks

- First run after install re-grades every open agent PR once (e.g. almanac has
  10 stale May groom PRs) — a one-off review cost; close stale PRs first.
- If the reviewer is down, nothing merges. That is the intended failure mode;
  `fleet stuck` should surface it (follow-up).
