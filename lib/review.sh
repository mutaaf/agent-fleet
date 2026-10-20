#!/bin/bash
# agent-fleet/lib/review.sh — generic autonomous review runner.
#
# Usage (from launchd): bash review.sh /abs/path/to/config-dir
#
# Polls for open agent PRs not yet reviewed by the repo owner and grades each
# against AGENTS.md + the referenced ticket. Runs as the PR author's gh identity,
# so GitHub forbids both --approve and --request-changes. Every verdict is a
# --comment review whose body carries `FLEET-VERDICT: clean|blocking`; the
# required `review-gate` check (ticket 0070, templates/workflows/) reads that
# marker on the PR's head commit, so auto-merge waits for the reviewer.
#
# Logs only when there is work, to avoid hundreds of empty logs/day.

source "$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )/common.sh"

fleet_load_manifest "${1:-}"
fleet_self_cancel >/dev/null || exit 0   # quiet on expiry — this is a frequent poller
# Budget gate before any work. Tag the event with phase=review even though
# fleet_log_init hasn't run yet, so consumers can attribute the block.
FLEET_PHASE="review"; export FLEET_PHASE
fleet_check_budget >/dev/null || exit 0

ME=$(gh api user --jq .login 2>/dev/null || echo "")
if [ -z "$ME" ]; then
  echo "$(date -u): review agent — no gh auth, exiting" >> "$LOG_DIR/review.err"
  exit 1
fi

# Branch prefixes that mark an agent PR. Manifest may override; default covers
# the canonical feature/groom/eng queues.
AGENT_BRANCH_RE="${AGENT_BRANCH_RE:-^(feat/|chore/gtm-|eng/)}"

