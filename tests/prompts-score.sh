#!/bin/bash
# tests/prompts-score.sh — `fleet prompts-score` end-to-end against a
# synthetic events.jsonl + runs.jsonl fixture spanning three prompt
# revisions over 14 days.
#
# Ticket 0024. One assertion block per acceptance-criteria checkbox in
# docs/backlog/0024-fleet-prompts-score-effectiveness-from-events.md.
#
# Fixture shape — three SHAs in time order:
#
#   aaaaaa1 — pinned 14d ago via prompts_pin_changed (the bootstrap pin
#             on the project; carries no `old`)
#   bbbbbb2 — implicit at 7d ago via prompts_drift (pinned=aaaaaa1,
#             actual=bbbbbb2). Exercises the fallback path for projects
#             that never re-ran the updated install.sh.
#   ccccccc — pinned 2d ago via prompts_pin_changed (old=bbbbbb2,
#             new=ccccccc). The current revision.
#
# Runs and PR-related events are seeded inside each SHA's window so the
# per-row metrics are deterministic. Time anchored via
# FLEET_PROMPTS_SCORE_FAKE_NOW so the golden DATE column stays stable
# across runs.

set -euo pipefail

REPO_ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
FLEET="$REPO_ROOT/bin/fleet"

TMP="$(mktemp -d -t fleet-prompts-score-test.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

# Isolate HOME so the cache dir lands under $TMP (per LESSONS 2026-05-26).
export HOME="$TMP/home"
mkdir -p "$HOME/.local/bin"
export PATH="$HOME/.local/bin:$PATH"

SLUG="scoretest"
CACHE_DIR="$HOME/.cache/${SLUG}-agent"
EVENTS="$CACHE_DIR/events.jsonl"
RUNS="$CACHE_DIR/runs.jsonl"
mkdir -p "$CACHE_DIR"

# Fixed epoch anchor — 2026-05-30T12:00:00Z. Every fixture timestamp is
# offset from this so the golden file's dates are stable.
NOW_EPOCH=1780142400
export FLEET_PROMPTS_SCORE_FAKE_NOW="$NOW_EPOCH"

iso_at() {  # $1 = epoch seconds → "YYYY-MM-DDTHH:MM:SSZ"
  date -u -r "$1" +%FT%TZ 2>/dev/null || date -u -d "@$1" +%FT%TZ
}

T_14D_AGO=$(( NOW_EPOCH - 14 * 86400 ))
T_13D_AGO=$(( NOW_EPOCH - 13 * 86400 ))
T_10D_AGO=$(( NOW_EPOCH - 10 * 86400 ))
T_7D_AGO=$(( NOW_EPOCH - 7 * 86400 ))
T_6D_AGO=$(( NOW_EPOCH - 6 * 86400 ))
T_4D_AGO=$(( NOW_EPOCH - 4 * 86400 ))
T_2D_AGO=$(( NOW_EPOCH - 2 * 86400 ))
T_1D_AGO=$(( NOW_EPOCH - 1 * 86400 ))

SHA_A="aaaaaa1"
SHA_B="bbbbbb2"
SHA_C="ccccccc"

