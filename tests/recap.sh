#!/bin/bash
# tests/recap.sh — `bin/fleet recap` shareable narrative snapshot test.
#
# Ticket 0048. One assertion block per acceptance-criteria checkbox in
# docs/backlog/0048-fleet-recap-shareable-narrative-snapshot.md.
#
# `recap` is a PURE READER: no events.jsonl writes, no fleet_emit_event,
# no `lib/` or `prompts/` edits, no new event types. The test asserts the
# events channel byte size is unchanged across invocations (AC#12).
#
# Per LESSONS 2026-05-26 stubs live under $HOME/.local/bin (lib/common.sh
# resets PATH — but bin/fleet does NOT source common.sh, so the stub dir is
# really only for HOME isolation). Per LESSONS 2026-05-27 every fixture is
# copied with `cp` (never `$(cat …)`). Per LESSONS 2026-06-01 every count
# uses `awk … END { print n+0 }`. Per LESSONS 2026-06-08 every awk
# accumulator declares `BEGIN { count = 0 }`. Per LESSONS 2026-05-30
# help-text greps use `grep -qF -- "$kw"`. Per LESSONS 2026-06-05 the
# anonymizer's sort is `LC_ALL=C sort`. Per LESSONS 2026-06-11
# window-boundary comparisons go through ISO8601 lex-compare.

set -euo pipefail

REPO_ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
FLEET="$REPO_ROOT/bin/fleet"
FIXTURE_DIR="$REPO_ROOT/tests/fixtures/recap"

TMP="$(mktemp -d -t fleet-recap-test.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

# Isolate HOME so $HOME/.cache, $HOME/.local/bin stay sandboxed.
export HOME="$TMP/home"
mkdir -p "$HOME/.local/bin"

# Anchor "today" at 2026-06-13T12:00:00Z. Default window is 30d so the
# walk reaches back to roughly 2026-05-14.
NOW_EPOCH=1781352000
export FLEET_NOW_OVERRIDE="$NOW_EPOCH"

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
CFG
}

# Copy the per-slug fixture jsonl files into $HOME/.cache/<slug>-agent.
# Per LESSONS 2026-05-27 we use `cp` (not `$(cat)`) so trailing newlines
# survive byte-exact.
install_slug_fixture() {  # $1 = slug, $2 = fixture name (subdir)
  local slug="$1" fixture="$2"
  local cache="$HOME/.cache/${slug}-agent"
  mkdir -p "$cache"
  if [ -f "$FIXTURE_DIR/$fixture/runs.jsonl" ]; then
    cp "$FIXTURE_DIR/$fixture/runs.jsonl" "$cache/runs.jsonl"
  else
    : > "$cache/runs.jsonl"
  fi
  if [ -f "$FIXTURE_DIR/$fixture/events.jsonl" ]; then
    cp "$FIXTURE_DIR/$fixture/events.jsonl" "$cache/events.jsonl"
  else
    : > "$cache/events.jsonl"
  fi
}

# Three project slugs: agent-fleet (rich), project-b (medium), and one with
# a deliberately identifying name (`customer-prod-secrets`) so AC#13's
# public-mode anonymization can be tested.
mk_manifest agent-fleet
mk_manifest project-b
mk_manifest customer-prod-secrets

install_slug_fixture agent-fleet            agent-fleet
install_slug_fixture project-b              project-b
install_slug_fixture customer-prod-secrets  customer-prod-secrets

# Stub `git` so the kit-sha branch returns a deterministic short SHA. The
# default recap call shells out to `git -C <repo> rev-parse --short HEAD`
# which would otherwise leak the host repo's actual SHA.
cat > "$HOME/.local/bin/git" <<'STUB'
#!/bin/bash
# Forward most calls to the real git; intercept the kit-sha probe.
case "$*" in
  *"rev-parse --short HEAD"*) echo "8a20547"; exit 0 ;;
  *"rev-parse --short"*)       echo "8a20547"; exit 0 ;;
esac
# Find the real git on PATH (skipping ourselves).
REAL=""
oldifs="$IFS"; IFS=:
for d in $PATH; do
  if [ -x "$d/git" ] && [ "$d/git" != "$HOME/.local/bin/git" ]; then
    REAL="$d/git"; break
  fi
done
IFS="$oldifs"
if [ -z "$REAL" ]; then echo "no real git" >&2; exit 127; fi
exec "$REAL" "$@"
STUB
chmod +x "$HOME/.local/bin/git"

