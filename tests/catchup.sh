#!/bin/bash
# tests/catchup.sh — `bin/fleet catchup` re-orientation briefing test.
#
# Ticket 0064. One assertion block per acceptance-criteria checkbox in
# docs/backlog/0064-fleet-catchup-re-orientation-after-absence.md.
#
# `catchup` is a PURE READER: no events.jsonl writes, no fleet_emit_event,
# no `lib/` or `prompts/` edits, no new event types. The test asserts the
# events channel byte sizes AND mtimes are unchanged across invocations
# (AC#12).
#
# Time is pinned via FLEET_NOW_OVERRIDE. State-file mtimes are pinned via
# `touch -t`. Stubs live under $HOME/.local/bin per LESSONS 2026-05-26.
# Per LESSONS 2026-05-27 fixtures use `cp` (never `$(cat)`). Per LESSONS
# 2026-05-30 keyword greps go through `grep -qF -- "$kw"`. Per LESSONS
# 2026-06-01 counts use `awk … END { print n+0 }`. Per LESSONS 2026-06-08
# any awk accumulator declares `BEGIN { count = 0 }`. Per LESSONS
# 2026-06-07 the test does NOT golden-byte-match catchup's output.

set -euo pipefail

REPO_ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
FLEET="$REPO_ROOT/bin/fleet"

TMP="$(mktemp -d -t fleet-catchup-test.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

# Isolate HOME so $HOME/.cache, $HOME/.local/bin stay sandboxed.
export HOME="$TMP/home"
mkdir -p "$HOME/.local/bin"
mkdir -p "$HOME/.cache/fleet"
mkdir -p "$HOME/.local/state/agent-fleet"

# Anchor "now" at 2026-06-23T12:00:00Z (a Tuesday — matches the user-lens
# example in the ticket's spec).
NOW_EPOCH=1782216000
export FLEET_NOW_OVERRIDE="$NOW_EPOCH"

iso_at() {  # $1 = epoch seconds → "YYYY-MM-DDTHH:MM:SSZ"
  date -u -r "$1" +%FT%TZ 2>/dev/null || date -u -d "@$1" +%FT%TZ
}

# touch a file's mtime to an epoch. Uses BSD `date -r` to render the
# CCYYMMDDHHMM.SS form for `touch -t`.
touch_epoch() {  # $1 = path, $2 = epoch
  local stamp
  stamp="$(date -r "$2" '+%Y%m%d%H%M.%S' 2>/dev/null || date -d "@$2" '+%Y%m%d%H%M.%S')"
  : > "$1"
  touch -t "$stamp" "$1"
}

T_18H_AGO=$(( NOW_EPOCH - 18 * 3600 ))
T_36H_AGO=$(( NOW_EPOCH - 36 * 3600 ))
T_71H_AGO=$(( NOW_EPOCH - 71 * 3600 - 59 * 60 ))   # 71h59m
T_72H_AGO=$(( NOW_EPOCH - 72 * 3600 ))
T_2D_AGO=$(( NOW_EPOCH - 2 * 86400 ))
T_3D_AGO=$(( NOW_EPOCH - 3 * 86400 ))
T_4D_AGO=$(( NOW_EPOCH - 4 * 86400 ))
T_5D_AGO=$(( NOW_EPOCH - 5 * 86400 ))
T_5D_14H_AGO=$(( NOW_EPOCH - 5 * 86400 - 14 * 3600 ))
T_6D_AGO=$(( NOW_EPOCH - 6 * 86400 ))
T_10D_AGO=$(( NOW_EPOCH - 10 * 86400 ))
T_14D_AGO=$(( NOW_EPOCH - 14 * 86400 ))
T_20D_AGO=$(( NOW_EPOCH - 20 * 86400 ))
T_28D_AGO=$(( NOW_EPOCH - 28 * 86400 ))

# Seed manifests under a fixture root and point discovery there.
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
MAX_DAILY_USD="5.00"
CFG
}