# --- events.jsonl ---------------------------------------------------------
# Bootstrap pin at 14d: prompts_pin_changed with no `old` (the very first
# install of the project). One pr_opened, one gate_failed, one
# lesson_draft_emitted inside the aaaaaa1 window. Two runs.
#
# At 7d: a prompts_drift event (no prompts_pin_changed) marks the SHA
# transition to bbbbbb2 — exercises the fallback path. Two pr_opened, one
# gate_failed (so heal/pr=0.5), one infra_flake_rerun, zero
# lesson_draft_emitted (clean revision). Three runs.
#
# At 2d: prompts_pin_changed old=bbbbbb2 new=ccccccc. One pr_opened, two
# gate_failed (heal/pr=2.0), one lesson_draft_emitted (sendback=100%).
# One run. This is the current revision.
{
  printf '{"ts":"%s","slug":"%s","phase":"install","type":"prompts_pin_changed","old":"","new":"%s"}\n' \
         "$(iso_at "$T_14D_AGO")" "$SLUG" "$SHA_A"
  printf '{"ts":"%s","slug":"%s","phase":"ship","type":"pr_opened","number":"101","branch":"feat/0100-x"}\n' \
         "$(iso_at "$T_13D_AGO")" "$SLUG"
  printf '{"ts":"%s","slug":"%s","phase":"ship","type":"gate_failed","check":"shellcheck"}\n' \
         "$(iso_at "$T_13D_AGO")" "$SLUG"
  printf '{"ts":"%s","slug":"%s","phase":"review","type":"lesson_draft_emitted","pr":"101","headline":"x"}\n' \
         "$(iso_at "$T_10D_AGO")" "$SLUG"
  printf '{"ts":"%s","slug":"%s","phase":"ship","type":"prompts_drift","pinned":"%s","actual":"%s"}\n' \
         "$(iso_at "$T_7D_AGO")" "$SLUG" "$SHA_A" "$SHA_B"
  printf '{"ts":"%s","slug":"%s","phase":"ship","type":"pr_opened","number":"102","branch":"feat/0101-y"}\n' \
         "$(iso_at "$T_6D_AGO")" "$SLUG"
  printf '{"ts":"%s","slug":"%s","phase":"ship","type":"pr_opened","number":"103","branch":"feat/0102-z"}\n' \
         "$(iso_at "$T_6D_AGO")" "$SLUG"
  printf '{"ts":"%s","slug":"%s","phase":"ship","type":"gate_failed","check":"validate"}\n' \
         "$(iso_at "$T_4D_AGO")" "$SLUG"
  printf '{"ts":"%s","slug":"%s","phase":"ship","type":"infra_flake_rerun","pattern":"actions_silent","run_id":"99","pr":"102"}\n' \
         "$(iso_at "$T_4D_AGO")" "$SLUG"
  printf '{"ts":"%s","slug":"%s","phase":"install","type":"prompts_pin_changed","old":"%s","new":"%s"}\n' \
         "$(iso_at "$T_2D_AGO")" "$SLUG" "$SHA_B" "$SHA_C"
  printf '{"ts":"%s","slug":"%s","phase":"ship","type":"pr_opened","number":"104","branch":"feat/0103-w"}\n' \
         "$(iso_at "$T_1D_AGO")" "$SLUG"
  printf '{"ts":"%s","slug":"%s","phase":"ship","type":"gate_failed","check":"shellcheck"}\n' \
         "$(iso_at "$T_1D_AGO")" "$SLUG"
  printf '{"ts":"%s","slug":"%s","phase":"ship","type":"gate_failed","check":"validate"}\n' \
         "$(iso_at "$T_1D_AGO")" "$SLUG"
  printf '{"ts":"%s","slug":"%s","phase":"review","type":"lesson_draft_emitted","pr":"104","headline":"y"}\n' \
         "$(iso_at "$T_1D_AGO")" "$SLUG"
} > "$EVENTS"

# --- runs.jsonl -----------------------------------------------------------
# aaaaaa1 window (14d→7d): 2 runs, total spend $0.60. PRS=1 → $/PR = $0.60.
# bbbbbb2 window (7d→2d):  3 runs, total spend $1.00. PRS=2 → $/PR = $0.50.
# ccccccc window (2d→now): 1 run,  total spend $0.40. PRS=1 → $/PR = $0.40.
{
  printf '{"slug":"%s","phase":"ship","ts_start":"%s","exit":0,"total_cost_usd":0.30}\n' \
         "$SLUG" "$(iso_at "$T_13D_AGO")"
  printf '{"slug":"%s","phase":"ship","ts_start":"%s","exit":0,"total_cost_usd":0.30}\n' \
         "$SLUG" "$(iso_at "$T_10D_AGO")"
  printf '{"slug":"%s","phase":"ship","ts_start":"%s","exit":0,"total_cost_usd":0.30}\n' \
         "$SLUG" "$(iso_at "$T_6D_AGO")"
  printf '{"slug":"%s","phase":"ship","ts_start":"%s","exit":0,"total_cost_usd":0.40}\n' \
         "$SLUG" "$(iso_at "$T_6D_AGO")"
  printf '{"slug":"%s","phase":"ship","ts_start":"%s","exit":0,"total_cost_usd":0.30}\n' \
         "$SLUG" "$(iso_at "$T_4D_AGO")"
  printf '{"slug":"%s","phase":"ship","ts_start":"%s","exit":0,"total_cost_usd":0.40}\n' \
         "$SLUG" "$(iso_at "$T_1D_AGO")"
} > "$RUNS"