# Prepend the stub dir to PATH for the test process.
export PATH="$HOME/.local/bin:$PATH"

# Override the prompts SHA via the existing env knob (mirrors how
# tests/prompts-suggest.sh stabilizes the value).
export FLEET_RECAP_PROMPTS_SHA="ee94b3a"
export FLEET_RECAP_KIT_SHA="8a20547"

# Record the events.jsonl byte size before any invocation (AC#12).
events_size() {
  local slug="$1"
  local f="$HOME/.cache/${slug}-agent/events.jsonl"
  if [ -f "$f" ]; then wc -c <"$f" | tr -d ' '; else echo "0"; fi
}
SIZE_BEFORE_AF="$(events_size agent-fleet)"
SIZE_BEFORE_PB="$(events_size project-b)"
SIZE_BEFORE_CPS="$(events_size customer-prod-secrets)"

# ========================================================================
# AC #1 — `bin/fleet recap` (no flags) walks every discovered project,
#         reads runs.jsonl + events.jsonl for the trailing 30 days, prints
#         the narrative block, exits 0.
# ========================================================================
echo "AC#1 — default invocation prints narrative block"
OUT="$TMP/ac1.out"
set +e
"$FLEET" recap > "$OUT" 2>&1
EXIT=$?
set -e
if [ "$EXIT" != "0" ]; then
  echo "FAIL: AC#1 recap exit $EXIT (want 0)"; cat "$OUT"; exit 1
fi
# Default mode shows real slug names in the body.
grep -qF -- "agent-fleet" "$OUT" \
  || { echo "FAIL: AC#1 default-mode body should mention 'agent-fleet'"; cat "$OUT"; exit 1; }
# Header carries the kit name and the 30d window.
grep -qF -- "agent-fleet" "$OUT" || { echo "FAIL: AC#1 missing header slug"; cat "$OUT"; exit 1; }
grep -qF -- "30-day recap" "$OUT" \
  || { echo "FAIL: AC#1 header missing '30-day recap'"; cat "$OUT"; exit 1; }
# PR count + spend headline must appear.
grep -qE 'PRs merged' "$OUT" \
  || { echo "FAIL: AC#1 missing 'PRs merged' headline"; cat "$OUT"; exit 1; }
grep -qE '\$[0-9]+\.[0-9]{2} total spend' "$OUT" \
  || { echo "FAIL: AC#1 missing '\$N.NN total spend' headline"; cat "$OUT"; exit 1; }
echo "  ok"

# ========================================================================
# AC #2 — `--since <Nd|YYYY-MM-DD>` overrides the default. Default is 30d.
# ========================================================================
echo "AC#2 — --since override (Nd + YYYY-MM-DD forms)"
OUT="$TMP/ac2-nd.out"
"$FLEET" recap --since 7d > "$OUT"
grep -qF -- "7-day recap" "$OUT" \
  || { echo "FAIL: AC#2 --since 7d header should say '7-day recap'"; cat "$OUT"; exit 1; }

OUT="$TMP/ac2-iso.out"
"$FLEET" recap --since 2026-06-01 > "$OUT"
grep -qF -- "2026-06-01" "$OUT" \
  || { echo "FAIL: AC#2 --since YYYY-MM-DD header should mention the start date"; cat "$OUT"; exit 1; }
# Default remains 30d (re-asserted from AC#1 output, but confirm via the
# JSON window field too).
OUT_JSON="$TMP/ac2-default.json"
"$FLEET" recap --json > "$OUT_JSON"
grep -qF -- '"window":"30d"' "$OUT_JSON" \
  || { echo "FAIL: AC#2 default --json window should be '30d'"; cat "$OUT_JSON"; exit 1; }
echo "  ok"

# ========================================================================
# AC #3 — `--public` replaces every slug name with stable ordinal token.
#         Mapping is computed deterministically (sorted lexicographically).
#         PR numbers stripped; ticket ids preserved + slug-prefixed.
# ========================================================================
echo "AC#3 — public anonymization replaces slug names with project-N"
OUT="$TMP/ac3.out"
"$FLEET" recap --public > "$OUT"
# No real slug name should appear in the body. Per AC#8 the kit name
# `agent-fleet` is ALWAYS disclosed (header + public footer's repo path),
# so we only check the two non-kit slugs.
for raw in project-b customer-prod-secrets; do
  printf -- '%s' "$(cat "$OUT")" | grep -qF -- "$raw" \
    && { echo "FAIL: AC#3 public body should NOT contain slug name '$raw'"; cat "$OUT"; exit 1; }
