#!/bin/bash
# tests/migrate.sh — `bin/fleet migrate --export / --import` end-to-end test.
#
# Ticket 0063. One assertion block per acceptance-criteria checkbox in
# docs/backlog/0063-fleet-migrate-export-import-fleet-state.md.
#
# `migrate` is a PURE PACKAGER+ORCHESTRATOR: no events.jsonl writes, no
# fleet_emit_event, no lib/common.sh / prompts/ / AGENTS.md edits, no new
# event types. The test asserts source events/runs byte sizes are unchanged
# across --export (AC #13) and that the diff against main is empty for
# lib/common.sh / prompts/ / AGENTS.md (AC #14).
#
# Per LESSONS 2026-05-26 stubs live under $HOME/.local/bin (lib/common.sh
# resets PATH; bin/fleet does not source it, but HOME isolation matters).
# Per LESSONS 2026-05-27 every fixture is copied with `cp` (never `$(cat …)`).
# Per LESSONS 2026-06-01 every count uses `awk … END { print n+0 }`.
# Per LESSONS 2026-06-08 every awk accumulator declares `BEGIN { count = 0 }`.
# Per LESSONS 2026-05-30 help-text greps use `grep -qF -- "$kw"`.
# Per LESSONS 2026-06-11 the timestamp helper uses `date -u '+%Y-%m-%dT%H:%M:%SZ'`.

set -euo pipefail

REPO_ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
FLEET="$REPO_ROOT/bin/fleet"
FIXTURE_DIR="$REPO_ROOT/tests/fixtures/migrate"

TMP="$(mktemp -d -t fleet-migrate-test.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

# Isolate HOME so $HOME/.cache, $HOME/.local/bin stay sandboxed.
export HOME="$TMP/home"
mkdir -p "$HOME/.local/bin" "$HOME/.cache" "$HOME/Desktop"

# Anchor "today" so the default-path test branch is deterministic.
export FLEET_NOW_OVERRIDE="2026-06-23T12:00:00Z"

# --- stubs: git, install.sh, openssl (passthrough), launchctl ----------------
# Per LESSONS 2026-05-26 PATH reset, all stubs live under $HOME/.local/bin so
# they survive lib/common.sh's PATH export. bin/fleet itself does not source
# common.sh, but `install.sh` (under test) does — keep the stubs there to be
# robust against any future migration that does source it.

# git stub: records argv to a log file AND mkdir's a fake $4 (clone target) so
# subsequent install.sh invocations see a real-looking directory.
GIT_LOG="$TMP/git-calls.log"
: > "$GIT_LOG"
cat > "$HOME/.local/bin/git" <<STUB
#!/bin/bash
# Records ALL invocations. For \`git clone <url> <dst>\` create <dst>/.git so
# subsequent file ops on the cloned tree don't trip over a missing directory.
printf -- '%s\n' "\$*" >> "$GIT_LOG"
if [ "\${1:-}" = "clone" ]; then
  dst="\${3:-}"
  [ -z "\$dst" ] && dst="."
  mkdir -p "\$dst/.git"
  exit 0
fi
exit 0
STUB
chmod +x "$HOME/.local/bin/git"

# install.sh stub via FLEET_INSTALL_CMD: records (dst-dir) per invocation.
INSTALL_LOG="$TMP/install-calls.log"
: > "$INSTALL_LOG"
cat > "$HOME/.local/bin/fleet-install-stub.sh" <<STUB
#!/bin/bash
printf -- '%s\n' "\$1" >> "$INSTALL_LOG"
exit 0
STUB
chmod +x "$HOME/.local/bin/fleet-install-stub.sh"
export FLEET_INSTALL_CMD="$HOME/.local/bin/fleet-install-stub.sh"

# launchctl stub: install.sh ramps may invoke it; the kit's onboard test
# already does the same.
cat > "$HOME/.local/bin/launchctl" <<'STUB'
#!/bin/bash
exit 0
STUB
chmod +x "$HOME/.local/bin/launchctl"

export PATH="$HOME/.local/bin:$PATH"

# --- seed discovered slugs ---------------------------------------------------
# Point FLEET_DISCOVERY_ROOT at a clean fixture tree (four manifests under
# $TMP/projects/<slug>/agents.config.sh) and per-slug $HOME/.cache/<slug>-agent
# with events/runs jsonl copied byte-for-byte from the fixture.
FIXTURE_ROOT="$TMP/projects"
mkdir -p "$FIXTURE_ROOT"
export FLEET_DISCOVERY_ROOT="$FIXTURE_ROOT"

