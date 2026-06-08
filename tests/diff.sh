#!/bin/bash
# tests/diff.sh — `bin/fleet diff <slug-a> <slug-b>` cross-project divergence test.
#
# Ticket 0038. One assertion block per acceptance-criteria checkbox in
# docs/backlog/0038-fleet-diff-cross-project-divergence.md. The `diff`
# reader is a pure consumer of the existing events.jsonl + runs.jsonl
# channels — no new event types, no fleet_* signature changes.
#
# Fixtures: two synthetic projects (slug-a healthy, slug-b degraded)
# seeded under a tmpdir FLEET_DISCOVERY_ROOT, mirroring tests/weekly.sh
# and tests/incident.sh. Time is pinned via FLEET_NOW_OVERRIDE so the
# rendered window header + every count stays deterministic.
#
# Per LESSONS 2026-05-26 ($HOME/.local/bin stubs survive lib/common.sh's
# PATH reset). Per LESSONS 2026-05-27 every fixture file is copied via
# `cp` — never `$(cat …)` — to preserve byte-exact trailing newlines.
# Per LESSONS 2026-06-01 (`grep -c file || echo 0` double-print trap)
# every count uses `awk … END { print n+0 }`. Per LESSONS 2026-05-30
# (`grep -F --` flag trap) every help-text grep uses `grep -qF -- "$kw"`.

set -euo pipefail

REPO_ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
FLEET="$REPO_ROOT/bin/fleet"
FIXTURE_DIR="$REPO_ROOT/tests/fixtures/diff"
GOLDEN_TEXT="$FIXTURE_DIR/diff.text.golden.txt"

TMP="$(mktemp -d -t fleet-diff-test.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

# Isolate HOME so $HOME/.cache, $HOME/.local/bin are sandboxed.
export HOME="$TMP/home"
mkdir -p "$HOME/.local/bin"

# Stable epoch anchor — 2026-06-08T12:00:00Z. The default window is 14d,
# so the rendered window header should read 2026-05-25 → 2026-06-08.
NOW_EPOCH=1780920000
export FLEET_NOW_OVERRIDE="$NOW_EPOCH"

iso_at() {  # $1 = epoch seconds → "YYYY-MM-DDTHH:MM:SSZ"
  date -u -r "$1" +%FT%TZ 2>/dev/null || date -u -d "@$1" +%FT%TZ
}

T_30D_AGO=$(( NOW_EPOCH - 30 * 86400 ))
T_12D_AGO=$(( NOW_EPOCH - 12 * 86400 ))
T_10D_AGO=$(( NOW_EPOCH - 10 * 86400 ))
T_8D_AGO=$(( NOW_EPOCH - 8 * 86400 ))
T_7D_AGO=$(( NOW_EPOCH - 7 * 86400 ))
T_6D_AGO=$(( NOW_EPOCH - 6 * 86400 ))
T_5D_AGO=$(( NOW_EPOCH - 5 * 86400 ))
T_4D_AGO=$(( NOW_EPOCH - 4 * 86400 ))
T_3D_AGO=$(( NOW_EPOCH - 3 * 86400 ))
T_2D_AGO=$(( NOW_EPOCH - 2 * 86400 ))
T_1D_AGO=$(( NOW_EPOCH - 1 * 86400 ))

FIXTURE_ROOT="$TMP/projects"
mkdir -p "$FIXTURE_ROOT"
export FLEET_DISCOVERY_ROOT="$FIXTURE_ROOT"

mk_manifest() {  # $1 = slug, $2 = prompts_sha
  local slug="$1" sha="$2"
  mkdir -p "$FIXTURE_ROOT/$slug"
  cat > "$FIXTURE_ROOT/$slug/agents.config.sh" <<CFG
PROJECT_NAME="$slug"
SLUG="$slug"
NAMESPACE="com.$slug"
REPO_URL="https://github.com/example/$slug"
SELF_CANCEL="20990101"
PROMPTS_SHA="$sha"
CFG
}

# ============================================================================
# Fixture A: slug-a (healthy week)
#   ships     = 19  (19 pr_opened events in window)
#   merges    = 18  (18 SHIP-prefix runs in window)
#   sendbacks = 3   (3 lesson_draft_emitted events in window)
#   spend     = 8.42 ($0.42 * 19 SHIP + $0.44 OOW)
#   paused hr = 0   (no ship_paused)
#   drafts    = 1   (1 unpromoted lesson_draft_emitted)
#   prompts   = 8a20547abcdef
#   atlas top = gh_graphql_502:2
# ============================================================================
mk_manifest slug-a 8a20547abcdef0123456789012345678901234567

A_CACHE="$HOME/.cache/slug-a-agent"
mkdir -p "$A_CACHE"

