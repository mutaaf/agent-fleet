#!/bin/bash
# tests/flaky.sh — bin/fleet flaky end-to-end test (ticket 0060).
#
# One assertion block per acceptance-criteria checkbox in
# docs/backlog/0060-fleet-flaky-intermittent-check-detector.md (13 boxes).
#
# Fixture: five synthetic slugs under tests/fixtures/flaky/<slug>/, each
# with `agents.config.sh`, `events.jsonl`, and (for non-empty slugs) a
# `gh-runlist.json` + one `gh-runview-<id>.json` per failing run. The `gh`
# stub reads per-slug response JSON from $FIX_DIR/<slug>/ and records
# every invocation to $INV_LOG so AC#7's exact-count assertion fires.
#
# Stubs live under $HOME/.local/bin per LESSONS 2026-05-26 (PATH reset
# in lib/common.sh — bin/fleet does NOT source it, but we keep the
# convention uniform). Per LESSONS 2026-05-27 fixture files are copied
# via `cp` only when the test mutates them — bin/fleet reads via stub.
# Counts via `awk … END { print n+0 }` per LESSONS 2026-06-01. Every awk
# script declares `BEGIN { count = 0 }` per LESSONS 2026-06-08. Clock
# frozen via FLEET_FLAKY_FAKE_NOW so since-window math is deterministic.

set -euo pipefail

REPO_ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
FLEET="$REPO_ROOT/bin/fleet"

TMP="$(mktemp -d -t fleet-flaky-test.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

# Isolate HOME so we sandbox $HOME/.cache + $HOME/.local/bin per
# LESSONS 2026-05-26 (PATH reset).
export HOME="$TMP/home"
mkdir -p "$HOME/.local/bin"

# Pinned epoch: 2026-06-19T00:00:00Z. The since-window math uses
# `date +%s - N*86400` per LESSONS 2026-06-11 — no `date -j -f`.
NOW_EPOCH=1781913600
export FLEET_FLAKY_FAKE_NOW="$NOW_EPOCH"
export FLEET_NOW_OVERRIDE="$NOW_EPOCH"

# --- fixture slugs (FLEET_DISCOVERY_ROOT seam) ----------------------------
# Copy each fixture slug subdir to a writable FIXTURE root. Per LESSONS
# 2026-05-27 use `cp -R` (NOT `$(cat …)`).
FIXTURE="$TMP/projects"
mkdir -p "$FIXTURE"
FIX_DIR="$REPO_ROOT/tests/fixtures/flaky"
for slug in flake-covered flake-uncovered regression healthy gh-fails; do
  mkdir -p "$FIXTURE/$slug"
  cp "$FIX_DIR/$slug/agents.config.sh" "$FIXTURE/$slug/agents.config.sh"
  # bin/fleet reads events.jsonl from $HOME/.cache/<slug>-agent/events.jsonl
  # at runtime, so mirror the fixture into the cache layout per slug.
  mkdir -p "$HOME/.cache/${slug}-agent"
  if [ -f "$FIX_DIR/$slug/events.jsonl" ]; then
    cp "$FIX_DIR/$slug/events.jsonl" "$HOME/.cache/${slug}-agent/events.jsonl"
  else
    : > "$HOME/.cache/${slug}-agent/events.jsonl"
  fi
done
export FLEET_DISCOVERY_ROOT="$FIXTURE"

# Point catalog at the existing atlas fixture catalog (5 tokens).
export FLEET_HEAL_CATALOG="$REPO_ROOT/tests/fixtures/atlas.catalog.sh"

# --- gh stub --------------------------------------------------------------
# Writes every invocation to $TMP/gh-invocations.log so AC#7's count
# assertion can fire. The stub maps `--repo example/<slug>` to the
# matching fixture dir under $FIX_DIR/<slug>/ and returns the canned
# JSON. The gh-fails slug has a `gh-fail` sentinel — those calls exit 1.
INV_LOG="$TMP/gh-invocations.log"
: > "$INV_LOG"
GH_FIX_DIR="$FIX_DIR"
export GH_FIX_DIR_EXPORT="$GH_FIX_DIR"
export INV_LOG_EXPORT="$INV_LOG"

cat > "$HOME/.local/bin/gh" <<'STUB'
#!/bin/bash
INV="${INV_LOG_EXPORT:-/tmp/gh-flaky-inv.log}"
FIX="${GH_FIX_DIR_EXPORT:-/tmp/gh-flaky-fix}"
printf '%s\n' "$*" >> "$INV"