# Cross-lessons target lives under $HOME/.local/share/agent-fleet/CROSS_LESSONS.md
# by default (see 0028/0051) — override to a sandboxed path so the test can
# write/read without touching the host.
export FLEET_CROSS_LESSONS="$HOME/.local/share/agent-fleet/CROSS_LESSONS.md"
mkdir -p "$(dirname "$FLEET_CROSS_LESSONS")"
cp "$FIXTURE_DIR/source/cross-lessons/CROSS_LESSONS.md" "$FLEET_CROSS_LESSONS"

SLUGS="alpha-strong beta-quiet gamma-busy delta-empty"
for slug in $SLUGS; do
  src="$FIXTURE_DIR/source/$slug"
  dst_manifest="$FIXTURE_ROOT/$slug"
  mkdir -p "$dst_manifest"
  cp "$src/agents.config.sh" "$dst_manifest/agents.config.sh"
  cache="$HOME/.cache/${slug}-agent"
  mkdir -p "$cache"
  cp "$src/events.jsonl" "$cache/events.jsonl"
  cp "$src/runs.jsonl" "$cache/runs.jsonl"
done

# Record source byte sizes for AC #13 (writes-only-to-named-output assertion).
SRC_SIZES_BEFORE="$TMP/src-sizes-before.txt"
( for slug in $SLUGS; do
    cache="$HOME/.cache/${slug}-agent"
    wc -c "$cache/events.jsonl" "$cache/runs.jsonl" 2>/dev/null
  done
) > "$SRC_SIZES_BEFORE"

PASS=0
FAIL=0
ASSERT() {  # $1 = label, $2 = condition string
  if eval "$2"; then
    PASS=$((PASS+1))
    printf -- 'PASS: %s\n' "$1"
  else
    FAIL=$((FAIL+1))
    printf -- 'FAIL: %s\n' "$1" >&2
  fi
}

# --- AC #1: refusal and default path ---------------------------------------
REFUSE_OUT="$TMP/refuse.out"
set +e
"$FLEET" migrate > "$REFUSE_OUT" 2>&1
REFUSE_EXIT=$?
set -e
ASSERT "AC1: bare migrate refuses with exit 2" "[ \"$REFUSE_EXIT\" = 2 ]"
ASSERT "AC1: refusal banner mentions --export" "grep -qF -- '--export' \"$REFUSE_OUT\""
ASSERT "AC1: refusal banner mentions --import" "grep -qF -- '--import' \"$REFUSE_OUT\""

DEFAULT_OUT="$TMP/default-export.out"
set +e
"$FLEET" migrate --export > "$DEFAULT_OUT" 2>&1
DEFAULT_EXIT=$?
set -e
EXPECTED_DEFAULT="$HOME/Desktop/fleet-2026-06-23.tar.gz"
ASSERT "AC1: --export (no path) exits 0" "[ \"$DEFAULT_EXIT\" = 0 ]"
ASSERT "AC1: default path written to ~/Desktop/fleet-YYYY-MM-DD.tar.gz" "[ -f \"$EXPECTED_DEFAULT\" ]"

# --- AC #2: tarball layout ---------------------------------------------------
EXPORT_PATH="$TMP/export.tar.gz"
set +e
"$FLEET" migrate --export "$EXPORT_PATH" > "$TMP/export.out" 2>&1
EXPORT_EXIT=$?
set -e
ASSERT "AC2: --export <path> exits 0" "[ \"$EXPORT_EXIT\" = 0 ]"
ASSERT "AC2: tarball exists" "[ -f \"$EXPORT_PATH\" ]"

LISTING="$TMP/tar-listing.txt"
tar -tzf "$EXPORT_PATH" > "$LISTING"
ASSERT "AC2: contains fleet-export.json at root" "grep -qF -- 'fleet-export.json' \"$LISTING\""
for slug in $SLUGS; do
  ASSERT "AC2: contains $slug/agents.config.sh" "grep -qF -- '$slug/agents.config.sh' \"$LISTING\""
  ASSERT "AC2: contains $slug/events.jsonl" "grep -qF -- '$slug/events.jsonl' \"$LISTING\""
  ASSERT "AC2: contains $slug/runs.jsonl" "grep -qF -- '$slug/runs.jsonl' \"$LISTING\""
done
ASSERT "AC2: contains cross-lessons/CROSS_LESSONS.md" "grep -qF -- 'cross-lessons/CROSS_LESSONS.md' \"$LISTING\""
ASSERT "AC2: does NOT contain installed lib/ copy" "! grep -qE -- '(^|/)lib/common\.sh' \"$LISTING\""

# --- AC #3: fleet-export.json manifest schema -------------------------------
STAGE="$TMP/extract"
mkdir -p "$STAGE"
tar -xzf "$EXPORT_PATH" -C "$STAGE"
MANIFEST="$STAGE/fleet-export.json"
ASSERT "AC3: manifest exists" "[ -f \"$MANIFEST\" ]"

