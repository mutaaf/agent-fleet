#!/bin/bash
# tests/lessons-import.sh — bin/fleet lessons-import end-to-end.
#
# Ticket 0065. One assertion block per acceptance-criteria checkbox in
# docs/backlog/0065-fleet-lessons-import-third-party-lesson-pack-contract.md.
#
# AC#1  usage refusal + URL/file branches present.
# AC#2  pack schema validation: valid / invalid-JSON / missing publisher /
#       wrong schema_version.
# AC#3  signature verification: happy path / pubkey_sha256 mismatch /
#       untrusted publisher / --allow-unsigned --reason override.
# AC#4  dedupe pass skips paragraphs whose body sha already lives in
#       CROSS_LESSONS.md.
# AC#5  imported paragraphs land under `## from <publisher>:<pack-slug>`
#       (fresh + re-import append).
# AC#6  lessons_imported event lands in kit's events.jsonl on happy path;
#       no event on dry-run / refusal paths.
# AC#7  --dry-run leaves CROSS_LESSONS.md byte-size + events.jsonl tail
#       unchanged.
# AC#8  --file <path> happy path and missing-file refusal.
# AC#9  <url> downloads via curl stub; failed-download refuses with exit 3.
# AC#10 --allow-unsigned --reason "<text>" override; refuses without
#       --reason; ASCII guard for --reason.
# AC#11 --json emits one structured JSON object.
# AC#12 --help mentions every flag and exits 0.
# AC#13 only CROSS_LESSONS.md and kit events.jsonl get mutated.
# AC#14 lib/common.sh and prompts/ untouched in this PR; AGENTS.md UPDATED.
# AC#15 (this file) — fixtures live under tests/fixtures/lessons-import/.
#
# Per LESSONS 2026-05-26 stubs live in $HOME/.local/bin (otherwise
# common.sh's hardcoded PATH wipes a $TMP/bin). Per LESSONS 2026-05-27
# we use `cp` for backup/restore of fixture files - never `$(cat …)`.
# Per LESSONS 2026-06-01 counts use `awk … END { print n+0 }`. Per
# LESSONS 2026-06-08 `BEGIN { count = 0 }` for awk accumulators. Per
# LESSONS 2026-06-11 the timestamp parser uses the full
# '%Y-%m-%dT%H:%M:%SZ' format - no `date -j -f`.

set -euo pipefail

REPO_ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
FLEET="$REPO_ROOT/bin/fleet"
FIXTURES="$REPO_ROOT/tests/fixtures/lessons-import"

TMP="$(mktemp -d -t fleet-lessons-import-test.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

# Isolate from the host - HOME shapes the default cross-lessons root,
# the trusted-pubkeys.txt resolution, the events.jsonl path, and the
# stub PATH (per LESSONS 2026-05-26).
export HOME="$TMP/home"
mkdir -p "$HOME" "$HOME/.local/bin" "$HOME/.local/share/agent-fleet" \
  "$HOME/.cache/agent-fleet-agent"

# Direct the writer at a tmp cross-lessons file via FLEET_CROSS_LESSONS
# (the env precedence the ticket pins). Same precedence as 0028 / 0051.
CROSS="$HOME/.local/share/agent-fleet/CROSS_LESSONS.md"
cp "$FIXTURES/CROSS_LESSONS.md" "$CROSS"
export FLEET_CROSS_LESSONS="$CROSS"

# Trusted-pubkeys.txt at the canonical path.
cp "$FIXTURES/trusted-pubkeys.txt" \
  "$HOME/.local/share/agent-fleet/trusted-pubkeys.txt"

# Seed the kit-as-project events channel so AC#6 / AC#7 can read it.
cp "$FIXTURES/events.jsonl" "$HOME/.cache/agent-fleet-agent/events.jsonl"

# Freeze the clock so any "now" stamp is deterministic.
export FLEET_NOW_OVERRIDE="2026-06-23T15:00:00Z"

