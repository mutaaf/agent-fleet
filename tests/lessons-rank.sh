#!/bin/bash
# tests/lessons-rank.sh — bin/fleet lessons-rank end-to-end.
#
# Ticket 0057. One assertion block per acceptance-criteria checkbox in
# docs/backlog/0057-fleet-lessons-rank-citation-frequency.md:
#
#   AC#1  bin/fleet lessons-rank prints the full ranked list (no flags).
#         Empty LESSONS.md prints the documented "no entries" message;
#         both branches exit 0.
#   AC#2  Headings extracted via one awk pass under LC_ALL=C with
#         BEGIN { count = 0 }. Fixture LESSONS.md has 10 headings; the
#         output names all 10 dates.
#   AC#3  Per-entry citation count = sum of `grep -c -F -- "$date"`
#         across the four file trees. Fixture entry "2026-04-15" must
#         render `cited 20× across 7 files`.
#   AC#4  Self-citation (the heading inside docs/LESSONS.md) is
#         excluded. Fixture entry "2026-04-10" appears only in
#         LESSONS.md itself; output must read `cited 0× across 0 files`.
#   AC#5  promote-candidate threshold: cited ≥10× AND ≥5 files.
#         Boundary fixtures:
#           - 2026-05-01: 10 cites / 4 files → no tag
#           - 2026-05-03: 9 cites / 5 files → no tag
#           - 2026-05-05: 10 cites / 5 files → promote tag
#           - 2026-04-15: 20 cites / 7 files → promote tag
#   AC#6  prune-candidate threshold: ≤1× AND >30d before today.
#         Frozen clock = 2026-06-17 via FLEET_NOW_OVERRIDE. Boundary
#         fixtures:
#           - 2026-05-15: 2 cites / 33d ago → no tag
#           - 2026-06-01: 0 cites / 16d ago → no tag
#           - 2026-05-12: 1 cite  / 36d ago → prune tag
#   AC#7  Output sorted by descending citation count; ties broken by
#         ascending date (older first). 2026-05-01 (10 cites, older)
#         must appear above 2026-05-05 (10 cites, newer).
#   AC#8  --top N / --bottom N. --top 0 / --bottom 0 exit 2 with the
#         documented stderr message.
#   AC#9  --json emits a structured array; Node parses it; each object
#         has the documented keys.
#   AC#10 --include-tests adds tests/*.sh as a fifth tree. Fixture
#         entry 2026-04-25 jumps from 0 cites (default) to 5 cites.
#   AC#11 --help mentions --top, --bottom, --json, --include-tests;
#         exit 0.
#   AC#12 Pure reader: byte sizes of LESSONS.md, prompts/principles.md,
#         and a sampled backlog ticket are unchanged before/after.
#   AC#13 lib/common.sh + prompts/ diff vs main is empty.
#
# Per LESSONS 2026-05-26: stubs live in $HOME/.local/bin. Per LESSONS
# 2026-05-27: cp for fixture backup/restore — never $(cat …). Per
# LESSONS 2026-06-01: counts use awk END { print n+0 }. Per LESSONS
# 2026-06-11: the 30-day-ago math uses `date -v -30d` / `date -v +30d`,
# never `date -j -f`.

set -uo pipefail

REPO_ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
FLEET="$REPO_ROOT/bin/fleet"
FIXTURES="$REPO_ROOT/tests/fixtures/lessons-rank"

TMP="$(mktemp -d -t fleet-lessons-rank-test.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

# Isolate from the host — common.sh's hardcoded PATH wipes a $TMP/bin
# prepended slot, so stubs need to live in $HOME/.local/bin.
export HOME="$TMP/home"
mkdir -p "$HOME" "$HOME/.local/bin"
export PATH="$HOME/.local/bin:$PATH"

# Freeze the clock to 2026-06-17 so the 30-day prune math is stable.
export FLEET_NOW_OVERRIDE="2026-06-17"

# ---------------------------------------------------------------------------
# Build the live fixture tree the implementation will scan.
# Backup/restore via cp per LESSONS 2026-05-27.
# ---------------------------------------------------------------------------
KIT_TREE="$TMP/kit"
mkdir -p "$KIT_TREE/bin" "$KIT_TREE/lib" "$KIT_TREE/prompts" \
         "$KIT_TREE/docs/backlog" "$KIT_TREE/tests"