# Fixture A — paused, no resume in window (PRIORITY 1).
mk_manifest sidebrew
SIDEBREW_CACHE="$HOME/.cache/sidebrew-agent"
mkdir -p "$SIDEBREW_CACHE"
{
  printf '{"ts":"%s","slug":"sidebrew","phase":"ship","type":"ship_paused","reason":"3 send-backs","count":"3"}\n' \
    "$(iso_at "$T_3D_AGO")"
  # Three lesson_draft_emitted with NO subsequent lesson_promoted for PR.
  printf '{"ts":"%s","slug":"sidebrew","phase":"review","type":"lesson_draft_emitted","pr":"311","headline":"draft a"}\n' \
    "$(iso_at "$T_4D_AGO")"
  printf '{"ts":"%s","slug":"sidebrew","phase":"review","type":"lesson_draft_emitted","pr":"312","headline":"draft b"}\n' \
    "$(iso_at "$T_3D_AGO")"
  printf '{"ts":"%s","slug":"sidebrew","phase":"review","type":"lesson_draft_emitted","pr":"313","headline":"draft c"}\n' \
    "$(iso_at "$T_2D_AGO")"
} > "$SIDEBREW_CACHE/events.jsonl"
: > "$SIDEBREW_CACHE/runs.jsonl"

# Fixture B — budget block (PRIORITY 2).
mk_manifest digitalcraft
DC_CACHE="$HOME/.cache/digitalcraft-agent"
mkdir -p "$DC_CACHE"
{
  printf '{"ts":"%s","slug":"digitalcraft","phase":"ship","type":"budget_block","reason":"daily_cap","spent":"5.00","cap":"5.00"}\n' \
    "$(iso_at "$T_4D_AGO")"
} > "$DC_CACHE/events.jsonl"
# One PR, $0.94 spent.
{
  printf '{"slug":"digitalcraft","phase":"ship","ts_start":"%s","ts_end":"%s","exit":0,"total_cost_usd":0.94,"result_head":"SHIP 0042-x — PR #142 green"}\n' \
    "$(iso_at "$T_4D_AGO")" "$(iso_at $(( T_4D_AGO + 60 )))"
} > "$DC_CACHE/runs.jsonl"

# Fixture C — clean shipper (4 PRs, no events).
mk_manifest courtiq
CQ_CACHE="$HOME/.cache/courtiq-agent"
mkdir -p "$CQ_CACHE"
: > "$CQ_CACHE/events.jsonl"
{
  for i in 1 2 3 4 5; do
    printf '{"slug":"courtiq","phase":"ship","ts_start":"%s","ts_end":"%s","exit":0,"total_cost_usd":0.55,"result_head":"SHIP 02%02d-x — PR #%s green"}\n' \
      "$(iso_at $(( T_5D_AGO + i * 3600 )))" "$(iso_at $(( T_5D_AGO + i * 3600 + 60 )))" "$i" "$(( 200 + i ))"
  done
} > "$CQ_CACHE/runs.jsonl"

# Fixture D — clean shipper #2 (1 PR).
mk_manifest levelup-kids
LK_CACHE="$HOME/.cache/levelup-kids-agent"
mkdir -p "$LK_CACHE"
: > "$LK_CACHE/events.jsonl"
{
  printf '{"slug":"levelup-kids","phase":"ship","ts_start":"%s","ts_end":"%s","exit":0,"total_cost_usd":0.46,"result_head":"SHIP 0001 — PR #51 green"}\n' \
    "$(iso_at "$T_3D_AGO")" "$(iso_at $(( T_3D_AGO + 60 )))"
} > "$LK_CACHE/runs.jsonl"

# Fixture E — cost regression (PRIORITY 5). Two windows: absence-window
# has 1 PR at $5.00 (≫ prior $0.50), prior window has 1 PR at $0.50.
mk_manifest costreg
CR_CACHE="$HOME/.cache/costreg-agent"
mkdir -p "$CR_CACHE"
: > "$CR_CACHE/events.jsonl"
{
  # Absence-window: 1 PR @ $5.00.
  printf '{"slug":"costreg","phase":"ship","ts_start":"%s","ts_end":"%s","exit":0,"total_cost_usd":5.00,"result_head":"SHIP 0099 — PR #99 green"}\n' \
    "$(iso_at "$T_2D_AGO")" "$(iso_at $(( T_2D_AGO + 60 )))"
  # Prior-window: 2 PRs @ $0.50 each.
  printf '{"slug":"costreg","phase":"ship","ts_start":"%s","ts_end":"%s","exit":0,"total_cost_usd":0.50,"result_head":"SHIP 0090 — PR #90 green"}\n' \
    "$(iso_at "$T_10D_AGO")" "$(iso_at $(( T_10D_AGO + 60 )))"
  printf '{"slug":"costreg","phase":"ship","ts_start":"%s","ts_end":"%s","exit":0,"total_cost_usd":0.50,"result_head":"SHIP 0091 — PR #91 green"}\n' \
    "$(iso_at "$T_14D_AGO")" "$(iso_at $(( T_14D_AGO + 60 )))"
} > "$CR_CACHE/runs.jsonl"

