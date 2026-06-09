#!/bin/bash
# tests/self-check.sh — bin/fleet self-check end-to-end.
#
# Ticket 0040. One assertion block per acceptance-criteria checkbox in
# docs/backlog/0040-fleet-self-check-static-lessons-lint.md:
#
#   AC#1  bin/fleet self-check exists, scans the kit source, prints the
#         table, exit 0 on no hits / exit 1 on any hit (fixture kit tree).
#   AC#2  --json prints one JSON object per hit (NDJSON), empty on clean.
#   AC#3  --pattern <name> restricts to one pattern; unknown name → exit 2.
#   AC#4  --list prints the catalog (12 rows) with LESSONS dates.
#   AC#5  Approximate patterns render with `≈` suffix; --json carries
#         "approximate": true.
#   AC#6  --help block mentions --list, --pattern, --json; exit 0.
#   AC#7  FLEET_SELF_CHECK_GATE=1 emits one self_check_failed event per
#         hit; unset env emits NO event.
#   AC#8  AGENTS.md § Telemetry documents the self_check_failed event.
#   AC#9  AGENTS.md § Agent parameters Local gate command is widened with
#         FLEET_SELF_CHECK_GATE=1 bin/fleet self-check.
#   AC#10 Catalog is exactly 12 patterns and every catalog entry has both
#         a positive and a negative fixture under tests/fixtures/self-check/.
#   AC#11 lib/common.sh diff vs main is empty.
#   AC#12 prompts/ diff vs main is empty.
#   AC#13 Performance budget <2s for a full scan against the kit's
#         current source.
#
# Per LESSONS 2026-05-26: stubs live in $HOME/.local/bin (common.sh's
# hardcoded PATH wipes a $TMP/bin). Per LESSONS 2026-05-27: `cp` for
# fixture backup/restore — never `$(cat …)`. Per LESSONS 2026-06-01:
# counts use awk END { print n+0 }, never `grep -c … || echo 0`.

set -uo pipefail

REPO_ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
FLEET="$REPO_ROOT/bin/fleet"
FIXTURES="$REPO_ROOT/tests/fixtures/self-check"

TMP="$(mktemp -d -t fleet-self-check-test.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

# Isolate from the host — HOME shapes the default events.jsonl path
# (~/.cache/agent-fleet-agent/events.jsonl) and the stub PATH entry.
export HOME="$TMP/home"
mkdir -p "$HOME" "$HOME/.local/bin"
# bin/fleet's dispatcher does NOT source lib/common.sh, so the test
# must prepend the stub dir itself. The subshell that emits
# self_check_failed DOES source common.sh and is unaffected.
export PATH="$HOME/.local/bin:$PATH"

# Force fleet_emit_event into the kit-as-project cache so AC#7 can
# read it.
KIT_CACHE="$HOME/.cache/agent-fleet-agent"
mkdir -p "$KIT_CACHE"
EVENTS="$KIT_CACHE/events.jsonl"
: > "$EVENTS"

# ---------------------------------------------------------------------------
# Build a fake kit-source tree. self-check scans the directory the dispatcher
# resolves from $0 (bin/fleet -> ..). The tests for AC#1/2/5 point
# FLEET_SELF_CHECK_ROOT at a synthetic tree so the assertions are stable
# regardless of the live kit's current hit-count.
# ---------------------------------------------------------------------------
mk_clean_tree() {
  local root="$1"
  rm -rf "$root"
  mkdir -p "$root/bin" "$root/lib" "$root/scripts"
  # bin/fleet — a minimal file with NO catalog hits.
  cat > "$root/bin/fleet" <<'CLEAN'
#!/bin/bash
set -euo pipefail
echo "fleet: clean stub"
exit 0
CLEAN
  # lib/common.sh — minimal, no hits.
  cat > "$root/lib/common.sh" <<'CLEAN'
#!/bin/bash
# minimal common
CLEAN
  # scripts/check-backlog.mjs — minimal, no hits.
  cat > "$root/scripts/check-backlog.mjs" <<'CLEAN'
// minimal validator
process.exit(0)
CLEAN
}

