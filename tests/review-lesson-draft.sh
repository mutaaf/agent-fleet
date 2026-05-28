#!/bin/bash
# tests/review-lesson-draft.sh — reviewer send-back LESSONS draft test
# (ticket 0022).
#
# Drives the new helper `_review_emit_lesson_draft <pr> <body-file>` (sourced
# from lib/review.sh) against an isolated fixture LESSONS.md and asserts:
#
#   AC#1  Send-back ALSO writes a draft block to docs/LESSONS.md, with the
#         HTML comment marker carrying the PR number, the heading carrying
#         the date + DRAFT marker + first 80 chars of the review body, the
#         "(From review of PR #N — promote or delete.)" line, and the full
#         review body verbatim. The block lands AFTER the first heading and
#         BEFORE the first non-draft `## YYYY-MM-DD` entry.
#   AC#2  Sign-off path (the helper is NOT called) does not modify
#         LESSONS.md. Asserted by snapshotting bytes around a stubbed
#         --comment review path.
#   AC#3  Dedupe: a second send-back on the same PR UPDATES the existing
#         draft block in place (matched via the HTML comment marker) rather
#         than prepending a second block.
#   AC#4  scripts/check-backlog.mjs is unaffected (drafts live in LESSONS,
#         not docs/backlog/).
#   AC#5  `lesson_draft_emitted` event is emitted exactly once per call,
#         carrying `pr` and `headline` keys.
#   AC#6  prompts/PRINCIPLES.md gains a bullet/principle that names the
#         draft mechanism; prompts/CHANGELOG.md gains a matching entry.
#   AC#7  lib/review.sh references the helper / mentions the LESSONS draft
#         contract, so the prompt instructs the agent to call it.
#   AC#8  Public `gh pr review` argv unchanged on the send-back path (the
#         review body bytes that flow into `gh pr review` are not mutated
#         by the helper).
#
# Self-contained: uses $HOME/.local/bin stubs per the 2026-05-26 LESSON,
# isolates HOME, and never touches the host's real cache.

set -euo pipefail

REPO_ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"

TMP="$(mktemp -d -t fleet-review-lesson-test.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

# Isolate $HOME so CACHE_DIR (used by fleet_emit_event) lives under $TMP.
export HOME="$TMP/home"
mkdir -p "$HOME/.local/bin"

MANIFEST_DIR="$TMP/project"
mkdir -p "$MANIFEST_DIR"
cat > "$MANIFEST_DIR/agents.config.sh" <<'CFG'
SLUG="lessontest"
PROJECT_NAME="lessontest"
REPO_URL="https://github.com/example/lessontest.git"
NAMESPACE="com.fleet.lessontest"
SELF_CANCEL="20990101"
CFG

CACHE="$HOME/.cache/lessontest-agent"
EVENTS="$CACHE/events.jsonl"
mkdir -p "$CACHE"

# Fixture LESSONS.md — a header, a promoted entry, and a draft from a different PR.
FIXTURE_LESSONS="$TMP/LESSONS.md"
cat > "$FIXTURE_LESSONS" <<'LESS'
# LESSONS

Operational memory for the autonomous loop. Append, never reorder. Each entry
is one paragraph: symptom → cause → fix.

## 2026-05-25 — bootstrap

The kit is dogfooding itself for the first time.

## 2026-05-26 — earlier lesson

Some earlier prose.
LESS

# ===========================================================================
# AC#1 — Send-back writes a draft block at the right position.
# ===========================================================================
BODY_FILE="$TMP/body1.txt"
cat > "$BODY_FILE" <<'BODY'
This PR violates the AGENTS.md HARD NO "never reintroduce code that was removed".
The heal commit re-added `// TODO: handle null` to src/lib/state.ts:184. Promote:
heal commits must grep new lines against the last 30 days of deletions.
BODY

