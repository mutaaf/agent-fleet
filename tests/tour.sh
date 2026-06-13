#!/bin/bash
# tests/tour.sh — `bin/fleet tour` annotated-walkthrough test.
#
# Ticket 0050. One assertion block per acceptance-criteria checkbox in
# docs/backlog/0050-fleet-tour-annotated-first-run-walkthrough.md.
#
# `tour` is a PURE READER: no events.jsonl writes, no fleet_emit_event,
# no `lib/` or `prompts/` edits, no new event types. AC#13 asserts the
# events channel byte size is unchanged across invocation; AC#14 + AC#15
# assert `lib/common.sh` and `prompts/` are untouched on this branch.
#
# Per LESSONS 2026-05-26 stubs live under $HOME/.local/bin (lib/common.sh
# resets PATH — bin/fleet does NOT source it, but reusing the convention
# keeps the test simple). Per LESSONS 2026-05-27 every fixture is copied
# with `cp` (never `$(cat …)`). Per LESSONS 2026-06-01 every count uses
# `awk … END { print n+0 }`. Per LESSONS 2026-05-30 help-text greps use
# `grep -qF -- "$kw"`. Per LESSONS 2026-06-11 every chronological compare
# is ISO8601 lex-compare. Run-time budget: <8s.

set -euo pipefail

REPO_ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
FLEET="$REPO_ROOT/bin/fleet"
FIXTURE_DIR="$REPO_ROOT/tests/fixtures/tour"

TMP="$(mktemp -d -t fleet-tour-test.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

# Isolate HOME so $HOME/.cache, $HOME/.local/bin stay sandboxed.
export HOME="$TMP/home"
mkdir -p "$HOME/.local/bin"
export PATH="$HOME/.local/bin:$PATH"

# Freeze the clock so any time-relative compositions are deterministic.
export FLEET_NOW_OVERRIDE="2026-06-13T12:00:00Z"

# Seed a manifest under a fixture root and point discovery there.
FIXTURE_ROOT="$TMP/projects"
mkdir -p "$FIXTURE_ROOT/demo"
cat > "$FIXTURE_ROOT/demo/agents.config.sh" <<'CFG'
PROJECT_NAME="demo"
SLUG="demo"
NAMESPACE="com.demo"
REPO_URL="https://github.com/example/demo"
SELF_CANCEL="20990101"
CFG
export FLEET_DISCOVERY_ROOT="$FIXTURE_ROOT"

CACHE="$HOME/.cache/demo-agent"
mkdir -p "$CACHE"

# Install the basic events fixture by default — most AC blocks reuse it.
cp "$FIXTURE_DIR/events-basic.jsonl" "$CACHE/events.jsonl"

# Track events byte size before any invocation (AC#13).
events_size() { wc -c < "$1" | tr -d ' '; }
SIZE_BEFORE="$(events_size "$CACHE/events.jsonl")"

# ========================================================================
# AC #1 — `bin/fleet tour [<repo>]` subcommand. With repo path arg → walks
#         that repo's events.jsonl. With no arg, walks the kit's events.jsonl
#         OR — when the kit has no events.jsonl — prints a guided "no
#         events.jsonl" hint. We force the "no kit events" branch by
#         pointing FLEET_DISCOVERY_ROOT at a manifest-less root.
# ========================================================================
echo "AC#1 — subcommand discovery + missing-channel hint"
OUT="$TMP/ac1.out"
set +e
"$FLEET" tour "$FIXTURE_ROOT/demo" > "$OUT" 2>&1
EXIT=$?
set -e
if [ "$EXIT" != "0" ]; then
  echo "FAIL: AC#1 tour <repo> exit $EXIT (want 0)"; cat "$OUT"; exit 1
fi
grep -qF -- "tour: walking events.jsonl for demo" "$OUT" \
  || { echo "FAIL: AC#1 missing 'walking events.jsonl for demo' header"; cat "$OUT"; exit 1; }

