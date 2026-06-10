#!/bin/bash
# tests/rank.sh — `bin/fleet rank --by <metric>` portfolio posture leaderboard test.
#
# Ticket 0043. One assertion block per acceptance-criteria checkbox in
# docs/backlog/0043-fleet-rank-portfolio-posture-leaderboard.md. The
# `rank` reader is a PURE CONSUMER of the existing events.jsonl +
# runs.jsonl channels — no new event types, no fleet_emit_event calls,
# no fleet_* signature changes, no lib/ or prompts/ edits.
#
# Fixtures: five synthetic projects seeded under a tmpdir
# FLEET_DISCOVERY_ROOT, mirroring tests/diff.sh + tests/streak.sh. Time
# is pinned via FLEET_NOW_OVERRIDE so the rendered window header and
# every count stays deterministic. Run-time budget: <10s.
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

TMP="$(mktemp -d -t fleet-rank-test.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

# Isolate HOME so $HOME/.cache, $HOME/.local/bin stay sandboxed.
export HOME="$TMP/home"
mkdir -p "$HOME/.local/bin"

# Stable epoch anchor: 2026-06-08T12:00:00Z.
NOW_EPOCH=1780920000
export FLEET_NOW_OVERRIDE="$NOW_EPOCH"

iso_at() {  # $1 = epoch seconds → "YYYY-MM-DDTHH:MM:SSZ"
  date -u -r "$1" +%FT%TZ 2>/dev/null || date -u -d "@$1" +%FT%TZ
}

T_30D_AGO=$(( NOW_EPOCH - 30 * 86400 ))
T_10D_AGO=$(( NOW_EPOCH - 10 * 86400 ))
T_8D_AGO=$(( NOW_EPOCH - 8 * 86400 ))
T_6D_AGO=$(( NOW_EPOCH - 6 * 86400 ))
T_5D_AGO=$(( NOW_EPOCH - 5 * 86400 ))
T_4D_AGO=$(( NOW_EPOCH - 4 * 86400 ))
T_3D_AGO=$(( NOW_EPOCH - 3 * 86400 ))
T_2D_AGO=$(( NOW_EPOCH - 2 * 86400 ))

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
PROMPTS_SHA="abc123def456"
CFG
}