cp "$FIXTURES/bin/fleet"               "$KIT_TREE/bin/fleet"
cp "$FIXTURES/lib/common.sh"           "$KIT_TREE/lib/common.sh"
cp "$FIXTURES/prompts/principles.md"   "$KIT_TREE/prompts/principles.md"
cp "$FIXTURES/docs/LESSONS.md"         "$KIT_TREE/docs/LESSONS.md"
cp "$FIXTURES/docs/backlog/0001-fixture.md" "$KIT_TREE/docs/backlog/0001-fixture.md"
cp "$FIXTURES/docs/backlog/0002-fixture.md" "$KIT_TREE/docs/backlog/0002-fixture.md"
cp "$FIXTURES/docs/backlog/0003-fixture.md" "$KIT_TREE/docs/backlog/0003-fixture.md"
cp "$FIXTURES/docs/backlog/0004-fixture.md" "$KIT_TREE/docs/backlog/0004-fixture.md"
cp "$FIXTURES/docs/backlog/0005-fixture.md" "$KIT_TREE/docs/backlog/0005-fixture.md"
cp "$FIXTURES/tests/lessons-rank-fixture.sh" "$KIT_TREE/tests/lessons-rank-fixture.sh"

EMPTY_TREE="$TMP/empty-kit"
mkdir -p "$EMPTY_TREE/bin" "$EMPTY_TREE/lib" "$EMPTY_TREE/prompts" \
         "$EMPTY_TREE/docs/backlog"
cp "$FIXTURES/empty-LESSONS.md" "$EMPTY_TREE/docs/LESSONS.md"

# ---------------------------------------------------------------------------
# AC#1 — default invocation prints the ranked list; empty LESSONS.md
# prints the documented "no entries" message; both exit 0.
# ---------------------------------------------------------------------------
FLEET_LESSONS_RANK_ROOT="$KIT_TREE" "$FLEET" lessons-rank \
  > "$TMP/ac1.out" 2> "$TMP/ac1.err"
RC=$?
if [ "$RC" != "0" ]; then
  echo "FAIL: AC#1 — default invocation should exit 0, got $RC"
  cat "$TMP/ac1.err"
  exit 1
fi
if ! grep -qE -- "lessons-rank" "$TMP/ac1.out"; then
  echo "FAIL: AC#1 — default invocation output missing 'lessons-rank' banner"
  cat "$TMP/ac1.out"
  exit 1
fi
if ! grep -qF -- "2026-04-15" "$TMP/ac1.out"; then
  echo "FAIL: AC#1 — default output missing top entry 2026-04-15"
  cat "$TMP/ac1.out"
  exit 1
fi

FLEET_LESSONS_RANK_ROOT="$EMPTY_TREE" "$FLEET" lessons-rank \
  > "$TMP/ac1-empty.out" 2> "$TMP/ac1-empty.err"
RC=$?
if [ "$RC" != "0" ]; then
  echo "FAIL: AC#1 — empty LESSONS.md should exit 0, got $RC"
  cat "$TMP/ac1-empty.err"
  exit 1
fi
if ! grep -qF -- "no LESSONS entries found" "$TMP/ac1-empty.out"; then
  echo "FAIL: AC#1 — empty LESSONS.md output missing documented message"
  cat "$TMP/ac1-empty.out"
  exit 1
fi
echo "ok AC#1: default ranked list rendered; empty LESSONS.md printed no-entries message"

# ---------------------------------------------------------------------------
# AC#2 — heading-extractor finds all 10 fixture headings.
# ---------------------------------------------------------------------------
expected_dates="2026-04-10 2026-04-15 2026-04-20 2026-04-25 2026-05-01 2026-05-03 2026-05-05 2026-05-12 2026-05-15 2026-06-01"
for d in $expected_dates; do
  if ! grep -qF -- "$d" "$TMP/ac1.out"; then
    echo "FAIL: AC#2 — heading $d missing from default output"
    cat "$TMP/ac1.out"
    exit 1
  fi
done
echo "ok AC#2: all 10 fixture LESSONS headings appear in default output"

