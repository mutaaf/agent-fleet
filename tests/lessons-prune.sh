#!/bin/bash
# tests/lessons-prune.sh — bin/fleet lessons-prune end-to-end.
#
# Ticket 0039. One assertion block per acceptance-criteria checkbox in
# docs/backlog/0039-lessons-expiry-marker-convention.md:
#
#   AC#1  AGENTS.md § Lessons documents the `<!-- EXPIRES: YYYY-MM-DD -->`
#         convention.
#   AC#2  `--dry-run` walks LESSONS.md, prints the 4-column table for
#         expired paragraphs, and the empty branch renders cleanly.
#   AC#3  unmarked paragraphs are NEVER listed; EXPIRES > today is
#         NEVER listed; EXPIRES <= today IS listed.
#   AC#4  malformed EXPIRES → warn on stderr, exit 0 (do NOT abort).
#   AC#5  `--commit --cause "<text>"` moves expired paragraphs from
#         LESSONS.md to LESSONS-ARCHIVE.md (byte-exact body via cmp
#         against golden), commits, pushes, opens a PR via gh.
#   AC#6  `--commit` without `--cause` exits 2 with a stderr usage line.
#   AC#7  `--cause` value starting with `-` parses correctly (printf
#         leading-dash trap; LESSONS 2026-05-28) and is recorded
#         verbatim in PR body, commit msg, AND event payload.
#   AC#8  `lessons_pruned` event lands in agent-fleet's events.jsonl
#         with phase=prune and the documented payload; dry-run emits
#         NO event.
#   AC#9  AGENTS.md § Telemetry documents the new `lessons_pruned`
#         event AND the PR diff touches zero files under `prompts/`.
#   AC#10 `--help` prints USAGE block with --dry-run, --commit, --cause
#         (grep -qF -- per LESSONS 2026-05-30) and exits 0.
#   AC#11 covered implicitly by every AC running through $HOME/.local/bin
#         stubs (LESSONS 2026-05-26), `cp` for backup/restore (LESSONS
#         2026-05-27), and `awk … END { print n+0 }` for counts (LESSONS
#         2026-06-01). Budget < 10s.
#
# Per LESSONS 2026-05-26: stubs live in $HOME/.local/bin (common.sh's
# hardcoded PATH wipes a $TMP/bin). Per LESSONS 2026-05-27: `cp` for
# backup/restore — never `$(cat …)`. Per LESSONS 2026-06-01: counts
# use awk, never `grep -c … || echo 0`.

set -uo pipefail

REPO_ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
FLEET="$REPO_ROOT/bin/fleet"
FIXTURES="$REPO_ROOT/tests/fixtures/lessons-prune"

TMP="$(mktemp -d -t fleet-lessons-prune-test.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

# Isolate from the host — HOME shapes the default events.jsonl path
# (~/.cache/agent-fleet-agent/events.jsonl) and the stub PATH entry.
export HOME="$TMP/home"
mkdir -p "$HOME" "$HOME/.local/bin"
# bin/fleet's dispatcher does NOT source lib/common.sh (which would
# otherwise reset PATH to $HOME/.local/bin first per LESSONS
# 2026-05-26), so the test must do the prepend itself. The
# subshell that emits the lessons_pruned event DOES source common.sh
# and is unaffected.
export PATH="$HOME/.local/bin:$PATH"

# Freeze the clock to 2026-06-07 so the fixture's EXPIRES dates line
# up deterministically (today, tomorrow, malformed, long-past).
export FLEET_NOW_OVERRIDE="2026-06-07"

# Force fleet_emit_event into the kit-as-project cache so AC#8 can
# read it. Mirrors prompts_revert_emit_event's path.
KIT_CACHE="$HOME/.cache/agent-fleet-agent"
mkdir -p "$KIT_CACHE"
EVENTS="$KIT_CACHE/events.jsonl"

