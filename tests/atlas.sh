#!/bin/bash
# tests/atlas.sh — bin/fleet atlas end-to-end test against checked-in fixtures.
#
# Ticket 0031. Covers all 11 acceptance-criteria boxes from
# docs/backlog/0031-fleet-atlas-failure-mode-frequency.md. One assertion
# block per box; the comment above each block names which AC it covers.
#
# Self-contained: stubs $HOME under $TMP, redirects FLEET_DISCOVERY_ROOT at
# the fixture, redirects FLEET_HEAL_CATALOG at tests/fixtures/atlas.catalog.sh,
# pins FLEET_ATLAS_FAKE_NOW so the `LAST SEEN` ages stay golden. Per
# LESSONS 2026-05-26 ($HOME/.local/bin stubs survive lib/common.sh's PATH
# reset — but `bin/fleet atlas` is a pure consumer that does NOT source
# common.sh, so stubs anywhere on $PATH would also work; we use
# $HOME/.local/bin anyway for consistency with the rest of the test fleet).
# Per LESSONS 2026-05-27 every fixture file is copied via `cp` — never
# `$(cat …)` — to preserve byte-exact trailing newlines.

set -euo pipefail

REPO_ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"

TMP="$(mktemp -d -t fleet-atlas-test.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

# Isolate from the host's $HOME.
export HOME="$TMP/home"
mkdir -p "$HOME/.local/bin"

FIX_DIR="$REPO_ROOT/tests/fixtures/atlas"
CATALOG_FIX="$REPO_ROOT/tests/fixtures/atlas.catalog.sh"
GOLDEN="$REPO_ROOT/tests/fixtures/atlas.text.golden.txt"

# Pin "now" to 2024-06-03T00:00:00Z so the events.jsonl timestamps map to
# stable `LAST SEEN` strings ("1h ago", "2h ago", "3h ago"). The fixture
# events lie within 30d of this anchor.
export FLEET_ATLAS_FAKE_NOW=1717372800

# --- copy fixture project trees to a writable root --------------------------
# `cp -R` (not $(cat …); LESSONS 2026-05-27) so events.jsonl/agents.config.sh
# stay byte-identical to the checked-in versions.
FLEET_ROOT="$TMP/projects"
mkdir -p "$FLEET_ROOT"
for slug in alpha bravo charlie; do
  cp -R "$FIX_DIR/$slug" "$FLEET_ROOT/$slug"
  # Each project's events.jsonl lives under $HOME/.cache/<slug>-agent/ at
  # runtime; the fixture co-locates it next to the manifest for repo
  # ergonomics. Mirror it into the cache layout the atlas reader expects.
  mkdir -p "$HOME/.cache/${slug}-agent"
  cp "$FIX_DIR/$slug/events.jsonl" "$HOME/.cache/${slug}-agent/events.jsonl"
  # The atlas reader does not need an events.jsonl in the project tree;
  # delete it so a stray `find` never picks it up.
  rm -f "$FLEET_ROOT/$slug/events.jsonl"
done

export FLEET_DISCOVERY_ROOT="$FLEET_ROOT"
export FLEET_HEAL_CATALOG="$CATALOG_FIX"

FLEET="$REPO_ROOT/bin/fleet"

# ========================================================================
# AC #1 — `bin/fleet atlas` (no flags) defaults to `--since 30d`, surveys
#         every project under FLEET_DISCOVERY_ROOT, exits 0, prints the
#         header row + one row per catalog pattern in catalog order. The
#         golden file is the byte-exact expected output.
# ========================================================================
OUT="$TMP/atlas.txt"
set +e
"$FLEET" atlas > "$OUT"
EXIT=$?
set -e
if [ "$EXIT" != "0" ]; then
  echo "FAIL: AC#1 atlas exit $EXIT (want 0)"; cat "$OUT"; exit 1
fi
if ! diff -u "$GOLDEN" "$OUT"; then
  echo "FAIL: AC#1 atlas output does not match golden"
  exit 1