# --- stub: openssl ---------------------------------------------------------
# The signature verifier shells out to `openssl dgst -sha256 -verify
# <pubkey> -signature <sig-file> <body-file>`. We stub it so the test
# does not depend on LibreSSL's ed25519 support (macOS ships LibreSSL
# 3.3.x without ed25519). The stub matches by signature-file contents:
# "STUB_VALID_SIG_BASE64" -> exit 0; anything else -> exit 1.
cat > "$HOME/.local/bin/openssl" <<'STUB'
#!/bin/bash
# argv: dgst -sha256 -verify <pubkey> -signature <sig-file> <body-file>
set -u
sig_file=""
while [ $# -gt 0 ]; do
  case "$1" in
    -signature) sig_file="${2:-}"; shift 2 ;;
    *) shift ;;
  esac
done
if [ -z "$sig_file" ] || [ ! -f "$sig_file" ]; then
  echo "Verification Failure" >&2
  exit 1
fi
sig_content="$(cat "$sig_file")"
case "$sig_content" in
  STUB_VALID_SIG_BASE64)
    echo "Verified OK"
    exit 0 ;;
  *)
    echo "Verification Failure" >&2
    exit 1 ;;
esac
STUB
chmod +x "$HOME/.local/bin/openssl"

# --- stub: curl ------------------------------------------------------------
# curl -fsSL <url> -o <out>. We map a few sentinel URLs to fixture files
# or to non-zero exit. Argv shape: any order of -f -s -S -L and "-o <out>".
cat > "$HOME/.local/bin/curl" <<STUB
#!/bin/bash
set -u
FIXTURES="$FIXTURES"
out=""; url=""
while [ \$# -gt 0 ]; do
  case "\$1" in
    -o) out="\${2:-}"; shift 2 ;;
    -f|-s|-S|-L|-fsSL|-fSL|-sSL|-fsL) shift ;;
    -*) shift ;;
    *) url="\$1"; shift ;;
  esac
done
case "\$url" in
  *valid-signed*) cp "\$FIXTURES/valid-signed.pack.json" "\$out"; exit 0 ;;
  *unicode-body*) cp "\$FIXTURES/unicode-body.pack.json" "\$out"; exit 0 ;;
  *dedupe-collision*) cp "\$FIXTURES/dedupe-collision.pack.json" "\$out"; exit 0 ;;
  *fail-download*) echo "stub-curl: simulated network failure" >&2; exit 22 ;;
  *) echo "stub-curl: unknown url \$url" >&2; exit 7 ;;
esac
STUB
chmod +x "$HOME/.local/bin/curl"

export PATH="$HOME/.local/bin:$PATH"

# Snapshot helpers — record byte size of a file and the byte size of a
# JSONL channel's tail. Counts use `awk … END { print n+0 }` per
# LESSONS 2026-06-01.
file_size() {  # $1 = path
  local file_size_path="$1"
  if [ ! -f "$file_size_path" ]; then
    printf -- '0\n'
    return 0
  fi
  awk 'BEGIN { count = 0 } { count = count + length($0) + 1 } END { print count+0 }' "$file_size_path"
}

events_count_type() {  # $1 = path, $2 = type substring
  local events_path="$1" events_type="$2"
  [ -f "$events_path" ] || { echo 0; return 0; }
  awk -v t="$events_type" '
    BEGIN { count = 0 }
    $0 ~ "\"type\":\"" t "\"" { count = count + 1 }
    END { print count+0 }
  ' "$events_path"
}

# ---------------------------------------------------------------------------
# AC#1 — usage refusal + URL/file branches present.
# ---------------------------------------------------------------------------
set +e
"$FLEET" lessons-import > "$TMP/ac1.out" 2> "$TMP/ac1.err"
RC=$?
set -e
if [ "$RC" != "2" ]; then
  echo "FAIL: AC#1 — missing argv expected exit 2, got $RC"
  cat "$TMP/ac1.err"
  exit 1
fi
if ! grep -qF -- "lessons-import: usage: bin/fleet lessons-import <url> | --file <path>" "$TMP/ac1.err"; then
  echo "FAIL: AC#1 — usage line missing from stderr"
  cat "$TMP/ac1.err"
  exit 1