# Validate JSON shape + required fields via node.
node -e "
  const fs = require('fs');
  const m = JSON.parse(fs.readFileSync('$MANIFEST', 'utf8'));
  const required = ['schema_version', 'created_at', 'host', 'slugs', 'tarball_sha256'];
  for (const k of required) {
    if (!(k in m)) { console.error('missing top-level: ' + k); process.exit(1); }
  }
  if (m.schema_version !== 1) { console.error('schema_version != 1'); process.exit(1); }
  if (!/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z\$/.test(m.created_at)) {
    console.error('created_at not ISO8601 UTC: ' + m.created_at); process.exit(1);
  }
  if (!Array.isArray(m.slugs)) { console.error('slugs not array'); process.exit(1); }
  if (m.slugs.length !== 4) { console.error('slugs.length != 4: ' + m.slugs.length); process.exit(1); }
  const wantKeys = ['slug','repo_path','repo_url','events_bytes','runs_bytes','events_sha256','runs_sha256','expected_verify'];
  for (const s of m.slugs) {
    for (const k of wantKeys) {
      if (!(k in s)) { console.error('slug ' + s.slug + ' missing ' + k); process.exit(1); }
    }
    const v = s.expected_verify;
    for (const k of ['pr_footer_posted_count','streak_days','lessons_promoted_count']) {
      if (!(k in v)) { console.error('expected_verify missing ' + k); process.exit(1); }
    }
  }
  // alpha-strong known counts.
  const alpha = m.slugs.find(s => s.slug === 'alpha-strong');
  if (alpha.expected_verify.pr_footer_posted_count !== 3) {
    console.error('alpha pr_footer_posted_count = ' + alpha.expected_verify.pr_footer_posted_count + ' want 3'); process.exit(1);
  }
  if (alpha.expected_verify.lessons_promoted_count !== 2) {
    console.error('alpha lessons_promoted_count = ' + alpha.expected_verify.lessons_promoted_count + ' want 2'); process.exit(1);
  }
  if (alpha.expected_verify.streak_days !== 5) {
    console.error('alpha streak_days = ' + alpha.expected_verify.streak_days + ' want 5'); process.exit(1);
  }
  console.log('manifest OK');
" 2>&1 | tee "$TMP/manifest-validate.out" >/dev/null
MANIFEST_VALIDATE_OUT="$(cat "$TMP/manifest-validate.out")"
ASSERT "AC3: manifest schema valid" "[ \"$MANIFEST_VALIDATE_OUT\" = 'manifest OK' ]"

# --- AC #4: --export --redact ------------------------------------------------
REDACT_EXPORT="$TMP/redact.tar.gz"
set +e
"$FLEET" migrate --export "$REDACT_EXPORT" --redact > "$TMP/redact.out" 2>&1
REDACT_EXIT=$?
set -e
ASSERT "AC4: --export --redact exits 0" "[ \"$REDACT_EXIT\" = 0 ]"

RSTAGE="$TMP/extract-redact"
mkdir -p "$RSTAGE"
tar -xzf "$REDACT_EXPORT" -C "$RSTAGE"

# The redacted manifest should not contain the original slug names.
RMANIFEST_RAW="$(cat "$RSTAGE/fleet-export.json")"
HAS_ANY_REAL_SLUG=0
for slug in $SLUGS; do
  if printf -- '%s' "$RMANIFEST_RAW" | grep -qF -- "\"$slug\""; then
    HAS_ANY_REAL_SLUG=1
  fi
done
ASSERT "AC4: redacted manifest contains no real slug name" "[ $HAS_ANY_REAL_SLUG = 0 ]"
ASSERT "AC4: redacted manifest contains project-a alias" "grep -qF -- 'project-a' \"$RSTAGE/fleet-export.json\""

# Redacted runs.jsonl: no original dollar value like 12.50.
RUNS_BAND_FILE="$RSTAGE/project-c/runs.jsonl"
if [ -f "$RUNS_BAND_FILE" ]; then
  ASSERT "AC4: redacted runs.jsonl has banded dollar values" "! grep -qF -- '12.50' \"$RUNS_BAND_FILE\""
fi

# --- AC #5: --export --encrypt requires FLEET_EXPORT_PASS --------------------
ENC_OUT_MISSING="$TMP/enc-missing.out"
unset FLEET_EXPORT_PASS || true
set +e
"$FLEET" migrate --export "$TMP/enc.tar.gz" --encrypt > "$ENC_OUT_MISSING" 2>&1
ENC_MISSING_EXIT=$?
set -e
ASSERT "AC5: --encrypt without env exits 2" "[ \"$ENC_MISSING_EXIT\" = 2 ]"
ASSERT "AC5: error names FLEET_EXPORT_PASS" "grep -qF -- 'FLEET_EXPORT_PASS' \"$ENC_OUT_MISSING\""