mk_dirty_tree() {
  local root="$1"
  rm -rf "$root"
  mkdir -p "$root/bin" "$root/lib" "$root/scripts"
  # Drop the printf-leading-dash positive fixture into bin/fleet so the
  # scan finds at least one hit.
  cp "$FIXTURES/printf-leading-dash.bad.sh" "$root/bin/fleet"
  cat > "$root/lib/common.sh" <<'CLEAN'
#!/bin/bash
# minimal common
CLEAN
  cat > "$root/scripts/check-backlog.mjs" <<'CLEAN'
// minimal validator
process.exit(0)
CLEAN
}

# ---------------------------------------------------------------------------
# AC#1 — self-check exists, scans, prints table, exit 0 clean / exit 1 hits.
# ---------------------------------------------------------------------------
CLEAN_TREE="$TMP/clean-kit"
DIRTY_TREE="$TMP/dirty-kit"
mk_clean_tree "$CLEAN_TREE"
mk_dirty_tree "$DIRTY_TREE"

FLEET_SELF_CHECK_ROOT="$CLEAN_TREE" "$FLEET" self-check > "$TMP/ac1-clean.out" 2> "$TMP/ac1-clean.err"
RC=$?
if [ "$RC" != "0" ]; then
  echo "FAIL: AC#1 — clean tree should exit 0, got $RC"
  cat "$TMP/ac1-clean.err"
  exit 1
fi
if ! grep -qE -- "^TRAP " "$TMP/ac1-clean.out"; then
  echo "FAIL: AC#1 — clean tree output missing TRAP header"
  cat "$TMP/ac1-clean.out"
  exit 1
fi
if ! grep -qE -- "0 hits across 12 patterns" "$TMP/ac1-clean.out"; then
  echo "FAIL: AC#1 — clean tree summary line missing '0 hits across 12 patterns'"
  cat "$TMP/ac1-clean.out"
  exit 1
fi

FLEET_SELF_CHECK_ROOT="$DIRTY_TREE" "$FLEET" self-check > "$TMP/ac1-dirty.out" 2> "$TMP/ac1-dirty.err"
RC=$?
if [ "$RC" != "1" ]; then
  echo "FAIL: AC#1 — dirty tree should exit 1, got $RC"
  cat "$TMP/ac1-dirty.err"
  exit 1
fi
if ! grep -qE -- "printf leading-dash" "$TMP/ac1-dirty.out"; then
  echo "FAIL: AC#1 — dirty tree output missing 'printf leading-dash' row"
  cat "$TMP/ac1-dirty.out"
  exit 1
fi
hits=$(awk '/^self-check:/ { print }' "$TMP/ac1-dirty.out")
if ! printf -- '%s' "$hits" | grep -qE -- "1 hit"; then
  echo "FAIL: AC#1 — dirty tree summary line expected '1 hit' got: $hits"
  exit 1
fi
echo "ok AC#1: self-check exit 0 on clean, exit 1 on hit, table rendered"

# ---------------------------------------------------------------------------
# AC#2 — --json prints NDJSON, empty on clean, hits on dirty.
# ---------------------------------------------------------------------------
FLEET_SELF_CHECK_ROOT="$CLEAN_TREE" "$FLEET" self-check --json > "$TMP/ac2-clean.out" 2> "$TMP/ac2-clean.err"
RC=$?
if [ "$RC" != "0" ]; then
  echo "FAIL: AC#2 — --json clean should exit 0, got $RC"
  exit 1
fi
clean_lines=$(awk 'NF { n++ } END { print n+0 }' "$TMP/ac2-clean.out")
if [ "$clean_lines" != "0" ]; then
  echo "FAIL: AC#2 — --json on clean should emit zero lines, got $clean_lines"
  cat "$TMP/ac2-clean.out"
  exit 1
fi

FLEET_SELF_CHECK_ROOT="$DIRTY_TREE" "$FLEET" self-check --json > "$TMP/ac2-dirty.out" 2> "$TMP/ac2-dirty.err"
RC=$?
if [ "$RC" != "1" ]; then
  echo "FAIL: AC#2 — --json dirty should exit 1, got $RC"
  exit 1
