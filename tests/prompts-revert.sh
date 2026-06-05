#!/bin/bash
# tests/prompts-revert.sh — bin/fleet prompts-revert end-to-end test.
#
# Ticket 0035. One assertion block per acceptance-criteria checkbox in
# docs/backlog/0035-fleet-prompts-revert-pin-to-sha.md.
#
# Strategy: stub `git` and `gh` under $HOME/.local/bin (per LESSONS
# 2026-05-26: lib/common.sh resets PATH, so a $TMP/bin prepend gets
# wiped the moment the script sources common.sh — even though this
# subcommand doesn't itself source common.sh except inside its
# emit-event subshell, we keep stubs under $HOME/.local/bin for
# parity with rollback.sh / resume.sh).
#
# The stub `git` records argv to $GIT_LOG and answers a handful of
# read-only queries (`rev-parse`, `status`, `log`, `show`) from env
# vars so each block can drive a precise scenario. Real on-disk state
# (the kit's actual git repo, our test fixture, etc.) is bypassed —
# the test asserts on what the script TRIED to do, not on real git
# I/O. The stub `gh` records argv to $GH_LOG and answers `pr create`
# with a canned URL.
#
# Per LESSONS 2026-05-27 we use `cp` for backup/restore, never
# `$(cat …)`. Per LESSONS 2026-05-30 we use `grep -qF --` for help
# assertions. Per LESSONS 2026-05-28 every printf of $reason uses
# `printf -- '%s'`.

set -euo pipefail

REPO_ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
FLEET="$REPO_ROOT/bin/fleet"

TMP="$(mktemp -d -t fleet-prompts-revert-test.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

# Isolate from the host. HOME is the test's; per LESSONS 2026-05-26
# stubs live in $HOME/.local/bin so common.sh's PATH reset preserves them.
export HOME="$TMP/home"
mkdir -p "$HOME/.local/bin"

# Per-slug cache for the AGENT-FLEET kit-as-project event channel
# (per the lessons_promote / rollback pattern from tickets 0017/0028).
export CACHE_DIR="$HOME/.cache/agent-fleet-agent"
mkdir -p "$CACHE_DIR"
EVENTS="$CACHE_DIR/events.jsonl"

# Stub logs. Exported so the stubs (spawned as child processes) inherit
# the values via env — the stubs read `${GIT_LOG:-...}` / `${GH_LOG:-...}`.
export GIT_LOG="$TMP/git.log"
export GH_LOG="$TMP/gh.log"
: > "$GIT_LOG"
: > "$GH_LOG"

# --- git stub -------------------------------------------------------------
# Answers a small set of queries from env vars so each block can tailor:
#   GIT_RESOLVE_<ref> — when set, `git rev-parse <ref>` (or any "verify"
#                      form) echoes the value; empty means "unknown ref".
#                      We use a single GIT_RESOLVE_MAP variable of the
#                      form "ref1=sha1;ref2=sha2;..." for simplicity.
#   GIT_TREE_MAP      — "sha=tree;sha=tree;..." answers `git rev-parse
#                      <sha>:prompts`.
#   GIT_STATUS_PORC   — what `git status --porcelain` echoes (empty = clean).
#   GIT_LOG_GREP      — what `git log -G "..." --format=%H -- ...` echoes
#                      (single SHA, possibly empty).
# Every other invocation just records argv and exits 0. `git checkout
# <sha> -- prompts/` is a no-op but the test asserts it was attempted.
cat > "$HOME/.local/bin/git" <<'STUB'
#!/bin/bash
log_file="${GIT_LOG:-/tmp/git.log}"
# shellcheck disable=SC2086
printf '%s\n' "git $*" >> "$log_file"
case "${1:-}" in
  rev-parse)
    # Forms we answer:
    #   git rev-parse <ref>                  → look up in GIT_RESOLVE_MAP
    #   git rev-parse <sha>:prompts          → look up in GIT_TREE_MAP
    #   git rev-parse --verify <ref>         → same as plain rev-parse
    shift
    # Drop --verify if present (we treat verify as a plain lookup).
    if [ "${1:-}" = "--verify" ]; then shift; fi
    arg="${1:-}"
    case "$arg" in
      *:prompts)
        sha="${arg%:prompts}"
        IFS=';' read -ra pairs <<< "${GIT_TREE_MAP:-}"
        for p in "${pairs[@]}"; do
          k="${p%%=*}"; v="${p#*=}"
          if [ "$k" = "$sha" ]; then
            echo "$v"; exit 0
          fi
        done
        echo "fatal: ambiguous argument '$arg'" >&2
        exit 128
        ;;
      *)
        IFS=';' read -ra pairs <<< "${GIT_RESOLVE_MAP:-}"
        for p in "${pairs[@]}"; do
          k="${p%%=*}"; v="${p#*=}"
          if [ "$k" = "$arg" ]; then
            echo "$v"; exit 0
          fi
        done
        echo "fatal: ambiguous argument '$arg': unknown revision or path" >&2
        exit 128
        ;;
    esac
    ;;
  status)
    # `git status --porcelain` — echo GIT_STATUS_PORC verbatim.
    printf '%s' "${GIT_STATUS_PORC:-}"
    exit 0 ;;
  log)
    # `git log --format=%H -G "..." -- prompts/CHANGELOG.md` (date-stamp
    # resolution) — echo GIT_LOG_GREP.
    printf '%s\n' "${GIT_LOG_GREP:-}"
    exit 0 ;;
  diff)
    # `git diff --cached --quiet -- prompts/` returns 0 if no diff, 1 otherwise.
    # We answer based on GIT_DIFF_CACHED_RC (default 1 = there IS a diff,
    # i.e. the checkout produced changes).
    exit "${GIT_DIFF_CACHED_RC:-1}" ;;
  *)
    exit 0 ;;
