#!/bin/bash
# tests/ticket-cost.sh — `bin/fleet ticket-cost <id>` per-ticket cost
# attribution test.
#
# Ticket 0047. One assertion block per acceptance-criteria checkbox in
# docs/backlog/0047-fleet-ticket-cost-per-id-attribution.md.
#
# Per LESSONS 2026-05-26 stubs live under $HOME/.local/bin (lib/common.sh
# resets PATH — but bin/fleet does NOT source common.sh, so we only need
# the dir for HOME isolation). Per LESSONS 2026-05-27 every fixture is
# copied with `cp` (never `$(cat …)`). Per LESSONS 2026-06-01 every count
# uses `awk … END { print n+0 }`. Per LESSONS 2026-06-08 awk accumulator
# arrays declare `BEGIN { count = 0 }`. Per LESSONS 2026-06-08
# `IFS=$'\t' read` uses a sentinel for empty middle fields. Per LESSONS
# 2026-05-30 help-text greps use `grep -qF -- "$kw"`.

set -euo pipefail

REPO_ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
FLEET="$REPO_ROOT/bin/fleet"
FIXTURE_DIR="$REPO_ROOT/tests/fixtures/ticket-cost"

TMP="$(mktemp -d -t fleet-ticket-cost-test.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

# Isolate HOME so $HOME/.cache, $HOME/.local/bin stay sandboxed.
export HOME="$TMP/home"
mkdir -p "$HOME/.local/bin"

# Anchor "today" at 2026-06-11T12:00:00Z. The default window is 30 days.
NOW_EPOCH=1781179200
export FLEET_NOW_OVERRIDE="$NOW_EPOCH"

# Seed manifests under a fixture root and point discovery at it.
FIXTURE_ROOT="$TMP/projects"
mkdir -p "$FIXTURE_ROOT"
export FLEET_DISCOVERY_ROOT="$FIXTURE_ROOT"

mk_manifest() {  # $1 = slug
  local slug="$1"
  mkdir -p "$FIXTURE_ROOT/$slug"
  cat > "$FIXTURE_ROOT/$slug/agents.config.sh" <<CFG
PROJECT_NAME="$slug"
SLUG="$slug"
NAMESPACE="com.$slug"
REPO_URL="https://github.com/example/$slug"
SELF_CANCEL="20990101"
CFG
}

# Copy the per-slug fixture jsonl files into $HOME/.cache/<slug>-agent.
# Per LESSONS 2026-05-27 we use `cp` (not `$(cat)`) so trailing newlines
# survive.
install_slug_fixture() {  # $1 = slug, $2 = fixture name (subdir)
  local slug="$1" fixture="$2"
  local cache="$HOME/.cache/${slug}-agent"
  mkdir -p "$cache"
  if [ -f "$FIXTURE_DIR/$fixture/runs.jsonl" ]; then
    cp "$FIXTURE_DIR/$fixture/runs.jsonl" "$cache/runs.jsonl"
  else
    : > "$cache/runs.jsonl"
  fi
  if [ -f "$FIXTURE_DIR/$fixture/events.jsonl" ]; then
    cp "$FIXTURE_DIR/$fixture/events.jsonl" "$cache/events.jsonl"
  else
    : > "$cache/events.jsonl"
  fi
}

# Three manifests: agent-fleet (rich), almanac (one ticket sharing id with
# agent-fleet for the disambiguation branch), digitalcraft (empty for the
# negative branch).
mk_manifest agent-fleet
mk_manifest almanac
mk_manifest digitalcraft

install_slug_fixture agent-fleet  agent-fleet
install_slug_fixture almanac      almanac
install_slug_fixture digitalcraft digitalcraft

# Prepend the stub dir to PATH for the test process.
export PATH="$HOME/.local/bin:$PATH"

# ========================================================================
# AC #1 — `bin/fleet ticket-cost <id>` is a new subcommand. Missing id
#          prints USAGE to stderr and exits 2.
# ========================================================================
set +e
"$FLEET" ticket-cost 2>"$TMP/missing.err.txt" >/dev/null
EXIT=$?
set -e
if [ "$EXIT" != "2" ]; then
  echo "FAIL: AC#1 missing id should exit 2, got $EXIT"; cat "$TMP/missing.err.txt"; exit 1
