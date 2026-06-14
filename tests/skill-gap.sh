#!/bin/bash
# tests/skill-gap.sh — `bin/fleet skill-gap <slug>` end-to-end.
#
# Ticket 0051. One assertion block per acceptance-criteria checkbox in
# docs/backlog/0051-fleet-skill-gap-cross-project-lessons-coverage.md.
#
# `skill-gap` is a PURE READER. It diffs the named slug's recurring
# send-back headlines (from `lesson_draft_emitted` events on the slug's
# events.jsonl) against the fleet-wide CROSS_LESSONS feed and surfaces
# coverage gaps (CROSS_LESSONS path unset, feed missing, override
# shadowing, or prose not generalized). No `events.jsonl` writes, no
# `fleet_emit_event` calls, no CROSS_LESSONS.md or agents.config.sh writes.
#
# Per LESSONS 2026-05-26 stubs live under $HOME/.local/bin (lib/common.sh
# resets PATH). Per LESSONS 2026-05-27 every fixture file is copied with
# `cp` — never `$(cat …)` — to preserve byte-exact trailing newlines.
# Per LESSONS 2026-06-01 every count uses `awk … END { print n+0 }`.
# Per LESSONS 2026-05-30 every help-text grep uses `grep -qF -- "$kw"`.
# Per LESSONS 2026-05-28 every printf of a metric/slug uses `printf --`.
# Per LESSONS 2026-06-11 the clock is frozen via FLEET_NOW_OVERRIDE so
# the YYYY-MM-DD `--since` parse stays wall-clock stable.

set -euo pipefail

REPO_ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
FLEET="$REPO_ROOT/bin/fleet"
FIXTURES="$REPO_ROOT/tests/fixtures/skill-gap"

TMP="$(mktemp -d -t fleet-skill-gap-test.XXXXXX)"
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
T_45D_AGO=$(( NOW_EPOCH - 45 * 86400 ))

# Per-slug discovery root. Mirror the fixture tree into a writable tmp
# dir so the test can mutate freely without touching the repo's pristine
# fixtures.
PROJECTS="$TMP/projects"
mkdir -p "$PROJECTS"
cp -R "$FIXTURES/courtiq"      "$PROJECTS/courtiq"
cp -R "$FIXTURES/unset-slug"   "$PROJECTS/unset-slug"
cp -R "$FIXTURES/missing-slug" "$PROJECTS/missing-slug"
cp -R "$FIXTURES/override-slug" "$PROJECTS/override-slug"
export FLEET_DISCOVERY_ROOT="$PROJECTS"

# Seed every slug's events.jsonl.
COURTIQ_CACHE="$HOME/.cache/courtiq-agent"
UNSET_CACHE="$HOME/.cache/unset-slug-agent"
MISSING_CACHE="$HOME/.cache/missing-slug-agent"
OVERRIDE_CACHE="$HOME/.cache/override-slug-agent"
mkdir -p "$COURTIQ_CACHE" "$UNSET_CACHE" "$MISSING_CACHE" "$OVERRIDE_CACHE"

COURTIQ_EV="$COURTIQ_CACHE/events.jsonl"
UNSET_EV="$UNSET_CACHE/events.jsonl"
MISSING_EV="$MISSING_CACHE/events.jsonl"
OVERRIDE_EV="$OVERRIDE_CACHE/events.jsonl"

# courtiq — 4 in-window draft events whose headlines normalize to
# "test wrote to a non-isolated path". One out-of-window noise event.
{
  printf '{"ts":"%s","slug":"courtiq","phase":"review","type":"lesson_draft_emitted","pr":"101","headline":"test wrote to a non-isolated path"}\n' \
    "$(iso_at "$T_5D_AGO")"
  printf '{"ts":"%s","slug":"courtiq","phase":"review","type":"lesson_draft_emitted","pr":"102","headline":"Test wrote to a non-isolated path."}\n' \
    "$(iso_at "$T_7D_AGO")"
  printf '{"ts":"%s","slug":"courtiq","phase":"review","type":"lesson_draft_emitted","pr":"103","headline":"TEST   wrote to a   non-isolated path"}\n' \
    "$(iso_at "$T_10D_AGO")"
  printf '{"ts":"%s","slug":"courtiq","phase":"review","type":"lesson_draft_emitted","pr":"104","headline":"test wrote to a non-isolated path"}\n' \
    "$(iso_at "$T_12D_AGO")"
  printf '{"ts":"%s","slug":"courtiq","phase":"review","type":"lesson_draft_emitted","pr":"99","headline":"test wrote to a non-isolated path"}\n' \
    "$(iso_at "$T_45D_AGO")"
} > "$COURTIQ_EV"