fi
if ! grep -qF -- "--dry-run" "$TMP/ac1.err"; then
  echo "FAIL: AC#1 — usage line should mention --dry-run"
  cat "$TMP/ac1.err"
  exit 1
fi
echo "ok AC#1: usage refusal exits 2 with usage line"

# ---------------------------------------------------------------------------
# AC#2 — pack schema validation.
# ---------------------------------------------------------------------------
# (a) invalid JSON -> exit 3 + clear stderr.
cp "$FIXTURES/CROSS_LESSONS.md" "$CROSS"
set +e
"$FLEET" lessons-import --file "$FIXTURES/invalid-json.pack.json" \
  > "$TMP/ac2a.out" 2> "$TMP/ac2a.err"
RC=$?
set -e
if [ "$RC" != "3" ]; then
  echo "FAIL: AC#2a — invalid JSON expected exit 3, got $RC"
  cat "$TMP/ac2a.err"
  exit 1
fi
if ! grep -qF -- "lessons-import: invalid JSON in pack file" "$TMP/ac2a.err"; then
  echo "FAIL: AC#2a — invalid JSON stderr missing"
  cat "$TMP/ac2a.err"
  exit 1
fi

# (b) missing required field (publisher) -> exit 3.
set +e
"$FLEET" lessons-import --file "$FIXTURES/missing-publisher.pack.json" \
  > "$TMP/ac2b.out" 2> "$TMP/ac2b.err"
RC=$?
set -e
if [ "$RC" != "3" ]; then
  echo "FAIL: AC#2b — missing publisher expected exit 3, got $RC"
  cat "$TMP/ac2b.err"
  exit 1
fi
if ! grep -qF -- "publisher" "$TMP/ac2b.err"; then
  echo "FAIL: AC#2b — missing-field stderr should mention 'publisher'"
  cat "$TMP/ac2b.err"
  exit 1
fi

# (c) wrong schema_version -> exit 3.
set +e
"$FLEET" lessons-import --file "$FIXTURES/wrong-schema.pack.json" \
  > "$TMP/ac2c.out" 2> "$TMP/ac2c.err"
RC=$?
set -e
if [ "$RC" != "3" ]; then
  echo "FAIL: AC#2c — wrong schema_version expected exit 3, got $RC"
  cat "$TMP/ac2c.err"
  exit 1
fi
if ! grep -qF -- "schema_version" "$TMP/ac2c.err"; then
  echo "FAIL: AC#2c — wrong schema stderr should mention 'schema_version'"
  cat "$TMP/ac2c.err"
  exit 1
fi
echo "ok AC#2: schema validation refuses invalid-JSON / missing-publisher / wrong-schema"

# ---------------------------------------------------------------------------
# AC#3 — signature verification.
# ---------------------------------------------------------------------------
# (a) pubkey_sha256 mismatch -> exit 3.
set +e
"$FLEET" lessons-import --file "$FIXTURES/wrong-pubkey.pack.json" \
  > "$TMP/ac3a.out" 2> "$TMP/ac3a.err"
RC=$?
set -e
if [ "$RC" != "3" ]; then
  echo "FAIL: AC#3a — pubkey mismatch expected exit 3, got $RC"
  cat "$TMP/ac3a.err"
  exit 1
fi
if ! grep -qF -- "pubkey_sha256 in pack" "$TMP/ac3a.err"; then
  echo "FAIL: AC#3a — pubkey-mismatch stderr missing"
  cat "$TMP/ac3a.err"
  exit 1
fi

# (b) untrusted publisher -> exit 3 with refusal nudge.
set +e
"$FLEET" lessons-import --file "$FIXTURES/untrusted-publisher.pack.json" \
  > "$TMP/ac3b.out" 2> "$TMP/ac3b.err"
RC=$?
set -e
if [ "$RC" != "3" ]; then
  echo "FAIL: AC#3b — untrusted publisher expected exit 3, got $RC"
  cat "$TMP/ac3b.err"
  exit 1
fi
if ! grep -qF -- "publisher stranger-danger not in trusted-pubkeys.txt" "$TMP/ac3b.err"; then
  echo "FAIL: AC#3b — untrusted-publisher stderr missing"
  cat "$TMP/ac3b.err"
  exit 1
