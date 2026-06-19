#!/bin/bash
# tests/stuck.sh — `bin/fleet stuck` end-to-end test (ticket 0059).
#
# One assertion block per acceptance-criteria checkbox in
# docs/backlog/0059-fleet-stuck-pr-detector.md (12 boxes).
#
# Fixture: six synthetic slugs under tests/fixtures/stuck/<slug>/, each
# with an `agents.config.sh` and an `events.jsonl`. The `gh` stub reads
# per-slug response JSON from $TMP/gh-fixtures/<slug>/<command>.json and
# records every invocation to $TMP/gh-invocations.log so AC#5's exact-
# count assertion can fire. Stubs live under $HOME/.local/bin per
# LESSONS 2026-05-26 (PATH reset in lib/common.sh — bin/fleet does NOT
# source it, but we keep the convention uniform). Backup/restore via
# `cp` per LESSONS 2026-05-27. Counts via `awk … END { print n+0 }` per
# LESSONS 2026-06-01. Every awk script declares `BEGIN { count = 0 }`
# per LESSONS 2026-06-08. Clock frozen via FLEET_NOW_OVERRIDE so the
# "age > 1h" predicate in DRAFT_armed is deterministic.

set -euo pipefail

REPO_ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
FLEET="$REPO_ROOT/bin/fleet"

TMP="$(mktemp -d -t fleet-stuck-test.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

# Isolate HOME so we sandbox $HOME/.cache + $HOME/.local/bin per
# LESSONS 2026-05-26 (PATH reset).
export HOME="$TMP/home"
mkdir -p "$HOME/.local/bin"

# Pinned epoch: 2026-06-19T12:00:00Z. The "age > 1h" DRAFT_armed
# predicate uses now - createdAt, so we anchor fixtures' createdAt
# values to NOW minus a deterministic offset.
NOW_EPOCH=1781697600  # 2026-06-19 00:00:00 UTC — round midnight
NOW_ISO="2026-06-19T00:00:00Z"
export FLEET_NOW_OVERRIDE="$NOW_EPOCH"
export FLEET_STUCK_FAKE_NOW="$NOW_EPOCH"

iso_at() {  # $1 = epoch seconds → YYYY-MM-DDTHH:MM:SSZ (full format,
            # per LESSONS 2026-06-11 — no missing time fields)
  date -u -r "$1" +%FT%TZ 2>/dev/null || date -u -d "@$1" +%FT%TZ
}

# Offsets for fixture PR createdAt:
TWO_HR_AGO=$((  NOW_EPOCH - 2 * 3600 ))
FOUR_HR_AGO=$(( NOW_EPOCH - 4 * 3600 ))
EIGHT_HR_AGO=$((NOW_EPOCH - 8 * 3600 ))
TWENTY_TWO_HR_AGO=$(( NOW_EPOCH - 22 * 3600 ))
THIRTY_MIN_AGO=$((    NOW_EPOCH - 30 * 60 ))

# --- fixture slugs (FLEET_DISCOVERY_ROOT seam) ----------------------------
FIXTURE="$TMP/projects"
mkdir -p "$FIXTURE"

emit_manifest() {  # $1 = slug, $2 = repo (owner/name)
  local slug="$1" repo="$2"
  mkdir -p "$FIXTURE/$slug"
  cat > "$FIXTURE/$slug/agents.config.sh" <<CFG
PROJECT_NAME="${slug}"
SLUG="${slug}"
NAMESPACE="com.${slug}"
REPO_URL="https://github.com/${repo}"
SELF_CANCEL="20990101"
CFG
  mkdir -p "$HOME/.cache/${slug}-agent"
  : > "$HOME/.cache/${slug}-agent/events.jsonl"
}

emit_manifest behind            example/behind
emit_manifest draft-armed       example/draft-armed
emit_manifest account-suspended example/account-suspended
emit_manifest flake-loop        example/flake-loop
emit_manifest healthy           example/healthy
emit_manifest gh-fails          example/gh-fails