fi
dirty_lines=$(awk 'NF { n++ } END { print n+0 }' "$TMP/ac2-dirty.out")
if [ "$dirty_lines" -lt 1 ]; then
  echo "FAIL: AC#2 — --json dirty should emit >=1 line, got $dirty_lines"
  cat "$TMP/ac2-dirty.out"
  exit 1
fi
# Validate every line is JSON.
if ! node -e 'let buf = ""; process.stdin.on("data", d => buf += d.toString()); process.stdin.on("end", () => { for (const l of buf.split("\n")) { if (l.trim()) JSON.parse(l); } });' < "$TMP/ac2-dirty.out"; then
  echo "FAIL: AC#2 — --json output is not valid NDJSON"
  cat "$TMP/ac2-dirty.out"
  exit 1
fi
# Validate one record carries pattern/lesson/file/line.
if ! node -e 'let buf = ""; process.stdin.on("data", d => buf += d.toString()); process.stdin.on("end", () => { const rows = buf.split("\n").filter(Boolean).map(l => JSON.parse(l)); const r = rows[0]; if (!r.pattern || !r.lesson || !r.file || typeof r.line !== "number") { console.error("missing field", r); process.exit(1); } });' < "$TMP/ac2-dirty.out"; then
  echo "FAIL: AC#2 — first JSON row missing required keys"
  exit 1
fi
echo "ok AC#2: --json emits valid NDJSON (clean: $clean_lines, dirty: $dirty_lines)"

# ---------------------------------------------------------------------------
# AC#3 — --pattern <name> restricts scan; unknown name exits 2.
# ---------------------------------------------------------------------------
FLEET_SELF_CHECK_ROOT="$DIRTY_TREE" "$FLEET" self-check --pattern printf-leading-dash > "$TMP/ac3-known.out" 2> "$TMP/ac3-known.err"
RC=$?
if [ "$RC" != "1" ]; then
  echo "FAIL: AC#3 — --pattern with hit should exit 1, got $RC"
  cat "$TMP/ac3-known.err"
  exit 1
fi
# Should NOT contain other pattern rows (e.g. cat-roundtrip).
if grep -qE -- "cat-roundtrip|grep-c-double-print" "$TMP/ac3-known.out"; then
  echo "FAIL: AC#3 — --pattern printf-leading-dash leaked other pattern names"
  cat "$TMP/ac3-known.out"
  exit 1
fi

"$FLEET" self-check --pattern bogus-pattern-name > "$TMP/ac3-bogus.out" 2> "$TMP/ac3-bogus.err"
RC=$?
if [ "$RC" != "2" ]; then
  echo "FAIL: AC#3 — unknown --pattern should exit 2, got $RC"
  cat "$TMP/ac3-bogus.err"
  exit 1
fi
if ! grep -qF -- 'unknown pattern' "$TMP/ac3-bogus.err"; then
  echo "FAIL: AC#3 — unknown --pattern stderr missing 'unknown pattern'"
  cat "$TMP/ac3-bogus.err"
  exit 1
fi
echo "ok AC#3: --pattern filters and unknown name exits 2"

# ---------------------------------------------------------------------------
# AC#4 — --list prints catalog (12 rows) with LESSONS dates.
# ---------------------------------------------------------------------------
"$FLEET" self-check --list > "$TMP/ac4.out" 2> "$TMP/ac4.err"
RC=$?
if [ "$RC" != "0" ]; then
  echo "FAIL: AC#4 — --list should exit 0, got $RC"
  cat "$TMP/ac4.err"
  exit 1
fi
catalog_rows=$(awk '/^[A-Za-z][A-Za-z0-9_-]+ +20[0-9]{2}-[0-9]{2}-[0-9]{2}/ { n++ } END { print n+0 }' "$TMP/ac4.out")
if [ "$catalog_rows" != "12" ]; then
  echo "FAIL: AC#4 — expected 12 catalog rows, got $catalog_rows"
  cat "$TMP/ac4.out"
  exit 1