fi
if ! grep -qF -- "--allow-unsigned" "$TMP/ac3b.err"; then
  echo "FAIL: AC#3b — untrusted stderr should nudge toward --allow-unsigned"
  cat "$TMP/ac3b.err"
  exit 1
fi

# (c) --allow-unsigned --reason override succeeds on untrusted-publisher.
cp "$FIXTURES/CROSS_LESSONS.md" "$CROSS"
cp "$FIXTURES/events.jsonl" "$HOME/.cache/agent-fleet-agent/events.jsonl"
set +e
"$FLEET" lessons-import --file "$FIXTURES/untrusted-publisher.pack.json" \
  --allow-unsigned --reason "air-gapped peer pack" \
  > "$TMP/ac3c.out" 2> "$TMP/ac3c.err"
RC=$?
set -e
if [ "$RC" != "0" ]; then
  echo "FAIL: AC#3c — --allow-unsigned override expected exit 0, got $RC"
  cat "$TMP/ac3c.err"
  exit 1
fi
if ! grep -qF -- "## from stranger-danger:" "$CROSS"; then
  echo "FAIL: AC#3c — namespace section missing after override"
  cat "$CROSS"
  exit 1
fi

# (d) happy path: trusted publisher, real signature, valid pubkey_sha256.
cp "$FIXTURES/CROSS_LESSONS.md" "$CROSS"
cp "$FIXTURES/events.jsonl" "$HOME/.cache/agent-fleet-agent/events.jsonl"
set +e
"$FLEET" lessons-import --file "$FIXTURES/valid-signed.pack.json" \
  > "$TMP/ac3d.out" 2> "$TMP/ac3d.err"
RC=$?
set -e
if [ "$RC" != "0" ]; then
  echo "FAIL: AC#3d — happy path expected exit 0, got $RC"
  cat "$TMP/ac3d.err"
  exit 1
fi
echo "ok AC#3: signature verification + override paths"

# ---------------------------------------------------------------------------
# AC#4 — dedupe pass: 4 of 10 lessons collide -> 6 imported, 4 skipped.
# ---------------------------------------------------------------------------
cp "$FIXTURES/CROSS_LESSONS.md" "$CROSS"
cp "$FIXTURES/events.jsonl" "$HOME/.cache/agent-fleet-agent/events.jsonl"
set +e
"$FLEET" lessons-import --file "$FIXTURES/dedupe-collision.pack.json" \
  > "$TMP/ac4.out" 2> "$TMP/ac4.err"
RC=$?
set -e
if [ "$RC" != "0" ]; then
  echo "FAIL: AC#4 — dedupe import expected exit 0, got $RC"
  cat "$TMP/ac4.err"
  exit 1
fi
if ! grep -qF -- "imported: 6" "$TMP/ac4.out"; then
  echo "FAIL: AC#4 — should report 'imported: 6'"
  cat "$TMP/ac4.out"
  exit 1
fi
if ! grep -qF -- "dedup_skipped: 4" "$TMP/ac4.out"; then
  echo "FAIL: AC#4 — should report 'dedup_skipped: 4'"
  cat "$TMP/ac4.out"
  exit 1
fi
echo "ok AC#4: dedupe walks pack + CROSS_LESSONS in one pass each"

# ---------------------------------------------------------------------------
# AC#5 — namespace section heading + re-import append.
# ---------------------------------------------------------------------------
cp "$FIXTURES/CROSS_LESSONS.md" "$CROSS"
cp "$FIXTURES/events.jsonl" "$HOME/.cache/agent-fleet-agent/events.jsonl"
"$FLEET" lessons-import --file "$FIXTURES/valid-signed.pack.json" \
  > "$TMP/ac5a.out" 2> "$TMP/ac5a.err"
if ! grep -qE '^## from peer-good:' "$CROSS"; then
  echo "FAIL: AC#5 — namespace section heading missing"
  cat "$CROSS"
  exit 1
fi
# The pre-existing ## agent-fleet content must STILL be there.
if ! grep -qF -- "### 2026-05-25 — bootstrap" "$CROSS"; then
  echo "FAIL: AC#5 — pre-existing agent-fleet content destroyed"
  cat "$CROSS"
  exit 1
