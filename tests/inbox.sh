#!/bin/bash
# tests/inbox.sh — `bin/fleet inbox` daily-TODO-list test.
#
# Ticket 0026. One assertion block per acceptance-criteria checkbox in
# docs/backlog/0026-fleet-inbox-daily-operator-todo.md.
#
# Fixture (three synthetic projects) seeded under a tmpdir
# FLEET_DISCOVERY_ROOT, mirroring tests/weekly.sh. Time is pinned via
# FLEET_INBOX_FAKE_NOW so the golden table at tests/fixtures/inbox.golden.txt
# stays byte-stable.
#
# Stubs in $HOME/.local/bin per LESSONS 2026-05-26 (lib/common.sh resets
# PATH — bin/fleet does NOT source common.sh, but using the same dir keeps
# the launchctl + gh mocks discoverable.

set -euo pipefail

REPO_ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
FLEET="$REPO_ROOT/bin/fleet"
GOLDEN="$REPO_ROOT/tests/fixtures/inbox.golden.txt"

TMP="$(mktemp -d -t fleet-inbox-test.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

# Isolate HOME so $HOME/.cache and $HOME/Library are sandboxed.
export HOME="$TMP/home"
mkdir -p "$HOME/.local/bin"
mkdir -p "$HOME/Library/LaunchAgents"
mkdir -p "$HOME/.cache/fleet"

# Stable epoch anchor — 2026-06-01T12:00:00Z.
NOW_EPOCH=1780315200
export FLEET_INBOX_FAKE_NOW="$NOW_EPOCH"
# Reuse weekly's fake-now for paused_days since inbox composes weekly_paused_days.
export FLEET_WEEKLY_FAKE_NOW="$NOW_EPOCH"

iso_at() {  # $1 = epoch seconds → "YYYY-MM-DDTHH:MM:SSZ"
  date -u -r "$1" +%FT%TZ 2>/dev/null || date -u -d "@$1" +%FT%TZ
}

T_30D_AGO=$(( NOW_EPOCH - 30 * 86400 ))
T_14D_AGO=$(( NOW_EPOCH - 14 * 86400 ))
T_2D_AGO=$(( NOW_EPOCH - 2 * 86400 ))
T_1D_AGO=$(( NOW_EPOCH - 1 * 86400 ))
T_6H_AGO=$(( NOW_EPOCH - 6 * 3600 ))

FIXTURE="$TMP/projects"
mkdir -p "$FIXTURE"
export FLEET_DISCOVERY_ROOT="$FIXTURE"

# ----- Fixture A: agent-fleet (2 drafts, 1 stuck PR, SELF_CANCEL=29d) ----
mkdir -p "$FIXTURE/agent-fleet/docs"
cat > "$FIXTURE/agent-fleet/agents.config.sh" <<CFG
PROJECT_NAME="Agent Fleet"
SLUG="agent-fleet"
NAMESPACE="com.agent-fleet"
REPO_URL="https://github.com/mutaaf/agent-fleet"
SELF_CANCEL="20260630"
CFG

# LESSONS.md: 2 active DRAFT markers + 1 promoted (no marker → real lesson).
cat > "$FIXTURE/agent-fleet/docs/LESSONS.md" <<'LESSONS'
# LESSONS

## 2026-05-25 — bootstrap

Existing promoted lesson, no marker.

<!-- DRAFT: reviewer send-back, PR #187, 2026-05-30 -->
## 2026-05-30 — DRAFT placeholder one

(promote me)

<!-- DRAFT: reviewer send-back, PR #189, 2026-05-31 -->
## 2026-05-31 — DRAFT placeholder two

(promote me too)
LESSONS

AF_CACHE="$HOME/.cache/agent-fleet-agent"
mkdir -p "$AF_CACHE"
# events: 2 lesson_draft_emitted, no budget_block today.
{
  printf '{"ts":"%s","slug":"agent-fleet","phase":"review","type":"lesson_draft_emitted","pr":"187","headline":"draft one"}\n' \
    "$(iso_at "$T_2D_AGO")"
  printf '{"ts":"%s","slug":"agent-fleet","phase":"review","type":"lesson_draft_emitted","pr":"189","headline":"draft two"}\n' \
    "$(iso_at "$T_1D_AGO")"
} > "$AF_CACHE/events.jsonl"