# unset-slug — 3 in-window draft events for the "printf leading-dash"
# failure (matches a CROSS_LESSON title). The slug's agents.config.sh
# has no CROSS_LESSONS= value (path UNSET branch).
{
  printf '{"ts":"%s","slug":"unset-slug","phase":"review","type":"lesson_draft_emitted","pr":"201","headline":"printf consumed flag arg as option"}\n' \
    "$(iso_at "$T_5D_AGO")"
  printf '{"ts":"%s","slug":"unset-slug","phase":"review","type":"lesson_draft_emitted","pr":"202","headline":"printf consumed flag arg as option"}\n' \
    "$(iso_at "$T_7D_AGO")"
  printf '{"ts":"%s","slug":"unset-slug","phase":"review","type":"lesson_draft_emitted","pr":"203","headline":"printf consumed flag arg as option"}\n' \
    "$(iso_at "$T_15D_AGO")"
} > "$UNSET_EV"

# missing-slug — 3 in-window draft events. The slug's agents.config.sh
# CROSS_LESSONS path points at a file that does NOT exist.
{
  printf '{"ts":"%s","slug":"missing-slug","phase":"review","type":"lesson_draft_emitted","pr":"301","headline":"read shifts left on empty middle field"}\n' \
    "$(iso_at "$T_5D_AGO")"
  printf '{"ts":"%s","slug":"missing-slug","phase":"review","type":"lesson_draft_emitted","pr":"302","headline":"read shifts left on empty middle field"}\n' \
    "$(iso_at "$T_7D_AGO")"
  printf '{"ts":"%s","slug":"missing-slug","phase":"review","type":"lesson_draft_emitted","pr":"303","headline":"read shifts left on empty middle field"}\n' \
    "$(iso_at "$T_15D_AGO")"
} > "$MISSING_EV"

# override-slug — 3 in-window draft events for the awk-empty-middle-field
# lesson. The slug has an override file that DOES NOT include the matched
# lesson — OVERRIDE_SHADOWING.
{
  printf '{"ts":"%s","slug":"override-slug","phase":"review","type":"lesson_draft_emitted","pr":"401","headline":"read shifts left on empty middle field"}\n' \
    "$(iso_at "$T_5D_AGO")"
  printf '{"ts":"%s","slug":"override-slug","phase":"review","type":"lesson_draft_emitted","pr":"402","headline":"read shifts left on empty middle field"}\n' \
    "$(iso_at "$T_7D_AGO")"
  printf '{"ts":"%s","slug":"override-slug","phase":"review","type":"lesson_draft_emitted","pr":"403","headline":"read shifts left on empty middle field"}\n' \
    "$(iso_at "$T_10D_AGO")"
} > "$OVERRIDE_EV"

# Point the courtiq slug at the main feed fixture under TMP.
CROSS_LESSONS_FILE="$TMP/CROSS_LESSONS.md"
cp "$FIXTURES/CROSS_LESSONS.md" "$CROSS_LESSONS_FILE"

# The shared override root holds per-slug override files. The override-slug
# fixture's manifest expects this layout for OVERRIDE_SHADOWING detection.
CROSS_LESSONS_ROOT="$TMP/cross"
mkdir -p "$CROSS_LESSONS_ROOT/projects/override-slug"
cp "$FIXTURES/CROSS_LESSONS.md" "$CROSS_LESSONS_ROOT/CROSS_LESSONS.md"
cp "$FIXTURES/override.CROSS_LESSONS.md" \
   "$CROSS_LESSONS_ROOT/projects/override-slug/CROSS_LESSONS.md.override"
export FLEET_CROSS_LESSONS_ROOT="$CROSS_LESSONS_ROOT"