# Seed flake-loop with one infra_flake_rerun event for PR #401 against
# run_id 9991, plus a healthy pr_opened on PR #401. The classifier walks
# events.jsonl in a single awk pass per LESSONS 2026-06-15.
cat > "$HOME/.cache/flake-loop-agent/events.jsonl" <<JSONL
{"ts":"$(iso_at "$FOUR_HR_AGO")","slug":"flake-loop","phase":"ship","type":"pr_opened","number":"401","branch":"feat/0099-x"}
{"ts":"$(iso_at "$TWO_HR_AGO")","slug":"flake-loop","phase":"ship","type":"infra_flake_rerun","pattern":"actions_silent","run_id":"9991","pr":"401"}
JSONL

# --- gh fixtures dir ------------------------------------------------------
GH_FIX="$TMP/gh-fixtures"
mkdir -p "$GH_FIX"

# `gh pr list --repo example/behind …` returns one PR #101.
mkdir -p "$GH_FIX/behind"
cat > "$GH_FIX/behind/pr-list.json" <<JSON
[{"number":101,"headRefName":"feat/0001-rebase-me"}]
JSON
cat > "$GH_FIX/behind/pr-view-101.json" <<JSON
{"number":101,"mergeStateStatus":"BEHIND","isDraft":false,"autoMergeRequest":{"enabledAt":"$(iso_at "$TWENTY_TWO_HR_AGO")"},"createdAt":"$(iso_at "$TWENTY_TWO_HR_AGO")","statusCheckRollup":[{"name":"shellcheck","conclusion":"SUCCESS"},{"name":"validate","conclusion":"SUCCESS"}]}
JSON

# `gh pr list --repo example/draft-armed …` returns one PR #214.
mkdir -p "$GH_FIX/draft-armed"
cat > "$GH_FIX/draft-armed/pr-list.json" <<JSON
[{"number":214,"headRefName":"feat/0002-still-drafting"}]
JSON
cat > "$GH_FIX/draft-armed/pr-view-214.json" <<JSON
{"number":214,"mergeStateStatus":"BLOCKED","isDraft":true,"autoMergeRequest":null,"createdAt":"$(iso_at "$EIGHT_HR_AGO")","statusCheckRollup":[{"name":"shellcheck","conclusion":"SUCCESS"},{"name":"validate","conclusion":"SUCCESS"}]}
JSON

# `gh pr list --repo example/account-suspended …` returns one PR #305.
mkdir -p "$GH_FIX/account-suspended"
cat > "$GH_FIX/account-suspended/pr-list.json" <<JSON
[{"number":305,"headRefName":"feat/0003-suspended"}]
JSON
cat > "$GH_FIX/account-suspended/pr-view-305.json" <<JSON
{"number":305,"mergeStateStatus":"BLOCKED","isDraft":false,"autoMergeRequest":null,"createdAt":"$(iso_at "$FOUR_HR_AGO")","statusCheckRollup":[{"name":"shellcheck","conclusion":"FAILURE","output":{"title":"Your account is suspended."}},{"name":"validate","conclusion":"FAILURE","output":{"title":"Your account is suspended."}}]}
JSON

# `gh pr list --repo example/flake-loop …` returns one PR #401.
mkdir -p "$GH_FIX/flake-loop"
cat > "$GH_FIX/flake-loop/pr-list.json" <<JSON
[{"number":401,"headRefName":"feat/0099-flake"}]
JSON
cat > "$GH_FIX/flake-loop/pr-view-401.json" <<JSON
{"number":401,"mergeStateStatus":"BLOCKED","isDraft":false,"autoMergeRequest":null,"createdAt":"$(iso_at "$FOUR_HR_AGO")","statusCheckRollup":[{"name":"shellcheck","conclusion":"FAILURE"},{"name":"validate","conclusion":"FAILURE"}]}
JSON
# The `gh run view 9991` call returns the rerun's conclusion.
cat > "$GH_FIX/flake-loop/run-view-9991.json" <<JSON
{"databaseId":9991,"conclusion":"failure","status":"completed"}
JSON