# Now exercise the no-events path. Use a discovery root with no project, and
# a HOME with no kit events channel.
EMPTY_ROOT="$TMP/empty-root"; mkdir -p "$EMPTY_ROOT"
OUT2="$TMP/ac1-empty.out"
set +e
FLEET_DISCOVERY_ROOT="$EMPTY_ROOT" "$FLEET" tour > "$OUT2" 2>&1
EXIT2=$?
set -e
if [ "$EXIT2" != "0" ]; then
  echo "FAIL: AC#1 no-events tour exit $EXIT2 (want 0)"; cat "$OUT2"; exit 1
fi
grep -qF -- "no events.jsonl found" "$OUT2" \
  || { echo "FAIL: AC#1 missing 'no events.jsonl found' hint"; cat "$OUT2"; exit 1; }
grep -qF -- "fleet onboard" "$OUT2" \
  || { echo "FAIL: AC#1 missing 'fleet onboard' hint"; cat "$OUT2"; exit 1; }
grep -qF -- "fleet kickstart --demo" "$OUT2" \
  || { echo "FAIL: AC#1 missing 'fleet kickstart --demo' hint"; cat "$OUT2"; exit 1; }
echo "  ok"

# ========================================================================
# AC #2 — `lib/tour-catalog.sh` has one function per event type listed in
#         AGENTS.md § Telemetry.
# ========================================================================
echo "AC#2 — lib/tour-catalog.sh covers every AGENTS.md event type"
CATALOG="$REPO_ROOT/lib/tour-catalog.sh"
AGENTS="$REPO_ROOT/AGENTS.md"
[ -f "$CATALOG" ] || { echo "FAIL: AC#2 missing $CATALOG"; exit 1; }
[ -f "$AGENTS" ]  || { echo "FAIL: AC#2 missing $AGENTS"; exit 1; }

# Extract event-type names from AGENTS.md. Pattern: lines like
#   `    - \`run_started {pid}\` — fired ...`
# Bounded to the `**Event types**` bullet list (same as
# scripts/check-tour-catalog.mjs). BSD awk lacks the 3-arg match form so
# we use sub/sed-style extraction inside an awk state machine.
AGENTS_TYPES="$TMP/agents-types.txt"
awk '
  BEGIN { in_list = 0 }
  /^- \*\*Event types\*\*/ { in_list = 1; next }
  in_list && /^[^[:space:]]/ { in_list = 0 }
  in_list && /^[[:space:]]+- `[a-z_][a-z_0-9]*/ {
    s = $0
    sub(/^[[:space:]]+- `/, "", s)
    sub(/[^a-z_0-9].*/, "", s)
    if (s != "") print s
  }
' "$AGENTS" | LC_ALL=C sort -u > "$AGENTS_TYPES"
N_AGENTS="$(awk 'END { print NR+0 }' "$AGENTS_TYPES")"
if [ "$N_AGENTS" -lt 23 ]; then
  echo "FAIL: AC#2 expected at least 23 event types in AGENTS.md, parsed $N_AGENTS"
  cat "$AGENTS_TYPES"; exit 1
fi

CATALOG_TYPES="$TMP/catalog-types.txt"
awk '
  /^tour_catalog_[a-z_][a-z_0-9]*\(\)/ {
    s = $0
    sub(/^tour_catalog_/, "", s)
    sub(/\(\).*/, "", s)
    if (s != "" && s != "principle_title") print s
  }
' "$CATALOG" | LC_ALL=C sort -u > "$CATALOG_TYPES"

MISSING="$(LC_ALL=C comm -23 "$AGENTS_TYPES" "$CATALOG_TYPES")"
if [ -n "$MISSING" ]; then
  echo "FAIL: AC#2 event types in AGENTS.md missing tour_catalog_<type>():"
  echo "$MISSING"
  exit 1
fi
echo "  ok ($N_AGENTS event types covered)"

# ========================================================================
# AC #3 — `scripts/check-tour-catalog.mjs` is a gate. Fails when AGENTS.md
#         has an event type with no catalog entry; passes on the real pair.
# ========================================================================
echo "AC#3 — check-tour-catalog gate"
GATE="$REPO_ROOT/scripts/check-tour-catalog.mjs"
[ -f "$GATE" ] || { echo "FAIL: AC#3 missing $GATE"; exit 1; }