fi
# Every row carries a YYYY-MM-DD LESSONS date.
date_rows=$(awk '/20[0-9]{2}-[0-9]{2}-[0-9]{2}/ { n++ } END { print n+0 }' "$TMP/ac4.out")
if [ "$date_rows" -lt 12 ]; then
  echo "FAIL: AC#4 — expected >=12 rows with LESSONS dates, got $date_rows"
  cat "$TMP/ac4.out"
  exit 1
fi
echo "ok AC#4: --list prints $catalog_rows catalog rows with LESSONS dates"

# ---------------------------------------------------------------------------
# AC#5 — Approximate patterns render with `≈` suffix; --json carries
#        "approximate": true.
# ---------------------------------------------------------------------------
# Build a tree with at least one approximate-pattern hit.
APPROX_TREE="$TMP/approx-kit"
rm -rf "$APPROX_TREE"
mkdir -p "$APPROX_TREE/bin" "$APPROX_TREE/lib" "$APPROX_TREE/scripts"
cp "$FIXTURES/json-escape-sign-extension.bad.sh" "$APPROX_TREE/bin/fleet"
cat > "$APPROX_TREE/lib/common.sh" <<'CLEAN'
#!/bin/bash
CLEAN
cat > "$APPROX_TREE/scripts/check-backlog.mjs" <<'CLEAN'
process.exit(0)
CLEAN

FLEET_SELF_CHECK_ROOT="$APPROX_TREE" "$FLEET" self-check > "$TMP/ac5.out" 2> "$TMP/ac5.err"
RC=$?
if [ "$RC" != "1" ]; then
  echo "FAIL: AC#5 — approximate-pattern fixture should exit 1, got $RC"
  cat "$TMP/ac5.err"
  exit 1
fi
if ! grep -qF -- '≈' "$TMP/ac5.out"; then
  echo "FAIL: AC#5 — approximate pattern not rendered with '≈' suffix"
  cat "$TMP/ac5.out"
  exit 1
fi

FLEET_SELF_CHECK_ROOT="$APPROX_TREE" "$FLEET" self-check --json > "$TMP/ac5.json" 2> "$TMP/ac5.json.err"
if ! node -e 'let buf = ""; process.stdin.on("data", d => buf += d.toString()); process.stdin.on("end", () => { const rows = buf.split("\n").filter(Boolean).map(l => JSON.parse(l)); if (!rows.some(r => r.approximate === true)) { console.error("no approximate row", rows); process.exit(1); } });' < "$TMP/ac5.json"; then
  echo "FAIL: AC#5 — --json output missing approximate: true"
  cat "$TMP/ac5.json"
  exit 1
fi
echo "ok AC#5: approximate patterns render '≈' (text) and approximate: true (json)"

# ---------------------------------------------------------------------------
# AC#6 — --help block mentions --list, --pattern, --json; exit 0.
# ---------------------------------------------------------------------------
"$FLEET" self-check --help > "$TMP/ac6.out" 2> "$TMP/ac6.err"
RC=$?
if [ "$RC" != "0" ]; then
  echo "FAIL: AC#6 — --help should exit 0, got $RC"
  cat "$TMP/ac6.err"
  exit 1
fi
for kw in "--list" "--pattern" "--json"; do
  if ! grep -qF -- "$kw" "$TMP/ac6.out"; then
    echo "FAIL: AC#6 — --help missing keyword $kw"
    cat "$TMP/ac6.out"
    exit 1
  fi
done
echo "ok AC#6: --help mentions --list, --pattern, --json (per LESSONS 2026-05-30 grep -qF --)"