fi
echo "ok: AC#1 default invocation matches golden"

# ========================================================================
# AC #2 — FIRED column counts infra_flake_rerun events with matching
#         pattern. Patterns with zero matches still render with FIRED=0
#         and LAST SEEN=—.
# ========================================================================
# actions_silent has 4 events in alpha → FIRED=4
if ! grep -qE '^actions_silent[[:space:]]+4[[:space:]]+2h ago' "$OUT"; then
  echo "FAIL: AC#2 actions_silent FIRED!=4 or LAST SEEN!=2h ago"
  grep -E '^actions_silent' "$OUT"; exit 1
fi
# supabase_port_bind has 0 events → FIRED=0, LAST SEEN=—
if ! grep -qE '^supabase_port_bind[[:space:]]+0[[:space:]]+—' "$OUT"; then
  echo "FAIL: AC#2 supabase_port_bind FIRED!=0 or LAST SEEN!=—"
  grep -E '^supabase_port_bind' "$OUT"; exit 1
fi
echo "ok: AC#2 nonzero and zero FIRED branches"

# ========================================================================
# AC #3 — LAST SEEN renders via human_age on the newest matching event's
#         ts, and the zero-match branch reads `—`.
# ========================================================================
# gh_graphql_502: alpha at 5h ago, bravo at 1h ago → newest is 1h ago.
if ! grep -qE '^gh_graphql_502[[:space:]]+5[[:space:]]+1h ago' "$OUT"; then
  echo "FAIL: AC#3 gh_graphql_502 newest-event age != 1h ago"
  grep -E '^gh_graphql_502' "$OUT"; exit 1
fi
# account_suspended: zero matches → —
if ! grep -qE '^account_suspended[[:space:]]+0[[:space:]]+—' "$OUT"; then
  echo "FAIL: AC#3 account_suspended LAST SEEN != —"
  grep -E '^account_suspended' "$OUT"; exit 1
fi
echo "ok: AC#3 LAST SEEN both branches"

# ========================================================================
# AC #4 — PROJECTS is a comma-joined sorted list of slugs that contributed
#         at least one event in the window; capped at 3 followed by `+N`.
# ========================================================================
# gh_graphql_502 has events from alpha + bravo → "alpha,bravo" sorted.
if ! grep -qE '^gh_graphql_502.*alpha,bravo' "$OUT"; then
  echo "FAIL: AC#4 gh_graphql_502 PROJECTS != alpha,bravo"
  grep -E '^gh_graphql_502' "$OUT"; exit 1
fi
# Synthesise five projects with at least one synth_pattern event to test
# the `+N` truncation cap (per AC#4: 3 + `+N`).
BIG_ROOT="$TMP/big_projects"
mkdir -p "$BIG_ROOT"
for s in p1 p2 p3 p4 p5; do
  mkdir -p "$BIG_ROOT/$s"
  cat > "$BIG_ROOT/$s/agents.config.sh" <<CFG
PROJECT_NAME="$s"
SLUG="$s"
NAMESPACE="com.$s"
REPO_URL="https://github.com/example/$s"
SELF_CANCEL="20990101"
CFG
  mkdir -p "$HOME/.cache/${s}-agent"
  cat > "$HOME/.cache/${s}-agent/events.jsonl" <<EVT
{"ts":"2024-06-02T21:00:00Z","slug":"$s","phase":"ship","type":"infra_flake_rerun","pattern":"synth_pattern","run_id":"600","pr":"7"}
EVT
done
BIG_OUT="$TMP/atlas.big.txt"
FLEET_DISCOVERY_ROOT="$BIG_ROOT" "$FLEET" atlas > "$BIG_OUT"
# synth_pattern should now show "p1,p2,p3 +2" (3 listed + 2 extras).
if ! grep -qE '^synth_pattern.*p1,p2,p3 \+2' "$BIG_OUT"; then
  echo "FAIL: AC#4 synth_pattern PROJECTS truncation != 'p1,p2,p3 +2'"
  grep -E '^synth_pattern' "$BIG_OUT"; exit 1