fi
if ! grep -qF -- 'ticket-cost: usage:' "$TMP/missing.err.txt"; then
  echo "FAIL: AC#1 missing id should print 'ticket-cost: usage:' line"
  cat "$TMP/missing.err.txt"; exit 1
fi
# Normalization: 0042, 42, #0042 are all equivalent.
OUT_42="$("$FLEET" ticket-cost 42  --slug agent-fleet 2>/dev/null)"
OUT_0042="$("$FLEET" ticket-cost 0042 --slug agent-fleet 2>/dev/null)"
OUT_HASH="$("$FLEET" ticket-cost '#0042' --slug agent-fleet 2>/dev/null)"
if [ "$OUT_42" != "$OUT_0042" ] || [ "$OUT_42" != "$OUT_HASH" ]; then
  echo "FAIL: AC#1 normalization of '42' / '0042' / '#0042' should yield identical output"
  echo "--- 42 ---"; printf '%s\n' "$OUT_42"
  echo "--- 0042 ---"; printf '%s\n' "$OUT_0042"
  echo "--- #0042 ---"; printf '%s\n' "$OUT_HASH"
  exit 1
fi
echo "ok: AC#1 missing-id exit 2 + id normalization"

# ========================================================================
# AC #2 — Default discovery walks all slugs. --slug restricts to one.
#          When --slug is omitted AND id matches multiple slugs, print a
#          disambiguation table.
# ========================================================================
# Default (no --slug). agent-fleet has 0042 (5 runs), almanac also has
# 0042 (1 cheap run). The command should print a disambiguation table.
OUT_DISAMBIG="$("$FLEET" ticket-cost 0042 2>/dev/null)"
if ! printf '%s\n' "$OUT_DISAMBIG" | grep -qF -- "ticket-cost: ticket 0042 appears in"; then
  echo "FAIL: AC#2 multi-slug should print disambiguation"
  printf '%s\n' "$OUT_DISAMBIG"; exit 1
fi
if ! printf '%s\n' "$OUT_DISAMBIG" | grep -qF 'agent-fleet'; then
  echo "FAIL: AC#2 disambiguation missing agent-fleet"; exit 1
fi
if ! printf '%s\n' "$OUT_DISAMBIG" | grep -qF 'almanac'; then
  echo "FAIL: AC#2 disambiguation missing almanac"; exit 1
fi
echo "ok: AC#2 default discovery + disambiguation"

# ========================================================================
# AC #3 — Attribution filter:
#          (a) result_head substring contains the id, OR
#          (b) row's pr cited matches a `pr_opened` event whose branch
#              starts with feat|chore/gtm-|eng|revert / <id>-
# ========================================================================
# Ticket 0044 in agent-fleet is attributable ONLY by branch correlation —
# its single run's result_head contains NO "0044" substring; instead, the
# events.jsonl carries a pr_opened with branch=feat/0044-...
OUT_44="$("$FLEET" ticket-cost 0044 --slug agent-fleet 2>/dev/null)"
if ! printf '%s\n' "$OUT_44" | grep -qE 'ticket-cost: \$0\.40 across 1 runs'; then
  echo "FAIL: AC#3 branch-correlated row should be picked up"
  printf '%s\n' "$OUT_44"; exit 1
fi
# Ticket 0040 in agent-fleet is attributable ONLY by result_head substring
# (no pr_opened event for it). Should still surface.
OUT_40="$("$FLEET" ticket-cost 0040 --slug agent-fleet 2>/dev/null)"
if ! printf '%s\n' "$OUT_40" | grep -qE 'ticket-cost: \$0\.20 across 1 runs'; then
  echo "FAIL: AC#3 result_head substring row should be picked up"
  printf '%s\n' "$OUT_40"; exit 1
fi
echo "ok: AC#3 substring + pr-correlation filter"

# ========================================================================
# AC #4 — Render: one row per attributable run + summary line with
#          breakdown counting phases.
# ========================================================================
OUT_42_FULL="$("$FLEET" ticket-cost 0042 --slug agent-fleet 2>/dev/null)"
# Row count for 0042 in agent-fleet is 5 (3 ship + 1 ship merge + 1 review).
N_ROWS=$(printf '%s\n' "$OUT_42_FULL" | awk '/^ +20[0-9][0-9]-/ { n++ } END { print n+0 }')
if [ "$N_ROWS" != "5" ]; then
  echo "FAIL: AC#4 expected 5 attributable rows for 0042, got $N_ROWS"
  printf '%s\n' "$OUT_42_FULL"; exit 1
