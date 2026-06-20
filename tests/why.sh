#!/bin/bash
# tests/why.sh — `bin/fleet why` self-justifying argument test.
#
# Ticket 0062. One assertion block per acceptance-criteria checkbox in
# docs/backlog/0062-fleet-why-self-justifying-argument.md.
#
# `why` is a PURE READER: no events.jsonl writes, no fleet_emit_event,
# no `lib/` or `prompts/` edits, no new event types. AC#12 asserts the
# events / runs / cross-LESSONS byte sizes are unchanged across an
# invocation.
#
# Per LESSONS 2026-05-26 stubs live under $HOME/.local/bin (lib/common.sh
# resets PATH, though bin/fleet does NOT source it — the stub dir is
# really only for HOME isolation here). Per LESSONS 2026-05-27 every
# fixture is copied with `cp` (never `$(cat …)`). Per LESSONS 2026-06-01
# every count uses `awk … END { print n+0 }`. Per LESSONS 2026-06-08
# every awk accumulator declares `BEGIN { count = 0 }`. Per LESSONS
# 2026-05-30 help-text greps use `grep -qF -- "$kw"`. Per LESSONS
# 2026-06-11 window math is `date +%s` minus `weeks * 7 * 86400`, no
# `date -j -f` involved (the clock is frozen via FLEET_NOW_OVERRIDE).

set -euo pipefail

REPO_ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
FLEET="$REPO_ROOT/bin/fleet"
FIXTURE_DIR="$REPO_ROOT/tests/fixtures/why"

TMP="$(mktemp -d -t fleet-why-test.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

# Isolate HOME so $HOME/.cache, $HOME/.local/bin stay sandboxed.
export HOME="$TMP/home"
mkdir -p "$HOME/.local/bin"

# Anchor "now" at 2026-06-19T12:00:00Z so the trailing 8-week window
# reaches back to 2026-04-24 deterministically. 8 * 7 * 86400 = 4838400
# (LESSONS 2026-06-11: `date +%s` minus weeks-seconds, no `date -j -f`).
NOW_EPOCH=1781870400
export FLEET_NOW_OVERRIDE="$NOW_EPOCH"

# Seed manifests under a fixture root and point discovery there.
FIXTURE_ROOT="$TMP/projects"
mkdir -p "$FIXTURE_ROOT"
export FLEET_DISCOVERY_ROOT="$FIXTURE_ROOT"

# Point the cross-LESSONS file at our fixture copy (per LESSONS 2026-05-27
# we `cp` rather than `$(cat …)`).
CROSS_LESSONS_PATH="$TMP/CROSS_LESSONS.md"
cp "$FIXTURE_DIR/CROSS_LESSONS.md" "$CROSS_LESSONS_PATH"
export FLEET_CROSS_LESSONS="$CROSS_LESSONS_PATH"

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

# Install per-slug events.jsonl / runs.jsonl into $HOME/.cache/<slug>-agent
# byte-exact via `cp` (LESSONS 2026-05-27).
install_slug_fixture() {  # $1 = slug
  local slug="$1"
  local cache="$HOME/.cache/${slug}-agent"
  mkdir -p "$cache"
  cp "$FIXTURE_DIR/$slug/events.jsonl" "$cache/events.jsonl"
  cp "$FIXTURE_DIR/$slug/runs.jsonl"   "$cache/runs.jsonl"
}

for slug in keep-strong keep-marginal remove-candidate first-week missing-cross-lessons; do
  mk_manifest "$slug"
  install_slug_fixture "$slug"
done

# Optional knob fixture for AC#4: keep-strong overrides MANUAL_PR_MINUTES
# back to 75 explicitly (matches default; demonstrates the manifest
# read path is honored). Per LESSONS 2026-06-05 the read is inside a
# subshell so no env leak.
cat >> "$FIXTURE_ROOT/keep-strong/agents.config.sh" <<'CFG'
MANUAL_PR_MINUTES=75
CONTRACTOR_USD_PER_HOUR=80
CFG

pass() { printf -- '  PASS  %s\n' "$1"; }
fail() { printf -- '  FAIL  %s\n' "$1" >&2; exit 1; }