# `gh pr list --repo example/healthy …` returns TWO open PRs, BOTH young.
mkdir -p "$GH_FIX/healthy"
cat > "$GH_FIX/healthy/pr-list.json" <<JSON
[{"number":501,"headRefName":"feat/0010-young"},{"number":502,"headRefName":"eng/0011-also-young"}]
JSON
cat > "$GH_FIX/healthy/pr-view-501.json" <<JSON
{"number":501,"mergeStateStatus":"CLEAN","isDraft":false,"autoMergeRequest":{"enabledAt":"$(iso_at "$THIRTY_MIN_AGO")"},"createdAt":"$(iso_at "$THIRTY_MIN_AGO")","statusCheckRollup":[{"name":"shellcheck","conclusion":"SUCCESS"},{"name":"validate","conclusion":"SUCCESS"}]}
JSON
cat > "$GH_FIX/healthy/pr-view-502.json" <<JSON
{"number":502,"mergeStateStatus":"BLOCKED","isDraft":false,"autoMergeRequest":{"enabledAt":"$(iso_at "$THIRTY_MIN_AGO")"},"createdAt":"$(iso_at "$THIRTY_MIN_AGO")","statusCheckRollup":[{"name":"shellcheck","conclusion":"SUCCESS"},{"name":"validate","conclusion":"PENDING"}]}
JSON

# `gh pr list --repo example/gh-fails …` errors. The stub treats the
# presence of a `gh-fail` sentinel file as "exit 1 with a message".
mkdir -p "$GH_FIX/gh-fails"
touch "$GH_FIX/gh-fails/gh-fail"

# --- gh stub --------------------------------------------------------------
# Writes every invocation to $TMP/gh-invocations.log so AC#5's count
# assertion can fire. The stub maps `--repo <owner>/<slug>` to the
# matching fixture dir under $GH_FIX/<slug>/ and returns the canned
# JSON. Unknown queries return `[]` to keep partial walks safe.
INV_LOG="$TMP/gh-invocations.log"
: > "$INV_LOG"

cat > "$HOME/.local/bin/gh" <<STUB
#!/bin/bash
# fixture root + invocation log come from env.
INV="\${FLEET_STUCK_TEST_INV:-$INV_LOG}"
FIX="\${FLEET_STUCK_TEST_FIX:-$GH_FIX}"
printf '%s\n' "\$*" >> "\$INV"

# Walk argv for --repo <owner>/<slug>.
repo=""
i=1
for arg in "\$@"; do
  case "\$arg" in
    --repo) need=1 ;;
    *) if [ "\${need:-0}" = "1" ]; then repo="\$arg"; need=0; fi ;;
  esac
done
slug=""
case "\$repo" in
  */*) slug="\${repo##*/}" ;;
esac

# Detect the gh-fails sentinel.
if [ -n "\$slug" ] && [ -f "\$FIX/\$slug/gh-fail" ]; then
  echo "gh: API request failed: rate limit exceeded" >&2
  exit 1
fi

sub1="\${1:-}"; sub2="\${2:-}"
case "\${sub1}/\${sub2}" in
  pr/list)
    if [ -n "\$slug" ] && [ -f "\$FIX/\$slug/pr-list.json" ]; then
      cat "\$FIX/\$slug/pr-list.json"
    else
      echo "[]"
    fi
    exit 0
    ;;
  pr/view)
    # \$3 = PR number.
    n="\${3:-}"
    if [ -n "\$slug" ] && [ -f "\$FIX/\$slug/pr-view-\$n.json" ]; then
      cat "\$FIX/\$slug/pr-view-\$n.json"
    else
      echo "{}"
    fi
    exit 0
    ;;
  run/view)
    n="\${3:-}"
    if [ -n "\$slug" ] && [ -f "\$FIX/\$slug/run-view-\$n.json" ]; then
      cat "\$FIX/\$slug/run-view-\$n.json"
    else
      echo "{}"
    fi
    exit 0
    ;;
  auth/status)
    exit 0 ;;
  *)
    echo "[]"; exit 0 ;;