fi

# Re-import: same publisher+version -> appends within the same section,
# no duplicate paragraphs (dedupe still applies).
BEFORE_COUNT=$(awk 'BEGIN { count = 0 } /^### / { count = count + 1 } END { print count+0 }' "$CROSS")
"$FLEET" lessons-import --file "$FIXTURES/valid-signed.pack.json" \
  > "$TMP/ac5b.out" 2> "$TMP/ac5b.err" || true
AFTER_COUNT=$(awk 'BEGIN { count = 0 } /^### / { count = count + 1 } END { print count+0 }' "$CROSS")
if [ "$BEFORE_COUNT" != "$AFTER_COUNT" ]; then
  echo "FAIL: AC#5 — re-import duplicated paragraphs (before=$BEFORE_COUNT after=$AFTER_COUNT)"
  cat "$CROSS"
  exit 1
fi
# The `## from <publisher>` heading text appears INSIDE the section, so
# the section-finder MUST use the cursor-walk pattern - the literal text
# `## from` would re-match a recursive while/match scan. Per LESSONS
# 2026-06-15. Assert there is exactly ONE `## from peer-good:` heading.
HEADING_N=$(awk 'BEGIN { count = 0 } /^## from peer-good:/ { count = count + 1 } END { print count+0 }' "$CROSS")
if [ "$HEADING_N" != "1" ]; then
  echo "FAIL: AC#5 — expected exactly one '## from peer-good:' heading, got $HEADING_N"
  cat "$CROSS"
  exit 1
fi
echo "ok AC#5: namespace section + re-import idempotency"

# ---------------------------------------------------------------------------
# AC#6 — lessons_imported event fires on happy path; silent on dry-run.
# ---------------------------------------------------------------------------
cp "$FIXTURES/CROSS_LESSONS.md" "$CROSS"
cp "$FIXTURES/events.jsonl" "$HOME/.cache/agent-fleet-agent/events.jsonl"
BEFORE_EV=$(events_count_type "$HOME/.cache/agent-fleet-agent/events.jsonl" "lessons_imported")
"$FLEET" lessons-import --file "$FIXTURES/valid-signed.pack.json" \
  > "$TMP/ac6.out" 2> "$TMP/ac6.err"
AFTER_EV=$(events_count_type "$HOME/.cache/agent-fleet-agent/events.jsonl" "lessons_imported")
if [ "$AFTER_EV" -le "$BEFORE_EV" ]; then
  echo "FAIL: AC#6 — happy path should emit lessons_imported (before=$BEFORE_EV after=$AFTER_EV)"
  cat "$HOME/.cache/agent-fleet-agent/events.jsonl"
  exit 1
fi
# Inspect the latest event line for required fields.
LAST_EV=$(grep -F '"type":"lessons_imported"' "$HOME/.cache/agent-fleet-agent/events.jsonl" | tail -1)
for kw in '"source":"peer-good"' '"version":"3.2.0"' '"count":"5"' '"dedup_skipped":"0"' '"unsigned":"0"' '"phase":"lessons-import"'; do
  if ! printf -- '%s' "$LAST_EV" | grep -qF -- "$kw"; then
    echo "FAIL: AC#6 — event missing $kw"
    printf -- '%s\n' "$LAST_EV"
    exit 1
  fi
done
echo "ok AC#6: lessons_imported event lands with phase=lessons-import"

# ---------------------------------------------------------------------------
# AC#7 — --dry-run leaves CROSS_LESSONS and events.jsonl untouched.
# ---------------------------------------------------------------------------
cp "$FIXTURES/CROSS_LESSONS.md" "$CROSS"
cp "$FIXTURES/events.jsonl" "$HOME/.cache/agent-fleet-agent/events.jsonl"
BEFORE_SIZE=$(file_size "$CROSS")
BEFORE_EVSIZE=$(file_size "$HOME/.cache/agent-fleet-agent/events.jsonl")
"$FLEET" lessons-import --file "$FIXTURES/valid-signed.pack.json" --dry-run \
  > "$TMP/ac7.out" 2> "$TMP/ac7.err"