# Walk argv for --repo example/<slug>.
repo=""
need=0
for arg in "$@"; do
  if [ "$need" = "1" ]; then repo="$arg"; need=0; continue; fi
  case "$arg" in
    --repo) need=1 ;;
  esac
done
slug=""
case "$repo" in
  */*) slug="${repo##*/}" ;;
esac

# Detect the gh-fails sentinel via slug name.
if [ "$slug" = "gh-fails" ]; then
  echo "gh: API rate limit exceeded" >&2
  exit 1
fi

sub1="${1:-}"; sub2="${2:-}"
case "${sub1}/${sub2}" in
  run/list)
    if [ -n "$slug" ] && [ -f "$FIX/$slug/gh-runlist.json" ]; then
      cat "$FIX/$slug/gh-runlist.json"
    else
      echo "[]"
    fi
    exit 0
    ;;
  run/view)
    n="${3:-}"
    if [ -n "$slug" ] && [ -f "$FIX/$slug/gh-runview-$n.json" ]; then
      cat "$FIX/$slug/gh-runview-$n.json"
    else
      echo "{}"
    fi
    exit 0
    ;;
esac
echo "[]"
exit 0
STUB
chmod +x "$HOME/.local/bin/gh"

# Make sure the stubbed gh wins.
export PATH="$HOME/.local/bin:$PATH"

# ========================================================================
# AC #1 — `bin/fleet flaky` (no flags) walks every slug + last 30d of
#         `gh run list` per slug and prints a ranked table per the
#         Product-Owner example. Exit 0. Also: `--since 7d` on a slug
#         with no failed runs prints the "healthy CI" line and exits 0
#         (the all-healthy branch).
# ========================================================================
OUT="$TMP/flaky.txt"
set +e
"$FLEET" flaky > "$OUT" 2>&1
EXIT=$?
set -e
if [ "$EXIT" != "0" ]; then
  echo "FAIL: AC#1 flaky exit $EXIT (want 0)"; cat "$OUT"; exit 1
fi
if ! grep -qF -- 'failed gating-check runs' "$OUT"; then
  echo "FAIL: AC#1 default invocation missing summary line"
  cat "$OUT"; exit 1
fi
# Table header sanity.
for kw in 'check name' 'failures' 'flaked' 'in-catalog?' 'next action'; do
  if ! grep -qF -- "$kw" "$OUT"; then
    echo "FAIL: AC#1 header missing '$kw'"; cat "$OUT"; exit 1
  fi
done
# Healthy branch: slug=healthy only.
HEALTHY_OUT="$TMP/flaky-healthy.txt"
set +e
"$FLEET" flaky --slug healthy --since 7d > "$HEALTHY_OUT" 2>&1
HEALTHY_EXIT=$?
set -e
if [ "$HEALTHY_EXIT" != "0" ]; then
  echo "FAIL: AC#1 healthy-branch exit $HEALTHY_EXIT (want 0)"; cat "$HEALTHY_OUT"; exit 1
fi
if ! grep -qF -- '0 failed gating-check runs in 7d (healthy CI)' "$HEALTHY_OUT"; then
  echo "FAIL: AC#1 healthy-branch missing 'healthy CI' line"; cat "$HEALTHY_OUT"; exit 1
fi
echo "ok: AC#1 default invocation + healthy branch + exit 0"

# ========================================================================
# AC #2 — Flake classifier: same SHA, fail→pass = flake. Different SHA,
#         fail→pass = regression (not flake). No later pass = genuine
#         failure (counts as failure, not flake).
# ========================================================================
# flake-covered: unit-tests flaked 1x (sha=shaAAA, fail+pass), build
# flaked 3x (3 distinct SHAs each with fail+pass).
if ! grep -qE 'unit-tests[[:space:]]+[0-9]+' "$OUT"; then
  echo "FAIL: AC#2 unit-tests row missing"; cat "$OUT"; exit 1
fi
if ! grep -qE 'build[[:space:]]+[0-9]+' "$OUT"; then
  echo "FAIL: AC#2 build row missing"; cat "$OUT"; exit 1
fi
# regression: lint failed once on shaDD1, passed on shaDD2 (newer SHA) →
# fail=1, flaked=0 (regression).
LINT_LINE="$(grep -E 'lint[[:space:]]+1' "$OUT" || true)"
if [ -z "$LINT_LINE" ]; then
  echo "FAIL: AC#2 lint row missing (regression case)"; cat "$OUT"; exit 1