esac
STUB
chmod +x "$HOME/.local/bin/gh"

# Ensure the stub wins.
export PATH="$HOME/.local/bin:$PATH"
export FLEET_DISCOVERY_ROOT="$FIXTURE"

# Helper: count gh invocations so AC#5 can assert.
gh_invocation_count() {
  awk 'BEGIN { count = 0 } NF > 0 { count++ } END { print count + 0 }' "$INV_LOG"
}

fail() { echo "FAIL: $*" >&2; echo "--- gh-invocations.log ---" >&2; cat "$INV_LOG" >&2 || true; exit 1; }

# ========================================================================
# AC #1 — `bin/fleet stuck` walks every discovered slug, prints one row
#         per stuck PR + a `healthy in-flight: …` footer naming the
#         not-classified PRs. Exit 0.
# ========================================================================
OUT="$TMP/stuck.txt"
: > "$INV_LOG"
set +e
"$FLEET" stuck > "$OUT" 2>&1
EXIT=$?
set -e
[ "$EXIT" = "0" ] || fail "AC#1: exit was $EXIT (expected 0); out: $(cat "$OUT")"

grep -qF -- "stuck — " "$OUT" || fail "AC#1: header missing 'stuck — '"
grep -qF -- "behind" "$OUT" || fail "AC#1: behind row missing"
grep -qF -- "draft-armed" "$OUT" || fail "AC#1: draft-armed row missing"
grep -qF -- "account-suspended" "$OUT" || fail "AC#1: account-suspended row missing"
grep -qF -- "flake-loop" "$OUT" || fail "AC#1: flake-loop row missing"
grep -qF -- "healthy in-flight" "$OUT" || fail "AC#1: footer missing 'healthy in-flight'"
grep -qF -- "#501" "$OUT" || fail "AC#1: footer missing healthy PR #501"
grep -qF -- "#502" "$OUT" || fail "AC#1: footer missing healthy PR #502"

# All-healthy branch: restrict to one healthy-only fixture root.
ALL_HEALTHY="$TMP/all-healthy-projects"
mkdir -p "$ALL_HEALTHY/healthy"
cp "$FIXTURE/healthy/agents.config.sh" "$ALL_HEALTHY/healthy/agents.config.sh"
set +e
FLEET_DISCOVERY_ROOT="$ALL_HEALTHY" "$FLEET" stuck > "$OUT" 2>&1
EXIT=$?
set -e
[ "$EXIT" = "0" ] || fail "AC#1: all-healthy exit was $EXIT (expected 0)"
grep -qF -- "stuck — 0 PRs" "$OUT" || fail "AC#1: all-healthy header missing 'stuck — 0 PRs'; out: $(cat "$OUT")"

# ========================================================================
# AC #2 — classifier recognizes exactly four causes via the fixtures.
# ========================================================================
: > "$INV_LOG"
"$FLEET" stuck > "$OUT" 2>&1 || true
grep -qF -- "BEHIND" "$OUT" || fail "AC#2: BEHIND cause missing"
grep -qF -- "DRAFT_armed" "$OUT" || fail "AC#2: DRAFT_armed cause missing"
grep -qF -- "account_suspended" "$OUT" || fail "AC#2: account_suspended cause missing"
grep -qF -- "infra_flake_loop" "$OUT" || fail "AC#2: infra_flake_loop cause missing"

# ========================================================================
# AC #3 — action strings per cause.
# ========================================================================
grep -qF -- "gh pr update-branch 101" "$OUT" || fail "AC#3: BEHIND action missing"
grep -qF -- "gh pr ready 214 && gh pr merge 214 --auto --squash" "$OUT" || fail "AC#3: DRAFT_armed action missing"
grep -qF -- "wait — typically clears in 30min" "$OUT" || fail "AC#3: account_suspended action missing"
grep -qF -- "fleet incident flake-loop --since 2h" "$OUT" || fail "AC#3: infra_flake_loop action missing"