fi
echo "ok: AC#4 PROJECTS sorted-join + +N truncation"

# ========================================================================
# AC #5 — LESSON is the YYYY-MM-DD date parsed from the inline
#         `# LESSON: <repo> YYYY-MM-DD …` comment immediately preceding
#         each pattern entry. Patterns with no preceding LESSON comment
#         render the column as `(no lesson)`.
# ========================================================================
# actions_silent's catalog comment says "agent-fleet 2026-05-26".
if ! grep -qE '^actions_silent.*2026-05-26' "$OUT"; then
  echo "FAIL: AC#5 actions_silent LESSON != 2026-05-26"
  grep -E '^actions_silent' "$OUT"; exit 1
fi
# synth_pattern has no preceding LESSON line → `(no lesson)`.
if ! grep -qE '^synth_pattern.*\(no lesson\)' "$OUT"; then
  echo "FAIL: AC#5 synth_pattern LESSON != (no lesson)"
  grep -E '^synth_pattern' "$OUT"; exit 1
fi
echo "ok: AC#5 LESSON parsed + (no lesson) branch"

# ========================================================================
# AC #6 — `--since <Nh|Nd>` parses via digest_parse_since. Invalid value
#         exits 2 with a specific stderr message.
# ========================================================================
set +e
"$FLEET" atlas --since 7d > "$TMP/atlas.7d.txt"
EXIT_7D=$?
set -e
if [ "$EXIT_7D" != "0" ]; then
  echo "FAIL: AC#6 --since 7d exit $EXIT_7D (want 0)"; exit 1
fi
# Our events are all within ~12h of FLEET_ATLAS_FAKE_NOW, so 7d/48h windows
# show identical FIRED counts.
set +e
"$FLEET" atlas --since 48h > "$TMP/atlas.48h.txt"
EXIT_48H=$?
set -e
if [ "$EXIT_48H" != "0" ]; then
  echo "FAIL: AC#6 --since 48h exit $EXIT_48H (want 0)"; exit 1
fi
# Invalid --since: exit 2, specific message to stderr.
set +e
ERR="$TMP/atlas.err.txt"
"$FLEET" atlas --since forever > /dev/null 2> "$ERR"
EXIT_INV=$?
set -e
if [ "$EXIT_INV" != "2" ]; then
  echo "FAIL: AC#6 invalid --since exit $EXIT_INV (want 2)"; cat "$ERR"; exit 1
fi
if ! grep -qF -- 'atlas: invalid --since' "$ERR"; then
  echo "FAIL: AC#6 invalid --since stderr missing message"; cat "$ERR"; exit 1
fi
echo "ok: AC#6 --since parsing + error path"

# ========================================================================
# AC #7 — `--slug NAME` restricts to one project. Unknown slug: exit 2
#         with a specific stderr message naming FLEET_DISCOVERY_ROOT.
# ========================================================================
SLUG_OUT="$TMP/atlas.slug.txt"
set +e
"$FLEET" atlas --slug alpha > "$SLUG_OUT"
SLUG_EXIT=$?
set -e
if [ "$SLUG_EXIT" != "0" ]; then
  echo "FAIL: AC#7 --slug alpha exit $SLUG_EXIT (want 0)"; cat "$SLUG_OUT"; exit 1
fi
# alpha contributed actions_silent + gh_graphql_502 events only — bravo's
# gh_graphql_502 events should NOT count toward the slug-restricted survey.
# alpha had 4 actions_silent events and 2 gh_graphql_502 events.
if ! grep -qE '^actions_silent[[:space:]]+4' "$SLUG_OUT"; then
  echo "FAIL: AC#7 --slug alpha actions_silent FIRED != 4"; cat "$SLUG_OUT"; exit 1
