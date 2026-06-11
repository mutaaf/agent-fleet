#!/bin/bash
# tests/prompts-suggest.sh — `bin/fleet prompts-suggest` end-to-end.
#
# Ticket 0045. One assertion block per acceptance-criteria checkbox in
# docs/backlog/0045-fleet-prompts-suggest-closes-self-improvement-loop.md.
#
# `prompts-suggest` is a PURE READER of `lesson_draft_emitted` events
# across every discovered project's events.jsonl. It clusters by
# normalized headline, composes a candidate PRINCIPLES.md block from the
# matching `docs/LESSONS.md` paragraph, and (when applicable) proposes an
# EXPIRES marker on an existing principle whose recent send-backs are
# mis-cited. The command never writes — no `events.jsonl` writes, no
# `PRINCIPLES.md` writes, no `fleet_emit_event` calls.
#
# Fixtures: four synthetic projects seeded under FLEET_DISCOVERY_ROOT,
# plus a PRINCIPLES.md fixture pointed at via FLEET_PROMPTS_SUGGEST_
# PRINCIPLES_PATH. Time is pinned via FLEET_NOW_OVERRIDE so the
# rendered window header and every age stays deterministic. Run-time
# budget: <10s.
#
# Per LESSONS 2026-05-26 stubs live under $HOME/.local/bin (lib/common.sh
# resets PATH). Per LESSONS 2026-05-27 every fixture file is copied with
# `cp` — never `$(cat …)` — to preserve byte-exact trailing newlines.
# Per LESSONS 2026-06-01 every count uses `awk … END { print n+0 }`.
# Per LESSONS 2026-05-30 every help-text grep uses `grep -qF -- "$kw"`.
# Per LESSONS 2026-05-28 every printf of a metric/slug uses `printf --`.

set -euo pipefail

REPO_ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
FLEET="$REPO_ROOT/bin/fleet"
FIXTURES="$REPO_ROOT/tests/fixtures/prompts-suggest"

TMP="$(mktemp -d -t fleet-prompts-suggest-test.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

# Isolate HOME so $HOME/.cache, $HOME/.local/bin stay sandboxed.
export HOME="$TMP/home"
mkdir -p "$HOME/.local/bin"

# Stable epoch anchor: 2026-06-11T12:00:00Z.
NOW_EPOCH=1781179200
export FLEET_NOW_OVERRIDE="$NOW_EPOCH"

iso_at() {  # $1 = epoch seconds → "YYYY-MM-DDTHH:MM:SSZ"
  date -u -r "$1" +%FT%TZ 2>/dev/null || date -u -d "@$1" +%FT%TZ
}

T_5D_AGO=$((  NOW_EPOCH -  5 * 86400 ))
T_7D_AGO=$((  NOW_EPOCH -  7 * 86400 ))
T_10D_AGO=$(( NOW_EPOCH - 10 * 86400 ))
T_12D_AGO=$(( NOW_EPOCH - 12 * 86400 ))
T_15D_AGO=$(( NOW_EPOCH - 15 * 86400 ))
T_20D_AGO=$(( NOW_EPOCH - 20 * 86400 ))
T_45D_AGO=$(( NOW_EPOCH - 45 * 86400 ))

# Per-slug discovery root. Mirror the fixture tree into a writable tmp
# dir so the test can copy and mutate freely without touching the repo's
# pristine fixtures.
PROJECTS="$TMP/projects"
mkdir -p "$PROJECTS"
cp -R "$FIXTURES/alpha"   "$PROJECTS/alpha"
cp -R "$FIXTURES/bravo"   "$PROJECTS/bravo"
cp -R "$FIXTURES/charlie" "$PROJECTS/charlie"
cp -R "$FIXTURES/delta"   "$PROJECTS/delta"
export FLEET_DISCOVERY_ROOT="$PROJECTS"