fi
case "$LINT_LINE" in
  *'0 (0%)'*) : ;;
  *)
    echo "FAIL: AC#2 lint should be flaked=0 (regression, not flake)"
    echo "got: $LINT_LINE"; exit 1
    ;;
esac
echo "ok: AC#2 flake / regression / genuine-failure classifier"

# ========================================================================
# AC #3 — Catalog-coverage cross-reference. yes / partial / NO branches.
# ========================================================================
# flake-covered has 2 infra_flake_rerun events. unit-tests flaked 1x →
# 2 ≥ 1 → yes. build flaked 3x → 0 < 2 < 3 → partial.
UT_LINE="$(grep -E 'unit-tests[[:space:]]' "$OUT" || true)"
case "$UT_LINE" in
  *yes*) : ;;
  *) echo "FAIL: AC#3 unit-tests should be in-catalog=yes (events=2 ≥ flaked=1)"
     echo "got: $UT_LINE"; exit 1 ;;
esac
BUILD_LINE="$(grep -E 'build[[:space:]]' "$OUT" || true)"
case "$BUILD_LINE" in
  *partial*) : ;;
  *) echo "FAIL: AC#3 build should be in-catalog=partial (0 < events=2 < flaked=3)"
     echo "got: $BUILD_LINE"; exit 1 ;;
esac
# flake-uncovered: install-supabase-cli flaked 3x, 0 events → no.
SUPA_LINE="$(grep -E 'install-supabase-cli[[:space:]]' "$OUT" || true)"
case "$SUPA_LINE" in
  *no*) : ;;
  *) echo "FAIL: AC#3 install-supabase-cli should be in-catalog=no (0 events)"
     echo "got: $SUPA_LINE"; exit 1 ;;
esac
echo "ok: AC#3 catalog-coverage yes/partial/NO branches"

# ========================================================================
# AC #4 — next action column emits `add: <snake_case_name>` for rows
#         where in-catalog ∈ {no, partial}; emits `—` for yes rows.
# ========================================================================
# install-supabase-cli is `no` → expect `add: ...`. The title example
# from the fixture is "supabase cli rate limit hit".
if ! grep -qE 'install-supabase-cli.*add: install_supabase' "$OUT"; then
  echo "FAIL: AC#4 install-supabase-cli missing 'add: install_supabase…' suggestion"
  echo "got: $SUPA_LINE"
  cat "$OUT"; exit 1
fi
# unit-tests is `yes` → next action should be `—`.
case "$UT_LINE" in
  *'—'*) : ;;
  *) echo "FAIL: AC#4 unit-tests (yes) should have next action = '—'"
     echo "got: $UT_LINE"; exit 1 ;;
esac
echo "ok: AC#4 next action add:<snake>/em-dash"

# ========================================================================
# AC #5 — --since <Nd|Nw>. Default 30d. Min 1d, max 90d. Out-of-range
#         exits 2 with a specific stderr message.
# ========================================================================
# 7d valid.
"$FLEET" flaky --since 7d > /dev/null 2>&1 || {
  echo "FAIL: AC#5 --since 7d should exit 0"; exit 1; }
# 2w valid (== 14 days).
"$FLEET" flaky --since 2w > /dev/null 2>&1 || {
  echo "FAIL: AC#5 --since 2w should exit 0"; exit 1; }
# 1d valid (boundary).
"$FLEET" flaky --since 1d > /dev/null 2>&1 || {
  echo "FAIL: AC#5 --since 1d should exit 0"; exit 1; }
# 90d valid (boundary).
"$FLEET" flaky --since 90d > /dev/null 2>&1 || {
  echo "FAIL: AC#5 --since 90d should exit 0"; exit 1; }
# Out-of-range cases.
ERR="$TMP/flaky-since.err"
set +e
"$FLEET" flaky --since 0d > /dev/null 2> "$ERR"
EX=$?
set -e
[ "$EX" = "2" ] || { echo "FAIL: AC#5 --since 0d should exit 2 (got $EX)"; cat "$ERR"; exit 1; }
grep -qF -- '--since must be 1d-90d' "$ERR" || {
  echo "FAIL: AC#5 --since 0d missing stderr msg"; cat "$ERR"; exit 1; }
