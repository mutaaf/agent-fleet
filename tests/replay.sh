#!/bin/bash
# tests/replay.sh — bin/fleet replay end-to-end test against tmpdir fixtures.
#
# Ticket 0021. One assertion block per acceptance-criteria checkbox in
# docs/backlog/0021-fleet-replay-past-pr-through-current-prompts.md.
#
# Strategy: stub `claude`, `gh`, and `git` on PATH under $HOME/.local/bin per
# LESSONS 2026-05-26 ("lib/common.sh resets PATH; stubs must live in
# $HOME/.local/bin"). bin/fleet itself does NOT source lib/common.sh, but
# inside the dispatcher we DO source common.sh to reuse `fleet_emit_event`
# and the runs.jsonl append shape — so stubs must survive the PATH reset.
#
# The `gh` stub returns canned `pr view --json` and `pr diff` output keyed
# by env vars; the `claude` stub records its argv and prints a canned JSON
# envelope with a `VERDICT:` line so the regex parser is exercised end-to-end.

set -euo pipefail

REPO_ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
FLEET="$REPO_ROOT/bin/fleet"

TMP="$(mktemp -d -t fleet-replay-test.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

# Isolate from the host: HOME is the test's, all caches land under $TMP.
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

# Per-slug cache (events.jsonl + runs.jsonl + replay output files).
CACHE_DIR="$HOME/.cache/replaytest-agent"
mkdir -p "$CACHE_DIR"
EVENTS_FILE="$CACHE_DIR/events.jsonl"
RUNS_FILE="$CACHE_DIR/runs.jsonl"

# --- stubs under $HOME/.local/bin -----------------------------------------
# Per LESSONS 2026-05-26: lib/common.sh resets PATH to start with
# $HOME/.local/bin, so stubs MUST live there to survive a fleet_emit_event
# call that sources common.sh.
BIN_STUB="$HOME/.local/bin"
mkdir -p "$BIN_STUB"
CLAUDE_LOG="$TMP/claude.log"
GH_LOG="$TMP/gh.log"
GIT_LOG="$TMP/git.log"
: > "$CLAUDE_LOG"
: > "$GH_LOG"
: > "$GIT_LOG"

# claude stub: records argv (one line) and emits a canned JSON envelope.
# CLAUDE_RESULT is the verdict body the stub returns; tests overwrite it
# per scenario (e.g. "VERDICT: sign-off" vs "VERDICT: request-changes").
cat > "$BIN_STUB/claude" <<STUB
#!/bin/bash
printf '%s\n' "claude \$*" >> "$CLAUDE_LOG"
# Drain stdin so the real fleet_run_claude pipe behaves naturally.
cat >/dev/null 2>&1 || true
result="\${CLAUDE_RESULT:-VERDICT: sign-off
rationale: looks fine}"
# Escape for JSON: backslashes, double-quotes, then newlines → \\n. Order
# matters: backslash first.
esc="\$(printf '%s' "\$result" | sed -e 's/\\\\/\\\\\\\\/g' -e 's/"/\\\\"/g' | awk 'BEGIN{ORS=""} {if (NR>1) print "\\\\n"; print}')"
cat <<JSON
{
  "result": "\$esc",
  "session_id": "replay-abc",
  "total_cost_usd": 0.12,
  "duration_ms": 4321,
  "num_turns": 1,
  "usage": {"input_tokens": 50, "output_tokens": 75},
  "is_error": false
}
JSON
exit 0
STUB
chmod +x "$BIN_STUB/claude"

# gh stub: records argv, returns env-driven responses.
#   GH_PR_VIEW_JSON       — body for `gh pr view <N> --json ...`
#   GH_PR_DIFF            — body for `gh pr diff <N>`
# A `gh pr merge` call would be a failure (replay must not merge); we exit
# non-zero on that path so the test catches accidents.
cat > "$BIN_STUB/gh" <<STUB
#!/bin/bash
printf '%s\n' "gh \$*" >> "$GH_LOG"
case "\${1:-}" in
  pr)
    case "\${2:-}" in
      view) printf '%s' "\${GH_PR_VIEW_JSON:-{}}" ;;
      diff) printf '%s' "\${GH_PR_DIFF:-diff --git a/x b/x}" ;;
      merge)
        echo "gh pr merge unexpectedly called during replay" >&2
        exit 1 ;;
      comment)
        echo "gh pr comment unexpectedly called during replay" >&2
        exit 1 ;;
      *) exit 0 ;;
    esac
    ;;
  *) exit 0 ;;