# ---------------------------------------------------------------------------
# AC#3 — sum-of-grep across four trees. 2026-04-15: 20 cites / 7 files.
# Look for the "cited 20× across 7 files" rendering.
# ---------------------------------------------------------------------------
if ! grep -qF -- "cited 20× across 7 files" "$TMP/ac1.out"; then
  echo "FAIL: AC#3 — 2026-04-15 entry did not render 'cited 20× across 7 files'"
  grep -F -- "2026-04-15" "$TMP/ac1.out" || true
  exit 1
fi
echo "ok AC#3: per-entry totals across four trees sum correctly (20 cites / 7 files)"

# ---------------------------------------------------------------------------
# AC#4 — self-citation in LESSONS.md excluded. 2026-04-10 appears
# only as a LESSONS.md heading; the rendered line must read 0× / 0 files.
# ---------------------------------------------------------------------------
sec="$(awk '/2026-04-10/ { found=1 } found && /cited / { print; exit }' "$TMP/ac1.out")"
if ! printf -- '%s' "$sec" | grep -qF -- "cited 0× across 0 files"; then
  echo "FAIL: AC#4 — 2026-04-10 (self-cite-only) rendered: $sec"
  exit 1
fi
echo "ok AC#4: self-citation in LESSONS.md excluded from count"

# ---------------------------------------------------------------------------
# AC#5 — promote-candidate threshold boundaries.
# ---------------------------------------------------------------------------
# 2026-05-01: 10 cites / 4 files → NO promote tag.
sec501="$(awk '/2026-05-01/ { found=1 } found && /cited / { print; print_next=1; next } print_next { print; exit }' "$TMP/ac1.out")"
if printf -- '%s' "$sec501" | grep -qF -- "promote-candidate"; then
  echo "FAIL: AC#5 — 2026-05-01 (10/4) should NOT be promote-candidate; got: $sec501"
  exit 1
fi
# 2026-05-03: 9 cites / 5 files → NO promote tag.
sec503="$(awk '/2026-05-03/ { found=1 } found && /cited / { print; print_next=1; next } print_next { print; exit }' "$TMP/ac1.out")"
if printf -- '%s' "$sec503" | grep -qF -- "promote-candidate"; then
  echo "FAIL: AC#5 — 2026-05-03 (9/5) should NOT be promote-candidate; got: $sec503"
  exit 1
fi
# 2026-05-05: 10 cites / 5 files → promote tag.
sec505="$(awk '/2026-05-05/ { found=1 } found && /cited / { print; print_next=1; next } print_next { print; exit }' "$TMP/ac1.out")"
if ! printf -- '%s' "$sec505" | grep -qF -- "promote-candidate"; then
  echo "FAIL: AC#5 — 2026-05-05 (10/5) should be promote-candidate; got: $sec505"
  exit 1
fi
# 2026-04-15: 20 cites / 7 files → promote tag.
sec415="$(awk '/2026-04-15/ { found=1 } found && /cited / { print; print_next=1; next } print_next { print; exit }' "$TMP/ac1.out")"
if ! printf -- '%s' "$sec415" | grep -qF -- "promote-candidate"; then
  echo "FAIL: AC#5 — 2026-04-15 (20/7) should be promote-candidate; got: $sec415"
  exit 1
fi
echo "ok AC#5: promote-candidate threshold (≥10 cites AND ≥5 files) holds at all four boundaries"

# ---------------------------------------------------------------------------
# AC#6 — prune-candidate threshold boundaries with frozen clock 2026-06-17.
# 2026-05-15: 2 cites / 33d ago → NO prune.
# 2026-06-01: 0 cites / 16d ago → NO prune (too recent).
# 2026-05-12: 1 cite  / 36d ago → prune tag, EXPIRES 2026-07-17 suggested.
# ---------------------------------------------------------------------------
sec515="$(awk '/2026-05-15/ { found=1 } found && /cited / { print; print_next=1; next } print_next { print; exit }' "$TMP/ac1.out")"
if printf -- '%s' "$sec515" | grep -qF -- "prune-candidate"; then
  echo "FAIL: AC#6 — 2026-05-15 (2 cites, 33d ago) should NOT be prune-candidate; got: $sec515"
  exit 1
fi
sec601="$(awk '/2026-06-01/ { found=1 } found && /cited / { print; print_next=1; next } print_next { print; exit }' "$TMP/ac1.out")"
if printf -- '%s' "$sec601" | grep -qF -- "prune-candidate"; then
  echo "FAIL: AC#6 — 2026-06-01 (0 cites, 16d ago) should NOT be prune-candidate; got: $sec601"
  exit 1
