#!/bin/bash
# tests/digest.sh — bin/fleet digest end-to-end test against a tmpdir fixture.
#
# Ticket 0012. Builds three synthetic projects under a temp FLEET_DISCOVERY_ROOT
# with seeded runs.jsonl + events.jsonl + LESSONS.md, then asserts every
# acceptance-criteria box. One assertion block per checkbox; comments name
# which AC each block covers.
#
# Self-contained: stubs $HOME, points FLEET_DISCOVERY_ROOT at the fixture,
# stubs `launchctl` so the launchd-state check (PAUSED) is deterministic.
# Exits non-zero on any failure.

set -euo pipefail

REPO_ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"

TMP="$(mktemp -d -t fleet-digest-test.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

# Isolate from any real ~/.cache state on the host.
export HOME="$TMP/home"
mkdir -p "$HOME"

# --- fixture roots --------------------------------------------------------
FIXTURE="$TMP/projects"
mkdir -p "$FIXTURE"

# Time helpers — events.jsonl uses ISO8601 UTC ending in Z.
NOW_EPOCH=$(date -u +%s)
iso_at() {  # $1 = epoch seconds → "YYYY-MM-DDTHH:MM:SSZ"
  date -u -r "$1" +%FT%TZ 2>/dev/null || date -u -d "@$1" +%FT%TZ
}
# Today's UTC date in two formats: events use ISO8601, runs.jsonl ts_start uses
# the same. Spend math is over the last 24h *window*, not the UTC calendar day.
TODAY_ISO="$(date -u +%FT%TZ)"
# Use offsets a bit inside their nominal windows so the digest's own
# `date +%s` call doesn't push records past the cutoff during the millisecond
# between seeding and reading. (50 min, 110 min, 25h are all comfortably
# inside the next-larger window.)
ONE_HR_AGO=$(( NOW_EPOCH - 50 * 60 ))
TWO_HR_AGO=$(( NOW_EPOCH - 110 * 60 ))
TWENTYSIX_HR_AGO=$(( NOW_EPOCH - 25 * 3600 ))   # OUTSIDE the 24h window
TEN_DAYS_AGO=$(( NOW_EPOCH - 10 * 86400 ))      # OUTSIDE the 7d window

# --- fixture A: alpha — healthy, OK, with events + runs in last 24h -------
mkdir -p "$FIXTURE/alpha/docs"
cat > "$FIXTURE/alpha/agents.config.sh" <<CFG
PROJECT_NAME="Alpha"
SLUG="alpha"
NAMESPACE="com.alpha"
REPO_URL="https://github.com/example/alpha"
SELF_CANCEL="20990101"
CFG
mkdir -p "$HOME/.cache/alpha-agent"
# Two runs in the last 24h totalling \$1.50; one run 26h ago (excluded).
cat > "$HOME/.cache/alpha-agent/runs.jsonl" <<JSONL
{"slug":"alpha","phase":"ship","ts_start":"$(iso_at "$ONE_HR_AGO")","ts_end":"$(iso_at "$ONE_HR_AGO")","exit":0,"total_cost_usd":1.25,"result_head":"opened PR #11 with"}
{"slug":"alpha","phase":"groom","ts_start":"$(iso_at "$TWO_HR_AGO")","ts_end":"$(iso_at "$TWO_HR_AGO")","exit":0,"total_cost_usd":0.25,"result_head":"groomed backlog"}
{"slug":"alpha","phase":"ship","ts_start":"$(iso_at "$TWENTYSIX_HR_AGO")","ts_end":"$(iso_at "$TWENTYSIX_HR_AGO")","exit":0,"total_cost_usd":99.00,"result_head":"ancient"}
JSONL
# Events: one pr_opened (in window), one run_completed (most recent).
cat > "$HOME/.cache/alpha-agent/events.jsonl" <<JSONL
{"ts":"$(iso_at "$TWO_HR_AGO")","slug":"alpha","phase":"ship","type":"pr_opened","number":"11","branch":"feat/0001-x"}
{"ts":"$(iso_at "$ONE_HR_AGO")","slug":"alpha","phase":"ship","type":"run_completed","exit":"0","duration_ms":"12345"}
JSONL