# ---------------------------------------------------------------------------
# AC#7 — FLEET_SELF_CHECK_GATE=1 emits one self_check_failed event per
#        hit; unset env emits NO event.
# ---------------------------------------------------------------------------
# Reset events.jsonl.
cp /dev/null "$EVENTS"
# Unset env — no event.
unset FLEET_SELF_CHECK_GATE
FLEET_SELF_CHECK_ROOT="$DIRTY_TREE" "$FLEET" self-check >/dev/null 2>&1 || true
n_events=$(awk '/self_check_failed/ { n++ } END { print n+0 }' "$EVENTS" 2>/dev/null || echo 0)
if [ "$n_events" != "0" ]; then
  echo "FAIL: AC#7 — unset gate env emitted $n_events events (expected 0)"
  cat "$EVENTS"
  exit 1
fi
# Gate env — emits events.
cp /dev/null "$EVENTS"
FLEET_SELF_CHECK_GATE=1 FLEET_SELF_CHECK_ROOT="$DIRTY_TREE" "$FLEET" self-check >/dev/null 2>&1 || true
n_events=$(awk '/self_check_failed/ { n++ } END { print n+0 }' "$EVENTS" 2>/dev/null || echo 0)
if [ "$n_events" -lt 1 ]; then
  echo "FAIL: AC#7 — FLEET_SELF_CHECK_GATE=1 emitted $n_events events (expected >=1)"
  cat "$EVENTS"
  exit 1
fi
# Validate the payload via node JSON.parse.
last_line=$(awk '/self_check_failed/ { last = $0 } END { print last }' "$EVENTS")
if ! printf -- '%s' "$last_line" | node -e 'let buf = ""; process.stdin.on("data", d => buf += d.toString()); process.stdin.on("end", () => { const o = JSON.parse(buf.trim()); if (o.type !== "self_check_failed") { console.error("wrong type", o.type); process.exit(1); } if (o.phase !== "self-check") { console.error("wrong phase", o.phase); process.exit(1); } if (!o.pattern || !o.lesson_date || !o.file || !o.line) { console.error("missing field", o); process.exit(1); } });'; then
  echo "FAIL: AC#7 — self_check_failed event payload invalid"
  echo "line: $last_line"
  exit 1
fi
echo "ok AC#7: FLEET_SELF_CHECK_GATE=1 emits self_check_failed (n=$n_events); unset env silent"

# ---------------------------------------------------------------------------
# AC#8 — AGENTS.md § Telemetry documents the self_check_failed event.
# ---------------------------------------------------------------------------
AGENTS_MD="$REPO_ROOT/AGENTS.md"
if ! grep -qF -- "self_check_failed" "$AGENTS_MD"; then
  echo "FAIL: AC#8 — AGENTS.md § Telemetry missing self_check_failed bullet"
  exit 1
fi
if ! grep -qF -- "{pattern, lesson_date, file, line}" "$AGENTS_MD"; then
  echo "FAIL: AC#8 — AGENTS.md § Telemetry self_check_failed missing payload signature"
  exit 1
fi
echo "ok AC#8: AGENTS.md § Telemetry documents self_check_failed"

# ---------------------------------------------------------------------------
# AC#9 — AGENTS.md § Agent parameters Local gate command widened with
#        FLEET_SELF_CHECK_GATE=1 bin/fleet self-check.
# ---------------------------------------------------------------------------
if ! grep -qF -- "FLEET_SELF_CHECK_GATE=1" "$AGENTS_MD"; then
  echo "FAIL: AC#9 — AGENTS.md missing FLEET_SELF_CHECK_GATE=1 in local gate"
  exit 1
fi
echo "ok AC#9: AGENTS.md § Agent parameters widened with FLEET_SELF_CHECK_GATE=1"

# ---------------------------------------------------------------------------
# AC#10 — Catalog is exactly 12 patterns and every catalog entry has both
#         a positive and a negative fixture.
# ---------------------------------------------------------------------------
patterns=$("$FLEET" self-check --list | awk '/^[A-Za-z][A-Za-z0-9_-]+ +20[0-9]{2}-[0-9]{2}-[0-9]{2}/ { print $1 }')
n_patterns=$(printf -- '%s\n' "$patterns" | awk 'NF { n++ } END { print n+0 }')
if [ "$n_patterns" != "12" ]; then
  echo "FAIL: AC#10 — catalog has $n_patterns patterns, expected 12"
  exit 1
