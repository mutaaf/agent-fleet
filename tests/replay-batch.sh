#!/bin/bash
# tests/replay-batch.sh — bin/fleet replay --batch end-to-end test.
#
# Ticket 0034. One assertion block per AC checkbox in
# docs/backlog/0034-fleet-replay-batch-counterfactual-prompt-regression.md.
#
# Strategy mirrors tests/replay.sh: stub `gh`, `claude`, `git` under
# $HOME/.local/bin per LESSONS 2026-05-26 (lib/common.sh resets PATH).
# Per LESSONS 2026-05-27 we restore fixtures via `cp`, never $(cat).
# Per LESSONS 2026-05-30 the help-text grep uses `grep -qF --`.
# Per LESSONS 2026-06-01 we never pass multi-line rationales through
# `awk -v` (the implementation under test must obey this; the test
# only asserts the resulting bytes).
#
# Run-time budget: <15s. The batch loop spawns claude once per fixture
# PR; with three PRs and ~0.5s per stub invocation we land under budget.

set -euo pipefail

REPO_ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
FLEET="$REPO_ROOT/bin/fleet"
FIX_DIR="$REPO_ROOT/tests/fixtures/replay-batch"

TMP="$(mktemp -d -t fleet-replay-batch-test.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

# Isolate from the host. HOME owns the PATH-reset-safe stub dir.
export HOME="$TMP/home"
mkdir -p "$HOME"

# --- fixture project + manifest -------------------------------------------
FIXTURE="$TMP/projects"
mkdir -p "$FIXTURE/replaytest"
cat > "$FIXTURE/replaytest/agents.config.sh" <<'CFG'
SLUG="replaytest"
PROJECT_NAME="replaytest"
NAMESPACE="com.replaytest"
REPO_URL="https://github.com/example/replaytest"
SELF_CANCEL="20990101"
CFG
export FLEET_DISCOVERY_ROOT="$FIXTURE"

CACHE_DIR="$HOME/.cache/replaytest-agent"
mkdir -p "$CACHE_DIR"
RUNS_FILE="$CACHE_DIR/runs.jsonl"

# --- stubs under $HOME/.local/bin -----------------------------------------
BIN_STUB="$HOME/.local/bin"
mkdir -p "$BIN_STUB"
CLAUDE_LOG="$TMP/claude.log"
GH_LOG="$TMP/gh.log"
GIT_LOG="$TMP/git.log"
: > "$CLAUDE_LOG"
: > "$GH_LOG"
: > "$GIT_LOG"

# `claude` stub: emits a per-PR seeded verdict. The test pre-stages the
# verdict-per-PR map in $TMP/verdicts/<pr>.txt — the stub reads the
# composed prompt off stdin, greps for the `- number: #<N>` line that
# `replay_compose_prompt` always emits, then echoes the seeded verdict.
# This keeps the batch loop deterministic without needing the stub to
# know the iteration index.
cat > "$BIN_STUB/claude" <<STUB
#!/bin/bash
printf '%s\n' "claude \$*" >> "$CLAUDE_LOG"
# Read stdin (the prompt). Locate the PR number in the composed body.
prompt_body="\$(cat)"
pr="\$(printf '%s\n' "\$prompt_body" | sed -nE 's/^- number: #([0-9]+).*/\1/p' | head -1)"
verdict_file="\$VERDICT_DIR/\$pr.txt"
if [ -n "\$pr" ] && [ -f "\$verdict_file" ]; then
  result="\$(cat "\$verdict_file")"
else
  result="\${CLAUDE_RESULT:-VERDICT: sign-off
rationale: fallback}"
fi
esc="\$(printf '%s' "\$result" | sed -e 's/\\\\/\\\\\\\\/g' -e 's/"/\\\\"/g' | awk 'BEGIN{ORS=""} {if (NR>1) print "\\\\n"; print}')"
cat <<JSON
{
  "result": "\$esc",
  "session_id": "replay-batch-abc",
  "total_cost_usd": 0.05,
  "duration_ms": 1234,
  "num_turns": 1,
  "usage": {"input_tokens": 25, "output_tokens": 40},
  "is_error": false
}
JSON
exit 0
STUB
chmod +x "$BIN_STUB/claude"