# ----- Fixture B: digitalcraft (1 draft, SELF_CANCEL=5d, budget_block) ---
mkdir -p "$FIXTURE/digitalcraft/docs"
cat > "$FIXTURE/digitalcraft/agents.config.sh" <<CFG
PROJECT_NAME="Digital Craft"
SLUG="digitalcraft"
NAMESPACE="com.digitalcraft"
REPO_URL="https://github.com/example/digitalcraft"
SELF_CANCEL="20260606"
CFG

cat > "$FIXTURE/digitalcraft/docs/LESSONS.md" <<'LESSONS'
# LESSONS

## 2026-05-25 — bootstrap

<!-- DRAFT: reviewer send-back, PR #305, 2026-05-31 -->
## 2026-05-31 — DRAFT placeholder

(promote me)
LESSONS

DC_CACHE="$HOME/.cache/digitalcraft-agent"
mkdir -p "$DC_CACHE"
# events: 1 lesson_draft_emitted + 1 budget_block today + 1 budget_block yesterday (should NOT count).
{
  printf '{"ts":"%s","slug":"digitalcraft","phase":"review","type":"lesson_draft_emitted","pr":"305","headline":"draft"}\n' \
    "$(iso_at "$T_2D_AGO")"
  printf '{"ts":"%s","slug":"digitalcraft","phase":"ship","type":"budget_block","reason":"daily_cap","spent":"5.00","cap":"5.00"}\n' \
    "$(iso_at "$T_6H_AGO")"
  printf '{"ts":"%s","slug":"digitalcraft","phase":"ship","type":"budget_block","reason":"daily_cap","spent":"5.00","cap":"5.00"}\n' \
    "$(iso_at "$T_1D_AGO")"
} > "$DC_CACHE/events.jsonl"

# ----- Fixture C: courtiq (0 drafts, EXPIRED, paused 14d) -----------------
mkdir -p "$FIXTURE/courtiq/docs"
cat > "$FIXTURE/courtiq/agents.config.sh" <<CFG
PROJECT_NAME="CourtIQ"
SLUG="courtiq"
NAMESPACE="com.courtiq"
REPO_URL="https://github.com/example/courtiq"
SELF_CANCEL="20260520"
CFG

cat > "$FIXTURE/courtiq/docs/LESSONS.md" <<'LESSONS'
# LESSONS

## 2026-05-25 — bootstrap

No drafts here.
LESSONS

CQ_CACHE="$HOME/.cache/courtiq-agent"
mkdir -p "$CQ_CACHE"
: > "$CQ_CACHE/events.jsonl"

# Drop a plist with mtime = 14d ago so weekly_paused_days reports "14d".
COURTIQ_PLIST="$HOME/Library/LaunchAgents/com.courtiq.agent-ship.plist"
echo "<plist/>" > "$COURTIQ_PLIST"
COURTIQ_LOCAL_STAMP="$(date -r "$T_14D_AGO" +%Y%m%d%H%M.%S 2>/dev/null || date -d "@$T_14D_AGO" +%Y%m%d%H%M.%S)"
touch -t "$COURTIQ_LOCAL_STAMP" "$COURTIQ_PLIST"

# ----- launchctl stub: only courtiq is paused ----------------------------
cat > "$HOME/.local/bin/launchctl" <<'STUB'
#!/bin/bash
if [ "${1:-}" = "print-disabled" ]; then
  cat <<DIS
{
  "com.courtiq.agent-ship" => true
  "com.agent-fleet.agent-ship" => false
  "com.digitalcraft.agent-ship" => false
}
DIS
  exit 0
fi
exit 0
STUB
chmod +x "$HOME/.local/bin/launchctl"

# ----- gh stub: 1 stuck PR for agent-fleet (created 2d ago) --------------
cat > "$HOME/.local/bin/gh" <<STUB
#!/bin/bash
# Only respond to the inbox's stuck-PR query.
if [ "\${1:-}" = "pr" ] && [ "\${2:-}" = "list" ]; then
  # Detect --repo argument and dispatch to the matching project's PR list.
  repo=""
  for ((i=3; i<=\$#; i++)); do
    eval "arg=\\\${\$i}"
    if [ "\$arg" = "--repo" ]; then
      j=\$(( i + 1 ))
      eval "repo=\\\${\$j}"
    fi
  done
  case "\$repo" in
    *agent-fleet*)
      printf '[{"number":187,"headRefName":"feat/0099-old","createdAt":"%s"}]\n' "$(iso_at "$T_2D_AGO")"
      ;;
    *)
      echo "[]"
      ;;
  esac
  exit 0