AFTER_SIZE=$(file_size "$CROSS")
AFTER_EVSIZE=$(file_size "$HOME/.cache/agent-fleet-agent/events.jsonl")
if [ "$BEFORE_SIZE" != "$AFTER_SIZE" ]; then
  echo "FAIL: AC#7 — dry-run mutated CROSS_LESSONS.md (before=$BEFORE_SIZE after=$AFTER_SIZE)"
  exit 1
fi
if [ "$BEFORE_EVSIZE" != "$AFTER_EVSIZE" ]; then
  echo "FAIL: AC#7 — dry-run emitted an event"
  exit 1
fi
if ! grep -qF -- "dry-run" "$TMP/ac7.out"; then
  echo "FAIL: AC#7 — dry-run output missing 'dry-run' marker"
  cat "$TMP/ac7.out"
  exit 1
fi
if ! grep -qF -- "## from peer-good:" "$TMP/ac7.out"; then
  echo "FAIL: AC#7 — dry-run should preview the namespace section heading"
  cat "$TMP/ac7.out"
  exit 1
fi
echo "ok AC#7: --dry-run is a pure read"

# ---------------------------------------------------------------------------
# AC#8 — --file <path> happy path + missing file refuses with exit 2.
# ---------------------------------------------------------------------------
set +e
"$FLEET" lessons-import --file "$TMP/does-not-exist.json" \
  > "$TMP/ac8.out" 2> "$TMP/ac8.err"
RC=$?
set -e
if [ "$RC" != "2" ]; then
  echo "FAIL: AC#8 — missing file expected exit 2, got $RC"
  cat "$TMP/ac8.err"
  exit 1
fi
if ! grep -qF -- "lessons-import: file" "$TMP/ac8.err"; then
  echo "FAIL: AC#8 — missing-file stderr missing"
  cat "$TMP/ac8.err"
  exit 1
fi
if ! grep -qF -- "not found" "$TMP/ac8.err"; then
  echo "FAIL: AC#8 — missing-file stderr should say 'not found'"
  cat "$TMP/ac8.err"
  exit 1
fi
echo "ok AC#8: --file <path> happy/refusal"

# ---------------------------------------------------------------------------
# AC#9 — <url> downloads via curl stub; failed download exits 3.
# ---------------------------------------------------------------------------
cp "$FIXTURES/CROSS_LESSONS.md" "$CROSS"
cp "$FIXTURES/events.jsonl" "$HOME/.cache/agent-fleet-agent/events.jsonl"
"$FLEET" lessons-import "https://example.com/valid-signed.pack.json" \
  > "$TMP/ac9a.out" 2> "$TMP/ac9a.err"
if ! grep -qE '^## from peer-good:' "$CROSS"; then
  echo "FAIL: AC#9a — URL happy path did not write namespace section"
  cat "$CROSS"
  exit 1
fi

# Failed download -> exit 3.
set +e
"$FLEET" lessons-import "https://example.com/fail-download.pack.json" \
  > "$TMP/ac9b.out" 2> "$TMP/ac9b.err"
RC=$?
set -e
if [ "$RC" != "3" ]; then
  echo "FAIL: AC#9b — failed download expected exit 3, got $RC"
  cat "$TMP/ac9b.err"
  exit 1
fi
if ! grep -qF -- "lessons-import: failed to download" "$TMP/ac9b.err"; then
  echo "FAIL: AC#9b — failed-download stderr missing"
  cat "$TMP/ac9b.err"
  exit 1
fi
echo "ok AC#9: <url> path downloads via curl stub + handles failure"

# ---------------------------------------------------------------------------
# AC#10 — --allow-unsigned --reason "<text>"; refuses without --reason;
#         ASCII guard on --reason.
# ---------------------------------------------------------------------------
# (a) --allow-unsigned without --reason -> exit 2.
set +e
"$FLEET" lessons-import --file "$FIXTURES/valid-signed.pack.json" --allow-unsigned \
  > "$TMP/ac10a.out" 2> "$TMP/ac10a.err"