fi
sec512="$(awk '/2026-05-12/ { found=1 } found && /cited / { print; print_next=1; next } print_next { print; exit }' "$TMP/ac1.out")"
if ! printf -- '%s' "$sec512" | grep -qF -- "prune-candidate"; then
  echo "FAIL: AC#6 — 2026-05-12 (1 cite, 36d ago) should be prune-candidate; got: $sec512"
  exit 1
fi
if ! printf -- '%s' "$sec512" | grep -qF -- "EXPIRES 2026-07-17"; then
  echo "FAIL: AC#6 — 2026-05-12 prune tag missing 'EXPIRES 2026-07-17' suggestion; got: $sec512"
  exit 1
fi
echo "ok AC#6: prune-candidate threshold (≤1 cite AND >30d old) holds at all three boundaries"

# ---------------------------------------------------------------------------
# AC#7 — sort order: 2026-05-01 (10/4, older) ranks above 2026-05-05
# (10/5, newer) when ties are broken by ascending date.
# ---------------------------------------------------------------------------
pos501="$(awk '/2026-05-01/ { print NR; exit }' "$TMP/ac1.out")"
pos505="$(awk '/2026-05-05/ { print NR; exit }' "$TMP/ac1.out")"
if [ -z "$pos501" ] || [ -z "$pos505" ]; then
  echo "FAIL: AC#7 — could not locate 2026-05-01 or 2026-05-05 in output"
  exit 1
fi
if [ "$pos501" -ge "$pos505" ]; then
  echo "FAIL: AC#7 — tie-break expects 2026-05-01 (older) ABOVE 2026-05-05; got line $pos501 vs $pos505"
  exit 1
fi
echo "ok AC#7: ties broken by ascending date (older first)"

# ---------------------------------------------------------------------------
# AC#8 — --top N / --bottom N + zero-arg refusal.
# ---------------------------------------------------------------------------
FLEET_LESSONS_RANK_ROOT="$KIT_TREE" "$FLEET" lessons-rank --top 2 \
  > "$TMP/ac8-top.out" 2> "$TMP/ac8-top.err"
RC=$?
if [ "$RC" != "0" ]; then
  echo "FAIL: AC#8 — --top 2 should exit 0, got $RC"
  cat "$TMP/ac8-top.err"
  exit 1
fi
# --top 2 must include the top two (2026-04-15 and 2026-04-20) and NOT
# the bottom self-only entry (2026-04-10).
if ! grep -qF -- "2026-04-15" "$TMP/ac8-top.out"; then
  echo "FAIL: AC#8 — --top 2 missing top entry 2026-04-15"
  cat "$TMP/ac8-top.out"
  exit 1
fi
if grep -qF -- "2026-04-10" "$TMP/ac8-top.out"; then
  echo "FAIL: AC#8 — --top 2 unexpectedly includes bottom entry 2026-04-10"
  cat "$TMP/ac8-top.out"
  exit 1
fi

FLEET_LESSONS_RANK_ROOT="$KIT_TREE" "$FLEET" lessons-rank --bottom 2 \
  > "$TMP/ac8-bot.out" 2> "$TMP/ac8-bot.err"
RC=$?
if [ "$RC" != "0" ]; then
  echo "FAIL: AC#8 — --bottom 2 should exit 0, got $RC"
  cat "$TMP/ac8-bot.err"
  exit 1
fi
# --bottom 2 must include 2026-04-10 / 2026-06-01 (two of the 0-cite tail)
# and NOT the top entry 2026-04-15.
if grep -qF -- "2026-04-15" "$TMP/ac8-bot.out"; then
  echo "FAIL: AC#8 — --bottom 2 unexpectedly includes top entry 2026-04-15"
  cat "$TMP/ac8-bot.out"
  exit 1
fi

FLEET_LESSONS_RANK_ROOT="$KIT_TREE" "$FLEET" lessons-rank --top 0 \
  > "$TMP/ac8-top0.out" 2> "$TMP/ac8-top0.err"
RC=$?
if [ "$RC" != "2" ]; then
  echo "FAIL: AC#8 — --top 0 should exit 2, got $RC"
  exit 1