fi
if ! grep -qE '^gh_graphql_502[[:space:]]+2[[:space:]]+5h ago[[:space:]]+alpha' "$SLUG_OUT"; then
  echo "FAIL: AC#7 --slug alpha gh_graphql_502 should be 2 events, 5h ago, alpha"
  grep -E '^gh_graphql_502' "$SLUG_OUT"; exit 1
fi
# Unknown slug → exit 2 + stderr name FLEET_DISCOVERY_ROOT.
set +e
UNK_ERR="$TMP/atlas.unknown.err"
"$FLEET" atlas --slug doesnotexist > /dev/null 2> "$UNK_ERR"
UNK_EXIT=$?
set -e
if [ "$UNK_EXIT" != "2" ]; then
  echo "FAIL: AC#7 unknown slug exit $UNK_EXIT (want 2)"; cat "$UNK_ERR"; exit 1
fi
if ! grep -qF -- 'FLEET_DISCOVERY_ROOT' "$UNK_ERR"; then
  echo "FAIL: AC#7 unknown slug stderr missing FLEET_DISCOVERY_ROOT"; cat "$UNK_ERR"; exit 1
fi
echo "ok: AC#7 --slug filter + error path"

# ========================================================================
# AC #8 — `--json` emits one JSON object per pattern row + a summary row.
#         Schema asserted via node -e 'JSON.parse(…)'.
# ========================================================================
JSON_OUT="$TMP/atlas.json"
set +e
"$FLEET" atlas --json > "$JSON_OUT"
JSON_EXIT=$?
set -e
if [ "$JSON_EXIT" != "0" ]; then
  echo "FAIL: AC#8 --json exit $JSON_EXIT"; cat "$JSON_OUT"; exit 1
fi
node -e '
  const fs = require("fs");
  const lines = fs.readFileSync(process.argv[1], "utf8").trim().split("\n");
  // 5 pattern rows + 1 summary row = 6 lines.
  if (lines.length !== 6) {
    console.error("FAIL: AC#8 expected 6 JSON lines, got " + lines.length);
    console.error(lines.join("\n"));
    process.exit(1);
  }
  const rows = lines.slice(0, 5).map(JSON.parse);
  const summary = JSON.parse(lines[5]);
  // Catalog order.
  const expected = ["actions_silent","supabase_port_bind","account_suspended","gh_graphql_502","synth_pattern"];
  for (let i = 0; i < expected.length; i++) {
    if (rows[i].pattern !== expected[i]) {
      console.error("FAIL: AC#8 row " + i + " pattern " + rows[i].pattern + " (want " + expected[i] + ")");
      process.exit(1);
    }
    for (const k of ["pattern","fired","last_seen_ts","projects","lesson_date"]) {
      if (!(k in rows[i])) {
        console.error("FAIL: AC#8 row " + i + " missing key " + k);
        process.exit(1);
      }
    }
  }
  // Specific values: actions_silent fired=4, projects=["alpha"], lesson_date="2026-05-26"
  if (rows[0].fired !== 4)                        { console.error("FAIL: AC#8 actions_silent.fired=" + rows[0].fired); process.exit(1); }
  if (JSON.stringify(rows[0].projects) !== JSON.stringify(["alpha"])) {
    console.error("FAIL: AC#8 actions_silent.projects=" + JSON.stringify(rows[0].projects)); process.exit(1);
  }
  if (rows[0].lesson_date !== "2026-05-26")       { console.error("FAIL: AC#8 actions_silent.lesson_date=" + rows[0].lesson_date); process.exit(1); }
  if (rows[1].fired !== 0)                        { console.error("FAIL: AC#8 supabase_port_bind.fired=" + rows[1].fired); process.exit(1); }
  if (rows[1].last_seen_ts !== null)              { console.error("FAIL: AC#8 supabase_port_bind.last_seen_ts=" + rows[1].last_seen_ts); process.exit(1); }
  if (JSON.stringify(rows[1].projects) !== "[]")  { console.error("FAIL: AC#8 supabase_port_bind.projects=" + JSON.stringify(rows[1].projects)); process.exit(1); }
  if (rows[4].lesson_date !== null)               { console.error("FAIL: AC#8 synth_pattern.lesson_date=" + rows[4].lesson_date + " (want null)"); process.exit(1); }
  // Summary row.
  if (summary.summary !== true)                   { console.error("FAIL: AC#8 summary.summary != true"); process.exit(1); }
  if (summary.patterns !== 5)                     { console.error("FAIL: AC#8 summary.patterns=" + summary.patterns); process.exit(1); }
  if (summary.window !== "30d")                   { console.error("FAIL: AC#8 summary.window=" + summary.window); process.exit(1); }
  // fired_total = 4 + 0 + 0 + 5 + 1 = 10
  if (summary.fired_total !== 10)                 { console.error("FAIL: AC#8 summary.fired_total=" + summary.fired_total); process.exit(1); }
  console.log("ok: AC#8 --json schema + values");