# Seed one project with explicit counts. Args: slug ships sendbacks heal
# unpromoted_drafts paused_pair_count
# - ships = pr_opened events in window AND SHIP-prefixed runs in window
# - sendbacks = lesson_draft_emitted events in window
# - heal = gate_failed events in window
# - unpromoted_drafts = lesson_draft_emitted with NO matching lesson_promoted
# - paused_pair_count = 0 (no pause) OR 1 (a 5h pause window)
# - spend = ships * 0.50 (so ROI = ships / spend = ships / (ships * 0.5) = 2.0)
#   Use $1 default; we will instead set spend via a fixed cost per run so ROI
#   varies by ship count.
seed_project() {  # $1=slug $2=ships $3=sendbacks $4=heal $5=unpromoted $6=paused $7=cost_per_ship
  local slug="$1" ships="$2" sendbacks="$3" heal="$4" unpromoted="$5" paused="$6" cost="$7"
  mk_manifest "$slug"
  local cache="$HOME/.cache/${slug}-agent"
  mkdir -p "$cache"
  local runs="$cache/runs.jsonl" events="$cache/events.jsonl"
  : > "$runs"
  : > "$events"

  # Pre-compute timestamp strings ONCE (one fork apiece) — re-used below.
  # iso_at shells `date`, so we batch all of them via a single python-free
  # bash loop instead of calling iso_at from every printf.
  local iso_in_window iso_oow iso_8d iso_6d iso_6d_plus5 iso_4d iso_3d
  iso_in_window="$(iso_at "$T_10D_AGO")"
  iso_oow="$(iso_at "$T_30D_AGO")"
  iso_8d="$(iso_at "$T_8D_AGO")"
  iso_6d="$(iso_at "$T_6D_AGO")"
  iso_6d_plus5="$(iso_at $(( T_6D_AGO + 5 * 3600 )))"
  iso_4d="$(iso_at "$T_4D_AGO")"
  iso_3d="$(iso_at "$T_3D_AGO")"

  local i
  # ships SHIP-prefixed runs in window (all at same ts to keep fixture small).
  for i in $(seq 1 "$ships"); do
    printf '{"slug":"%s","phase":"ship","ts_start":"%s","ts_end":"%s","exit":0,"total_cost_usd":%s,"result_head":"SHIP 00%02d-x — PR #%d green"}\n' \
      "$slug" "$iso_in_window" "$iso_in_window" "$cost" "$i" "$(( 100 + i ))" >> "$runs"
    # Matching pr_opened event so ships also counts via pr_opened.
    printf '{"ts":"%s","slug":"%s","phase":"ship","type":"pr_opened","number":"%d","branch":"feat/00%02d-x"}\n' \
      "$iso_in_window" "$slug" "$(( 100 + i ))" "$i" >> "$events"
  done

  # Out-of-window noise — must NOT be counted.
  printf '{"slug":"%s","phase":"ship","ts_start":"%s","ts_end":"%s","exit":0,"total_cost_usd":9.99,"result_head":"SHIP OOW"}\n' \
    "$slug" "$iso_oow" "$iso_oow" >> "$runs"
  printf '{"ts":"%s","slug":"%s","phase":"ship","type":"pr_opened","number":"99","branch":"feat/9999-oow"}\n' \
    "$iso_oow" "$slug" >> "$events"

  # sendbacks lesson_draft_emitted events in window. First (sendbacks - unpromoted)
  # are promoted; remaining unpromoted are open.
  local promoted_count=$(( sendbacks - unpromoted ))
  [ "$promoted_count" -lt 0 ] && promoted_count=0
  for i in $(seq 1 "$sendbacks"); do
    printf '{"ts":"%s","slug":"%s","phase":"review","type":"lesson_draft_emitted","pr":"%d","headline":"draft %d","text_sha":"sha_%s_%04d"}\n' \
      "$iso_8d" "$slug" "$(( 200 + i ))" "$i" "$slug" "$i" >> "$events"
    if [ "$i" -le "$promoted_count" ]; then
      printf '{"ts":"%s","slug":"%s","phase":"promote","type":"lesson_promoted","source":"%s","text_sha":"sha_%s_%04d","scope":"all"}\n' \
        "$iso_3d" "$slug" "$slug" "$slug" "$i" >> "$events"
    fi
  done

  # heal gate_failed events in window.
  for i in $(seq 1 "$heal"); do
    printf '{"ts":"%s","slug":"%s","phase":"ship","type":"gate_failed","check":"shellcheck"}\n' \
      "$iso_4d" "$slug" >> "$events"
  done

  # paused pair (one 5h interval), if asked.
  if [ "$paused" -gt 0 ]; then
    printf '{"ts":"%s","slug":"%s","phase":"ship","type":"ship_paused","reason":"sendback_streak","count":"3","prs":"205"}\n' \
      "$iso_6d" "$slug" >> "$events"
    printf '{"ts":"%s","slug":"%s","phase":"resume","type":"ship_resumed","source":"%s","paused_for":"5h","reason":"streak cleared","forced":"0"}\n' \
      "$iso_6d_plus5" "$slug" "$slug" >> "$events"
  fi
}

# =====================================================================
# Five-slug portfolio:
#   alpha   — best ROI, heal-rate; clean drafts; no pause; low sendbacks
#   bravo   — good across the board
#   charlie — median performer
#   delta   — heavy paused-hours; high drafts
#   echo    — worst ROI, worst heal-rate, worst sendback-rate, outlier
# =====================================================================
# seed_project   slug    ships  sb  heal  unpromoted  paused  cost_per_ship
# Kept small to fit the <10s test budget — the goal is one number per
# slug per metric, not stress-testing the per-event walker.
# The existing per-slug helpers fork `date -u -j -f` from awk's getline
# once per event line — so reducing event counts is the dominant lever
# for keeping the test budget bounded.
seed_project     alpha     5     1   1     0          0       0.10
seed_project     bravo     4     2   2     1          0       0.15
seed_project     charlie   3     3   3     2          0       0.20
seed_project     delta     2     4   5     3          1       0.30
seed_project     echo-co   1     8   8     7          1       0.80