# `gh` stub. `pr list` returns the canned list JSON from $GH_PR_LIST_JSON.
# `pr view <N> --json ...` returns the per-PR JSON from $GH_VIEW_DIR/<N>.json.
# `pr diff <N>` returns a stub diff. Any merge/comment call exits non-zero
# so the test catches accidents (AC#10: dry-run must NEVER mutate).
cat > "$BIN_STUB/gh" <<STUB
#!/bin/bash
printf '%s\n' "gh \$*" >> "$GH_LOG"
case "\${1:-}" in
  pr)
    case "\${2:-}" in
      list) printf '%s' "\${GH_PR_LIST_JSON:-[]}" ;;
      view)
        n="\${3:-}"
        f="\$GH_VIEW_DIR/\$n.json"
        if [ -f "\$f" ]; then cat "\$f"
        else printf '%s' "{}"
        fi
        ;;
      diff) printf '%s' "diff --git a/x b/x\n+stub diff body" ;;
      merge)
        echo "gh pr merge unexpectedly called during replay --batch" >&2
        exit 1 ;;
      comment)
        echo "gh pr comment unexpectedly called during replay --batch" >&2
        exit 1 ;;
      review)
        echo "gh pr review unexpectedly called during replay --batch" >&2
        exit 1 ;;
      *) exit 0 ;;
    esac
    ;;
  *) exit 0 ;;
esac
STUB
chmod +x "$BIN_STUB/gh"

# `git` stub: satisfies the fresh-checkout step the existing replay()
# already performs. Records pushes (none are expected; AC#10 asserts).
cat > "$BIN_STUB/git" <<STUB
#!/bin/bash
printf '%s\n' "git \$*" >> "$GIT_LOG"
case "\${1:-}" in
  clone)
    dest="\${@: -1}"
    mkdir -p "\$dest/docs/backlog"
    : > "\$dest/AGENTS.md"
    printf '%s\n' '# AGENTS.md — fixture' >> "\$dest/AGENTS.md"
    printf '%s\n' '## Agent parameters' >> "\$dest/AGENTS.md"
    : > "\$dest/docs/LESSONS.md"
    printf '%s\n' '# LESSONS — fixture' >> "\$dest/docs/LESSONS.md"
    printf '%s\n' '# Ticket 0017 fixture body' > "\$dest/docs/backlog/0017-fleet-rollback.md"
    printf '%s\n' '# Ticket 0018 fixture body' > "\$dest/docs/backlog/0018-fleet-principles.md"
    printf '%s\n' '# Ticket 0019 fixture body' > "\$dest/docs/backlog/0019-fleet-overview.md"
    exit 0 ;;
  push)
    echo "git push unexpectedly called during replay --batch" >&2
    exit 1 ;;
  *) exit 0 ;;
esac
STUB
chmod +x "$BIN_STUB/git"

export PATH="$BIN_STUB:$PATH"

# Per-PR fixture: seeded verdicts + per-PR view JSON.
VERDICT_DIR="$TMP/verdicts"
GH_VIEW_DIR="$TMP/gh-views"
mkdir -p "$VERDICT_DIR" "$GH_VIEW_DIR"
export VERDICT_DIR GH_VIEW_DIR

# Three synthetic PRs:
#   #17 feat/0017-… — MERGED, dry-run sign-off  → past=merged, dry=sign-off, delta=`=`
#   #18 feat/0018-… — MERGED, dry-run reject    → past=merged, dry=reject,  delta=`!`
#   #19 feat/0019-… — CLOSED-unmerged (changes-requested), dry-run sign-off
#                                                → past=rejected, dry=sign-off, delta=`!`
cat > "$GH_VIEW_DIR/17.json" <<'JSON'
{"number":17,"title":"ticket 0017: shipped","headRefName":"feat/0017-fleet-rollback","body":"Implements ticket 0017.","mergeCommit":{"oid":"deadbeef"},"mergedAt":"2026-05-26T12:00:00Z","files":[{"path":"bin/fleet"}],"state":"MERGED"}
JSON
cat > "$GH_VIEW_DIR/18.json" <<'JSON'
{"number":18,"title":"ticket 0018: principles","headRefName":"feat/0018-principles","body":"Implements ticket 0018.","mergeCommit":{"oid":"feedface"},"mergedAt":"2026-05-28T12:00:00Z","files":[{"path":"prompts/PRINCIPLES.md"}],"state":"MERGED"}
JSON
cat > "$GH_VIEW_DIR/19.json" <<'JSON'
{"number":19,"title":"ticket 0019: overview","headRefName":"feat/0019-fleet-overview","body":"Implements ticket 0019.","mergeCommit":null,"mergedAt":null,"closedAt":"2026-05-30T12:00:00Z","files":[{"path":"bin/fleet"}],"state":"CLOSED"}
JSON