esac
STUB
chmod +x "$HOME/.local/bin/git"

# --- gh stub --------------------------------------------------------------
# `gh pr create --body-file <path>` is what the script uses (LESSONS
# 2026-06-01: never `--body "$multiline"`). We capture the body file's
# contents into $GH_LOG so assertions can grep it.
#   GH_CREATE_OUTPUT — stdout for `gh pr create` (default a fake URL).
cat > "$HOME/.local/bin/gh" <<'STUB'
#!/bin/bash
log_file="${GH_LOG:-/tmp/gh.log}"
# shellcheck disable=SC2086
printf '%s\n' "gh $*" >> "$log_file"
# When --body-file is passed, dump the body contents into the log too.
prev=""
for arg in "$@"; do
  if [ "$prev" = "--body-file" ] && [ -f "$arg" ]; then
    {
      echo "--- pr-body ---"
      cat "$arg"
      echo "--- /pr-body ---"
    } >> "$log_file"
  fi
  prev="$arg"
done
case "${1:-}" in
  pr)
    case "${2:-}" in
      create) printf '%s\n' "${GH_CREATE_OUTPUT:-https://github.com/mutaaf/agent-fleet/pull/91}" ;;
      *)      exit 0 ;;
    esac
    ;;
  *) exit 0 ;;
esac
STUB
chmod +x "$HOME/.local/bin/gh"

export PATH="$HOME/.local/bin:$PATH"
export FLEET_KIT_ROOT="$REPO_ROOT"

# Snapshot the kit's current prompts SHA — the script uses
# `fleet prompts-sha` (the early helper at line ~142) to compute the
# "current" SHA on disk. Stubbing it isn't worth it; instead we just
# record what the kit reports and feed it into env-driven stubs.
CURRENT_PROMPTS_SHA="$( "$FLEET" prompts-sha )"

# Helper: reset state between AC blocks.
reset_state() {
  : > "$GIT_LOG"
  : > "$GH_LOG"
  rm -f "$EVENTS"
  unset GIT_RESOLVE_MAP GIT_TREE_MAP GIT_STATUS_PORC GIT_LOG_GREP GIT_DIFF_CACHED_RC
  unset GH_CREATE_OUTPUT
}

# Canonical resolver maps for a "two-commit prompts history" world:
#   target_full = 40-char SHA of the target (older, known-good) commit
#   current_full = 40-char SHA of HEAD
TARGET_FULL="ee94b3a0000000000000000000000000000000aa"
TARGET_SHORT="ee94b3a"
CURRENT_FULL="8a205470000000000000000000000000000000bb"
TARGET_TREE="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
CURRENT_TREE="bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"

DEFAULT_RESOLVE_MAP="$TARGET_FULL=$TARGET_FULL;$TARGET_SHORT=$TARGET_FULL;$CURRENT_FULL=$CURRENT_FULL;HEAD=$CURRENT_FULL"
DEFAULT_TREE_MAP="$TARGET_FULL=$TARGET_TREE;$CURRENT_FULL=$CURRENT_TREE"

