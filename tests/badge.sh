#!/bin/bash
# tests/badge.sh — `bin/fleet badge <slug>` shareable-ROI-shield test.
#
# Ticket 0027. One assertion block per acceptance-criteria checkbox in
# docs/backlog/0027-fleet-badge-shareable-roi-shield.md.
#
# Fixture (one synthetic project at tests/fixtures/badge/agent-fleet)
# seeded under a tmpdir FLEET_DISCOVERY_ROOT, mirroring tests/weekly.sh.
# The runs.jsonl + log mtimes are seeded into $HOME/.cache so the
# in-window metrics (3 PRs, $5.83, "6h ago") match the goldens at
# tests/fixtures/badge.{md,svg,txt}.golden.txt byte-for-byte.
#
# Network-free guarantee: `gh` and `curl` stubs in $HOME/.local/bin
# fail-on-invoke so AC#4 (SVG path makes no HTTP call) is exercised
# structurally — any badge code that shells out to gh/curl breaks
# every assertion.
#
# Stub placement: $HOME/.local/bin per LESSONS 2026-05-26 (bin/fleet
# does NOT source common.sh today, but the same dir keeps the test
# rig portable when a future ticket flips that).

set -euo pipefail

REPO_ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
FLEET="$REPO_ROOT/bin/fleet"
GOLDEN_MD="$REPO_ROOT/tests/fixtures/badge.md.golden.txt"
GOLDEN_SVG="$REPO_ROOT/tests/fixtures/badge.svg.golden.txt"
GOLDEN_TXT="$REPO_ROOT/tests/fixtures/badge.txt.golden.txt"

TMP="$(mktemp -d -t fleet-badge-test.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

# Isolate HOME so $HOME/.cache and any installed copies are sandboxed.
export HOME="$TMP/home"
mkdir -p "$HOME/.local/bin"

# --- Stubs: gh + curl fail-on-invoke ---------------------------------
# AC#4 says the SVG path makes NO network call. The fail-on-invoke
# stubs make that a structural property: if the implementation EVER
# shells out to gh or curl while rendering, every assertion breaks.
# LESSONS 2026-05-30: -F -- guards a pattern that starts with `-`.
cat > "$HOME/.local/bin/gh" <<'STUB'
#!/bin/bash
echo "gh stub: badge MUST NOT call gh (got: $*)" >&2
exit 99
STUB
chmod +x "$HOME/.local/bin/gh"
cat > "$HOME/.local/bin/curl" <<'STUB'
#!/bin/bash
echo "curl stub: badge MUST NOT call curl (got: $*)" >&2
exit 99
STUB
chmod +x "$HOME/.local/bin/curl"
export PATH="$HOME/.local/bin:$PATH"

# --- Fixture: point FLEET_DISCOVERY_ROOT at the checked-in tree ------
# Use cp -R per LESSONS 2026-05-27 — never $(cat …) when round-tripping
# file content; here we just want a writable copy of the fixture dir.
FIXTURE="$TMP/projects"
mkdir -p "$FIXTURE"
cp -R "$REPO_ROOT/tests/fixtures/badge/agent-fleet" "$FIXTURE/agent-fleet"
export FLEET_DISCOVERY_ROOT="$FIXTURE"

# Seed the project cache: 3 SHIP rows summing to $5.83 in the trailing
# 30d window, plus an out-of-window row that must NOT contribute.
AF_CACHE="$HOME/.cache/agent-fleet-agent"
mkdir -p "$AF_CACHE/logs"

NOW_EPOCH=$(date -u +%s)
iso_at() { date -u -r "$1" +%FT%TZ 2>/dev/null || date -u -d "@$1" +%FT%TZ; }

T_1D_AGO=$(( NOW_EPOCH - 1 * 86400 ))
T_2D_AGO=$(( NOW_EPOCH - 2 * 86400 ))
T_3D_AGO=$(( NOW_EPOCH - 3 * 86400 ))
T_40D_AGO=$(( NOW_EPOCH - 40 * 86400 ))
T_LOG_MTIME=$(( NOW_EPOCH - 6 * 3600 - 60 ))   # 6h 1min ago — falls in the "Xh ago" bucket