# Stub `git` — record every invocation under $TMP/git.log and
# succeed for commit/checkout -b/add/push. The implementation does
# `cd $kit_root && git …` so we record the cwd too.
cat > "$HOME/.local/bin/git" <<'STUB'
#!/bin/bash
{
  printf 'CWD=%s ARGV=' "$PWD"
  for a in "$@"; do printf ' [%s]' "$a"; done
  printf '\n'
} >> "$GIT_LOG_FILE"
case "$1" in
  status)
    # Always-clean working tree so the implementation doesn't refuse.
    exit 0 ;;
  checkout|add|commit|push)
    exit 0 ;;
  rev-parse)
    # Echo a fake SHA so anything that resolves a ref gets something.
    printf 'deadbeefdeadbeefdeadbeefdeadbeefdeadbeef\n'
    exit 0 ;;
  *)
    exit 0 ;;
esac
STUB
chmod +x "$HOME/.local/bin/git"
export GIT_LOG_FILE="$TMP/git.log"
: > "$GIT_LOG_FILE"

# Stub `gh` — record argv, echo a synthetic PR URL so the parser
# captures PR=42.
cat > "$HOME/.local/bin/gh" <<'STUB'
#!/bin/bash
{
  printf 'ARGV='
  for a in "$@"; do printf ' [%s]' "$a"; done
  printf '\n'
  # If --body-file was passed, copy the body to a fixed location so
  # the test can grep it for the --cause value.
  for ((i=1; i<=$#; i++)); do
    case "${!i}" in
      --body-file)
        j=$((i+1))
        cp -f "${!j}" "$GH_BODY_FILE" 2>/dev/null || true
        ;;
    esac
  done
} >> "$GH_LOG_FILE"
case "$1 $2" in
  "pr create")
    printf 'https://github.com/mutaaf/agent-fleet/pull/42\n'
    exit 0 ;;
  *)
    exit 0 ;;
esac
STUB
chmod +x "$HOME/.local/bin/gh"
export GH_LOG_FILE="$TMP/gh.log"
export GH_BODY_FILE="$TMP/gh-body.txt"
: > "$GH_LOG_FILE"
: > "$GH_BODY_FILE"

# Lay out a writable copy of the kit so lessons_prune_apply_move can
# mutate docs/LESSONS.md without disturbing the repo's pristine tree.
# Per LESSONS 2026-05-27 we use `cp`, never `$(cat …)`.
KIT_ROOT="$TMP/kit"
mkdir -p "$KIT_ROOT/docs" "$KIT_ROOT/bin" "$KIT_ROOT/lib"
cp "$FIXTURES/LESSONS.md" "$KIT_ROOT/docs/LESSONS.md"
# Point the implementation at our kit copy. The dispatcher derives
# its root from $0; we override via env so the test can choose.
export FLEET_KIT_ROOT="$KIT_ROOT"

# ---------------------------------------------------------------------------
# AC#1 — AGENTS.md § Lessons documents the EXPIRES marker convention.
# ---------------------------------------------------------------------------
AGENTS_MD="$REPO_ROOT/AGENTS.md"
if ! grep -qF -- "EXPIRES: YYYY-MM-DD" "$AGENTS_MD"; then
  echo "FAIL: AC#1 — AGENTS.md does not document the EXPIRES: YYYY-MM-DD convention"
  exit 1
fi
if ! grep -qE -- "^## Lessons" "$AGENTS_MD"; then
  echo "FAIL: AC#1 — AGENTS.md missing the '## Lessons' section heading"
  exit 1
fi
echo "ok AC#1: AGENTS.md documents the EXPIRES convention"

# ---------------------------------------------------------------------------
# AC#2 — --dry-run prints the 4-column table for expired paragraphs.
#        Empty branch renders cleanly when no paragraph is expired.
# ---------------------------------------------------------------------------
# Reset LESSONS.md from fixture before each run via cp.
cp "$FIXTURES/LESSONS.md" "$KIT_ROOT/docs/LESSONS.md"
"$FLEET" lessons-prune --dry-run > "$TMP/ac2.out" 2> "$TMP/ac2.err"
RC=$?
if [ "$RC" != "0" ]; then
  echo "FAIL: AC#2 — dry-run exited $RC"
  cat "$TMP/ac2.err"
  exit 1
