#!/bin/bash
# agent-fleet/lib/review.sh — generic autonomous review runner.
#
# Usage (from launchd): bash review.sh /abs/path/to/config-dir
#
# Polls for open agent PRs not yet reviewed by the repo owner and grades each
# against AGENTS.md + the referenced ticket. Runs as the PR author's gh identity,
# so it never --approves (GitHub forbids self-approval): it posts
#   --comment          clean sign-off (does not block)
#   --request-changes  blocking issue (blocks auto-merge until dismissed)
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

# Open agent PRs without a review from us. One PR number per line.
UNREVIEWED=$(gh pr list --repo "$REPO" --state open --base main \
  --json number,headRefName,reviews \
  --jq "[.[] | select(.headRefName | test(\"$AGENT_BRANCH_RE\"))
            | select(.reviews | any(.author.login == \"$ME\") | not)
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
     post --request-changes and stop.
  5. .claude/agents/review.md — the full grading rubric for this project.

Grade against: AGENTS.md hard NOs; ticket fit (every acceptance-criteria box
covered by a test in the diff); test-first discipline (every src change has a
matching test change); code quality; and the project's voice/aesthetic rules.

If you discover a NOVEL operational lesson not already in docs/LESSONS.md, note
it in your review body prefixed "LESSON:" so the next ship/groom run folds it in.
Do NOT commit to the PR branch — you are read-only on the diff.

Deliver exactly one verdict:
  clean    → gh pr review $PR --repo $REPO --comment --body "<detailed sign-off>"
  blocking → gh pr review $PR --repo $REPO --request-changes --body "<summary>"
Never --approve. End the session immediately after the gh pr review call.
PROMPT

  cd "$CACHE_DIR/review-checkout" || { echo "review-checkout missing"; continue; }
  git checkout main --quiet; git reset --hard origin/main --quiet
done

git checkout main --quiet 2>/dev/null || true
echo; echo "=== ${SLUG}-review complete $(date -u) ==="
fleet_emit_event run_completed "exit=0" "duration_ms=$(( ( $(date -u +%s) - RUN_STARTED_EPOCH ) * 1000 ))" || true