{
  printf '{"slug":"agent-fleet","phase":"ship","ts_start":"%s","ts_end":"%s","exit":0,"total_cost_usd":1.94,"result_head":"SHIP 0001-x — PR #101 green"}\n' \
    "$(iso_at "$T_3D_AGO")" "$(iso_at $(( T_3D_AGO + 60 )))"
  printf '{"slug":"agent-fleet","phase":"ship","ts_start":"%s","ts_end":"%s","exit":0,"total_cost_usd":1.94,"result_head":"SHIP 0002-y — PR #102 green"}\n' \
    "$(iso_at "$T_2D_AGO")" "$(iso_at $(( T_2D_AGO + 60 )))"
  printf '{"slug":"agent-fleet","phase":"ship","ts_start":"%s","ts_end":"%s","exit":0,"total_cost_usd":1.95,"result_head":"SHIP 0003-z — PR #103 green"}\n' \
    "$(iso_at "$T_1D_AGO")" "$(iso_at $(( T_1D_AGO + 60 )))"
  # Out-of-window: 40d ago. Must NOT count.
  printf '{"slug":"agent-fleet","phase":"ship","ts_start":"%s","ts_end":"%s","exit":0,"total_cost_usd":9.99,"result_head":"SHIP 0099-w — PR #1 green"}\n' \
    "$(iso_at "$T_40D_AGO")" "$(iso_at $(( T_40D_AGO + 60 )))"
  # In-window non-ship (groom) — spend ignored by ship_count; spend SUM
  # via digest_spend_since takes EVERYTHING in-window, so we keep this
  # at $0.00 to leave the 5.83 total intact.
  printf '{"slug":"agent-fleet","phase":"groom","ts_start":"%s","ts_end":"%s","exit":0,"total_cost_usd":0.00,"result_head":"GROOM refreshed 4 tickets"}\n' \
    "$(iso_at "$T_2D_AGO")" "$(iso_at $(( T_2D_AGO + 60 )))"
} > "$AF_CACHE/runs.jsonl"

# events.jsonl — empty for the cold-event branch (AC#8). The badge
# does NOT read events for v1 metrics (per engineering notes — events
# is reserved for the future color-thresholds ticket), so any content
# here is irrelevant to the current goldens. We seed an empty file so
# the cache layout matches a real project.
: > "$AF_CACHE/events.jsonl"

# Touch the log file to a deterministic mtime so "last ship Xh ago"
# is stable across runs. macOS `touch -t` takes LOCAL time; convert
# the UTC epoch through the same local-tz dance as tests/weekly.sh.
echo "fixture ship log" > "$AF_CACHE/logs/2026-06-01.log"
LOG_STAMP="$(date -r "$T_LOG_MTIME" +%Y%m%d%H%M.%S 2>/dev/null \
              || date -d "@$T_LOG_MTIME" +%Y%m%d%H%M.%S)"
touch -t "$LOG_STAMP" "$AF_CACHE/logs/2026-06-01.log"

# ========================================================================
# AC #1 — default invocation: --since 30d --format md, exits 0, one
#         line, byte-exact match against the md golden.
# ========================================================================
OUT="$TMP/badge.md.out"
set +e
"$FLEET" badge agent-fleet > "$OUT"
EXIT=$?
set -e
if [ "$EXIT" != "0" ]; then
  echo "FAIL: AC#1 default badge should exit 0, got $EXIT"; cat "$OUT"; exit 1
fi
LINES=$(wc -l < "$OUT" | tr -d ' ')
if [ "$LINES" != "1" ]; then
  echo "FAIL: AC#1 expected exactly 1 output line, got $LINES"; cat "$OUT"; exit 1
fi
if ! diff -u "$GOLDEN_MD" "$OUT"; then
  echo "FAIL: AC#1 md output does not byte-match golden"; exit 1
fi
# URL-encoded markers must appear (the AC's belt-and-suspenders check).
for tok in 'agent--fleet' '%20PRs' '%245.83' '%2F%2030d'; do
  if ! grep -qF -- "$tok" "$OUT"; then
    echo "FAIL: AC#1 missing URL-encoded token '$tok'"; cat "$OUT"; exit 1
  fi
done
echo "ok: AC#1 default md output matches golden"