# ========================================================================
# AC#1 — defaults to --since 7d, exits 0, prints the documented table
#        columns. The 7d window includes bbbbbb2 (transition at 7d back)
#        and ccccccc (transition at 2d back) but NOT aaaaaa1 — so the
#        default print shows two rows for AC#1's "table renders" assertion.
#        AC#1 also requires the CURRENT row carry a trailing `← current`.
# ========================================================================
OUT="$TMP/score.default.txt"
set +e
"$FLEET" prompts-score "$SLUG" > "$OUT" 2>"$TMP/score.default.err"
EXIT=$?
set -e
if [ "$EXIT" != "0" ]; then
  echo "FAIL: AC#1 default exit=$EXIT (want 0)"
  cat "$OUT" "$TMP/score.default.err"
  exit 1
fi
HEADER='SHA      DATE        RUNS  PRS   SENDBACK%  DRAFTS  HEAL/PR  INFRA-FLK  $/PR'
if ! grep -qF "$HEADER" "$OUT"; then
  echo "FAIL: AC#1 header missing or wrong"
  cat "$OUT"
  exit 1
fi
# Current-revision marker on the ccccccc row.
if ! grep -E "^${SHA_C}\b.*← current" "$OUT" >/dev/null; then
  echo "FAIL: AC#1 ccccccc row missing '← current' marker"
  cat "$OUT"
  exit 1
fi
echo "ok: AC#1 header + current marker"

# ========================================================================
# AC#9 — golden-file byte-exact comparison.
#        Use --since 30d so the table shows all THREE SHAs deterministically
#        (the AC#1 default --since 7d only includes two).
# ========================================================================
GOLDEN="$REPO_ROOT/tests/fixtures/prompts-score.golden.txt"
if [ ! -f "$GOLDEN" ]; then
  echo "FAIL: AC#9 golden file $GOLDEN missing"
  exit 1
fi
ALL_OUT="$TMP/score.all.txt"
"$FLEET" prompts-score "$SLUG" --since 30d > "$ALL_OUT"
if ! diff -u "$GOLDEN" "$ALL_OUT"; then
  echo "FAIL: AC#9 output does not match golden file"
  echo "--- got ---"
  cat "$ALL_OUT"
  exit 1
fi
echo "ok: AC#9 golden byte-exact"

# ========================================================================
# AC#3 — per-revision metrics on the synthetic fixture, within rounding.
#        Computed against the 30d window (golden table):
#          aaaaaa1: RUNS=2 PRS=1 DRAFTS=1 SENDBACK=100.0% HEAL/PR=1.0 INFRA-FLK=0 $/PR=$0.60
#          bbbbbb2: RUNS=3 PRS=2 DRAFTS=0 SENDBACK=0.0%   HEAL/PR=0.5 INFRA-FLK=1 $/PR=$0.50
#          ccccccc: RUNS=1 PRS=1 DRAFTS=1 SENDBACK=100.0% HEAL/PR=2.0 INFRA-FLK=0 $/PR=$0.40
# ========================================================================
ROW_A="$(grep "^${SHA_A}" "$ALL_OUT" || true)"
ROW_B="$(grep "^${SHA_B}" "$ALL_OUT" || true)"
ROW_C="$(grep "^${SHA_C}" "$ALL_OUT" || true)"
for label in A B C; do
  var="ROW_$label"; row="${!var}"
  if [ -z "$row" ]; then
    echo "FAIL: AC#3 row $label missing in output"
    cat "$ALL_OUT"; exit 1
  fi