# Point the composer at a writable copy of the PRINCIPLES.md fixture.
PRINCIPLES_DIR="$TMP/principles"
mkdir -p "$PRINCIPLES_DIR"
cp "$FIXTURES/principles/PRINCIPLES.md" "$PRINCIPLES_DIR/PRINCIPLES.md"
export FLEET_PROMPTS_SUGGEST_PRINCIPLES_PATH="$PRINCIPLES_DIR/PRINCIPLES.md"

# ---------------------------------------------------------------------------
# Seed events.jsonl per slug.
#
# alpha-fixture (4 events, normalized headline = "test wrote to a
#   non-isolated path"):
#     - one variant per LESSONS 2026-06-09 paragraph (extra whitespace,
#       trailing punctuation, mixed case, plain).
# bravo-fixture (3 events, SAME normalized headline as alpha — covers
#   the cross-slug cluster):
#     - one variant with a leading `pr=#NNN ` prefix that must be stripped.
# charlie-fixture (4 events, cite `P-6` in body but headline maps to a
#   different principle — covers AC#6 EXPIRES branch):
#     - normalized headline = "agent assumed claude cli was on path".
# delta-fixture (2 unique headlines, below threshold → silently dropped).
# ---------------------------------------------------------------------------

ALPHA_CACHE="$HOME/.cache/alpha-fixture-agent"
BRAVO_CACHE="$HOME/.cache/bravo-fixture-agent"
CHARLIE_CACHE="$HOME/.cache/charlie-fixture-agent"
DELTA_CACHE="$HOME/.cache/delta-fixture-agent"
mkdir -p "$ALPHA_CACHE" "$BRAVO_CACHE" "$CHARLIE_CACHE" "$DELTA_CACHE"

ALPHA_EV="$ALPHA_CACHE/events.jsonl"
BRAVO_EV="$BRAVO_CACHE/events.jsonl"
CHARLIE_EV="$CHARLIE_CACHE/events.jsonl"
DELTA_EV="$DELTA_CACHE/events.jsonl"

# alpha-fixture — 4 in-window events, varying surface form to exercise
# normalization. All four normalize to "test wrote to a non-isolated path".
{
  printf '{"ts":"%s","slug":"alpha-fixture","phase":"review","type":"lesson_draft_emitted","pr":"101","headline":"test wrote to a non-isolated path"}\n' \
    "$(iso_at "$T_5D_AGO")"
  printf '{"ts":"%s","slug":"alpha-fixture","phase":"review","type":"lesson_draft_emitted","pr":"102","headline":"Test wrote to a non-isolated path."}\n' \
    "$(iso_at "$T_7D_AGO")"
  printf '{"ts":"%s","slug":"alpha-fixture","phase":"review","type":"lesson_draft_emitted","pr":"103","headline":"TEST   wrote to a   non-isolated path"}\n' \
    "$(iso_at "$T_10D_AGO")"
  printf '{"ts":"%s","slug":"alpha-fixture","phase":"review","type":"lesson_draft_emitted","pr":"104","headline":"test wrote to a non-isolated path"}\n' \
    "$(iso_at "$T_12D_AGO")"
  # Out-of-window noise (45d ago — outside the 30d default).
  printf '{"ts":"%s","slug":"alpha-fixture","phase":"review","type":"lesson_draft_emitted","pr":"99","headline":"test wrote to a non-isolated path"}\n' \
    "$(iso_at "$T_45D_AGO")"
} > "$ALPHA_EV"

# bravo-fixture — 3 in-window events. One has a `pr=#202 ` prefix to test
# the AC#2 strip rule.
{
  printf '{"ts":"%s","slug":"bravo-fixture","phase":"review","type":"lesson_draft_emitted","pr":"201","headline":"test wrote to a non-isolated path"}\n' \
    "$(iso_at "$T_5D_AGO")"
  printf '{"ts":"%s","slug":"bravo-fixture","phase":"review","type":"lesson_draft_emitted","pr":"202","headline":"pr=#202 test wrote to a non-isolated path"}\n' \
    "$(iso_at "$T_7D_AGO")"
  printf '{"ts":"%s","slug":"bravo-fixture","phase":"review","type":"lesson_draft_emitted","pr":"203","headline":"test wrote to a non-isolated path"}\n' \
    "$(iso_at "$T_15D_AGO")"
} > "$BRAVO_EV"