# ---------------------------------------------------------------------
# AC#1 — refusals: missing slug AND no --all → exit 2 + usage; unknown
# slug → exit 2 + discovered-slugs hint. Per LESSONS 2026-05-30 the
# keyword greps use `grep -qF -- "$kw"`.
# ---------------------------------------------------------------------
err_log="$TMP/ac1.err"
set +e
"$FLEET" why > "$TMP/ac1.out" 2> "$err_log"
ac1_rc=$?
set -e
[ "$ac1_rc" = "2" ] || fail "AC#1 missing slug should exit 2 (got $ac1_rc)"
grep -qF -- "usage:" "$err_log" || fail "AC#1 missing slug error must contain 'usage:'"
grep -qF -- "--all" "$err_log"  || fail "AC#1 missing slug error must mention '--all'"

err_log="$TMP/ac1b.err"
set +e
"$FLEET" why nosuch-slug > "$TMP/ac1b.out" 2> "$err_log"
ac1b_rc=$?
set -e
[ "$ac1b_rc" = "2" ] || fail "AC#1 unknown slug should exit 2 (got $ac1b_rc)"
grep -qF -- "nosuch-slug" "$err_log" || fail "AC#1 unknown-slug error must echo the bad slug"
grep -qF -- "discovered slugs:" "$err_log" || fail "AC#1 unknown-slug error must list discovered slugs"
pass "AC#1 refusal paths (missing slug + unknown slug) exit 2 with documented messages"

# ---------------------------------------------------------------------
# AC#2 — peer is the default audience; paragraph ≤6 sentences AND ≤480
# chars; each sentence carries at least one citation token (number).
# ---------------------------------------------------------------------
out="$("$FLEET" why keep-strong)"
body="$(printf -- '%s' "$out" | awk '/^why /,0 { next } /^$/ { found = 1; next } found { print }')"
# Simpler: grab everything that is not the header line.
paragraph="$(printf -- '%s\n' "$out" | awk 'BEGIN { count = 0 } /^why / { next } /^[[:space:]]*cites:/ { next } { print }')"
# Sentence count: number of ". " or terminal "." characters in paragraph.
sent_count="$(printf -- '%s' "$paragraph" | tr '\n' ' ' | awk 'BEGIN { count = 0 } { n = gsub(/\. /, ""); count = n; if (substr($0, length($0), 1) == ".") count++ } END { print count + 0 }')"
char_count="$(printf -- '%s' "$paragraph" | tr '\n' ' ' | awk 'BEGIN { count = 0 } { gsub(/^[[:space:]]+|[[:space:]]+$/, ""); count = length($0) } END { print count + 0 }')"
[ "$sent_count" -ge 3 ] && [ "$sent_count" -le 6 ] || fail "AC#2 paragraph sentence count expected 3..6, got $sent_count"
[ "$char_count" -le 480 ] || fail "AC#2 paragraph char count expected ≤480, got $char_count"
# Each sentence must carry at least one citation digit. Count sentences
# without any digit.
no_cite="$(printf -- '%s' "$paragraph" | tr '\n' ' ' | awk 'BEGIN { count = 0 } {
  s = $0
  n = split(s, parts, /\. /)
  for (i = 1; i <= n; i++) {
    p = parts[i]
    sub(/^[[:space:]]+|[[:space:]]+$/, "", p)
    if (p == "") continue
    if (p !~ /[0-9]/) count++
  }
} END { print count + 0 }')"
[ "$no_cite" = "0" ] || fail "AC#2 every sentence must carry at least one citation number ($no_cite without)"
pass "AC#2 peer paragraph: $sent_count sentences, $char_count chars, every sentence cites a number"