done
case "$ROW_A" in
  *" 2 "*" 1 "*"100.0%"*" 1 "*"1.0 "*" 0 "*"\$0.60"*) ;;
  *) echo "FAIL: AC#3 aaaaaa1 metrics wrong"; echo "  $ROW_A"; exit 1 ;;
esac
case "$ROW_B" in
  *" 3 "*" 2 "*"0.0%"*" 0 "*"0.5 "*" 1 "*"\$0.50"*) ;;
  *) echo "FAIL: AC#3 bbbbbb2 metrics wrong"; echo "  $ROW_B"; exit 1 ;;
esac
case "$ROW_C" in
  *" 1 "*" 1 "*"100.0%"*" 1 "*"2.0 "*" 0 "*"\$0.40"*) ;;
  *) echo "FAIL: AC#3 ccccccc metrics wrong"; echo "  $ROW_C"; exit 1 ;;
esac
echo "ok: AC#3 per-row metrics"

# ========================================================================
# AC#2 — grouping by PROMPTS_SHA via the events.jsonl timeline. We assert
#        that a run at ts_start inside the prompts_drift window (7d→2d) is
#        attributed to bbbbbb2 (the `actual` SHA from the drift event), AND
#        that a run inside the prompts_pin_changed window (2d→now) is
#        attributed to ccccccc. The PRS counts above implicitly proved
#        grouping; here we also assert no row appears for an unrelated SHA.
# ========================================================================
EXTRA="$(grep -vE "^(${SHA_A}|${SHA_B}|${SHA_C}|SHA|-+\$| *\$|trend:|7-day|PROMPT)" "$ALL_OUT" || true)"
if [ -n "$EXTRA" ]; then
  echo "FAIL: AC#2 unexpected non-fixture row(s) in output:"
  echo "$EXTRA"
  exit 1
fi
echo "ok: AC#2 grouping limited to fixture SHAs"

# ========================================================================
# AC#4 — --since parsing. Valid Nh/Nd accepted; invalid forms exit 2 with
#        a documented error.
# ========================================================================
for bad in 30 30m forever ""; do
  set +e
  "$FLEET" prompts-score "$SLUG" --since "$bad" > "$TMP/since.out" 2> "$TMP/since.err"
  RC=$?
  set -e
  if [ "$RC" != "2" ]; then
    echo "FAIL: AC#4 --since '$bad' exit=$RC (want 2)"
    cat "$TMP/since.err"; exit 1
  fi
  if ! grep -qE "prompts-score: invalid --since" "$TMP/since.err"; then
    echo "FAIL: AC#4 --since '$bad' missing documented error"
    cat "$TMP/since.err"; exit 1
  fi
done
# Valid forms must NOT error.
for good in 24h 30d; do
  set +e
  "$FLEET" prompts-score "$SLUG" --since "$good" >/dev/null 2>"$TMP/since.err"
  RC=$?
  set -e
  if [ "$RC" != "0" ]; then
    echo "FAIL: AC#4 --since '$good' exit=$RC (want 0)"
    cat "$TMP/since.err"; exit 1
  fi
done
echo "ok: AC#4 --since parsing"

# ========================================================================
# AC#5 — --json prints one JSON object per revision (JSONL).
# ========================================================================
JSON_OUT="$TMP/score.json"
"$FLEET" prompts-score "$SLUG" --since 30d --json > "$JSON_OUT"
LINES=$(grep -c . "$JSON_OUT" || true)
if [ "$LINES" != "3" ]; then
  echo "FAIL: AC#5 --json expected 3 lines (one per revision), got $LINES"
  cat "$JSON_OUT"; exit 1
fi
# Each line must parse as JSON and carry the documented schema keys.
while IFS= read -r line; do
  [ -z "$line" ] && continue
  echo "$line" | node -e '
    let body = "";
    process.stdin.on("data", c => body += c);
    process.stdin.on("end", () => {
      const o = JSON.parse(body);
      const keys = ["sha","date","runs","prs","sendback_rate","drafts",
                    "heal_per_pr","infra_flake","spend_per_pr","is_current"];
      for (const k of keys) {
        if (!(k in o)) { console.error("missing key: " + k); process.exit(1); }
      }
      if (typeof o.is_current !== "boolean") {
        console.error("is_current not boolean: " + JSON.stringify(o.is_current));
        process.exit(1);
      }
    });
  ' || {
    echo "FAIL: AC#5 JSONL row failed schema check: $line"
    exit 1
  }