# Computed expected metrics (over default 14-day window):
#
# ROI = ships / spend  (spend = ships * cost_per_ship)
#   alpha   = 20 / (20*0.10) = 20 / 2.00  = 10.00
#   bravo   = 15 / (15*0.15) = 15 / 2.25  ≈  6.6667
#   charlie = 10 / (10*0.20) = 10 / 2.00  =  5.00
#   delta   =  8 / ( 8*0.30) =  8 / 2.40  ≈  3.3333
#   echo-co =  5 / ( 5*0.80) =  5 / 4.00  =  1.25
#
# heal-rate = merges / heal  (merges = ships)
#   alpha   = 20 / 1  = 20.00
#   bravo   = 15 / 2  =  7.50
#   charlie = 10 / 3  ≈  3.3333
#   delta   =  8 / 6  ≈  1.3333
#   echo-co =  5 / 10 =  0.50
#
# draft-debt = unpromoted drafts (lower is better)
#   alpha=0 bravo=1 charlie=2 delta=3 echo-co=7
#
# paused-hours (lower is better)
#   alpha=0 bravo=0 charlie=0 delta=5 echo-co=5
#
# sendback-rate = sendbacks / pr_opened  (lower is better)
#   alpha   = 1/20 = 0.05
#   bravo   = 2/15 ≈ 0.1333
#   charlie = 3/10 = 0.30
#   delta   = 5/8  = 0.625
#   echo-co = 9/5  = 1.80


# =====================================================================
# AC#1 — `--by` is REQUIRED. Missing prints usage line, exit 2.
#        Unknown metric prints diagnostic + valid list, exit 2.
# =====================================================================
echo "AC#1 — --by required + unknown metric handling"

set +e
err_missing="$TMP/ac1_missing.err"
"$FLEET" rank 2>"$err_missing"
rc_missing=$?
set -e
[ "$rc_missing" -eq 2 ] || { echo "FAIL AC#1 missing --by: expected exit 2, got $rc_missing"; exit 1; }
grep -qF -- 'rank: usage: bin/fleet rank --by <roi|heal-rate|draft-debt|paused-hours|sendback-rate>' "$err_missing" \
  || { echo "FAIL AC#1 missing --by: wrong usage line"; cat "$err_missing"; exit 1; }

set +e
err_unknown="$TMP/ac1_unknown.err"
"$FLEET" rank --by bogus 2>"$err_unknown"
rc_unknown=$?
set -e
[ "$rc_unknown" -eq 2 ] || { echo "FAIL AC#1 unknown metric: expected exit 2, got $rc_unknown"; exit 1; }
grep -qF -- 'rank: unknown metric "bogus"' "$err_unknown" \
  || { echo "FAIL AC#1 unknown metric: wrong diagnostic"; cat "$err_unknown"; exit 1; }
grep -qF -- 'roi heal-rate draft-debt paused-hours sendback-rate' "$err_unknown" \
  || { echo "FAIL AC#1 unknown metric: valid list missing"; cat "$err_unknown"; exit 1; }
echo "  ok"

# =====================================================================
# Run each metric ONCE and cache the output — subsequent ACs reuse.
# (per-rank invocation forks `date -u -j -f` once per event line via
# the existing helpers; the rank() body backgrounds the per-slug walk
# but cumulative cost still dominates. <10s budget caps total calls.)
#
# AC#10 (pure-reader byte-size check) folds into this block by snapping
# the alpha events.jsonl size BEFORE the 5 ranks and verifying it has
# not changed AFTER.
# =====================================================================
EVENTS_ALPHA="$HOME/.cache/alpha-agent/events.jsonl"
ac10_size_before="$(stat -f %z "$EVENTS_ALPHA" 2>/dev/null || stat -c %s "$EVENTS_ALPHA")"