fi
for p in $patterns; do
  if [ ! -f "$FIXTURES/$p.bad.sh" ]; then
    echo "FAIL: AC#10 — missing positive fixture for pattern $p"
    exit 1
  fi
  if [ ! -f "$FIXTURES/$p.good.sh" ]; then
    echo "FAIL: AC#10 — missing negative fixture for pattern $p"
    exit 1
  fi
  # Each pattern matches its positive fixture and does NOT match its
  # negative fixture when scanned in isolation. Build a one-file kit
  # tree per fixture and assert.
  ONE="$TMP/one-$p"
  rm -rf "$ONE"
  mkdir -p "$ONE/bin" "$ONE/lib" "$ONE/scripts"
  cp "$FIXTURES/$p.bad.sh" "$ONE/bin/fleet"
  : > "$ONE/lib/common.sh"
  : > "$ONE/scripts/check-backlog.mjs"
  hits_bad=$(FLEET_SELF_CHECK_ROOT="$ONE" "$FLEET" self-check --pattern "$p" --json 2>/dev/null | awk 'NF { n++ } END { print n+0 }')
  if [ "$hits_bad" -lt 1 ]; then
    echo "FAIL: AC#10 — pattern $p did NOT match its positive fixture"
    exit 1
  fi
  cp "$FIXTURES/$p.good.sh" "$ONE/bin/fleet"
  hits_good=$(FLEET_SELF_CHECK_ROOT="$ONE" "$FLEET" self-check --pattern "$p" --json 2>/dev/null | awk 'NF { n++ } END { print n+0 }')
  if [ "$hits_good" != "0" ]; then
    echo "FAIL: AC#10 — pattern $p matched its NEGATIVE fixture ($hits_good hits)"
    exit 1
  fi
done
echo "ok AC#10: 12 patterns, each proven by positive + negative fixture"

# ---------------------------------------------------------------------------
# AC#11 — lib/common.sh diff vs main is empty.
# ---------------------------------------------------------------------------
if [ -d "$REPO_ROOT/.git" ]; then
  lib_diff=$(cd "$REPO_ROOT" && git diff --name-only origin/main...HEAD -- lib/common.sh 2>/dev/null || true)
  if [ -n "$lib_diff" ]; then
    echo "FAIL: AC#11 — lib/common.sh changed on this branch: $lib_diff"
    exit 1
  fi
  echo "ok AC#11: lib/common.sh unchanged vs origin/main"
else
  echo "ok AC#11: skipped (no .git in test repo root)"
fi

# ---------------------------------------------------------------------------
# AC#12 — prompts/ diff vs main is empty.
# ---------------------------------------------------------------------------
if [ -d "$REPO_ROOT/.git" ]; then
  prompts_diff=$(cd "$REPO_ROOT" && git diff --name-only origin/main...HEAD -- prompts/ 2>/dev/null || true)
  if [ -n "$prompts_diff" ]; then
    echo "FAIL: AC#12 — prompts/ changed on this branch: $prompts_diff"
    exit 1
  fi
  echo "ok AC#12: prompts/ unchanged vs origin/main"
else
  echo "ok AC#12: skipped (no .git in test repo root)"
fi

# ---------------------------------------------------------------------------
# AC#13 — Performance budget <2s for a full scan against the LIVE kit.
# ---------------------------------------------------------------------------
# Use awk to time without bc (LESSONS 2026-06-01 — bc is not a required
# dep on this repo).
t0=$EPOCHREALTIME
"$FLEET" self-check >/dev/null 2>&1 || true
t1=$EPOCHREALTIME
if ! awk -v a="$t0" -v b="$t1" 'BEGIN { exit !(b-a < 2.0) }'; then
  echo "FAIL: AC#13 — full self-check scan took >=2s (t0=$t0 t1=$t1)"
  exit 1
fi
echo "ok AC#13: full self-check scan < 2s ($(awk -v a="$t0" -v b="$t1" 'BEGIN { printf "%.2fs\n", b-a }'))"

echo
echo "tests/self-check.sh: all 13 ACs passed"
exit 0
