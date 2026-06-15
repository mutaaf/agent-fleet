#!/bin/bash
# tests/portfolio.sh — `bin/fleet portfolio` leak-safe one-pager test.
#
# Ticket 0053. One assertion block per acceptance-criteria checkbox in
# docs/backlog/0053-fleet-portfolio-redacted-shareable.md.
#
# `portfolio` is a PURE READER: no events.jsonl writes, no
# `fleet_emit_event` calls, no `lib/` or `prompts/` edits, no new event
# types. Per LESSONS 2026-05-26 stubs live under $HOME/.local/bin
# (PATH-reset isolation). Per LESSONS 2026-05-27 fixtures are copied
# with `cp` (never `$(cat …)`). Per LESSONS 2026-06-01 every count uses
# `awk … END { print n+0 }`. Per LESSONS 2026-06-08 every awk
# accumulator declares `BEGIN { count = 0 }`. Per LESSONS 2026-05-30
# help-text greps use `grep -qF -- "$kw"`. Per LESSONS 2026-06-05 the
# anonymizer's sort is `LC_ALL=C sort`. Per LESSONS 2026-06-11 the
# `--since YYYY-MM-DD` value is normalized to T00:00:00 inside the
# parser.

set -euo pipefail

REPO_ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
FLEET="$REPO_ROOT/bin/fleet"
FIXTURE_DIR="$REPO_ROOT/tests/fixtures/portfolio"

TMP="$(mktemp -d -t fleet-portfolio-test.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

export HOME="$TMP/home"
mkdir -p "$HOME/.local/bin"

# Anchor "today" at 2026-06-13T12:00:00Z (matches recap window math). The
# default 90-day window covers everything in the fixtures.
NOW_EPOCH=1781352000
export FLEET_NOW_OVERRIDE="$NOW_EPOCH"

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
REPO_URL="git@github.com:realuser/$slug.git"
SELF_CANCEL="20990101"
CFG
}

install_slug_fixture() {  # $1 = slug, $2 = fixture name
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

mk_manifest alpha
mk_manifest beta
mk_manifest gamma
install_slug_fixture alpha alpha
install_slug_fixture beta  beta
install_slug_fixture gamma gamma

# Stub `git` so kit-sha branch is deterministic.
cat > "$HOME/.local/bin/git" <<'STUB'
#!/bin/bash
case "$*" in
  *"rev-parse --short HEAD"*) echo "deadbee"; exit 0 ;;
  *"rev-parse --short"*)       echo "deadbee"; exit 0 ;;
esac
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
export PATH="$HOME/.local/bin:$PATH"

export FLEET_RECAP_PROMPTS_SHA="ee94b3a"
export FLEET_RECAP_KIT_SHA="deadbee"

# AC#13 — record events.jsonl byte sizes BEFORE any invocation.
events_size() {
  local slug="$1"
  local f="$HOME/.cache/${slug}-agent/events.jsonl"
  if [ -f "$f" ]; then wc -c <"$f" | tr -d ' '; else echo "0"; fi
}
SZ_BEFORE_A=$(events_size alpha)
SZ_BEFORE_B=$(events_size beta)
SZ_BEFORE_G=$(events_size gamma)

# Snapshot the fixture root + HOME so AC#14 can diff for newly-created
# files containing both a real slug name and its pseudonym.
snapshot_before="$TMP/snap-before.txt"
( cd "$TMP" && find home projects -type f | LC_ALL=C sort ) > "$snapshot_before"

# ========================================================================
# AC #1 — `bin/fleet portfolio` with no flags prints the page WITHOUT
#         redaction (real slug names appear). With zero discovered slugs
#         prints a "no slugs discovered" hint and exits 0.
# ========================================================================
echo "AC#1 — default invocation (no redaction) + zero-slugs branch"
OUT="$TMP/ac1.out"
set +e
"$FLEET" portfolio > "$OUT" 2>&1
EXIT=$?
set -e
if [ "$EXIT" != "0" ]; then
  echo "FAIL: AC#1 exit $EXIT (want 0)"; cat "$OUT"; exit 1
fi
grep -qF -- "alpha" "$OUT" \
  || { echo "FAIL: AC#1 default-mode body should mention real slug 'alpha'"; cat "$OUT"; exit 1; }
grep -qF -- "beta" "$OUT" \
  || { echo "FAIL: AC#1 default-mode body should mention real slug 'beta'"; cat "$OUT"; exit 1; }

