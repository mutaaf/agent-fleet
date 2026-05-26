#!/bin/bash
# tests/rollback.sh — bin/fleet rollback end-to-end test against tmpdir fixtures.
#
# Ticket 0017. One assertion block per acceptance-criteria checkbox in
# docs/backlog/0017-fleet-rollback.md.
#
# Strategy: stub `gh` and `git` on PATH (mktemp -d). The `gh` stub records its
# argv to a log file so assertions can diff the exact command sequence; the
# `git` stub records argv similarly but also satisfies the few real commands
# the script needs (clone/branch/revert/push) by no-op'ing them. CACHE_DIR
# points at a temp dir so events.jsonl ends up under the fixture.
#
# Per LESSONS 2026-05-26 about naming shell functions, we double-checked that
# `rollback` doesn't collide with any coreutils binary the script also shells
# out to — `man rollback` / `which rollback` come up empty on macOS, so the
# dispatcher is safe to keep its plain name.

set -euo pipefail

REPO_ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
FLEET="$REPO_ROOT/bin/fleet"

TMP="$(mktemp -d -t fleet-rollback-test.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

# Isolate from the host: HOME is the test's, all caches land under $TMP.
export HOME="$TMP/home"
mkdir -p "$HOME"

FIXTURE="$TMP/projects"
mkdir -p "$FIXTURE/alpha"
cat > "$FIXTURE/alpha/agents.config.sh" <<'CFG'
SLUG="alpha"
PROJECT_NAME="Alpha"
NAMESPACE="com.alpha"
REPO_URL="https://github.com/example/alpha"
SELF_CANCEL="20990101"
CFG
export FLEET_DISCOVERY_ROOT="$FIXTURE"

# Per-slug cache (where events.jsonl will land).
export CACHE_DIR="$HOME/.cache/alpha-agent"
mkdir -p "$CACHE_DIR"
EVENTS="$CACHE_DIR/events.jsonl"

# --- gh stub --------------------------------------------------------------
# Records argv to $GH_LOG, returns canned JSON. The canned behavior is
# parameterised by env vars so each test block can swap the response without
# rewriting the stub:
#   GH_LIST_RESPONSE   — JSON returned by `gh pr list`
#   GH_VIEW_RESPONSE   — JSON returned by `gh pr view <N> --json ...`
#   GH_CREATE_OUTPUT   — stdout for `gh pr create` (default: a fake PR URL)
#   GH_MERGE_EXIT      — exit code for `gh pr merge` (default 0)
BIN_STUB="$TMP/bin"
mkdir -p "$BIN_STUB"
GH_LOG="$TMP/gh.log"
GIT_LOG="$TMP/git.log"
: > "$GH_LOG"
: > "$GIT_LOG"

cat > "$BIN_STUB/gh" <<STUB
#!/bin/bash
# Append argv (one line) to the log so tests can diff it.
printf '%s\n' "gh \$*" >> "$GH_LOG"
case "\${1:-}" in
  pr)
    case "\${2:-}" in
      list)
        printf '%s' "\${GH_LIST_RESPONSE:-[]}"
        ;;
      view)
        printf '%s' "\${GH_VIEW_RESPONSE:-{}}"
        ;;
      create)
        printf '%s\n' "\${GH_CREATE_OUTPUT:-https://github.com/example/alpha/pull/99}"
        ;;
      merge)
        exit "\${GH_MERGE_EXIT:-0}"
        ;;
      *)
        exit 0
        ;;
    esac
    ;;
  *) exit 0 ;;
esac
STUB
chmod +x "$BIN_STUB/gh"

cat > "$BIN_STUB/git" <<STUB
#!/bin/bash
# Log argv, then no-op every command. We don't need real git state for the
# fleet rollback tests — the gh stub is the side-effect surface that matters.
# The one exception is \`git clone\`: when the script clones into
# \$CACHE_DIR/rollback-checkout/, we just create the dir so subsequent
# \`cd\` calls succeed.
printf '%s\n' "git \$*" >> "$GIT_LOG"
case "\${1:-}" in
  clone)
    # Last positional arg is the destination.
    dest="\${!#}"
    mkdir -p "\$dest/.git"
    ;;
esac
exit 0
STUB
chmod +x "$BIN_STUB/git"
export PATH="$BIN_STUB:$PATH"

# Helper: reset the logs + events between blocks.
reset_logs() {
  : > "$GH_LOG"
  : > "$GIT_LOG"
  rm -f "$EVENTS"
  rm -rf "$CACHE_DIR/rollback-checkout"
}