# Stubs for gh (no stuck PRs anywhere by default) and launchctl.
cat > "$HOME/.local/bin/gh" <<'STUB'
#!/bin/bash
if [ "${1:-}" = "pr" ] && [ "${2:-}" = "list" ]; then
  echo "[]"; exit 0
fi
exit 0
STUB
chmod +x "$HOME/.local/bin/gh"

cat > "$HOME/.local/bin/launchctl" <<'STUB'
#!/bin/bash
exit 0
STUB
chmod +x "$HOME/.local/bin/launchctl"

export PATH="$HOME/.local/bin:$PATH"

# State files: by default both at 5d14h ago — "you were away 5d 14h"
# matches the user-lens spec.
MORNING_STATE="$HOME/.local/state/agent-fleet/morning-last-run"
INBOX_STATE="$HOME/.cache/fleet/inbox-state"

# Capture pre-invocation file sizes + mtimes (AC#12).
record_state() {
  local slug f size mtime
  for slug in sidebrew digitalcraft courtiq levelup-kids costreg; do
    for f in "$HOME/.cache/${slug}-agent/events.jsonl" \
             "$HOME/.cache/${slug}-agent/runs.jsonl"; do
      if [ -f "$f" ]; then
        size="$(wc -c <"$f" | tr -d ' ')"
        mtime="$(stat -f %m "$f" 2>/dev/null || stat -c %Y "$f" 2>/dev/null)"
        echo "$f $size $mtime"
      fi
    done
  done
}

# --- AC#1: default branch + both-missing branch -------------------------
echo "AC#1 — default detection from morning/inbox state mtimes; both-missing branch"

# Both files missing → hint + exit 0.
rm -f "$MORNING_STATE" "$INBOX_STATE"
OUT="$TMP/ac1-missing.out"
set +e
"$FLEET" catchup > "$OUT" 2>&1
EXIT=$?
set -e
if [ "$EXIT" != "0" ]; then
  echo "FAIL: AC#1 both-missing should exit 0 (got $EXIT)"; cat "$OUT"; exit 1
fi
kw="run \`fleet morning\` or \`fleet inbox\` yet"
if ! grep -qF -- "$kw" "$OUT"; then
  echo "FAIL: AC#1 both-missing missing hint about morning/inbox"
  cat "$OUT"; exit 1
fi

# Default detection — newer of morning/inbox mtimes drives "last seen".
touch_epoch "$MORNING_STATE" "$T_5D_14H_AGO"
touch_epoch "$INBOX_STATE"   "$T_6D_AGO"
OUT="$TMP/ac1-default.out"
set +e
"$FLEET" catchup > "$OUT" 2>&1
EXIT=$?
set -e
if [ "$EXIT" != "0" ]; then
  echo "FAIL: AC#1 default detect should exit 0 (got $EXIT)"; cat "$OUT"; exit 1
fi
grep -qF -- "catchup" "$OUT" || { echo "FAIL: AC#1 default missing 'catchup' header"; cat "$OUT"; exit 1; }
grep -qF -- "5d" "$OUT" || { echo "FAIL: AC#1 default should mention 5d"; cat "$OUT"; exit 1; }
echo "  ok"

# --- AC#2: <72h short-circuit ------------------------------------------
echo "AC#2 — <72h prints redirect-to-morning hint, exit 0"
for ep_var in T_18H_AGO T_36H_AGO T_71H_AGO; do
  ep="${!ep_var}"
  touch_epoch "$MORNING_STATE" "$ep"
  touch_epoch "$INBOX_STATE"   "$ep"
  OUT="$TMP/ac2-${ep_var}.out"
  set +e
  "$FLEET" catchup > "$OUT" 2>&1
  EXIT=$?
  set -e
  if [ "$EXIT" != "0" ]; then
    echo "FAIL: AC#2 $ep_var should exit 0 (got $EXIT)"; cat "$OUT"; exit 1
  fi
  grep -qF -- "you haven't been away" "$OUT" \
    || { echo "FAIL: AC#2 $ep_var missing redirect-to-morning hint"; cat "$OUT"; exit 1; }
  grep -qF -- "fleet morning" "$OUT" \
    || { echo "FAIL: AC#2 $ep_var should point at 'fleet morning'"; cat "$OUT"; exit 1; }