esac
STUB
chmod +x "$BIN_STUB/gh"

# git stub: replay does a fresh checkout to read AGENTS.md/LESSONS.md/ticket.
# We satisfy `git clone` by creating a minimal kit-shaped tree at the dest;
# subsequent `git ...` calls are recorded and no-op.
cat > "$BIN_STUB/git" <<STUB
#!/bin/bash
printf '%s\n' "git \$*" >> "$GIT_LOG"
case "\${1:-}" in
  clone)
    # The destination is the last positional argument.
    dest="\${@: -1}"
    mkdir -p "\$dest/docs/backlog"
    : > "\$dest/AGENTS.md"
    printf '%s\n' '# AGENTS.md — fixture' >> "\$dest/AGENTS.md"
    printf '%s\n' '## Agent parameters' >> "\$dest/AGENTS.md"
    : > "\$dest/docs/LESSONS.md"
    printf '%s\n' '# LESSONS — fixture' >> "\$dest/docs/LESSONS.md"
    printf '%s\n' '# Ticket 0017 fixture body' > "\$dest/docs/backlog/0017-fleet-rollback.md"
    exit 0 ;;
  *) exit 0 ;;
esac
STUB
chmod +x "$BIN_STUB/git"

export PATH="$BIN_STUB:$PATH"

reset_state() {
  : > "$CLAUDE_LOG"
  : > "$GH_LOG"
  : > "$GIT_LOG"
  rm -rf "$CACHE_DIR"
  mkdir -p "$CACHE_DIR"
  unset CLAUDE_RESULT GH_PR_VIEW_JSON GH_PR_DIFF
}

# A canned `gh pr view --json` body for a merged feat/0017 PR. Used by
# every "happy path" scenario.
MERGED_PR_VIEW_JSON='{"number":17,"title":"ticket 0017: shipped","headRefName":"feat/0017-fleet-rollback","body":"Implements ticket 0017.","mergeCommit":{"oid":"deadbeef"},"mergedAt":"2026-05-26T12:00:00Z","files":[{"path":"bin/fleet"}],"state":"MERGED"}'
OPEN_PR_VIEW_JSON='{"number":18,"title":"ticket 0018: in-progress","headRefName":"feat/0018-principles","body":"Implements ticket 0018.","mergeCommit":null,"mergedAt":null,"files":[{"path":"prompts/PRINCIPLES.md"}],"state":"OPEN"}'
CHORE_PR_VIEW_JSON='{"number":42,"title":"GTM: backlog refresh","headRefName":"chore/gtm-backlog-2026-05-26","body":"Adds new tickets.","mergeCommit":{"oid":"feedface"},"mergedAt":"2026-05-26T18:00:00Z","files":[{"path":"docs/backlog/README.md"}],"state":"MERGED"}'

# ========================================================================
# AC #1 — `fleet replay <slug> --pr <N>` (no --phase) defaults to review.
# Asserts: claude argv contains `--allowedTools none`; stdout contains the
# parsed verdict line `VERDICT: sign-off`; gh pr view + gh pr diff were
# called; the printed verdict line is present.
# ========================================================================
reset_state
export GH_PR_VIEW_JSON="$MERGED_PR_VIEW_JSON"
export GH_PR_DIFF="diff --git a/bin/fleet b/bin/fleet
+new replay impl"
export CLAUDE_RESULT="VERDICT: sign-off
rationale: respects branch prefixes; tests cover all ACs; no HARD NO violation."

OUT="$("$FLEET" replay replaytest --pr 17 2>&1)" \
  || { echo "FAIL: AC#1 fleet replay exited non-zero"; echo "--- out ---"; echo "$OUT"; echo "--- claude.log ---"; cat "$CLAUDE_LOG"; exit 1; }

if ! grep -qE -- '--allowedTools[[:space:]]+none' "$CLAUDE_LOG"; then
  echo "FAIL: AC#1 expected '--allowedTools none' in claude argv"
  cat "$CLAUDE_LOG"; exit 1
fi
if ! grep -qE 'gh pr view 17' "$GH_LOG"; then
  echo "FAIL: AC#1 expected 'gh pr view 17' to be invoked"
  cat "$GH_LOG"; exit 1
fi
if ! grep -qE 'gh pr diff 17' "$GH_LOG"; then
  echo "FAIL: AC#1 expected 'gh pr diff 17' to be invoked"
  cat "$GH_LOG"; exit 1