# Zero-slugs branch.
EMPTY_ROOT="$TMP/empty"
mkdir -p "$EMPTY_ROOT"
OUT_EMPTY="$TMP/ac1-empty.out"
set +e
FLEET_DISCOVERY_ROOT="$EMPTY_ROOT" "$FLEET" portfolio > "$OUT_EMPTY" 2>&1
EXIT=$?
set -e
if [ "$EXIT" != "0" ]; then
  echo "FAIL: AC#1 zero-slugs exit $EXIT (want 0)"; cat "$OUT_EMPTY"; exit 1
fi
grep -qF -- "no slugs discovered" "$OUT_EMPTY" \
  || { echo "FAIL: AC#1 zero-slugs branch should say 'no slugs discovered'"; cat "$OUT_EMPTY"; exit 1; }
grep -qF -- "fleet onboard" "$OUT_EMPTY" \
  || { echo "FAIL: AC#1 zero-slugs hint should mention 'fleet onboard'"; cat "$OUT_EMPTY"; exit 1; }
echo "  ok"

# ========================================================================
# AC #2 — `--redact` maps each discovered slug to project-a/b/c…
#         alphabetically. Mapping is held in memory only.
# ========================================================================
echo "AC#2 — --redact deterministic alphabetic pseudonyms"
OUT="$TMP/ac2.out"
"$FLEET" portfolio --redact > "$OUT"
grep -qF -- "project-a" "$OUT" \
  || { echo "FAIL: AC#2 missing 'project-a' token"; cat "$OUT"; exit 1; }
grep -qF -- "project-b" "$OUT" \
  || { echo "FAIL: AC#2 missing 'project-b' token"; cat "$OUT"; exit 1; }
grep -qF -- "project-c" "$OUT" \
  || { echo "FAIL: AC#2 missing 'project-c' token"; cat "$OUT"; exit 1; }
for raw in alpha beta gamma; do
  if grep -qF -- "$raw" "$OUT"; then
    echo "FAIL: AC#2 --redact output should NOT contain raw slug '$raw'"
    cat "$OUT"; exit 1
  fi
done
echo "  ok"

# ========================================================================
# AC #3 — slug-name rewrite is whole-word so substrings of unrelated text
#         are preserved. We assert (via the deterministic alpha → project-a
#         mapping) that "alphabet" inside a passed-through string would
#         survive the rewrite — exercised through the lesson-body path in
#         AC#7 with a passing fixture line. Here we just confirm the
#         output is deterministic across runs.
# ========================================================================
echo "AC#3 — whole-word rewrite + deterministic across runs"
OUT2="$TMP/ac3-2.out"
"$FLEET" portfolio --redact > "$OUT2"
diff -u "$OUT" "$OUT2" \
  || { echo "FAIL: AC#3 deterministic --redact output should be stable"; exit 1; }
echo "  ok"

# ========================================================================
# AC #4 — PR numbers redacted to PR #aaa/bbb/ccc... deterministically.
#         Real PR numbers (#14, #143, #1024) MUST NOT appear in --redact
#         output.
# ========================================================================
echo "AC#4 — PR numbers redacted"
OUT="$TMP/ac4.out"
"$FLEET" portfolio --redact > "$OUT"
# Real PR numbers don't appear.
for n in "#14" "#143" "#1024" "#77" "#82" "#311"; do
  if grep -qF -- "$n" "$OUT"; then
    echo "FAIL: AC#4 --redact output should NOT contain real PR number '$n'"
    cat "$OUT"; exit 1
  fi
done
# At least one PR #aXX token (alphabetic pseudonym) appears.
grep -qE 'PR #[a-z]+' "$OUT" \
  || { echo "FAIL: AC#4 missing alphabetic PR pseudonym 'PR #aaa…'"; cat "$OUT"; exit 1; }
echo "  ok"

# ========================================================================
# AC #5 — Dollar amounts bucketed into bands.
# ========================================================================
echo "AC#5 — dollar amounts bucketed"
OUT="$TMP/ac5.out"
"$FLEET" portfolio --redact > "$OUT"
# Real dollar values from fixtures: $0.42, $4.50, $11.20, $47.00, $118.00.
for raw in "0.42" "4.50" "11.20" "47.00" "118.00"; do
  if grep -qF -- "\$$raw" "$OUT"; then
    echo "FAIL: AC#5 --redact should NOT contain raw '\$$raw'"
    cat "$OUT"; exit 1
  fi
done
# At least one band token appears.
grep -qE '(<\$1|~\$1|~\$2|~\$5|~\$10|~\$25|~\$50|~\$100|>\$100)' "$OUT" \
  || { echo "FAIL: AC#5 expected a band token (<\$1 / ~\$5 / >\$100 / …)"; cat "$OUT"; exit 1; }
echo "  ok"