fi
# Summary line shape.
if ! printf '%s\n' "$OUT_42_FULL" | grep -qE 'ticket-cost: \$1\.83 across 5 runs'; then
  echo "FAIL: AC#4 expected summary 'ticket-cost: \$1.83 across 5 runs'"
  printf '%s\n' "$OUT_42_FULL"; exit 1
fi
# Breakdown counts at least one ship + one review.
if ! printf '%s\n' "$OUT_42_FULL" | grep -qE 'ship.* review'; then
  echo "FAIL: AC#4 breakdown should mention ship and review"
  printf '%s\n' "$OUT_42_FULL"; exit 1
fi
echo "ok: AC#4 render + summary + breakdown"

# ========================================================================
# AC #5 — median ticket cost across all attributable tickets in the slug
#          over the window; ratio = this_ticket_sum / median to 1 decimal.
# ========================================================================
# In agent-fleet over 30d the per-ticket sums are:
#   0040 = 0.20, 0041 = 0.50, 0043 = 0.60, 0044 = 0.40, 0042 = 1.83.
# Sorted: 0.20, 0.40, 0.50, 0.60, 1.83 → median = 0.50.
# Ratio for 0042 = 1.83 / 0.50 = 3.7 (1 decimal).
if ! printf '%s\n' "$OUT_42_FULL" | grep -qE 'median ticket cost in agent-fleet: \$0\.50'; then
  echo "FAIL: AC#5 expected 'median ticket cost in agent-fleet: \$0.50'"
  printf '%s\n' "$OUT_42_FULL"; exit 1
fi
if ! printf '%s\n' "$OUT_42_FULL" | grep -qE 'ratio: 3\.7x'; then
  echo "FAIL: AC#5 expected 'ratio: 3.7x'"
  printf '%s\n' "$OUT_42_FULL"; exit 1
fi
echo "ok: AC#5 median + ratio"

# ========================================================================
# AC #6 — Ratio > 2.0x AND heal-driven: suggest `fleet prompts-suggest`.
#          For a single-run high ratio: suggest `fleet provenance`.
# ========================================================================
# 0042 is heal-driven (>=25% heal) and ratio 3.7x → suggest prompts-suggest.
if ! printf '%s\n' "$OUT_42_FULL" | grep -qF 'fleet prompts-suggest'; then
  echo "FAIL: AC#6 heal-driven outlier should suggest 'fleet prompts-suggest'"
  printf '%s\n' "$OUT_42_FULL"; exit 1
fi
# Ticket 0043 is single-run, ratio 1.2x (0.60 / 0.50) — below threshold.
# Use a synthetic single-run high-cost ticket in fixture: ticket 0099 in
# almanac (1 run, $2.00, no heals; median in almanac is the only sum =
# 2.00 itself, so ratio = 1.0). Add a second cheap ticket so the median
# becomes meaningful and the ratio crosses 2.0x.
# (Handled by the almanac fixture — see below.)
OUT_99="$("$FLEET" ticket-cost 0099 --slug almanac 2>/dev/null)"
if ! printf '%s\n' "$OUT_99" | grep -qF 'fleet provenance'; then
  echo "FAIL: AC#6 single-run outlier should suggest 'fleet provenance'"
  printf '%s\n' "$OUT_99"; exit 1
fi
echo "ok: AC#6 outlier follow-up suggestions"

# ========================================================================
# AC #7 — HEAL breakdown: rows whose result_head starts with HEAL are
#          counted as heals; summary reports the percentage when >= 25%.
# ========================================================================
# 0042 has 2 of 5 cost-bearing rows as heals — heal_cost = 0.30 + 0.20 =
# 0.50, total = 1.83 → 0.50/1.83 = 27.3% (>= 25%, line should appear).
if ! printf '%s\n' "$OUT_42_FULL" | grep -qE 'heals account for [0-9]+% of cost'; then
  echo "FAIL: AC#7 expected 'heals account for N% of cost' line"
  printf '%s\n' "$OUT_42_FULL"; exit 1