done
# 72h+ should NOT trip the redirect.
for ep_var in T_72H_AGO T_5D_14H_AGO T_14D_AGO; do
  ep="${!ep_var}"
  touch_epoch "$MORNING_STATE" "$ep"
  touch_epoch "$INBOX_STATE"   "$ep"
  OUT="$TMP/ac2-${ep_var}-away.out"
  set +e
  "$FLEET" catchup > "$OUT" 2>&1
  EXIT=$?
  set -e
  if [ "$EXIT" != "0" ]; then
    echo "FAIL: AC#2 $ep_var (away) should exit 0 (got $EXIT)"; cat "$OUT"; exit 1
  fi
  if grep -qF -- "you haven't been away" "$OUT"; then
    echo "FAIL: AC#2 $ep_var should NOT redirect (was away)"; cat "$OUT"; exit 1
  fi
done
echo "  ok"

# --- AC#3: --since Nh|Nd|YYYY-MM-DD + refusal --------------------------
echo "AC#3 — --since Nh / Nd / YYYY-MM-DD + invalid refusal"
# Reset state files so they don't drive detection.
touch_epoch "$MORNING_STATE" "$T_18H_AGO"
touch_epoch "$INBOX_STATE"   "$T_18H_AGO"

OUT="$TMP/ac3-nh.out"
"$FLEET" catchup --since 120h > "$OUT"
grep -qF -- "catchup" "$OUT" || { echo "FAIL: AC#3 --since 120h missing header"; cat "$OUT"; exit 1; }
grep -qF -- "5d" "$OUT" || { echo "FAIL: AC#3 --since 120h should humanize to 5d"; cat "$OUT"; exit 1; }

OUT="$TMP/ac3-nd.out"
"$FLEET" catchup --since 5d > "$OUT"
grep -qF -- "5d" "$OUT" || { echo "FAIL: AC#3 --since 5d missing 5d"; cat "$OUT"; exit 1; }

OUT="$TMP/ac3-iso.out"
"$FLEET" catchup --since 2026-06-18 > "$OUT"
grep -qF -- "catchup" "$OUT" || { echo "FAIL: AC#3 --since YYYY-MM-DD missing header"; cat "$OUT"; exit 1; }

# Invalid: exit 2, stderr keyword.
OUT="$TMP/ac3-bad.out"
set +e
"$FLEET" catchup --since banana > "$OUT" 2>&1
EXIT=$?
set -e
if [ "$EXIT" != "2" ]; then
  echo "FAIL: AC#3 invalid --since should exit 2 (got $EXIT)"; cat "$OUT"; exit 1
fi
grep -qF -- "--since must be" "$OUT" \
  || { echo "FAIL: AC#3 invalid --since missing refusal hint"; cat "$OUT"; exit 1; }
echo "  ok"

# --- AC#4: verdict template + cursor-walk repl-with-$digit -------------
echo "AC#4 — verdict sentence shape + cursor-walk renders \$5.00 literally"
touch_epoch "$MORNING_STATE" "$T_5D_14H_AGO"
touch_epoch "$INBOX_STATE"   "$T_5D_14H_AGO"

OUT="$TMP/ac4.out"
"$FLEET" catchup > "$OUT"
# Template: `you were away <DURATION>. verdict: <N> things need you now. <FIRE>.`
grep -qE 'you were away [0-9]+(w [0-9]+d|d( [0-9]+h)?|h)' "$OUT" \
  || { echo "FAIL: AC#4 verdict missing humanized duration"; cat "$OUT"; exit 1; }
grep -qE 'verdict: [0-9]+ thing' "$OUT" \
  || { echo "FAIL: AC#4 verdict missing 'N thing(s) need you'"; cat "$OUT"; exit 1; }
grep -qE 'fire' "$OUT" \
  || { echo "FAIL: AC#4 verdict missing FIRE_STATE"; cat "$OUT"; exit 1; }