# Canonical "list" JSON used by every default-path block. One agent feat/
# PR merged most-recently, plus one older.
DEFAULT_LIST='[
  {"number":42,"title":"feat/0019 broken thing","mergeCommit":{"oid":"1976339abcdef0000000"},"headRefName":"feat/0019-broken-thing","mergedAt":"2026-05-25T23:14:02Z"},
  {"number":41,"title":"feat/0018 prior thing","mergeCommit":{"oid":"abcdef1976339000000"},"headRefName":"feat/0018-prior-thing","mergedAt":"2026-05-25T20:00:00Z"}
]'
# Canonical "view" JSON for a squash merge.
DEFAULT_VIEW_SQUASH='{"number":42,"title":"feat/0019 broken thing","mergeCommit":{"oid":"1976339abcdef0000000"},"headRefName":"feat/0019-broken-thing","mergedAt":"2026-05-25T23:14:02Z","mergeMethod":"SQUASH"}'
DEFAULT_VIEW_MERGE='{"number":42,"title":"feat/0019 merge thing","mergeCommit":{"oid":"deadbeefcafe1234567890"},"headRefName":"feat/0019-merge-thing","mergedAt":"2026-05-25T23:14:02Z","mergeMethod":"MERGE"}'

# ========================================================================
# AC #1 — `fleet rollback <slug>` queries `gh pr list --repo <repo>
#         --state merged --base main --limit 20 --search "head:feat/ OR
#         head:eng/"` for recently-merged agent PRs.
# ========================================================================
reset_logs
export GH_LIST_RESPONSE="$DEFAULT_LIST"
export GH_VIEW_RESPONSE="$DEFAULT_VIEW_SQUASH"
# Pipe "y\n" so the confirmation prompt resolves (we'll cover N + --yes below).
printf 'y\n' | "$FLEET" rollback alpha >/dev/null 2>&1 || true

if ! grep -qE 'gh pr list .*--state merged' "$GH_LOG"; then
  echo "FAIL: AC#1 expected 'gh pr list --state merged' invocation"
  cat "$GH_LOG"; exit 1
fi
if ! grep -qE 'gh pr list .*--base main' "$GH_LOG"; then
  echo "FAIL: AC#1 expected '--base main'"; cat "$GH_LOG"; exit 1
fi
if ! grep -qE 'gh pr list .*--limit 20' "$GH_LOG"; then
  echo "FAIL: AC#1 expected '--limit 20'"; cat "$GH_LOG"; exit 1
fi
if ! grep -qE 'gh pr list .*--search .*head:feat/ OR head:eng/' "$GH_LOG"; then
  echo "FAIL: AC#1 expected --search for 'head:feat/ OR head:eng/'"
  cat "$GH_LOG"; exit 1
fi
echo "ok: AC#1 gh pr list query shape"

# ========================================================================
# AC #2 — Empty list → "no agent-merged feature PR found in the last 20
#         merges" + exit 1.
# ========================================================================
reset_logs
export GH_LIST_RESPONSE='[]'
set +e
OUT="$("$FLEET" rollback alpha 2>&1)"
RC=$?
set -e
if [ "$RC" -ne 1 ]; then
  echo "FAIL: AC#2 expected exit 1 on empty list, got $RC"; echo "$OUT"; exit 1
fi
if ! grep -q 'no agent-merged feature PR found in the last 20 merges' <<<"$OUT"; then
  echo "FAIL: AC#2 expected the contract error message"; echo "$OUT"; exit 1
fi
echo "ok: AC#2 empty list error path"

# ========================================================================
# AC #3 — Without flags, prints target metadata + prompts
#         "proceed with revert? [y/N]"; pressing N exits 0 without opening a PR.
# ========================================================================
reset_logs
export GH_LIST_RESPONSE="$DEFAULT_LIST"
export GH_VIEW_RESPONSE="$DEFAULT_VIEW_SQUASH"
set +e
OUT="$(printf 'N\n' | "$FLEET" rollback alpha 2>&1)"
RC=$?
set -e
if [ "$RC" -ne 0 ]; then
  echo "FAIL: AC#3 'N' answer should exit 0, got $RC"; echo "$OUT"; exit 1
fi
if ! grep -q 'proceed with revert? \[y/N\]' <<<"$OUT"; then
  echo "FAIL: AC#3 expected the literal prompt 'proceed with revert? [y/N]'"
  echo "$OUT"; exit 1