set +e
"$FLEET" flaky --since 91d > /dev/null 2> "$ERR"
EX=$?
set -e
[ "$EX" = "2" ] || { echo "FAIL: AC#5 --since 91d should exit 2"; exit 1; }
grep -qF -- '--since must be 1d-90d' "$ERR" || {
  echo "FAIL: AC#5 --since 91d missing stderr msg"; cat "$ERR"; exit 1; }
set +e
"$FLEET" flaky --since foo > /dev/null 2> "$ERR"
EX=$?
set -e
[ "$EX" = "2" ] || { echo "FAIL: AC#5 --since foo should exit 2"; exit 1; }
echo "ok: AC#5 --since boundary validation"

# ========================================================================
# AC #6 — --slug NAME restricts the walk. Unknown slug + missing value
#         exit 2 with specific stderr messages.
# ========================================================================
"$FLEET" flaky --slug flake-uncovered > "$TMP/flaky-slug.txt" 2>&1 || {
  echo "FAIL: AC#6 --slug flake-uncovered should exit 0"; cat "$TMP/flaky-slug.txt"; exit 1; }
# install-supabase-cli must appear; unit-tests must not (it lives in another slug).
grep -qE 'install-supabase-cli' "$TMP/flaky-slug.txt" || {
  echo "FAIL: AC#6 --slug filter dropped install-supabase-cli"
  cat "$TMP/flaky-slug.txt"; exit 1; }
if grep -qE '^[[:space:]]*[0-9]+[[:space:]]+unit-tests' "$TMP/flaky-slug.txt"; then
  echo "FAIL: AC#6 --slug flake-uncovered leaked unit-tests row"
  cat "$TMP/flaky-slug.txt"; exit 1
fi
# Unknown slug → exit 2 with the documented stderr.
set +e
"$FLEET" flaky --slug doesnotexist > /dev/null 2> "$ERR"
EX=$?
set -e
[ "$EX" = "2" ] || { echo "FAIL: AC#6 unknown slug should exit 2"; cat "$ERR"; exit 1; }
grep -qF -- 'flaky: slug doesnotexist not found' "$ERR" || {
  echo "FAIL: AC#6 unknown slug stderr msg missing"; cat "$ERR"; exit 1; }
# Missing value: `--slug` with no follow-up arg.
set +e
"$FLEET" flaky --slug > /dev/null 2> "$ERR"
EX=$?
set -e
[ "$EX" = "2" ] || { echo "FAIL: AC#6 --slug (missing value) should exit 2"; exit 1; }
grep -qF -- '--slug requires a value' "$ERR" || {
  echo "FAIL: AC#6 --slug missing-value stderr msg missing"; cat "$ERR"; exit 1; }
echo "ok: AC#6 --slug filter + refusals"

# ========================================================================
# AC #7 — gh calls batched: ONE `gh run list` per slug + ONE `gh run
#         view <id>` per candidate run. Count = N_slugs + N_candidate_runs
#         per LESSONS 2026-06-15.
# ========================================================================
: > "$INV_LOG"
"$FLEET" flaky > /dev/null 2>&1
# Count list calls + view calls.
LIST_CALLS="$(awk 'BEGIN { count = 0 } /^run list/ { count++ } END { print count + 0 }' "$INV_LOG")"
VIEW_CALLS="$(awk 'BEGIN { count = 0 } /^run view/ { count++ } END { print count + 0 }' "$INV_LOG")"
# 5 slugs (flake-covered, flake-uncovered, regression, healthy, gh-fails),
# but gh-fails errors immediately so list count = 5 (gh-fails still
# fires once). Candidate runs: 8 (covered) + 6 (uncovered) + 2 (regression)
# + 0 (healthy) + 0 (gh-fails after error) = 16. healthy is `[]` and
# emits zero view calls.
if [ "$LIST_CALLS" != "5" ]; then
  echo "FAIL: AC#7 expected 5 'gh run list' calls; got $LIST_CALLS"
  echo "--- inv log ---"
  cat "$INV_LOG"
  exit 1
fi
if [ "$VIEW_CALLS" != "16" ]; then
  echo "FAIL: AC#7 expected 16 'gh run view' calls; got $VIEW_CALLS"
  echo "--- inv log ---"
  cat "$INV_LOG"
  exit 1
fi
echo "ok: AC#7 gh calls batched (5 list + 16 view; NOT 5×16)"