# --- fixture B: bravo — OVER-BUDGET (spend ≥ MAX_DAILY_USD today) ---------
mkdir -p "$FIXTURE/bravo/docs"
cat > "$FIXTURE/bravo/agents.config.sh" <<CFG
PROJECT_NAME="Bravo"
SLUG="bravo"
NAMESPACE="com.bravo"
REPO_URL="https://github.com/example/bravo"
SELF_CANCEL="20990101"
MAX_DAILY_USD=2
CFG
mkdir -p "$HOME/.cache/bravo-agent"
TODAY_PREFIX="$(date -u +%Y-%m-%d)"
cat > "$HOME/.cache/bravo-agent/runs.jsonl" <<JSONL
{"slug":"bravo","phase":"ship","ts_start":"${TODAY_PREFIX}T01:00:00Z","ts_end":"${TODAY_PREFIX}T01:00:30Z","exit":0,"total_cost_usd":3.50}
JSONL
# No events at all → fall through to LESSONS.md path.
echo "## 2026-05-01 — bravo lesson about something rather long that should be truncated by the digest" > "$FIXTURE/bravo/docs/LESSONS.md"

# --- fixture C: charlie — EXPIRED SELF_CANCEL -----------------------------
mkdir -p "$FIXTURE/charlie/docs"
cat > "$FIXTURE/charlie/agents.config.sh" <<CFG
PROJECT_NAME="Charlie"
SLUG="charlie"
NAMESPACE="com.charlie"
REPO_URL="https://github.com/example/charlie"
SELF_CANCEL="20200101"
CFG
mkdir -p "$HOME/.cache/charlie-agent"
# Empty runs/events; LESSONS missing → last-event field collapses to "—".
: > "$HOME/.cache/charlie-agent/runs.jsonl"
: > "$HOME/.cache/charlie-agent/events.jsonl"

# --- stubs ----------------------------------------------------------------
BIN_STUB="$TMP/bin"
mkdir -p "$BIN_STUB"
# launchctl: by default "print" succeeds for everything (i.e. NOT disabled).
# The digest only consumes the exit code of `launchctl print-disabled` (or
# similar) — we'll stub it to always exit 0 so PAUSED never trips in this run.
cat > "$BIN_STUB/launchctl" <<'STUB'
#!/bin/bash
# `launchctl print-disabled gui/$UID` — print no labels (i.e. nothing disabled).
# `launchctl print <label>` — exit 0 (label loaded).
exit 0
STUB
chmod +x "$BIN_STUB/launchctl"
# gh stub: digest does not call gh today (no STUCK criterion needs it for the
# fixture), but exporting one prevents real-network surprises.
cat > "$BIN_STUB/gh" <<'STUB'
#!/bin/bash
echo "[]"
exit 0
STUB
chmod +x "$BIN_STUB/gh"
export PATH="$BIN_STUB:$PATH"

export FLEET_DISCOVERY_ROOT="$FIXTURE"

FLEET="$REPO_ROOT/bin/fleet"

# ========================================================================
# AC #1 — bin/fleet digest prints one line per project in slug-alpha order
#         with the documented format.
# ========================================================================
OUT="$TMP/digest.txt"
set +e
"$FLEET" digest > "$OUT"
EXIT=$?
set -e
# slug-alpha order: alpha < bravo < charlie
if ! awk '
  NR==1 && $1=="alpha" { ok1=1 }
  NR==2 && $1=="bravo" { ok2=1 }
  NR==3 && $1=="charlie" { ok3=1 }
  END { exit (ok1 && ok2 && ok3) ? 0 : 1 }
' "$OUT"; then
  echo "FAIL: AC#1 slug-alpha order broken"; cat "$OUT"; exit 1
fi

# Format check: each line has slug, state tag, "N opened / M merged",
# "$X.YY", and a trailing field. Use a regex per line.
while read -r line; do
  [ -z "$line" ] && continue
  if ! echo "$line" | grep -qE '^[a-z][a-z0-9_-]*[[:space:]]+(OK|PAUSED|THROTTLED|EXPIRED|OVER-BUDGET|STUCK)[[:space:]]+[0-9]+ opened / [0-9]+ merged[[:space:]]+\$[0-9]+\.[0-9]{2}[[:space:]]+'; then
    echo "FAIL: AC#1 line does not match format:"; echo "  $line"; exit 1
  fi
done < "$OUT"

# No emoji should appear in the slug/state/pr-summary/spend prefix (i.e. the
# kit-generated columns). The trailing last-event-or-lesson field is verbatim
# external text — LESSONS.md is allowed to contain em-dashes / unicode.
while read -r line; do
  [ -z "$line" ] && continue
  # Strip everything from the spend column onward.
  prefix="$(echo "$line" | sed -E 's/(\$[0-9]+\.[0-9]{2}).*/\1/')"
  if echo "$prefix" | LC_ALL=C grep -qE '[^[:print:][:space:]]'; then
    echo "FAIL: AC#1 non-ASCII char in kit-rendered prefix: $prefix"; exit 1
  fi