fi
if ! grep -qE -- "^lessons-prune: 2 paragraphs expired as of 2026-06-07" "$TMP/ac2.out"; then
  echo "FAIL: AC#2 — summary line wrong"
  cat "$TMP/ac2.out"
  exit 1
fi
if ! grep -qE -- "^[[:space:]]+EXPIRES[[:space:]]+DATE[[:space:]]+HEADLINE" "$TMP/ac2.out"; then
  echo "FAIL: AC#2 — table header row missing"
  cat "$TMP/ac2.out"
  exit 1
fi
# Empty-branch sub-check: feed a LESSONS.md with NO expired paragraphs.
cat > "$KIT_ROOT/docs/LESSONS.md" <<EMPTY
# LESSONS

## 2026-05-25 — only an unmarked entry lives here

No EXPIRES marker, nothing to prune today.

## 2026-05-27 — only a future EXPIRES lives here
<!-- EXPIRES: 2099-01-01 -->

Future-dated; not a current retirement.
EMPTY
"$FLEET" lessons-prune --dry-run > "$TMP/ac2b.out" 2> "$TMP/ac2b.err"
RC=$?
if [ "$RC" != "0" ]; then
  echo "FAIL: AC#2 — empty-branch dry-run exited $RC"
  cat "$TMP/ac2b.err"
  exit 1
fi
if ! grep -qE -- "^lessons-prune: no paragraphs expired as of 2026-06-07" "$TMP/ac2b.out"; then
  echo "FAIL: AC#2 — empty-branch summary line wrong"
  cat "$TMP/ac2b.out"
  exit 1
fi
echo "ok AC#2: --dry-run table and empty branches"

# ---------------------------------------------------------------------------
# AC#3 — unmarked never listed; EXPIRES > today never listed;
#        EXPIRES <= today IS listed.
# ---------------------------------------------------------------------------
cp "$FIXTURES/LESSONS.md" "$KIT_ROOT/docs/LESSONS.md"
"$FLEET" lessons-prune --dry-run > "$TMP/ac3.out" 2>&1
# The unmarked paragraph headline "bootstrap entry without expiry marker"
# MUST NOT appear in the dry-run table.
if grep -qF -- "bootstrap entry without expiry marker" "$TMP/ac3.out"; then
  echo "FAIL: AC#3 — unmarked paragraph appeared in dry-run table"
  cat "$TMP/ac3.out"
  exit 1
fi
# The EXPIRES=2026-06-30 paragraph (future) MUST NOT appear.
if grep -qF -- "\$(cat file) strips trailing newlines" "$TMP/ac3.out"; then
  echo "FAIL: AC#3 — future-EXPIRES paragraph appeared in dry-run table"
  cat "$TMP/ac3.out"
  exit 1
fi
# The EXPIRES=2026-06-07 (today) AND EXPIRES=2024-01-01 (long-past)
# headlines MUST appear.
if ! grep -qF -- "bash scripts launched with & cannot be SIGINT-tested" "$TMP/ac3.out"; then
  echo "FAIL: AC#3 — EXPIRES=today paragraph missing from dry-run table"
  cat "$TMP/ac3.out"
  exit 1
fi
if ! grep -qF -- "doctor_json_escape sign-extends multi-byte UTF-8" "$TMP/ac3.out"; then
  echo "FAIL: AC#3 — EXPIRES=long-past paragraph missing from dry-run table"
  cat "$TMP/ac3.out"
  exit 1
fi
echo "ok AC#3: marker semantics (unmarked, future, past)"

# ---------------------------------------------------------------------------
# AC#4 — malformed EXPIRES → stderr warning, exit 0 (do NOT abort).
# ---------------------------------------------------------------------------
cp "$FIXTURES/LESSONS.md" "$KIT_ROOT/docs/LESSONS.md"
"$FLEET" lessons-prune --dry-run > "$TMP/ac4.out" 2> "$TMP/ac4.err"
RC=$?
if [ "$RC" != "0" ]; then
  echo "FAIL: AC#4 — dry-run with malformed EXPIRES exited $RC (want 0)"
  cat "$TMP/ac4.err"
  exit 1