# Real pair should pass.
set +e
node "$GATE" > "$TMP/gate-pass.out" 2>&1
GATE_PASS=$?
set -e
if [ "$GATE_PASS" != "0" ]; then
  echo "FAIL: AC#3 gate exit $GATE_PASS on real AGENTS.md + catalog (want 0)"
  cat "$TMP/gate-pass.out"; exit 1
fi

# Fixture pair (AGENTS.md with hypothetical_future_event) should fail.
set +e
FLEET_CHECK_TOUR_AGENTS_MD="$FIXTURE_DIR/AGENTS-missing-event.md" \
  FLEET_CHECK_TOUR_CATALOG="$CATALOG" \
  node "$GATE" > "$TMP/gate-fail.out" 2>&1
GATE_FAIL=$?
set -e
if [ "$GATE_FAIL" = "0" ]; then
  echo "FAIL: AC#3 gate should fail on fixture AGENTS.md with hypothetical_future_event"
  cat "$TMP/gate-fail.out"; exit 1
fi
grep -qF -- "hypothetical_future_event" "$TMP/gate-fail.out" \
  || { echo "FAIL: AC#3 gate output should name the missing event type"; cat "$TMP/gate-fail.out"; exit 1; }
echo "  ok"

# ========================================================================
# AC #4 — Render walks chronologically, prints one annotated block per
#         event: `[<idx>] <ts>  <type> {<fields>}` + 2-3 sentences + the
#         "Why this event exists: P-<N> (<title>). <elaboration>." line.
# ========================================================================
echo "AC#4 — annotated render"
OUT="$TMP/ac4.out"
"$FLEET" tour "$FIXTURE_ROOT/demo" > "$OUT"
# Per-event index prefixes [1], [2], [3], [4].
for idx in '[1]' '[2]' '[3]' '[4]'; do
  grep -qF -- "$idx" "$OUT" \
    || { echo "FAIL: AC#4 missing index $idx in render"; cat "$OUT"; exit 1; }
done
# Timestamps appear with full ISO8601.
grep -qF -- "2026-06-13T09:37:09Z" "$OUT" \
  || { echo "FAIL: AC#4 missing run_started ts"; cat "$OUT"; exit 1; }
grep -qF -- "2026-06-13T10:53:22Z" "$OUT" \
  || { echo "FAIL: AC#4 missing run_completed ts"; cat "$OUT"; exit 1; }
# Each event type prints a Why-line citing a P-N.
N_WHY="$(awk '/^[[:space:]]+Why this event exists: P-/ { n++ } END { print n+0 }' "$OUT")"
if [ "$N_WHY" -lt 4 ]; then
  echo "FAIL: AC#4 want ≥4 'Why this event exists: P-' lines, got $N_WHY"
  cat "$OUT"; exit 1
fi
echo "  ok ($N_WHY annotated blocks)"

# ========================================================================
# AC #5 — Consecutive identical-body events fold: `× N occurrences
#         (<first_ts> → <last_ts>)`.
# ========================================================================
echo "AC#5 — fold consecutive identical events"
cp "$FIXTURE_DIR/events-folding.jsonl" "$CACHE/events.jsonl"
OUT="$TMP/ac5.out"
"$FLEET" tour "$FIXTURE_ROOT/demo" > "$OUT"
grep -qE 'x ?4 occurrences' "$OUT" \
  || { echo "FAIL: AC#5 missing 'x 4 occurrences' fold line"; cat "$OUT"; exit 1; }
grep -qF -- "2026-06-13T09:40:01Z" "$OUT" \
  || { echo "FAIL: AC#5 missing first ts of fold"; cat "$OUT"; exit 1; }
grep -qF -- "2026-06-13T09:46:01Z" "$OUT" \
  || { echo "FAIL: AC#5 missing last ts of fold"; cat "$OUT"; exit 1; }
echo "  ok"

# ========================================================================
# AC #6 — Footer: lesson_draft_emitted → fleet lessons-promote, ship_paused
#         → fleet resume, infra_flake_rerun → fleet incident; the daily
#         three are always suggested.
# ========================================================================
echo "AC#6 — conditional what-to-read-next footer"
cp "$FIXTURE_DIR/events-footer.jsonl" "$CACHE/events.jsonl"
OUT="$TMP/ac6.out"
"$FLEET" tour "$FIXTURE_ROOT/demo" > "$OUT"
for kw in \
  "fleet lessons-promote" \
  "fleet resume" \
  "fleet incident" \
  "fleet morning" \
  "fleet streak" \
  "fleet doctor" \
  "AGENTS.md" \
  "PRINCIPLES" \
  "LESSONS"; do
  grep -qF -- "$kw" "$OUT" \
    || { echo "FAIL: AC#6 footer missing keyword '$kw'"; cat "$OUT"; exit 1; }