fi
if ! grep -qE '^VERDICT:[[:space:]]+sign-off' <<<"$OUT"; then
  echo "FAIL: AC#1 expected printed 'VERDICT: sign-off' line in stdout"
  echo "$OUT"; exit 1
fi
echo "ok: AC#1 default phase=review runs claude tool-locked, prints verdict"

# ========================================================================
# AC #2 — `--phase ship` runs the ship-prompt flow. Verdict regex is
# `^ACTION:\s*(heal|ship|wait|noop)`. The composed prompt MUST NOT include
# the diff (ship is asked "what would you do?" not "is this good?").
# ========================================================================
reset_state
export GH_PR_VIEW_JSON="$MERGED_PR_VIEW_JSON"
export GH_PR_DIFF="should-not-be-used-for-ship"
export CLAUDE_RESULT="ACTION: ship
rationale: ticket 0017 is groomed, no in-flight PR, proceed to PHASE 2."

OUT="$("$FLEET" replay replaytest --pr 17 --phase ship 2>&1)" \
  || { echo "FAIL: AC#2 fleet replay --phase ship exited non-zero"; echo "$OUT"; exit 1; }

if ! grep -qE '^ACTION:[[:space:]]+ship' <<<"$OUT"; then
  echo "FAIL: AC#2 expected printed 'ACTION: ship' line"
  echo "$OUT"; exit 1
fi
# The `gh pr diff` call must NOT have happened in --phase ship.
if grep -qE 'gh pr diff' "$GH_LOG"; then
  echo "FAIL: AC#2 --phase ship must NOT call gh pr diff (ship doesn't grade the diff)"
  cat "$GH_LOG"; exit 1
fi
echo "ok: AC#2 --phase ship parses ACTION verdict and skips the diff"

# ========================================================================
# AC #3 — `--phase review --request-changes-ok` flips the success condition.
# Exit 0 when verdict is request-changes; exit 1 when verdict is sign-off.
# ========================================================================
reset_state
export GH_PR_VIEW_JSON="$MERGED_PR_VIEW_JSON"
export GH_PR_DIFF="diff goes here"
export CLAUDE_RESULT="VERDICT: request-changes
rationale: pinned principle P-7 violation."

# request-changes + --request-changes-ok → exit 0 (the expected case here).
set +e
"$FLEET" replay replaytest --pr 17 --request-changes-ok >/dev/null 2>&1
rc=$?
set -e
if [ "$rc" -ne 0 ]; then
  echo "FAIL: AC#3 --request-changes-ok with VERDICT:request-changes must exit 0 (got $rc)"
  exit 1
fi

# sign-off + --request-changes-ok → exit 1 (the inverse).
reset_state
export GH_PR_VIEW_JSON="$MERGED_PR_VIEW_JSON"
export GH_PR_DIFF="diff goes here"
export CLAUDE_RESULT="VERDICT: sign-off
rationale: all good."
set +e
"$FLEET" replay replaytest --pr 17 --request-changes-ok >/dev/null 2>&1
rc=$?
set -e
if [ "$rc" -eq 0 ]; then
  echo "FAIL: AC#3 --request-changes-ok with VERDICT:sign-off must exit non-zero"
  exit 1
fi
echo "ok: AC#3 --request-changes-ok flips the exit-code success condition"

# ========================================================================
# AC #4 — `--dry` (default) does not call `gh pr merge`, does not push,
# does not comment on the PR; AGENT_DRY_RUN=1 end-to-end (claude argv
# includes --allowedTools none).
# ========================================================================
reset_state
export GH_PR_VIEW_JSON="$MERGED_PR_VIEW_JSON"
export GH_PR_DIFF="diff body"
export CLAUDE_RESULT="VERDICT: sign-off
rationale: ok."
"$FLEET" replay replaytest --pr 17 >/dev/null 2>&1 \
  || { echo "FAIL: AC#4 default replay exited non-zero"; cat "$CLAUDE_LOG"; exit 1; }

if grep -qE 'gh pr merge' "$GH_LOG"; then
  echo "FAIL: AC#4 replay must NEVER call 'gh pr merge'"
  cat "$GH_LOG"; exit 1
fi
if grep -qE 'gh pr comment' "$GH_LOG"; then
  echo "FAIL: AC#4 replay must NEVER call 'gh pr comment'"
  cat "$GH_LOG"; exit 1