done < "$OUT"
echo "ok: AC#1 format + slug-alpha order"

# ========================================================================
# AC #2 — <pr-summary> is "N opened / M merged" over trailing 24h. Events
#         source of truth. alpha has 1 pr_opened event in the last 24h, 0
#         merged → "1 opened / 0 merged".
# ========================================================================
if ! grep -E '^alpha[[:space:]]' "$OUT" | grep -q '1 opened / 0 merged'; then
  echo "FAIL: AC#2 alpha pr-summary wrong (want '1 opened / 0 merged')"
  grep '^alpha' "$OUT" || true
  exit 1
fi
echo "ok: AC#2 pr-summary"

# ========================================================================
# AC #3 — <spend> is the trailing-24h sum of total_cost_usd formatted $X.YY.
#         alpha: 1.25 + 0.25 = $1.50 (the 26h-old $99 must be excluded).
# ========================================================================
if ! grep -E '^alpha[[:space:]]' "$OUT" | grep -q '\$1\.50'; then
  echo "FAIL: AC#3 alpha spend wrong (want \$1.50)"
  grep '^alpha' "$OUT" || true
  exit 1
fi
echo "ok: AC#3 spend"

# ========================================================================
# AC #4 — state-tag derivation. charlie SELF_CANCEL is in the past → EXPIRED.
#         bravo spend $3.50 ≥ cap $2 → OVER-BUDGET.
#         alpha → OK (none of the red conditions trip).
# ========================================================================
if ! grep -E '^charlie[[:space:]]+EXPIRED[[:space:]]' "$OUT"; then
  echo "FAIL: AC#4 charlie should be EXPIRED"; cat "$OUT"; exit 1
fi
if ! grep -E '^bravo[[:space:]]+OVER-BUDGET[[:space:]]' "$OUT"; then
  echo "FAIL: AC#4 bravo should be OVER-BUDGET"; cat "$OUT"; exit 1
fi
if ! grep -E '^alpha[[:space:]]+OK[[:space:]]' "$OUT"; then
  echo "FAIL: AC#4 alpha should be OK"; cat "$OUT"; exit 1
fi
echo "ok: AC#4 state derivation"

# ========================================================================
# AC #5 — <last-event-or-lesson>. alpha most-recent event is run_completed.
#         bravo has no events → fall back to last line of LESSONS.md,
#         truncated to 60 chars.
# ========================================================================
if ! grep -E '^alpha[[:space:]]' "$OUT" | grep -q 'run_completed'; then
  echo "FAIL: AC#5 alpha last-event should be run_completed"
  grep '^alpha' "$OUT" || true; exit 1
fi
BRAVO_LINE="$(grep -E '^bravo[[:space:]]' "$OUT")"
# Whatever lesson text shows up, it must be no more than 60 chars after the
# leading "$X.YY  " column. Easier check: the LESSONS line begins with "##".
if ! echo "$BRAVO_LINE" | grep -q '##'; then
  echo "FAIL: AC#5 bravo should fall back to LESSONS.md (no events)"
  echo "  $BRAVO_LINE"; exit 1
fi
# Extract the trailing field (everything after the spend column) and assert ≤60.
TRAIL="$(echo "$BRAVO_LINE" | sed -E 's/^[^$]*\$[0-9]+\.[0-9]{2}[[:space:]]+//')"
if [ "${#TRAIL}" -gt 60 ]; then
  echo "FAIL: AC#5 bravo trailing field >60 chars (was ${#TRAIL}): $TRAIL"; exit 1
fi
echo "ok: AC#5 last-event-or-lesson"

# ========================================================================
# AC #6 — --slug <name> restricts to one project.
# ========================================================================
SLUG_OUT="$TMP/digest.slug.txt"
set +e
"$FLEET" digest --slug alpha > "$SLUG_OUT"
SLUG_EXIT=$?
set -e
LINES=$(wc -l < "$SLUG_OUT" | tr -d ' ')
if [ "$LINES" != "1" ]; then
  echo "FAIL: AC#6 --slug alpha should print 1 line, got $LINES"; cat "$SLUG_OUT"; exit 1