fi
# 0040 has 0 heals — line should NOT appear.
if printf '%s\n' "$OUT_40" | grep -qF 'heals account for'; then
  echo "FAIL: AC#7 zero-heal ticket should NOT print heal line"
  printf '%s\n' "$OUT_40"; exit 1
fi
echo "ok: AC#7 heal-share line"

# ========================================================================
# AC #8 — --json emits one JSON object per attributable run plus one
#          summary object. Validate via Node.
# ========================================================================
"$FLEET" ticket-cost 0042 --slug agent-fleet --json > "$TMP/0042.json"
node -e '
  const fs = require("fs");
  const lines = fs.readFileSync(process.argv[1], "utf8").trim().split("\n");
  if (lines.length !== 6) { console.error("FAIL JSON line count=" + lines.length); process.exit(1); }
  const row_keys = ["slug","ts","phase","cost","duration_ms","result_head","is_heal"];
  const sum_keys = ["summary"];
  let summary_seen = false;
  for (const ln of lines) {
    const o = JSON.parse(ln);
    if (o.summary) {
      summary_seen = true;
      const s = o.summary;
      const expected_sum = ["ticket","slug","total_cost","run_count","heal_count","median_30d","ratio"];
      for (const k of expected_sum) {
        if (!(k in s)) { console.error("FAIL summary missing key " + k); process.exit(1); }
      }
      if (s.ticket !== "0042") { console.error("FAIL summary.ticket=" + s.ticket); process.exit(1); }
      if (s.slug !== "agent-fleet") { console.error("FAIL summary.slug=" + s.slug); process.exit(1); }
      if (Math.abs(s.total_cost - 1.83) > 0.005) { console.error("FAIL summary.total_cost=" + s.total_cost); process.exit(1); }
      if (s.run_count !== 5) { console.error("FAIL summary.run_count=" + s.run_count); process.exit(1); }
      if (s.heal_count !== 2) { console.error("FAIL summary.heal_count=" + s.heal_count); process.exit(1); }
      if (Math.abs(s.median_30d - 0.50) > 0.005) { console.error("FAIL summary.median_30d=" + s.median_30d); process.exit(1); }
    } else {
      for (const k of row_keys) {
        if (!(k in o)) { console.error("FAIL row missing key " + k + " in " + ln); process.exit(1); }
      }
    }
  }
  if (!summary_seen) { console.error("FAIL summary not emitted"); process.exit(1); }
  console.log("ok json validate");
' "$TMP/0042.json" > "$TMP/json.log"
echo "ok: AC#8 --json schema"

# ========================================================================
# AC #9 — --since <Nd|YYYY-MM-DD> overrides window. Restricts attribution
#          scan AND median window.
# ========================================================================
# 0042's runs are spread over the last 25 days. With --since 7d only the
# last 2 rows fall in window (the 2 most recent: review + last heal). The
# sum should drop accordingly.
OUT_SINCE_7D="$("$FLEET" ticket-cost 0042 --slug agent-fleet --since 7d 2>/dev/null)"
N_7D=$(printf '%s\n' "$OUT_SINCE_7D" | awk '/^ +20[0-9][0-9]-/ { n++ } END { print n+0 }')
if [ "$N_7D" -ge 5 ]; then
  echo "FAIL: AC#9 --since 7d should drop OOW rows (expected < 5, got $N_7D)"
  printf '%s\n' "$OUT_SINCE_7D"; exit 1
fi
# YYYY-MM-DD form.
OUT_SINCE_DATE="$("$FLEET" ticket-cost 0042 --slug agent-fleet --since 2026-05-12 2>/dev/null)"
N_DATE=$(printf '%s\n' "$OUT_SINCE_DATE" | awk '/^ +20[0-9][0-9]-/ { n++ } END { print n+0 }')
if [ "$N_DATE" -lt 5 ]; then
  echo "FAIL: AC#9 --since 2026-05-12 should include all 5 rows, got $N_DATE"
  printf '%s\n' "$OUT_SINCE_DATE"; exit 1
fi
echo "ok: AC#9 --since Nd + YYYY-MM-DD"