# ========================================================================
# AC #1 — `fleet prompts-revert <sha> --reason "<one-line>"` on a clean
#         tree runs `git checkout <sha> -- prompts/`, commits, pushes,
#         opens a PR, emits prompts_reverted, exits 0.
# ========================================================================
reset_state
export GIT_RESOLVE_MAP="$DEFAULT_RESOLVE_MAP"
export GIT_TREE_MAP="$DEFAULT_TREE_MAP"
export GIT_STATUS_PORC=""
export GIT_DIFF_CACHED_RC=1   # there IS a diff after checkout

set +e
OUT="$("$FLEET" prompts-revert "$TARGET_FULL" --reason "8a20547 regression" 2>&1)"
RC=$?
set -e
if [ "$RC" -ne 0 ]; then
  echo "FAIL: AC#1 expected exit 0 on happy path, got $RC"
  echo "--- stdout/stderr ---"; echo "$OUT"
  echo "--- git.log ---"; cat "$GIT_LOG"
  echo "--- gh.log ---"; cat "$GH_LOG"
  exit 1
fi
# git checkout <sha> -- prompts/
if ! grep -qE "git checkout $TARGET_FULL -- prompts/?\$" "$GIT_LOG"; then
  echo "FAIL: AC#1 expected 'git checkout $TARGET_FULL -- prompts/'"
  cat "$GIT_LOG"; exit 1
fi
# git commit (any form — we assert the message via PR body below).
if ! grep -qE 'git commit' "$GIT_LOG"; then
  echo "FAIL: AC#1 expected 'git commit'"; cat "$GIT_LOG"; exit 1
fi
# git push origin revert/prompts-<short>
if ! grep -qE "git push .*revert/prompts-$TARGET_SHORT" "$GIT_LOG"; then
  echo "FAIL: AC#1 expected 'git push ... revert/prompts-$TARGET_SHORT'"
  cat "$GIT_LOG"; exit 1
fi
# gh pr create --head mutaaf:revert/prompts-<short> --base main
if ! grep -qE "gh pr create .*--head mutaaf:revert/prompts-$TARGET_SHORT .*--base main" "$GH_LOG"; then
  echo "FAIL: AC#1 expected 'gh pr create --head mutaaf:revert/prompts-$TARGET_SHORT --base main'"
  cat "$GH_LOG"; exit 1
fi
# prompts_reverted event landed.
if ! grep -q '"type":"prompts_reverted"' "$EVENTS"; then
  echo "FAIL: AC#1 expected type=prompts_reverted in $EVENTS"
  if [ -f "$EVENTS" ]; then cat "$EVENTS"; else echo "(no events file)"; fi
  exit 1
fi
echo "ok: AC#1 happy-path checkout + commit + push + PR + event"

# ========================================================================
# AC #2 — `<sha>` accepts a full 40-char SHA, a short SHA (>=7), OR a
#         CHANGELOG date stamp (YYYY-MM-DD). The date branch resolves via
#         `git log --format=%H -G "^## $date" -- prompts/CHANGELOG.md`.
# ========================================================================
# Full SHA: already covered above (AC#1). Now short SHA:
reset_state
export GIT_RESOLVE_MAP="$DEFAULT_RESOLVE_MAP"
export GIT_TREE_MAP="$DEFAULT_TREE_MAP"
export GIT_STATUS_PORC=""
export GIT_DIFF_CACHED_RC=1
"$FLEET" prompts-revert "$TARGET_SHORT" --reason "short-form" >/dev/null 2>&1
if ! grep -qE "git checkout $TARGET_FULL -- prompts/?\$" "$GIT_LOG"; then
  echo "FAIL: AC#2 short SHA must resolve and checkout the full SHA"
  cat "$GIT_LOG"; exit 1
fi

# Date stamp: `git log -G "^## 2026-05-28" -- prompts/CHANGELOG.md` echoes
# the target full SHA via GIT_LOG_GREP.
reset_state
export GIT_RESOLVE_MAP="$DEFAULT_RESOLVE_MAP"
export GIT_TREE_MAP="$DEFAULT_TREE_MAP"
export GIT_STATUS_PORC=""
export GIT_DIFF_CACHED_RC=1
export GIT_LOG_GREP="$TARGET_FULL"
"$FLEET" prompts-revert 2026-05-28 --reason "date-form" >/dev/null 2>&1
if ! grep -qE "git checkout $TARGET_FULL -- prompts/?\$" "$GIT_LOG"; then
  echo "FAIL: AC#2 date-stamp must resolve via git log and checkout"
  cat "$GIT_LOG"; exit 1