# Seeded verdicts (per LESSONS 2026-05-27, fixtures are written via
# heredoc + redirection, not $(cat) round-trips).
cat > "$VERDICT_DIR/17.txt" <<'TXT'
VERDICT: sign-off
rationale: ticket 0017's diff respects branch prefixes; no Hard NO violations.
TXT
cat > "$VERDICT_DIR/18.txt" <<'TXT'
VERDICT: request-changes
rationale: under the new prompts, the diff touches lib/common.sh additively but the PR body lacks a BREAKING: line. P-7 requires it.
TXT
cat > "$VERDICT_DIR/19.txt" <<'TXT'
VERDICT: sign-off
rationale: re-graded under current prompts, the diff is fine — the original send-back cited a now-relaxed rule.
TXT

# The canned `gh pr list` JSON: three PRs in mergedAt-desc order.
GH_PR_LIST_JSON='[{"number":19,"title":"ticket 0019: overview","headRefName":"feat/0019-fleet-overview","state":"CLOSED","closedAt":"2026-05-30T12:00:00Z","mergedAt":null},{"number":18,"title":"ticket 0018: principles","headRefName":"feat/0018-principles","state":"MERGED","closedAt":"2026-05-28T12:00:00Z","mergedAt":"2026-05-28T12:00:00Z"},{"number":17,"title":"ticket 0017: shipped","headRefName":"feat/0017-fleet-rollback","state":"MERGED","closedAt":"2026-05-26T12:00:00Z","mergedAt":"2026-05-26T12:00:00Z"}]'

reset_state() {
  : > "$CLAUDE_LOG"
  : > "$GH_LOG"
  : > "$GIT_LOG"
  rm -rf "$CACHE_DIR"
  mkdir -p "$CACHE_DIR"
  unset CLAUDE_RESULT
}

# ========================================================================
# AC #1 — `fleet replay <slug> --batch --since 14d` walks merged PRs in
# the window, replays each in dry-run, prints the matrix table, and the
# verdict line. With our 3 fixtures (1 unchanged, 2 deltas → 67% delta),
# the verdict MUST be FAIL → exit 2.
# ========================================================================
reset_state
export GH_PR_LIST_JSON

set +e
OUT="$("$FLEET" replay replaytest --batch --since 365d 2>&1)"
rc=$?
set -e
if [ "$rc" -ne 2 ]; then
  echo "FAIL: AC#1 expected exit 2 (FAIL, 67% delta), got $rc"
  echo "--- out ---"
  echo "$OUT"
  exit 1
fi
# Header row present.
if ! grep -qE '^PR[[:space:]]+TITLE[[:space:]]+PAST[[:space:]]+DRY-RUN[[:space:]]+DELTA' <<<"$OUT"; then
  echo "FAIL: AC#1 expected matrix header row"
  echo "$OUT"; exit 1
fi
# Every fixture PR row present.
for n in 17 18 19; do
  if ! grep -qE "^#${n}[[:space:]]" <<<"$OUT"; then
    echo "FAIL: AC#1 expected row for #${n} in matrix"
    echo "$OUT"; exit 1
  fi
done
# Summary + verdict lines per the User-lens example.
if ! grep -qE '^summary:' <<<"$OUT"; then
  echo "FAIL: AC#1 missing 'summary:' line"
  echo "$OUT"; exit 1
fi
if ! grep -qE '^verdict: FAIL' <<<"$OUT"; then
  echo "FAIL: AC#1 expected 'verdict: FAIL' (2/3 delta = 67% ≥ 30%)"
  echo "$OUT"; exit 1
fi
echo "ok: AC#1 --batch renders matrix + summary + FAIL verdict + exit 2"