# Cursor-walk: a budget event with a 'cap' value that contains "$5.00"
# substring renders without an infinite loop AND the literal value is
# present in the budget action.
# (digitalcraft cap=5.00 → action line should mention $5.00.)
grep -qF -- '$5.00' "$OUT" \
  || { echo "FAIL: AC#4 budget action should include literal '\$5.00'"; cat "$OUT"; exit 1; }
echo "  ok"

# --- AC#5: priority-ordered ranking (5 categories) ---------------------
echo "AC#5 — five priority categories surface in order"
OUT="$TMP/ac5.out"
"$FLEET" catchup --all > "$OUT"
# Items numbered 1..K. Category 1 (ship_paused) should appear first.
# Pull the lines starting with "1." / "2." / etc. and check order.
# Use awk to extract the numbered lines.
LIST="$(awk '/^  [0-9]+\. / { sub(/^  /, ""); print }' "$OUT")"
if [ -z "$LIST" ]; then
  echo "FAIL: AC#5 ranked-action list missing"; cat "$OUT"; exit 1
fi
# Item 1 → ship_paused (sidebrew).
echo "$LIST" | awk 'NR==1' | grep -qF -- "sidebrew" \
  || { echo "FAIL: AC#5 item #1 should be paused sidebrew"; echo "$LIST"; exit 1; }
echo "$LIST" | awk 'NR==1' | grep -qF -- "resume" \
  || { echo "FAIL: AC#5 item #1 action should mention 'resume'"; echo "$LIST"; exit 1; }
# Item 2 → budget_block (digitalcraft).
echo "$LIST" | awk 'NR==2' | grep -qF -- "digitalcraft" \
  || { echo "FAIL: AC#5 item #2 should be digitalcraft budget"; echo "$LIST"; exit 1; }
echo "  ok"

# --- AC#6: default 3-item cap; --all lifts it --------------------------
echo "AC#6 — default cap is 3 items; --all lifts it"
OUT="$TMP/ac6-default.out"
"$FLEET" catchup > "$OUT"
N_DEFAULT="$(awk 'BEGIN { count = 0 } /^  [0-9]+\. / { count++ } END { print count + 0 }' "$OUT")"
if [ "$N_DEFAULT" -ne 3 ]; then
  echo "FAIL: AC#6 default should emit exactly 3 ranked items (got $N_DEFAULT)"; cat "$OUT"; exit 1
fi
OUT="$TMP/ac6-all.out"
"$FLEET" catchup --all > "$OUT"
N_ALL="$(awk 'BEGIN { count = 0 } /^  [0-9]+\. / { count++ } END { print count + 0 }' "$OUT")"
if [ "$N_ALL" -lt 4 ]; then
  echo "FAIL: AC#6 --all should emit >=4 ranked items (got $N_ALL)"; cat "$OUT"; exit 1
fi
echo "  ok ($N_DEFAULT default, $N_ALL --all)"

# --- AC#7: each action line is a valid shell command -------------------
echo "AC#7 — action lines are syntactically valid shell"
OUT="$TMP/ac7.out"
"$FLEET" catchup --all > "$OUT"
# Action lines start with `     → ` (or some indent + arrow). Extract them.
ACTIONS_FILE="$TMP/ac7-actions.txt"
awk '/^[[:space:]]+→ / { sub(/^[[:space:]]+→ /, ""); print }' "$OUT" > "$ACTIONS_FILE"
N_ACTIONS="$(awk 'END { print NR + 0 }' "$ACTIONS_FILE")"
if [ "$N_ACTIONS" -lt 1 ]; then
  echo "FAIL: AC#7 should have at least 1 action line"; cat "$OUT"; exit 1
fi
# Each one should parse via bash -n. Skip lines that are pure prose
# (start with a lowercase word ending in colon, or "currently $X").
while IFS= read -r line; do
  case "$line" in
    fleet*|gh*|bash*|sh*|date*|node*|cat*|grep*|sed*|awk*|"bin/fleet"*)
      bash -n -c "$line" 2>"$TMP/ac7-err.log" \
        || { echo "FAIL: AC#7 action does not parse: $line"; cat "$TMP/ac7-err.log"; exit 1; }
      ;;
    *)
      # Non-command lines (follow-ups, notes) are tolerated.
      ;;
  esac
done < "$ACTIONS_FILE"
echo "  ok ($N_ACTIONS action lines)"