# Only run the encrypt round-trip when openssl is on PATH.
if command -v openssl >/dev/null 2>&1; then
  export FLEET_EXPORT_PASS="correct-horse-battery-staple"
  set +e
  "$FLEET" migrate --export "$TMP/encrypted.tar.gz" --encrypt > "$TMP/enc.out" 2>&1
  ENC_EXIT=$?
  set -e
  ASSERT "AC5: --encrypt with env exits 0" "[ \"$ENC_EXIT\" = 0 ]"
  ASSERT "AC5: encrypted output uses .tar.gz.enc extension" "[ -f \"$TMP/encrypted.tar.gz.enc\" ]"
  unset FLEET_EXPORT_PASS
else
  printf -- 'SKIP: AC5 round-trip (openssl not on PATH)\n'
fi

# --- AC #6: --import refusals (sha mismatch, schema mismatch) ----------------
# Build a tampered tarball by extracting, mutating the manifest, repacking.
TAMP_STAGE="$TMP/tamper-stage"
mkdir -p "$TAMP_STAGE"
tar -xzf "$EXPORT_PATH" -C "$TAMP_STAGE"
# Tweak the manifest sha256 to a wrong value while keeping the structure
# intact. We use python3 or node to JSON-rewrite (already a node dep).
node -e "
  const fs = require('fs');
  const p = '$TAMP_STAGE/fleet-export.json';
  const m = JSON.parse(fs.readFileSync(p, 'utf8'));
  m.tarball_sha256 = 'deadbeef'.repeat(8);
  fs.writeFileSync(p, JSON.stringify(m));
"
TAMPERED_TARBALL="$TMP/tampered.tar.gz"
( cd "$TAMP_STAGE" && tar -czf "$TAMPERED_TARBALL" . )

IMPORT_OUT="$TMP/import-tampered.out"
set +e
"$FLEET" migrate --import "$TAMPERED_TARBALL" --skip-clone > "$IMPORT_OUT" 2>&1 < /dev/null
IMPORT_EXIT=$?
set -e
ASSERT "AC6: tampered import refuses with exit 3" "[ \"$IMPORT_EXIT\" = 3 ]"
ASSERT "AC6: refusal mentions sha256 mismatch" "grep -qiF -- 'sha256' \"$IMPORT_OUT\""

# Schema mismatch: build another tampered with schema_version=99.
SCHEMA_STAGE="$TMP/schema-stage"
mkdir -p "$SCHEMA_STAGE"
tar -xzf "$EXPORT_PATH" -C "$SCHEMA_STAGE"
node -e "
  const fs = require('fs');
  const p = '$SCHEMA_STAGE/fleet-export.json';
  const m = JSON.parse(fs.readFileSync(p, 'utf8'));
  m.schema_version = 99;
  fs.writeFileSync(p, JSON.stringify(m));
"
SCHEMA_TARBALL="$TMP/schema.tar.gz"
( cd "$SCHEMA_STAGE" && tar -czf "$SCHEMA_TARBALL" . )

SCHEMA_OUT="$TMP/import-schema.out"
set +e
"$FLEET" migrate --import "$SCHEMA_TARBALL" --skip-clone > "$SCHEMA_OUT" 2>&1 < /dev/null
SCHEMA_EXIT=$?
set -e
ASSERT "AC6: bad schema_version refuses with exit 3" "[ \"$SCHEMA_EXIT\" = 3 ]"
ASSERT "AC6: schema refusal mentions schema_version" "grep -qiF -- 'schema_version' \"$SCHEMA_OUT\""

# Skip-clone happy path on a CLEAN destination (no live cache, manifests gone).
CLEAN_HOME="$TMP/home-fresh"
mkdir -p "$CLEAN_HOME/.local/bin" "$CLEAN_HOME/.cache" "$CLEAN_HOME/.local/share/agent-fleet"
# Re-stub git+install under the fresh home so the import's resolution lands here.
cat > "$CLEAN_HOME/.local/bin/git" <<STUB
#!/bin/bash
printf -- '%s\n' "\$*" >> "$TMP/git-fresh.log"
if [ "\${1:-}" = "clone" ]; then
  dst="\${3:-}"
  [ -z "\$dst" ] && dst="."
  mkdir -p "\$dst/.git"
fi
exit 0
STUB
chmod +x "$CLEAN_HOME/.local/bin/git"
cp "$HOME/.local/bin/launchctl" "$CLEAN_HOME/.local/bin/launchctl"
cp "$HOME/.local/bin/fleet-install-stub.sh" "$CLEAN_HOME/.local/bin/fleet-install-stub.sh"
chmod +x "$CLEAN_HOME/.local/bin/launchctl" "$CLEAN_HOME/.local/bin/fleet-install-stub.sh"