# charlie-fixture — 4 in-window events. Headline normalizes to
# "agent assumed claude cli was on path" — semantically NOT about
# telemetry. Each event body mentions `P-6`, which is the existing
# principle the loop has been mis-citing. AC#6 EXPIRES-marker branch.
{
  printf '{"ts":"%s","slug":"charlie-fixture","phase":"review","type":"lesson_draft_emitted","pr":"301","headline":"agent assumed claude CLI was on PATH","body":"cited P-6 in send-back body"}\n' \
    "$(iso_at "$T_5D_AGO")"
  printf '{"ts":"%s","slug":"charlie-fixture","phase":"review","type":"lesson_draft_emitted","pr":"302","headline":"agent assumed claude cli was on path","body":"cited P-6 in send-back body"}\n' \
    "$(iso_at "$T_7D_AGO")"
  printf '{"ts":"%s","slug":"charlie-fixture","phase":"review","type":"lesson_draft_emitted","pr":"303","headline":"Agent assumed claude CLI was on PATH.","body":"cited P-6 in send-back body"}\n' \
    "$(iso_at "$T_10D_AGO")"
  printf '{"ts":"%s","slug":"charlie-fixture","phase":"review","type":"lesson_draft_emitted","pr":"304","headline":"agent assumed claude CLI was on PATH","body":"cited P-6 in send-back body"}\n' \
    "$(iso_at "$T_12D_AGO")"
} > "$CHARLIE_EV"

# delta-fixture — 2 in-window events with UNIQUE headlines (cluster=1 each).
{
  printf '{"ts":"%s","slug":"delta-fixture","phase":"review","type":"lesson_draft_emitted","pr":"401","headline":"unique headline alpha"}\n' \
    "$(iso_at "$T_5D_AGO")"
  printf '{"ts":"%s","slug":"delta-fixture","phase":"review","type":"lesson_draft_emitted","pr":"402","headline":"unique headline beta"}\n' \
    "$(iso_at "$T_7D_AGO")"
} > "$DELTA_EV"

# Snap byte size of every events.jsonl + the PRINCIPLES.md fixture so
# AC#10 can verify "pure reader, no writes".
size() { stat -f %z "$1" 2>/dev/null || stat -c %s "$1"; }
ALPHA_EV_SIZE_BEFORE="$(size "$ALPHA_EV")"
BRAVO_EV_SIZE_BEFORE="$(size "$BRAVO_EV")"
CHARLIE_EV_SIZE_BEFORE="$(size "$CHARLIE_EV")"
DELTA_EV_SIZE_BEFORE="$(size "$DELTA_EV")"
PRINCIPLES_SIZE_BEFORE="$(size "$PRINCIPLES_DIR/PRINCIPLES.md")"

# =====================================================================
# AC#1 — `bin/fleet prompts-suggest` with no flags renders the
#        candidates table over the default 30-day window.
# =====================================================================
echo "AC#1 — render candidates table over default 30-day window"

DEFAULT_OUT="$TMP/ac1.out"
DEFAULT_ERR="$TMP/ac1.err"
set +e
"$FLEET" prompts-suggest > "$DEFAULT_OUT" 2> "$DEFAULT_ERR"
rc=$?
set -e
[ "$rc" -eq 0 ] || { echo "FAIL AC#1: expected exit 0, got $rc"; cat "$DEFAULT_ERR"; exit 1; }
grep -qF -- "prompts-suggest:" "$DEFAULT_OUT" \
  || { echo "FAIL AC#1: banner line missing"; cat "$DEFAULT_OUT"; exit 1; }
grep -qF -- "FREQUENCY" "$DEFAULT_OUT" \
  || { echo "FAIL AC#1: FREQUENCY column missing"; cat "$DEFAULT_OUT"; exit 1; }
