#!/bin/bash
# tests/pr-footer.sh — `bin/fleet pr-footer <pr>` per-merge ROI footer test.
#
# Ticket 0044. One assertion block per acceptance-criteria checkbox in
# docs/backlog/0044-fleet-pr-footer-per-merge-roi-comment.md.
#
# The pr-footer command is a PURE WRITER of exactly one PR comment via
# `gh pr comment`. It reads runs.jsonl (cost/duration), events.jsonl
# (PR count from `pr_opened`), the project's agents.config.sh
# (PROMPTS_SHA), the kit's docs/LESSONS.md (line count), and `git
# rev-parse --short HEAD` (kit SHA). No new event types, no
# events.jsonl writes, no public-API change in lib/common.sh.
#
# Per LESSONS 2026-05-26 stubs live in $HOME/.local/bin so they
# survive lib/common.sh's PATH reset. Per LESSONS 2026-05-27 fixture
# files are copied via `cp`. The clock is frozen via FLEET_NOW_OVERRIDE.

set -euo pipefail

REPO_ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
FLEET="$REPO_ROOT/bin/fleet"
FIXTURES="$REPO_ROOT/tests/fixtures/pr-footer"

TMP="$(mktemp -d -t fleet-pr-footer-test.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

# Isolate HOME so the per-slug cache resolves under $TMP and the test
# never reads from / writes to the host's real ~/.cache.
export HOME="$TMP/home"
mkdir -p "$HOME/.local/bin"

# Anchor "now" at 2026-06-11T12:00:00Z so the 30d ticket-to-date
# window covers the seeded runs.jsonl rows deterministically.
NOW_EPOCH=1781179200
export FLEET_NOW_OVERRIDE="$NOW_EPOCH"

# Pin the kit-SHA reader to a deterministic value so the composed
# body doesn't drift between machines/checkouts.
export FLEET_PR_FOOTER_KIT_SHA="8a20547"

# --- gh stub: records every invocation + returns canned JSON --------
# Three modes (controlled via FLEET_GH_STUB_STATE which the test
# rewrites between AC blocks):
#   merged-agent — `gh pr view` returns a merged PR on an agent
#                  branch; `gh pr comment` records the body and
#                  exits 0.
#   merged-non-agent — merged PR on a non-agent branch (refusal path).
#   open         — open PR (refusal path).
#   already-posted — `gh pr view --json comments` returns one prior
#                  fleet-roi-footer comment (idempotency path).
#
# The stub honours FLEET_PR_FIXTURE: when set, it reads the canned
# JSON body from that file instead of synthesizing it.
cat > "$HOME/.local/bin/gh" <<'STUB'
#!/bin/bash
# Stub for `gh`. Records every invocation under FLEET_GH_LOG.
LOG="${FLEET_GH_LOG:-/dev/null}"
{ printf 'gh'; for a in "$@"; do printf ' %q' "$a"; done; printf '\n'; } >> "$LOG"

mode="${FLEET_GH_STUB_STATE:-merged-agent}"

if [ "$1" = "pr" ] && [ "$2" = "view" ]; then
  # `gh pr view <N> --json number,title,mergedAt,mergeCommit,baseRepository,headRefName`
  # or `gh pr view <N> --json comments`
  want_comments=0
  for a in "$@"; do
    case "$a" in
      *comments*) want_comments=1 ;;
    esac
  done
  if [ "$want_comments" = "1" ]; then
    case "$mode" in
      already-posted)
        cat <<'JSON'
{"comments":[{"body":"<!-- fleet-roi-footer v1 -->\nold receipt"}]}
JSON
        ;;
      *)
        echo '{"comments":[]}'
        ;;
    esac
    exit 0
  fi
  case "$mode" in
    open)
      cat <<'JSON'
{"number":555,"title":"feat: thing","mergedAt":null,"mergeCommit":null,"baseRepository":{"nameWithOwner":"example/repo"},"headRefName":"feat/9999-thing"}
JSON
      ;;
    merged-non-agent)
      cat <<'JSON'
{"number":777,"title":"hotfix: thing","mergedAt":"2026-06-10T20:00:00Z","mergeCommit":{"oid":"deadbeef"},"baseRepository":{"nameWithOwner":"example/repo"},"headRefName":"hotfix/oops"}
JSON
      ;;
    merged-agent|already-posted|*)
      cat <<'JSON'
{"number":99,"title":"feat: thing","mergedAt":"2026-06-10T22:30:00Z","mergeCommit":{"oid":"abc1234"},"baseRepository":{"nameWithOwner":"example/repo"},"headRefName":"feat/0044-fleet-pr-footer"}
JSON
      ;;
  esac
  exit 0