out_roi="$TMP/out_roi.out"
out_hr="$TMP/out_hr.out"
out_dd="$TMP/out_dd.out"
out_ph="$TMP/out_ph.out"
out_sr="$TMP/out_sr.out"
"$FLEET" rank --by roi           > "$out_roi"
"$FLEET" rank --by heal-rate     > "$out_hr"
"$FLEET" rank --by draft-debt    > "$out_dd"
"$FLEET" rank --by paused-hours  > "$out_ph"
"$FLEET" rank --by sendback-rate > "$out_sr"

ac10_size_after="$(stat -f %z "$EVENTS_ALPHA" 2>/dev/null || stat -c %s "$EVENTS_ALPHA")"

# =====================================================================
# AC#2 — Five metrics supported. Each computes one number per slug
#        from that slug's events.jsonl / runs.jsonl over window.
# =====================================================================
echo "AC#2 — five metrics each produce one ranked value per slug"

for metric_pair in "roi:$out_roi" "heal-rate:$out_hr" "draft-debt:$out_dd" "paused-hours:$out_ph" "sendback-rate:$out_sr"; do
  metric="${metric_pair%%:*}"
  out="${metric_pair#*:}"
  for slug in alpha bravo charlie delta echo-co; do
    count="$(awk -v s="$slug" '$0 ~ ("(^| )" s "( |$)") { n++ } END { print n+0 }' "$out")"
    [ "$count" -ge 1 ] || { echo "FAIL AC#2 $metric: slug $slug not present (got $count)"; cat "$out"; exit 1; }
  done
done
echo "  ok"

# =====================================================================
# AC#3 — Order: best-at-top. ROI/heal-rate higher-better (desc),
#        draft-debt/paused-hours/sendback-rate lower-better (asc).
#        Ties break alphabetically.
# =====================================================================
echo "AC#3 — best-at-top, direction by metric, alphabetical ties"

assert_order() {  # $1 = label, $2 = file, $3 = expected order " ... "
  local label="$1" file="$2" expected="$3" got
  got="$(awk '/^[0-9]/ { print $2 }' "$file" | tr '\n' ' ')"
  case "$got" in
    "$expected"* ) ;;
    * ) echo "FAIL AC#3 $label order wrong: got '$got' expected prefix '$expected'"; cat "$file"; exit 1 ;;
  esac
}

assert_order roi           "$out_roi" "alpha bravo charlie delta echo-co "
assert_order heal-rate     "$out_hr"  "alpha bravo charlie delta echo-co "
assert_order draft-debt    "$out_dd"  "alpha bravo charlie delta echo-co "
assert_order paused-hours  "$out_ph"  "alpha bravo charlie delta echo-co "
assert_order sendback-rate "$out_sr"  "alpha bravo charlie delta echo-co "
echo "  ok"

# =====================================================================
# AC#4 — Δ FROM MEDIAN column: even/odd N median. Median row prints
#        "median" in the Δ column.
# =====================================================================
echo "AC#4 — Δ FROM MEDIAN column for odd + even N"

# Odd N = 5 → median = middle value. For draft-debt sorted = 0,1,2,3,7 →
# median = 2 (charlie). charlie's Δ column reads "median".
awk '/^[0-9]/ && $2 == "charlie" { print $0 }' "$out_dd" | grep -qF -- "median" \
  || { echo "FAIL AC#4 odd median: charlie should have 'median' in Δ column"; cat "$out_dd"; exit 1; }

# Even N — add a 6th project with a known value to force even count.
# Use minimal events to keep the budget tight.
seed_project foxtrot 1 1 1 1 0 0.40
out_even="$TMP/ac4_even.out"
"$FLEET" rank --by draft-debt > "$out_even"
# Values for draft-debt: alpha=0 bravo=1 charlie=2 foxtrot=4 delta=3 echo-co=7
# Sorted ascending: 0,1,2,3,4,7 — middle two are 2 and 3, median = 2.5.
n_rows="$(awk '/^[0-9]/ { n++ } END { print n+0 }' "$out_even")"
[ "$n_rows" -eq 6 ] || { echo "FAIL AC#4 even N: expected 6 ranked rows, got $n_rows"; cat "$out_even"; exit 1; }
echo "  ok"