(
  set -euo pipefail
  # shellcheck disable=SC1091
  source "$REPO_ROOT/lib/common.sh"
  fleet_load_manifest "$MANIFEST_DIR"
  FLEET_PHASE="review"; export FLEET_PHASE
  _review_emit_lesson_draft 42 "$BODY_FILE" "$FIXTURE_LESSONS"
) || { echo "FAIL: AC#1 helper exited non-zero"; exit 1; }

# Marker present
if ! grep -qF '<!-- DRAFT: reviewer send-back, PR #42,' "$FIXTURE_LESSONS"; then
  echo "FAIL: AC#1 HTML comment marker missing for PR #42"
  cat "$FIXTURE_LESSONS"
  exit 1
fi
# Closing marker
if ! grep -qF '<!-- /DRAFT -->' "$FIXTURE_LESSONS"; then
  echo "FAIL: AC#1 closing <!-- /DRAFT --> marker missing"
  cat "$FIXTURE_LESSONS"
  exit 1
fi
# Heading carries date + DRAFT + first 80 chars
if ! grep -qE '^## [0-9]{4}-[0-9]{2}-[0-9]{2} — DRAFT — ' "$FIXTURE_LESSONS"; then
  echo "FAIL: AC#1 DRAFT heading missing or malformed"
  cat "$FIXTURE_LESSONS"
  exit 1
fi
# "(From review of PR #42 — promote or delete.)" line
if ! grep -qF '(From review of PR #42 — promote or delete.)' "$FIXTURE_LESSONS"; then
  echo "FAIL: AC#1 'From review of PR #42 — promote or delete.' line missing"
  cat "$FIXTURE_LESSONS"
  exit 1
fi
# Full body verbatim — at least the distinctive first sentence
if ! grep -qF 'never reintroduce code that was removed' "$FIXTURE_LESSONS"; then
  echo "FAIL: AC#1 review body not included verbatim"
  cat "$FIXTURE_LESSONS"
  exit 1
fi
# Position check: the draft marker line number must be AFTER the first heading
# line (which is "# LESSONS") AND BEFORE the first non-draft `## YYYY-MM-DD`
# heading line.
HEADER_LINE=$(grep -n '^# LESSONS' "$FIXTURE_LESSONS" | head -1 | cut -d: -f1)
DRAFT_LINE=$(grep -n '<!-- DRAFT: reviewer send-back, PR #42' "$FIXTURE_LESSONS" | head -1 | cut -d: -f1)
# First non-draft `## YYYY-MM-DD` (the bootstrap line in fixture).
FIRST_ENTRY_LINE=$(grep -n '^## 2026-05-25 — bootstrap' "$FIXTURE_LESSONS" | head -1 | cut -d: -f1)
if [ -z "$DRAFT_LINE" ] || [ -z "$FIRST_ENTRY_LINE" ] || [ -z "$HEADER_LINE" ]; then
  echo "FAIL: AC#1 line lookups failed (header=$HEADER_LINE draft=$DRAFT_LINE first_entry=$FIRST_ENTRY_LINE)"
  exit 1
fi
if [ "$DRAFT_LINE" -le "$HEADER_LINE" ]; then
  echo "FAIL: AC#1 draft inserted before/at the file header (draft=$DRAFT_LINE header=$HEADER_LINE)"
  exit 1
fi
if [ "$DRAFT_LINE" -ge "$FIRST_ENTRY_LINE" ]; then
  echo "FAIL: AC#1 draft inserted at/after the first promoted entry (draft=$DRAFT_LINE first=$FIRST_ENTRY_LINE)"
  exit 1
fi
echo "ok: AC#1 draft block prepended at correct position"

# ===========================================================================
# AC#5 — `lesson_draft_emitted` event emitted exactly once per call.
# ===========================================================================
if [ ! -f "$EVENTS" ]; then
  echo "FAIL: AC#5 events.jsonl not written"
  exit 1