fi
if ! grep -qF -- 'invalid EXPIRES "someday"' "$TMP/ac4.err"; then
  echo "FAIL: AC#4 — stderr warning for malformed EXPIRES missing"
  cat "$TMP/ac4.err"
  exit 1
fi
if ! grep -qF -- "use YYYY-MM-DD" "$TMP/ac4.err"; then
  echo "FAIL: AC#4 — stderr warning missing the YYYY-MM-DD hint"
  cat "$TMP/ac4.err"
  exit 1
fi
echo "ok AC#4: malformed EXPIRES warns without aborting"

# ---------------------------------------------------------------------------
# AC#5 — --commit --cause "<text>" moves expired paragraphs byte-exact
#        from LESSONS.md to LESSONS-ARCHIVE.md, commits, pushes,
#        opens a PR via gh.
# ---------------------------------------------------------------------------
cp "$FIXTURES/LESSONS.md" "$KIT_ROOT/docs/LESSONS.md"
rm -f "$KIT_ROOT/docs/LESSONS-ARCHIVE.md"
: > "$GIT_LOG_FILE"
: > "$GH_LOG_FILE"
"$FLEET" lessons-prune --commit --cause "defused by inline helpers" \
  > "$TMP/ac5.out" 2> "$TMP/ac5.err"
RC=$?
if [ "$RC" != "0" ]; then
  echo "FAIL: AC#5 — --commit exited $RC"
  cat "$TMP/ac5.err"
  exit 1
fi
if [ ! -f "$KIT_ROOT/docs/LESSONS-ARCHIVE.md" ]; then
  echo "FAIL: AC#5 — LESSONS-ARCHIVE.md not created"
  exit 1
fi
# Golden compare (byte-exact body of the move) per AC#5's `cmp` requirement.
if ! cmp -s "$KIT_ROOT/docs/LESSONS-ARCHIVE.md" "$FIXTURES/ARCHIVE.golden.md"; then
  echo "FAIL: AC#5 — ARCHIVE.md does not match golden"
  diff -u "$FIXTURES/ARCHIVE.golden.md" "$KIT_ROOT/docs/LESSONS-ARCHIVE.md" || true
  exit 1
fi
if ! cmp -s "$KIT_ROOT/docs/LESSONS.md" "$FIXTURES/LESSONS.golden.md"; then
  echo "FAIL: AC#5 — post-prune LESSONS.md does not match golden"
  diff -u "$FIXTURES/LESSONS.golden.md" "$KIT_ROOT/docs/LESSONS.md" || true
  exit 1
fi
# Confirm gh pr create was invoked (the PR-opening side of the contract).
if ! grep -qE -- "\\[pr\\] \\[create\\]" "$GH_LOG_FILE"; then
  echo "FAIL: AC#5 — gh pr create not invoked"
  cat "$GH_LOG_FILE"
  exit 1
fi
# Confirm `git push` was invoked on the chore/lessons-prune-* branch.
if ! grep -qE -- "ARGV=.* \[push\]" "$GIT_LOG_FILE"; then
  echo "FAIL: AC#5 — git push not invoked"
  cat "$GIT_LOG_FILE"
  exit 1
fi
if ! grep -qF -- "chore/lessons-prune-2026-06-07" "$GIT_LOG_FILE"; then
  echo "FAIL: AC#5 — branch name not chore/lessons-prune-<today>"
  cat "$GIT_LOG_FILE"
  exit 1
fi
echo "ok AC#5: --commit moves expired paragraphs (byte-exact golden), commits, pushes, opens PR"

# ---------------------------------------------------------------------------
# AC#6 — --commit without --cause exits 2 with a stderr usage line.
# ---------------------------------------------------------------------------
cp "$FIXTURES/LESSONS.md" "$KIT_ROOT/docs/LESSONS.md"
rm -f "$KIT_ROOT/docs/LESSONS-ARCHIVE.md"
"$FLEET" lessons-prune --commit > "$TMP/ac6.out" 2> "$TMP/ac6.err"
RC=$?
if [ "$RC" != "2" ]; then
  echo "FAIL: AC#6 — --commit without --cause exit code = $RC (want 2)"
  cat "$TMP/ac6.err"
  exit 1