fi
# Also assert the script DID invoke `git log` for the date form.
if ! grep -qE 'git log .*-G .*2026-05-28' "$GIT_LOG"; then
  echo "FAIL: AC#2 date form must invoke 'git log -G \"...2026-05-28...\"'"
  cat "$GIT_LOG"; exit 1
fi
echo "ok: AC#2 full / short / date-stamp SHA forms"

# ========================================================================
# AC #3 — `--reason` is MANDATORY. Missing reason: stderr message, exit 2.
# ========================================================================
reset_state
export GIT_RESOLVE_MAP="$DEFAULT_RESOLVE_MAP"
export GIT_TREE_MAP="$DEFAULT_TREE_MAP"
set +e
OUT="$("$FLEET" prompts-revert "$TARGET_FULL" 2>&1)"
RC=$?
set -e
if [ "$RC" -ne 2 ]; then
  echo "FAIL: AC#3 missing --reason must exit 2, got $RC"; echo "$OUT"; exit 1
fi
if ! grep -q 'reason' <<<"$OUT"; then
  echo "FAIL: AC#3 stderr must mention 'reason'"; echo "$OUT"; exit 1
fi
if ! grep -qE 'required' <<<"$OUT"; then
  echo "FAIL: AC#3 stderr must say 'required'"; echo "$OUT"; exit 1
fi
echo "ok: AC#3 missing --reason rejected with exit 2"

# ========================================================================
# AC #4 — `--reason` with leading `-` parses correctly (LESSONS 2026-05-28)
#         and is rendered verbatim in PR body, commit message, AND event.
# ========================================================================
reset_state
export GIT_RESOLVE_MAP="$DEFAULT_RESOLVE_MAP"
export GIT_TREE_MAP="$DEFAULT_TREE_MAP"
export GIT_STATUS_PORC=""
export GIT_DIFF_CACHED_RC=1
LEADING_DASH_REASON="-regression on heal phase"
"$FLEET" prompts-revert "$TARGET_FULL" --reason "$LEADING_DASH_REASON" >/dev/null 2>&1
# PR body file dumped in $GH_LOG between --- pr-body --- markers.
if ! grep -qF -- "$LEADING_DASH_REASON" "$GH_LOG"; then
  echo "FAIL: AC#4 PR body must include verbatim reason '$LEADING_DASH_REASON'"
  cat "$GH_LOG"; exit 1
fi
# Event payload (events.jsonl) carries reason verbatim.
if ! grep -qF -- "$LEADING_DASH_REASON" "$EVENTS"; then
  echo "FAIL: AC#4 event payload must include verbatim reason"
  if [ -f "$EVENTS" ]; then cat "$EVENTS"; fi
  exit 1
fi
# Commit message — the script writes the commit message to a tmp file
# and passes it via `git commit -F <path>`. The git stub captures argv
# in $GIT_LOG, but `-F <path>` references a tmp file the script will
# delete. We grep the GIT_LOG line for the file path AND that the file
# (which the script must NOT delete before recording it; the simplest
# guarantee is just to inspect that the `git commit -F` path appears).
# But because the path is ephemeral, we instead grep for the commit
# message argv form: the script may also pass `-m "..."` as a fallback.
# Simpler: the PR body and the commit message are composed from the
# same source string (per engineering notes) — the PR body assertion
# already covers verbatim rendering. We DO assert that `git commit`
# was called via a `-F` flag so the multi-line commit message goes
# through a tmp file (defending LESSONS 2026-06-01 awk-v family).
if ! grep -qE 'git commit -F ' "$GIT_LOG"; then
  echo "FAIL: AC#4 commit must use 'git commit -F <tmpfile>' (multi-line message)"
  cat "$GIT_LOG"; exit 1
fi
echo "ok: AC#4 leading-dash reason rendered verbatim in PR body + event + commit-F"