# ========================================================================
# AC #2 — --since Nh|Nd parsed via digest_parse_since. Valid 30d, 7d,
#         48h. Invalid 'forever' → exit 2 + documented stderr message.
# ========================================================================
"$FLEET" badge agent-fleet --since 7d  > "$TMP/since-7d.txt"
grep -qF -- '%2F%207d'  "$TMP/since-7d.txt"  || { echo "FAIL: AC#2 --since 7d label missing"; cat "$TMP/since-7d.txt"; exit 1; }
"$FLEET" badge agent-fleet --since 48h > "$TMP/since-48h.txt"
grep -qF -- '%2F%2048h' "$TMP/since-48h.txt" || { echo "FAIL: AC#2 --since 48h label missing"; cat "$TMP/since-48h.txt"; exit 1; }
"$FLEET" badge agent-fleet --since 30d > "$TMP/since-30d.txt"
grep -qF -- '%2F%2030d' "$TMP/since-30d.txt" || { echo "FAIL: AC#2 --since 30d label missing"; cat "$TMP/since-30d.txt"; exit 1; }

set +e
"$FLEET" badge agent-fleet --since forever 2>"$TMP/since-err.txt" >/dev/null
SINCE_EXIT=$?
set -e
if [ "$SINCE_EXIT" != "2" ]; then
  echo "FAIL: AC#2 invalid --since forever should exit 2, got $SINCE_EXIT"; exit 1
fi
if ! grep -qF -- 'badge: invalid --since "forever" (use Nh or Nd)' "$TMP/since-err.txt"; then
  echo "FAIL: AC#2 stderr missing documented error"; cat "$TMP/since-err.txt"; exit 1
fi
echo "ok: AC#2 --since parsing (valid + invalid)"

# ========================================================================
# AC #3 — --format md is default; markdown image + link + HTML
#         comment marker; anchor target is REPO_URL.
# ========================================================================
# Verify the link target points at the manifest's REPO_URL (NOT the
# kit repo) and the HTML comment marker is intact.
grep -qF -- '](https://github.com/mutaaf/agent-fleet)' "$OUT" \
  || { echo "FAIL: AC#3 md anchor target is not the manifest REPO_URL"; cat "$OUT"; exit 1; }
grep -qF -- '<!-- generated by fleet badge -->' "$OUT" \
  || { echo "FAIL: AC#3 md regenerate marker missing"; cat "$OUT"; exit 1; }
echo "ok: AC#3 md format markdown image + link + marker"

# ========================================================================
# AC #4 — --format svg is self-contained, NO network call (the curl/gh
#         stubs would fire and break this). XML prelude + closing tag.
# ========================================================================
SVG_OUT="$TMP/badge.svg.out"
"$FLEET" badge agent-fleet --format svg > "$SVG_OUT"
head -1 "$SVG_OUT" | grep -qF -- '<?xml version' \
  || { echo "FAIL: AC#4 svg head is not the XML prelude"; head -3 "$SVG_OUT"; exit 1; }
tail -1 "$SVG_OUT" | grep -qF -- '</svg>' \
  || { echo "FAIL: AC#4 svg tail is not </svg>"; tail -3 "$SVG_OUT"; exit 1; }
if ! diff -u "$GOLDEN_SVG" "$SVG_OUT"; then
  echo "FAIL: AC#4 svg output does not byte-match golden"; exit 1
fi
# Optional xmllint check — if available, the SVG must parse.
if command -v xmllint >/dev/null 2>&1; then
  if ! xmllint --noout "$SVG_OUT" 2>"$TMP/xmllint.err"; then
    echo "FAIL: AC#4 svg failed xmllint"; cat "$TMP/xmllint.err"; exit 1
  fi
fi
echo "ok: AC#4 svg format self-contained (no network)"

# ========================================================================
# AC #5 — --format txt plain string; "last ship Xh ago" from
#         newest_log_epoch + human_age.
# ========================================================================
TXT_OUT="$TMP/badge.txt.out"
"$FLEET" badge agent-fleet --format txt > "$TXT_OUT"
if ! diff -u "$GOLDEN_TXT" "$TXT_OUT"; then
  echo "FAIL: AC#5 txt output does not byte-match golden"; exit 1
fi
echo "ok: AC#5 txt format ntfy/email body"