# ========================================================================
# AC #8 — --json emits one structured object validated via node -e
#         'JSON.parse(...)'. Keys: since, slugs, total_failures, rows[],
#         estimated_cost_usd. Each row has check_name, failures, flaked,
#         flake_pct, in_catalog, next_action.
# ========================================================================
JSON_OUT="$TMP/flaky.json"
set +e
"$FLEET" flaky --json > "$JSON_OUT" 2>&1
JEXIT=$?
set -e
[ "$JEXIT" = "0" ] || { echo "FAIL: AC#8 --json exit $JEXIT"; cat "$JSON_OUT"; exit 1; }
node -e '
  const fs = require("fs");
  const obj = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
  for (const k of ["since","slugs","total_failures","rows","estimated_cost_usd"]) {
    if (!(k in obj)) { console.error("FAIL: AC#8 missing key " + k); process.exit(1); }
  }
  if (!Array.isArray(obj.rows)) { console.error("FAIL: AC#8 rows not array"); process.exit(1); }
  if (obj.rows.length === 0) { console.error("FAIL: AC#8 rows is empty"); process.exit(1); }
  for (const r of obj.rows) {
    for (const k of ["check_name","failures","flaked","flake_pct","in_catalog","next_action"]) {
      if (!(k in r)) { console.error("FAIL: AC#8 row missing key " + k); process.exit(1); }
    }
  }
  // Sanity: at least one row in_catalog === "yes", "partial", and "no".
  const states = new Set(obj.rows.map(r => r.in_catalog));
  for (const s of ["yes","partial","no"]) {
    if (!states.has(s)) { console.error("FAIL: AC#8 missing in_catalog state " + s); process.exit(1); }
  }
  console.log("ok: AC#8 --json schema");
' "$JSON_OUT"

# ========================================================================
# AC #9 — Resilient to gh failure for one slug. The failing slug renders
#         under `errors` in --json and as `<slug>: gh failed — skipped`
#         in text. Other slugs still walk. Exit 0.
# ========================================================================
RES_TXT="$TMP/flaky-res.txt"
"$FLEET" flaky > "$RES_TXT" 2>&1
# gh-fails should appear in text output as the error-skip line.
grep -qF -- 'gh-fails: gh failed' "$RES_TXT" || {
  echo "FAIL: AC#9 gh-fails resilience line missing"
  cat "$RES_TXT"; exit 1; }
# JSON has errors[] non-empty with the slug.
RES_JSON="$TMP/flaky-res.json"
"$FLEET" flaky --json > "$RES_JSON" 2>&1
node -e '
  const obj = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
  if (!Array.isArray(obj.errors)) { console.error("FAIL: AC#9 errors not array"); process.exit(1); }
  const hit = obj.errors.find(e => e.slug === "gh-fails");
  if (!hit) { console.error("FAIL: AC#9 gh-fails not in errors[]"); process.exit(1); }
  console.log("ok: AC#9 gh-fails resilience");
' "$RES_JSON"

# ========================================================================
# AC #10 — --help prints USAGE mentioning --since / --slug / --json.
#          Exit 0 (NO fall-through to the default status block).
# ========================================================================
HELP_OUT="$TMP/flaky.help.txt"
set +e
"$FLEET" flaky --help > "$HELP_OUT" 2>&1
HELP_EXIT=$?
set -e
[ "$HELP_EXIT" = "0" ] || { echo "FAIL: AC#10 --help exit $HELP_EXIT (want 0)"; cat "$HELP_OUT"; exit 1; }
for kw in --since --slug --json; do
  grep -qF -- "$kw" "$HELP_OUT" || {
    echo "FAIL: AC#10 --help missing keyword '$kw'"; cat "$HELP_OUT"; exit 1; }
done
# Dispatcher fall-through trap (LESSONS 2026-06-01) → no `INSTALLED` /
# `LAST RUN` columns from the default status block.
if grep -qF -- 'INSTALLED' "$HELP_OUT"; then
  echo "FAIL: AC#10 --help fell through to default status block"
  cat "$HELP_OUT"; exit 1
fi
echo "ok: AC#10 --help banner + exit-0"

# ========================================================================
# AC #11 — Pure reader: every slug's events.jsonl byte size AND
#          lib/heal-catalog.sh byte size unchanged before and after.
# ========================================================================
catalog_path="$FLEET_HEAL_CATALOG"
CATALOG_BEFORE="$(wc -c < "$catalog_path" | awk 'BEGIN { count = 0 } { print $1 + 0 }')"
declare -a EVENTS_BEFORE
i=0
for slug in flake-covered flake-uncovered regression healthy gh-fails; do
  ef="$HOME/.cache/${slug}-agent/events.jsonl"
  EVENTS_BEFORE[i]="$(wc -c < "$ef" | awk 'BEGIN { count = 0 } { print $1 + 0 }')"
  i=$(( i + 1 ))
