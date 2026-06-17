#!/bin/bash
# tests/share.sh — `bin/fleet share <slug> <pr>` one-line testimonial test.
#
# Ticket 0056. One assertion block per acceptance-criteria checkbox in
# docs/backlog/0056-fleet-share-pr-testimonial.md (13 boxes).
#
# `share` is a PURE READER: no events.jsonl writes, no `fleet_emit_event`
# calls, no `lib/` or `prompts/` edits, no new event types.
#
# Defensive habits (per LESSONS):
#   - 2026-05-26 (PATH reset) — every stub lives under `$HOME/.local/bin`.
#   - 2026-05-27 ($(cat) trap) — fixture installs use `cp`, never `$(cat)`.
#   - 2026-05-28 (printf leading-dash) — all printf-of-user-value via `--`.
#   - 2026-05-30 (`grep -F --` trap) — every keyword grep uses `grep -qF --`.
#   - 2026-06-01 (grep -c double-print) — counts via `awk … END { print n+0 }`.
#   - 2026-06-08 (awk arr empty-string key) — every awk declares BEGIN { count = 0 }.
#   - 2026-06-11 (BSD date -j -f fills missing time) — clock frozen via
#     FLEET_NOW_OVERRIDE.
#   - 2026-06-15 (per-slug streak shellout) — share MUST NOT call fleet streak.
#
# Run-time budget: <8s.

set -euo pipefail

REPO_ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
FLEET="$REPO_ROOT/bin/fleet"
FIXTURE_DIR="$REPO_ROOT/tests/fixtures/share"

TMP="$(mktemp -d -t fleet-share-test.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

export HOME="$TMP/home"
mkdir -p "$HOME/.local/bin"
mkdir -p "$HOME/.cache/agent-fleet"

# Anchor "today" at 2026-06-16T12:00:00Z (well after every fixture event so
# the share line treats every PR as merged).
NOW_EPOCH=1781697600
export FLEET_NOW_OVERRIDE="$NOW_EPOCH"

FIXTURE_ROOT="$TMP/projects"
mkdir -p "$FIXTURE_ROOT"
export FLEET_DISCOVERY_ROOT="$FIXTURE_ROOT"

# Per LESSONS 2026-05-27: copy fixture files with `cp`, never via $(cat …).
install_slug_fixture() {  # $1 = slug
  local slug="$1"
  mkdir -p "$FIXTURE_ROOT/$slug"
  cp "$FIXTURE_DIR/$slug/agents.config.sh" "$FIXTURE_ROOT/$slug/agents.config.sh"
  local cache="$HOME/.cache/${slug}-agent"
  mkdir -p "$cache"
  cp "$FIXTURE_DIR/$slug/events.jsonl" "$cache/events.jsonl"
  cp "$FIXTURE_DIR/$slug/runs.jsonl"   "$cache/runs.jsonl"
}

install_slug_fixture sidebrew
install_slug_fixture courtiq
install_slug_fixture hedgehog

# ---------------------------------------------------------------------------
# Stubs. Per LESSONS 2026-05-26, every stub lives under $HOME/.local/bin so it
# survives `lib/common.sh`'s PATH reset (share itself does NOT source
# common.sh, but the production runners that future regression tests pull in
# do — using the same dir keeps the fixture simple).
# ---------------------------------------------------------------------------

# `gh` stub — responds to `gh pr view <n> --json …` by emitting the
# pre-canned fixture JSON for the slug/PR being asked about, OR by writing
# its argv to a side file for later assertion.
GH_CALLS="$TMP/gh-calls.log"
: > "$GH_CALLS"
cat > "$HOME/.local/bin/gh" <<STUB
#!/bin/bash
echo "\$@" >> "$GH_CALLS"
# Determine which PR was requested. Argv shape:
#   gh pr view <n> --json <fields>
# We don't know the slug here, so we resolve by cwd? Instead we honour an
# env knob GH_FIXTURE_SLUG that the test sets per invocation.
slug="\${GH_FIXTURE_SLUG:-sidebrew}"
pr=""
saw_view=0
for a in "\$@"; do
  if [ "\$saw_view" = "1" ] && [ -z "\$pr" ]; then pr="\$a"; fi
  if [ "\$a" = "view" ]; then saw_view=1; fi