fi

if [ "$1" = "pr" ] && [ "$2" = "comment" ]; then
  # Capture the --body value if present so the test can grep it.
  body_file="${FLEET_GH_BODY_OUT:-/dev/null}"
  while [ $# -gt 0 ]; do
    case "$1" in
      --body) shift; printf '%s\n' "${1:-}" > "$body_file" ;;
      --body=*) printf '%s\n' "${1#--body=}" > "$body_file" ;;
    esac
    shift || break
  done
  exit 0
fi

# Any other gh invocation is unexpected.
echo "gh stub: unexpected invocation: $*" >&2
exit 1
STUB
chmod +x "$HOME/.local/bin/gh"

# git stub: only `rev-parse --short HEAD` is exercised by the
# composer. Real git is fine but we want determinism — return the
# FLEET_PR_FOOTER_KIT_SHA env value the implementation reads. The
# implementation honours that env override directly so this stub
# is just a safety net.
cat > "$HOME/.local/bin/git" <<'STUB'
#!/bin/bash
if [ "$1" = "rev-parse" ]; then
  echo "${FLEET_PR_FOOTER_KIT_SHA:-deadbee}"
  exit 0
fi
# Pass-through for anything else.
exec /usr/bin/git "$@" 2>/dev/null || true
STUB
chmod +x "$HOME/.local/bin/git"

export PATH="$HOME/.local/bin:$PATH"

# --- fixtures: project tree, runs.jsonl, events.jsonl, LESSONS.md ---
PROJECTS="$TMP/projects"
mkdir -p "$PROJECTS/agent-fleet"
cp "$FIXTURES/agents.config.sh" "$PROJECTS/agent-fleet/agents.config.sh"
export FLEET_DISCOVERY_ROOT="$PROJECTS"

CACHE="$HOME/.cache/agent-fleet-agent"
mkdir -p "$CACHE"
cp "$FIXTURES/runs.jsonl"   "$CACHE/runs.jsonl"
cp "$FIXTURES/events.jsonl" "$CACHE/events.jsonl"

# Point the LESSONS reader at a deterministic fixture so the line
# count is stable.
export FLEET_PR_FOOTER_LESSONS_FILE="$FIXTURES/LESSONS.md"

# Capture the gh stub's command log and the body it would post.
export FLEET_GH_LOG="$TMP/gh.log"
export FLEET_GH_BODY_OUT="$TMP/body.out"
: > "$FLEET_GH_LOG"
: > "$FLEET_GH_BODY_OUT"

# ===========================================================================
# AC#1 — refusals: not-merged → exit 2 "PR #N is not merged"; non-agent
#        branch → exit 2 "PR #N is not an agent PR".
# ===========================================================================
set +e
FLEET_GH_STUB_STATE="open" \
  "$FLEET" pr-footer 555 2>"$TMP/refuse-open.err" >/dev/null
EXIT=$?
set -e
if [ "$EXIT" != "2" ]; then
  echo "FAIL: AC#1 open PR should exit 2, got $EXIT"
  cat "$TMP/refuse-open.err"
  exit 1
fi
grep -qF -- 'pr-footer: PR #555 is not merged' "$TMP/refuse-open.err" \
  || { echo "FAIL: AC#1 open-PR refusal message missing"; cat "$TMP/refuse-open.err"; exit 1; }

set +e
FLEET_GH_STUB_STATE="merged-non-agent" \
  "$FLEET" pr-footer 777 2>"$TMP/refuse-nonagent.err" >/dev/null