grep -qF -- "HEADLINE" "$DEFAULT_OUT" \
  || { echo "FAIL AC#1: HEADLINE column missing"; cat "$DEFAULT_OUT"; exit 1; }
echo "  ok"

# =====================================================================
# AC#2 — Headline normalization: lowercase, strip leading `pr=#N `
#        prefix, collapse whitespace, strip trailing punctuation.
#        alpha+bravo events (7 total in 30d window) all collapse into
#        ONE cluster.
# =====================================================================
echo "AC#2 — headline normalization clusters cross-slug variants"

# The alpha+bravo cluster is 4+3=7 events. The candidate FREQUENCY line
# must show "7".
grep -qF -- "FREQUENCY 7 " "$DEFAULT_OUT" \
  || { echo "FAIL AC#2: expected one cluster with FREQUENCY 7"; cat "$DEFAULT_OUT"; exit 1; }
# The normalized headline appears verbatim.
grep -qF -- 'HEADLINE: "test wrote to a non-isolated path"' "$DEFAULT_OUT" \
  || { echo "FAIL AC#2: expected normalized headline"; cat "$DEFAULT_OUT"; exit 1; }
# Per-slug breakdown shows both alpha-fixture (4) and bravo-fixture (3).
grep -qF -- "alpha-fixture (4)" "$DEFAULT_OUT" \
  || { echo "FAIL AC#2: per-slug breakdown missing alpha-fixture (4)"; cat "$DEFAULT_OUT"; exit 1; }
grep -qF -- "bravo-fixture (3)" "$DEFAULT_OUT" \
  || { echo "FAIL AC#2: per-slug breakdown missing bravo-fixture (3)"; cat "$DEFAULT_OUT"; exit 1; }
echo "  ok"

# =====================================================================
# AC#3 — Recurrence threshold is 3 events per cluster by default.
#        Clusters below threshold are silently dropped. --threshold 1
#        lists every cluster.
# =====================================================================
echo "AC#3 — recurrence threshold default 3 + override"

# delta-fixture's two unique headlines (each cluster=1) must NOT appear
# under the default threshold.
if grep -qF -- "unique headline alpha" "$DEFAULT_OUT"; then
  echo "FAIL AC#3: below-threshold cluster leaked into default output"
  cat "$DEFAULT_OUT"
  exit 1
fi
# The diagnostic surface — no "below threshold" listing.
if grep -qiF -- "below threshold" "$DEFAULT_OUT"; then
  echo "FAIL AC#3: silent-drop contract violated"
  cat "$DEFAULT_OUT"
  exit 1
fi

# --threshold 1 lists every cluster, including the delta singletons.
T1_OUT="$TMP/ac3_t1.out"
"$FLEET" prompts-suggest --threshold 1 > "$T1_OUT"
grep -qF -- "unique headline alpha" "$T1_OUT" \
  || { echo "FAIL AC#3: --threshold 1 should list 'unique headline alpha'"; cat "$T1_OUT"; exit 1; }
grep -qF -- "unique headline beta" "$T1_OUT" \
  || { echo "FAIL AC#3: --threshold 1 should list 'unique headline beta'"; cat "$T1_OUT"; exit 1; }
echo "  ok"

# =====================================================================
# AC#4 — --since accepts Nd and YYYY-MM-DD; default is 30d (NOT 14d).
# =====================================================================
echo "AC#4 — --since Nd + YYYY-MM-DD"

# --since 6d narrows the window so the alpha cluster drops below
# threshold (only 2 events fall inside 6d: the T_5D_AGO entries from
# alpha + bravo = 2 events). With default threshold=3, the cluster is
# silently dropped → "none recur" message.
SINCE_6D_OUT="$TMP/ac4_6d.out"
"$FLEET" prompts-suggest --since 6d > "$SINCE_6D_OUT"
grep -qF -- "none recur" "$SINCE_6D_OUT" \
  || { echo "FAIL AC#4: --since 6d should produce a 'none recur' diagnostic"; cat "$SINCE_6D_OUT"; exit 1; }