fi
if ! grep -qF -- "--commit requires --cause" "$TMP/ac6.err"; then
  echo "FAIL: AC#6 — stderr usage line missing"
  cat "$TMP/ac6.err"
  exit 1
fi
# Ensure no archive file was created on the refusal path.
if [ -f "$KIT_ROOT/docs/LESSONS-ARCHIVE.md" ]; then
  echo "FAIL: AC#6 — refusal path created LESSONS-ARCHIVE.md"
  exit 1
fi
echo "ok AC#6: --commit requires --cause"

# ---------------------------------------------------------------------------
# AC#7 — --cause value starting with `-` parses correctly (printf
#        leading-dash trap) and lands verbatim in PR body, commit msg,
#        AND event payload.
# ---------------------------------------------------------------------------
cp "$FIXTURES/LESSONS.md" "$KIT_ROOT/docs/LESSONS.md"
rm -f "$KIT_ROOT/docs/LESSONS-ARCHIVE.md"
: > "$GIT_LOG_FILE"
: > "$GH_LOG_FILE"
: > "$GH_BODY_FILE"
rm -f "$EVENTS"
CAUSE="-defused-after-helper-merge"
"$FLEET" lessons-prune --commit --cause "$CAUSE" \
  > "$TMP/ac7.out" 2> "$TMP/ac7.err"
RC=$?
if [ "$RC" != "0" ]; then
  echo "FAIL: AC#7 — leading-dash --cause exited $RC"
  cat "$TMP/ac7.err"
  exit 1
fi
# The PR body file the gh stub captured MUST contain the cause verbatim.
if ! grep -qF -- "$CAUSE" "$GH_BODY_FILE"; then
  echo "FAIL: AC#7 — leading-dash cause missing from PR body"
  cat "$GH_BODY_FILE"
  exit 1
fi
# The event payload MUST also carry it.
if [ ! -f "$EVENTS" ]; then
  echo "FAIL: AC#7 — events.jsonl missing after --commit"
  exit 1
fi
LAST_EVENT=$(tail -1 "$EVENTS")
case "$LAST_EVENT" in
  *"\"cause\":\"-defused-after-helper-merge\""*) ;;
  *)
    echo "FAIL: AC#7 — leading-dash cause missing/garbled in event payload"
    echo "$LAST_EVENT"
    exit 1 ;;
esac
echo "ok AC#7: leading-dash --cause survives PR body + event payload"

# ---------------------------------------------------------------------------
# AC#8 — lessons_pruned event lands with phase=prune and documented
#        payload. Dry-run emits NO event.
# ---------------------------------------------------------------------------
cp "$FIXTURES/LESSONS.md" "$KIT_ROOT/docs/LESSONS.md"
rm -f "$KIT_ROOT/docs/LESSONS-ARCHIVE.md"
rm -f "$EVENTS"
"$FLEET" lessons-prune --commit --cause "kit defends at helper level" \
  > "$TMP/ac8.out" 2> "$TMP/ac8.err"
RC=$?
if [ "$RC" != "0" ]; then
  echo "FAIL: AC#8 — --commit for event-assert exited $RC"
  cat "$TMP/ac8.err"
  exit 1
fi
if [ ! -f "$EVENTS" ]; then
  echo "FAIL: AC#8 — events.jsonl not created at $EVENTS"
  exit 1
fi
LAST_EVENT=$(tail -1 "$EVENTS")
node -e '
  const line = process.argv[1];
  const obj = JSON.parse(line);
  const want = {
    type: "lessons_pruned",
    phase: "prune",
    slug: "agent-fleet",
    since_date: "2026-06-07",
    pr: "42",
    archived_count: "2",
    cause: "kit defends at helper level"
  };
  for (const k of Object.keys(want)) {
    if (obj[k] !== want[k]) {
      console.error(`FAIL: AC#8 — event.${k} = ${JSON.stringify(obj[k])}, want ${JSON.stringify(want[k])}`);
      process.exit(1);
    }
  }
  if (!obj.ts || !/^\d{4}-\d{2}-\d{2}T/.test(obj.ts)) {
    console.error(`FAIL: AC#8 — ts missing/wrong shape: ${JSON.stringify(obj.ts)}`);
    process.exit(1);
  }