fi
exit 0
STUB
chmod +x "$HOME/.local/bin/gh"

export PATH="$HOME/.local/bin:$PATH"

# ========================================================================
# AC #1 — `bin/fleet inbox` (no flags) prints banner + 5 sections in order.
# ========================================================================
OUT="$TMP/inbox.txt"
set +e
"$FLEET" inbox > "$OUT"
EXIT=$?
set -e

if [ "$EXIT" != "0" ]; then
  echo "FAIL: AC#1 default inbox should exit 0, got $EXIT"
  cat "$OUT"; exit 1
fi

# Banner — first non-blank line.
if ! head -1 "$OUT" | grep -qE '^FLEET INBOX — 2026-06-01 \(since last run '; then
  echo "FAIL: AC#1 banner missing"; head -3 "$OUT"; exit 1
fi

# Five named sections in this exact order. Use awk to find their line numbers.
expected_order=(
  "drafts to promote"
  "self-cancel expiring (<=7d)"
  "paused projects"
  "budget tripped today"
  "in-flight agent PRs >24h old"
)
prev_line=0
for section in "${expected_order[@]}"; do
  line=$(grep -nF -- "$section" "$OUT" | head -1 | cut -d: -f1)
  if [ -z "$line" ]; then
    echo "FAIL: AC#1 section '$section' missing"; cat "$OUT"; exit 1
  fi
  if [ "$line" -le "$prev_line" ]; then
    echo "FAIL: AC#1 section '$section' out of order (line $line <= prev $prev_line)"
    cat "$OUT"; exit 1
  fi
  prev_line="$line"
done
echo "ok: AC#1 banner + 5 sections in order"

# ========================================================================
# AC #2 — drafts to promote counts DRAFT markers in docs/LESSONS.md.
#         agent-fleet has 2, digitalcraft has 1 → total 3.
# ========================================================================
DRAFTS_LINE=$(grep -nF -- "drafts to promote" "$OUT" | head -1 | cut -d: -f1)
DRAFTS_BLOCK="$(awk -v n="$DRAFTS_LINE" 'NR>=n && NR<n+5' "$OUT")"
if ! echo "$DRAFTS_BLOCK" | grep -qE '^drafts to promote[[:space:]]+3'; then
  echo "FAIL: AC#2 drafts headline should be 3"
  echo "$DRAFTS_BLOCK"; exit 1
fi
if ! echo "$DRAFTS_BLOCK" | grep -qE 'agent-fleet[[:space:]]+2 drafts'; then
  echo "FAIL: AC#2 agent-fleet row should be '2 drafts'"
  echo "$DRAFTS_BLOCK"; exit 1
fi
if ! echo "$DRAFTS_BLOCK" | grep -qE 'digitalcraft[[:space:]]+1 draft'; then
  echo "FAIL: AC#2 digitalcraft row should be '1 draft'"
  echo "$DRAFTS_BLOCK"; exit 1
fi
echo "ok: AC#2 drafts to promote"

# ========================================================================
# AC #3 — self-cancel expiring lists <=7d projects + EXPIRED projects.
#         digitalcraft = 5d, courtiq = EXPIRED.
# ========================================================================
SC_LINE=$(grep -nF -- "self-cancel expiring (<=7d)" "$OUT" | head -1 | cut -d: -f1)
SC_BLOCK="$(awk -v n="$SC_LINE" 'NR>=n && NR<n+5' "$OUT")"
if ! echo "$SC_BLOCK" | grep -qE 'digitalcraft[[:space:]]+5d'; then
  echo "FAIL: AC#3 digitalcraft should be '5d'"
  echo "$SC_BLOCK"; exit 1
fi
if ! echo "$SC_BLOCK" | grep -qE 'courtiq[[:space:]]+EXPIRED'; then
  echo "FAIL: AC#3 courtiq should be 'EXPIRED'"
  echo "$SC_BLOCK"; exit 1
fi
if ! echo "$SC_BLOCK" | grep -qF 'bump SELF_CANCEL in agents.config.sh'; then
  echo "FAIL: AC#3 remediation hint missing"
  echo "$SC_BLOCK"; exit 1