# Open agent PRs whose CURRENT head has no verdict from us (ticket 0070): a
# heal push moves the head, so a blocked PR is re-graded automatically, and a
# review that forgot the FLEET-VERDICT marker is retried on the next tick.
UNREVIEWED=$(gh pr list --repo "$REPO" --state open --base main \
  --json number,headRefName,headRefOid,reviews \
  --jq "[.[] | select(.headRefName | test(\"$AGENT_BRANCH_RE\"))
            | .headRefOid as \$head
            | select(.reviews | any(.author.login == \"$ME\"
                                    and .commit.oid == \$head
                                    and (.body | test(\"FLEET-VERDICT:\"; \"i\"))) | not)
            | .number] | .[]" 2>/dev/null)

[ -z "$UNREVIEWED" ] && exit 0   # quiet exit — most ticks have no work

fleet_log_init review
fleet_emit_event run_started "pid=$$" || true
fleet_check_prompts_sha || true
echo "reviewer: $ME"
echo "PRs to review:"; echo "$UNREVIEWED" | sed 's/^/  #/'; echo

fleet_acquire_lock review || exit 0
trap 'fleet_release_lock review' EXIT

fleet_checkout review-checkout

for PR in $UNREVIEWED; do
  echo; echo "--- reviewing PR #$PR ---"

  PR_SHA=$(gh pr view "$PR" --repo "$REPO" --json headRefOid --jq .headRefOid 2>/dev/null)
  [ -z "$PR_SHA" ] && { echo "couldn't resolve head SHA for #$PR; skipping"; continue; }
  git fetch origin "pull/$PR/head" --depth=20 --quiet 2>&1 || { echo "couldn't fetch #$PR head; skipping"; continue; }
  git checkout --detach FETCH_HEAD --quiet
  [ "$(git rev-parse HEAD)" != "$PR_SHA" ] && { echo "SHA mismatch for #$PR; skipping"; continue; }

  rm -rf /tmp/fleet-review && mkdir -p /tmp/fleet-review
  gh pr view "$PR" --repo "$REPO" \
    --json title,body,headRefName,baseRefName,additions,deletions,changedFiles,files,author \
    > /tmp/fleet-review/meta.json
  gh pr diff "$PR" --repo "$REPO" > /tmp/fleet-review/diff.patch
  echo "diff: $(wc -l </tmp/fleet-review/diff.patch | tr -d ' ') lines"; echo

  PR="$PR" REPO="$REPO" ME="$ME" \
    fleet_run_claude review <<PROMPT
You are the autonomous Review agent for the $REPO repo, reviewing PR #$PR
on branch \$(jq -r .headRefName /tmp/fleet-review/meta.json).

You have:
  - the repo checked out at the PR head (cwd is the working tree)
  - /tmp/fleet-review/meta.json  — PR metadata
  - /tmp/fleet-review/diff.patch — the diff
  - gh CLI authed as $ME (the PR author — you CANNOT --approve)

Read in order, then grade:
  1. AGENTS.md — the contract. Its "## Agent parameters" section names the
     EXACT gating checks and the hard NOs for this project. Only those checks
     gate a merge; every other check (Vercel, preview comments, informational
     suites) MUST be ignored when deciding mergeability.
  2. docs/LESSONS.md — operational memory; don't re-approve a pattern a past
     lesson warned against.
  3. /tmp/fleet-review/meta.json and /tmp/fleet-review/diff.patch
  4. docs/backlog/README.md and the ticket referenced in the PR body/branch
     (e.g. "Implements: docs/backlog/NNNN-..."). If no ticket reference exists,
     the verdict is blocking.
  5. .claude/agents/review.md — the full grading rubric for this project.

Grade against: AGENTS.md hard NOs; ticket fit (every acceptance-criteria box
covered by a test in the diff); test-first discipline (every src change has a
matching test change); code quality; the project's voice/aesthetic rules;
and prompts/PRINCIPLES.md — does the diff violate any principle? If yes,
the verdict is blocking; cite the P-N id.

If you discover a NOVEL operational lesson not already in docs/LESSONS.md, note
it in your review body prefixed "LESSON:" so the next ship/groom run folds it in.
Do NOT commit to the PR branch — you are read-only on the diff.

Deliver exactly one verdict, ALWAYS as a --comment review (you are the PR
author: GitHub rejects both --approve and --request-changes from you). The
FIRST line of the body must be exactly one of:
  FLEET-VERDICT: clean
  FLEET-VERDICT: blocking
  clean    → gh pr review $PR --repo $REPO --comment --body "FLEET-VERDICT: clean
<detailed sign-off>"
  blocking → gh pr review $PR --repo $REPO --comment --body "FLEET-VERDICT: blocking
<summary of what must change>"
The required review-gate check reads that line on the PR's head commit:
clean lets auto-merge proceed, blocking holds the merge until a new commit is
re-graded. A body without the marker counts as no review at all.

If (and ONLY if) your verdict is blocking, ALSO drop a LESSONS draft
skeleton for the operator to promote later. Mechanism (ticket 0022):

  1. Write your review body verbatim to /tmp/fleet-review/draft-body.txt.
  2. Run (from a fresh checkout of $REPO with main checked out):

       bash -c 'source lib/common.sh && \
                fleet_load_manifest "$PROJECT_DIR" && \
                FLEET_PHASE=review _review_emit_lesson_draft \
                  '"$PR"' /tmp/fleet-review/draft-body.txt docs/LESSONS.md'

  3. Open a tiny side-PR (NOT main):
       git checkout -b chore/lesson-draft-${PR}-$(date -u +%s)
       git add docs/LESSONS.md
       git commit -m "chore: draft LESSON from review #${PR}"
       git push -u origin HEAD
       gh pr create --repo $REPO --base main --fill

Do NOT call _review_emit_lesson_draft on a clean verdict.
Do NOT commit to the PR's own branch (you are read-only on the diff).

End the session immediately after the gh pr review call (and the optional
draft side-PR for blocking verdicts).
PROMPT

  cd "$CACHE_DIR/review-checkout" || { echo "review-checkout missing"; continue; }
  git checkout -f main --quiet; git reset --hard origin/main --quiet
done

git checkout main --quiet 2>/dev/null || true
echo; echo "=== ${SLUG}-review complete $(date -u) ==="
fleet_emit_event run_completed "exit=0" "duration_ms=$(( ( $(date -u +%s) - RUN_STARTED_EPOCH ) * 1000 ))" || true