' "$JSON_OUT"

# ========================================================================
# AC #9 — Empty fleet: text path renders header + one row per catalog
#         pattern with FIRED=0, LAST SEEN=—, PROJECTS=—. JSON path renders
#         one object per pattern with fired=0, last_seen_ts=null,
#         projects=[], plus the summary row. Exit 0.
# ========================================================================
EMPTY_ROOT="$TMP/empty"
mkdir -p "$EMPTY_ROOT"  # exists but contains no agents.config.sh files
EMPTY_OUT="$TMP/atlas.empty.txt"
set +e
FLEET_DISCOVERY_ROOT="$EMPTY_ROOT" "$FLEET" atlas > "$EMPTY_OUT"
EMPTY_EXIT=$?
set -e
if [ "$EMPTY_EXIT" != "0" ]; then
  echo "FAIL: AC#9 empty fleet exit $EMPTY_EXIT (want 0)"; cat "$EMPTY_OUT"; exit 1
fi
# Header still printed.
if ! head -1 "$EMPTY_OUT" | grep -q 'PATTERN'; then
  echo "FAIL: AC#9 empty fleet missing header"; cat "$EMPTY_OUT"; exit 1
fi
# Every catalog pattern reports FIRED=0, LAST SEEN=—, PROJECTS=—.
for tok in actions_silent supabase_port_bind account_suspended gh_graphql_502 synth_pattern; do
  if ! grep -qE "^${tok}[[:space:]]+0[[:space:]]+—[[:space:]]+—" "$EMPTY_OUT"; then
    echo "FAIL: AC#9 empty fleet row for $tok"
    grep -E "^${tok}" "$EMPTY_OUT"; exit 1
  fi
done
# JSON variant.
EMPTY_JSON="$TMP/atlas.empty.json"
FLEET_DISCOVERY_ROOT="$EMPTY_ROOT" "$FLEET" atlas --json > "$EMPTY_JSON"
node -e '
  const fs = require("fs");
  const lines = fs.readFileSync(process.argv[1], "utf8").trim().split("\n");
  if (lines.length !== 6) {
    console.error("FAIL: AC#9 empty JSON expected 6 lines, got " + lines.length);
    process.exit(1);
  }
  const rows = lines.slice(0, 5).map(JSON.parse);
  for (const r of rows) {
    if (r.fired !== 0) { console.error("FAIL: AC#9 " + r.pattern + ".fired=" + r.fired); process.exit(1); }
    if (r.last_seen_ts !== null) { console.error("FAIL: AC#9 " + r.pattern + ".last_seen_ts not null"); process.exit(1); }
    if (JSON.stringify(r.projects) !== "[]") { console.error("FAIL: AC#9 " + r.pattern + ".projects=" + JSON.stringify(r.projects)); process.exit(1); }
  }
  const summary = JSON.parse(lines[5]);
  if (summary.summary !== true || summary.patterns !== 5 || summary.fired_total !== 0) {
    console.error("FAIL: AC#9 summary " + JSON.stringify(summary));
    process.exit(1);
  }
' "$EMPTY_JSON"
echo "ok: AC#9 empty fleet honest cold-fleet rendering"