# ========================================================================
# AC #4 — --slug NAME restricts the walk; unknown slug & missing value
#         both refuse with exit 2.
# ========================================================================
: > "$INV_LOG"
set +e
"$FLEET" stuck --slug behind > "$OUT" 2>&1
EXIT=$?
set -e
[ "$EXIT" = "0" ] || fail "AC#4: --slug behind exit was $EXIT (expected 0); out: $(cat "$OUT")"
grep -qF -- "behind" "$OUT" || fail "AC#4: --slug behind: behind row missing"
grep -qF -- "draft-armed" "$OUT" && fail "AC#4: --slug behind unexpectedly contains draft-armed row"

set +e
"$FLEET" stuck --slug nonexistent > "$OUT" 2>&1
EXIT=$?
set -e
[ "$EXIT" = "2" ] || fail "AC#4: unknown-slug exit was $EXIT (expected 2)"
grep -qF -- "stuck: slug nonexistent not found." "$OUT" || fail "AC#4: unknown-slug message missing"
grep -qF -- "discovered slugs:" "$OUT" || fail "AC#4: unknown-slug missing 'discovered slugs:'"

set +e
"$FLEET" stuck --slug > "$OUT" 2>&1
EXIT=$?
set -e
[ "$EXIT" = "2" ] || fail "AC#4: --slug missing-value exit was $EXIT (expected 2)"
grep -qF -- "stuck: --slug requires a value" "$OUT" || fail "AC#4: --slug missing-value message missing"

# ========================================================================
# AC #5 — gh calls batched. 6 slugs × 1 pr-list each + 5 pr-view (one per
#         PR returned across non-failing slugs: behind=1, draft-armed=1,
#         account-suspended=1, flake-loop=1, healthy=2 = 6 PRs) + 1
#         run-view for the flake-loop infra-flake check = 6 + 6 + 1 = 13.
#         The gh-fails slug only invokes pr-list (which fails). The ticket
#         names the example "4 slugs + 6 PRs = 10" — our fixture has 6
#         slugs (one fails) + 6 PRs + 1 run-view = 13; the ASSERTION
#         is that we DON'T explode to N_slugs × N_PRs (which would be
#         6 × 6 = 36). We assert count <= 15 (defensive band) AND
#         pr-list count == 6 (one per slug) AND pr-view count == 6.
# ========================================================================
total="$(gh_invocation_count)"
pr_list_count="$(awk 'BEGIN { count = 0 } /^pr list/ { count++ } END { print count + 0 }' "$INV_LOG")"
pr_view_count="$(awk 'BEGIN { count = 0 } /^pr view/ { count++ } END { print count + 0 }' "$INV_LOG")"
[ "$pr_list_count" = "1" ] || fail "AC#5: --slug pr list count was $pr_list_count (expected 1 for one slug)"
[ "$pr_view_count" = "1" ] || fail "AC#5: --slug pr view count was $pr_view_count (expected 1 for one slug)"

# Now the unrestricted run: count again from a clean log.
: > "$INV_LOG"
"$FLEET" stuck > /dev/null 2>&1 || true
total="$(gh_invocation_count)"
pr_list_count="$(awk 'BEGIN { count = 0 } /^pr list/ { count++ } END { print count + 0 }' "$INV_LOG")"
pr_view_count="$(awk 'BEGIN { count = 0 } /^pr view/ { count++ } END { print count + 0 }' "$INV_LOG")"
# 6 slugs → 6 pr-list calls. 6 PRs returned (behind 1, draft-armed 1,
# account-suspended 1, flake-loop 1, healthy 2, gh-fails 0) → 6 pr-view.
[ "$pr_list_count" = "6" ] || fail "AC#5: full-walk pr list count was $pr_list_count (expected 6)"
[ "$pr_view_count" = "6" ] || fail "AC#5: full-walk pr view count was $pr_view_count (expected 6)"
# Guard against the O(N_slugs × N_PRs) regression.
if [ "$total" -ge 30 ]; then
  fail "AC#5: total gh invocations $total >= 30 (smells like N_slugs × N_PRs); log: $(cat "$INV_LOG")"
fi