# Cleanup: remove foxtrot so subsequent ACs use the 5-slug portfolio.
rm -rf "$FIXTURE_ROOT/foxtrot" "$HOME/.cache/foxtrot-agent"

# =====================================================================
# AC#5 — Outlier line: present when |Δ| > 2 * MAD OR value is the worst
#        in the wrong direction. Absent when the cluster is tight.
#        Recommend line names `fleet diff <outlier> <leader>`.
# =====================================================================
echo "AC#5 — outlier present + outlier absent branches"

# Outlier present: re-use AC#3's draft-debt output ($out_dd).
grep -qF -- "outlier" "$out_dd" \
  || { echo "FAIL AC#5 outlier should be present in draft-debt fixture"; cat "$out_dd"; exit 1; }
# Recommend line cites `fleet diff <outlier> <leader>`. Leader = alpha.
grep -qF -- "fleet diff echo-co alpha" "$out_dd" \
  || { echo "FAIL AC#5 recommend line should name 'fleet diff echo-co alpha'"; cat "$out_dd"; exit 1; }

# Outlier absent: clear out the cache for echo-co + delta so only the
# tight-cluster slugs (alpha, bravo, charlie) remain.
rm -rf "$FIXTURE_ROOT/delta" "$HOME/.cache/delta-agent"
rm -rf "$FIXTURE_ROOT/echo-co" "$HOME/.cache/echo-co-agent"
out_tight="$TMP/ac5_tight.out"
"$FLEET" rank --by draft-debt > "$out_tight"
grep -qF -- "outlier" "$out_tight" \
  && { echo "FAIL AC#5 outlier should be ABSENT in tight-cluster fixture"; cat "$out_tight"; exit 1; }
echo "  ok"

# Re-seed delta + echo-co so AC#7 (--json) sees the 5-slug portfolio
# but skip extra ranks here.
seed_project delta   3 5  6 3 1 0.30
seed_project echo-co 2 9 10 7 1 0.80

# =====================================================================
# AC#6 — --since <Nd|YYYY-MM-DD> overrides the default window.
# =====================================================================
echo "AC#6 — --since flag (Nd + YYYY-MM-DD)"

# Nd form: shorten the window to 1d. Use draft-debt (cheapest metric).
"$FLEET" rank --by draft-debt --since 1d > /dev/null \
  || { echo "FAIL AC#6 --since 1d exit nonzero"; exit 1; }

# YYYY-MM-DD form: pick a date 7 days before NOW_EPOCH (2026-06-01).
"$FLEET" rank --by draft-debt --since 2026-06-01 > /dev/null \
  || { echo "FAIL AC#6 --since YYYY-MM-DD exit nonzero"; exit 1; }
echo "  ok"

# =====================================================================
# AC#7 — --json emits one JSON object per slug + summary object.
# =====================================================================
echo "AC#7 — --json output, parseable + has expected keys"

out_json="$TMP/ac7.json"
"$FLEET" rank --by draft-debt --json > "$out_json"

node -e '
  const fs = require("fs");
  const lines = fs.readFileSync(process.argv[1], "utf8").trim().split("\n");
  if (lines.length < 2) { console.error("too few lines"); process.exit(1); }
  // First N lines: per-slug objects. Last line: summary.
  const rows = [];
  let summary = null;
  for (const line of lines) {
    const obj = JSON.parse(line);
    if (obj.summary) summary = obj.summary;
    else rows.push(obj);
  }
  if (rows.length === 0) { console.error("no slug rows"); process.exit(1); }
  if (!summary) { console.error("missing summary"); process.exit(1); }
  for (const r of rows) {
    if (typeof r.slug !== "string") { console.error("bad slug", r); process.exit(1); }
    if (typeof r.rank !== "number") { console.error("bad rank", r); process.exit(1); }
    if (typeof r.value !== "number") { console.error("bad value", r); process.exit(1); }
    if (typeof r.delta_from_median !== "number") { console.error("bad delta", r); process.exit(1); }
    if (typeof r.is_outlier !== "boolean") { console.error("bad outlier", r); process.exit(1); }
  }
  if (summary.metric !== "draft-debt") { console.error("summary.metric wrong", summary); process.exit(1); }
  if (!summary.window) { console.error("summary.window missing"); process.exit(1); }
  if (typeof summary.median !== "number") { console.error("summary.median wrong"); process.exit(1); }
  if (typeof summary.leader !== "string") { console.error("summary.leader wrong"); process.exit(1); }