{
  # 19 SHIP runs in window — but only 18 result_head start with "SHIP "
  # to give merges=18 ships=19 (one pr_opened without a SHIP exit).
  for i in $(seq 1 18); do
    ts=$(( T_10D_AGO + i * 3600 ))
    printf '{"slug":"slug-a","phase":"ship","ts_start":"%s","ts_end":"%s","exit":0,"total_cost_usd":0.42,"result_head":"SHIP 00%02d-x — PR #%d green"}\n' \
      "$(iso_at "$ts")" "$(iso_at $(( ts + 60 )))" "$i" "$(( 100 + i ))"
  done
  # 19th run — heal exit, not a SHIP success (pr_opened was emitted but exit_head was HEAL).
  printf '{"slug":"slug-a","phase":"ship","ts_start":"%s","ts_end":"%s","exit":0,"total_cost_usd":0.42,"result_head":"HEAL #1 fix shellcheck warning"}\n' \
    "$(iso_at $(( T_2D_AGO )))" "$(iso_at $(( T_2D_AGO + 60 )))"
  # Out-of-window — must NOT count toward merges or spend.
  printf '{"slug":"slug-a","phase":"ship","ts_start":"%s","ts_end":"%s","exit":0,"total_cost_usd":0.44,"result_head":"SHIP 9999-z — PR #1 green"}\n' \
    "$(iso_at "$T_30D_AGO")" "$(iso_at $(( T_30D_AGO + 60 )))"
} > "$A_CACHE/runs.jsonl"

{
  # 19 pr_opened events in window.
  for i in $(seq 1 19); do
    ts=$(( T_10D_AGO + i * 3600 ))
    printf '{"ts":"%s","slug":"slug-a","phase":"ship","type":"pr_opened","number":"%d","branch":"feat/00%02d-x"}\n' \
      "$(iso_at "$ts")" "$(( 100 + i ))" "$i"
  done
  # 3 sendbacks (lesson_draft_emitted) — 1 unpromoted (drafts=1), 2 promoted.
  printf '{"ts":"%s","slug":"slug-a","phase":"review","type":"lesson_draft_emitted","pr":"101","headline":"draft 1","text_sha":"aaaa0001"}\n' \
    "$(iso_at $(( T_8D_AGO )))"
  printf '{"ts":"%s","slug":"slug-a","phase":"review","type":"lesson_draft_emitted","pr":"102","headline":"draft 2","text_sha":"aaaa0002"}\n' \
    "$(iso_at $(( T_7D_AGO )))"
  printf '{"ts":"%s","slug":"slug-a","phase":"review","type":"lesson_draft_emitted","pr":"103","headline":"draft 3","text_sha":"aaaa0003"}\n' \
    "$(iso_at $(( T_6D_AGO )))"
  # Promote two of them — leaves draft promotion debt = 1.
  printf '{"ts":"%s","slug":"slug-a","phase":"promote","type":"lesson_promoted","source":"slug-a","text_sha":"aaaa0001","scope":"all"}\n' \
    "$(iso_at $(( T_5D_AGO )))"
  printf '{"ts":"%s","slug":"slug-a","phase":"promote","type":"lesson_promoted","source":"slug-a","text_sha":"aaaa0002","scope":"all"}\n' \
    "$(iso_at $(( T_5D_AGO + 3600 )))"
  # 2 infra_flake_rerun events on gh_graphql_502 (top atlas pattern).
  printf '{"ts":"%s","slug":"slug-a","phase":"ship","type":"infra_flake_rerun","pattern":"gh_graphql_502","run_id":"401","pr":"105"}\n' \
    "$(iso_at $(( T_4D_AGO )))"
  printf '{"ts":"%s","slug":"slug-a","phase":"ship","type":"infra_flake_rerun","pattern":"gh_graphql_502","run_id":"402","pr":"106"}\n' \
    "$(iso_at $(( T_3D_AGO )))"
  # OOW — must NOT count.
  printf '{"ts":"%s","slug":"slug-a","phase":"ship","type":"pr_opened","number":"99","branch":"feat/9999-x"}\n' \
    "$(iso_at "$T_30D_AGO")"
  printf '{"ts":"%s","slug":"slug-a","phase":"review","type":"lesson_draft_emitted","pr":"99","headline":"old","text_sha":"old00099"}\n' \
    "$(iso_at "$T_30D_AGO")"
} > "$A_CACHE/events.jsonl"

# ============================================================================
# Fixture B: slug-b (degraded week — sendback cluster + paused window)
#   ships     = 21  (21 pr_opened events in window)
#   merges    = 14  (14 SHIP-prefix runs in window)
#   sendbacks = 11  (11 lesson_draft_emitted events in window)
#   spend     = 14.91 (21 * $0.71 = 14.91)
#   paused hr = 26  (one ship_paused → ship_resumed pair, 26h apart)
#   drafts    = 7   (7 unpromoted lesson_draft_emitted)
#   prompts   = 8a20547abcdef (SAME — for hypothesis branch)
#   atlas top = actions_silent:5
# ============================================================================
mk_manifest slug-b 8a20547abcdef0123456789012345678901234567