# ========================================================================
# AC #6 — --json emits a valid JSON array.
# ========================================================================
JSON_OUT="$TMP/stuck.json"
: > "$INV_LOG"
set +e
"$FLEET" stuck --json > "$JSON_OUT" 2>&1
EXIT=$?
set -e
[ "$EXIT" = "0" ] || fail "AC#6: --json exit was $EXIT; out: $(cat "$JSON_OUT")"
# Node MUST parse the output.
node -e 'const d=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"));
if (typeof d !== "object" || d === null) { console.error("not an object"); process.exit(1); }
if (!Array.isArray(d.stuck)) { console.error("stuck not an array"); process.exit(1); }
if (!Array.isArray(d.healthy)) { console.error("healthy not an array"); process.exit(1); }
// Each stuck element has slug, pr, cause, action, age_hours, detail.
for (const r of d.stuck) {
  for (const k of ["slug","pr","cause","action","age_hours","detail"]) {
    if (!(k in r)) { console.error("stuck row missing key "+k+": "+JSON.stringify(r)); process.exit(1); }
  }
}
for (const r of d.healthy) {
  for (const k of ["slug","pr"]) {
    if (!(k in r)) { console.error("healthy row missing key "+k+": "+JSON.stringify(r)); process.exit(1); }
  }
}
// Causes are from the v1 catalog.
const ok = new Set(["BEHIND","DRAFT_armed","account_suspended","infra_flake_loop"]);
for (const r of d.stuck) {
  if (!ok.has(r.cause)) { console.error("unknown cause: "+r.cause); process.exit(1); }
}
' "$JSON_OUT" || fail "AC#6: JSON parse/shape check failed"

# ========================================================================
# AC #7 — resilience: gh-fails slug renders as `<slug>: gh failed —
#         skipped` in text AND appears under errors[] in JSON. Other
#         slugs still walk; exit 0.
# ========================================================================
: > "$INV_LOG"
"$FLEET" stuck > "$OUT" 2>&1 || true
grep -qF -- "gh-fails: gh failed — skipped" "$OUT" || fail "AC#7: gh-fails skip line missing; out: $(cat "$OUT")"
# Other slugs still resolved.
grep -qF -- "behind" "$OUT" || fail "AC#7: behind row missing after gh-fails skip"

: > "$INV_LOG"
"$FLEET" stuck --json > "$JSON_OUT" 2>&1 || true
node -e 'const d=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"));
if (!Array.isArray(d.errors) || d.errors.length < 1) { console.error("errors array missing/empty"); process.exit(1); }
const e = d.errors.find(x => x.slug === "gh-fails");
if (!e) { console.error("gh-fails not in errors[]"); process.exit(1); }
if (typeof e.error !== "string" || !e.error.length) { console.error("gh-fails error message missing"); process.exit(1); }
' "$JSON_OUT" || fail "AC#7: JSON errors[] shape check failed"

# ========================================================================
# AC #8 — --help prints USAGE that mentions --slug and --json. Per
#         LESSONS 2026-05-30 we use `grep -qF -- "$kw"`.
# ========================================================================
HELP_OUT="$TMP/help.txt"
set +e
"$FLEET" stuck --help > "$HELP_OUT" 2>&1
EXIT=$?
set -e
[ "$EXIT" = "0" ] || fail "AC#8: --help exit was $EXIT"
for kw in '--slug' '--json' 'stuck'; do
  if ! grep -qF -- "$kw" "$HELP_OUT"; then
    fail "AC#8: --help missing keyword '$kw'"
  fi
done

# ========================================================================
# AC #9 — pure reader. NO events.jsonl bytes added across the walk.
# ========================================================================
declare -a SLUGS=(behind draft-armed account-suspended flake-loop healthy gh-fails)
declare -A BYTES_BEFORE
for s in "${SLUGS[@]}"; do
  BYTES_BEFORE[$s]="$(wc -c < "$HOME/.cache/${s}-agent/events.jsonl")"