# ========================================================================
# AC #6 — PR-count metric via weekly_ship_count_since. Test the
#         singular form `1 PR` when count is 1, plus the default `3
#         PRs` plural the earlier golden already covers.
# ========================================================================
# Drop a 1-PR fixture under a separate slug.
SOLO_DIR="$TMP/projects-solo"
mkdir -p "$SOLO_DIR/solo"
cat > "$SOLO_DIR/solo/agents.config.sh" <<CFG
PROJECT_NAME="Solo"
SLUG="solo"
NAMESPACE="com.solo"
REPO_URL="https://github.com/example/solo"
SELF_CANCEL="20260801"
CFG
SOLO_CACHE="$HOME/.cache/solo-agent"
mkdir -p "$SOLO_CACHE/logs"
printf '{"slug":"solo","phase":"ship","ts_start":"%s","ts_end":"%s","exit":0,"total_cost_usd":0.50,"result_head":"SHIP 0010-x — PR #999 green"}\n' \
  "$(iso_at "$T_1D_AGO")" "$(iso_at $(( T_1D_AGO + 60 )))" > "$SOLO_CACHE/runs.jsonl"
: > "$SOLO_CACHE/events.jsonl"
echo "fixture solo ship log" > "$SOLO_CACHE/logs/2026-06-01.log"
touch -t "$LOG_STAMP" "$SOLO_CACHE/logs/2026-06-01.log"

FLEET_DISCOVERY_ROOT="$SOLO_DIR" "$FLEET" badge solo --format txt > "$TMP/solo.txt"
if ! grep -qF -- '1 PR,' "$TMP/solo.txt"; then
  echo "FAIL: AC#6 singular '1 PR' missing for 1-ship project"; cat "$TMP/solo.txt"; exit 1
fi
# And the default-fixture plural is already golden-checked above.
grep -qF -- '3%20PRs' "$OUT" \
  || { echo "FAIL: AC#6 plural '3 PRs' missing from md golden"; exit 1; }
echo "ok: AC#6 PR-count singular/plural"

# ========================================================================
# AC #7 — Spend metric via digest_spend_since. $5.83 (non-zero) and
#         $0.00 (zero) branches.
# ========================================================================
grep -qF -- '%245.83' "$OUT" \
  || { echo "FAIL: AC#7 non-zero spend \$5.83 missing from md golden"; exit 1; }

# Zero-spend project.
ZERO_DIR="$TMP/projects-zero"
mkdir -p "$ZERO_DIR/zero"
cat > "$ZERO_DIR/zero/agents.config.sh" <<CFG
PROJECT_NAME="Zero"
SLUG="zero"
NAMESPACE="com.zero"
REPO_URL="https://github.com/example/zero"
SELF_CANCEL="20260801"
CFG
mkdir -p "$HOME/.cache/zero-agent/logs"
: > "$HOME/.cache/zero-agent/runs.jsonl"
: > "$HOME/.cache/zero-agent/events.jsonl"

FLEET_DISCOVERY_ROOT="$ZERO_DIR" "$FLEET" badge zero --format txt > "$TMP/zero.txt"
if ! grep -qF -- '$0.00' "$TMP/zero.txt"; then
  echo "FAIL: AC#7 zero-spend project should render \$0.00"; cat "$TMP/zero.txt"; exit 1
fi
echo "ok: AC#7 spend metric (\$5.83 + \$0.00 branches)"

# ========================================================================
# AC #8 — Cold project (zero events AND zero runs) still renders with
#         `0 PRs, $0.00`; HTML comment marker intact.
# ========================================================================
FLEET_DISCOVERY_ROOT="$ZERO_DIR" "$FLEET" badge zero > "$TMP/zero.md"
grep -qF -- '0%20PRs' "$TMP/zero.md" \
  || { echo "FAIL: AC#8 cold project should show '0 PRs'"; cat "$TMP/zero.md"; exit 1; }
grep -qF -- '%240.00' "$TMP/zero.md" \
  || { echo "FAIL: AC#8 cold project should show '\$0.00'"; cat "$TMP/zero.md"; exit 1; }
grep -qF -- '<!-- generated by fleet badge -->' "$TMP/zero.md" \
  || { echo "FAIL: AC#8 cold project HTML comment marker missing"; cat "$TMP/zero.md"; exit 1; }