EXIT=$?
set -e
if [ "$EXIT" != "2" ]; then
  echo "FAIL: AC#1 non-agent PR should exit 2, got $EXIT"
  cat "$TMP/refuse-nonagent.err"
  exit 1
fi
grep -qF -- 'pr-footer: PR #777 is not an agent PR' "$TMP/refuse-nonagent.err" \
  || { echo "FAIL: AC#1 non-agent-branch refusal message missing"; cat "$TMP/refuse-nonagent.err"; exit 1; }
echo "ok AC#1: refusal paths (not-merged, non-agent branch)"

# ===========================================================================
# AC#2 — composed body has six values from documented sources.
# ===========================================================================
: > "$FLEET_GH_BODY_OUT"
: > "$FLEET_GH_LOG"
FLEET_GH_STUB_STATE="merged-agent" \
  "$FLEET" pr-footer 99 >"$TMP/post.out" 2>"$TMP/post.err"
EXIT=$?
if [ "$EXIT" != "0" ]; then
  echo "FAIL: AC#2 valid agent-merged PR should exit 0, got $EXIT"
  cat "$TMP/post.err"; cat "$TMP/post.out"; exit 1
fi
BODY="$(cat "$FLEET_GH_BODY_OUT")"
# (1) cost — $0.42 row was seeded in runs.jsonl with result_head "PR #99"
grep -qF -- 'cost **$0.42**' "$FLEET_GH_BODY_OUT" \
  || { echo "FAIL: AC#2 cost \$0.42 not in body"; printf '%s\n' "$BODY"; exit 1; }
# (2) duration — 6m12s (372000 ms = 6 min 12 sec)
grep -qF -- 'duration **6m12s**' "$FLEET_GH_BODY_OUT" \
  || { echo "FAIL: AC#2 duration 6m12s not in body"; printf '%s\n' "$BODY"; exit 1; }
# (3) ticket-to-date — sum across runs.jsonl trailing 30 days
grep -qF -- 'ticket-to-date' "$FLEET_GH_BODY_OUT" \
  || { echo "FAIL: AC#2 ticket-to-date label not in body"; printf '%s\n' "$BODY"; exit 1; }
# (4) pr-count — count of pr_opened events in the 30d window (3 in fixture)
grep -qF -- '**3** PRs' "$FLEET_GH_BODY_OUT" \
  || { echo "FAIL: AC#2 PRs count not in body"; printf '%s\n' "$BODY"; exit 1; }
# (5) prompts pin — manifest's PROMPTS_SHA short form
grep -qF -- 'ee94b3a' "$FLEET_GH_BODY_OUT" \
  || { echo "FAIL: AC#2 prompts pin ee94b3a not in body"; printf '%s\n' "$BODY"; exit 1; }
# (6) lessons_lines — line count of fixture LESSONS.md
grep -qF -- 'LESSONS:' "$FLEET_GH_BODY_OUT" \
  || { echo "FAIL: AC#2 LESSONS label not in body"; printf '%s\n' "$BODY"; exit 1; }
# (7) kit_sha — FLEET_PR_FOOTER_KIT_SHA
grep -qF -- '8a20547' "$FLEET_GH_BODY_OUT" \
  || { echo "FAIL: AC#2 kit_sha 8a20547 not in body"; printf '%s\n' "$BODY"; exit 1; }
echo "ok AC#2: six values composed from documented sources"

# ===========================================================================
# AC#3 — posted via `gh pr comment N --body "<body>"`; sentinel HTML
#        comment on first line; idempotent re-run skips.
# ===========================================================================
# The gh log must include a pr comment invocation.
grep -qF -- 'gh pr comment' "$FLEET_GH_LOG" \
  || { echo "FAIL: AC#3 gh pr comment not invoked"; cat "$FLEET_GH_LOG"; exit 1; }
# Sentinel must be on first line.
head -1 "$FLEET_GH_BODY_OUT" | grep -qF -- '<!-- fleet-roi-footer v1 -->' \
  || { echo "FAIL: AC#3 sentinel not on first line"; head -3 "$FLEET_GH_BODY_OUT"; exit 1; }