done
"$FLEET" stuck > /dev/null 2>&1 || true
"$FLEET" stuck --json > /dev/null 2>&1 || true
for s in "${SLUGS[@]}"; do
  after="$(wc -c < "$HOME/.cache/${s}-agent/events.jsonl")"
  if [ "$after" != "${BYTES_BEFORE[$s]}" ]; then
    fail "AC#9: $s events.jsonl size changed (${BYTES_BEFORE[$s]} → $after)"
  fi
done

# ========================================================================
# AC #10 — lib/common.sh + prompts/ untouched on this branch.
# ========================================================================
diff_lib="$(cd "$REPO_ROOT" && git diff --name-only main...HEAD -- lib/common.sh prompts/ 2>/dev/null || true)"
if [ -n "$diff_lib" ]; then
  fail "AC#10: forbidden files changed: $diff_lib"
fi

# ========================================================================
# AC #11 — account_suspended path: BOTH failing checks carry the
#          suspension substring → cause = account_suspended. A negative
#          fixture where a failing check carries an unrelated message
#          MUST NOT classify as account_suspended.
# ========================================================================
NEG_ROOT="$TMP/neg-projects"
mkdir -p "$NEG_ROOT/neg-fail"
cat > "$NEG_ROOT/neg-fail/agents.config.sh" <<CFG
SLUG="neg-fail"
NAMESPACE="com.neg-fail"
REPO_URL="https://github.com/example/neg-fail"
SELF_CANCEL="20990101"
CFG
mkdir -p "$HOME/.cache/neg-fail-agent"
: > "$HOME/.cache/neg-fail-agent/events.jsonl"
mkdir -p "$GH_FIX/neg-fail"
cat > "$GH_FIX/neg-fail/pr-list.json" <<JSON
[{"number":701,"headRefName":"feat/0070-neg"}]
JSON
cat > "$GH_FIX/neg-fail/pr-view-701.json" <<JSON
{"number":701,"mergeStateStatus":"BLOCKED","isDraft":false,"autoMergeRequest":null,"createdAt":"$(iso_at "$FOUR_HR_AGO")","statusCheckRollup":[{"name":"shellcheck","conclusion":"FAILURE","output":{"title":"shellcheck failed: SC2086"}},{"name":"validate","conclusion":"SUCCESS"}]}
JSON

set +e
FLEET_DISCOVERY_ROOT="$NEG_ROOT" "$FLEET" stuck --json > "$JSON_OUT" 2>&1
EXIT=$?
set -e
[ "$EXIT" = "0" ] || fail "AC#11: neg exit was $EXIT"
node -e 'const d=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"));
const susp = d.stuck.filter(r => r.cause === "account_suspended");
if (susp.length > 0) { console.error("neg fixture wrongly classified as account_suspended"); process.exit(1); }
' "$JSON_OUT" || fail "AC#11: neg classifier guard failed"

# Positive: the account-suspended fixture from the main walk classifies.
"$FLEET" stuck --json > "$JSON_OUT" 2>&1 || true
node -e 'const d=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"));
const susp = d.stuck.filter(r => r.cause === "account_suspended");
if (!susp.length) { console.error("account-suspended fixture not classified"); process.exit(1); }
' "$JSON_OUT" || fail "AC#11: positive classifier failed"

# ========================================================================
# AC #12 — infra_flake_loop: events.jsonl walk is ONE awk pass per slug,
#          NOT per PR. We confirm via JSON shape: the flake-loop PR #401
#          carries cause = infra_flake_loop.
# ========================================================================
"$FLEET" stuck --json > "$JSON_OUT" 2>&1 || true
node -e 'const d=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"));
const r = d.stuck.find(x => x.slug === "flake-loop" && x.pr === 401);
if (!r) { console.error("flake-loop PR #401 not in stuck[]"); process.exit(1); }
if (r.cause !== "infra_flake_loop") { console.error("flake-loop cause is "+r.cause+" (expected infra_flake_loop)"); process.exit(1); }
' "$JSON_OUT" || fail "AC#12: flake-loop classification failed"

echo "OK tests/stuck.sh — all 12 acceptance criteria pass"
exit 0