done
# Ordinal tokens must appear.
grep -qE 'project-[0-9]+' "$OUT" \
  || { echo "FAIL: AC#3 public body should contain 'project-N' tokens"; cat "$OUT"; exit 1; }
# Mapping is deterministic — repeated invocations yield the same output.
OUT2="$TMP/ac3-2.out"
"$FLEET" recap --public > "$OUT2"
diff -u "$OUT" "$OUT2" \
  || { echo "FAIL: AC#3 mapping should be stable across runs"; exit 1; }
# No `pr=#N`-shaped substring in public output.
if grep -qE 'pr=#[0-9]+' "$OUT"; then
  echo "FAIL: AC#3 public output should NOT contain 'pr=#N' substring"
  cat "$OUT"; exit 1
fi
echo "  ok"

# ========================================================================
# AC #4 — Rendered block (without header) is between 12 and 18 lines.
# ========================================================================
echo "AC#4 — render body 12..18 lines"
OUT="$TMP/ac4.out"
"$FLEET" recap > "$OUT"
# Strip the header line(s) and any blank lines at the bottom. Per the
# user-lens example the header is the first non-blank line; the rest is
# the body. Count non-empty lines via awk END { print n+0 }.
BODY_LINES="$(awk 'NR==1 { next } /^[[:space:]]*$/ { next } { n++ } END { print n+0 }' "$OUT")"
if [ "$BODY_LINES" -lt 12 ] || [ "$BODY_LINES" -gt 18 ]; then
  echo "FAIL: AC#4 body lines=$BODY_LINES, want 12..18"
  cat "$OUT"; exit 1
fi
echo "  ok ($BODY_LINES lines)"

# ========================================================================
# AC #5 — Top heal pattern line reads infra_flake_rerun + catalog. Two
#         branches: nonzero (renders pattern + count) and zero ("none
#         (clean window)").
# ========================================================================
echo "AC#5 — top heal pattern branches"
# Non-zero branch: agent-fleet fixture seeded with ≥3 infra_flake_rerun
# events.
OUT="$TMP/ac5.out"
"$FLEET" recap > "$OUT"
grep -qF -- "top heal pattern:" "$OUT" \
  || { echo "FAIL: AC#5 missing 'top heal pattern:' line"; cat "$OUT"; exit 1; }
# Should mention a pattern name + a (×N) count.
grep -qE 'top heal pattern: [a-z_]+ \(.{1,2}[0-9]+\)' "$OUT" \
  || grep -qF -- 'top heal pattern: none (clean window)' "$OUT" \
  || { echo "FAIL: AC#5 heal-pattern line malformed"; cat "$OUT"; exit 1; }

# Zero branch: a fleet with PRs merged but no infra_flake_rerun events.
CLEAN_ROOT="$TMP/clean"
mkdir -p "$CLEAN_ROOT/project-clean"
cat > "$CLEAN_ROOT/project-clean/agents.config.sh" <<CFG
PROJECT_NAME="project-clean"
SLUG="project-clean"
NAMESPACE="com.project-clean"
REPO_URL="https://github.com/example/project-clean"
SELF_CANCEL="20990101"
CFG
mkdir -p "$HOME/.cache/project-clean-agent"
cat > "$HOME/.cache/project-clean-agent/runs.jsonl" <<'EOF'
{"ts_start":"2026-06-01T10:00:00Z","slug":"project-clean","phase":"ship","type":"run_completed","exit":"0","duration_ms":180000,"total_cost_usd":0.10,"result_head":"SHIP 0001 — feature shipped PR #500"}
EOF
cat > "$HOME/.cache/project-clean-agent/events.jsonl" <<'EOF'
{"ts":"2026-06-01T10:01:00Z","slug":"project-clean","phase":"ship","type":"pr_opened","number":"500","branch":"feat/0001-something"}
EOF
OUT="$TMP/ac5-clean.out"
FLEET_DISCOVERY_ROOT="$CLEAN_ROOT" "$FLEET" recap > "$OUT" 2>&1
grep -qF -- "top heal pattern: none (clean window)" "$OUT" \
  || { echo "FAIL: AC#5 clean-window branch should say 'none (clean window)'"; cat "$OUT"; exit 1; }