done
if [ -z "\$pr" ]; then
  echo "stub gh: no PR number in argv" >&2
  exit 1
fi
fixture="$FIXTURE_DIR/\$slug/gh-pr-view-\$pr.json"
if [ -f "\$fixture" ]; then
  cat "\$fixture"
  exit 0
fi
# Mimic gh's "no PR found" failure mode.
echo "GraphQL: Could not resolve to a PullRequest with the number of \$pr." >&2
exit 1
STUB
chmod +x "$HOME/.local/bin/gh"

# `pbcopy` stub — records its stdin to a side file.
PBCOPY_STDIN="$TMP/pbcopy.stdin"
: > "$PBCOPY_STDIN"
cat > "$HOME/.local/bin/pbcopy" <<STUB
#!/bin/bash
cat > "$PBCOPY_STDIN"
STUB
chmod +x "$HOME/.local/bin/pbcopy"

# `uname` stub — by default reports Darwin; tests that want the Linux branch
# set UNAME_OVERRIDE=Linux before invocation.
cat > "$HOME/.local/bin/uname" <<'STUB'
#!/bin/bash
echo "${UNAME_OVERRIDE:-Darwin}"
STUB
chmod +x "$HOME/.local/bin/uname"

export PATH="$HOME/.local/bin:$PATH"

# AC#12 — record events.jsonl + runs.jsonl byte sizes BEFORE any invocation.
size_of() {
  local f="$1"
  if [ -f "$f" ]; then awk 'END { print n+0 }' n=$(wc -c < "$f") /dev/null; else echo 0; fi
}
events_size() {
  local slug="$1"
  local f="$HOME/.cache/${slug}-agent/events.jsonl"
  if [ -f "$f" ]; then wc -c < "$f" | tr -d ' '; else echo 0; fi
}
runs_size() {
  local slug="$1"
  local f="$HOME/.cache/${slug}-agent/runs.jsonl"
  if [ -f "$f" ]; then wc -c < "$f" | tr -d ' '; else echo 0; fi
}
SZ_EVT_SIDEBREW_BEFORE=$(events_size sidebrew)
SZ_EVT_COURTIQ_BEFORE=$(events_size courtiq)
SZ_EVT_HEDGEHOG_BEFORE=$(events_size hedgehog)
SZ_RUN_SIDEBREW_BEFORE=$(runs_size sidebrew)
SZ_RUN_COURTIQ_BEFORE=$(runs_size courtiq)
SZ_RUN_HEDGEHOG_BEFORE=$(runs_size hedgehog)

# ========================================================================
# AC #1 — usage refusal: missing args, slug-only, slug + non-numeric PR all
#         exit 2 with the documented usage banner on stderr.
# ========================================================================
echo "AC#1 — usage refusal on missing / partial / non-numeric args"
OUT="$TMP/ac1-noargs.out"
set +e
GH_FIXTURE_SLUG=sidebrew "$FLEET" share > "$OUT" 2>&1
EXIT=$?
set -e
if [ "$EXIT" != "2" ]; then
  echo "FAIL: AC#1 no-args exit $EXIT (want 2)"; cat "$OUT"; exit 1
fi
grep -qF -- "share: usage:" "$OUT" \
  || { echo "FAIL: AC#1 no-args missing 'share: usage:' on stderr"; cat "$OUT"; exit 1; }

OUT="$TMP/ac1-slugonly.out"
set +e
GH_FIXTURE_SLUG=sidebrew "$FLEET" share sidebrew > "$OUT" 2>&1
EXIT=$?
set -e
if [ "$EXIT" != "2" ]; then
  echo "FAIL: AC#1 slug-only exit $EXIT (want 2)"; cat "$OUT"; exit 1