fi
if grep -qE 'git push' "$GIT_LOG"; then
  echo "FAIL: AC#4 replay must NEVER push"
  cat "$GIT_LOG"; exit 1
fi
if ! grep -qE -- '--allowedTools[[:space:]]+none' "$CLAUDE_LOG"; then
  echo "FAIL: AC#4 dry-run argv must include --allowedTools none"
  cat "$CLAUDE_LOG"; exit 1
fi
echo "ok: AC#4 default --dry blocks merge/push/comment; allowedTools none"

# ========================================================================
# AC #5 — `--out FILE` writes the full claude result to a file. Default
# path: $CACHE_DIR/replay-<slug>-pr<N>-<phase>-<ts>.txt. The path is
# printed at end of stdout so the operator can cat it.
# ========================================================================
reset_state
export GH_PR_VIEW_JSON="$MERGED_PR_VIEW_JSON"
export GH_PR_DIFF="diff body"
export CLAUDE_RESULT="VERDICT: sign-off
rationale: ok, long body here, lots of detail."
OUT_FILE="$TMP/replay-out.txt"
OUT="$("$FLEET" replay replaytest --pr 17 --out "$OUT_FILE" 2>&1)" \
  || { echo "FAIL: AC#5 --out replay exited non-zero"; echo "$OUT"; exit 1; }

if [ ! -f "$OUT_FILE" ]; then
  echo "FAIL: AC#5 expected output file at $OUT_FILE"
  exit 1
fi
if ! grep -qE '^VERDICT:[[:space:]]+sign-off' "$OUT_FILE"; then
  echo "FAIL: AC#5 output file missing VERDICT line"
  cat "$OUT_FILE"; exit 1
fi
# stdout must mention the path.
if ! grep -qF "$OUT_FILE" <<<"$OUT"; then
  echo "FAIL: AC#5 stdout must print the --out path"
  echo "$OUT"; exit 1
fi

# Default path branch: no --out flag, the file lands in $CACHE_DIR with
# the expected naming convention.
reset_state
export GH_PR_VIEW_JSON="$MERGED_PR_VIEW_JSON"
export GH_PR_DIFF="diff body"
export CLAUDE_RESULT="VERDICT: sign-off
rationale: ok."
OUT="$("$FLEET" replay replaytest --pr 17 2>&1)" \
  || { echo "FAIL: AC#5 default-path replay exited non-zero"; echo "$OUT"; exit 1; }
# Locate the printed default path. We grep the line carrying the
# replay-<slug>-pr<N> token (the "  result: …" callout line in stdout),
# then awk the last field — the path is whitespace-separated from any
# preceding "result:" label.
default_path="$(printf '%s\n' "$OUT" | grep -E 'replay-replaytest-pr17-review-[0-9TZ-]+\.txt' | awk '{print $NF}' | head -1)"
if [ -z "$default_path" ]; then
  echo "FAIL: AC#5 default --out path not printed to stdout"
  echo "$OUT"; exit 1
fi
case "$default_path" in
  "$CACHE_DIR"/replay-replaytest-pr17-review-*.txt) ;;
  *) echo "FAIL: AC#5 default --out path '$default_path' not under \$CACHE_DIR with expected naming"; exit 1 ;;
esac
if [ ! -f "$default_path" ]; then
  echo "FAIL: AC#5 default --out path printed but file missing on disk"
  exit 1
fi
echo "ok: AC#5 --out + default-path both write the full claude result"

# ========================================================================
# AC #6 — chore/gtm-* PR head → replay exits 2 with the contract message.
# ========================================================================
reset_state
export GH_PR_VIEW_JSON="$CHORE_PR_VIEW_JSON"
export GH_PR_DIFF="should not matter"
set +e
OUT="$("$FLEET" replay replaytest --pr 42 2>&1)"
rc=$?
set -e
if [ "$rc" -ne 2 ]; then
  echo "FAIL: AC#6 expected exit 2 for a non-feat/eng PR (got $rc)"
  echo "$OUT"; exit 1
fi
if ! grep -qF 'not an agent feature PR' <<<"$OUT"; then
  echo "FAIL: AC#6 expected 'not an agent feature PR' message"
  echo "$OUT"; exit 1
fi
echo "ok: AC#6 chore/gtm-* PR is rejected with exit 2"