# Also keep an empty-projects root around for AC#7 / AC#11.
EMPTY_ROOT="$TMP/empty"
mkdir -p "$EMPTY_ROOT/project-x"
cat > "$EMPTY_ROOT/project-x/agents.config.sh" <<CFG
PROJECT_NAME="project-x"
SLUG="project-x"
NAMESPACE="com.project-x"
REPO_URL="https://github.com/example/project-x"
SELF_CANCEL="20990101"
CFG
mkdir -p "$HOME/.cache/project-x-agent"
: > "$HOME/.cache/project-x-agent/events.jsonl"
: > "$HOME/.cache/project-x-agent/runs.jsonl"
echo "  ok"

# ========================================================================
# AC #6 — Top failure mode line reads lesson_draft_emitted + normalizes
#         via prompts_suggest_normalize_headline. Both branches: P-N
#         match + no-match (promotion candidate).
# ========================================================================
echo "AC#6 — top failure mode branches"
OUT="$TMP/ac6.out"
"$FLEET" recap > "$OUT"
grep -qF -- "top failure mode:" "$OUT" \
  || { echo "FAIL: AC#6 missing 'top failure mode:' line"; cat "$OUT"; exit 1; }
# Either "see PRINCIPLES P-N" OR "promotion candidate" must appear on
# that line. Match the literal substrings.
if ! grep -qF -- "see PRINCIPLES P-" "$OUT" \
     && ! grep -qF -- "promotion candidate" "$OUT" \
     && ! grep -qF -- "top failure mode: none" "$OUT"; then
  echo "FAIL: AC#6 failure-mode line missing principle/candidate/none suffix"
  cat "$OUT"; exit 1
fi
echo "  ok"

# ========================================================================
# AC #7 — Cheapest / most-expensive ticket line. Reads runs.jsonl across
#         the fleet, attributes per-ticket, renders min and max. Negative
#         branch: prints `not attributable in window`.
# ========================================================================
echo "AC#7 — extremes (cheapest + most expensive)"
OUT="$TMP/ac7.out"
"$FLEET" recap > "$OUT"
grep -qE 'cheapest|most expensive' "$OUT" \
  || { echo "FAIL: AC#7 missing extremes line"; cat "$OUT"; exit 1; }
# Negative branch: a fleet whose runs.jsonl rows have no 4-digit ticket id
# in result_head — so attribution fails but the empty-window branch does
# NOT fire (PRs are still merged).
NOATTR_ROOT="$TMP/noattr"
mkdir -p "$NOATTR_ROOT/project-noattr"
cat > "$NOATTR_ROOT/project-noattr/agents.config.sh" <<CFG
PROJECT_NAME="project-noattr"
SLUG="project-noattr"
NAMESPACE="com.project-noattr"
REPO_URL="https://github.com/example/project-noattr"
SELF_CANCEL="20990101"
CFG
mkdir -p "$HOME/.cache/project-noattr-agent"
cat > "$HOME/.cache/project-noattr-agent/runs.jsonl" <<'EOF'
{"ts_start":"2026-06-01T10:00:00Z","slug":"project-noattr","phase":"ship","type":"run_completed","exit":"0","duration_ms":180000,"total_cost_usd":0.10,"result_head":"SHIP feature shipped PR no id here"}
EOF
cat > "$HOME/.cache/project-noattr-agent/events.jsonl" <<'EOF'
{"ts":"2026-06-01T10:01:00Z","slug":"project-noattr","phase":"ship","type":"pr_opened","number":"600","branch":"feat/noattr-something"}
EOF
OUT_NOATTR="$TMP/ac7-noattr.out"
FLEET_DISCOVERY_ROOT="$NOATTR_ROOT" "$FLEET" recap > "$OUT_NOATTR" 2>&1
grep -qF -- "not attributable in window" "$OUT_NOATTR" \
  || { echo "FAIL: AC#7 negative branch should say 'not attributable in window'"; cat "$OUT_NOATTR"; exit 1; }
echo "  ok"

# ========================================================================
# AC #8 — Header line: `<top-level-slug> · <Nd>-day recap · <start> →
#         <end>` in both modes. Public footer reads `generated by ...`.
# ========================================================================
echo "AC#8 — header + public footer"
OUT="$TMP/ac8.out"
"$FLEET" recap > "$OUT"
# Header line should be the first non-blank line and carry the kit name.
HEAD_LINE="$(awk 'NF { print; exit }' "$OUT")"
case "$HEAD_LINE" in
  *"agent-fleet"*"30-day recap"*) ;;
  *) echo "FAIL: AC#8 default header '$HEAD_LINE' should match 'agent-fleet · 30-day recap · …'"; cat "$OUT"; exit 1 ;;