# YYYY-MM-DD form: 2026-06-06 → 5 days ago. Same narrowing.
SINCE_DATE_OUT="$TMP/ac4_date.out"
"$FLEET" prompts-suggest --since 2026-06-06 > "$SINCE_DATE_OUT"
grep -qF -- "none recur" "$SINCE_DATE_OUT" \
  || { echo "FAIL AC#4: --since 2026-06-06 should narrow window"; cat "$SINCE_DATE_OUT"; exit 1; }

# Default window header advertises 30d.
grep -qF -- "30d" "$DEFAULT_OUT" \
  || { echo "FAIL AC#4: default window must be 30d, not 14d"; cat "$DEFAULT_OUT"; exit 1; }
echo "  ok"

# =====================================================================
# AC#5 — PROPOSED ADDITION composed from the matching LESSONS.md
#        paragraph, under `## P-NEXT — <imperative title>` heading.
#        Next P-N = max existing + 1 (12 + 1 = 13 for our fixture).
# =====================================================================
echo "AC#5 — proposed addition composed from LESSONS paragraph"

grep -qF -- "PROPOSED ADDITION TO PRINCIPLES.md" "$DEFAULT_OUT" \
  || { echo "FAIL AC#5: missing 'PROPOSED ADDITION TO PRINCIPLES.md' label"; cat "$DEFAULT_OUT"; exit 1; }
grep -qF -- "## P-13 — Test Wrote To A Non-Isolated Path" "$DEFAULT_OUT" \
  || { echo "FAIL AC#5: expected '## P-13 — Test Wrote To A Non-Isolated Path' heading"; cat "$DEFAULT_OUT"; exit 1; }
# Body text from the alpha LESSONS paragraph appears verbatim.
grep -qF -- "mktemp -d" "$DEFAULT_OUT" \
  || { echo "FAIL AC#5: lesson body text missing from composed candidate"; cat "$DEFAULT_OUT"; exit 1; }
echo "  ok"

# =====================================================================
# AC#6 — EXPIRES-marker branch: charlie cluster cites P-6 ≥4 times
#        with a headline that semantically maps to a DIFFERENT
#        principle. Candidate proposes an EXPIRES marker on P-6.
# =====================================================================
echo "AC#6 — EXPIRES-marker branch on misciting principle"

# charlie cluster is 4 events.
grep -qF -- "agent assumed claude cli was on path" "$DEFAULT_OUT" \
  || { echo "FAIL AC#6: charlie cluster headline missing"; cat "$DEFAULT_OUT"; exit 1; }
grep -qF -- "PROPOSED EXPIRES on existing principle" "$DEFAULT_OUT" \
  || { echo "FAIL AC#6: EXPIRES proposal label missing"; cat "$DEFAULT_OUT"; exit 1; }
grep -qE -- "<!-- EXPIRES: [0-9]{4}-[0-9]{2}-[0-9]{2} -->" "$DEFAULT_OUT" \
  || { echo "FAIL AC#6: EXPIRES marker text missing"; cat "$DEFAULT_OUT"; exit 1; }
grep -qF -- "P-6" "$DEFAULT_OUT" \
  || { echo "FAIL AC#6: target principle P-6 missing from EXPIRES proposal"; cat "$DEFAULT_OUT"; exit 1; }
echo "  ok"

# =====================================================================
# AC#7 — --json emits one JSON object per candidate, then a summary
#        object. Validate via node.
# =====================================================================
echo "AC#7 — --json mode emits valid JSON lines + summary"

JSON_OUT="$TMP/ac7.json"
"$FLEET" prompts-suggest --json > "$JSON_OUT"
[ -s "$JSON_OUT" ] || { echo "FAIL AC#7: --json produced empty output"; exit 1; }