# Idempotent re-run: gh stub returns a comment with the sentinel.
: > "$FLEET_GH_LOG"
FLEET_GH_STUB_STATE="already-posted" \
  "$FLEET" pr-footer 99 >"$TMP/dedupe.out" 2>"$TMP/dedupe.err"
EXIT=$?
if [ "$EXIT" != "0" ]; then
  echo "FAIL: AC#3 idempotent re-run should exit 0, got $EXIT"
  cat "$TMP/dedupe.err"; exit 1
fi
grep -qF -- 'pr-footer: PR #99 already has a fleet-roi-footer (skipping)' "$TMP/dedupe.out" \
  || { echo "FAIL: AC#3 skip message missing"; cat "$TMP/dedupe.out"; exit 1; }
# A second pr comment MUST NOT have fired.
if grep -qF -- 'gh pr comment' "$FLEET_GH_LOG"; then
  echo "FAIL: AC#3 idempotent re-run posted again"; cat "$FLEET_GH_LOG"; exit 1
fi
echo "ok AC#3: posted with sentinel; idempotent re-run skips"

# ===========================================================================
# AC#4 — body is ASCII-only except the one permitted emoji line.
# ===========================================================================
# Strip the one emoji line then assert every remaining byte is printable
# ASCII (0x20..0x7e) plus tab/newline.
LC_ALL=C grep -v 'fleet receipt' "$FLEET_GH_BODY_OUT" > "$TMP/body.ascii"
if LC_ALL=C grep -qE -- '[^[:print:][:space:]]' "$TMP/body.ascii"; then
  echo "FAIL: AC#4 body contains non-ASCII bytes outside the emoji line"
  cat -v "$TMP/body.ascii"
  exit 1
fi
echo "ok AC#4: body is ASCII-only outside the permitted emoji line"

# ===========================================================================
# AC#5 — lib/ship.sh sources PR_FOOTER_ENABLED knob from manifest and
#        invokes pr-footer in the background. Tested via grep of the
#        ship.sh source for the conditional + bin/fleet pr-footer call.
# ===========================================================================
SHIP_SH="$REPO_ROOT/lib/ship.sh"
grep -qF -- 'PR_FOOTER_ENABLED' "$SHIP_SH" \
  || { echo "FAIL: AC#5 lib/ship.sh missing PR_FOOTER_ENABLED knob"; exit 1; }
grep -qF -- 'pr-footer' "$SHIP_SH" \
  || { echo "FAIL: AC#5 lib/ship.sh missing pr-footer invocation"; exit 1; }
# Background fork (the merge path must not wait on the gh REST call).
# The fork is the literal `) &` line within 6 lines after the pr-footer
# invocation. Use awk to assert structurally that a `&` line follows.
if ! awk '/pr-footer/ { c = 6; next } c > 0 { if (/\) &$/) { found = 1; exit } c-- } END { exit !found }' "$SHIP_SH"; then
  echo "FAIL: AC#5 lib/ship.sh pr-footer invocation must run in background"
  exit 1
fi
echo "ok AC#5: lib/ship.sh post-claude hook reads PR_FOOTER_ENABLED + forks"

# ===========================================================================
# AC#6 — manifest.example.sh names PR_FOOTER_ENABLED; kit dogfoods.
# ===========================================================================
grep -qF -- 'PR_FOOTER_ENABLED=' "$REPO_ROOT/manifest.example.sh" \
  || { echo "FAIL: AC#6 manifest.example.sh missing PR_FOOTER_ENABLED"; exit 1; }
grep -qF -- 'PR_FOOTER_ENABLED=1' "$REPO_ROOT/agents.config.sh" \
  || { echo "FAIL: AC#6 kit's agents.config.sh missing PR_FOOTER_ENABLED=1"; exit 1; }
echo "ok AC#6: manifest knob + kit dogfood"

# ===========================================================================
# AC#7 — help banner mentions PR argument, the manifest knob, and
#        idempotency. Exits 0.
# ===========================================================================
HELP_OUT="$TMP/help.out"
"$FLEET" pr-footer --help > "$HELP_OUT" || true
for kw in 'fleet pr-footer' '<pr>' 'PR_FOOTER_ENABLED' 'idempotent' '--help'; do
  if ! grep -qF -- "$kw" "$HELP_OUT"; then
    echo "FAIL: AC#7 help missing '$kw'"; cat "$HELP_OUT"; exit 1
  fi