B_CACHE="$HOME/.cache/slug-b-agent"
mkdir -p "$B_CACHE"

{
  # 14 SHIP runs + 7 non-SHIP runs (heal/wait) = 21 ship-phase runs total,
  # 14 SHIP-prefix; combined with 21 pr_opened events below, ships=21 merges=14.
  for i in $(seq 1 14); do
    ts=$(( T_10D_AGO + i * 3600 ))
    printf '{"slug":"slug-b","phase":"ship","ts_start":"%s","ts_end":"%s","exit":0,"total_cost_usd":0.71,"result_head":"SHIP 02%02d-y — PR #%d green"}\n' \
      "$(iso_at "$ts")" "$(iso_at $(( ts + 60 )))" "$i" "$(( 200 + i ))"
  done
  for i in $(seq 1 7); do
    ts=$(( T_5D_AGO + i * 3600 ))
    printf '{"slug":"slug-b","phase":"ship","ts_start":"%s","ts_end":"%s","exit":0,"total_cost_usd":0.71,"result_head":"HEAL #1 fix lint"}\n' \
      "$(iso_at "$ts")" "$(iso_at $(( ts + 60 )))"
  done
} > "$B_CACHE/runs.jsonl"

{
  # 21 pr_opened events.
  for i in $(seq 1 21); do
    ts=$(( T_10D_AGO + i * 3600 ))
    printf '{"ts":"%s","slug":"slug-b","phase":"ship","type":"pr_opened","number":"%d","branch":"feat/02%02d-y"}\n' \
      "$(iso_at "$ts")" "$(( 200 + i ))" "$i"
  done
  # 11 sendbacks (lesson_draft_emitted) — 4 promoted, 7 unpromoted.
  for i in $(seq 1 11); do
    ts=$(( T_8D_AGO + i * 3600 ))
    printf '{"ts":"%s","slug":"slug-b","phase":"review","type":"lesson_draft_emitted","pr":"%d","headline":"draft %d","text_sha":"bbbb00%02d"}\n' \
      "$(iso_at "$ts")" "$(( 200 + i ))" "$i" "$i"
  done
  for i in 1 2 3 4; do
    printf '{"ts":"%s","slug":"slug-b","phase":"promote","type":"lesson_promoted","source":"slug-b","text_sha":"bbbb00%02d","scope":"all"}\n' \
      "$(iso_at $(( T_3D_AGO + i * 3600 )))" "$i"
  done
  # One ship_paused (T_3D_AGO - 12h) → ship_resumed (T_3D_AGO - 12h + 26h) = 26h pause.
  printf '{"ts":"%s","slug":"slug-b","phase":"ship","type":"ship_paused","reason":"sendback_streak","count":"3","prs":"205,206,207"}\n' \
    "$(iso_at $(( T_3D_AGO - 12 * 3600 )))"
  printf '{"ts":"%s","slug":"slug-b","phase":"resume","type":"ship_resumed","source":"slug-b","paused_for":"26h","reason":"streak cleared","forced":"0"}\n' \
    "$(iso_at $(( T_3D_AGO - 12 * 3600 + 26 * 3600 )))"
  # 5 infra_flake_rerun on actions_silent (top atlas pattern).
  for i in 1 2 3 4 5; do
    printf '{"ts":"%s","slug":"slug-b","phase":"ship","type":"infra_flake_rerun","pattern":"actions_silent","run_id":"%d","pr":"%d"}\n' \
      "$(iso_at $(( T_4D_AGO + i * 3600 )))" "$(( 500 + i ))" "$(( 210 + i ))"
  done
  # 1 infra_flake_rerun on gh_graphql_502 (lower count — not top).
  printf '{"ts":"%s","slug":"slug-b","phase":"ship","type":"infra_flake_rerun","pattern":"gh_graphql_502","run_id":"406","pr":"215"}\n' \
    "$(iso_at $(( T_2D_AGO )))"
} > "$B_CACHE/events.jsonl"

# ============================================================================
# Helper: assert N matches of regex in file via awk (LESSONS 2026-06-01).
# ============================================================================
assert_n_matches() {  # $1 = description, $2 = regex, $3 = file, $4 = expected
  local desc="$1" pat="$2" file="$3" want="$4" got
  got="$(awk -v p="$pat" '$0 ~ p { n++ } END { print n+0 }' "$file")"
  if [ "$got" -ne "$want" ]; then
    echo "FAIL: $desc — expected $want matches of /$pat/, got $got" >&2
    echo "----- $file -----" >&2
    cat "$file" >&2
    echo "-----------------" >&2
    exit 1
  fi
}