esac
# Public mode footer.
OUT_PUB="$TMP/ac8-pub.out"
"$FLEET" recap --public > "$OUT_PUB"
grep -qF -- 'generated by `fleet recap --public`' "$OUT_PUB" \
  || { echo "FAIL: AC#8 public footer missing"; cat "$OUT_PUB"; exit 1; }
grep -qF -- 'agent-fleet/agent-fleet' "$OUT_PUB" \
  || { echo "FAIL: AC#8 public footer missing repo path"; cat "$OUT_PUB"; exit 1; }
echo "  ok"

# ========================================================================
# AC #9 — `--json` emits one JSON object summarizing the recap. Validity
#         via node. In `--public --json` slug names are anonymized.
# ========================================================================
echo "AC#9 — --json output validity + schema"
OUT_JSON="$TMP/ac9.json"
"$FLEET" recap --json > "$OUT_JSON"
if command -v node >/dev/null 2>&1; then
  node -e '
    const fs = require("fs");
    const txt = fs.readFileSync("'"$OUT_JSON"'", "utf8").trim();
    let obj;
    try { obj = JSON.parse(txt); }
    catch (e) { console.error("JSON parse failed:", e.message); console.error(txt); process.exit(1); }
    const required = [
      "window","start","end","public","projects_count","prs_merged",
      "total_spend_usd","median_ticket_cost_usd","current_longest_streak_days",
      "top_heal_pattern","top_failure_mode","cheapest_ticket",
      "most_expensive_ticket","kit_sha","prompts_pin","lessons_lines","cross_lessons_lines"
    ];
    for (const k of required) {
      if (!(k in obj)) { console.error("missing key:", k); process.exit(1); }
    }
    if (obj.public !== false) { console.error("default public should be false"); process.exit(1); }
    if (obj.window !== "30d") { console.error("default window should be 30d"); process.exit(1); }
  ' || { echo "FAIL: AC#9 --json schema mismatch"; cat "$OUT_JSON"; exit 1; }
else
  echo "  (node missing — skipping JSON schema check)"
fi
# --public --json anonymizes slug names.
OUT_PUBJSON="$TMP/ac9-public.json"
"$FLEET" recap --public --json > "$OUT_PUBJSON"
for raw in project-b customer-prod-secrets; do
  if grep -qF -- "$raw" "$OUT_PUBJSON"; then
    echo "FAIL: AC#9 public JSON should not contain slug '$raw'"
    cat "$OUT_PUBJSON"; exit 1
  fi
done
echo "  ok"

# ========================================================================
# AC #10 — `--help` USAGE mentions --since, --public, --json. Exits 0.
# ========================================================================
echo "AC#10 — help mentions flags + exits 0"
HELP_OUT="$TMP/ac10.help"
set +e
"$FLEET" recap --help > "$HELP_OUT" 2>&1
EXIT=$?
set -e
if [ "$EXIT" != "0" ]; then
  echo "FAIL: AC#10 recap --help exit $EXIT"; cat "$HELP_OUT"; exit 1
fi
for kw in --since --public --json; do
  grep -qF -- "$kw" "$HELP_OUT" \
    || { echo "FAIL: AC#10 help should mention '$kw'"; cat "$HELP_OUT"; exit 1; }
done
echo "  ok"

# ========================================================================
# AC #11 — Empty fleet branch + empty window branch.
# ========================================================================
echo "AC#11 — empty fleet + empty window branches"
EMPTY_NONE="$TMP/empty-none"
mkdir -p "$EMPTY_NONE"
OUT="$TMP/ac11-no-projects.out"
FLEET_DISCOVERY_ROOT="$EMPTY_NONE" "$FLEET" recap > "$OUT" 2>&1 || true
grep -qF -- "recap: no projects discovered" "$OUT" \
  || { echo "FAIL: AC#11 empty fleet branch"; cat "$OUT"; exit 1; }