fi
grep -qF -- "share: usage:" "$OUT" \
  || { echo "FAIL: AC#1 slug-only missing 'share: usage:'"; cat "$OUT"; exit 1; }

OUT="$TMP/ac1-nonnum.out"
set +e
GH_FIXTURE_SLUG=sidebrew "$FLEET" share sidebrew not-a-number > "$OUT" 2>&1
EXIT=$?
set -e
if [ "$EXIT" != "2" ]; then
  echo "FAIL: AC#1 non-numeric PR exit $EXIT (want 2)"; cat "$OUT"; exit 1
fi
grep -qF -- "share: usage:" "$OUT" \
  || { echo "FAIL: AC#1 non-numeric PR missing 'share: usage:'"; cat "$OUT"; exit 1; }
echo "  ok"

# ========================================================================
# AC #2 — unknown slug AND known slug + unknown PR both refuse with the
#         documented messages and exit 2.
# ========================================================================
echo "AC#2 — unknown slug + unknown PR refusals"
OUT="$TMP/ac2-unknown-slug.out"
set +e
GH_FIXTURE_SLUG=sidebrew "$FLEET" share nope-slug 42 > "$OUT" 2>&1
EXIT=$?
set -e
if [ "$EXIT" != "2" ]; then
  echo "FAIL: AC#2 unknown-slug exit $EXIT (want 2)"; cat "$OUT"; exit 1
fi
grep -qF -- "share: slug nope-slug not found" "$OUT" \
  || { echo "FAIL: AC#2 unknown-slug message missing"; cat "$OUT"; exit 1; }
grep -qF -- "discovered slugs:" "$OUT" \
  || { echo "FAIL: AC#2 unknown-slug should list discovered slugs"; cat "$OUT"; exit 1; }

OUT="$TMP/ac2-unknown-pr.out"
set +e
GH_FIXTURE_SLUG=sidebrew "$FLEET" share sidebrew 9999 > "$OUT" 2>&1
EXIT=$?
set -e
if [ "$EXIT" != "2" ]; then
  echo "FAIL: AC#2 unknown-PR exit $EXIT (want 2)"; cat "$OUT"; exit 1
fi
grep -qF -- "share: sidebrew has no merged PR #9999" "$OUT" \
  || { echo "FAIL: AC#2 unknown-PR message missing"; cat "$OUT"; exit 1; }
echo "  ok"

# ========================================================================
# AC #3 — composed line shape (no flags), three phrase branches.
# ========================================================================
echo "AC#3 — composed line shape + phrase branches"
# (a) no send-backs: sidebrew/42 has zero lesson_draft_emitted, zero heal_*.
OUT="$TMP/ac3-nosendback.out"
GH_FIXTURE_SLUG=sidebrew "$FLEET" share sidebrew 42 > "$OUT"
grep -qF -- "sidebrew" "$OUT" \
  || { echo "FAIL: AC#3 default mode should carry real slug name"; cat "$OUT"; exit 1; }
grep -qF -- "PR #42" "$OUT" \
  || { echo "FAIL: AC#3 default mode should carry real PR number"; cat "$OUT"; exit 1; }
grep -qF -- "shipped autonomously by agent-fleet" "$OUT" \
  || { echo "FAIL: AC#3 missing canonical phrase 'shipped autonomously by agent-fleet'"; cat "$OUT"; exit 1; }
grep -qF -- "lines changed" "$OUT" \
  || { echo "FAIL: AC#3 missing 'lines changed' clause"; cat "$OUT"; exit 1; }
grep -qF -- "min runtime" "$OUT" \
  || { echo "FAIL: AC#3 missing 'min runtime' clause"; cat "$OUT"; exit 1; }