RC=$?
set -e
if [ "$RC" != "2" ]; then
  echo "FAIL: AC#10a — --allow-unsigned without --reason expected exit 2, got $RC"
  cat "$TMP/ac10a.err"
  exit 1
fi
if ! grep -qF -- 'lessons-import: --allow-unsigned requires --reason' "$TMP/ac10a.err"; then
  echo "FAIL: AC#10a — missing-reason stderr line missing"
  cat "$TMP/ac10a.err"
  exit 1
fi

# (b) non-ASCII --reason -> exit 2.
set +e
"$FLEET" lessons-import --file "$FIXTURES/untrusted-publisher.pack.json" \
  --allow-unsigned --reason "café latte" \
  > "$TMP/ac10b.out" 2> "$TMP/ac10b.err"
RC=$?
set -e
if [ "$RC" != "2" ]; then
  echo "FAIL: AC#10b — non-ASCII --reason expected exit 2, got $RC"
  cat "$TMP/ac10b.err"
  exit 1
fi
if ! grep -qF -- "ASCII" "$TMP/ac10b.err"; then
  echo "FAIL: AC#10b — non-ASCII guard stderr missing"
  cat "$TMP/ac10b.err"
  exit 1
fi

# (c) ASCII --reason succeeds + event payload carries reason verbatim.
cp "$FIXTURES/CROSS_LESSONS.md" "$CROSS"
cp "$FIXTURES/events.jsonl" "$HOME/.cache/agent-fleet-agent/events.jsonl"
"$FLEET" lessons-import --file "$FIXTURES/untrusted-publisher.pack.json" \
  --allow-unsigned --reason "air-gapped peer pack" \
  > "$TMP/ac10c.out" 2> "$TMP/ac10c.err"
LAST_EV=$(grep -F '"type":"lessons_imported"' "$HOME/.cache/agent-fleet-agent/events.jsonl" | tail -1)
if ! printf -- '%s' "$LAST_EV" | grep -qF -- '"reason":"air-gapped peer pack"'; then
  echo "FAIL: AC#10c — event missing reason payload"
  printf -- '%s\n' "$LAST_EV"
  exit 1
fi
if ! printf -- '%s' "$LAST_EV" | grep -qF -- '"unsigned":"1"'; then
  echo "FAIL: AC#10c — event should carry unsigned=1 on override path"
  printf -- '%s\n' "$LAST_EV"
  exit 1
fi
echo "ok AC#10: --allow-unsigned --reason gating"

# ---------------------------------------------------------------------------
# AC#11 — --json emits one structured object validatable by Node.
# ---------------------------------------------------------------------------
cp "$FIXTURES/CROSS_LESSONS.md" "$CROSS"
cp "$FIXTURES/events.jsonl" "$HOME/.cache/agent-fleet-agent/events.jsonl"
"$FLEET" lessons-import --file "$FIXTURES/valid-signed.pack.json" --json \
  > "$TMP/ac11.out" 2> "$TMP/ac11.err"
if ! node -e 'const data = require("fs").readFileSync(process.argv[1], "utf8"); const o = JSON.parse(data); if (!o.pack || !o.pack.publisher) process.exit(1); if (typeof o.imported_count !== "number") process.exit(2); if (!Array.isArray(o.lesson_dates)) process.exit(3);' "$TMP/ac11.out"; then
  echo "FAIL: AC#11 — --json output not a valid pack object"
  cat "$TMP/ac11.out"
  exit 1
fi
echo "ok AC#11: --json is a structured JSON object"

# ---------------------------------------------------------------------------
# AC#12 — --help mentions every flag and exits 0.
# ---------------------------------------------------------------------------
set +e
"$FLEET" lessons-import --help > "$TMP/ac12.out" 2> "$TMP/ac12.err"
RC=$?
set -e
if [ "$RC" != "0" ]; then
  echo "FAIL: AC#12 — --help expected exit 0, got $RC"
  cat "$TMP/ac12.err"
  exit 1