done

# The conditionals should NOT fire when nothing triggers them. Use the basic
# fixture (no ship_paused, no lesson_draft_emitted, no infra_flake_rerun).
cp "$FIXTURE_DIR/events-basic.jsonl" "$CACHE/events.jsonl"
OUT2="$TMP/ac6-basic.out"
"$FLEET" tour "$FIXTURE_ROOT/demo" > "$OUT2"
if grep -qF -- "fleet lessons-promote" "$OUT2"; then
  echo "FAIL: AC#6 basic fixture should NOT suggest 'fleet lessons-promote'"
  cat "$OUT2"; exit 1
fi
if grep -qF -- "fleet resume" "$OUT2"; then
  echo "FAIL: AC#6 basic fixture should NOT suggest 'fleet resume'"
  cat "$OUT2"; exit 1
fi
if grep -qF -- "fleet incident" "$OUT2"; then
  echo "FAIL: AC#6 basic fixture should NOT suggest 'fleet incident'"
  cat "$OUT2"; exit 1
fi
# But the always-three should still appear.
for kw in "fleet morning" "fleet streak" "fleet doctor"; do
  grep -qF -- "$kw" "$OUT2" \
    || { echo "FAIL: AC#6 basic-fixture footer missing daily-three keyword '$kw'"; cat "$OUT2"; exit 1; }
done
echo "  ok"

# ========================================================================
# AC #7 — `--archive` walks events.jsonl.archive/*.jsonl in chronological
#         order BEFORE the live file; separator `--- archive boundary ---`
#         between segments.
# ========================================================================
echo "AC#7 — --archive walks rotated segments"
# Replace the cache contents with the archive fixture (including the
# events.jsonl.archive/ subdir).
rm -rf "$CACHE"
mkdir -p "$CACHE/events.jsonl.archive"
cp "$FIXTURE_DIR/archive-fixture/events.jsonl" "$CACHE/events.jsonl"
cp "$FIXTURE_DIR/archive-fixture/events.jsonl.archive/2026-06-10T120000Z.jsonl" \
   "$CACHE/events.jsonl.archive/2026-06-10T120000Z.jsonl"
cp "$FIXTURE_DIR/archive-fixture/events.jsonl.archive/2026-06-11T120000Z.jsonl" \
   "$CACHE/events.jsonl.archive/2026-06-11T120000Z.jsonl"
OUT="$TMP/ac7.out"
"$FLEET" tour --archive "$FIXTURE_ROOT/demo" > "$OUT"
grep -qF -- "--- archive boundary ---" "$OUT" \
  || { echo "FAIL: AC#7 missing 'archive boundary' separator"; cat "$OUT"; exit 1; }
# Archive events should appear BEFORE the live events.
LINE_ARCH=$(grep -n "2026-06-09T12:00:00Z" "$OUT" | head -1 | cut -d: -f1)
LINE_LIVE=$(grep -n "2026-06-13T09:37:09Z" "$OUT" | head -1 | cut -d: -f1)
if [ -z "$LINE_ARCH" ] || [ -z "$LINE_LIVE" ]; then
  echo "FAIL: AC#7 expected archive + live timestamps in render"; cat "$OUT"; exit 1
fi
if [ "$LINE_ARCH" -ge "$LINE_LIVE" ]; then
  echo "FAIL: AC#7 archive timestamps should precede live (got arch=$LINE_ARCH live=$LINE_LIVE)"
  cat "$OUT"; exit 1
fi
echo "  ok"