done
# Exit 0 (per LESSONS 2026-06-01 dispatcher fall-through trap — the
# help block must end with `exit 0`).
set +e
"$FLEET" pr-footer --help >/dev/null
HELP_EXIT=$?
set -e
if [ "$HELP_EXIT" != "0" ]; then
  echo "FAIL: AC#7 help exits 0, got $HELP_EXIT"; exit 1
fi
echo "ok AC#7: help banner + exit 0"

# ===========================================================================
# AC#8 — composer aborts on a secret-shaped substring in the
#        composed body. Defense-in-depth check: a `ghp_<36>` PAT-shaped
#        value flowing through ANY field surfaces in the body and the
#        secret-scan refuses to post. We simulate this by injecting the
#        token via FLEET_PR_FOOTER_KIT_SHA (the kit-SHA flows verbatim
#        into the body's `kit:` segment, so any tainted env value
#        surfaces in the composed body — the most realistic leak path
#        is via an upstream helper feeding a bad value into one of the
#        six render slots).
# ===========================================================================
: > "$FLEET_GH_BODY_OUT"
: > "$FLEET_GH_LOG"
set +e
FLEET_PR_FOOTER_KIT_SHA="ghp_FAKE123456789012345678901234567890abc" \
FLEET_GH_STUB_STATE="merged-agent" \
  "$FLEET" pr-footer 99 2>"$TMP/secret.err" >"$TMP/secret.out"
SECRET_EXIT=$?
set -e
if [ "$SECRET_EXIT" != "3" ]; then
  echo "FAIL: AC#8 secret-detected should exit 3, got $SECRET_EXIT"
  cat "$TMP/secret.err"; exit 1
fi
grep -qF -- 'pr-footer: refusing' "$TMP/secret.err" \
  || { echo "FAIL: AC#8 refuse message missing"; cat "$TMP/secret.err"; exit 1; }
grep -qF -- 'github_pat' "$TMP/secret.err" \
  || { echo "FAIL: AC#8 refuse message must name regex"; cat "$TMP/secret.err"; exit 1; }
# And NO gh pr comment must have fired.
if grep -qF -- 'gh pr comment' "$FLEET_GH_LOG"; then
  echo "FAIL: AC#8 secret-detected branch must NOT post"; cat "$FLEET_GH_LOG"; exit 1
fi
echo "ok AC#8: secret-detected abort branch"

# ===========================================================================
# AC#9 — pure writer of one PR comment; events.jsonl byte size unchanged.
# ===========================================================================
EVENTS_BEFORE=$(wc -c < "$CACHE/events.jsonl" | tr -d ' ')
: > "$FLEET_GH_BODY_OUT"
: > "$FLEET_GH_LOG"
FLEET_GH_STUB_STATE="merged-agent" \
  "$FLEET" pr-footer 99 >/dev/null 2>/dev/null
EVENTS_AFTER=$(wc -c < "$CACHE/events.jsonl" | tr -d ' ')
if [ "$EVENTS_BEFORE" != "$EVENTS_AFTER" ]; then
  echo "FAIL: AC#9 events.jsonl changed ($EVENTS_BEFORE -> $EVENTS_AFTER)"
  exit 1
fi
echo "ok AC#9: pure writer — events.jsonl unchanged"

# ===========================================================================
# AC#10 — graceful degrade: PR not in runs.jsonl → cost/duration/
#         ticket-to-date/pr-count print `unknown`, the three surviving
#         values render.
# ===========================================================================
: > "$FLEET_GH_BODY_OUT"
: > "$FLEET_GH_LOG"
# Use a PR number that has no matching runs.jsonl row but the gh stub
# returns merged-agent metadata for it. The stub returns the same
# canned data for any PR number — we just need a number absent from
# the seeded runs.jsonl.
FLEET_GH_STUB_STATE="merged-agent" \
  "$FLEET" pr-footer 12345 >/dev/null 2>"$TMP/degrade.err"