fi
# Metadata: commit sha, PR number, title, branch, mergedAt.
for needle in '1976339' '#42' 'feat/0019 broken thing' 'feat/0019-broken-thing' '2026-05-25T23:14:02Z'; do
  if ! grep -q "$needle" <<<"$OUT"; then
    echo "FAIL: AC#3 missing metadata '$needle' in pre-confirm output"
    echo "$OUT"; exit 1
  fi
done
# No PR should have been created.
if grep -q 'gh pr create' "$GH_LOG"; then
  echo "FAIL: AC#3 'N' answer must not call 'gh pr create'"
  cat "$GH_LOG"; exit 1
fi
echo "ok: AC#3 confirmation prompt + N exits clean"

# ========================================================================
# AC #4 — `--yes` (and `-y`) skip the prompt and proceed directly.
# ========================================================================
reset_logs
export GH_LIST_RESPONSE="$DEFAULT_LIST"
export GH_VIEW_RESPONSE="$DEFAULT_VIEW_SQUASH"
# No stdin: if a prompt would block, the command would hang. Feed </dev/null
# so a hung read returns EOF and any bug shows up loudly instead.
set +e
OUT="$("$FLEET" rollback alpha --yes </dev/null 2>&1)"
RC=$?
set -e
if [ "$RC" -ne 0 ]; then
  echo "FAIL: AC#4 --yes path must exit 0, got $RC"; echo "$OUT"; exit 1
fi
if grep -q 'proceed with revert?' <<<"$OUT"; then
  echo "FAIL: AC#4 --yes must NOT print the confirmation prompt"
  echo "$OUT"; exit 1
fi
if ! grep -qE 'gh pr create' "$GH_LOG"; then
  echo "FAIL: AC#4 --yes must reach 'gh pr create'"; cat "$GH_LOG"; exit 1
fi
# -y short flag — same contract.
reset_logs
export GH_LIST_RESPONSE="$DEFAULT_LIST"
export GH_VIEW_RESPONSE="$DEFAULT_VIEW_SQUASH"
"$FLEET" rollback alpha -y </dev/null >/dev/null 2>&1
if ! grep -qE 'gh pr create' "$GH_LOG"; then
  echo "FAIL: AC#4 -y short flag must reach 'gh pr create'"; cat "$GH_LOG"; exit 1
fi
echo "ok: AC#4 --yes / -y skips prompt"

# ========================================================================
# AC #5 — On proceed: clones into $CACHE_DIR/rollback-checkout/, branches
#         revert/<id>-<slug>, runs `git revert --no-edit <sha>`, pushes,
#         opens PR via `gh pr create --fill --base main --head <branch>`,
#         arms `gh pr merge --auto --squash`.
# ========================================================================
reset_logs
export GH_LIST_RESPONSE="$DEFAULT_LIST"
export GH_VIEW_RESPONSE="$DEFAULT_VIEW_SQUASH"
"$FLEET" rollback alpha --yes </dev/null >/dev/null 2>&1
# git clone into $CACHE_DIR/rollback-checkout/
if ! grep -qE "git clone .*$CACHE_DIR/rollback-checkout" "$GIT_LOG"; then
  echo "FAIL: AC#5 expected 'git clone ... \$CACHE_DIR/rollback-checkout'"
  cat "$GIT_LOG"; exit 1
fi
# --depth 50 per the engineering notes.
if ! grep -qE 'git clone .*--depth 50' "$GIT_LOG"; then
  echo "FAIL: AC#5 expected 'git clone --depth 50' for shallow but reachable history"
  cat "$GIT_LOG"; exit 1
fi
# Branch name: revert/0019-broken-thing (id-slug parsed from headRefName).
if ! grep -qE 'git checkout -b revert/0019-broken-thing' "$GIT_LOG"; then
  echo "FAIL: AC#5 expected 'git checkout -b revert/0019-broken-thing'"
  cat "$GIT_LOG"; exit 1
fi
# Squash → `git revert --no-edit <sha>`
if ! grep -qE 'git revert --no-edit 1976339abcdef0000000' "$GIT_LOG"; then
  echo "FAIL: AC#5 expected 'git revert --no-edit <sha>' for squash"
  cat "$GIT_LOG"; exit 1
fi
# git push origin HEAD (any push form is fine).
if ! grep -qE 'git push' "$GIT_LOG"; then
  echo "FAIL: AC#5 expected a 'git push' call"; cat "$GIT_LOG"; exit 1