# ========================================================================
# AC #8 — `--type <name>` filters to one event type across the channel.
# ========================================================================
echo "AC#8 — --type filter"
# Reuse footer fixture (multi-type).
rm -rf "$CACHE"
mkdir -p "$CACHE"
cp "$FIXTURE_DIR/events-footer.jsonl" "$CACHE/events.jsonl"
OUT="$TMP/ac8.out"
"$FLEET" tour --type lesson_draft_emitted "$FIXTURE_ROOT/demo" > "$OUT"
grep -qF -- "lesson_draft_emitted" "$OUT" \
  || { echo "FAIL: AC#8 --type lesson_draft_emitted output missing the type name"; cat "$OUT"; exit 1; }
# Should NOT contain run_started / ship_paused / infra_flake_rerun blocks.
N_OTHER="$(awk '/^\[[0-9]+\]/ && !/lesson_draft_emitted/ { n++ } END { print n+0 }' "$OUT")"
if [ "$N_OTHER" -gt 0 ]; then
  echo "FAIL: AC#8 --type filter included $N_OTHER non-matching blocks"
  cat "$OUT"; exit 1
fi
echo "  ok"

# ========================================================================
# AC #9 — `--json` emits one JSON object per annotated event with the
#         required keys.
# ========================================================================
echo "AC#9 — --json shape"
cp "$FIXTURE_DIR/events-basic.jsonl" "$CACHE/events.jsonl"
OUT="$TMP/ac9.json"
"$FLEET" tour --json "$FIXTURE_ROOT/demo" > "$OUT"
node -e '
  const fs = require("fs");
  const text = fs.readFileSync(process.argv[1], "utf8").trim();
  const lines = text.split("\n").filter(s => s.length > 0);
  if (lines.length !== 4) {
    console.error("FAIL: AC#9 expected 4 JSON lines, got " + lines.length);
    console.error(text);
    process.exit(1);
  }
  for (const l of lines) {
    const o = JSON.parse(l);
    for (const k of ["idx","ts","type","fields","principle_id","principle_title","gloss","why_exists","fold_count"]) {
      if (!(k in o)) {
        console.error("FAIL: AC#9 JSON missing key " + k + " in: " + l);
        process.exit(1);
      }
    }
    if (typeof o.idx !== "number") {
      console.error("FAIL: AC#9 idx not number in: " + l);
      process.exit(1);
    }
    if (!/^P-[0-9]+$/.test(o.principle_id)) {
      console.error("FAIL: AC#9 principle_id format = " + o.principle_id);
      process.exit(1);
    }
  }
' "$OUT"
echo "  ok"

# ========================================================================
# AC #10 — `--help` prints USAGE mentioning the optional repo arg,
#          `--archive`, `--type`, `--json`. exit 0. Per LESSONS 2026-06-01
#          help must NOT fall through to fleet status.
# ========================================================================
echo "AC#10 — --help banner"
OUT="$TMP/ac10.out"
set +e
"$FLEET" tour --help > "$OUT" 2>&1
HEXIT=$?
set -e
if [ "$HEXIT" != "0" ]; then
  echo "FAIL: AC#10 --help exit $HEXIT (want 0)"; cat "$OUT"; exit 1
fi
for kw in "<repo>" "--archive" "--type" "--json"; do
  grep -qF -- "$kw" "$OUT" \
    || { echo "FAIL: AC#10 --help missing keyword '$kw'"; cat "$OUT"; exit 1; }
done
if grep -qE '^PROJECT[[:space:]]+INSTALLED' "$OUT"; then
  echo "FAIL: AC#10 --help fell through to fleet status (LESSONS 2026-06-01)"
  cat "$OUT"; exit 1
fi
echo "  ok"

# ========================================================================
# AC #11 — Empty events.jsonl → hint about next :37 ship cycle.
# ========================================================================
echo "AC#11 — empty channel hint"
: > "$CACHE/events.jsonl"
OUT="$TMP/ac11.out"
set +e
"$FLEET" tour "$FIXTURE_ROOT/demo" > "$OUT" 2>&1
EEXIT=$?
set -e
if [ "$EEXIT" != "0" ]; then
  echo "FAIL: AC#11 empty-channel exit $EEXIT (want 0)"; cat "$OUT"; exit 1
fi
grep -qF -- "events.jsonl is empty" "$OUT" \
  || { echo "FAIL: AC#11 missing 'events.jsonl is empty' hint"; cat "$OUT"; exit 1; }