# --- AC#8: footer rows + no-activity branch ---------------------------
echo "AC#8 — footer prints per-slug rows + omits on quiet window"
OUT="$TMP/ac8.out"
"$FLEET" catchup --all > "$OUT"
grep -qF -- "while you were away" "$OUT" \
  || { echo "FAIL: AC#8 missing 'while you were away' footer heading"; cat "$OUT"; exit 1; }
# Each slug should appear in the footer.
for slug in sidebrew digitalcraft courtiq levelup-kids; do
  grep -qF -- "$slug" "$OUT" \
    || { echo "FAIL: AC#8 footer missing slug $slug"; cat "$OUT"; exit 1; }
done

# No-activity branch: a fleet whose only slug has no events + no runs.
QUIET_ROOT="$TMP/quiet"
mkdir -p "$QUIET_ROOT/quietslug"
cat > "$QUIET_ROOT/quietslug/agents.config.sh" <<CFG
PROJECT_NAME="quietslug"
SLUG="quietslug"
NAMESPACE="com.quietslug"
REPO_URL="https://github.com/example/quietslug"
SELF_CANCEL="20990101"
MAX_DAILY_USD="5.00"
CFG
mkdir -p "$HOME/.cache/quietslug-agent"
: > "$HOME/.cache/quietslug-agent/runs.jsonl"
: > "$HOME/.cache/quietslug-agent/events.jsonl"

OUT_QUIET="$TMP/ac8-quiet.out"
FLEET_DISCOVERY_ROOT="$QUIET_ROOT" "$FLEET" catchup > "$OUT_QUIET" 2>&1
if grep -qF -- "while you were away" "$OUT_QUIET"; then
  echo "FAIL: AC#8 quiet window should omit footer"; cat "$OUT_QUIET"; exit 1
fi
echo "  ok"

# --- AC#9: --json validity --------------------------------------------
echo "AC#9 — --json emits a valid object with documented schema"
OUT="$TMP/ac9.json"
"$FLEET" catchup --json > "$OUT"
if command -v node >/dev/null 2>&1; then
  node -e '
    const fs = require("fs");
    const txt = fs.readFileSync(process.argv[1], "utf8").trim();
    let obj;
    try { obj = JSON.parse(txt); }
    catch (e) { console.error("JSON parse failed:", e.message); console.error(txt); process.exit(1); }
    const required = [
      "away_seconds","away_human","verdict","actions","footer","total_spent_usd"
    ];
    for (const k of required) {
      if (!(k in obj)) { console.error("missing key:", k); process.exit(1); }
    }
    if (typeof obj.away_seconds !== "number") { console.error("away_seconds must be number"); process.exit(1); }
    if (typeof obj.away_human !== "string") { console.error("away_human must be string"); process.exit(1); }
    if (!obj.verdict || typeof obj.verdict !== "object") { console.error("verdict must be object"); process.exit(1); }
    for (const k of ["items_count","fire","summary"]) {
      if (!(k in obj.verdict)) { console.error("verdict missing key:", k); process.exit(1); }
    }
    if (!Array.isArray(obj.actions)) { console.error("actions must be array"); process.exit(1); }
    if (!Array.isArray(obj.footer)) { console.error("footer must be array"); process.exit(1); }
    if (typeof obj.total_spent_usd !== "number") { console.error("total_spent_usd must be number"); process.exit(1); }
  ' "$OUT" || { echo "FAIL: AC#9 --json schema mismatch"; cat "$OUT"; exit 1; }
else
  echo "  (node missing — skipping JSON schema check)"
fi
echo "  ok"

# --- AC#10: --all + --slug + unknown-slug refusal ----------------------
echo "AC#10 — --all + --slug filter + unknown-slug refusal"
OUT="$TMP/ac10-slug.out"
"$FLEET" catchup --slug sidebrew --all > "$OUT"
grep -qF -- "sidebrew" "$OUT" || { echo "FAIL: AC#10 --slug should show sidebrew"; cat "$OUT"; exit 1; }
# Footer in slug-filtered mode should NOT list other slugs.
if grep -qE 'courtiq[[:space:]]+[0-9]' "$OUT"; then
  echo "FAIL: AC#10 --slug sidebrew should not include courtiq in footer"
  cat "$OUT"; exit 1
fi