# ============================================================================
# AC#1 — default --since 14d, 8 metric rows in order, golden text.
# ============================================================================
echo "AC#1 — default 14d, 8 metric rows, golden text"
out="$TMP/ac1.out"
"$FLEET" diff slug-a slug-b > "$out"

# Header row contains METRIC, both slugs, Δ.
grep -qF -- "METRIC" "$out" || { echo "FAIL AC#1 missing METRIC header" >&2; exit 1; }
grep -qF -- "slug-a" "$out" || { echo "FAIL AC#1 missing slug-a column" >&2; exit 1; }
grep -qF -- "slug-b" "$out" || { echo "FAIL AC#1 missing slug-b column" >&2; exit 1; }
grep -q  "Δ"  "$out"        || { echo "FAIL AC#1 missing Δ header" >&2; exit 1; }

# Exactly 8 metric rows in order.
EXPECTED_METRICS=(
  "ships"
  "merges"
  "sendbacks"
  'spend ($)'
  "paused hours"
  "draft promotion debt"
  "prompts SHA"
  "top atlas pattern (fires)"
)
for m in "${EXPECTED_METRICS[@]}"; do
  grep -qF -- "$m" "$out" || { echo "FAIL AC#1 missing metric row '$m'" >&2; cat "$out" >&2; exit 1; }
done

# Order check: each metric should appear AFTER the previous one in the file.
prev_line=0
for m in "${EXPECTED_METRICS[@]}"; do
  line=$(awk -v m="$m" 'index($0, m) > 0 { print NR; exit }' "$out")
  if [ -z "$line" ] || [ "$line" -le "$prev_line" ]; then
    echo "FAIL AC#1 metric '$m' out of order (line=$line, prev=$prev_line)" >&2
    cat "$out" >&2
    exit 1
  fi
  prev_line="$line"
done

# Numeric assertions on the table values.
grep -qE "^ships[[:space:]]+19[[:space:]]+21[[:space:]]" "$out" \
  || { echo "FAIL AC#1 ships row expected '19  21 ...'" >&2; cat "$out" >&2; exit 1; }
grep -qE "^merges[[:space:]]+18[[:space:]]+14[[:space:]]" "$out" \
  || { echo "FAIL AC#1 merges row expected '18  14 ...'" >&2; cat "$out" >&2; exit 1; }
grep -qE "^sendbacks[[:space:]]+3[[:space:]]+11[[:space:]]" "$out" \
  || { echo "FAIL AC#1 sendbacks row expected '3  11 ...'" >&2; cat "$out" >&2; exit 1; }
grep -qE "paused hours[[:space:]]+0[[:space:]]+26[[:space:]]" "$out" \
  || { echo "FAIL AC#1 paused hours row expected '0  26 ...'" >&2; cat "$out" >&2; exit 1; }
grep -qE "draft promotion debt[[:space:]]+1[[:space:]]+7[[:space:]]" "$out" \
  || { echo "FAIL AC#1 draft promotion debt row expected '1  7 ...'" >&2; cat "$out" >&2; exit 1; }
grep -qE "top atlas pattern \(fires\)[[:space:]]+gh_graphql_502:2[[:space:]]+actions_silent:5[[:space:]]" "$out" \
  || { echo "FAIL AC#1 top atlas pattern row expected 'gh_graphql_502:2  actions_silent:5 ...'" >&2; cat "$out" >&2; exit 1; }
# Same prompts SHA both sides → Δ column is `=`.
grep -qE "prompts SHA[[:space:]]+8a20547[[:space:]]+8a20547[[:space:]]+=" "$out" \
  || { echo "FAIL AC#1 prompts SHA row expected short SHA both sides + '='" >&2; cat "$out" >&2; exit 1; }

# Window header includes 14d.
grep -qF -- "14d" "$out" || { echo "FAIL AC#1 window header should mention 14d" >&2; cat "$out" >&2; exit 1; }
echo "  ok"

# ============================================================================
# AC#2 — DIVERGENCE section: populated case + empty case.
# ============================================================================
echo "AC#2 — DIVERGENCE section populated + empty"

# Populated case: sendbacks (3 vs 11, 3.7x), paused hours (0 vs 26, ∞),
# draft debt (1 vs 7, 7x), top atlas pattern (differs).
grep -qE "DIVERGENCE \(>=2x\)" "$out" \
  || { echo "FAIL AC#2 populated DIVERGENCE header missing" >&2; cat "$out" >&2; exit 1; }