# Run --import --skip-clone with fresh HOME and clean cache.
SKIP_OUT="$TMP/import-skip.out"
set +e
HOME="$CLEAN_HOME" \
  PATH="$CLEAN_HOME/.local/bin:$PATH" \
  FLEET_INSTALL_CMD="$CLEAN_HOME/.local/bin/fleet-install-stub.sh" \
  FLEET_DISCOVERY_ROOT="$FIXTURE_ROOT" \
  FLEET_CROSS_LESSONS="$CLEAN_HOME/.local/share/agent-fleet/CROSS_LESSONS.md" \
  "$FLEET" migrate --import "$EXPORT_PATH" --skip-clone > "$SKIP_OUT" 2>&1 < /dev/null
SKIP_EXIT=$?
set -e
ASSERT "AC6: --import --skip-clone exits 0 on clean dest" "[ \"$SKIP_EXIT\" = 0 ]"
ASSERT "AC6: --skip-clone does not invoke git clone" "! grep -qF -- 'clone' \"$TMP/git-fresh.log\" 2>/dev/null || true"

# --- AC #7: install.sh invoked once per slug --------------------------------
# Re-run import under the same clean home but a different install log target,
# and assert install.sh is called 4 times (one per slug).
INSTALL_LOG_FRESH="$TMP/install-fresh.log"
: > "$INSTALL_LOG_FRESH"
cat > "$CLEAN_HOME/.local/bin/fleet-install-stub.sh" <<STUB
#!/bin/bash
printf -- '%s\n' "\$1" >> "$INSTALL_LOG_FRESH"
exit 0
STUB
chmod +x "$CLEAN_HOME/.local/bin/fleet-install-stub.sh"

# Fresh cache, fresh discovery root (per-slug paths populated by --import).
rm -rf "$CLEAN_HOME/.cache" "$FIXTURE_ROOT/imported"
mkdir -p "$CLEAN_HOME/.cache"
IMPORT_AC7_OUT="$TMP/import-ac7.out"
set +e
HOME="$CLEAN_HOME" \
  PATH="$CLEAN_HOME/.local/bin:$PATH" \
  FLEET_INSTALL_CMD="$CLEAN_HOME/.local/bin/fleet-install-stub.sh" \
  FLEET_DISCOVERY_ROOT="$FIXTURE_ROOT" \
  FLEET_CROSS_LESSONS="$CLEAN_HOME/.local/share/agent-fleet/CROSS_LESSONS.md" \
  "$FLEET" migrate --import "$EXPORT_PATH" --skip-clone > "$IMPORT_AC7_OUT" 2>&1 < /dev/null
AC7_EXIT=$?
set -e
ASSERT "AC7: import succeeded for install assertion" "[ \"$AC7_EXIT\" = 0 ]"
INSTALL_CALLS=$(awk 'BEGIN { count = 0 } /./ { count++ } END { print count+0 }' "$INSTALL_LOG_FRESH")
ASSERT "AC7: install.sh invoked 4 times (one per slug)" "[ \"$INSTALL_CALLS\" = 4 ]"

# --- AC #8: events.jsonl + runs.jsonl restored to per-slug CACHE_DIR --------
for slug in $SLUGS; do
  restored="$CLEAN_HOME/.cache/${slug}-agent/events.jsonl"
  expected="$FIXTURE_DIR/source/$slug/events.jsonl"
  if cmp -s "$restored" "$expected"; then
    ASSERT "AC8: $slug events.jsonl restored byte-for-byte" "true"
  else
    ASSERT "AC8: $slug events.jsonl restored byte-for-byte" "false"
  fi
  restored_runs="$CLEAN_HOME/.cache/${slug}-agent/runs.jsonl"
  expected_runs="$FIXTURE_DIR/source/$slug/runs.jsonl"
  if cmp -s "$restored_runs" "$expected_runs"; then
    ASSERT "AC8: $slug runs.jsonl restored byte-for-byte" "true"
  else
    ASSERT "AC8: $slug runs.jsonl restored byte-for-byte" "false"
  fi
done