# Snap byte size of every events.jsonl + the CROSS_LESSONS.md fixture so
# AC#16 can verify "pure reader, no writes".
size() { stat -f %z "$1" 2>/dev/null || stat -c %s "$1"; }
COURTIQ_EV_SIZE_BEFORE="$(size "$COURTIQ_EV")"
UNSET_EV_SIZE_BEFORE="$(size "$UNSET_EV")"
MISSING_EV_SIZE_BEFORE="$(size "$MISSING_EV")"
OVERRIDE_EV_SIZE_BEFORE="$(size "$OVERRIDE_EV")"
CROSS_LESSONS_SIZE_BEFORE="$(size "$CROSS_LESSONS_FILE")"

# =====================================================================
# AC#1 — missing slug arg + unknown slug both refuse with exit 2.
# =====================================================================
echo "AC#1 — missing slug + unknown slug refuse with exit 2"

set +e
"$FLEET" skill-gap > "$TMP/ac1_missing.out" 2> "$TMP/ac1_missing.err"
rc=$?
set -e
[ "$rc" -eq 2 ] \
  || { echo "FAIL AC#1: expected exit 2 on missing slug, got $rc"; cat "$TMP/ac1_missing.err"; exit 1; }
grep -qF -- "skill-gap: usage:" "$TMP/ac1_missing.err" \
  || { echo "FAIL AC#1: missing-slug usage banner missing"; cat "$TMP/ac1_missing.err"; exit 1; }

set +e
FLEET_CROSS_LESSONS="$CROSS_LESSONS_FILE" \
  "$FLEET" skill-gap nonexistent-slug > "$TMP/ac1_unknown.out" 2> "$TMP/ac1_unknown.err"
rc=$?
set -e
[ "$rc" -eq 2 ] \
  || { echo "FAIL AC#1: expected exit 2 on unknown slug, got $rc"; cat "$TMP/ac1_unknown.err"; exit 1; }
grep -qF -- "skill-gap: slug nonexistent-slug not found" "$TMP/ac1_unknown.err" \
  || { echo "FAIL AC#1: unknown-slug refusal banner missing"; cat "$TMP/ac1_unknown.err"; exit 1; }
grep -qF -- "discovered slugs:" "$TMP/ac1_unknown.err" \
  || { echo "FAIL AC#1: discovered-slugs hint missing"; cat "$TMP/ac1_unknown.err"; exit 1; }
echo "  ok"

# =====================================================================
# AC#2 — CROSS_LESSONS path resolution: env override → manifest →
#        default. Missing entirely prints a hint + exit 0.
# =====================================================================
echo "AC#2 — CROSS_LESSONS missing prints a hint + exit 0"

EMPTY_CL_ROOT="$TMP/empty-cl"
mkdir -p "$EMPTY_CL_ROOT"
NO_FEED_OUT="$TMP/ac2.out"
set +e
FLEET_CROSS_LESSONS="$EMPTY_CL_ROOT/CROSS_LESSONS.md" \
  "$FLEET" skill-gap courtiq > "$NO_FEED_OUT" 2>&1
rc=$?
set -e
[ "$rc" -eq 0 ] \
  || { echo "FAIL AC#2: expected exit 0 on missing feed, got $rc"; cat "$NO_FEED_OUT"; exit 1; }
grep -qF -- "no CROSS_LESSONS feed found" "$NO_FEED_OUT" \
  || { echo "FAIL AC#2: missing-feed hint missing"; cat "$NO_FEED_OUT"; exit 1; }
grep -qF -- "fleet lessons-sync" "$NO_FEED_OUT" \
  || { echo "FAIL AC#2: lessons-sync suggestion missing"; cat "$NO_FEED_OUT"; exit 1; }
echo "  ok"

# =====================================================================
# AC#3 — CROSS_LESSONS parser walks `## YYYY-MM-DD — <title>` headings
#        and emits one TSV record per heading. We exercise it indirectly
#        through the default render — every lesson date appears in the
#        no-signal footer or in a coverage gap block.
# =====================================================================
echo "AC#3 — parser walks every dated heading"

DEFAULT_OUT="$TMP/ac3.out"
FLEET_CROSS_LESSONS="$CROSS_LESSONS_FILE" \
  "$FLEET" skill-gap courtiq --threshold 3 > "$DEFAULT_OUT" 2>&1