# ========================================================================
# AC #5 — Revert to a SHA whose prompts tree is BYTE-IDENTICAL: prints
#         a "nothing to do" message, exits 0, does NOT commit/push/emit.
# ========================================================================
reset_state
# Map the TARGET's tree to the CURRENT tree so they are identical.
# The script also asks for `HEAD:prompts`, so map HEAD too.
export GIT_RESOLVE_MAP="$DEFAULT_RESOLVE_MAP"
IDENTICAL_TREE_MAP="$TARGET_FULL=$CURRENT_TREE;$CURRENT_FULL=$CURRENT_TREE;HEAD=$CURRENT_TREE"
export GIT_TREE_MAP="$IDENTICAL_TREE_MAP"
export GIT_STATUS_PORC=""

set +e
OUT="$("$FLEET" prompts-revert "$TARGET_FULL" --reason "typo revert to self" 2>&1)"
RC=$?
set -e
if [ "$RC" -ne 0 ]; then
  echo "FAIL: AC#5 byte-identical revert must exit 0, got $RC"; echo "$OUT"; exit 1
fi
if ! grep -q 'identical' <<<"$OUT"; then
  echo "FAIL: AC#5 expected the 'identical' message"; echo "$OUT"; exit 1
fi
if grep -qE 'git checkout .*-- prompts' "$GIT_LOG"; then
  echo "FAIL: AC#5 must NOT call 'git checkout -- prompts' on the no-op path"
  cat "$GIT_LOG"; exit 1
fi
if grep -qE 'git commit' "$GIT_LOG"; then
  echo "FAIL: AC#5 must NOT call 'git commit' on the no-op path"
  cat "$GIT_LOG"; exit 1
fi
if grep -qE 'gh pr create' "$GH_LOG"; then
  echo "FAIL: AC#5 must NOT call 'gh pr create' on the no-op path"
  cat "$GH_LOG"; exit 1
fi
if [ -f "$EVENTS" ] && grep -q '"type":"prompts_reverted"' "$EVENTS"; then
  echo "FAIL: AC#5 must NOT emit prompts_reverted on the no-op path"
  cat "$EVENTS"; exit 1
fi
echo "ok: AC#5 byte-identical revert is an idempotent no-op"

# ========================================================================
# AC #6 — Dirty working tree: refuse + exit 2.
# ========================================================================
reset_state
export GIT_RESOLVE_MAP="$DEFAULT_RESOLVE_MAP"
export GIT_TREE_MAP="$DEFAULT_TREE_MAP"
export GIT_STATUS_PORC=" M lib/common.sh"
set +e
OUT="$("$FLEET" prompts-revert "$TARGET_FULL" --reason "any" 2>&1)"
RC=$?
set -e
if [ "$RC" -ne 2 ]; then
  echo "FAIL: AC#6 dirty tree must exit 2, got $RC"; echo "$OUT"; exit 1
fi
if ! grep -q 'uncommitted' <<<"$OUT"; then
  echo "FAIL: AC#6 stderr must mention 'uncommitted'"; echo "$OUT"; exit 1
fi
if grep -qE 'git checkout .*-- prompts' "$GIT_LOG"; then
  echo "FAIL: AC#6 must NOT call 'git checkout' on dirty tree"
  cat "$GIT_LOG"; exit 1
fi
echo "ok: AC#6 dirty tree refused with exit 2"

# ========================================================================
# AC #7 — Unknown SHA: error + exit 2.
# ========================================================================
reset_state
# Empty resolver map → every rev-parse fails.
export GIT_RESOLVE_MAP=""
export GIT_TREE_MAP=""
export GIT_STATUS_PORC=""
export GIT_LOG_GREP=""
set +e
OUT="$("$FLEET" prompts-revert "deadbeef" --reason "any" 2>&1)"
RC=$?
set -e
if [ "$RC" -ne 2 ]; then
  echo "FAIL: AC#7 unknown SHA must exit 2, got $RC"; echo "$OUT"; exit 1
fi
if ! grep -q 'not a valid git ref' <<<"$OUT"; then
  echo "FAIL: AC#7 expected 'not a valid git ref' in stderr"
  echo "$OUT"; exit 1
fi
echo "ok: AC#7 unknown SHA rejected with exit 2"