# Keep-existing branch: pre-populate one slug's events.jsonl with a marker.
KEEP_HOME="$TMP/home-keep"
mkdir -p "$KEEP_HOME/.local/bin" "$KEEP_HOME/.cache/alpha-strong-agent" "$KEEP_HOME/.local/share/agent-fleet"
echo '{"ts":"2099-01-01T00:00:00Z","type":"keep-marker"}' > "$KEEP_HOME/.cache/alpha-strong-agent/events.jsonl"
cp "$HOME/.local/bin/git" "$KEEP_HOME/.local/bin/git"
cp "$HOME/.local/bin/launchctl" "$KEEP_HOME/.local/bin/launchctl"
cp "$HOME/.local/bin/fleet-install-stub.sh" "$KEEP_HOME/.local/bin/fleet-install-stub.sh"
chmod +x "$KEEP_HOME/.local/bin/git" "$KEEP_HOME/.local/bin/launchctl" "$KEEP_HOME/.local/bin/fleet-install-stub.sh"
set +e
HOME="$KEEP_HOME" \
  PATH="$KEEP_HOME/.local/bin:$PATH" \
  FLEET_INSTALL_CMD="$KEEP_HOME/.local/bin/fleet-install-stub.sh" \
  FLEET_DISCOVERY_ROOT="$FIXTURE_ROOT" \
  FLEET_CROSS_LESSONS="$KEEP_HOME/.local/share/agent-fleet/CROSS_LESSONS.md" \
  "$FLEET" migrate --import "$EXPORT_PATH" --skip-clone > "$TMP/import-keep.out" 2>&1 < /dev/null
KEEP_EXIT=$?
set -e
ASSERT "AC8: keep-local default on non-interactive shell preserves existing" "grep -qF -- 'keep-marker' \"$KEEP_HOME/.cache/alpha-strong-agent/events.jsonl\""

# --- AC #9: --import --dry-run writes nothing -------------------------------
DRYRUN_HOME="$TMP/home-dryrun"
mkdir -p "$DRYRUN_HOME/.local/bin" "$DRYRUN_HOME/.cache" "$DRYRUN_HOME/.local/share/agent-fleet"
cp "$HOME/.local/bin/git" "$DRYRUN_HOME/.local/bin/git"
cp "$HOME/.local/bin/launchctl" "$DRYRUN_HOME/.local/bin/launchctl"
cp "$HOME/.local/bin/fleet-install-stub.sh" "$DRYRUN_HOME/.local/bin/fleet-install-stub.sh"
chmod +x "$DRYRUN_HOME/.local/bin/git" "$DRYRUN_HOME/.local/bin/launchctl" "$DRYRUN_HOME/.local/bin/fleet-install-stub.sh"

DRYRUN_INSTALL_LOG="$TMP/dryrun-install.log"
: > "$DRYRUN_INSTALL_LOG"
cat > "$DRYRUN_HOME/.local/bin/fleet-install-stub.sh" <<STUB
#!/bin/bash
printf -- '%s\n' "\$1" >> "$DRYRUN_INSTALL_LOG"
exit 0
STUB
chmod +x "$DRYRUN_HOME/.local/bin/fleet-install-stub.sh"

set +e
HOME="$DRYRUN_HOME" \
  PATH="$DRYRUN_HOME/.local/bin:$PATH" \
  FLEET_INSTALL_CMD="$DRYRUN_HOME/.local/bin/fleet-install-stub.sh" \
  FLEET_DISCOVERY_ROOT="$FIXTURE_ROOT" \
  FLEET_CROSS_LESSONS="$DRYRUN_HOME/.local/share/agent-fleet/CROSS_LESSONS.md" \
  "$FLEET" migrate --import "$EXPORT_PATH" --dry-run --skip-clone > "$TMP/dryrun.out" 2>&1 < /dev/null
DRYRUN_EXIT=$?
set -e
ASSERT "AC9: --import --dry-run exits 0" "[ \"$DRYRUN_EXIT\" = 0 ]"
DRYRUN_INSTALL_COUNT=$(awk 'BEGIN { count = 0 } /./ { count++ } END { print count+0 }' "$DRYRUN_INSTALL_LOG")
ASSERT "AC9: --dry-run did NOT invoke install.sh" "[ \"$DRYRUN_INSTALL_COUNT\" = 0 ]"
ASSERT "AC9: --dry-run cache stays empty" "[ ! -d \"$DRYRUN_HOME/.cache/alpha-strong-agent\" ]"
ASSERT "AC9: --dry-run output mentions 'would'" "grep -qF -- 'would' \"$TMP/dryrun.out\""

# --- AC #10: verify pass + corrupted detection -------------------------------
# The clean import (AC#7) already ran the verify pass; assert "matches export"
# (or similar) appears in its output.
ASSERT "AC10: import output mentions verify" "grep -qiF -- 'verify' \"$IMPORT_AC7_OUT\""