grep -qF -- "no send-backs" "$OUT" \
  || { echo "FAIL: AC#3 sidebrew PR #42 should render 'no send-backs'"; cat "$OUT"; exit 1; }

# (b) healed in N cycle(s): sidebrew/99 has heal_attempt + no lesson_draft.
OUT="$TMP/ac3-healed.out"
GH_FIXTURE_SLUG=sidebrew "$FLEET" share sidebrew 99 > "$OUT"
grep -qF -- "healed in 1 cycle" "$OUT" \
  || { echo "FAIL: AC#3 sidebrew PR #99 should render 'healed in 1 cycle(s)'"; cat "$OUT"; exit 1; }

# (c) N send-back(s): courtiq/88 has 2 lesson_draft_emitted.
OUT="$TMP/ac3-sendbacks.out"
GH_FIXTURE_SLUG=courtiq "$FLEET" share courtiq 88 > "$OUT"
grep -qF -- "2 send-back" "$OUT" \
  || { echo "FAIL: AC#3 courtiq PR #88 should render '2 send-back(s)'"; cat "$OUT"; exit 1; }
echo "  ok"

# ========================================================================
# AC #4 — runtime minutes: 18-minute window and ~103-minute window.
# ========================================================================
echo "AC#4 — runtime minutes math"
OUT="$TMP/ac4-18.out"
GH_FIXTURE_SLUG=sidebrew "$FLEET" share sidebrew 42 > "$OUT"
grep -qF -- "18 min runtime" "$OUT" \
  || { echo "FAIL: AC#4 sidebrew PR #42 expected '18 min runtime'"; cat "$OUT"; exit 1; }

OUT="$TMP/ac4-103.out"
GH_FIXTURE_SLUG=sidebrew "$FLEET" share sidebrew 99 > "$OUT"
grep -qF -- "103 min runtime" "$OUT" \
  || { echo "FAIL: AC#4 sidebrew PR #99 expected '103 min runtime'"; cat "$OUT"; exit 1; }
echo "  ok"

# ========================================================================
# AC #5 — cost render: $N.NN by default, banded under --redact.
# ========================================================================
echo "AC#5 — cost render + cost bands"
OUT="$TMP/ac5-default.out"
GH_FIXTURE_SLUG=sidebrew "$FLEET" share sidebrew 42 > "$OUT"
grep -qF -- '$0.42' "$OUT" \
  || { echo "FAIL: AC#5 sidebrew PR #42 expected raw '\$0.42'"; cat "$OUT"; exit 1; }

OUT="$TMP/ac5-default-450.out"
GH_FIXTURE_SLUG=sidebrew "$FLEET" share sidebrew 99 > "$OUT"
grep -qF -- '$4.50' "$OUT" \
  || { echo "FAIL: AC#5 sidebrew PR #99 expected raw '\$4.50'"; cat "$OUT"; exit 1; }

OUT="$TMP/ac5-redact-042.out"
GH_FIXTURE_SLUG=sidebrew "$FLEET" share sidebrew 42 --redact > "$OUT"
# $0.42 → "<$1" band.
grep -qF -- '<$1' "$OUT" \
  || { echo "FAIL: AC#5 --redact sidebrew/42 expected '<\$1' band"; cat "$OUT"; exit 1; }
if grep -qF -- '0.42' "$OUT"; then
  echo "FAIL: AC#5 --redact should NOT leak raw '0.42'"; cat "$OUT"; exit 1
fi

OUT="$TMP/ac5-redact-450.out"
GH_FIXTURE_SLUG=sidebrew "$FLEET" share sidebrew 99 --redact > "$OUT"
# $4.50 → "~$5" band.
grep -qF -- '~$5' "$OUT" \
  || { echo "FAIL: AC#5 --redact sidebrew/99 expected '~\$5' band"; cat "$OUT"; exit 1; }
if grep -qF -- '4.50' "$OUT"; then
  echo "FAIL: AC#5 --redact should NOT leak raw '4.50'"; cat "$OUT"; exit 1