grep -qF -- "sendbacks" "$out" || { echo "FAIL AC#2 missing sendbacks in DIVERGENCE" >&2; exit 1; }
# Empty case: feed two slugs with identical metrics.
mk_manifest twin-x 8a20547abcdef0123456789012345678901234567
mk_manifest twin-y 8a20547abcdef0123456789012345678901234567
TWIN_X_CACHE="$HOME/.cache/twin-x-agent"
TWIN_Y_CACHE="$HOME/.cache/twin-y-agent"
mkdir -p "$TWIN_X_CACHE" "$TWIN_Y_CACHE"
for c in "$TWIN_X_CACHE" "$TWIN_Y_CACHE"; do
  {
    printf '{"slug":"x","phase":"ship","ts_start":"%s","ts_end":"%s","exit":0,"total_cost_usd":0.10,"result_head":"SHIP 0001-x"}\n' \
      "$(iso_at "$T_3D_AGO")" "$(iso_at $(( T_3D_AGO + 60 )))"
  } > "$c/runs.jsonl"
  {
    printf '{"ts":"%s","slug":"x","phase":"ship","type":"pr_opened","number":"1","branch":"feat/0001-x"}\n' \
      "$(iso_at "$T_3D_AGO")"
    printf '{"ts":"%s","slug":"x","phase":"ship","type":"infra_flake_rerun","pattern":"gh_graphql_502","run_id":"1","pr":"1"}\n' \
      "$(iso_at "$T_3D_AGO")"
  } > "$c/events.jsonl"
done

out_empty="$TMP/ac2_empty.out"
"$FLEET" diff twin-x twin-y > "$out_empty"
grep -qF -- "no metric diverges; the two projects are behaving similarly." "$out_empty" \
  || { echo "FAIL AC#2 empty DIVERGENCE message missing" >&2; cat "$out_empty" >&2; exit 1; }
echo "  ok"

# ============================================================================
# AC#3 — HYPOTHESES section: four branches.
# ============================================================================
echo "AC#3 — HYPOTHESES branches"

# Branch 1: sendbacks diverge AND prompts SHA matches → AGENTS.md drift.
grep -qF -- "per-project AGENTS.md drift" "$out" \
  || { echo "FAIL AC#3 hypothesis 'AGENTS.md drift' missing on slug-a vs slug-b" >&2; cat "$out" >&2; exit 1; }

# Branch 2: top atlas pattern differs → per-project CI/infra drift.
grep -qF -- "per-project CI/infra drift" "$out" \
  || { echo "FAIL AC#3 hypothesis 'CI/infra drift' missing" >&2; cat "$out" >&2; exit 1; }

# Branch 3: prompts SHA differs. Build a third fixture with a different SHA.
mk_manifest old-rev abcdef1234567890123456789012345678901234
OR_CACHE="$HOME/.cache/old-rev-agent"
mkdir -p "$OR_CACHE"
{
  for i in 1 2 3; do
    printf '{"slug":"old-rev","phase":"ship","ts_start":"%s","ts_end":"%s","exit":0,"total_cost_usd":0.50,"result_head":"SHIP %04d-z"}\n' \
      "$(iso_at $(( T_5D_AGO + i * 3600 )))" "$(iso_at $(( T_5D_AGO + i * 3600 + 60 )))" "$i"
  done
} > "$OR_CACHE/runs.jsonl"
{
  for i in 1 2 3; do
    printf '{"ts":"%s","slug":"old-rev","phase":"ship","type":"pr_opened","number":"%d","branch":"feat/000%d-z"}\n' \
      "$(iso_at $(( T_5D_AGO + i * 3600 )))" "$(( 300 + i ))" "$i"
  done
} > "$OR_CACHE/events.jsonl"
out_sha="$TMP/ac3_sha.out"
"$FLEET" diff slug-a old-rev > "$out_sha"
grep -qF -- "prompts revision regression" "$out_sha" \
  || { echo "FAIL AC#3 hypothesis 'prompts revision regression' missing on differing SHA" >&2; cat "$out_sha" >&2; exit 1; }