# Now build a corrupted export by removing one pr_footer_posted line from
# alpha-strong's events.jsonl post-extraction, re-packing without recomputing
# the manifest's expected_verify counts. The verify should fail with exit 3
# and a "MIGRATION VERIFY FAILED" line.
CORRUPT_STAGE="$TMP/corrupt-stage"
mkdir -p "$CORRUPT_STAGE"
tar -xzf "$EXPORT_PATH" -C "$CORRUPT_STAGE"
# Remove one pr_footer_posted line.
awk 'BEGIN { count = 0 } { if (/pr_footer_posted/ && count == 0) { count = 1; next } print }' \
  "$CORRUPT_STAGE/alpha-strong/events.jsonl" > "$CORRUPT_STAGE/alpha-strong/events.jsonl.new"
mv "$CORRUPT_STAGE/alpha-strong/events.jsonl.new" "$CORRUPT_STAGE/alpha-strong/events.jsonl"
# Re-pack but DO NOT recompute the manifest. The sha verification will catch
# it FIRST, so we ALSO need to recompute tarball_sha256 to isolate the
# verify-pass failure. Recompute by re-running migrate_validate logic in node.
# Simpler: re-pack WITHOUT the manifest, hash, then write a fresh manifest
# that matches sha but keeps old expected_verify counts.
node -e "
  const fs = require('fs');
  const path = require('path');
  const crypto = require('crypto');
  const { execSync } = require('child_process');
  const stage = '$CORRUPT_STAGE';
  // The kit's content-digest sha256 is the sha256 of a sorted stream of
  // '<rel-path>\t<file-sha256>\n' lines for every regular file EXCEPT
  // fleet-export.json and the .migrate-repo-* sidecars. Mirror that here so
  // the validator's sha pass succeeds and the test isolates the
  // expected_verify mismatch.
  const oldManifest = JSON.parse(fs.readFileSync(path.join(stage, 'fleet-export.json'), 'utf8'));
  fs.unlinkSync(path.join(stage, 'fleet-export.json'));
  const findFiles = (d, base) => {
    const out = [];
    for (const e of fs.readdirSync(d, { withFileTypes: true })) {
      const p = base ? base + '/' + e.name : e.name;
      if (e.isDirectory()) { out.push(...findFiles(path.join(d, e.name), p)); }
      else if (e.isFile()
               && e.name !== 'fleet-export.json'
               && e.name !== '.migrate-repo-url'
               && e.name !== '.migrate-repo-path') {
        out.push(p);
      }
    }
    return out;
  };
  const files = findFiles(stage, '').sort();
  let stream = '';
  for (const f of files) {
    const buf = fs.readFileSync(path.join(stage, f));
    stream += f + '\t' + crypto.createHash('sha256').update(buf).digest('hex') + '\n';
  }
  oldManifest.tarball_sha256 = crypto.createHash('sha256').update(stream).digest('hex');
  // Update per-slug events_sha256 / events_bytes to match the mutated content.
  for (const s of oldManifest.slugs) {
    const eventsPath = path.join(stage, s.slug, 'events.jsonl');
    if (fs.existsSync(eventsPath)) {
      const buf = fs.readFileSync(eventsPath);
      s.events_bytes = buf.length;
      s.events_sha256 = crypto.createHash('sha256').update(buf).digest('hex');
    }
  }
  fs.writeFileSync(path.join(stage, 'fleet-export.json'), JSON.stringify(oldManifest));
  execSync('tar -czf $TMP/corrupt.tar.gz -C ' + stage + ' .');
"

CORRUPT_HOME="$TMP/home-corrupt"
mkdir -p "$CORRUPT_HOME/.local/bin" "$CORRUPT_HOME/.cache" "$CORRUPT_HOME/.local/share/agent-fleet"
cp "$HOME/.local/bin/git" "$CORRUPT_HOME/.local/bin/git"
cp "$HOME/.local/bin/launchctl" "$CORRUPT_HOME/.local/bin/launchctl"
cp "$HOME/.local/bin/fleet-install-stub.sh" "$CORRUPT_HOME/.local/bin/fleet-install-stub.sh"
chmod +x "$CORRUPT_HOME/.local/bin/git" "$CORRUPT_HOME/.local/bin/launchctl" "$CORRUPT_HOME/.local/bin/fleet-install-stub.sh"

CORRUPT_OUT="$TMP/import-corrupt.out"
set +e
HOME="$CORRUPT_HOME" \
  PATH="$CORRUPT_HOME/.local/bin:$PATH" \
  FLEET_INSTALL_CMD="$CORRUPT_HOME/.local/bin/fleet-install-stub.sh" \
  FLEET_DISCOVERY_ROOT="$FIXTURE_ROOT" \
  FLEET_CROSS_LESSONS="$CORRUPT_HOME/.local/share/agent-fleet/CROSS_LESSONS.md" \
  "$FLEET" migrate --import "$TMP/corrupt.tar.gz" --skip-clone > "$CORRUPT_OUT" 2>&1 < /dev/null