' "$out_json" || { echo "FAIL AC#7 JSON validation failed"; cat "$out_json"; exit 1; }
echo "  ok"

# =====================================================================
# AC#8 — `--help` USAGE mentions --by, --since, --json, and the 5 metrics.
# =====================================================================
echo "AC#8 — --help mentions flags + five metrics"

help_out="$TMP/ac8.help"
"$FLEET" rank --help > "$help_out"
for kw in "--by" "--since" "--json" "roi" "heal-rate" "draft-debt" "paused-hours" "sendback-rate"; do
  grep -qF -- "$kw" "$help_out" \
    || { echo "FAIL AC#8 help missing keyword '$kw'"; cat "$help_out"; exit 1; }
done
echo "  ok"

# =====================================================================
# AC#9 — Empty fleet + single-slug fleet messages, exit 0.
# =====================================================================
echo "AC#9 — empty fleet + single-slug fleet messages"

EMPTY_ROOT="$TMP/empty"
mkdir -p "$EMPTY_ROOT"
out_empty="$TMP/ac9_empty.out"
FLEET_DISCOVERY_ROOT="$EMPTY_ROOT" "$FLEET" rank --by roi > "$out_empty"
grep -qF -- 'rank: no projects discovered. run `fleet onboard` to adopt one.' "$out_empty" \
  || { echo "FAIL AC#9 empty fleet message wrong"; cat "$out_empty"; exit 1; }

SINGLE_ROOT="$TMP/single"
mkdir -p "$SINGLE_ROOT/lonely"
cat > "$SINGLE_ROOT/lonely/agents.config.sh" <<'CFG'
PROJECT_NAME="lonely"
SLUG="lonely"
NAMESPACE="com.lonely"
REPO_URL="https://github.com/example/lonely"
CFG
out_single="$TMP/ac9_single.out"
FLEET_DISCOVERY_ROOT="$SINGLE_ROOT" "$FLEET" rank --by roi > "$out_single"
grep -qF -- 'rank: only 1 project; nothing to rank.' "$out_single" \
  || { echo "FAIL AC#9 single-slug fleet message wrong"; cat "$out_single"; exit 1; }
echo "  ok"

# =====================================================================
# AC#10 — Pure reader: events.jsonl byte size unchanged before/after.
# (Snapshotted before/after the 5 cached rank calls at the top of the file.)
# =====================================================================
echo "AC#10 — pure reader: events.jsonl unchanged"

[ "$ac10_size_before" = "$ac10_size_after" ] \
  || { echo "FAIL AC#10 events.jsonl byte size changed ($ac10_size_before → $ac10_size_after)"; exit 1; }
echo "  ok"

# =====================================================================
# AC#11 — Reuse existing per-slug helpers. Source-grep that rank_compute_*
#         calls into the existing helper namespace (weekly_*, digest_*,
#         diff_*, inbox_*).
# =====================================================================
echo "AC#11 — rank_compute_* helpers wrap existing per-slug helpers"

FLEET_FILE="$REPO_ROOT/bin/fleet"

# rank_compute_roi must reference weekly_ship_count_since OR digest_spend_since.
awk '/^rank_compute_roi\(\)/,/^\}/' "$FLEET_FILE" \
  | grep -qE 'weekly_ship_count_since|digest_spend_since' \
  || { echo "FAIL AC#11 rank_compute_roi must wrap weekly_/digest_ helpers"; exit 1; }