fi
echo "ok: AC#3 self-cancel expiring"

# ========================================================================
# AC #4 — paused projects lists agent-ship label in launchctl disabled.
# ========================================================================
PA_LINE=$(grep -nF -- "paused projects" "$OUT" | head -1 | cut -d: -f1)
PA_BLOCK="$(awk -v n="$PA_LINE" 'NR>=n && NR<n+4' "$OUT")"
if ! echo "$PA_BLOCK" | grep -qE '^paused projects[[:space:]]+1'; then
  echo "FAIL: AC#4 paused headline should be 1"
  echo "$PA_BLOCK"; exit 1
fi
if ! echo "$PA_BLOCK" | grep -qE 'courtiq[[:space:]]+paused 14d ago'; then
  echo "FAIL: AC#4 courtiq row should be 'paused 14d ago'"
  echo "$PA_BLOCK"; exit 1
fi
if ! echo "$PA_BLOCK" | grep -qF 'launchctl enable gui/$UID/com.courtiq.agent-ship'; then
  echo "FAIL: AC#4 paused remediation hint missing"
  echo "$PA_BLOCK"; exit 1
fi
echo "ok: AC#4 paused projects"

# ========================================================================
# AC #5 — budget tripped today counts budget_block events in today's UTC
#         window. digitalcraft has one today, one yesterday (skip).
# ========================================================================
BG_LINE=$(grep -nF -- "budget tripped today" "$OUT" | head -1 | cut -d: -f1)
BG_BLOCK="$(awk -v n="$BG_LINE" 'NR>=n && NR<n+4' "$OUT")"
if ! echo "$BG_BLOCK" | grep -qE '^budget tripped today[[:space:]]+1'; then
  echo "FAIL: AC#5 budget headline should be 1"
  echo "$BG_BLOCK"; exit 1
fi
if ! echo "$BG_BLOCK" | grep -qF 'digitalcraft' || ! echo "$BG_BLOCK" | grep -qF '$5.00'; then
  echo "FAIL: AC#5 digitalcraft \$5.00 row missing"
  echo "$BG_BLOCK"; exit 1
fi
if ! echo "$BG_BLOCK" | grep -qF 'bump MAX_DAILY_USD or wait for tomorrow'; then
  echo "FAIL: AC#5 budget remediation hint missing"
  echo "$BG_BLOCK"; exit 1
fi
echo "ok: AC#5 budget tripped today"

# ========================================================================
# AC #6 — in-flight agent PRs >24h old (gh stub returns 1 for agent-fleet).
# ========================================================================
PR_LINE=$(grep -nF -- "in-flight agent PRs >24h old" "$OUT" | head -1 | cut -d: -f1)
PR_BLOCK="$(awk -v n="$PR_LINE" 'NR>=n && NR<n+4' "$OUT")"
if ! echo "$PR_BLOCK" | grep -qE '^in-flight agent PRs >24h old[[:space:]]+1'; then
  echo "FAIL: AC#6 stuck PR headline should be 1"
  echo "$PR_BLOCK"; exit 1
fi
if ! echo "$PR_BLOCK" | grep -qE 'agent-fleet[[:space:]]+PR #187'; then
  echo "FAIL: AC#6 agent-fleet PR #187 missing"
  echo "$PR_BLOCK"; exit 1
fi
echo "ok: AC#6 in-flight agent PRs"

# Negative branch: when gh is absent, the section renders '(skipped: gh not
# available)' and counts as 0. We can't simply strip $HOME/.local/bin from
# PATH because the system $PATH may have a real gh installed (homebrew).
# Build a tight whitelist PATH that contains only the dirs we need + the
# stub for launchctl, but NOT the gh stub or the system gh.
mkdir -p "$TMP/nogh-bin"
cp "$HOME/.local/bin/launchctl" "$TMP/nogh-bin/launchctl"
# Minimal coreutils-only PATH that excludes both $HOME/.local/bin and
# /opt/homebrew/bin (where gh might live on macOS) and /usr/local/bin.
NO_GH_PATH="$TMP/nogh-bin:/usr/bin:/bin:/usr/sbin:/sbin"
set +e
PATH="$NO_GH_PATH" "$FLEET" inbox > "$TMP/inbox.nogh.txt" 2>/dev/null
NOGH_EXIT=$?
set -e
if [ "$NOGH_EXIT" != "0" ]; then
  echo "FAIL: AC#6 inbox should exit 0 even when gh is absent, got $NOGH_EXIT"
  cat "$TMP/inbox.nogh.txt"; exit 1