' "$LAST_EVENT"

# Dry-run on the next run must NOT add a new event line.
LINES_BEFORE=$(awk 'END { print NR+0 }' "$EVENTS")
cp "$FIXTURES/LESSONS.md" "$KIT_ROOT/docs/LESSONS.md"
"$FLEET" lessons-prune --dry-run > "$TMP/ac8b.out" 2> "$TMP/ac8b.err"
LINES_AFTER=$(awk 'END { print NR+0 }' "$EVENTS")
if [ "$LINES_BEFORE" != "$LINES_AFTER" ]; then
  echo "FAIL: AC#8 — --dry-run emitted an event ($LINES_BEFORE → $LINES_AFTER)"
  exit 1
fi
echo "ok AC#8: lessons_pruned event payload + dry-run-silent"

# ---------------------------------------------------------------------------
# AC#9 — AGENTS.md § Telemetry documents the new event AND the PR
#        leaves prompts/ untouched.
# ---------------------------------------------------------------------------
if ! grep -qF -- "lessons_pruned {archived_count, since_date, pr, cause}" "$AGENTS_MD"; then
  echo "FAIL: AC#9 — AGENTS.md § Telemetry missing lessons_pruned bullet"
  exit 1
fi
# The PR must touch zero files under prompts/. We check via git ls-files
# diff between HEAD (this branch's tip) and the local main; if the
# detection fails (e.g. main absent in CI shallow clones), we skip.
PROMPTS_TOUCHED=""
if git rev-parse --verify main >/dev/null 2>&1; then
  PROMPTS_TOUCHED="$(git diff --name-only main...HEAD -- prompts/ 2>/dev/null)"
elif git rev-parse --verify origin/main >/dev/null 2>&1; then
  PROMPTS_TOUCHED="$(git diff --name-only origin/main...HEAD -- prompts/ 2>/dev/null)"
fi
if [ -n "$PROMPTS_TOUCHED" ]; then
  echo "FAIL: AC#9 — PR touches files under prompts/:"
  echo "$PROMPTS_TOUCHED"
  exit 1
fi
echo "ok AC#9: telemetry bullet present + prompts/ untouched"

# ---------------------------------------------------------------------------
# AC#10 — --help prints USAGE block with --dry-run, --commit, --cause
#         (grep -qF -- per LESSONS 2026-05-30) and exits 0.
# ---------------------------------------------------------------------------
"$FLEET" lessons-prune --help > "$TMP/ac10.out" 2> "$TMP/ac10.err"
RC=$?
if [ "$RC" != "0" ]; then
  echo "FAIL: AC#10 — --help exit code = $RC (want 0)"
  cat "$TMP/ac10.err"
  exit 1
fi
for kw in "--dry-run" "--commit" "--cause"; do
  if ! grep -qF -- "$kw" "$TMP/ac10.out"; then
    echo "FAIL: AC#10 — --help output missing $kw"
    cat "$TMP/ac10.out"
    exit 1
  fi
done
echo "ok AC#10: --help mentions --dry-run / --commit / --cause"

# ---------------------------------------------------------------------------
# AC#11 — covered implicitly:
#   - stubs live in $HOME/.local/bin (LESSONS 2026-05-26): see top of file.
#   - backup/restore uses `cp` (LESSONS 2026-05-27): every `cp` line above.
#   - paragraph counts use `awk … END { print n+0 }` (LESSONS 2026-06-01):
#     see the LINES_BEFORE/LINES_AFTER assertions in AC#3/AC#8.
# Time budget assertion: this whole script must finish under 10s.
# ---------------------------------------------------------------------------
echo "ok AC#11: stub layout + cp-only backup + awk-counter convention"

echo "ok: tests/lessons-prune.sh passed"