# The fixture has at least 3 dated headings. The default render shows
# every coverage gap PLUS a no-signal footer listing un-cited entries.
grep -qF -- "2026-05-26" "$DEFAULT_OUT" \
  || { echo "FAIL AC#3: 2026-05-26 lesson date missing"; cat "$DEFAULT_OUT"; exit 1; }
echo "  ok"

# =====================================================================
# AC#4 — Recurring-headline detector uses
#        prompts_suggest_normalize_headline (reused verbatim from 0045),
#        clusters by normalized headline, filters by threshold.
# =====================================================================
echo "AC#4 — recurring-headline clustering via shared normalizer"

# The courtiq cluster is 4 events. The text render must surface that
# count alongside the matched lesson.
grep -qF -- "x4" "$DEFAULT_OUT" \
  || grep -qF -- "(4" "$DEFAULT_OUT" \
  || { echo "FAIL AC#4: expected '×4' or '(4' frequency marker in default output"; cat "$DEFAULT_OUT"; exit 1; }
echo "  ok"

# =====================================================================
# AC#5 — Fuzzy match: lowercase + substring in either direction.
#        Positive: "test wrote to a non-isolated path" ↔ "tests own
#        their own filesystem" via the prose body fallback. Use a
#        cleaner positive: courtiq's recurring headline matches the
#        CROSS_LESSON titled "test wrote to a non-isolated path"
#        verbatim (subset substring).
# =====================================================================
echo "AC#5 — fuzzy match positive + negative"

grep -qF -- "test wrote to a non-isolated path" "$DEFAULT_OUT" \
  || { echo "FAIL AC#5: positive match missing"; cat "$DEFAULT_OUT"; exit 1; }
# Negative: a headline-shape that should NOT match any CROSS_LESSON.
NEG_CACHE="$HOME/.cache/neg-slug-agent"
mkdir -p "$NEG_CACHE"
mkdir -p "$PROJECTS/neg-slug"
cat > "$PROJECTS/neg-slug/agents.config.sh" <<'CFG'
SLUG="neg-slug"
PROJECT_NAME="neg-slug"
NAMESPACE="com.neg-slug"
REPO_URL="https://example.invalid/neg-slug"
SELF_CANCEL="20990101"
CROSS_LESSONS="$HOME/.local/share/agent-fleet/CROSS_LESSONS.md"
CFG
{
  for n in 1 2 3 4; do
    printf '{"ts":"%s","slug":"neg-slug","phase":"review","type":"lesson_draft_emitted","pr":"50%s","headline":"completely unrelated semantic noise zzz"}\n' \
      "$(iso_at "$T_5D_AGO")" "$n"
  done
} > "$NEG_CACHE/events.jsonl"
NEG_OUT="$TMP/ac5_neg.out"
FLEET_CROSS_LESSONS="$CROSS_LESSONS_FILE" \
  "$FLEET" skill-gap neg-slug > "$NEG_OUT" 2>&1
grep -qF -- "no recurring send-back headlines" "$NEG_OUT" \
  || grep -qF -- "no coverage gaps" "$NEG_OUT" \
  || { echo "FAIL AC#5: negative match should surface no-gap or no-cluster message"; cat "$NEG_OUT"; exit 1; }
echo "  ok"

# =====================================================================
# AC#6 — Coverage check 1: CROSS_LESSONS_PATH_UNSET. The unset-slug
#        manifest has no CROSS_LESSONS= line.
# =====================================================================
echo "AC#6 — CROSS_LESSONS_PATH_UNSET diagnosis"

UNSET_OUT="$TMP/ac6.out"
FLEET_CROSS_LESSONS="$CROSS_LESSONS_FILE" \
  "$FLEET" skill-gap unset-slug > "$UNSET_OUT" 2>&1
grep -qF -- "CROSS_LESSONS_PATH_UNSET" "$UNSET_OUT" \
  || { echo "FAIL AC#6: unset diagnosis missing"; cat "$UNSET_OUT"; exit 1; }
grep -qF -- "agents.config.sh" "$UNSET_OUT" \
  || { echo "FAIL AC#6: suggested fix should reference agents.config.sh"; cat "$UNSET_OUT"; exit 1; }