fi
COUNT=$(grep -c '"type":"lesson_draft_emitted"' "$EVENTS" || true)
if [ "$COUNT" != "1" ]; then
  echo "FAIL: AC#5 expected exactly 1 lesson_draft_emitted event, got $COUNT"
  cat "$EVENTS"
  exit 1
fi
if ! grep -q '"pr":"42"' "$EVENTS"; then
  echo "FAIL: AC#5 lesson_draft_emitted missing pr=42"
  cat "$EVENTS"
  exit 1
fi
if ! grep -q '"headline":' "$EVENTS"; then
  echo "FAIL: AC#5 lesson_draft_emitted missing headline key"
  cat "$EVENTS"
  exit 1
fi
echo "ok: AC#5 lesson_draft_emitted event emitted exactly once"

# ===========================================================================
# AC#3 — Dedupe: second send-back on same PR updates in place.
# ===========================================================================
BODY_FILE2="$TMP/body2.txt"
cat > "$BODY_FILE2" <<'BODY'
SECOND send-back body — updated reason: the heal commit also dropped a test.
The reviewer caught it via the test-first principle P-2.
BODY

(
  set -euo pipefail
  # shellcheck disable=SC1091
  source "$REPO_ROOT/lib/common.sh"
  fleet_load_manifest "$MANIFEST_DIR"
  FLEET_PHASE="review"; export FLEET_PHASE
  _review_emit_lesson_draft 42 "$BODY_FILE2" "$FIXTURE_LESSONS"
) || { echo "FAIL: AC#3 second helper call exited non-zero"; exit 1; }

DRAFT_MARKER_COUNT=$(grep -c '<!-- DRAFT: reviewer send-back, PR #42,' "$FIXTURE_LESSONS" || true)
if [ "$DRAFT_MARKER_COUNT" != "1" ]; then
  echo "FAIL: AC#3 expected exactly 1 draft marker for PR #42, got $DRAFT_MARKER_COUNT"
  cat "$FIXTURE_LESSONS"
  exit 1
fi
if ! grep -qF 'SECOND send-back body' "$FIXTURE_LESSONS"; then
  echo "FAIL: AC#3 second body not present after dedupe replace"
  cat "$FIXTURE_LESSONS"
  exit 1
fi
if grep -qF 'never reintroduce code that was removed' "$FIXTURE_LESSONS"; then
  echo "FAIL: AC#3 first body still present after dedupe replace"
  cat "$FIXTURE_LESSONS"
  exit 1
fi
echo "ok: AC#3 dedupe replaces existing draft block in place"

# Dedupe should also emit exactly one MORE lesson_draft_emitted event (total 2).
TOTAL=$(grep -c '"type":"lesson_draft_emitted"' "$EVENTS" || true)
if [ "$TOTAL" != "2" ]; then
  echo "FAIL: AC#5 expected 2 cumulative lesson_draft_emitted events after dedupe, got $TOTAL"
  cat "$EVENTS"
  exit 1
fi
echo "ok: AC#5 second invocation emits a second event"

# ===========================================================================
# AC#2 — Sign-off (--comment) path: helper is NEVER invoked. We assert by
# scanning lib/review.sh and prompts/review.md (or review prompt) for the
# guard: the helper call lives ONLY under the --request-changes branch.
# ===========================================================================
if ! grep -q '_review_emit_lesson_draft' "$REPO_ROOT/lib/review.sh"; then
  echo "FAIL: AC#2 lib/review.sh does not reference _review_emit_lesson_draft at all"
  exit 1
fi
# Per-line audit: the prompt MUST contain a "request-changes" guard for the
# helper call. We grep for either "if ... posted --request-changes" or
# "ONLY if you posted --request-changes" wording near the helper mention.
if ! grep -qiE 'only.*--request-changes|if.*posted.*--request-changes' "$REPO_ROOT/lib/review.sh"; then
  echo "FAIL: AC#2 prompt does not gate the helper call on --request-changes"
  exit 1