fi
# gh pr create --fill --base main --head <branch>
if ! grep -qE 'gh pr create .*--fill .*--base main .*--head revert/0019-broken-thing' "$GH_LOG"; then
  echo "FAIL: AC#5 expected 'gh pr create --fill --base main --head revert/0019-broken-thing'"
  cat "$GH_LOG"; exit 1
fi
# Body must reference the original PR.
if ! grep -qE 'gh pr create .*Reverts #42' "$GH_LOG"; then
  echo "FAIL: AC#5 PR body must say 'Reverts #42'"; cat "$GH_LOG"; exit 1
fi
# gh pr merge --auto --squash
if ! grep -qE 'gh pr merge .*--auto .*--squash' "$GH_LOG"; then
  echo "FAIL: AC#5 expected 'gh pr merge --auto --squash'"; cat "$GH_LOG"; exit 1
fi
echo "ok: AC#5 full proceed sequence (clone/branch/revert/push/PR/merge)"

# ========================================================================
# AC #6 — `fleet_emit_event rollback_opened pr=<N> reverts=<orig>
#         merge_commit=<sha>` lands in events.jsonl.
# ========================================================================
# Reuse the state from AC#5 (event was emitted at end of proceed).
if [ ! -f "$EVENTS" ]; then
  echo "FAIL: AC#6 events.jsonl was not created at $EVENTS"; exit 1
fi
if ! grep -q '"type":"rollback_opened"' "$EVENTS"; then
  echo "FAIL: AC#6 missing type=rollback_opened in events.jsonl"
  cat "$EVENTS"; exit 1
fi
# pr is the NEW PR number (parsed from the gh pr create URL → 99 per stub default).
if ! grep -qE '"pr":"99"' "$EVENTS"; then
  echo "FAIL: AC#6 expected pr=99 (parsed from PR URL)"; cat "$EVENTS"; exit 1
fi
if ! grep -qE '"reverts":"42"' "$EVENTS"; then
  echo "FAIL: AC#6 expected reverts=42 (the original PR number)"
  cat "$EVENTS"; exit 1
fi
if ! grep -qE '"merge_commit":"1976339abcdef0000000"' "$EVENTS"; then
  echo "FAIL: AC#6 expected merge_commit=<sha>"; cat "$EVENTS"; exit 1
fi
echo "ok: AC#6 rollback_opened event"

# ========================================================================
# AC #7 — `--pr <N>` overrides the auto-pick: uses `gh pr view <N>` instead
#         of `gh pr list`.
# ========================================================================
reset_logs
export GH_LIST_RESPONSE="$DEFAULT_LIST"   # would point at #42 if list was called
# Override response: pretend we want to revert #41 (the older one).
export GH_VIEW_RESPONSE='{"number":41,"title":"feat/0018 prior thing","mergeCommit":{"oid":"abcdef1976339000000"},"headRefName":"feat/0018-prior-thing","mergedAt":"2026-05-25T20:00:00Z","mergeMethod":"SQUASH"}'
"$FLEET" rollback alpha --pr 41 --yes </dev/null >/dev/null 2>&1
# `gh pr list` must NOT have been called.
if grep -q 'gh pr list' "$GH_LOG"; then
  echo "FAIL: AC#7 --pr override must NOT call 'gh pr list'"
  cat "$GH_LOG"; exit 1
fi
# `gh pr view 41 ...` must have been called.
if ! grep -qE 'gh pr view 41' "$GH_LOG"; then
  echo "FAIL: AC#7 expected 'gh pr view 41'"; cat "$GH_LOG"; exit 1
fi
# Branch derives from the overridden PR's headRefName.
if ! grep -qE 'git checkout -b revert/0018-prior-thing' "$GIT_LOG"; then
  echo "FAIL: AC#7 expected revert/0018-prior-thing branch from override"
  cat "$GIT_LOG"; exit 1
fi
# Revert sha must be the OVERRIDDEN sha, not the list's.
if ! grep -qE 'git revert --no-edit abcdef1976339000000' "$GIT_LOG"; then
  echo "FAIL: AC#7 expected revert of overridden sha"; cat "$GIT_LOG"; exit 1
fi
echo "ok: AC#7 --pr override"

# ========================================================================
# AC #8 — `--dry-run` prints metadata + the exact git/gh commands it WOULD
#         run, but does nothing destructive. Exit 0.
# ========================================================================
reset_logs
export GH_LIST_RESPONSE="$DEFAULT_LIST"
export GH_VIEW_RESPONSE="$DEFAULT_VIEW_SQUASH"
set +e
OUT="$("$FLEET" rollback alpha --dry-run </dev/null 2>&1)"
RC=$?
set -e
if [ "$RC" -ne 0 ]; then
  echo "FAIL: AC#8 --dry-run must exit 0, got $RC"; echo "$OUT"; exit 1