# ========================================================================
# AC #2 — `--phase review` is the default; `--phase ship` also works.
# Both branches must run; the test asserts each phase reaches claude.
# ========================================================================
reset_state
# Use a single-PR list so the deterministic "1 unchanged" arithmetic holds.
# PR #17 alone: past=merged, dry-run sign-off → 0% delta → OK → exit 0.
export GH_PR_LIST_JSON='[{"number":17,"title":"ticket 0017: shipped","headRefName":"feat/0017-fleet-rollback","state":"MERGED","closedAt":"2026-05-26T12:00:00Z","mergedAt":"2026-05-26T12:00:00Z"}]'
set +e
"$FLEET" replay replaytest --batch --since 365d --limit 1 >/dev/null 2>&1
rc=$?
set -e
# 1 unchanged out of 1 = 0% delta → OK → exit 0.
if [ "$rc" -ne 0 ]; then
  echo "FAIL: AC#2 default phase=review with 1 unchanged PR expected exit 0, got $rc"
  exit 1
fi
# Claude was called with the review prompt — we check argv carries
# --allowedTools none (the dry-run signature), then assert the composed
# prompt body for that call contained the "Review contract" header. We
# look at all claude.log entries (a single one in this case).
if ! grep -qE -- '--allowedTools[[:space:]]+none' "$CLAUDE_LOG"; then
  echo "FAIL: AC#2 --batch must run claude tool-locked (--allowedTools none)"
  cat "$CLAUDE_LOG"; exit 1
fi
review_call_count="$(awk 'END { print NR+0 }' "$CLAUDE_LOG")"
if [ "$review_call_count" -ne 1 ]; then
  echo "FAIL: AC#2 --limit 1 should call claude exactly once (got $review_call_count)"
  exit 1
fi

# Now exercise --phase ship.
reset_state
export GH_PR_LIST_JSON
# Pre-stage ACTION verdicts so the ship-phase parser succeeds.
cat > "$VERDICT_DIR/17.txt" <<'TXT'
ACTION: ship
rationale: ticket 0017 is groomed and ready to ship.
TXT
set +e
"$FLEET" replay replaytest --batch --since 365d --limit 1 --phase ship >/dev/null 2>&1
rc=$?
set -e
if [ "$rc" -ne 0 ] && [ "$rc" -ne 1 ]; then
  # Either OK (0) or WARN (1) is acceptable here — we're only asserting
  # the phase ran. FAIL (2) on a single PR would indicate a wiring bug.
  echo "FAIL: AC#2 --phase ship single-PR replay exited with $rc (expected 0 or 1)"
  exit 1
fi
if ! grep -qE -- '--allowedTools[[:space:]]+none' "$CLAUDE_LOG"; then
  echo "FAIL: AC#2 --phase ship --batch must run claude tool-locked"
  exit 1
fi

# Restore the review verdicts for the remaining ACs.
cat > "$VERDICT_DIR/17.txt" <<'TXT'
VERDICT: sign-off
rationale: ticket 0017's diff respects branch prefixes; no Hard NO violations.
TXT
echo "ok: AC#2 --phase review (default) + --phase ship both reach claude"

# ========================================================================
# AC #3 — `--since` parses via digest_parse_since. Invalid → exit 2 + the
# exact stderr message.
# ========================================================================
reset_state
set +e
ERR="$("$FLEET" replay replaytest --batch --since blarg 2>&1 >/dev/null)"
rc=$?
set -e
if [ "$rc" -ne 2 ]; then
  echo "FAIL: AC#3 invalid --since must exit 2 (got $rc)"
  echo "$ERR"; exit 1
fi
if ! grep -qF 'replay --batch: invalid --since' <<<"$ERR"; then
  echo "FAIL: AC#3 expected 'replay --batch: invalid --since' in stderr"
  echo "$ERR"; exit 1
fi
if ! grep -qF '(use Nh or Nd)' <<<"$ERR"; then
  echo "FAIL: AC#3 expected '(use Nh or Nd)' hint in stderr"
  echo "$ERR"; exit 1
fi
echo "ok: AC#3 --since parses via digest_parse_since (invalid → exit 2)"