echo "ok: AC#8 cold project renders honestly"

# ========================================================================
# AC #9 — Unknown slug: documented error + exit 2.
# ========================================================================
set +e
"$FLEET" badge no-such-project 2>"$TMP/unknown-err.txt" >/dev/null
UNK_EXIT=$?
set -e
if [ "$UNK_EXIT" != "2" ]; then
  echo "FAIL: AC#9 unknown slug should exit 2, got $UNK_EXIT"; exit 1
fi
if ! grep -qF -- 'badge: no project with SLUG=no-such-project found' "$TMP/unknown-err.txt"; then
  echo "FAIL: AC#9 unknown-slug error message wrong"
  cat "$TMP/unknown-err.txt"; exit 1
fi
if ! grep -qF -- "FLEET_DISCOVERY_ROOT=$FIXTURE" "$TMP/unknown-err.txt"; then
  echo "FAIL: AC#9 unknown-slug error should name FLEET_DISCOVERY_ROOT"
  cat "$TMP/unknown-err.txt"; exit 1
fi
echo "ok: AC#9 unknown slug → exit 2"

# ========================================================================
# AC #10 — Help banner mentions --since, --format, --repo, --help.
#          LESSONS 2026-05-30: grep -qF -- guards leading-dash patterns.
# ========================================================================
HELP_OUT="$TMP/badge.help.txt"
"$FLEET" badge --help > "$HELP_OUT" || true
for kw in 'fleet badge' '--since' '--format' '--repo' '--help' 'md' 'svg' 'txt'; do
  if ! grep -qF -- "$kw" "$HELP_OUT"; then
    echo "FAIL: AC#10 help missing '$kw'"; cat "$HELP_OUT"; exit 1
  fi
done
echo "ok: AC#10 help banner"

# ========================================================================
# AC #11 — --repo <URL> overrides the manifest's REPO_URL for the
#          markdown anchor target. Different anchor on the override path.
# ========================================================================
OVERRIDE_URL="https://example.com/fork-of-agent-fleet"
"$FLEET" badge agent-fleet --repo "$OVERRIDE_URL" > "$TMP/override.md"
grep -qF -- "]($OVERRIDE_URL)" "$TMP/override.md" \
  || { echo "FAIL: AC#11 --repo override missing from md anchor"; cat "$TMP/override.md"; exit 1; }
# The manifest's REPO_URL should NOT appear when overridden.
if grep -qF -- '](https://github.com/mutaaf/agent-fleet)' "$TMP/override.md"; then
  echo "FAIL: AC#11 manifest REPO_URL leaked into overridden anchor"
  cat "$TMP/override.md"; exit 1
fi
echo "ok: AC#11 --repo override"

# ========================================================================
# AC #12 — No new event types. The badge() function source must not
#          contain fleet_emit_event. Extract the function body and
#          grep it the same way tests/weekly.sh does.
# ========================================================================
BADGE_FN_BODY="$(awk '
  /^badge\(\) \{/,/^\}/
' "$REPO_ROOT/bin/fleet")"
if echo "$BADGE_FN_BODY" | grep -q 'fleet_emit_event'; then
  echo "FAIL: AC#12 badge() must not call fleet_emit_event (no new event types)"
  exit 1
fi
echo "ok: AC#12 badge() emits no new events"

# ========================================================================
# AC #13 — Structural test-rig assertions. (Counts as the all-twelve-
#          boxes umbrella check.)
#   * $HOME/.local/bin stubs present
#   * FLEET_DISCOVERY_ROOT pointed at the fixture
#   * gh + curl fail-on-invoke (proves the SVG path made no network call —
#     if it had, EXIT would have been 99 above and the diff would fail)
# ========================================================================
[ -x "$HOME/.local/bin/gh" ]   || { echo "FAIL: AC#13 gh stub missing"; exit 1; }
[ -x "$HOME/.local/bin/curl" ] || { echo "FAIL: AC#13 curl stub missing"; exit 1; }
[ -d "$FIXTURE/agent-fleet" ]  || { echo "FAIL: AC#13 fixture project missing"; exit 1; }
echo "ok: AC#13 test rig (stubs + fixture)"

echo "ok: tests/badge.sh passed"