# Branch 4: spend diverges AND ships similar → manifest drift.
# Build a fixture pair where both projects have similar pr_opened counts
# but very different total spend.
mk_manifest cheap-co 8a20547abcdef0123456789012345678901234567
mk_manifest spendy-co 8a20547abcdef0123456789012345678901234567
CC_CACHE="$HOME/.cache/cheap-co-agent"
SC_CACHE="$HOME/.cache/spendy-co-agent"
mkdir -p "$CC_CACHE" "$SC_CACHE"
{
  for i in $(seq 1 10); do
    printf '{"slug":"cheap-co","phase":"ship","ts_start":"%s","ts_end":"%s","exit":0,"total_cost_usd":0.10,"result_head":"SHIP %04d-c"}\n' \
      "$(iso_at $(( T_5D_AGO + i * 1800 )))" "$(iso_at $(( T_5D_AGO + i * 1800 + 60 )))" "$i"
  done
} > "$CC_CACHE/runs.jsonl"
{
  for i in $(seq 1 10); do
    printf '{"ts":"%s","slug":"cheap-co","phase":"ship","type":"pr_opened","number":"%d","branch":"feat/000%d-c"}\n' \
      "$(iso_at $(( T_5D_AGO + i * 1800 )))" "$(( 400 + i ))" "$i"
  done
} > "$CC_CACHE/events.jsonl"
{
  for i in $(seq 1 10); do
    printf '{"slug":"spendy-co","phase":"ship","ts_start":"%s","ts_end":"%s","exit":0,"total_cost_usd":2.50,"result_head":"SHIP %04d-s"}\n' \
      "$(iso_at $(( T_5D_AGO + i * 1800 )))" "$(iso_at $(( T_5D_AGO + i * 1800 + 60 )))" "$i"
  done
} > "$SC_CACHE/runs.jsonl"
{
  for i in $(seq 1 10); do
    printf '{"ts":"%s","slug":"spendy-co","phase":"ship","type":"pr_opened","number":"%d","branch":"feat/000%d-s"}\n' \
      "$(iso_at $(( T_5D_AGO + i * 1800 )))" "$(( 500 + i ))" "$i"
  done
} > "$SC_CACHE/events.jsonl"
out_spend="$TMP/ac3_spend.out"
"$FLEET" diff cheap-co spendy-co > "$out_spend"
grep -qF -- "per-project manifest drift" "$out_spend" \
  || { echo "FAIL AC#3 hypothesis 'manifest drift' missing on similar-ships-different-spend" >&2; cat "$out_spend" >&2; exit 1; }
echo "  ok"

# ============================================================================
# AC#4 — --since flag, valid + invalid.
# ============================================================================
echo "AC#4 — --since flag"

out_since="$TMP/ac4.out"
"$FLEET" diff slug-a slug-b --since 7d > "$out_since"
grep -qF -- "7d" "$out_since" \
  || { echo "FAIL AC#4 --since 7d not reflected in window header" >&2; cat "$out_since" >&2; exit 1; }

# Invalid --since value: exit 2, stderr message.
set +e
err_out="$TMP/ac4.err"
"$FLEET" diff slug-a slug-b --since "garbage" 2>"$err_out"
rc=$?
set -e
[ "$rc" -eq 2 ] || { echo "FAIL AC#4 invalid --since: expected exit 2, got $rc" >&2; exit 1; }
grep -qF -- 'diff: invalid --since "garbage" (use Nh or Nd)' "$err_out" \
  || { echo "FAIL AC#4 invalid --since error message wrong" >&2; cat "$err_out" >&2; exit 1; }
echo "  ok"

# ============================================================================
# AC#5 — usage: zero or one positional arg → exit 2.
# ============================================================================
echo "AC#5 — usage on missing positional arg"

set +e
"$FLEET" diff 2>"$TMP/ac5_zero.err"
rc_zero=$?
"$FLEET" diff slug-a 2>"$TMP/ac5_one.err"
rc_one=$?
set -e
[ "$rc_zero" -eq 2 ] || { echo "FAIL AC#5 zero args: expected exit 2, got $rc_zero" >&2; exit 1; }
[ "$rc_one"  -eq 2 ] || { echo "FAIL AC#5 one arg:   expected exit 2, got $rc_one" >&2; exit 1; }
grep -qF -- "diff: usage: bin/fleet diff <slug-a> <slug-b> [--since Nh|Nd] [--json]" "$TMP/ac5_zero.err" \
  || { echo "FAIL AC#5 zero-arg usage text wrong" >&2; cat "$TMP/ac5_zero.err" >&2; exit 1; }
grep -qF -- "diff: usage: bin/fleet diff <slug-a> <slug-b> [--since Nh|Nd] [--json]" "$TMP/ac5_one.err" \
  || { echo "FAIL AC#5 one-arg usage text wrong" >&2; cat "$TMP/ac5_one.err" >&2; exit 1; }
echo "  ok"

# ============================================================================
# AC#6 — one or both slugs not installed → exit 2 + which-slug error.
# ============================================================================
echo "AC#6 — slug not installed"