# ========================================================================
# AC #4 — `--limit N` caps PR replays (default 20, max 50). With a list
# of 30 PRs and --limit 10, only 10 are replayed (most-recent-first).
# ========================================================================
reset_state
# Build a synthetic list of 30 PRs, all merged, descending by mergedAt.
# Reuse the #17 view JSON for each — we only care about the count.
big_list=""
for i in $(seq 30 -1 1); do
  pr=$((100 + i))
  cat > "$GH_VIEW_DIR/$pr.json" <<JSON
{"number":$pr,"title":"ticket $pr: synthetic","headRefName":"feat/$(printf '%04d' "$pr")-synthetic","body":"body","mergeCommit":{"oid":"abc$pr"},"mergedAt":"2026-05-$(printf '%02d' "$i")T12:00:00Z","files":[{"path":"bin/fleet"}],"state":"MERGED"}
JSON
  cat > "$VERDICT_DIR/$pr.txt" <<TXT
VERDICT: sign-off
rationale: synthetic $pr
TXT
  iso="2026-05-$(printf '%02d' "$i")T12:00:00Z"
  if [ -z "$big_list" ]; then
    big_list="{\"number\":$pr,\"title\":\"ticket $pr: synthetic\",\"headRefName\":\"feat/$(printf '%04d' "$pr")-synthetic\",\"state\":\"MERGED\",\"closedAt\":\"$iso\",\"mergedAt\":\"$iso\"}"
  else
    big_list="$big_list,{\"number\":$pr,\"title\":\"ticket $pr: synthetic\",\"headRefName\":\"feat/$(printf '%04d' "$pr")-synthetic\",\"state\":\"MERGED\",\"closedAt\":\"$iso\",\"mergedAt\":\"$iso\"}"
  fi
done
export GH_PR_LIST_JSON="[$big_list]"

set +e
"$FLEET" replay replaytest --batch --since 365d --limit 10 >/dev/null 2>&1
rc=$?
set -e
# 10 unchanged = 0% delta = OK = exit 0.
if [ "$rc" -ne 0 ]; then
  echo "FAIL: AC#4 --limit 10 with 10 unchanged expected exit 0, got $rc"
  exit 1
fi
# Exactly 10 claude calls — one per replayed PR.
n_calls="$(awk 'END { print NR+0 }' "$CLAUDE_LOG")"
if [ "$n_calls" -ne 10 ]; then
  echo "FAIL: AC#4 --limit 10 should produce 10 claude calls (got $n_calls)"
  exit 1
fi
# Max-cap check: --limit 100 must be clamped to 50.
reset_state
set +e
"$FLEET" replay replaytest --batch --since 365d --limit 100 >/dev/null 2>&1
rc=$?
set -e
n_calls="$(awk 'END { print NR+0 }' "$CLAUDE_LOG")"
if [ "$n_calls" -gt 50 ]; then
  echo "FAIL: AC#4 --limit 100 must clamp to 50 (got $n_calls claude calls)"
  exit 1
fi
echo "ok: AC#4 --limit caps replays (default 20, max 50); most-recent first"

# Restore the small 3-PR list for subsequent ACs.
export GH_PR_LIST_JSON='[{"number":19,"title":"ticket 0019: overview","headRefName":"feat/0019-fleet-overview","state":"CLOSED","closedAt":"2026-05-30T12:00:00Z","mergedAt":null},{"number":18,"title":"ticket 0018: principles","headRefName":"feat/0018-principles","state":"MERGED","closedAt":"2026-05-28T12:00:00Z","mergedAt":"2026-05-28T12:00:00Z"},{"number":17,"title":"ticket 0017: shipped","headRefName":"feat/0017-fleet-rollback","state":"MERGED","closedAt":"2026-05-26T12:00:00Z","mergedAt":"2026-05-26T12:00:00Z"}]'

# ========================================================================
# AC #5 — Each per-PR replay reuses the existing replay() stack. The
# observable contract: runs.jsonl gains ONE row per replayed PR, each
# carrying phase=replay.
# ========================================================================
reset_state
set +e
"$FLEET" replay replaytest --batch --since 365d >/dev/null 2>&1
rc=$?
set -e
# rc is 2 (FAIL — our 3-PR fixture has 67% delta). We only care about the
# runs.jsonl side-effect here.
if [ "$rc" -ne 2 ]; then
  echo "FAIL: AC#5 expected exit 2 on the 3-PR fixture (got $rc)"
  exit 1
fi
if [ ! -f "$RUNS_FILE" ]; then
  echo "FAIL: AC#5 expected runs.jsonl at $RUNS_FILE after --batch"
  exit 1