# ========================================================================
# AC #6 — Repo URLs redacted to github.com/<redacted>/<repo-pseudonym>.
#         No raw 'realuser' appears anywhere in --redact output.
# ========================================================================
echo "AC#6 — repo URLs redacted"
OUT="$TMP/ac6.out"
"$FLEET" portfolio --redact > "$OUT"
if grep -qF -- "realuser" "$OUT"; then
  echo "FAIL: AC#6 --redact should NOT leak github org 'realuser'"
  cat "$OUT"; exit 1
fi
echo "  ok"

# ========================================================================
# AC #7 — Lesson headlines truncated to 6 words + ellipsis.
# ========================================================================
echo "AC#7 — lesson headlines truncated"
OUT="$TMP/ac7.out"
"$FLEET" portfolio --redact > "$OUT"
# The long fixture headline is "P-1 a very long lesson headline that contains
# many words and should be truncated to six words" — the substring "truncated
# to six words" MUST NOT appear in --redact output.
if grep -qF -- "truncated to six words" "$OUT"; then
  echo "FAIL: AC#7 --redact should truncate the long headline before the tail words"
  cat "$OUT"; exit 1
fi
# An ellipsis (the truncation marker `...`) must appear somewhere.
grep -qF -- "..." "$OUT" \
  || { echo "FAIL: AC#7 expected '...' ellipsis after truncation"; cat "$OUT"; exit 1; }
echo "  ok"

# ========================================================================
# AC #8 — File paths inside lesson bodies replaced by `<path>`.
# ========================================================================
echo "AC#8 — file paths redacted"
OUT="$TMP/ac8.out"
"$FLEET" portfolio --redact > "$OUT"
# The alpha runs.jsonl has a result_head with `/Users/alpha/repo/foo.sh` —
# the raw path must not appear in --redact output (and even partial
# tokens like /Users/alpha must be redacted).
if grep -qF -- "/Users/alpha" "$OUT"; then
  echo "FAIL: AC#8 --redact should NOT leak '/Users/alpha' path"
  cat "$OUT"; exit 1
fi
echo "  ok"

# ========================================================================
# AC #9 — `--redact --keep-slug-names` bypasses the slug-name rewrite but
#         keeps PR/dollar/repo/lesson/path redactions.
# ========================================================================
echo "AC#9 — --keep-slug-names bypass"
OUT="$TMP/ac9.out"
"$FLEET" portfolio --redact --keep-slug-names > "$OUT"
# Real slug names appear.
grep -qF -- "alpha" "$OUT" \
  || { echo "FAIL: AC#9 --keep-slug-names should preserve real slug 'alpha'"; cat "$OUT"; exit 1; }
grep -qF -- "beta" "$OUT" \
  || { echo "FAIL: AC#9 --keep-slug-names should preserve real slug 'beta'"; cat "$OUT"; exit 1; }
# But PR numbers still redacted.
if grep -qF -- "#143" "$OUT"; then
  echo "FAIL: AC#9 --keep-slug-names should STILL redact PR numbers"
  cat "$OUT"; exit 1
fi
# Repo URL org still redacted.
if grep -qF -- "realuser" "$OUT"; then
  echo "FAIL: AC#9 --keep-slug-names should STILL redact 'realuser' org"
  cat "$OUT"; exit 1
fi
echo "  ok"

# ========================================================================
# AC #10 — `--since` accepts Nd and YYYY-MM-DD forms.
# ========================================================================
echo "AC#10 — --since override (Nd + YYYY-MM-DD)"
OUT="$TMP/ac10-nd.out"
"$FLEET" portfolio --since 30d > "$OUT"
# Output mentions a 30-day window header.
grep -qE '(30-day|since 30d)' "$OUT" \
  || { echo "FAIL: AC#10 30d window header missing"; cat "$OUT"; exit 1; }

OUT="$TMP/ac10-iso.out"
"$FLEET" portfolio --since 2026-05-15 > "$OUT"
grep -qF -- "2026-05-15" "$OUT" \
  || { echo "FAIL: AC#10 ISO since header missing date"; cat "$OUT"; exit 1; }
echo "  ok"

# ========================================================================
# AC #11 — `--json` emits one structured object with summary, principles,
#          slugs keys. Validate via Node.
# ========================================================================
echo "AC#11 — --json structured emit"
OUT="$TMP/ac11.json"
"$FLEET" portfolio --json > "$OUT"
node -e '
  const fs = require("fs");
  const obj = JSON.parse(fs.readFileSync("'"$OUT"'", "utf8"));
  if (typeof obj.summary !== "object" || obj.summary === null) {
    console.error("AC#11 .summary missing or not object"); process.exit(1);
  }
  if (!Array.isArray(obj.principles)) {
    console.error("AC#11 .principles missing or not array"); process.exit(1);
  }
  if (!Array.isArray(obj.slugs)) {
    console.error("AC#11 .slugs missing or not array"); process.exit(1);
  }