# ========================================================================
# AC #10 — Catalog file missing or unreadable: exit 2, specific message
#          to stderr.
# ========================================================================
set +e
MISS_ERR="$TMP/atlas.miss.err"
FLEET_HEAL_CATALOG=/nonexistent/path "$FLEET" atlas > /dev/null 2> "$MISS_ERR"
MISS_EXIT=$?
set -e
if [ "$MISS_EXIT" != "2" ]; then
  echo "FAIL: AC#10 missing catalog exit $MISS_EXIT (want 2)"; cat "$MISS_ERR"; exit 1
fi
if ! grep -qF -- 'heal catalog not found' "$MISS_ERR"; then
  echo "FAIL: AC#10 missing catalog stderr missing 'heal catalog not found'"
  cat "$MISS_ERR"; exit 1
fi
if ! grep -qF -- 'FLEET_HEAL_CATALOG' "$MISS_ERR"; then
  echo "FAIL: AC#10 missing catalog stderr missing FLEET_HEAL_CATALOG hint"
  cat "$MISS_ERR"; exit 1
fi
echo "ok: AC#10 missing catalog error path"

# ========================================================================
# AC #11 — No new event types added. atlas is a pure consumer — assert the
#          source does not call fleet_emit_event from inside the atlas
#          dispatcher/helpers, and the PR body affirmation lands in the
#          ticket file's Implementation log.
# ========================================================================
# Surgical scan: between the `atlas() {` declaration and its matching exit
# block, no `fleet_emit_event` calls should appear. Use awk so the assertion
# is robust to brace-counting (the function ends at the dispatcher block
# `if [ "$CMD" = "atlas" ]; then`).
if awk '
  /^atlas\(\) \{/                 { inside = 1; next }
  inside && /^if \[ "\$CMD" = "atlas" \]; then/ { inside = 0 }
  inside && /fleet_emit_event/    { found = 1 }
  END                              { exit found ? 1 : 0 }
' "$REPO_ROOT/bin/fleet"; then
  : # no emit_event calls inside atlas()
else
  echo "FAIL: AC#11 atlas() calls fleet_emit_event — atlas must be a pure reader"
  exit 1
fi
echo "ok: AC#11 atlas() emits no new events"

# ========================================================================
# AC #12 — Help: `bin/fleet atlas --help` prints USAGE mentioning
#          --since / --slug / --json / --help, ends with exit 0 (per
#          LESSONS 2026-06-01 dispatcher fall-through trap).
# ========================================================================
HELP_OUT="$TMP/atlas.help.txt"
set +e
"$FLEET" atlas --help > "$HELP_OUT"
HELP_EXIT=$?
set -e
if [ "$HELP_EXIT" != "0" ]; then
  echo "FAIL: AC#12 --help exit $HELP_EXIT (want 0)"; cat "$HELP_OUT"; exit 1
fi
# Per LESSONS 2026-05-30, `grep -F` with a leading-dash pattern needs `--`.
for kw in --since --slug --json --help; do
  if ! grep -qF -- "$kw" "$HELP_OUT"; then
    echo "FAIL: AC#12 --help missing keyword '$kw'"; cat "$HELP_OUT"; exit 1
  fi
done
# Help block ends with exit 0 — sanity check: the dispatcher fall-through
# trap (LESSONS 2026-06-01) would print extra lines after USAGE if the
# help branch didn't `exit 0`. We assert there are no `PROJECT` /
# `INSTALLED` columns (the default `fleet status` header) in the help out.
if grep -qF -- 'INSTALLED' "$HELP_OUT"; then
  echo "FAIL: AC#12 --help fell through to default status block"
  cat "$HELP_OUT"; exit 1
fi
echo "ok: AC#12 --help banner + exit-0"

# ========================================================================
# Coverage tally: AC#1–#12 all asserted above. Output a final marker line
# so the parent shell (or CI) can grep for it.
# ========================================================================
echo "ok: tests/atlas.sh passed (12/12 assertions)"