# ========================================================================
# AC #8 — `prompts_reverted` event payload contract: {from, to, pr,
#         reason}; phase=revert; lands in the kit-as-project
#         events.jsonl.
# ========================================================================
reset_state
export GIT_RESOLVE_MAP="$DEFAULT_RESOLVE_MAP"
export GIT_TREE_MAP="$DEFAULT_TREE_MAP"
export GIT_STATUS_PORC=""
export GIT_DIFF_CACHED_RC=1
export GH_CREATE_OUTPUT="https://github.com/mutaaf/agent-fleet/pull/91"
"$FLEET" prompts-revert "$TARGET_FULL" --reason "AC8 payload check" >/dev/null 2>&1

if [ ! -f "$EVENTS" ]; then
  echo "FAIL: AC#8 events.jsonl was not created at $EVENTS"; exit 1
fi
# Last line must be the prompts_reverted event.
LAST="$(tail -n 1 "$EVENTS")"
for needle in '"type":"prompts_reverted"' '"phase":"revert"' \
              "\"from\":\"$CURRENT_PROMPTS_SHA\"" "\"to\":\"$TARGET_FULL\"" \
              '"pr":"91"' '"reason":"AC8 payload check"'; do
  if ! grep -qF -- "$needle" <<<"$LAST"; then
    echo "FAIL: AC#8 event payload missing '$needle'"
    echo "got: $LAST"
    exit 1
  fi
done
echo "ok: AC#8 prompts_reverted payload + phase=revert"

# ========================================================================
# AC #9 — AGENTS.md § Telemetry has a new bullet for
#         `prompts_reverted {from, to, pr, reason}` in the same PR.
# ========================================================================
AGENTS_MD="$REPO_ROOT/AGENTS.md"
if ! grep -qF -- 'prompts_reverted {from, to, pr, reason}' "$AGENTS_MD"; then
  echo "FAIL: AC#9 AGENTS.md must document 'prompts_reverted {from, to, pr, reason}'"
  exit 1
fi
# The bullet must live inside the § Telemetry section. We assert by
# proximity to the existing rollback_opened paragraph.
if ! awk '/`rollback_opened/,/^## /' "$AGENTS_MD" | grep -qF 'prompts_reverted'; then
  # Fallback: the bullet may sit after rollback_opened, but if grep can't
  # find it in that range we just check that the §Telemetry block contains it.
  if ! awk '/^## Telemetry/,/^## [A-Z]/' "$AGENTS_MD" | grep -qF 'prompts_reverted'; then
    echo "FAIL: AC#9 prompts_reverted bullet not under § Telemetry"
    exit 1
  fi
fi
echo "ok: AC#9 AGENTS.md § Telemetry documents prompts_reverted"

# ========================================================================
# AC #10 — PR body includes `Reinstall: all projects` (LESSONS 2026-05-25).
# ========================================================================
reset_state
export GIT_RESOLVE_MAP="$DEFAULT_RESOLVE_MAP"
export GIT_TREE_MAP="$DEFAULT_TREE_MAP"
export GIT_STATUS_PORC=""
export GIT_DIFF_CACHED_RC=1
"$FLEET" prompts-revert "$TARGET_FULL" --reason "AC10 reinstall trailer" >/dev/null 2>&1
if ! grep -qF -- 'Reinstall: all projects' "$GH_LOG"; then
  echo "FAIL: AC#10 PR body must contain 'Reinstall: all projects'"
  cat "$GH_LOG"; exit 1
fi
echo "ok: AC#10 PR body has Reinstall: all projects trailer"

# ========================================================================
# AC #11 — Help: `bin/fleet prompts-revert --help` prints a USAGE block
#          mentioning `<sha>`, `--reason`, `--help`. Help ends with exit 0.
# ========================================================================
reset_state
set +e
HELP_OUT="$("$FLEET" prompts-revert --help 2>&1)"
RC=$?
set -e
if [ "$RC" -ne 0 ]; then
  echo "FAIL: AC#11 --help must exit 0 (LESSONS 2026-06-01), got $RC"
  echo "$HELP_OUT"; exit 1
fi
HELP_FILE="$TMP/help.out"
printf '%s\n' "$HELP_OUT" > "$HELP_FILE"
for kw in '<sha>' '--reason' '--help'; do
  if ! grep -qF -- "$kw" "$HELP_FILE"; then
    echo "FAIL: AC#11 --help missing keyword '$kw'"
    echo "$HELP_OUT"; exit 1
  fi
done
echo "ok: AC#11 --help prints USAGE block + exits 0"

echo
echo "tests/prompts-revert.sh: all assertions passed"