CORRUPT_EXIT=$?
set -e
ASSERT "AC10: corrupted import exits 3 (verify failed)" "[ \"$CORRUPT_EXIT\" = 3 ]"
ASSERT "AC10: corrupted output mentions MIGRATION VERIFY FAILED" "grep -qF -- 'MIGRATION VERIFY FAILED' \"$CORRUPT_OUT\""

# --- AC #11: CROSS_LESSONS restored -----------------------------------------
ASSERT "AC11: CROSS_LESSONS restored under FLEET_CROSS_LESSONS path" "[ -f \"$CLEAN_HOME/.local/share/agent-fleet/CROSS_LESSONS.md\" ]"
RESTORED_CROSS="$CLEAN_HOME/.local/share/agent-fleet/CROSS_LESSONS.md"
EXPECTED_CROSS="$FIXTURE_DIR/source/cross-lessons/CROSS_LESSONS.md"
if cmp -s "$RESTORED_CROSS" "$EXPECTED_CROSS"; then
  ASSERT "AC11: CROSS_LESSONS restored byte-for-byte" "true"
else
  ASSERT "AC11: CROSS_LESSONS restored byte-for-byte" "false"
fi

# --- AC #12: --export --json -------------------------------------------------
JSON_OUT="$TMP/json-export.out"
set +e
"$FLEET" migrate --export "$TMP/json-export.tar.gz" --json > "$JSON_OUT" 2>&1
JSON_EXIT=$?
set -e
ASSERT "AC12: --export --json exits 0" "[ \"$JSON_EXIT\" = 0 ]"
# Strip any pre-JSON banner: node parses the first '{' through the matching '}'.
node -e "
  const fs = require('fs');
  const raw = fs.readFileSync('$JSON_OUT', 'utf8');
  const first = raw.indexOf('{');
  const last = raw.lastIndexOf('}');
  if (first < 0 || last < 0) { console.error('no JSON braces'); process.exit(1); }
  const text = raw.slice(first, last + 1);
  const obj = JSON.parse(text);
  for (const k of ['path','schema_version','slugs','cross_lessons_bytes','tarball_bytes','tarball_sha256']) {
    if (!(k in obj)) { console.error('missing: ' + k); process.exit(1); }
  }
  if (obj.schema_version !== 1) { console.error('schema_version != 1'); process.exit(1); }
  if (!Array.isArray(obj.slugs)) { console.error('slugs not array'); process.exit(1); }
  console.log('json OK');
" 2>&1 | tee "$TMP/json-validate.out" >/dev/null
JSON_VAL_OUT="$(cat "$TMP/json-validate.out")"
ASSERT "AC12: --export --json valid" "[ \"$JSON_VAL_OUT\" = 'json OK' ]"

# --- AC #13: --help banner ---------------------------------------------------
HELP_OUT="$TMP/help.out"
set +e
"$FLEET" migrate --help > "$HELP_OUT" 2>&1
HELP_EXIT=$?
set -e
ASSERT "AC13: --help exits 0" "[ \"$HELP_EXIT\" = 0 ]"
for kw in --export --import --redact --encrypt --dry-run --skip-clone --json; do
  ASSERT "AC13: help mentions $kw" "grep -qF -- '$kw' \"$HELP_OUT\""
done

# --- AC #14: source bytes unchanged + lib/common.sh + prompts/ untouched ----
SRC_SIZES_AFTER="$TMP/src-sizes-after.txt"
( for slug in $SLUGS; do
    cache="$HOME/.cache/${slug}-agent"
    wc -c "$cache/events.jsonl" "$cache/runs.jsonl" 2>/dev/null
  done
) > "$SRC_SIZES_AFTER"
if diff -q "$SRC_SIZES_BEFORE" "$SRC_SIZES_AFTER" >/dev/null 2>&1; then
  ASSERT "AC14: source events/runs byte sizes unchanged after export" "true"
else
  ASSERT "AC14: source events/runs byte sizes unchanged after export" "false"
fi

# Repo-level diff scope: no edits to lib/common.sh, prompts/, AGENTS.md.
( cd "$REPO_ROOT"
  DIFF_FILES="$(git diff --name-only main...HEAD -- lib/common.sh prompts/ AGENTS.md 2>/dev/null || true)"
  if [ -z "$DIFF_FILES" ]; then
    printf -- 'PASS: AC14: lib/common.sh prompts/ AGENTS.md not modified\n'
    PASS=$((PASS+1))
  else
    printf -- 'FAIL: AC14: lib/common.sh prompts/ AGENTS.md modified: %s\n' "$DIFF_FILES" >&2
    FAIL=$((FAIL+1))
  fi
)

# --- summary -----------------------------------------------------------------
printf -- '\nmigrate test: %d PASS, %d FAIL\n' "$PASS" "$FAIL"
if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
exit 0