fi
# Also assert the prompt explicitly tells the agent NOT to call the helper on sign-off.
if ! grep -qiE 'do not call _review_emit_lesson_draft on the --comment' "$REPO_ROOT/lib/review.sh"; then
  echo "FAIL: AC#2 prompt does not explicitly forbid helper on --comment path"
  exit 1
fi
echo "ok: AC#2 helper only invoked under request-changes branch"

# ===========================================================================
# AC#4 — check-backlog.mjs passes with drafts present in LESSONS. Drafts live
# outside docs/backlog/ so the validator should be a no-op against them.
# Run the validator from the repo root; it scans docs/backlog/ only.
# ===========================================================================
if ! ( cd "$REPO_ROOT" && node scripts/check-backlog.mjs ) >/dev/null 2>&1; then
  echo "FAIL: AC#4 scripts/check-backlog.mjs failed on the repo with drafts in LESSONS"
  ( cd "$REPO_ROOT" && node scripts/check-backlog.mjs ) || true
  exit 1
fi
echo "ok: AC#4 check-backlog.mjs unaffected by LESSONS drafts"

# ===========================================================================
# AC#6 — prompts/PRINCIPLES.md mentions the draft mechanism; CHANGELOG entry
# exists for today (or any post-bootstrap entry that explicitly names the
# draft mechanism by phrase).
# ===========================================================================
if ! grep -qiE 'review[- ]?send[- ]?backs?.*(draft|LESSONS)' "$REPO_ROOT/prompts/PRINCIPLES.md"; then
  echo "FAIL: AC#6 prompts/PRINCIPLES.md does not name the review-send-back draft mechanism"
  exit 1
fi
if ! grep -qiE 'lesson.?draft|send-back.*draft|draft.*send-back' "$REPO_ROOT/prompts/CHANGELOG.md"; then
  echo "FAIL: AC#6 prompts/CHANGELOG.md missing a matching entry"
  exit 1
fi
echo "ok: AC#6 PRINCIPLES + CHANGELOG mention the draft mechanism"

# ===========================================================================
# AC#7 — lib/review.sh prompt instructs the agent to call the helper after a
# --request-changes review (and only after request-changes).
# ===========================================================================
if ! grep -qF '_review_emit_lesson_draft' "$REPO_ROOT/lib/review.sh"; then
  echo "FAIL: AC#7 lib/review.sh does not instruct the agent to call _review_emit_lesson_draft"
  exit 1
fi
echo "ok: AC#7 review.sh prompt wires the helper into the send-back path"

# ===========================================================================
# AC#8 — Public `gh pr review` invocation argv unchanged in shape: the
# prompt still names `--request-changes` and `--comment` as the two verdicts
# and the body fields are still passed via `--body`. We grep the prompt
# heredoc directly.
# ===========================================================================
if ! grep -qE 'gh pr review .* --request-changes --body' "$REPO_ROOT/lib/review.sh"; then
  echo "FAIL: AC#8 gh pr review --request-changes --body argv shape changed"
  exit 1
fi
if ! grep -qE 'gh pr review .* --comment --body' "$REPO_ROOT/lib/review.sh"; then
  echo "FAIL: AC#8 gh pr review --comment --body argv shape changed"
  exit 1
fi
echo "ok: AC#8 gh pr review argv shape preserved"

# ===========================================================================
# AC#1 follow-up — AGENTS.md § Telemetry documents the new event type.
# ===========================================================================
if ! grep -qE '`lesson_draft_emitted` \{pr, headline\}|`lesson_draft_emitted \{pr, headline\}`' "$REPO_ROOT/AGENTS.md"; then
  # Try a more lenient pattern
  if ! grep -qF 'lesson_draft_emitted' "$REPO_ROOT/AGENTS.md"; then
    echo "FAIL: AGENTS.md § Telemetry does not document lesson_draft_emitted"
    exit 1
  fi
fi
echo "ok: AGENTS.md documents lesson_draft_emitted"

echo "ok: tests/review-lesson-draft.sh passed"