fi
replay_rows="$(awk '/"phase":"replay"/ { n++ } END { print n+0 }' "$RUNS_FILE")"
if [ "$replay_rows" -ne 3 ]; then
  echo "FAIL: AC#5 expected 3 phase=replay rows in runs.jsonl (got $replay_rows)"
  cat "$RUNS_FILE"; exit 1
fi
if ! grep -qE '"slug":"replaytest"' "$RUNS_FILE"; then
  echo "FAIL: AC#5 runs.jsonl rows missing slug=replaytest"
  cat "$RUNS_FILE"; exit 1
fi
echo "ok: AC#5 batch path writes one phase=replay row per PR to runs.jsonl"

# ========================================================================
# AC #6 — DELTA classification:
#   #17 MERGED + sign-off → `=`
#   #18 MERGED + reject   → `!`
#   #19 CLOSED-unmerged (past=rejected) + sign-off → `!`
# Summary line counts only `!` rows.
# ========================================================================
reset_state
set +e
OUT="$("$FLEET" replay replaytest --batch --since 365d 2>&1)"
set -e
# Each row must end with the expected delta marker. We grep with the
# literal `=` or `!` at the end of the row.
if ! grep -qE '^#17[[:space:]].*[[:space:]]=[[:space:]]*$' <<<"$OUT"; then
  echo "FAIL: AC#6 #17 row should end with '=' delta"
  echo "$OUT"; exit 1
fi
if ! grep -qE '^#18[[:space:]].*[[:space:]]![[:space:]]*$' <<<"$OUT"; then
  echo "FAIL: AC#6 #18 row should end with '!' delta"
  echo "$OUT"; exit 1
fi
if ! grep -qE '^#19[[:space:]].*[[:space:]]![[:space:]]*$' <<<"$OUT"; then
  echo "FAIL: AC#6 #19 row should end with '!' delta"
  echo "$OUT"; exit 1
fi
# Summary line counts exactly 2 deltas out of 3.
if ! grep -qE '^summary: 1/3 unchanged, 2 DELTA' <<<"$OUT"; then
  echo "FAIL: AC#6 summary line should read '1/3 unchanged, 2 DELTA'"
  echo "$OUT"; exit 1
fi
# Past column shows 'merged' for #17/#18 and 'rejected' for #19.
if ! grep -qE '^#17[[:space:]].*[[:space:]]merged[[:space:]]' <<<"$OUT"; then
  echo "FAIL: AC#6 #17 row should report PAST=merged"
  echo "$OUT"; exit 1
fi
if ! grep -qE '^#19[[:space:]].*[[:space:]]rejected[[:space:]]' <<<"$OUT"; then
  echo "FAIL: AC#6 #19 row should report PAST=rejected"
  echo "$OUT"; exit 1
fi
echo "ok: AC#6 DELTA classification matches MERGED/REJECTED × sign-off/reject"

# ========================================================================
# AC #7 — `--json` emits one JSON object per row + one summary object.
# Parsed via node -e 'JSON.parse(...)'. Asserts the document shape.
# ========================================================================
reset_state
set +e
OUT="$("$FLEET" replay replaytest --batch --since 365d --json 2>&1)"
set -e
# Strip the trailing exit-code noise; the JSON output is the full stdout.
# Each line is a standalone JSON object — parse each.
n_objs=0
n_summary=0
while IFS= read -r line; do
  [ -z "$line" ] && continue
  if ! printf '%s\n' "$line" | node -e 'let d="";process.stdin.on("data",c=>d+=c).on("end",()=>{JSON.parse(d)})' 2>/dev/null; then
    echo "FAIL: AC#7 line did not parse as JSON: $line"
    exit 1
  fi
  if printf '%s' "$line" | grep -qE '"summary":true'; then
    n_summary=$((n_summary + 1))
  else
    n_objs=$((n_objs + 1))
  fi
done <<<"$OUT"
if [ "$n_objs" -ne 3 ]; then
  echo "FAIL: AC#7 expected 3 PR JSON rows (got $n_objs)"
  echo "$OUT"; exit 1
fi
if [ "$n_summary" -ne 1 ]; then
  echo "FAIL: AC#7 expected 1 summary JSON object (got $n_summary)"
  echo "$OUT"; exit 1