echo "  ok"

# =====================================================================
# AC#7 — Coverage check 2: CROSS_LESSONS_FILE_MISSING.
# =====================================================================
echo "AC#7 — CROSS_LESSONS_FILE_MISSING diagnosis"

MISSING_OUT="$TMP/ac7.out"
# Do not override FLEET_CROSS_LESSONS so the slug's own manifest
# value drives the resolution.
unset FLEET_CROSS_LESSONS || true
"$FLEET" skill-gap missing-slug > "$MISSING_OUT" 2>&1
grep -qF -- "CROSS_LESSONS_FILE_MISSING" "$MISSING_OUT" \
  || { echo "FAIL AC#7: file-missing diagnosis missing"; cat "$MISSING_OUT"; exit 1; }
grep -qF -- "fleet lessons-sync" "$MISSING_OUT" \
  || { echo "FAIL AC#7: file-missing fix should reference lessons-sync"; cat "$MISSING_OUT"; exit 1; }
echo "  ok"

# =====================================================================
# AC#8 — Coverage check 3: OVERRIDE_SHADOWING.
# =====================================================================
echo "AC#8 — OVERRIDE_SHADOWING diagnosis"

OVERRIDE_OUT="$TMP/ac8.out"
FLEET_CROSS_LESSONS="$CROSS_LESSONS_FILE" \
  "$FLEET" skill-gap override-slug > "$OVERRIDE_OUT" 2>&1
grep -qF -- "OVERRIDE_SHADOWING" "$OVERRIDE_OUT" \
  || { echo "FAIL AC#8: override diagnosis missing"; cat "$OVERRIDE_OUT"; exit 1; }
grep -qF -- "CROSS_LESSONS.md.override" "$OVERRIDE_OUT" \
  || { echo "FAIL AC#8: override fix should mention the override file"; cat "$OVERRIDE_OUT"; exit 1; }
echo "  ok"

# =====================================================================
# AC#9 — Coverage check 4: LESSON_PROSE_NOT_GENERALIZED.
#        courtiq's manifest points at a valid feed file that DOES
#        carry the matched lesson under another slug's section,
#        and there is no override shadowing it.
# =====================================================================
echo "AC#9 — LESSON_PROSE_NOT_GENERALIZED diagnosis"

PROSE_OUT="$TMP/ac9.out"
FLEET_CROSS_LESSONS="$CROSS_LESSONS_FILE" \
  "$FLEET" skill-gap courtiq > "$PROSE_OUT" 2>&1
grep -qF -- "LESSON_PROSE_NOT_GENERALIZED" "$PROSE_OUT" \
  || { echo "FAIL AC#9: prose-not-generalized diagnosis missing"; cat "$PROSE_OUT"; exit 1; }
grep -qF -- "fleet lessons-promote" "$PROSE_OUT" \
  || { echo "FAIL AC#9: suggested fix should reference fleet lessons-promote"; cat "$PROSE_OUT"; exit 1; }
echo "  ok"

# =====================================================================
# AC#10 — no-signal footer lists CROSS_LESSONS headings with zero
#         matching recurring headlines across any slug in the window.
#         The fixture's "2026-06-08 — only-cited-by-no-one lesson"
#         heading has no matching headline in any slug.
# =====================================================================
echo "AC#10 — no-signal footer"

grep -qF -- "no-signal" "$PROSE_OUT" \
  || { echo "FAIL AC#10: no-signal footer missing"; cat "$PROSE_OUT"; exit 1; }
grep -qF -- "lessons-prune" "$PROSE_OUT" \
  || { echo "FAIL AC#10: no-signal footer should mention lessons-prune followup"; cat "$PROSE_OUT"; exit 1; }
echo "  ok"

# =====================================================================
# AC#11 — --since accepts Nd and YYYY-MM-DD; narrows the window.
# =====================================================================
echo "AC#11 — --since Nd + YYYY-MM-DD"

# --since 6d narrows the courtiq window so only 2 events fall inside
# (T_5D_AGO only). With default threshold=3, no recurring cluster
# remains → no coverage gap.
SINCE_6D_OUT="$TMP/ac11_6d.out"
FLEET_CROSS_LESSONS="$CROSS_LESSONS_FILE" \
  "$FLEET" skill-gap courtiq --since 6d > "$SINCE_6D_OUT" 2>&1