grep -qF -- ":37" "$OUT" \
  || { echo "FAIL: AC#11 empty-hint should mention ':37'"; cat "$OUT"; exit 1; }
grep -qF -- "fleet kickstart --demo" "$OUT" \
  || { echo "FAIL: AC#11 empty-hint should mention 'fleet kickstart --demo'"; cat "$OUT"; exit 1; }
echo "  ok"

# ========================================================================
# AC #12 — Unknown event type renders gracefully (not in catalog yet) and
#          keeps walking.
# ========================================================================
echo "AC#12 — unknown event type does not abort the walk"
cp "$FIXTURE_DIR/events-unknown.jsonl" "$CACHE/events.jsonl"
OUT="$TMP/ac12.out"
set +e
"$FLEET" tour "$FIXTURE_ROOT/demo" > "$OUT" 2>&1
UEXIT=$?
set -e
if [ "$UEXIT" != "0" ]; then
  echo "FAIL: AC#12 unknown-type exit $UEXIT (want 0)"; cat "$OUT"; exit 1
fi
grep -qF -- "some_future_event" "$OUT" \
  || { echo "FAIL: AC#12 should show the unknown type name"; cat "$OUT"; exit 1; }
grep -qF -- "not in the catalog yet" "$OUT" \
  || { echo "FAIL: AC#12 should explain 'not in the catalog yet'"; cat "$OUT"; exit 1; }
# Walk should continue past the unknown — run_completed should still annotate.
grep -qF -- "run_completed" "$OUT" \
  || { echo "FAIL: AC#12 walk should continue past unknown event"; cat "$OUT"; exit 1; }
echo "  ok"

# ========================================================================
# AC #13 — tour is a PURE READER. events.jsonl byte size unchanged across
#          invocations. Also assert no fleet_emit_event calls happened by
#          confirming the channel was not written.
# ========================================================================
echo "AC#13 — tour is read-only"
cp "$FIXTURE_DIR/events-basic.jsonl" "$CACHE/events.jsonl"
SIZE_PRE="$(events_size "$CACHE/events.jsonl")"
"$FLEET" tour "$FIXTURE_ROOT/demo" > /dev/null
"$FLEET" tour --json "$FIXTURE_ROOT/demo" > /dev/null
"$FLEET" tour --archive "$FIXTURE_ROOT/demo" > /dev/null
"$FLEET" tour --type run_started "$FIXTURE_ROOT/demo" > /dev/null
SIZE_POST="$(events_size "$CACHE/events.jsonl")"
if [ "$SIZE_PRE" != "$SIZE_POST" ]; then
  echo "FAIL: AC#13 events.jsonl size changed: pre=$SIZE_PRE post=$SIZE_POST"
  exit 1
fi
echo "  ok (size $SIZE_PRE bytes, unchanged)"

# ========================================================================
# AC #14 — lib/common.sh unchanged on this branch.
# ========================================================================
echo "AC#14 — lib/common.sh untouched"
if git -C "$REPO_ROOT" rev-parse --verify main >/dev/null 2>&1; then
  CHG="$(git -C "$REPO_ROOT" diff --name-only main...HEAD -- lib/common.sh 2>/dev/null || true)"
  if [ -n "$CHG" ]; then
    echo "FAIL: AC#14 lib/common.sh changed: $CHG"; exit 1
  fi
fi
echo "  ok"

# ========================================================================
# AC #15 — prompts/ unchanged on this branch.
# ========================================================================
echo "AC#15 — prompts/ untouched"
if git -C "$REPO_ROOT" rev-parse --verify main >/dev/null 2>&1; then
  CHG="$(git -C "$REPO_ROOT" diff --name-only main...HEAD -- prompts/ 2>/dev/null || true)"
  if [ -n "$CHG" ]; then
    echo "FAIL: AC#15 prompts/ changed: $CHG"; exit 1
  fi
fi
echo "  ok"

# Sanity: total byte size of demo events channel pre-test = post-test.
SIZE_AFTER="$(events_size "$CACHE/events.jsonl")"
if [ "$SIZE_AFTER" -le 0 ]; then
  echo "FAIL: extra: cache channel empty after suite"; exit 1
fi

echo
echo "ALL tour tests passed."