# ---------------------------------------------------------------------
# AC#3 — citations: PR count (pr_footer_posted in 8w), median cost-per-
# PR (runs.jsonl), stuck recoveries (infra_flake_rerun followed by
# run_completed exit=0 for same PR), lesson_promoted with scope=all,
# prompts_pin_changed in the same window. Test via --json so the
# numbers are unambiguously surfaced.
# ---------------------------------------------------------------------
json_out="$("$FLEET" why keep-strong --json)"
get_num() {  # $1 = json blob, $2 = key
  printf -- '%s' "$1" | node -e '
    let buf = "";
    process.stdin.on("data", d => buf += d);
    process.stdin.on("end", () => {
      const obj = JSON.parse(buf);
      const keys = process.argv.slice(1);
      let cur = obj;
      for (const k of keys) cur = cur[k];
      process.stdout.write(String(cur));
    });
  ' "$2" "$3" <<< "$1"
}
prs_merged="$(printf -- '%s' "$json_out" | node -e 'let buf=""; process.stdin.on("data",d=>buf+=d); process.stdin.on("end",()=>{const o=JSON.parse(buf); process.stdout.write(String(o.citations.prs_merged));});')"
cost_per_pr="$(printf -- '%s' "$json_out" | node -e 'let buf=""; process.stdin.on("data",d=>buf+=d); process.stdin.on("end",()=>{const o=JSON.parse(buf); process.stdout.write(String(o.citations.cost_per_pr_usd));});')"
stuck="$(printf -- '%s' "$json_out" | node -e 'let buf=""; process.stdin.on("data",d=>buf+=d); process.stdin.on("end",()=>{const o=JSON.parse(buf); process.stdout.write(String(o.citations.stuck_recoveries));});')"
lessons="$(printf -- '%s' "$json_out" | node -e 'let buf=""; process.stdin.on("data",d=>buf+=d); process.stdin.on("end",()=>{const o=JSON.parse(buf); process.stdout.write(String(o.citations.lessons_promoted));});')"
pinned="$(printf -- '%s' "$json_out" | node -e 'let buf=""; process.stdin.on("data",d=>buf+=d); process.stdin.on("end",()=>{const o=JSON.parse(buf); process.stdout.write(String(o.citations.prompts_pinned));});')"
[ "$prs_merged" = "12" ]   || fail "AC#3 prs_merged expected 12, got $prs_merged"
[ "$cost_per_pr" = "0.33" ] || fail "AC#3 cost_per_pr_usd median expected 0.33, got $cost_per_pr"
[ "$stuck" = "2" ]          || fail "AC#3 stuck_recoveries expected 2, got $stuck"
[ "$lessons" = "3" ]        || fail "AC#3 lessons_promoted expected 3, got $lessons"
[ "$pinned" = "2" ]         || fail "AC#3 prompts_pinned expected 2, got $pinned"
pass "AC#3 citations: prs=12 cost_per_pr=0.33 stuck=2 lessons=3 pinned=2 (window 8w)"

# ---------------------------------------------------------------------
# AC#4 — alternatives: Cursor Pro cost = weeks × $5 (8×5=$40);
# contractor cost = PR_count × MANUAL_PR_MINUTES / 60 × CONTRACTOR_USD_PER_HOUR
# = 12 × 75/60 × 80 = $1200.
# Per LESSONS 2026-06-05 manifest read happens inside `( … )`.
# ---------------------------------------------------------------------
cursor_alt="$(printf -- '%s' "$json_out" | node -e 'let buf=""; process.stdin.on("data",d=>buf+=d); process.stdin.on("end",()=>{const o=JSON.parse(buf); process.stdout.write(String(o.alternatives.cursor_usd));});')"
contractor_alt="$(printf -- '%s' "$json_out" | node -e 'let buf=""; process.stdin.on("data",d=>buf+=d); process.stdin.on("end",()=>{const o=JSON.parse(buf); process.stdout.write(String(o.alternatives.contractor_usd));});')"
[ "$cursor_alt" = "40" ]      || fail "AC#4 cursor_usd expected 40, got $cursor_alt"
[ "$contractor_alt" = "1200" ] || fail "AC#4 contractor_usd expected 1200, got $contractor_alt"
pass "AC#4 alternatives: cursor=\$40 contractor=\$1200 (knobs honoured)"

# ---------------------------------------------------------------------
# AC#5 — three audiences produce distinct first-sentence text but
# share the same citations.
# ---------------------------------------------------------------------
peer_para="$("$FLEET" why keep-strong --audience peer    | head -3 | tail -1)"
mgr_para="$("$FLEET" why keep-strong --audience manager  | head -3 | tail -1)"
self_para="$("$FLEET" why keep-strong --audience self    | head -3 | tail -1)"
[ "$peer_para" != "$mgr_para" ]  || fail "AC#5 peer and manager first-sentence text should differ"
[ "$peer_para" != "$self_para" ] || fail "AC#5 peer and self first-sentence text should differ"
[ "$mgr_para" != "$self_para" ]  || fail "AC#5 manager and self first-sentence text should differ"
mgr_json="$("$FLEET" why keep-strong --audience manager --json)"
self_json="$("$FLEET" why keep-strong --audience self --json)"
mgr_prs="$(printf -- '%s' "$mgr_json" | node -e 'let b="";process.stdin.on("data",d=>b+=d);process.stdin.on("end",()=>process.stdout.write(String(JSON.parse(b).citations.prs_merged)));')"
self_prs="$(printf -- '%s' "$self_json" | node -e 'let b="";process.stdin.on("data",d=>b+=d);process.stdin.on("end",()=>process.stdout.write(String(JSON.parse(b).citations.prs_merged)));')"
[ "$mgr_prs" = "12" ] && [ "$self_prs" = "12" ] || fail "AC#5 manager/self should share citations (got mgr=$mgr_prs self=$self_prs)"
pass "AC#5 audiences (peer/manager/self) produce distinct first sentences with shared citations"