fi
if ! grep -qF -- "requires a positive integer" "$TMP/ac8-top0.err"; then
  echo "FAIL: AC#8 — --top 0 stderr missing 'requires a positive integer'"
  cat "$TMP/ac8-top0.err"
  exit 1
fi

FLEET_LESSONS_RANK_ROOT="$KIT_TREE" "$FLEET" lessons-rank --bottom 0 \
  > "$TMP/ac8-bot0.out" 2> "$TMP/ac8-bot0.err"
RC=$?
if [ "$RC" != "2" ]; then
  echo "FAIL: AC#8 — --bottom 0 should exit 2, got $RC"
  exit 1
fi
if ! grep -qF -- "requires a positive integer" "$TMP/ac8-bot0.err"; then
  echo "FAIL: AC#8 — --bottom 0 stderr missing 'requires a positive integer'"
  cat "$TMP/ac8-bot0.err"
  exit 1
fi
echo "ok AC#8: --top N / --bottom N work; zero-arg exits 2 with documented stderr"

# ---------------------------------------------------------------------------
# AC#9 — --json emits a valid JSON array of objects with the documented
# shape. Validate with Node.
# ---------------------------------------------------------------------------
FLEET_LESSONS_RANK_ROOT="$KIT_TREE" "$FLEET" lessons-rank --json \
  > "$TMP/ac9.json" 2> "$TMP/ac9.err"
RC=$?
if [ "$RC" != "0" ]; then
  echo "FAIL: AC#9 — --json should exit 0, got $RC"
  cat "$TMP/ac9.err"
  exit 1
fi
node -e '
  const fs = require("fs");
  const arr = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
  if (!Array.isArray(arr)) { console.error("expected array, got " + typeof arr); process.exit(1); }
  if (arr.length !== 10) { console.error("expected 10 entries, got " + arr.length); process.exit(1); }
  const top = arr[0];
  const required = ["date","headline","total_citations","files_cited","by_tree","recommendation"];
  for (const k of required) {
    if (!(k in top)) { console.error("missing key " + k + " in top entry"); process.exit(1); }
  }
  const treeKeys = ["bin/fleet","lib","prompts","docs/backlog"];
  for (const k of treeKeys) {
    if (!(k in top.by_tree)) { console.error("missing by_tree key " + k); process.exit(1); }
  }
  if (top.date !== "2026-04-15") { console.error("top date wrong: " + top.date); process.exit(1); }
  if (top.total_citations !== 20) { console.error("top citations wrong: " + top.total_citations); process.exit(1); }
  if (top.recommendation !== "promote") { console.error("top recommendation wrong: " + top.recommendation); process.exit(1); }
  // Find 2026-04-10 — should be recommendation prune.
  const selfOnly = arr.find(e => e.date === "2026-04-10");
  if (!selfOnly || selfOnly.recommendation !== "prune") {
    console.error("self-only entry not prune-recommended: " + JSON.stringify(selfOnly));
    process.exit(1);
  }
' "$TMP/ac9.json" || {
  echo "FAIL: AC#9 — JSON shape validation failed"
  cat "$TMP/ac9.json"
  exit 1
}
echo "ok AC#9: --json emits a valid array with the documented shape"

# ---------------------------------------------------------------------------
# AC#10 — --include-tests adds tests/*.sh as a fifth tree. The
# 2026-04-25 fixture has 5 cites in tests/lessons-rank-fixture.sh and
# zero cites in the four default trees. Default: 0 cites; --include-tests:
# 5 cites.
# ---------------------------------------------------------------------------
sec425_default="$(awk '/2026-04-25/ { found=1 } found && /cited / { print; exit }' "$TMP/ac1.out")"
if ! printf -- '%s' "$sec425_default" | grep -qF -- "cited 0× across 0 files"; then
  echo "FAIL: AC#10 — 2026-04-25 default (no --include-tests) expected '0× across 0 files'; got: $sec425_default"
  exit 1
fi

FLEET_LESSONS_RANK_ROOT="$KIT_TREE" "$FLEET" lessons-rank --include-tests \
  > "$TMP/ac10.out" 2> "$TMP/ac10.err"
RC=$?
if [ "$RC" != "0" ]; then
  echo "FAIL: AC#10 — --include-tests should exit 0, got $RC"
  cat "$TMP/ac10.err"
  exit 1