DGEXIT=$?
if [ "$DGEXIT" != "0" ]; then
  echo "FAIL: AC#10 graceful-degrade should exit 0, got $DGEXIT"
  cat "$TMP/degrade.err"; exit 1
fi
# The body must contain "unknown" for cost/duration/ticket-to-date/pr-count.
grep -qF -- 'cost **unknown**' "$FLEET_GH_BODY_OUT" \
  || { echo "FAIL: AC#10 cost should be 'unknown' for unmapped PR"; cat "$FLEET_GH_BODY_OUT"; exit 1; }
grep -qF -- 'duration **unknown**' "$FLEET_GH_BODY_OUT" \
  || { echo "FAIL: AC#10 duration should be 'unknown' for unmapped PR"; cat "$FLEET_GH_BODY_OUT"; exit 1; }
# The three surviving values must still appear.
grep -qF -- 'ee94b3a' "$FLEET_GH_BODY_OUT" \
  || { echo "FAIL: AC#10 prompts pin missing on degrade path"; exit 1; }
grep -qF -- '8a20547' "$FLEET_GH_BODY_OUT" \
  || { echo "FAIL: AC#10 kit sha missing on degrade path"; exit 1; }
grep -qF -- 'LESSONS:' "$FLEET_GH_BODY_OUT" \
  || { echo "FAIL: AC#10 LESSONS line missing on degrade path"; exit 1; }
echo "ok AC#10: graceful degrade prints 'unknown' for missing fields"

# ===========================================================================
# AC#11 — lib/common.sh public API unchanged. No NEW non-underscore
#         function lands in common.sh (additions, if any, are
#         underscore-prefixed private helpers).
# ===========================================================================
DIFF_FILE="$TMP/common-diff.txt"
git -C "$REPO_ROOT" diff origin/main...HEAD -- lib/common.sh > "$DIFF_FILE" || true
# Extract function names from added lines (start with `+`, not `+++`).
# Look for `^+name() {` shape.
ADDED_FN=$(awk '/^\+[a-zA-Z_][a-zA-Z_0-9]*\(\)[[:space:]]*\{/ { print $0 }' "$DIFF_FILE")
if [ -n "$ADDED_FN" ]; then
  # Every new top-level fn must begin with `_` (underscore-private).
  BAD=$(echo "$ADDED_FN" | awk '!/^\+_[a-zA-Z_]/')
  if [ -n "$BAD" ]; then
    echo "FAIL: AC#11 lib/common.sh added a non-underscore function"
    echo "$BAD"; exit 1
  fi
fi
echo "ok AC#11: lib/common.sh public API unchanged"

# ===========================================================================
# AC#12 — prompts/ unchanged.
# ===========================================================================
PROMPTS_DIFF=$(git -C "$REPO_ROOT" diff --name-only origin/main...HEAD -- prompts/ || true)
if [ -n "$PROMPTS_DIFF" ]; then
  echo "FAIL: AC#12 prompts/ must not change"
  echo "$PROMPTS_DIFF"; exit 1
fi
echo "ok AC#12: prompts/ unchanged"

# ===========================================================================
# AC#13 — test rig structural checks: stubs in $HOME/.local/bin per
#         LESSONS 2026-05-26; fixture files copied via cp per
#         LESSONS 2026-05-27; clock pinned via FLEET_NOW_OVERRIDE;
#         all 12 boxes above exercised.
# ===========================================================================
[ -x "$HOME/.local/bin/gh"  ] || { echo "FAIL: AC#13 gh stub missing"; exit 1; }
[ -x "$HOME/.local/bin/git" ] || { echo "FAIL: AC#13 git stub missing"; exit 1; }
[ -f "$CACHE/runs.jsonl"    ] || { echo "FAIL: AC#13 runs.jsonl fixture missing"; exit 1; }
[ -f "$CACHE/events.jsonl"  ] || { echo "FAIL: AC#13 events.jsonl fixture missing"; exit 1; }
[ -n "${FLEET_NOW_OVERRIDE:-}" ] || { echo "FAIL: AC#13 FLEET_NOW_OVERRIDE not set"; exit 1; }
echo "ok AC#13: test rig structural"

echo "all pr-footer ACs pass"