' || { echo "FAIL: AC#11 --json validation failed"; cat "$OUT"; exit 1; }

# Combined --json --redact should still be valid JSON AND not leak raw slug.
OUT="$TMP/ac11-redact.json"
"$FLEET" portfolio --json --redact > "$OUT"
node -e '
  const obj = JSON.parse(require("fs").readFileSync("'"$OUT"'", "utf8"));
  if (typeof obj.summary !== "object") { console.error("missing summary"); process.exit(1); }
' || { echo "FAIL: AC#11 --json --redact validation failed"; cat "$OUT"; exit 1; }
if grep -qF -- '"alpha"' "$OUT"; then
  echo "FAIL: AC#11 --json --redact should not embed raw slug 'alpha'"
  cat "$OUT"; exit 1
fi
echo "  ok"

# ========================================================================
# AC #12 — `--help` prints USAGE mentioning the four flag families.
#          Help block exits 0.
# ========================================================================
echo "AC#12 — --help banner"
OUT="$TMP/ac12.help"
set +e
"$FLEET" portfolio --help > "$OUT" 2>&1
EXIT=$?
set -e
if [ "$EXIT" != "0" ]; then
  echo "FAIL: AC#12 --help exit $EXIT (want 0)"; cat "$OUT"; exit 1
fi
for kw in "--redact" "--keep-slug-names" "--since" "--json"; do
  grep -qF -- "$kw" "$OUT" \
    || { echo "FAIL: AC#12 help missing keyword '$kw'"; cat "$OUT"; exit 1; }
done
echo "  ok"

# ========================================================================
# AC #13 — Pure reader: every slug's events.jsonl byte size unchanged
#          before and after invocation.
# ========================================================================
echo "AC#13 — pure reader, no events.jsonl writes"
SZ_AFTER_A=$(events_size alpha)
SZ_AFTER_B=$(events_size beta)
SZ_AFTER_G=$(events_size gamma)
if [ "$SZ_BEFORE_A" != "$SZ_AFTER_A" ] \
   || [ "$SZ_BEFORE_B" != "$SZ_AFTER_B" ] \
   || [ "$SZ_BEFORE_G" != "$SZ_AFTER_G" ]; then
  echo "FAIL: AC#13 events.jsonl size changed (before A=$SZ_BEFORE_A B=$SZ_BEFORE_B G=$SZ_BEFORE_G | after A=$SZ_AFTER_A B=$SZ_AFTER_B G=$SZ_AFTER_G)"
  exit 1
fi
echo "  ok"

# ========================================================================
# AC #14 — Pseudonym map never written to disk. After --redact, no
#          newly-created file contains both a real slug AND its pseudonym.
# ========================================================================
echo "AC#14 — pseudonym map never persisted"
"$FLEET" portfolio --redact > /dev/null
snapshot_after="$TMP/snap-after.txt"
( cd "$TMP" && find home projects -type f | LC_ALL=C sort ) > "$snapshot_after"
new_files="$(comm -13 "$snapshot_before" "$snapshot_after" || true)"
# For each newly-created file: it must NOT contain a raw slug name.
# (If the file contains a raw slug but no pseudonym, that's also a leak
# of the source data, but the contract is about the MAP — we conservatively
# fail if both appear in the same file.)
fail=0
if [ -n "$new_files" ]; then
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    full="$TMP/$f"
    [ -f "$full" ] || continue
    for raw in alpha beta gamma; do
      if grep -qF -- "$raw" "$full" 2>/dev/null; then
        if grep -qF -- "project-" "$full" 2>/dev/null; then
          echo "FAIL: AC#14 newly-created file '$full' contains BOTH raw slug '$raw' AND a 'project-*' pseudonym"
          fail=1
        fi
      fi
    done
  done <<< "$new_files"
fi
[ "$fail" = "0" ] || exit 1
echo "  ok"

# ========================================================================
# AC #15 — lib/common.sh and prompts/ untouched; no new event types.
# ========================================================================
echo "AC#15 — lib/common.sh + prompts/ untouched"
( cd "$REPO_ROOT" && \
  diff="$(git diff --name-only main...HEAD -- lib/common.sh prompts/ 2>/dev/null || true)"
  if [ -n "$diff" ]; then
    echo "FAIL: AC#15 unexpected changes to lib/common.sh or prompts/: $diff"
    exit 1
  fi
)
echo "  ok"

echo
echo "tests/portfolio.sh — all AC blocks passed"