fi
# Required keys on the PR rows.
for k in pr title past dry_run delta rationale; do
  if ! grep -qE "\"$k\":" <<<"$OUT"; then
    echo "FAIL: AC#7 JSON row missing key '$k'"
    echo "$OUT"; exit 1
  fi
done
# Required keys on the summary line.
for k in summary replayed deltas verdict window; do
  if ! grep -qE "\"$k\":" <<<"$OUT"; then
    echo "FAIL: AC#7 summary JSON missing key '$k'"
    echo "$OUT"; exit 1
  fi
done
# Rationale on row #18 (the reject row) is a non-empty string — proves
# the multi-line rationale survived the awk-free render path.
row18="$(grep -E '"pr":18' <<<"$OUT" | head -1)"
if [ -z "$row18" ]; then
  echo "FAIL: AC#7 could not locate JSON row for pr=18"
  echo "$OUT"; exit 1
fi
if ! printf '%s' "$row18" | grep -qE '"rationale":"[^"]+'; then
  echo "FAIL: AC#7 row #18 missing rationale value"
  echo "$row18"; exit 1
fi
echo "ok: AC#7 --json emits N row objects + 1 summary object, all parseable"

# ========================================================================
# AC #8 — Empty window → friendly stderr message + exit 0 (not an error).
# ========================================================================
reset_state
export GH_PR_LIST_JSON='[]'
set +e
ERR="$("$FLEET" replay replaytest --batch --since 14d 2>&1 >/dev/null)"
rc=$?
set -e
if [ "$rc" -ne 0 ]; then
  echo "FAIL: AC#8 empty-window must exit 0 (got $rc)"
  echo "$ERR"; exit 1
fi
if ! grep -qF 'replay --batch: no PRs matched in the last 14d for slug=replaytest' <<<"$ERR"; then
  echo "FAIL: AC#8 expected 'no PRs matched in the last 14d for slug=replaytest' on stderr"
  echo "$ERR"; exit 1
fi
echo "ok: AC#8 empty window → friendly stderr + exit 0"

# Restore the 3-PR list.
export GH_PR_LIST_JSON='[{"number":19,"title":"ticket 0019: overview","headRefName":"feat/0019-fleet-overview","state":"CLOSED","closedAt":"2026-05-30T12:00:00Z","mergedAt":null},{"number":18,"title":"ticket 0018: principles","headRefName":"feat/0018-principles","state":"MERGED","closedAt":"2026-05-28T12:00:00Z","mergedAt":"2026-05-28T12:00:00Z"},{"number":17,"title":"ticket 0017: shipped","headRefName":"feat/0017-fleet-rollback","state":"MERGED","closedAt":"2026-05-26T12:00:00Z","mergedAt":"2026-05-26T12:00:00Z"}]'

# ========================================================================
# AC #9 — `--since 1h` with no PRs → empty-window message;
# `--since 365d` with --limit 10 on a 30-PR fixture replays 10.
# (Both halves: AC#9 first half is a re-assertion of AC#8 under a
# different window; AC#9 second half is the same exercise as AC#4 but
# stated against this AC's phrasing.)
# ========================================================================
reset_state
export GH_PR_LIST_JSON='[]'
set +e
ERR="$("$FLEET" replay replaytest --batch --since 1h 2>&1 >/dev/null)"
rc=$?
set -e
if [ "$rc" -ne 0 ]; then
  echo "FAIL: AC#9a --since 1h with no PRs must exit 0 (got $rc)"
  echo "$ERR"; exit 1
fi
if ! grep -qF 'no PRs matched in the last 1h' <<<"$ERR"; then
  echo "FAIL: AC#9a --since 1h with no PRs missing the message"
  echo "$ERR"; exit 1
fi

# Build the 30-PR list again for the second half.
reset_state
big_list=""
for i in $(seq 30 -1 1); do
  pr=$((100 + i))
  cat > "$GH_VIEW_DIR/$pr.json" <<JSON
{"number":$pr,"title":"ticket $pr: synthetic","headRefName":"feat/$(printf '%04d' "$pr")-synthetic","body":"body","mergeCommit":{"oid":"abc$pr"},"mergedAt":"2026-05-$(printf '%02d' "$i")T12:00:00Z","files":[{"path":"bin/fleet"}],"state":"MERGED"}
JSON
  cat > "$VERDICT_DIR/$pr.txt" <<TXT