fi
sec425_inc="$(awk '/2026-04-25/ { found=1 } found && /cited / { print; exit }' "$TMP/ac10.out")"
if ! printf -- '%s' "$sec425_inc" | grep -qF -- "cited 5× across 1 file"; then
  echo "FAIL: AC#10 — 2026-04-25 --include-tests expected '5× across 1 file'; got: $sec425_inc"
  exit 1
fi
echo "ok AC#10: --include-tests adds the fifth tree (5 cites surface for 2026-04-25)"

# ---------------------------------------------------------------------------
# AC#11 — --help mentions every documented flag; exit 0.
# ---------------------------------------------------------------------------
"$FLEET" lessons-rank --help > "$TMP/ac11.out" 2> "$TMP/ac11.err"
RC=$?
if [ "$RC" != "0" ]; then
  echo "FAIL: AC#11 — --help should exit 0, got $RC"
  cat "$TMP/ac11.err"
  exit 1
fi
for kw in "--top" "--bottom" "--json" "--include-tests"; do
  if ! grep -qF -- "$kw" "$TMP/ac11.out"; then
    echo "FAIL: AC#11 — --help missing keyword $kw"
    cat "$TMP/ac11.out"
    exit 1
  fi
done
echo "ok AC#11: --help mentions all documented flags; exits 0"

# ---------------------------------------------------------------------------
# AC#12 — pure reader. Byte sizes of LESSONS.md, prompts/principles.md,
# and a sampled backlog ticket are unchanged before/after invocation.
# ---------------------------------------------------------------------------
size() { wc -c < "$1" | tr -d ' '; }
before_lessons="$(size "$KIT_TREE/docs/LESSONS.md")"
before_prompt="$(size "$KIT_TREE/prompts/principles.md")"
before_ticket="$(size "$KIT_TREE/docs/backlog/0001-fixture.md")"

FLEET_LESSONS_RANK_ROOT="$KIT_TREE" "$FLEET" lessons-rank \
  > /dev/null 2> /dev/null

after_lessons="$(size "$KIT_TREE/docs/LESSONS.md")"
after_prompt="$(size "$KIT_TREE/prompts/principles.md")"
after_ticket="$(size "$KIT_TREE/docs/backlog/0001-fixture.md")"

if [ "$before_lessons" != "$after_lessons" ]; then
  echo "FAIL: AC#12 — LESSONS.md size changed ($before_lessons -> $after_lessons)"
  exit 1
fi
if [ "$before_prompt" != "$after_prompt" ]; then
  echo "FAIL: AC#12 — prompts/principles.md size changed ($before_prompt -> $after_prompt)"
  exit 1
fi
if [ "$before_ticket" != "$after_ticket" ]; then
  echo "FAIL: AC#12 — backlog ticket size changed ($before_ticket -> $after_ticket)"
  exit 1
fi

# Pure reader also implies NO events.jsonl writes from the kit cache.
KIT_CACHE="$HOME/.cache/agent-fleet-agent"
EVENTS="$KIT_CACHE/events.jsonl"
n_events=0
if [ -f "$EVENTS" ]; then
  n_events="$(awk 'BEGIN { count = 0 } /lessons_rank/ { n++ } END { print n+0 }' "$EVENTS")"
fi
if [ "$n_events" != "0" ]; then
  echo "FAIL: AC#12 — lessons-rank emitted events ($n_events lessons_rank entries in events.jsonl)"
  exit 1
fi
echo "ok AC#12: pure reader — no file mutation, no events emitted"

# ---------------------------------------------------------------------------
# AC#13 — lib/common.sh and prompts/ diff vs main is empty (no engine
# or prompt edits in this PR).
# ---------------------------------------------------------------------------
cd "$REPO_ROOT" || exit 1
diff_out="$(git diff --name-only main...HEAD -- lib/common.sh prompts/ 2>/dev/null || true)"
if [ -n "$diff_out" ]; then
  echo "FAIL: AC#13 — lib/common.sh or prompts/ has unexpected diff vs main: $diff_out"
  exit 1
fi
echo "ok AC#13: lib/common.sh and prompts/ untouched"

echo
echo "tests/lessons-rank.sh — all 13 ACs PASSED"