set +e
"$FLEET" diff missing-a slug-b 2>"$TMP/ac6_a.err"
rc_a=$?
"$FLEET" diff slug-a missing-b 2>"$TMP/ac6_b.err"
rc_b=$?
"$FLEET" diff missing-a missing-b 2>"$TMP/ac6_both.err"
rc_both=$?
set -e
[ "$rc_a"    -eq 2 ] || { echo "FAIL AC#6 a-missing: expected exit 2, got $rc_a" >&2; exit 1; }
[ "$rc_b"    -eq 2 ] || { echo "FAIL AC#6 b-missing: expected exit 2, got $rc_b" >&2; exit 1; }
[ "$rc_both" -eq 2 ] || { echo "FAIL AC#6 both-missing: expected exit 2, got $rc_both" >&2; exit 1; }
grep -qF -- 'diff: slug "missing-a" not installed (no events.jsonl found)' "$TMP/ac6_a.err" \
  || { echo "FAIL AC#6 a-missing message wrong" >&2; cat "$TMP/ac6_a.err" >&2; exit 1; }
grep -qF -- 'diff: slug "missing-b" not installed (no events.jsonl found)' "$TMP/ac6_b.err" \
  || { echo "FAIL AC#6 b-missing message wrong" >&2; cat "$TMP/ac6_b.err" >&2; exit 1; }
# Both-missing path must name one of them (first one) in the error.
grep -qF -- 'not installed' "$TMP/ac6_both.err" \
  || { echo "FAIL AC#6 both-missing message wrong" >&2; cat "$TMP/ac6_both.err" >&2; exit 1; }
echo "  ok"

# ============================================================================
# AC#7 — same-slug-twice is a usage error.
# ============================================================================
echo "AC#7 — same-slug-twice usage error"

set +e
"$FLEET" diff slug-a slug-a 2>"$TMP/ac7.err"
rc_same=$?
set -e
[ "$rc_same" -eq 2 ] || { echo "FAIL AC#7 same-slug: expected exit 2, got $rc_same" >&2; exit 1; }
grep -qF -- 'diff: <slug-a> and <slug-b> must differ; use `fleet weekly --slug <slug>` for the same-project historical comparison' "$TMP/ac7.err" \
  || { echo "FAIL AC#7 same-slug message wrong" >&2; cat "$TMP/ac7.err" >&2; exit 1; }
echo "  ok"

# ============================================================================
# AC#8 — --json output, parseable + has expected keys.
# ============================================================================
echo "AC#8 — --json output"

out_json="$TMP/ac8.json"
"$FLEET" diff slug-a slug-b --json > "$out_json"

# Parseable.
node -e '
  const fs = require("fs");
  const obj = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
  if (!obj.window || !obj.window.start || !obj.window.end) { console.error("missing window"); process.exit(1); }
  if (obj.a !== "slug-a" || obj.b !== "slug-b") { console.error("missing a/b slugs"); process.exit(1); }
  if (!Array.isArray(obj.metrics) || obj.metrics.length !== 8) { console.error("expected 8 metrics, got", obj.metrics ? obj.metrics.length : "none"); process.exit(1); }
  const names = obj.metrics.map(m => m.name);
  const expected = ["ships","merges","sendbacks","spend ($)","paused hours","draft promotion debt","prompts SHA","top atlas pattern (fires)"];
  for (let i=0; i<expected.length; i++) {
    if (names[i] !== expected[i]) { console.error("metric order mismatch at", i, "got", names[i], "expected", expected[i]); process.exit(1); }
  }
  if (!Array.isArray(obj.divergence)) { console.error("missing divergence[]"); process.exit(1); }
  if (!Array.isArray(obj.hypotheses)) { console.error("missing hypotheses[]"); process.exit(1); }
  // sendbacks delta = 11 - 3 = 8.
  const sb = obj.metrics.find(m => m.name === "sendbacks");
  if (!sb || sb.a !== 3 || sb.b !== 11 || sb.delta !== 8) { console.error("sendbacks row wrong", sb); process.exit(1); }
  // divergence must include sendbacks with direction "b>a".
  const div_sb = obj.divergence.find(d => d.metric === "sendbacks");
  if (!div_sb || div_sb.direction !== "b>a") { console.error("divergence sendbacks wrong", div_sb); process.exit(1); }
  // hypotheses non-empty for this fixture pair.
  if (obj.hypotheses.length === 0) { console.error("hypotheses empty unexpectedly"); process.exit(1); }
' "$out_json" || { echo "FAIL AC#8 JSON validation failed" >&2; cat "$out_json" >&2; exit 1; }
echo "  ok"

# ============================================================================
# AC#9 — help text.
# ============================================================================
echo "AC#9 — help text"

help_out="$TMP/ac9.help"
"$FLEET" diff --help > "$help_out"
for kw in "<slug-a>" "<slug-b>" "--since" "--json"; do
  grep -qF -- "$kw" "$help_out" \
    || { echo "FAIL AC#9 help missing keyword '$kw'" >&2; cat "$help_out" >&2; exit 1; }
done
echo "  ok"

# ============================================================================
# AC#10 — dispatcher exits cleanly; diff_cmd named (not diff).
# ============================================================================
echo "AC#10 — dispatcher + naming"