fi
# Metadata still printed.
if ! grep -q '#42' <<<"$OUT"; then
  echo "FAIL: AC#8 --dry-run should print target metadata"; echo "$OUT"; exit 1
fi
# The two key planned commands must appear in stdout.
if ! grep -qE 'git revert --no-edit 1976339abcdef0000000' <<<"$OUT"; then
  echo "FAIL: AC#8 --dry-run must print the planned 'git revert' command"
  echo "$OUT"; exit 1
fi
if ! grep -qE 'gh pr create .*--head revert/0019-broken-thing' <<<"$OUT"; then
  echo "FAIL: AC#8 --dry-run must print the planned 'gh pr create' command"
  echo "$OUT"; exit 1
fi
# AND no clone/branch/push/create/merge actually executed.
if grep -qE 'git (clone|checkout -b|push)' "$GIT_LOG"; then
  echo "FAIL: AC#8 --dry-run must not run any destructive git command"
  cat "$GIT_LOG"; exit 1
fi
if grep -qE 'gh pr (create|merge)' "$GH_LOG"; then
  echo "FAIL: AC#8 --dry-run must not call gh pr create/merge"
  cat "$GH_LOG"; exit 1
fi
echo "ok: AC#8 --dry-run prints plan without side effects"

# ========================================================================
# AC #9 — mergeMethod=MERGE → `git revert -m 1 <sha>` (not --no-edit).
#         Both branches (squash + true merge) must be covered.
# ========================================================================
reset_logs
export GH_LIST_RESPONSE='[{"number":50,"title":"feat/0050 merged-not-squashed","mergeCommit":{"oid":"deadbeefcafe1234567890"},"headRefName":"feat/0050-merged-not-squashed","mergedAt":"2026-05-25T23:00:00Z"}]'
export GH_VIEW_RESPONSE="$DEFAULT_VIEW_MERGE"
"$FLEET" rollback alpha --yes </dev/null >/dev/null 2>&1
if ! grep -qE 'git revert -m 1 deadbeefcafe1234567890' "$GIT_LOG"; then
  echo "FAIL: AC#9 mergeMethod=MERGE must use 'git revert -m 1 <sha>'"
  cat "$GIT_LOG"; exit 1
fi
# Squash path (re-cover, separate from AC#5 to make the symmetry explicit).
reset_logs
export GH_LIST_RESPONSE="$DEFAULT_LIST"
export GH_VIEW_RESPONSE="$DEFAULT_VIEW_SQUASH"
"$FLEET" rollback alpha --yes </dev/null >/dev/null 2>&1
if ! grep -qE 'git revert --no-edit 1976339abcdef0000000' "$GIT_LOG"; then
  echo "FAIL: AC#9 mergeMethod=SQUASH must use 'git revert --no-edit <sha>'"
  cat "$GIT_LOG"; exit 1
fi
if grep -qE 'git revert -m 1' "$GIT_LOG"; then
  echo "FAIL: AC#9 squash path must NOT use 'git revert -m 1'"
  cat "$GIT_LOG"; exit 1
fi
echo "ok: AC#9 squash vs merge branch detection"

# ========================================================================
# AC #10 — README.md "Daily ops" section gains a `fleet rollback` callout
#          next to `fleet doctor`.
# ========================================================================
README="$REPO_ROOT/README.md"
if ! grep -qE 'fleet rollback' "$README"; then
  echo "FAIL: AC#10 README.md must mention 'fleet rollback'"
  exit 1
fi
# The callout must live in or near the "Daily ops" section (asserted by
# proximity — within 30 lines after the header).
DAILY_OPS_LINE=$(grep -n '^### Daily ops' "$README" | head -1 | cut -d: -f1)
if [ -z "$DAILY_OPS_LINE" ]; then
  echo "FAIL: AC#10 README.md must have a '### Daily ops' section"
  exit 1
fi
END=$(( DAILY_OPS_LINE + 30 ))
if ! sed -n "${DAILY_OPS_LINE},${END}p" "$README" | grep -q 'fleet rollback'; then
  echo "FAIL: AC#10 'fleet rollback' must appear within 30 lines of '### Daily ops'"
  exit 1
fi
echo "ok: AC#10 README Daily ops callout"

echo
echo "tests/rollback.sh: all assertions passed"