# ========================================================================
# AC #7 — Unmerged (open) PRs work — replay reads the head diff. The test
# exercises an OPEN PR via the stubbed gh pr view payload and confirms
# the dispatcher does NOT bail on `state":"OPEN"`.
# ========================================================================
reset_state
export GH_PR_VIEW_JSON="$OPEN_PR_VIEW_JSON"
export GH_PR_DIFF="diff of an open PR"
export CLAUDE_RESULT="VERDICT: sign-off
rationale: open PR replay path still composes a prompt and parses a verdict."
OUT="$("$FLEET" replay replaytest --pr 18 2>&1)" \
  || { echo "FAIL: AC#7 replay against open PR exited non-zero"; echo "$OUT"; exit 1; }
if ! grep -qE '^VERDICT:[[:space:]]+sign-off' <<<"$OUT"; then
  echo "FAIL: AC#7 open-PR replay missing verdict line"
  echo "$OUT"; exit 1
fi
echo "ok: AC#7 unmerged (open) PR is replayed end-to-end"

# ========================================================================
# AC #8 — A runs.jsonl record is appended with phase=replay. Cost
# accounting can sort replay calls from real ship runs.
# ========================================================================
reset_state
export GH_PR_VIEW_JSON="$MERGED_PR_VIEW_JSON"
export GH_PR_DIFF="diff body"
export CLAUDE_RESULT="VERDICT: sign-off
rationale: ok."
"$FLEET" replay replaytest --pr 17 >/dev/null 2>&1 \
  || { echo "FAIL: AC#8 replay run exited non-zero"; exit 1; }

if [ ! -f "$RUNS_FILE" ]; then
  echo "FAIL: AC#8 expected runs.jsonl at $RUNS_FILE"
  exit 1
fi
if ! grep -qE '"phase":"replay"' "$RUNS_FILE"; then
  echo "FAIL: AC#8 runs.jsonl row missing phase=replay tag"
  cat "$RUNS_FILE"; exit 1
fi
if ! grep -qE '"slug":"replaytest"' "$RUNS_FILE"; then
  echo "FAIL: AC#8 runs.jsonl row missing slug"
  cat "$RUNS_FILE"; exit 1
fi
echo "ok: AC#8 runs.jsonl row carries phase=replay"

# ========================================================================
# AC #9 — Test stubs live under $HOME/.local/bin per LESSONS 2026-05-26.
# This is structural: the test fixture above already places stubs there
# and the earlier AC blocks asserted argv was captured. Here we just
# confirm the path of one stub matches the convention so a future drift
# (e.g. someone moving stubs back under $TMP/bin) is caught loudly.
# ========================================================================
case "$BIN_STUB" in
  "$HOME"/.local/bin) ;;
  *)
    echo "FAIL: AC#9 stubs must live under \$HOME/.local/bin (got $BIN_STUB)"
    exit 1 ;;
esac
echo "ok: AC#9 stubs respect LESSONS 2026-05-26 PATH-reset convention"

# ========================================================================
# AC #10 — README.md "Daily ops" section gains a one-line callout for
# `fleet replay`, placed near the existing `kickstart --dry-run` callout.
# ========================================================================
README="$REPO_ROOT/README.md"
if ! grep -qE 'fleet replay' "$README"; then
  echo "FAIL: AC#10 README.md must mention 'fleet replay'"
  exit 1
fi
if ! grep -nE 'fleet replay' "$README" | head -1 | grep -qE '^[0-9]+:'; then
  echo "FAIL: AC#10 fleet replay callout not findable in README"
  exit 1
fi
# Confirm the callout sits near the kickstart --dry-run line, not buried
# at the bottom: the relevant "Daily ops" header should sit within ~40
# lines of the replay mention.
ops_line="$(grep -nE '^### Daily ops' "$README" | head -1 | cut -d: -f1)"
replay_line="$(grep -nE 'fleet replay' "$README" | head -1 | cut -d: -f1)"
if [ -z "$ops_line" ] || [ -z "$replay_line" ]; then
  echo "FAIL: AC#10 could not locate '### Daily ops' header or replay mention"
  exit 1
fi
if [ "$replay_line" -lt "$ops_line" ] || [ "$(( replay_line - ops_line ))" -gt 40 ]; then
  echo "FAIL: AC#10 'fleet replay' should sit within 40 lines of '### Daily ops'"
  echo "  ops_line=$ops_line replay_line=$replay_line"
  exit 1
fi
echo "ok: AC#10 README Daily ops section documents fleet replay"

echo
echo "all replay.sh assertions passed."