# Validate every line is JSON; the LAST line is the summary.
node -e '
  const fs = require("fs");
  const lines = fs.readFileSync("'"$JSON_OUT"'", "utf8").split(/\n/).filter(Boolean);
  if (lines.length < 2) { console.error("expected ≥2 JSON lines"); process.exit(1); }
  let sawAddition = false, sawExpires = false, summary = null;
  for (const ln of lines) {
    let obj;
    try { obj = JSON.parse(ln); } catch (e) { console.error("bad JSON:", ln); process.exit(1); }
    if (obj.summary) { summary = obj.summary; continue; }
    if (obj.kind === "addition") sawAddition = true;
    if (obj.kind === "expires")  sawExpires  = true;
    if (typeof obj.frequency !== "number") { console.error("frequency not number"); process.exit(1); }
    if (typeof obj.per_slug !== "object" || !obj.per_slug) { console.error("per_slug not object"); process.exit(1); }
  }
  if (!sawAddition) { console.error("no addition candidate"); process.exit(1); }
  if (!sawExpires)  { console.error("no expires candidate");  process.exit(1); }
  if (!summary) { console.error("no summary"); process.exit(1); }
  if (summary.window !== "30d") { console.error("window != 30d:", summary.window); process.exit(1); }
  if (summary.threshold !== 3) { console.error("threshold != 3"); process.exit(1); }
  if (summary.candidates_found < 2) { console.error("candidates_found < 2"); process.exit(1); }
  if (summary.principles_md_p_max !== 12) { console.error("principles_md_p_max != 12:", summary.principles_md_p_max); process.exit(1); }
'
echo "  ok"

# =====================================================================
# AC#8 — --help prints USAGE mentioning --since, --threshold, --json,
#        EXPIRES.
# =====================================================================
echo "AC#8 — --help mentions every flag + EXPIRES contract"

HELP_OUT="$TMP/ac8.help"
"$FLEET" prompts-suggest --help > "$HELP_OUT"
for kw in "--since" "--threshold" "--json" "EXPIRES"; do
  grep -qF -- "$kw" "$HELP_OUT" \
    || { echo "FAIL AC#8: help missing '$kw'"; cat "$HELP_OUT"; exit 1; }
done
# `-h` short flag works too.
HELP_SHORT_OUT="$TMP/ac8.help_short"
"$FLEET" prompts-suggest -h > "$HELP_SHORT_OUT"
[ -s "$HELP_SHORT_OUT" ] || { echo "FAIL AC#8: -h produced no output"; exit 1; }
echo "  ok"

# =====================================================================
# AC#9 — Three empty-state branches.
# =====================================================================
echo "AC#9 — three empty-state branches"

# Branch (a): empty fleet (zero projects discovered).
EMPTY_ROOT="$TMP/empty"
mkdir -p "$EMPTY_ROOT"
EMPTY_OUT="$TMP/ac9_empty.out"
FLEET_DISCOVERY_ROOT="$EMPTY_ROOT" "$FLEET" prompts-suggest > "$EMPTY_OUT"
grep -qF -- "no projects discovered" "$EMPTY_OUT" \
  || { echo "FAIL AC#9 (a): empty fleet branch missing"; cat "$EMPTY_OUT"; exit 1; }

# Branch (b): projects exist but zero events in window.
NOEV_ROOT="$TMP/noev"
mkdir -p "$NOEV_ROOT/quiet"
cp "$FIXTURES/alpha/agents.config.sh" "$NOEV_ROOT/quiet/agents.config.sh"
# Rewrite the SLUG so the cache is fresh + empty.
sed -i.bak 's/alpha-fixture/quiet-fixture/g' "$NOEV_ROOT/quiet/agents.config.sh"
rm -f "$NOEV_ROOT/quiet/agents.config.sh.bak"
mkdir -p "$HOME/.cache/quiet-fixture-agent"
: > "$HOME/.cache/quiet-fixture-agent/events.jsonl"
NOEV_OUT="$TMP/ac9_noev.out"
FLEET_DISCOVERY_ROOT="$NOEV_ROOT" "$FLEET" prompts-suggest > "$NOEV_OUT"
grep -qF -- "no lesson_draft_emitted events" "$NOEV_OUT" \
  || { echo "FAIL AC#9 (b): no-events branch missing"; cat "$NOEV_OUT"; exit 1; }