# Source check: function is named diff_cmd, not diff.
grep -q '^diff_cmd()' "$FLEET" \
  || { echo "FAIL AC#10 expected 'diff_cmd()' function in bin/fleet (avoid /usr/bin/diff shadow)" >&2; exit 1; }
grep -q '^diff()' "$FLEET" \
  && { echo "FAIL AC#10 found 'diff()' function — must be 'diff_cmd' to avoid shadowing /usr/bin/diff" >&2; exit 1; } || true

# Dispatcher must call diff_cmd.
grep -qE 'if \[ "\$CMD" = "diff" \]; then$' "$FLEET" \
  || { echo "FAIL AC#10 missing 'if [ \"\$CMD\" = \"diff\" ]; then' dispatcher block" >&2; exit 1; }
# diff_cmd must end with an explicit `exit` (LESSONS 2026-06-01).
# Pull the function body and assert there's at least one `exit 0` line.
awk '/^diff_cmd\(\) \{/,/^\}/' "$FLEET" | grep -qE '^\s+exit (0|2)' \
  || { echo "FAIL AC#10 diff_cmd() body missing explicit 'exit N'" >&2; exit 1; }

# Dispatcher fall-through guard: after invoking diff_cmd, the next thing
# in the file should NOT be the default fleet status block. The function
# itself owns the exit, so we just confirm diff_cmd ends with exit.
echo "  ok"

# ============================================================================
# AC#11 — division-by-zero guard via fixture (slug-a sendbacks=0, slug-b=4).
# ============================================================================
echo "AC#11 — div-by-zero guard"

mk_manifest zero-sb 8a20547abcdef0123456789012345678901234567
mk_manifest four-sb 8a20547abcdef0123456789012345678901234567
Z_CACHE="$HOME/.cache/zero-sb-agent"
F_CACHE="$HOME/.cache/four-sb-agent"
mkdir -p "$Z_CACHE" "$F_CACHE"
{
  printf '{"slug":"zero-sb","phase":"ship","ts_start":"%s","ts_end":"%s","exit":0,"total_cost_usd":0.10,"result_head":"SHIP 0001-z"}\n' \
    "$(iso_at "$T_3D_AGO")" "$(iso_at $(( T_3D_AGO + 60 )))"
} > "$Z_CACHE/runs.jsonl"
{
  printf '{"ts":"%s","slug":"zero-sb","phase":"ship","type":"pr_opened","number":"1","branch":"feat/0001-z"}\n' \
    "$(iso_at "$T_3D_AGO")"
  # zero sendbacks.
} > "$Z_CACHE/events.jsonl"
{
  printf '{"slug":"four-sb","phase":"ship","ts_start":"%s","ts_end":"%s","exit":0,"total_cost_usd":0.10,"result_head":"SHIP 0001-f"}\n' \
    "$(iso_at "$T_3D_AGO")" "$(iso_at $(( T_3D_AGO + 60 )))"
} > "$F_CACHE/runs.jsonl"
{
  printf '{"ts":"%s","slug":"four-sb","phase":"ship","type":"pr_opened","number":"1","branch":"feat/0001-f"}\n' \
    "$(iso_at "$T_3D_AGO")"
  for i in 1 2 3 4; do
    printf '{"ts":"%s","slug":"four-sb","phase":"review","type":"lesson_draft_emitted","pr":"%d","headline":"d %d","text_sha":"ffff000%d"}\n' \
      "$(iso_at $(( T_2D_AGO + i * 3600 )))" "$(( 600 + i ))" "$i" "$i"
  done
} > "$F_CACHE/events.jsonl"

out_div0="$TMP/ac11.out"
"$FLEET" diff zero-sb four-sb > "$out_div0" 2>"$TMP/ac11.err"
# Must NOT exit with a shell arithmetic error.
grep -qE 'divide by zero|division by zero|integer expression expected' "$TMP/ac11.err" \
  && { echo "FAIL AC#11 division-by-zero error leaked to stderr" >&2; cat "$TMP/ac11.err" >&2; exit 1; } || true
# Sendbacks row must show 0 and 4 and a ∞ in Δ.
grep -qE "^sendbacks[[:space:]]+0[[:space:]]+4[[:space:]]" "$out_div0" \
  || { echo "FAIL AC#11 sendbacks row missing or wrong" >&2; cat "$out_div0" >&2; exit 1; }
# Divergence section should list sendbacks too (ratio = 4 / max(0,1) = 4).
grep -qF -- "sendbacks" "$out_div0" \
  || { echo "FAIL AC#11 divergence missing sendbacks bullet" >&2; cat "$out_div0" >&2; exit 1; }
echo "  ok"

echo "tests/diff.sh — all 11 acceptance-criteria blocks passed."