done
"$FLEET" flaky > /dev/null 2>&1
"$FLEET" flaky --json > /dev/null 2>&1
CATALOG_AFTER="$(wc -c < "$catalog_path" | awk 'BEGIN { count = 0 } { print $1 + 0 }')"
[ "$CATALOG_BEFORE" = "$CATALOG_AFTER" ] || {
  echo "FAIL: AC#11 lib/heal-catalog.sh size changed (${CATALOG_BEFORE} → ${CATALOG_AFTER})"
  exit 1
}
i=0
for slug in flake-covered flake-uncovered regression healthy gh-fails; do
  ef="$HOME/.cache/${slug}-agent/events.jsonl"
  after="$(wc -c < "$ef" | awk 'BEGIN { count = 0 } { print $1 + 0 }')"
  if [ "$after" != "${EVENTS_BEFORE[i]}" ]; then
    echo "FAIL: AC#11 $slug events.jsonl size changed (${EVENTS_BEFORE[i]} → ${after})"
    exit 1
  fi
  i=$(( i + 1 ))
done
echo "ok: AC#11 pure reader — no writes to events.jsonl or heal-catalog"

# ========================================================================
# AC #12 — lib/common.sh and prompts/ NOT touched. The diff against main
#          for those paths must be empty.
# ========================================================================
DIFF_OUT="$(cd "$REPO_ROOT" && git diff --name-only main...HEAD -- lib/common.sh prompts/ 2>/dev/null || true)"
if [ -n "$DIFF_OUT" ]; then
  echo "FAIL: AC#12 lib/common.sh or prompts/ modified:"
  echo "$DIFF_OUT"
  exit 1
fi
echo "ok: AC#12 lib/common.sh + prompts/ untouched"

# ========================================================================
# AC #13 — Classifier uses ONE awk pass per slug to group (headSha,
#          workflow, check) and detect fail→pass on same vs newer SHA.
#          Per LESSONS 2026-06-08 BEGIN { count = 0 }. We assert the
#          source of flaky_classify_runs declares that BEGIN block AND
#          the source of the per-slug count loop also uses the awk-
#          count pattern (LESSONS 2026-06-01 grep -c double-print).
# ========================================================================
if ! grep -nE 'flaky_classify_runs\(\)' "$REPO_ROOT/bin/fleet" >/dev/null; then
  echo "FAIL: AC#13 flaky_classify_runs() not defined"; exit 1
fi
# awk BEGIN { count = 0 } guard somewhere inside flaky_classify_runs body.
# The BEGIN line and the `count = 0` line may be on different lines (the
# BEGIN { opens a multi-line block in our implementation). Walk the body
# and stamp `seen_begin` when we cross a `BEGIN {` and `found` when we
# then see a `count = 0` BEFORE we exit the function.
awk '
  BEGIN { count = 0 }
  /^flaky_classify_runs\(\) \{/ { inside = 1; next }
  inside && /^\}/ && !found        { exit 1 }
  inside && /BEGIN[[:space:]]*\{/  { seen_begin = 1 }
  inside && seen_begin && /count[[:space:]]*=[[:space:]]*0/ { found = 1 }
  END { exit found ? 0 : 1 }
' "$REPO_ROOT/bin/fleet" || {
  echo "FAIL: AC#13 flaky_classify_runs missing BEGIN { count = 0 } guard"; exit 1; }
# Surgical scan: flaky() function body must NOT call fleet_emit_event.
awk '
  /^flaky\(\) \{/                 { inside = 1; next }
  inside && /^if \[ "\$CMD" = "flaky" \]; then/ { inside = 0 }
  inside && /fleet_emit_event/    { found = 1 }
  END                              { exit found ? 1 : 0 }
' "$REPO_ROOT/bin/fleet" || {
  echo "FAIL: AC#13 flaky() calls fleet_emit_event — must be a pure reader"; exit 1; }
echo "ok: AC#13 classifier shape + pure-reader source-level check"

# ========================================================================
# Coverage tally: AC#1–#13 all asserted above.
# ========================================================================
echo "ok: tests/flaky.sh passed (13/13 assertions)"