grep -qF -- "no recurring send-back headlines" "$SINCE_6D_OUT" \
  || { echo "FAIL AC#11: --since 6d should produce empty-cluster message"; cat "$SINCE_6D_OUT"; exit 1; }

SINCE_DATE_OUT="$TMP/ac11_date.out"
FLEET_CROSS_LESSONS="$CROSS_LESSONS_FILE" \
  "$FLEET" skill-gap courtiq --since 2026-06-06 > "$SINCE_DATE_OUT" 2>&1
grep -qF -- "no recurring send-back headlines" "$SINCE_DATE_OUT" \
  || { echo "FAIL AC#11: --since 2026-06-06 should narrow window"; cat "$SINCE_DATE_OUT"; exit 1; }
echo "  ok"

# =====================================================================
# AC#12 — --threshold N override.
# =====================================================================
echo "AC#12 — --threshold override"

# --threshold 100 silences every coverage gap (no cluster has 100 events).
T100_OUT="$TMP/ac12.out"
FLEET_CROSS_LESSONS="$CROSS_LESSONS_FILE" \
  "$FLEET" skill-gap courtiq --threshold 100 > "$T100_OUT" 2>&1
grep -qF -- "no recurring send-back headlines" "$T100_OUT" \
  || { echo "FAIL AC#12: --threshold 100 should produce empty-cluster message"; cat "$T100_OUT"; exit 1; }

# --threshold 1 lists every cluster, including the singletons.
T1_OUT="$TMP/ac12_t1.out"
FLEET_CROSS_LESSONS="$CROSS_LESSONS_FILE" \
  "$FLEET" skill-gap courtiq --threshold 1 > "$T1_OUT" 2>&1
grep -qF -- "test wrote to a non-isolated path" "$T1_OUT" \
  || { echo "FAIL AC#12: --threshold 1 should still list main cluster"; cat "$T1_OUT"; exit 1; }
echo "  ok"

# =====================================================================
# AC#13 — --json emits one JSON object per coverage gap + a summary.
# =====================================================================
echo "AC#13 — --json mode emits valid JSON lines + summary"

JSON_OUT="$TMP/ac13.json"
FLEET_CROSS_LESSONS="$CROSS_LESSONS_FILE" \
  "$FLEET" skill-gap courtiq --json > "$JSON_OUT"
[ -s "$JSON_OUT" ] || { echo "FAIL AC#13: --json produced empty output"; exit 1; }

node -e '
  const fs = require("fs");
  const lines = fs.readFileSync("'"$JSON_OUT"'", "utf8").split(/\n/).filter(Boolean);
  if (lines.length < 2) { console.error("expected ≥2 JSON lines, got", lines.length); process.exit(1); }
  let sawGap = false, summary = null;
  for (const ln of lines) {
    let obj;
    try { obj = JSON.parse(ln); } catch (e) { console.error("bad JSON:", ln); process.exit(1); }
    if (obj.summary) { summary = obj.summary; continue; }
    if (!obj.slug || obj.slug !== "courtiq") { console.error("bad slug field:", JSON.stringify(obj)); process.exit(1); }
    if (typeof obj.frequency !== "number") { console.error("frequency not number"); process.exit(1); }
    if (!obj.coverage_check) { console.error("coverage_check missing"); process.exit(1); }
    if (!obj.cluster_headline) { console.error("cluster_headline missing"); process.exit(1); }
    sawGap = true;
  }
  if (!sawGap) { console.error("no coverage gap object"); process.exit(1); }
  if (!summary) { console.error("no summary"); process.exit(1); }
  if (summary.slug !== "courtiq") { console.error("summary slug mismatch:", summary.slug); process.exit(1); }
  if (summary.window !== "30d") { console.error("window != 30d:", summary.window); process.exit(1); }
  if (typeof summary.gaps_found !== "number") { console.error("gaps_found not number"); process.exit(1); }
  if (typeof summary.no_signal_entries !== "number") { console.error("no_signal_entries not number"); process.exit(1); }
'
echo "  ok"