fi
echo "  ok"

# ========================================================================
# AC #6 — LESSONS cited: 0, 1, and 2 fixtures.
# ========================================================================
echo "AC#6 — LESSONS cited resolver"
# 0 lessons cited: hedgehog/11 — no lesson_promoted, no lesson_draft.
OUT="$TMP/ac6-0.out"
GH_FIXTURE_SLUG=hedgehog "$FLEET" share hedgehog 11 > "$OUT"
if grep -qF -- "LESSONS cited:" "$OUT"; then
  echo "FAIL: AC#6 hedgehog/11 should OMIT 'LESSONS cited:' clause"; cat "$OUT"; exit 1
fi

# 1 lesson cited: sidebrew/42 — one lesson_promoted with 2026-06-15.
OUT="$TMP/ac6-1.out"
GH_FIXTURE_SLUG=sidebrew "$FLEET" share sidebrew 42 > "$OUT"
grep -qF -- "LESSONS cited: 2026-06-15" "$OUT" \
  || { echo "FAIL: AC#6 sidebrew/42 expected 'LESSONS cited: 2026-06-15'"; cat "$OUT"; exit 1; }

# 2 lessons cited: sidebrew/99 — two lesson_promoted with 2026-06-08, 2026-06-11.
OUT="$TMP/ac6-2.out"
GH_FIXTURE_SLUG=sidebrew "$FLEET" share sidebrew 99 > "$OUT"
grep -qF -- "LESSONS cited: 2026-06-08, 2026-06-11" "$OUT" \
  || { echo "FAIL: AC#6 sidebrew/99 expected 'LESSONS cited: 2026-06-08, 2026-06-11'"; cat "$OUT"; exit 1; }
echo "  ok"

# ========================================================================
# AC #7 — --redact pseudonymizes slug, PR, cost, repo URL.
# ========================================================================
echo "AC#7 — --redact pseudonyms"
OUT="$TMP/ac7.out"
GH_FIXTURE_SLUG=sidebrew "$FLEET" share sidebrew 42 --redact > "$OUT"
# Real slug name MUST NOT appear.
if grep -qF -- "sidebrew" "$OUT"; then
  echo "FAIL: AC#7 --redact leaked real slug 'sidebrew'"; cat "$OUT"; exit 1
fi
# Real PR number MUST NOT appear.
if grep -qF -- "#42" "$OUT"; then
  echo "FAIL: AC#7 --redact leaked real '#42'"; cat "$OUT"; exit 1
fi
# Real repo org/user MUST NOT appear.
if grep -qF -- "realuser" "$OUT"; then
  echo "FAIL: AC#7 --redact leaked 'realuser' org"; cat "$OUT"; exit 1
fi
# A 'project-' pseudonym appears.
grep -qE 'project-[a-z]+' "$OUT" \
  || { echo "FAIL: AC#7 --redact missing 'project-<token>' pseudonym"; cat "$OUT"; exit 1; }
# An alphabetic PR token (`PR #aaa` style — three lowercase letters) appears.
grep -qE 'PR #[a-z]{3}' "$OUT" \
  || { echo "FAIL: AC#7 --redact missing 'PR #<token>' three-letter pseudonym"; cat "$OUT"; exit 1; }
echo "  ok"

# ========================================================================
# AC #8 — --copy pipes through pbcopy on Darwin; warns on non-Darwin.
# ========================================================================
echo "AC#8 — --copy pbcopy + platform-mismatch warning"
: > "$PBCOPY_STDIN"
OUT="$TMP/ac8-copy.out"
ERR="$TMP/ac8-copy.err"
GH_FIXTURE_SLUG=sidebrew "$FLEET" share sidebrew 42 --copy > "$OUT" 2> "$ERR"
# pbcopy stub recorded the composed line.
if [ ! -s "$PBCOPY_STDIN" ]; then
  echo "FAIL: AC#8 pbcopy stub recorded empty stdin"; cat "$OUT"; cat "$ERR"; exit 1