fi
for kw in '--file' '--dry-run' '--allow-unsigned' '--reason' '--json'; do
  if ! grep -qF -- "$kw" "$TMP/ac12.out"; then
    echo "FAIL: AC#12 — --help missing $kw"
    cat "$TMP/ac12.out"
    exit 1
  fi
done
echo "ok AC#12: --help lists every flag"

# ---------------------------------------------------------------------------
# AC#13 — only CROSS_LESSONS.md and kit events.jsonl get mutated.
# ---------------------------------------------------------------------------
# Snapshot mtimes/contents of the surrounding tree before a fresh import.
cp "$FIXTURES/CROSS_LESSONS.md" "$CROSS"
cp "$FIXTURES/events.jsonl" "$HOME/.cache/agent-fleet-agent/events.jsonl"
SENTINEL_PROJECT_DIR="$TMP/sentinel-project"
mkdir -p "$SENTINEL_PROJECT_DIR"
echo "untouched config" > "$SENTINEL_PROJECT_DIR/agents.config.sh"
SENTINEL_BEFORE=$(file_size "$SENTINEL_PROJECT_DIR/agents.config.sh")

"$FLEET" lessons-import --file "$FIXTURES/valid-signed.pack.json" \
  > "$TMP/ac13.out" 2> "$TMP/ac13.err"

SENTINEL_AFTER=$(file_size "$SENTINEL_PROJECT_DIR/agents.config.sh")
if [ "$SENTINEL_BEFORE" != "$SENTINEL_AFTER" ]; then
  echo "FAIL: AC#13 — sibling agents.config.sh was mutated"
  exit 1
fi
# Repo lib/common.sh + prompts/ MUST be byte-equivalent to main's copy.
if ! git -C "$REPO_ROOT" diff --quiet main -- lib/common.sh; then
  echo "FAIL: AC#13 — lib/common.sh diff against main is non-empty"
  exit 1
fi
if ! git -C "$REPO_ROOT" diff --quiet main -- 'prompts/*.md'; then
  echo "FAIL: AC#13 — prompts/ diff against main is non-empty"
  exit 1
fi
echo "ok AC#13: only CROSS_LESSONS.md and events.jsonl mutated"

# ---------------------------------------------------------------------------
# AC#14 — AGENTS.md UPDATED with the new event type; lib/common.sh and
#         prompts/ untouched.
# ---------------------------------------------------------------------------
if ! git -C "$REPO_ROOT" diff main...HEAD -- AGENTS.md | grep -qF -- "lessons_imported"; then
  echo "FAIL: AC#14 — AGENTS.md diff missing 'lessons_imported'"
  exit 1
fi
if ! git -C "$REPO_ROOT" diff --quiet main...HEAD -- lib/common.sh; then
  echo "FAIL: AC#14 — lib/common.sh has changed against main"
  exit 1
fi
if ! git -C "$REPO_ROOT" diff --quiet main...HEAD -- 'prompts/'; then
  echo "FAIL: AC#14 — prompts/ has changed against main"
  exit 1
fi
echo "ok AC#14: AGENTS.md updated; lib/common.sh and prompts/ untouched"

# ---------------------------------------------------------------------------
# AC#15 — UTF-8 body round-trips per LESSONS 2026-06-03.
# ---------------------------------------------------------------------------
cp "$FIXTURES/CROSS_LESSONS.md" "$CROSS"
cp "$FIXTURES/events.jsonl" "$HOME/.cache/agent-fleet-agent/events.jsonl"
"$FLEET" lessons-import --file "$FIXTURES/unicode-body.pack.json" \
  > "$TMP/ac15.out" 2> "$TMP/ac15.err"
if ! grep -qF -- "em-dash — and en-dash" "$CROSS"; then
  echo "FAIL: AC#15 — em-dash didn't round-trip into CROSS_LESSONS.md"
  cat "$CROSS"
  exit 1
fi
if ! grep -qF -- "café, naïve, ümlaut, 中文" "$CROSS"; then
  echo "FAIL: AC#15 — unicode body didn't round-trip"
  cat "$CROSS"
  exit 1
fi
echo "ok AC#15: UTF-8 body round-trips per LESSONS 2026-06-03"

echo "PASS tests/lessons-import.sh"