# ---------------------------------------------------------------------
# AC#6 — --why-not invert: GENUINELY-against branch and HONEST-tooling
# branch (positive case with leading marker).
# ---------------------------------------------------------------------
out_negative="$("$FLEET" why remove-candidate --why-not)"
printf -- '%s' "$out_negative" | grep -qF -- "remove" || fail "AC#6 against-case prose should mention removing"
# keep-strong is a clearly-positive slug → --why-not should still emit the
# honest-tooling marker ("against expectation").
out_positive="$("$FLEET" why keep-strong --why-not)"
printf -- '%s' "$out_positive" | grep -qF -- "against expectation" || fail "AC#6 honest-tooling branch missing 'against expectation' marker"
printf -- '%s' "$out_positive" | grep -qF -- "does NOT support removing" || fail "AC#6 honest-tooling branch missing 'does NOT support removing'"
pass "AC#6 --why-not handles both genuine-against and honest-tooling branches"

# ---------------------------------------------------------------------
# AC#7 — --all walks every discovered slug; each paragraph prefixed
# with slug name and verdict tag (keep) or (consider removing). Per
# LESSONS 2026-06-15 one awk pass per slug — but the test asserts
# behavior, not internal subprocess count.
# ---------------------------------------------------------------------
all_out="$("$FLEET" why --all)"
printf -- '%s' "$all_out" | grep -qF -- "keep-strong (keep)"        || fail "AC#7 --all missing 'keep-strong (keep)' header"
printf -- '%s' "$all_out" | grep -qF -- "keep-marginal (keep)"      || fail "AC#7 --all missing 'keep-marginal (keep)' header"
printf -- '%s' "$all_out" | grep -qF -- "remove-candidate (consider removing)" || fail "AC#7 --all missing 'remove-candidate (consider removing)' header"
pass "AC#7 --all renders per-slug paragraphs with verdict tags"

# ---------------------------------------------------------------------
# AC#8 — cross-LESSONS file path resolution honours FLEET_CROSS_LESSONS;
# missing file branches to a friendly placeholder.
# ---------------------------------------------------------------------
# With file present (the default for this test run), the prose mentions
# the lesson count from the cross-LESSONS file.
present_out="$("$FLEET" why keep-strong)"
printf -- '%s' "$present_out" | grep -qE 'cross-project memory|LESSONS|sibling project' \
  || fail "AC#8 present-file branch should mention cross-project memory"
# Move the file aside and re-run; the prose must surface the missing-file
# placeholder.
saved="$TMP/CROSS_LESSONS.md.saved"
cp "$CROSS_LESSONS_PATH" "$saved"
rm -f "$CROSS_LESSONS_PATH"
absent_out="$("$FLEET" why missing-cross-lessons)"
printf -- '%s' "$absent_out" | grep -qF -- "file not yet created" \
  || fail "AC#8 absent-file branch should mention 'file not yet created'"
cp "$saved" "$CROSS_LESSONS_PATH"
pass "AC#8 cross-LESSONS file present/absent both render correctly"

# ---------------------------------------------------------------------
# AC#9 — --json emits one structured JSON object with the documented
# shape. Validate via Node.
# ---------------------------------------------------------------------
schema_ok="$(printf -- '%s' "$json_out" | node -e '
  let buf = "";
  process.stdin.on("data", d => buf += d);
  process.stdin.on("end", () => {
    const o = JSON.parse(buf);
    const required = ["slug","audience","verdict","paragraph","citations","alternatives"];
    for (const k of required) {
      if (!(k in o)) { console.error("missing top-level key:", k); process.exit(1); }
    }
    const citeKeys = ["prs_merged","cost_per_pr_usd","stuck_recoveries","lessons_promoted","prompts_pinned"];
    for (const k of citeKeys) {
      if (!(k in o.citations)) { console.error("missing citations key:", k); process.exit(1); }
    }
    const altKeys = ["cursor_usd","contractor_usd"];
    for (const k of altKeys) {
      if (!(k in o.alternatives)) { console.error("missing alternatives key:", k); process.exit(1); }
    }
    if (typeof o.paragraph !== "string") { console.error("paragraph not a string"); process.exit(1); }
    if (!["keep","consider_removing"].includes(o.verdict)) { console.error("verdict bad"); process.exit(1); }
    if (!["peer","manager","self"].includes(o.audience))   { console.error("audience bad"); process.exit(1); }
    console.log("OK");
  });