done < "$JSON_OUT"
# Exactly one row has is_current=true.
CURRENT_COUNT=$(grep -c '"is_current":true' "$JSON_OUT" || true)
if [ "$CURRENT_COUNT" != "1" ]; then
  echo "FAIL: AC#5 expected exactly one is_current:true row, got $CURRENT_COUNT"
  cat "$JSON_OUT"; exit 1
fi
echo "ok: AC#5 --json JSONL schema"

# ========================================================================
# AC#6 — missing <slug> argument: exit 2 with documented error.
# ========================================================================
set +e
"$FLEET" prompts-score > "$TMP/noslug.out" 2> "$TMP/noslug.err"
RC=$?
set -e
if [ "$RC" != "2" ]; then
  echo "FAIL: AC#6 missing slug exit=$RC (want 2)"
  cat "$TMP/noslug.err"; exit 1
fi
if ! grep -qE "prompts-score: missing <slug> argument" "$TMP/noslug.err"; then
  echo "FAIL: AC#6 missing-slug error wrong"
  cat "$TMP/noslug.err"; exit 1
fi
echo "ok: AC#6 missing slug"

# ========================================================================
# AC#7 — trend line appears when ≥2 revisions present, suppressed otherwise.
# ========================================================================
# Two-revisions case: --since 7d shows bbbbbb2 + ccccccc → trend line.
"$FLEET" prompts-score "$SLUG" --since 7d > "$TMP/score.7d.txt"
if ! grep -q '^trend:' "$TMP/score.7d.txt"; then
  echo "FAIL: AC#7 trend line missing when 2 revisions present"
  cat "$TMP/score.7d.txt"; exit 1
fi
# One-revision case: --since 1d shows only ccccccc → no trend line.
"$FLEET" prompts-score "$SLUG" --since 1d > "$TMP/score.1d.txt"
if grep -q '^trend:' "$TMP/score.1d.txt"; then
  echo "FAIL: AC#7 trend line should be suppressed with 1 revision"
  cat "$TMP/score.1d.txt"; exit 1
fi
echo "ok: AC#7 trend line"

# ========================================================================
# AC#8 — empty events.jsonl: documented message to stderr, exit 0.
# ========================================================================
EMPTY_HOME="$TMP/empty-home"
mkdir -p "$EMPTY_HOME/.cache/emptyproj-agent"
: > "$EMPTY_HOME/.cache/emptyproj-agent/events.jsonl"
set +e
HOME="$EMPTY_HOME" "$FLEET" prompts-score emptyproj > "$TMP/empty.out" 2> "$TMP/empty.err"
RC=$?
set -e
if [ "$RC" != "0" ]; then
  echo "FAIL: AC#8 empty events expected exit 0, got $RC"
  cat "$TMP/empty.err"; exit 1
fi
if ! grep -qE "prompts-score: no events found for emptyproj" "$TMP/empty.err"; then
  echo "FAIL: AC#8 empty events: documented message missing on stderr"
  cat "$TMP/empty.err"; exit 1
fi
# Also test the MISSING file case (no events.jsonl at all).
NOFILE_HOME="$TMP/nofile-home"
mkdir -p "$NOFILE_HOME/.cache/missingproj-agent"
set +e
HOME="$NOFILE_HOME" "$FLEET" prompts-score missingproj > "$TMP/missing.out" 2> "$TMP/missing.err"
RC=$?
set -e
if [ "$RC" != "0" ]; then
  echo "FAIL: AC#8 missing events expected exit 0, got $RC"
  cat "$TMP/missing.err"; exit 1
fi
if ! grep -qE "prompts-score: no events found for missingproj" "$TMP/missing.err"; then
  echo "FAIL: AC#8 missing events: documented message missing on stderr"
  cat "$TMP/missing.err"; exit 1