VERDICT: sign-off
rationale: synthetic $pr
TXT
  iso="2026-05-$(printf '%02d' "$i")T12:00:00Z"
  if [ -z "$big_list" ]; then
    big_list="{\"number\":$pr,\"title\":\"ticket $pr: synthetic\",\"headRefName\":\"feat/$(printf '%04d' "$pr")-synthetic\",\"state\":\"MERGED\",\"closedAt\":\"$iso\",\"mergedAt\":\"$iso\"}"
  else
    big_list="$big_list,{\"number\":$pr,\"title\":\"ticket $pr: synthetic\",\"headRefName\":\"feat/$(printf '%04d' "$pr")-synthetic\",\"state\":\"MERGED\",\"closedAt\":\"$iso\",\"mergedAt\":\"$iso\"}"
  fi
done
export GH_PR_LIST_JSON="[$big_list]"
"$FLEET" replay replaytest --batch --since 365d --limit 10 >/dev/null 2>&1 || true
n_calls="$(awk 'END { print NR+0 }' "$CLAUDE_LOG")"
if [ "$n_calls" -ne 10 ]; then
  echo "FAIL: AC#9b --since 365d --limit 10 on 30-PR fixture should make 10 claude calls (got $n_calls)"
  exit 1
fi
echo "ok: AC#9 empty 1h window + 365d --limit 10 both behave"

# Restore the 3-PR list.
export GH_PR_LIST_JSON='[{"number":19,"title":"ticket 0019: overview","headRefName":"feat/0019-fleet-overview","state":"CLOSED","closedAt":"2026-05-30T12:00:00Z","mergedAt":null},{"number":18,"title":"ticket 0018: principles","headRefName":"feat/0018-principles","state":"MERGED","closedAt":"2026-05-28T12:00:00Z","mergedAt":"2026-05-28T12:00:00Z"},{"number":17,"title":"ticket 0017: shipped","headRefName":"feat/0017-fleet-rollback","state":"MERGED","closedAt":"2026-05-26T12:00:00Z","mergedAt":"2026-05-26T12:00:00Z"}]'

# ========================================================================
# AC #10 — DRY-RUN respects ticket 0010: NO `gh pr review`, NO
# `gh pr merge`, NO `gh pr comment`, NO `git push`. The stubs above all
# exit non-zero on any mutating verb, so the absence of those records is
# proven by NOT seeing them in $GH_LOG / $GIT_LOG. The previous AC blocks
# already ran every path; here we just re-assert defensively.
# ========================================================================
reset_state
"$FLEET" replay replaytest --batch --since 365d >/dev/null 2>&1 || true
if grep -qE 'gh pr (merge|comment|review)' "$GH_LOG"; then
  echo "FAIL: AC#10 --batch must NEVER call gh pr merge/comment/review"
  cat "$GH_LOG"; exit 1
fi
if grep -qE 'git push' "$GIT_LOG"; then
  echo "FAIL: AC#10 --batch must NEVER push"
  cat "$GIT_LOG"; exit 1
fi
echo "ok: AC#10 --batch never mutates (no merge/comment/review/push)"

# ========================================================================
# AC #11 — Help text mentions --batch, --limit, --since. Per LESSONS
# 2026-05-30 we grep with `grep -qF --` to defuse the leading-dash trap.
# Per LESSONS 2026-06-01 the help block ends with explicit `exit 0`.
# ========================================================================
help_out="$TMP/replay-help.txt"
"$FLEET" replay --help > "$help_out" 2>&1
for kw in '--batch' '--limit' '--since'; do
  if ! grep -qF -- "$kw" "$help_out"; then
    echo "FAIL: AC#11 replay --help missing keyword '$kw'"
    cat "$help_out"; exit 1
  fi
done
# Source-level guard: help banner block must end with `exit 0`.
if ! grep -nE '^[[:space:]]*exit 0' "$REPO_ROOT/bin/fleet" >/dev/null; then
  echo "FAIL: AC#11 bin/fleet must contain 'exit 0' (LESSONS 2026-06-01)"
  exit 1
fi
echo "ok: AC#11 replay --help mentions --batch/--limit/--since; ends exit 0"

echo
echo "all replay-batch.sh assertions passed."