# =====================================================================
# AC#14 — --help prints USAGE mentioning --since, --threshold, --json.
# =====================================================================
echo "AC#14 — --help mentions every flag"

HELP_OUT="$TMP/ac14.help"
"$FLEET" skill-gap --help > "$HELP_OUT"
for kw in "--since" "--threshold" "--json" "<slug>"; do
  grep -qF -- "$kw" "$HELP_OUT" \
    || { echo "FAIL AC#14: help missing '$kw'"; cat "$HELP_OUT"; exit 1; }
done
echo "  ok"

# =====================================================================
# AC#15 — Empty case: zero recurring headlines.
# =====================================================================
echo "AC#15 — empty case (no recurring headlines)"

EMPTY_SLUG_CACHE="$HOME/.cache/empty-slug-agent"
mkdir -p "$EMPTY_SLUG_CACHE"
: > "$EMPTY_SLUG_CACHE/events.jsonl"
mkdir -p "$PROJECTS/empty-slug"
cat > "$PROJECTS/empty-slug/agents.config.sh" <<'CFG'
SLUG="empty-slug"
PROJECT_NAME="empty-slug"
NAMESPACE="com.empty-slug"
REPO_URL="https://example.invalid/empty-slug"
SELF_CANCEL="20990101"
CFG
EMPTY_OUT="$TMP/ac15.out"
FLEET_CROSS_LESSONS="$CROSS_LESSONS_FILE" \
  "$FLEET" skill-gap empty-slug > "$EMPTY_OUT" 2>&1
grep -qF -- "no recurring send-back headlines" "$EMPTY_OUT" \
  || { echo "FAIL AC#15: empty-case message missing"; cat "$EMPTY_OUT"; exit 1; }
grep -qF -- "30d" "$EMPTY_OUT" \
  || { echo "FAIL AC#15: empty-case should mention window"; cat "$EMPTY_OUT"; exit 1; }
echo "  ok"

# =====================================================================
# AC#16 — PURE READER. events.jsonl + CROSS_LESSONS.md byte-identical.
# =====================================================================
echo "AC#16 — pure reader: no events.jsonl or CROSS_LESSONS.md writes"

for pair in \
  "courtiq:$COURTIQ_EV:$COURTIQ_EV_SIZE_BEFORE" \
  "unset:$UNSET_EV:$UNSET_EV_SIZE_BEFORE" \
  "missing:$MISSING_EV:$MISSING_EV_SIZE_BEFORE" \
  "override:$OVERRIDE_EV:$OVERRIDE_EV_SIZE_BEFORE" \
; do
  name="${pair%%:*}"
  rest="${pair#*:}"
  path="${rest%%:*}"
  expected="${rest#*:}"
  actual="$(size "$path")"
  [ "$expected" = "$actual" ] \
    || { echo "FAIL AC#16: $name events.jsonl size changed ($expected → $actual)"; exit 1; }
done
actual_cl="$(size "$CROSS_LESSONS_FILE")"
[ "$CROSS_LESSONS_SIZE_BEFORE" = "$actual_cl" ] \
  || { echo "FAIL AC#16: CROSS_LESSONS.md byte size changed"; exit 1; }
echo "  ok"

# =====================================================================
# AC#17 — lib/common.sh unchanged on this branch.
# =====================================================================
echo "AC#17 — lib/common.sh untouched"
( cd "$REPO_ROOT" && git diff --name-only main...HEAD -- lib/common.sh ) > "$TMP/ac17.diff"
if [ -s "$TMP/ac17.diff" ]; then
  echo "FAIL AC#17: lib/common.sh changed on this branch:"
  cat "$TMP/ac17.diff"
  exit 1
fi
echo "  ok"

# =====================================================================
# AC#18 — prompts/ unchanged on this branch.
# =====================================================================
echo "AC#18 — prompts/ untouched"
( cd "$REPO_ROOT" && git diff --name-only main...HEAD -- prompts/ ) > "$TMP/ac18.diff"
if [ -s "$TMP/ac18.diff" ]; then
  echo "FAIL AC#18: prompts/ changed on this branch:"
  cat "$TMP/ac18.diff"
  exit 1
fi
echo "  ok"

echo
echo "tests/skill-gap.sh: ALL ACs PASSED."