fi
echo "ok: AC#8 empty/missing events"

# ========================================================================
# AC-Install — lib/install.sh emits prompts_pin_changed when PROMPTS_SHA
#              changes between runs.
# ========================================================================
INSTALL_TMP="$(mktemp -d -t fleet-pin-changed.XXXXXX)"
INSTALL_HOME="$INSTALL_TMP/home"
mkdir -p "$INSTALL_HOME/.local/bin"
INSTALL_PROJ="$INSTALL_TMP/project"
mkdir -p "$INSTALL_PROJ"
cat > "$INSTALL_PROJ/agents.config.sh" <<'CFG'
SLUG="pinproj"
PROJECT_NAME="pinproj"
NAMESPACE="com.pinproj"
REPO_URL="https://github.com/example/pinproj"
SELF_CANCEL="20990101"
# Pre-existing pin — the install should detect this as the `old` value.
PROMPTS_SHA="oldoldoldsha000000000000000000000000000000000000000000000000000"
CFG

# Stub launchctl so we don't try to bootstrap real plists.
cat > "$INSTALL_HOME/.local/bin/launchctl" <<'STUB'
#!/bin/bash
exit 0
STUB
chmod +x "$INSTALL_HOME/.local/bin/launchctl"

# Stub fleet so the lessons-sync end-of-run call is a no-op.
cat > "$INSTALL_HOME/.local/bin/fleet" <<'STUB'
#!/bin/bash
exit 0
STUB
chmod +x "$INSTALL_HOME/.local/bin/fleet"

# Run install.sh under the isolated HOME.
HOME="$INSTALL_HOME" \
  PATH="$INSTALL_HOME/.local/bin:$PATH" \
  FLEET_LESSONS_SYNC_CMD="$INSTALL_HOME/.local/bin/fleet" \
  bash "$REPO_ROOT/lib/install.sh" "$INSTALL_PROJ" >/dev/null 2>&1 || {
    echo "FAIL: AC-Install lib/install.sh failed under stubs"
    exit 1
  }

PIN_EVENTS="$INSTALL_HOME/.cache/pinproj-agent/events.jsonl"
if [ ! -f "$PIN_EVENTS" ]; then
  echo "FAIL: AC-Install events.jsonl never created"
  ls -la "$INSTALL_HOME/.cache/pinproj-agent/" 2>/dev/null || true
  exit 1
fi
if ! grep -q '"type":"prompts_pin_changed"' "$PIN_EVENTS"; then
  echo "FAIL: AC-Install prompts_pin_changed event missing"
  cat "$PIN_EVENTS"; exit 1
fi
if ! grep -q '"old":"oldoldoldsha000000000000000000000000000000000000000000000000000"' "$PIN_EVENTS"; then
  echo "FAIL: AC-Install old= payload missing"
  cat "$PIN_EVENTS"; exit 1
fi
if ! grep -q '"phase":"install"' "$PIN_EVENTS"; then
  echo "FAIL: AC-Install phase=install missing"
  cat "$PIN_EVENTS"; exit 1
fi
# Single-shot: a second install with the SAME pin should NOT emit a second
# event. Re-run and assert the count stays at 1.
HOME="$INSTALL_HOME" \
  PATH="$INSTALL_HOME/.local/bin:$PATH" \
  FLEET_LESSONS_SYNC_CMD="$INSTALL_HOME/.local/bin/fleet" \
  bash "$REPO_ROOT/lib/install.sh" "$INSTALL_PROJ" >/dev/null 2>&1
COUNT=$(grep -c '"type":"prompts_pin_changed"' "$PIN_EVENTS" || true)
if [ "$COUNT" != "1" ]; then
  echo "FAIL: AC-Install prompts_pin_changed emitted $COUNT times (want 1, idempotent)"
  cat "$PIN_EVENTS"; exit 1
fi
echo "ok: AC-Install prompts_pin_changed emitted once with right payload"
rm -rf "$INSTALL_TMP"

echo "ok: tests/prompts-score.sh passed"