# ========================================================================
# AC #10 — --help prints USAGE mentioning the id arg, --slug, --since,
#           --json. Help block exits 0.
# ========================================================================
HELP_OUT="$TMP/help.txt"
set +e
"$FLEET" ticket-cost --help > "$HELP_OUT"
HELP_EXIT=$?
set -e
if [ "$HELP_EXIT" != "0" ]; then
  echo "FAIL: AC#10 --help should exit 0, got $HELP_EXIT"; cat "$HELP_OUT"; exit 1
fi
for kw in 'fleet ticket-cost' '<id>' '--slug' '--since' '--json'; do
  if ! grep -qF -- "$kw" "$HELP_OUT"; then
    echo "FAIL: AC#10 help missing '$kw'"; cat "$HELP_OUT"; exit 1
  fi
done
echo "ok: AC#10 help text"

# ========================================================================
# AC #11 — Empty case: ticket id with zero attributable runs prints a
#           friendly explanatory line and exits 0.
# ========================================================================
set +e
"$FLEET" ticket-cost 9999 --slug agent-fleet > "$TMP/empty.txt"
EMPTY_EXIT=$?
set -e
if [ "$EMPTY_EXIT" != "0" ]; then
  echo "FAIL: AC#11 empty case should exit 0, got $EMPTY_EXIT"; cat "$TMP/empty.txt"; exit 1
fi
if ! grep -qF -- 'ticket 9999 has no attributable runs' "$TMP/empty.txt"; then
  echo "FAIL: AC#11 empty case missing explanatory line"
  cat "$TMP/empty.txt"; exit 1
fi
echo "ok: AC#11 empty case"

# ========================================================================
# AC #12 — `bin/fleet ticket-cost` is a PURE READER. NO events.jsonl
#           writes. Test asserts unchanged byte size before + after.
# ========================================================================
EV_BEFORE=$(stat -f %z "$HOME/.cache/agent-fleet-agent/events.jsonl" 2>/dev/null \
  || stat -c %s "$HOME/.cache/agent-fleet-agent/events.jsonl")
"$FLEET" ticket-cost 0042 --slug agent-fleet > /dev/null
EV_AFTER=$(stat -f %z "$HOME/.cache/agent-fleet-agent/events.jsonl" 2>/dev/null \
  || stat -c %s "$HOME/.cache/agent-fleet-agent/events.jsonl")
if [ "$EV_BEFORE" != "$EV_AFTER" ]; then
  echo "FAIL: AC#12 events.jsonl mutated by ticket-cost (before=$EV_BEFORE after=$EV_AFTER)"
  exit 1
fi
# Also verify the function source contains no fleet_emit_event invocation.
TC_FN_BODY="$(awk '/^ticket_cost\(\) \{/,/^\}/' "$REPO_ROOT/bin/fleet")"
if echo "$TC_FN_BODY" | grep -q 'fleet_emit_event'; then
  echo "FAIL: AC#12 ticket_cost() must not call fleet_emit_event"
  exit 1
fi
echo "ok: AC#12 pure reader (no events writes)"

# ========================================================================
# AC #13 — `lib/common.sh` unchanged on this branch.
# ========================================================================
DIFF_LIB="$(cd "$REPO_ROOT" && git diff --name-only main...HEAD -- lib/common.sh)"
if [ -n "$DIFF_LIB" ]; then
  echo "FAIL: AC#13 lib/common.sh changed on this branch: $DIFF_LIB"
  exit 1
fi
echo "ok: AC#13 lib/common.sh untouched"

# ========================================================================
# AC #14 — `prompts/` and `AGENTS.md` untouched on this branch.
# ========================================================================
DIFF_PROMPTS="$(cd "$REPO_ROOT" && git diff --name-only main...HEAD -- prompts/)"
if [ -n "$DIFF_PROMPTS" ]; then
  echo "FAIL: AC#14 prompts/ changed on this branch:"; printf '%s\n' "$DIFF_PROMPTS"; exit 1
fi
DIFF_AGENTS="$(cd "$REPO_ROOT" && git diff --name-only main...HEAD -- AGENTS.md)"
if [ -n "$DIFF_AGENTS" ]; then
  echo "FAIL: AC#14 AGENTS.md changed on this branch: $DIFF_AGENTS"
  exit 1
fi
echo "ok: AC#14 prompts/ and AGENTS.md untouched"

echo "ok: tests/ticket-cost.sh passed"