fi
grep -qF -- "shipped autonomously by agent-fleet" "$PBCOPY_STDIN" \
  || { echo "FAIL: AC#8 pbcopy stdin missing composed line"; cat "$PBCOPY_STDIN"; exit 1; }
grep -qF -- "copied to clipboard" "$ERR" \
  || { echo "FAIL: AC#8 expected 'copied to clipboard' on stderr"; cat "$ERR"; exit 1; }

# Linux platform branch.
OUT="$TMP/ac8-linux.out"
ERR="$TMP/ac8-linux.err"
GH_FIXTURE_SLUG=sidebrew UNAME_OVERRIDE=Linux "$FLEET" share sidebrew 42 --copy > "$OUT" 2> "$ERR"
grep -qF -- "macOS only" "$ERR" \
  || { echo "FAIL: AC#8 Linux branch should warn 'macOS only'"; cat "$ERR"; exit 1; }
grep -qF -- "shipped autonomously by agent-fleet" "$OUT" \
  || { echo "FAIL: AC#8 Linux branch should still print line to stdout"; cat "$OUT"; exit 1; }
echo "  ok"

# ========================================================================
# AC #9 — --json: structured object with documented keys; valid JSON.
# ========================================================================
echo "AC#9 — --json emit (default + redacted)"
OUT="$TMP/ac9-default.json"
GH_FIXTURE_SLUG=sidebrew "$FLEET" share sidebrew 42 --json > "$OUT"
node -e '
  const obj = JSON.parse(require("fs").readFileSync("'"$OUT"'", "utf8"));
  const need = ["slug","pr","lines_changed","runtime_minutes","cost_usd","send_backs","heal_cycles","lessons_cited","pr_url","rendered"];
  for (const k of need) {
    if (!(k in obj)) { console.error("missing key", k); process.exit(1); }
  }
  if (obj.slug !== "sidebrew") { console.error("slug mismatch", obj.slug); process.exit(1); }
  if (obj.lines_changed !== 312) { console.error("lines_changed mismatch", obj.lines_changed); process.exit(1); }
  if (obj.runtime_minutes !== 18) { console.error("runtime_minutes mismatch", obj.runtime_minutes); process.exit(1); }
  if (!Array.isArray(obj.lessons_cited)) { console.error(".lessons_cited must be array"); process.exit(1); }
' || { echo "FAIL: AC#9 default JSON shape invalid"; cat "$OUT"; exit 1; }

OUT="$TMP/ac9-redact.json"
GH_FIXTURE_SLUG=sidebrew "$FLEET" share sidebrew 42 --redact --json > "$OUT"
node -e '
  const obj = JSON.parse(require("fs").readFileSync("'"$OUT"'", "utf8"));
  if (typeof obj.slug !== "string") { console.error("redacted slug missing"); process.exit(1); }
  if (obj.slug === "sidebrew") { console.error("--redact JSON leaked real slug"); process.exit(1); }
  if (typeof obj.cost_usd !== "string") { console.error("--redact cost_usd should be band string"); process.exit(1); }
  if (obj.cost_usd.indexOf("$") < 0) { console.error("--redact cost_usd should look like a band token"); process.exit(1); }
' || { echo "FAIL: AC#9 --redact --json shape invalid"; cat "$OUT"; exit 1; }
echo "  ok"

# ========================================================================
# AC #10 — gh pr view called ONCE per invocation; missing-gh branch refuses.
# ========================================================================
echo "AC#10 — gh pr view call counts + missing-gh branch"
# Wipe the cache so this run actually shells out to gh.
rm -rf "$HOME/.cache/agent-fleet/share-gh-pr-"*
: > "$GH_CALLS"
OUT="$TMP/ac10.out"
GH_FIXTURE_SLUG=sidebrew "$FLEET" share sidebrew 42 > "$OUT"
n_calls=$(awk 'BEGIN { n = 0 } /pr view/ { n++ } END { print n+0 }' "$GH_CALLS")
if [ "$n_calls" != "1" ]; then
  echo "FAIL: AC#10 expected exactly 1 'gh pr view' call, saw $n_calls"; cat "$GH_CALLS"; exit 1