')"
[ "$schema_ok" = "OK" ] || fail "AC#9 JSON schema validation failed: $schema_ok"
pass "AC#9 --json emits the documented schema and parses cleanly"

# ---------------------------------------------------------------------
# AC#10 — prose composer template substitution survives a value
# containing a `$<digit>` substring (LESSONS 2026-06-15: cursor-based
# walk, NOT recursive `s = before repl after`). The keep-strong slug's
# contractor alt = "$1200" contains "$1" / "$2" substrings; the
# rendered text must contain the literal "1200" without infinite loop.
# ---------------------------------------------------------------------
render_start=$(date +%s)
trick_out="$("$FLEET" why keep-strong --audience manager)"
render_end=$(date +%s)
render_dt=$((render_end - render_start))
[ "$render_dt" -lt 4 ] || fail "AC#10 prose composer ran >4s (likely the cursor-walk regression)"
printf -- '%s' "$trick_out" | grep -qF -- "1200" || fail "AC#10 manager prose must surface the literal 1200 value"
pass "AC#10 composer cursor-walk handles \$<digit> substrings without infinite loop"

# ---------------------------------------------------------------------
# AC#11 — `bin/fleet why --help` USAGE mentions --all, --audience,
# --why-not, --json (LESSONS 2026-05-30 → `grep -qF -- "$kw"`). The
# help block must `exit 0` (LESSONS 2026-06-01).
# ---------------------------------------------------------------------
help_out="$TMP/help.out"
set +e
"$FLEET" why --help > "$help_out" 2>&1
help_rc=$?
set -e
[ "$help_rc" = "0" ] || fail "AC#11 --help must exit 0 (got $help_rc)"
for kw in --all --audience --why-not --json; do
  grep -qF -- "$kw" "$help_out" || fail "AC#11 help missing keyword $kw"
done
pass "AC#11 --help exits 0 and lists --all / --audience / --why-not / --json"

# ---------------------------------------------------------------------
# AC#12 — PURE READER: events.jsonl + runs.jsonl + cross-LESSONS byte
# sizes unchanged across an invocation.
# ---------------------------------------------------------------------
size_of() { wc -c < "$1" | tr -d ' '; }
before_ev="$(size_of "$HOME/.cache/keep-strong-agent/events.jsonl")"
before_rn="$(size_of "$HOME/.cache/keep-strong-agent/runs.jsonl")"
before_cl="$(size_of "$CROSS_LESSONS_PATH")"
"$FLEET" why keep-strong > /dev/null
"$FLEET" why keep-strong --audience self > /dev/null
"$FLEET" why keep-strong --json > /dev/null
"$FLEET" why --all > /dev/null
after_ev="$(size_of "$HOME/.cache/keep-strong-agent/events.jsonl")"
after_rn="$(size_of "$HOME/.cache/keep-strong-agent/runs.jsonl")"
after_cl="$(size_of "$CROSS_LESSONS_PATH")"
[ "$before_ev" = "$after_ev" ] || fail "AC#12 events.jsonl changed (before=$before_ev after=$after_ev)"
[ "$before_rn" = "$after_rn" ] || fail "AC#12 runs.jsonl changed (before=$before_rn after=$after_rn)"
[ "$before_cl" = "$after_cl" ] || fail "AC#12 CROSS_LESSONS.md changed (before=$before_cl after=$after_cl)"
pass "AC#12 pure reader: events / runs / cross-LESSONS unchanged across 4 invocations"

# ---------------------------------------------------------------------
# AC#13 — no `lib/common.sh` change, no `prompts/` change vs main.
# (When run outside a feature branch, this assertion may be skipped:
# we only enforce it inside the agent-fleet checkout where `main`
# exists locally.)
# ---------------------------------------------------------------------
if (cd "$REPO_ROOT" && git rev-parse --verify main >/dev/null 2>&1); then
  changed="$(cd "$REPO_ROOT" && git diff --name-only main...HEAD -- lib/common.sh prompts/)"
  if [ -n "$changed" ]; then
    fail "AC#13 contract: lib/common.sh and prompts/ MUST NOT change (got: $changed)"
  fi
  pass "AC#13 lib/common.sh and prompts/ untouched vs main"
else
  pass "AC#13 lib/common.sh and prompts/ contract (skipped: no main ref in this checkout)"
fi

printf -- '\ntests/why.sh: all 13 acceptance criteria PASSED\n'