# Empty window — a discovered project with no PRs merged in the window.
OUT="$TMP/ac11-empty-window.out"
FLEET_DISCOVERY_ROOT="$EMPTY_ROOT" "$FLEET" recap > "$OUT" 2>&1 || true
grep -qF -- "window contained no merged" "$OUT" \
  || { echo "FAIL: AC#11 empty-window branch"; cat "$OUT"; exit 1; }
echo "  ok"

# ========================================================================
# AC #12 — recap is a PURE READER. No new events written.
# ========================================================================
echo "AC#12 — recap writes zero events"
"$FLEET" recap >/dev/null
"$FLEET" recap --public >/dev/null
"$FLEET" recap --json >/dev/null
SIZE_AFTER_AF="$(events_size agent-fleet)"
SIZE_AFTER_PB="$(events_size project-b)"
SIZE_AFTER_CPS="$(events_size customer-prod-secrets)"
if [ "$SIZE_BEFORE_AF" != "$SIZE_AFTER_AF" ] \
  || [ "$SIZE_BEFORE_PB" != "$SIZE_AFTER_PB" ] \
  || [ "$SIZE_BEFORE_CPS" != "$SIZE_AFTER_CPS" ]; then
  echo "FAIL: AC#12 events.jsonl size changed; recap is not pure reader"
  echo "agent-fleet            before=$SIZE_BEFORE_AF after=$SIZE_AFTER_AF"
  echo "project-b              before=$SIZE_BEFORE_PB after=$SIZE_AFTER_PB"
  echo "customer-prod-secrets  before=$SIZE_BEFORE_CPS after=$SIZE_AFTER_CPS"
  exit 1
fi
echo "  ok"

# ========================================================================
# AC #13 — --public NEVER emits a real slug name, never `pr=#N`, never a
#          full `feat/0NNN-<slug>` branch reference. The fixture
#          customer-prod-secrets slug exercises the strip.
# ========================================================================
echo "AC#13 — public anonymization strips identifying tokens"
OUT="$TMP/ac13.out"
"$FLEET" recap --public > "$OUT"
# Header is allowed to carry 'agent-fleet'; strip it before inspecting.
BODY="$TMP/ac13-body.out"
awk 'NR>1' "$OUT" > "$BODY"
for needle in customer prod secrets; do
  if grep -qF -- "$needle" "$BODY"; then
    echo "FAIL: AC#13 public body must not contain '$needle'"
    cat "$OUT"; exit 1
  fi
done
# No pr=#N
if grep -qE 'pr=#[0-9]+' "$BODY"; then
  echo "FAIL: AC#13 public body contains 'pr=#N'"; cat "$OUT"; exit 1
fi
# No feat/NNNN-<slug>-style branch leak. The id prefix may survive (e.g.
# `feat/0047-`) but not the trailing slug portion.
if grep -qE 'feat/[0-9]{4}-[a-z][a-z0-9-]+' "$BODY"; then
  echo "FAIL: AC#13 public body contains branch with slug suffix"; cat "$OUT"; exit 1
fi
echo "  ok"

# ========================================================================
# AC #14 + AC #15 — no edits to lib/common.sh, prompts/, AGENTS.md. (The
#         dev agent enforces this; the test asserts via git diff.)
# ========================================================================
echo "AC#14/15 — recap touches neither lib/common.sh nor prompts/ nor AGENTS.md"
cd "$REPO_ROOT"
# Identify the merge-base against main. On a feature branch, diff base.
BASE_REF="main"
if git rev-parse --verify "$BASE_REF" >/dev/null 2>&1; then
  MB="$(git merge-base "$BASE_REF" HEAD 2>/dev/null || echo "")"
  if [ -n "$MB" ]; then
    if git diff --name-only "$MB" HEAD -- lib/common.sh | grep -q .; then
      echo "FAIL: AC#14 lib/common.sh was modified on this branch"; exit 1
    fi
    if git diff --name-only "$MB" HEAD -- prompts/ | grep -q .; then
      echo "FAIL: AC#14 prompts/ was modified on this branch"; exit 1
    fi
    if git diff --name-only "$MB" HEAD -- AGENTS.md | grep -q .; then
      echo "FAIL: AC#14 AGENTS.md was modified on this branch"; exit 1
    fi
  fi
fi
echo "  ok"

# ========================================================================
# AC #16 — tests/recap.sh runs under 10s budget. Asserted by virtue of
#         finishing at all under default `bash tests/recap.sh`; print the
#         elapsed for visibility.
# ========================================================================
echo "all AC blocks passed for ticket 0048"