fi
if ! grep -qF '(skipped: gh not available)' "$TMP/inbox.nogh.txt"; then
  echo "FAIL: AC#6 expected '(skipped: gh not available)' when gh absent"
  cat "$TMP/inbox.nogh.txt"; exit 1
fi
echo "ok: AC#6 in-flight PRs degrades without gh"

# ========================================================================
# AC #7 — trailing 'nothing else owes you a click. last weekly: ...' line.
#         First-run: no marker → 'last weekly: never'.
# ========================================================================
if ! grep -qF 'nothing else owes you a click.' "$OUT"; then
  echo "FAIL: AC#7 trailing 'nothing else owes you a click' line missing"
  tail -3 "$OUT"; exit 1
fi
if ! grep -qF 'last weekly: never' "$OUT"; then
  echo "FAIL: AC#7 first-run should print 'last weekly: never'"
  tail -3 "$OUT"; exit 1
fi
echo "ok: AC#7 trailing line (first-run branch)"

# Cached-weekly branch: drop a marker, re-run, expect '<Nh|Nd> ago'.
WEEKLY_MARKER="$HOME/.cache/fleet/last-weekly-run"
# Stamp 2d ago.
echo "$T_2D_AGO" > "$WEEKLY_MARKER"
LOCAL_2D="$(date -r "$T_2D_AGO" +%Y%m%d%H%M.%S 2>/dev/null || date -d "@$T_2D_AGO" +%Y%m%d%H%M.%S)"
touch -t "$LOCAL_2D" "$WEEKLY_MARKER"
"$FLEET" inbox > "$TMP/inbox.weekly.txt"
if ! grep -qE 'last weekly: 2d ago' "$TMP/inbox.weekly.txt"; then
  echo "FAIL: AC#7 cached-weekly branch should print 'last weekly: 2d ago'"
  tail -3 "$TMP/inbox.weekly.txt"; exit 1
fi
echo "ok: AC#7 trailing line (cached-weekly branch)"

# ========================================================================
# AC #8 — "since last run <Nh|Nd> ago" header reads $XDG_CACHE_HOME/fleet/
#         inbox-state; first invocation prints 'since last run: never'.
# ========================================================================
# We already verified the first invocation above (banner regex). After the
# first run the marker should be written; second run should yield '0h ago'
# or '0m ago' immediately.
INBOX_STATE="$HOME/.cache/fleet/inbox-state"
if [ ! -f "$INBOX_STATE" ]; then
  echo "FAIL: AC#8 inbox-state marker not written on first run"
  exit 1
fi
"$FLEET" inbox > "$TMP/inbox.second.txt"
if ! head -1 "$TMP/inbox.second.txt" | grep -qE 'since last run [0-9]+[mhd] ago'; then
  echo "FAIL: AC#8 second-run banner should be 'since last run Nm/h/d ago'"
  head -1 "$TMP/inbox.second.txt"; exit 1
fi
echo "ok: AC#8 inbox-state marker"

# ========================================================================
# AC #9 — --json prints one JSON object per section + 1 summary object.
# ========================================================================
"$FLEET" inbox --json > "$TMP/inbox.json"
# 5 section rows + 1 summary row = 6 lines.
LINES=$(wc -l < "$TMP/inbox.json" | tr -d ' ')
if [ "$LINES" != "6" ]; then
  echo "FAIL: AC#9 expected 6 JSON lines, got $LINES"
  cat "$TMP/inbox.json"; exit 1