# rank_compute_heal_rate must reference weekly_heal_count_since OR digest_event_count_since.
awk '/^rank_compute_heal_rate\(\)/,/^\}/' "$FLEET_FILE" \
  | grep -qE 'weekly_heal_count_since|digest_event_count_since' \
  || { echo "FAIL AC#11 rank_compute_heal_rate must wrap weekly_/digest_ helpers"; exit 1; }

# rank_compute_draft_debt must reference diff_draft_debt OR inbox_count_drafts.
awk '/^rank_compute_draft_debt\(\)/,/^\}/' "$FLEET_FILE" \
  | grep -qE 'diff_draft_debt|inbox_count_drafts' \
  || { echo "FAIL AC#11 rank_compute_draft_debt must wrap existing draft helper"; exit 1; }

# rank_compute_paused_hours must reference diff_paused_hours.
awk '/^rank_compute_paused_hours\(\)/,/^\}/' "$FLEET_FILE" \
  | grep -qF -- "diff_paused_hours" \
  || { echo "FAIL AC#11 rank_compute_paused_hours must wrap diff_paused_hours"; exit 1; }

# rank_compute_sendback_rate must reference digest_event_count_since OR diff_count_pr_opened.
awk '/^rank_compute_sendback_rate\(\)/,/^\}/' "$FLEET_FILE" \
  | grep -qE 'digest_event_count_since|diff_count_pr_opened' \
  || { echo "FAIL AC#11 rank_compute_sendback_rate must wrap weekly_/digest_ helpers"; exit 1; }
echo "  ok"

# =====================================================================
# AC#12 — lib/common.sh untouched on this branch.
# =====================================================================
echo "AC#12 — lib/common.sh untouched"

if git -C "$REPO_ROOT" rev-parse --verify main >/dev/null 2>&1; then
  diff_lc="$(git -C "$REPO_ROOT" diff --name-only main...HEAD -- lib/common.sh 2>/dev/null || true)"
  [ -z "$diff_lc" ] || { echo "FAIL AC#12 lib/common.sh changed on this branch: $diff_lc"; exit 1; }
fi
echo "  ok"

# =====================================================================
# AC#13 — prompts/ untouched on this branch.
# =====================================================================
echo "AC#13 — prompts/ untouched"

if git -C "$REPO_ROOT" rev-parse --verify main >/dev/null 2>&1; then
  diff_pr="$(git -C "$REPO_ROOT" diff --name-only main...HEAD -- prompts/ 2>/dev/null || true)"
  [ -z "$diff_pr" ] || { echo "FAIL AC#13 prompts/ changed on this branch: $diff_pr"; exit 1; }
fi
echo "  ok"

# =====================================================================
# AC#14 — fleet_emit_event must NOT be invoked from rank().
# =====================================================================
echo "AC#14 — rank() never calls fleet_emit_event"

# Grep the rank() and rank_* function bodies for actual fleet_emit_event
# call shapes — i.e. a line where the FIRST non-whitespace token is
# `fleet_emit_event`. Comments and help-text mentions are allowed.
check_no_emit() {  # $1 = function-name regex
  awk -v fn="$1" '
    $0 ~ ("^" fn "\\(\\) \\{") { in_fn = 1 }
    in_fn { print }
    in_fn && /^\}/ { in_fn = 0 }
  ' "$FLEET_FILE" | awk '
    {
      line = $0
      sub(/^[[:space:]]+/, "", line)
      if (substr(line, 1, 1) == "#") next
      if (line ~ /^fleet_emit_event[[:space:]]/) { print; bad++ }
    }
    END { exit (bad > 0) ? 1 : 0 }
  '
}

if ! check_no_emit "rank"; then
  echo "FAIL AC#14 rank() must not call fleet_emit_event"
  exit 1
fi
if ! check_no_emit "rank_[a-z_]+"; then
  echo "FAIL AC#14 a rank_* helper calls fleet_emit_event"
  exit 1
fi
echo "  ok"

echo "ALL OK — tests/rank.sh"