# Branch (c): events exist but none recur above threshold.
NOCLUSTER_OUT="$TMP/ac9_nocluster.out"
FLEET_DISCOVERY_ROOT="$PROJECTS" "$FLEET" prompts-suggest --threshold 20 > "$NOCLUSTER_OUT"
grep -qF -- "none recur" "$NOCLUSTER_OUT" \
  || { echo "FAIL AC#9 (c): no-clusters-above-threshold branch missing"; cat "$NOCLUSTER_OUT"; exit 1; }
echo "  ok"

# =====================================================================
# AC#10 — PURE READER. Every events.jsonl byte-size and the
#         PRINCIPLES.md byte-size is byte-identical before and after
#         every prompts-suggest invocation above.
# =====================================================================
echo "AC#10 — pure reader: no events.jsonl or PRINCIPLES.md writes"

for pair in \
  "alpha:$ALPHA_EV:$ALPHA_EV_SIZE_BEFORE" \
  "bravo:$BRAVO_EV:$BRAVO_EV_SIZE_BEFORE" \
  "charlie:$CHARLIE_EV:$CHARLIE_EV_SIZE_BEFORE" \
  "delta:$DELTA_EV:$DELTA_EV_SIZE_BEFORE" \
; do
  name="${pair%%:*}"
  rest="${pair#*:}"
  path="${rest%%:*}"
  expected="${rest#*:}"
  actual="$(size "$path")"
  [ "$expected" = "$actual" ] \
    || { echo "FAIL AC#10: $name events.jsonl size changed ($expected → $actual)"; exit 1; }
done

actual_principles="$(size "$PRINCIPLES_DIR/PRINCIPLES.md")"
[ "$PRINCIPLES_SIZE_BEFORE" = "$actual_principles" ] \
  || { echo "FAIL AC#10: PRINCIPLES.md byte size changed"; exit 1; }
echo "  ok"

# =====================================================================
# AC#11 — Composer NEVER suggests text whose source paragraph carries
#         a `<!-- DRAFT: ` marker. The bravo fixture's LESSONS.md has
#         a DRAFT-prefixed paragraph for the same headline as alpha's;
#         the composer must prefer alpha's (non-draft) version.
# =====================================================================
echo "AC#11 — composer filters DRAFT-marked paragraphs"

# The bravo DRAFT paragraph carries the literal "DRAFT paragraph that
# must NOT be used" — that string MUST NOT appear in the default render.
if grep -qF -- "DRAFT paragraph that must NOT be used" "$DEFAULT_OUT"; then
  echo "FAIL AC#11: DRAFT paragraph leaked into composed candidate"
  cat "$DEFAULT_OUT"
  exit 1
fi
echo "  ok"

# =====================================================================
# AC#12 — `lib/common.sh` unchanged on this branch.
# =====================================================================
echo "AC#12 — lib/common.sh untouched"
( cd "$REPO_ROOT" && git diff --name-only main...HEAD -- lib/common.sh ) > "$TMP/ac12.diff"
if [ -s "$TMP/ac12.diff" ]; then
  echo "FAIL AC#12: lib/common.sh changed on this branch:"
  cat "$TMP/ac12.diff"
  exit 1
fi
echo "  ok"

# =====================================================================
# AC#13 — `prompts/` unchanged on this branch.
# =====================================================================
echo "AC#13 — prompts/ untouched"
( cd "$REPO_ROOT" && git diff --name-only main...HEAD -- prompts/ ) > "$TMP/ac13.diff"
if [ -s "$TMP/ac13.diff" ]; then
  echo "FAIL AC#13: prompts/ changed on this branch:"
  cat "$TMP/ac13.diff"
  exit 1
fi
echo "  ok"

echo
echo "tests/prompts-suggest.sh: ALL ACs PASSED."