fi
node -e '
  const fs = require("fs");
  const lines = fs.readFileSync(process.argv[1], "utf8").trim().split("\n");
  if (lines.length !== 6) { console.error("FAIL JSON line count " + lines.length); process.exit(1); }
  const expected_sections = ["drafts","self_cancel","paused","budget","stuck_prs"];
  const seen = [];
  let summary_seen = false;
  for (const ln of lines) {
    const o = JSON.parse(ln);
    if (o.summary === true) {
      summary_seen = true;
      for (const k of ["summary","sections","items","since_last_run_seconds"]) {
        if (!(k in o)) { console.error("FAIL summary missing key " + k); process.exit(1); }
      }
      if (o.sections !== 5) { console.error("FAIL summary.sections=" + o.sections); process.exit(1); }
    } else {
      for (const k of ["section","count","items"]) {
        if (!(k in o)) { console.error("FAIL section missing key " + k); process.exit(1); }
      }
      seen.push(o.section);
      if (!Array.isArray(o.items)) { console.error("FAIL section.items not array for " + o.section); process.exit(1); }
      for (const it of o.items) {
        for (const k of ["slug","count","hint"]) {
          if (!(k in it)) { console.error("FAIL item missing key " + k); process.exit(1); }
        }
      }
    }
  }
  if (!summary_seen) { console.error("FAIL summary not emitted"); process.exit(1); }
  for (const s of expected_sections) {
    if (!seen.includes(s)) { console.error("FAIL section " + s + " not emitted"); process.exit(1); }
  }
  console.log("ok: AC#9 --json shape");
' "$TMP/inbox.json"

# ========================================================================
# AC #10 — --slug filters every section to one project; empty sections
#          still render with 0.
# ========================================================================
"$FLEET" inbox --slug agent-fleet > "$TMP/inbox.slug.txt"
# Other projects should not appear under any section row.
if grep -E '^  digitalcraft' "$TMP/inbox.slug.txt"; then
  echo "FAIL: AC#10 --slug should suppress digitalcraft rows"
  cat "$TMP/inbox.slug.txt"; exit 1
fi
if grep -E '^  courtiq' "$TMP/inbox.slug.txt"; then
  echo "FAIL: AC#10 --slug should suppress courtiq rows"
  cat "$TMP/inbox.slug.txt"; exit 1
fi
# All five section headlines still print (even with 0).
for section in "${expected_order[@]}"; do
  if ! grep -qF -- "$section" "$TMP/inbox.slug.txt"; then
    echo "FAIL: AC#10 section '$section' missing from --slug output"
    cat "$TMP/inbox.slug.txt"; exit 1
  fi
done
echo "ok: AC#10 --slug filter"

# ========================================================================
# AC #11 — exit 0 even when sections have items; exit 2 only on usage err.
# ========================================================================
# Default invocation already exited 0 above with non-zero items. Confirm
# exit 2 on usage error.
set +e
"$FLEET" inbox --slug "" 2>/dev/null
USAGE_EXIT=$?
set -e
if [ "$USAGE_EXIT" != "2" ]; then
  echo "FAIL: AC#11 empty --slug should exit 2, got $USAGE_EXIT"; exit 1
fi
set +e
"$FLEET" inbox --bogus 2>/dev/null
BOGUS_EXIT=$?
set -e
if [ "$BOGUS_EXIT" != "2" ]; then
  echo "FAIL: AC#11 unknown flag should exit 2, got $BOGUS_EXIT"; exit 1
fi
echo "ok: AC#11 exit codes"

# ========================================================================
# AC #12 — no new event types. Assert the inbox() function does not call
#          fleet_emit_event.
# ========================================================================
INBOX_FN_BODY="$(awk '
  /^inbox\(\) \{/,/^\}/
' "$REPO_ROOT/bin/fleet")"
if echo "$INBOX_FN_BODY" | grep -q 'fleet_emit_event'; then
  echo "FAIL: AC#12 inbox() must not call fleet_emit_event (no new event types)"
  exit 1
fi
echo "ok: AC#12 inbox() emits no new events"

# Bonus: help text mentions inbox in the README "Daily ops" block.
README="$REPO_ROOT/README.md"
if ! grep -qF -- 'fleet inbox' "$README"; then
  echo "FAIL: README does not mention 'fleet inbox'"; exit 1
fi
echo "ok: README mentions fleet inbox"

# Bonus: golden file match.
if [ ! -f "$GOLDEN" ]; then
  echo "FAIL: golden file missing at $GOLDEN"; exit 1
fi
# Re-run with FIRST-run state (delete the markers so banner + trailing
# line are stable) so the golden is reproducible across local + CI runs.
rm -f "$INBOX_STATE" "$WEEKLY_MARKER"
"$FLEET" inbox > "$TMP/inbox.golden.out.txt"
if ! diff -u "$GOLDEN" "$TMP/inbox.golden.out.txt"; then
  echo "FAIL: golden byte-match failed (see diff above)"; exit 1
fi
echo "ok: golden byte-match"

echo "ok: tests/inbox.sh passed"