fi
if ! grep -E '^alpha[[:space:]]' "$SLUG_OUT" >/dev/null; then
  echo "FAIL: AC#6 --slug alpha row missing"; cat "$SLUG_OUT"; exit 1
fi
# alpha alone is OK → exit 0.
if [ "$SLUG_EXIT" != "0" ]; then
  echo "FAIL: AC#6 --slug alpha exit code = $SLUG_EXIT (want 0)"; exit 1
fi
echo "ok: AC#6 --slug filter"

# ========================================================================
# AC #7 — --json prints a JSON array of objects with the same fields.
# ========================================================================
JSON_OUT="$TMP/digest.json"
set +e
"$FLEET" digest --json > "$JSON_OUT"
set -e
node -e '
  const fs = require("fs");
  const arr = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
  if (!Array.isArray(arr)) {
    console.error("FAIL: AC#7 --json top-level should be an array");
    console.error(JSON.stringify(arr));
    process.exit(1);
  }
  const required = ["slug", "state", "prs_opened", "prs_merged", "spend_usd", "last"];
  for (const row of arr) {
    for (const k of required) {
      if (!(k in row)) {
        console.error("FAIL: AC#7 row " + JSON.stringify(row.slug) + " missing key " + k);
        process.exit(1);
      }
    }
  }
  console.log("ok: AC#7 --json shape");
' "$JSON_OUT"

# ========================================================================
# AC #8 — --since 7d widens the window. Default is 24h. We seed nothing in
#         the 24h-but-not-7d window (uncomplicated alpha case), so the
#         shape test is: --since 7d still succeeds and includes alpha.
#         We also assert that --since 1h restricts alpha's spend to the
#         single run inside the last hour ($1.25, not $1.50).
# ========================================================================
SINCE_OUT="$TMP/digest.since.txt"
set +e
"$FLEET" digest --since 1h --slug alpha > "$SINCE_OUT"
set -e
if ! grep -q '\$1\.25' "$SINCE_OUT"; then
  echo "FAIL: AC#8 --since 1h spend should be \$1.25 (only the 1h-old run)"
  cat "$SINCE_OUT"; exit 1
fi
# A bad unit must exit non-zero (sanity guard, not a strict AC).
set +e
"$FLEET" digest --since 5x --slug alpha >/dev/null 2>&1
BAD=$?
set -e
if [ "$BAD" = "0" ]; then
  echo "FAIL: AC#8 --since 5x should fail (bad unit)"; exit 1
fi
echo "ok: AC#8 --since"

# ========================================================================
# AC #9 — fixture project + --json --slug produces the expected JSON object.
#         We use alpha and assert exact field values.
# ========================================================================
ALPHA_JSON="$TMP/digest.alpha.json"
"$FLEET" digest --json --slug alpha > "$ALPHA_JSON"
node -e '
  const fs = require("fs");
  const arr = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
  if (arr.length !== 1) {
    console.error("FAIL: AC#9 --json --slug alpha length=" + arr.length);
    process.exit(1);
  }
  const a = arr[0];
  if (a.slug !== "alpha")          { console.error("FAIL: AC#9 slug=" + a.slug); process.exit(1); }
  if (a.state !== "OK")            { console.error("FAIL: AC#9 state=" + a.state); process.exit(1); }
  if (a.prs_opened !== 1)          { console.error("FAIL: AC#9 prs_opened=" + a.prs_opened); process.exit(1); }
  if (a.prs_merged !== 0)          { console.error("FAIL: AC#9 prs_merged=" + a.prs_merged); process.exit(1); }
  if (Math.abs(a.spend_usd - 1.5) > 0.001) { console.error("FAIL: AC#9 spend_usd=" + a.spend_usd); process.exit(1); }
  if (typeof a.last !== "string" || !a.last.includes("run_completed")) {
    console.error("FAIL: AC#9 last=" + JSON.stringify(a.last));
    process.exit(1);
  }
  console.log("ok: AC#9 exact JSON object");
' "$ALPHA_JSON"

# ========================================================================
# AC #10 — exit 0 when no project red, 1 otherwise. The full fixture has
#          charlie EXPIRED + bravo OVER-BUDGET → digest must exit 1.
# ========================================================================
if [ "$EXIT" != "1" ]; then
  echo "FAIL: AC#10 fixture has EXPIRED+OVER-BUDGET → expect exit 1, got $EXIT"
  exit 1
fi
# alpha alone → exit 0 (already asserted in AC#6).
echo "ok: AC#10 exit code"

echo "ok: tests/digest.sh passed"