fi

# Missing-gh branch: temporarily move the stub out of PATH and ensure refusal.
mv "$HOME/.local/bin/gh" "$HOME/.local/bin/gh.bak"
# Wipe the cache so the share path must shell out.
rm -rf "$HOME/.cache/agent-fleet/share-gh-pr-"*
ERR="$TMP/ac10-nogh.err"
set +e
PATH="$HOME/.local/bin:/usr/bin:/bin" "$FLEET" share sidebrew 42 > "$TMP/ac10-nogh.out" 2> "$ERR"
EXIT=$?
set -e
mv "$HOME/.local/bin/gh.bak" "$HOME/.local/bin/gh"
if [ "$EXIT" != "2" ]; then
  echo "FAIL: AC#10 missing-gh exit $EXIT (want 2)"; cat "$ERR"; exit 1
fi
grep -qF -- "share: gh CLI required" "$ERR" \
  || { echo "FAIL: AC#10 missing-gh message missing"; cat "$ERR"; exit 1; }
echo "  ok"

# ========================================================================
# AC #11 — --help banner mentions slug + PR args + --redact/--copy/--json.
# ========================================================================
echo "AC#11 — --help banner"
OUT="$TMP/ac11.help"
set +e
"$FLEET" share --help > "$OUT" 2>&1
EXIT=$?
set -e
if [ "$EXIT" != "0" ]; then
  echo "FAIL: AC#11 --help exit $EXIT (want 0)"; cat "$OUT"; exit 1
fi
for kw in "<slug>" "<pr" "--redact" "--copy" "--json"; do
  grep -qF -- "$kw" "$OUT" \
    || { echo "FAIL: AC#11 help missing keyword '$kw'"; cat "$OUT"; exit 1; }
done
echo "  ok"

# ========================================================================
# AC #12 — pure reader: every slug's events.jsonl + runs.jsonl byte size
#          unchanged before and after every invocation above.
# ========================================================================
echo "AC#12 — pure reader, no events.jsonl / runs.jsonl writes"
SZ_EVT_SIDEBREW_AFTER=$(events_size sidebrew)
SZ_EVT_COURTIQ_AFTER=$(events_size courtiq)
SZ_EVT_HEDGEHOG_AFTER=$(events_size hedgehog)
SZ_RUN_SIDEBREW_AFTER=$(runs_size sidebrew)
SZ_RUN_COURTIQ_AFTER=$(runs_size courtiq)
SZ_RUN_HEDGEHOG_AFTER=$(runs_size hedgehog)

for label in EVT_SIDEBREW EVT_COURTIQ EVT_HEDGEHOG RUN_SIDEBREW RUN_COURTIQ RUN_HEDGEHOG; do
  before_var="SZ_${label}_BEFORE"
  after_var="SZ_${label}_AFTER"
  if [ "${!before_var}" != "${!after_var}" ]; then
    echo "FAIL: AC#12 $label size changed ${!before_var} -> ${!after_var}"
    exit 1
  fi
done
echo "  ok"

# ========================================================================
# AC #13 — lib/common.sh + prompts/ untouched; no new event types.
# ========================================================================
echo "AC#13 — lib/common.sh + prompts/ untouched"
( cd "$REPO_ROOT" && \
  diff="$(git diff --name-only main...HEAD -- lib/common.sh prompts/ 2>/dev/null || true)"
  if [ -n "$diff" ]; then
    echo "FAIL: AC#13 unexpected changes to lib/common.sh or prompts/: $diff"
    exit 1
  fi
)
echo "  ok"

echo
echo "tests/share.sh — all 13 AC blocks passed"