# Unknown slug → exit 2, stderr "not found".
OUT="$TMP/ac10-unknown.out"
set +e
"$FLEET" catchup --slug doesnotexist > "$OUT" 2>&1
EXIT=$?
set -e
if [ "$EXIT" != "2" ]; then
  echo "FAIL: AC#10 unknown slug should exit 2 (got $EXIT)"; cat "$OUT"; exit 1
fi
grep -qF -- "not found" "$OUT" \
  || { echo "FAIL: AC#10 unknown slug missing 'not found'"; cat "$OUT"; exit 1; }
echo "  ok"

# --- AC#11: --help mentions all flags ---------------------------------
echo "AC#11 — --help mentions --since, --all, --slug, --json"
HELP_OUT="$TMP/ac11.help"
set +e
"$FLEET" catchup --help > "$HELP_OUT" 2>&1
HEXIT=$?
set -e
if [ "$HEXIT" != "0" ]; then
  echo "FAIL: AC#11 --help should exit 0 (got $HEXIT)"; cat "$HELP_OUT"; exit 1
fi
for kw in --since --all --slug --json; do
  grep -qF -- "$kw" "$HELP_OUT" \
    || { echo "FAIL: AC#11 help missing '$kw'"; cat "$HELP_OUT"; exit 1; }
done
echo "  ok"

# --- AC#12: pure reader — no writes anywhere --------------------------
echo "AC#12 — pure reader: state files + events.jsonl unchanged"
# Re-anchor state files at 5d 14h ago and record baseline.
touch_epoch "$MORNING_STATE" "$T_5D_14H_AGO"
touch_epoch "$INBOX_STATE"   "$T_5D_14H_AGO"

BEFORE_STATE="$TMP/before.state"
record_state > "$BEFORE_STATE"
M_MORNING_BEFORE="$(stat -f %m "$MORNING_STATE" 2>/dev/null || stat -c %Y "$MORNING_STATE")"
M_INBOX_BEFORE="$(stat -f %m "$INBOX_STATE" 2>/dev/null || stat -c %Y "$INBOX_STATE")"
S_MORNING_BEFORE="$(wc -c <"$MORNING_STATE" | tr -d ' ')"
S_INBOX_BEFORE="$(wc -c <"$INBOX_STATE" | tr -d ' ')"

"$FLEET" catchup > /dev/null
"$FLEET" catchup --json > /dev/null
"$FLEET" catchup --all > /dev/null

AFTER_STATE="$TMP/after.state"
record_state > "$AFTER_STATE"
M_MORNING_AFTER="$(stat -f %m "$MORNING_STATE" 2>/dev/null || stat -c %Y "$MORNING_STATE")"
M_INBOX_AFTER="$(stat -f %m "$INBOX_STATE" 2>/dev/null || stat -c %Y "$INBOX_STATE")"
S_MORNING_AFTER="$(wc -c <"$MORNING_STATE" | tr -d ' ')"
S_INBOX_AFTER="$(wc -c <"$INBOX_STATE" | tr -d ' ')"

if ! diff -u "$BEFORE_STATE" "$AFTER_STATE" >/dev/null; then
  echo "FAIL: AC#12 events.jsonl/runs.jsonl mtime or size changed"
  diff -u "$BEFORE_STATE" "$AFTER_STATE"
  exit 1
fi
if [ "$M_MORNING_BEFORE" != "$M_MORNING_AFTER" ] || [ "$S_MORNING_BEFORE" != "$S_MORNING_AFTER" ]; then
  echo "FAIL: AC#12 morning state file changed"; exit 1
fi
if [ "$M_INBOX_BEFORE" != "$M_INBOX_AFTER" ] || [ "$S_INBOX_BEFORE" != "$S_INBOX_AFTER" ]; then
  echo "FAIL: AC#12 inbox state file changed"; exit 1
fi
echo "  ok"

# --- AC#13: lib/common.sh and prompts/ untouched ----------------------
echo "AC#13 — lib/common.sh + prompts/ have no diff"
if ! git -C "$REPO_ROOT" diff --quiet -- lib/common.sh prompts/ 2>/dev/null; then
  echo "FAIL: AC#13 lib/common.sh or prompts/ changed in this branch"
  git -C "$REPO_ROOT" diff --name-only -- lib/common.sh prompts/
  exit 1
fi
echo "  ok"

echo ""
echo "tests/catchup.sh — all 13 acceptance criteria pass."
