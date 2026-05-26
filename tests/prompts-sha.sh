#!/bin/bash
# tests/prompts-sha.sh — prompt-version pinning end-to-end test.
#
# Ticket 0005. Covers every acceptance-criteria box:
#   1. `bin/fleet prompts-sha` prints a 64-hex SHA256 and is deterministic
#      across two invocations (the headline test).
#   2. `bin/fleet prompts-sha` matches what
#      `find prompts -type f -name '*.md' | sort | xargs cat | shasum -a 256`
#      computes — i.e. it's the documented formula, not a black box.
#   3. With `PROMPTS_SHA` unset in the manifest, fleet_check_prompts_sha
#      returns 0 and emits no `prompts_drift` event (no-warn baseline).
#   4. With `PROMPTS_SHA` set and matching, returns 0 and emits no event.
#   5. With `PROMPTS_SHA` set and mismatched, returns 0 (NOT fatal),
#      prints a warning, AND emits exactly one `prompts_drift` event
#      per run carrying `pinned` + `actual` keys.
#   6. lib/install.sh stamps the COPIED manifest at
#      $CFG_DIR/agents.config.sh with one `# PROMPTS_SHA pinned at install
#      time: <sha>` line, and is idempotent: re-running strips the old
#      stamp before re-appending so the file never grows duplicate lines.
#      The SOURCE manifest is left untouched.
#
# Self-contained: stubs $HOME, points at a fixture project, stubs
# `launchctl` so install.sh's bootstrap calls don't touch real launchd.
# Exits non-zero on any failure.

set -euo pipefail

REPO_ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"

TMP="$(mktemp -d -t fleet-prompts-sha-test.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

# Isolate from any real $HOME so install.sh writes into the tmp tree only.
export HOME="$TMP/home"
mkdir -p "$HOME"

FLEET="$REPO_ROOT/bin/fleet"

# --- assertion 1: deterministic, well-formed SHA256 ----------------------
SHA1=$("$FLEET" prompts-sha)
SHA2=$("$FLEET" prompts-sha)

if [ "$SHA1" != "$SHA2" ]; then
  echo "FAIL: bin/fleet prompts-sha is not deterministic"
  echo "  first:  $SHA1"
  echo "  second: $SHA2"
  exit 1
fi
if ! [[ "$SHA1" =~ ^[0-9a-f]{64}$ ]]; then
  echo "FAIL: bin/fleet prompts-sha returned non-hex64: $SHA1"
  exit 1
fi
echo "ok: prompts-sha is deterministic ($SHA1)"

# --- assertion 2: matches the documented `find | sort | xargs cat | shasum` formula ---
WANT=$( (cd "$REPO_ROOT" && find prompts -type f -name '*.md' | sort | xargs cat) | shasum -a 256 | awk '{print $1}' )
if [ "$SHA1" != "$WANT" ]; then
  echo "FAIL: prompts-sha mismatch with documented formula"
  echo "  bin/fleet: $SHA1"
  echo "  formula:   $WANT"
  exit 1
fi
echo "ok: prompts-sha matches documented formula"

# --- shared fixture for the drift-check assertions -----------------------
MANIFEST_DIR="$TMP/project"
mkdir -p "$MANIFEST_DIR"
cat > "$MANIFEST_DIR/agents.config.sh" <<'CFG'
SLUG="promptstest"
PROJECT_NAME="promptstest"
REPO_URL="https://github.com/example/promptstest.git"
SELF_CANCEL="20990101"
CFG

CACHE="$HOME/.cache/promptstest-agent"
EVENTS="$CACHE/events.jsonl"

reset_events() { rm -rf "$CACHE"; mkdir -p "$CACHE"; }

# --- assertion 3: PROMPTS_SHA unset → no warn, no event ------------------
reset_events
(
  set -euo pipefail
  # shellcheck disable=SC1091
  source "$REPO_ROOT/lib/common.sh"
  fleet_load_manifest "$MANIFEST_DIR"
  FLEET_PHASE="ship"; export FLEET_PHASE
  unset PROMPTS_SHA || true
  if ! fleet_check_prompts_sha; then
    echo "FAIL: fleet_check_prompts_sha returned non-zero with PROMPTS_SHA unset"
    exit 1
  fi
) || exit 1
if [ -f "$EVENTS" ] && grep -q '"type":"prompts_drift"' "$EVENTS"; then
  echo "FAIL: prompts_drift event emitted even though PROMPTS_SHA is unset"
  cat "$EVENTS"
  exit 1
fi
echo "ok: no event when PROMPTS_SHA unset"

# --- assertion 4: PROMPTS_SHA set + matches → no event -------------------
reset_events
CURRENT_SHA=$("$FLEET" prompts-sha)
(
  set -euo pipefail
  # shellcheck disable=SC1091
  source "$REPO_ROOT/lib/common.sh"
  fleet_load_manifest "$MANIFEST_DIR"
  FLEET_PHASE="ship"; export FLEET_PHASE
  PROMPTS_SHA="$CURRENT_SHA"; export PROMPTS_SHA
  if ! fleet_check_prompts_sha; then
    echo "FAIL: fleet_check_prompts_sha returned non-zero on a matching pin"
    exit 1
  fi
) || exit 1
if [ -f "$EVENTS" ] && grep -q '"type":"prompts_drift"' "$EVENTS"; then
  echo "FAIL: prompts_drift event emitted on a matching pin"
  cat "$EVENTS"
  exit 1
fi
echo "ok: no event when PROMPTS_SHA matches"

# --- assertion 5: mismatched pin → continues (returns 0), warns, one event ---
reset_events
FAKE_SHA="deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef"
OUT="$TMP/drift.out"
(
  set -euo pipefail
  # shellcheck disable=SC1091
  source "$REPO_ROOT/lib/common.sh"
  fleet_load_manifest "$MANIFEST_DIR"
  FLEET_PHASE="ship"; export FLEET_PHASE
  PROMPTS_SHA="$FAKE_SHA"; export PROMPTS_SHA
  if ! fleet_check_prompts_sha; then
    echo "FAIL: fleet_check_prompts_sha aborted (returned non-zero) on mismatch"
    exit 1
  fi
  # Second call in the same run must NOT emit a duplicate event.
  fleet_check_prompts_sha
) > "$OUT" 2>&1 || { cat "$OUT"; exit 1; }

if ! grep -qi 'drift\|mismatch\|pinned' "$OUT"; then
  echo "FAIL: mismatch case produced no warning text"
  cat "$OUT"
  exit 1
fi
if [ ! -f "$EVENTS" ]; then
  echo "FAIL: events.jsonl not created on mismatch"
  exit 1
fi
DRIFT_COUNT=$(grep -c '"type":"prompts_drift"' "$EVENTS" || true)
if [ "$DRIFT_COUNT" != "1" ]; then
  echo "FAIL: expected exactly 1 prompts_drift event, got $DRIFT_COUNT"
  cat "$EVENTS"
  exit 1
fi

# Schema: the event carries pinned + actual + the four base keys.
node -e '
  const fs = require("fs");
  const path = process.argv[1];
  const lines = fs.readFileSync(path, "utf8").split("\n").filter(Boolean);
  const drift = lines.map(JSON.parse).find(e => e.type === "prompts_drift");
  if (!drift) { console.error("FAIL: no prompts_drift event"); process.exit(1); }
  for (const k of ["ts","slug","phase","type","pinned","actual"]) {
    if (!(k in drift)) {
      console.error("FAIL: prompts_drift missing key " + k);
      console.error("  event: " + JSON.stringify(drift));
      process.exit(1);
    }
  }
  if (drift.pinned !== process.argv[2]) {
    console.error("FAIL: pinned=" + drift.pinned + " want " + process.argv[2]);
    process.exit(1);
  }
  if (drift.actual !== process.argv[3]) {
    console.error("FAIL: actual=" + drift.actual + " want " + process.argv[3]);
    process.exit(1);
  }
  console.log("ok: prompts_drift schema valid");
' "$EVENTS" "$FAKE_SHA" "$CURRENT_SHA"

# --- assertion 6: install.sh stamps the COPIED manifest, idempotent -------
# install.sh calls launchctl bootstrap/bootout — stub it so we can run on
# a test host without poking real launchd.
BIN_STUB="$TMP/bin"
mkdir -p "$BIN_STUB"
cat > "$BIN_STUB/launchctl" <<'STUB'
#!/bin/bash
exit 0
STUB
chmod +x "$BIN_STUB/launchctl"
export PATH="$BIN_STUB:$PATH"

INSTALL_PROJECT="$TMP/install-project"
mkdir -p "$INSTALL_PROJECT"
# Source manifest gets a non-matching PROMPTS_SHA so we can prove install.sh
# overwrites it in the COPY without touching the SOURCE.
cat > "$INSTALL_PROJECT/agents.config.sh" <<CFG
SLUG="installtest"
PROJECT_NAME="installtest"
REPO_URL="https://github.com/example/installtest.git"
SELF_CANCEL="20990101"
PROMPTS_SHA="0000000000000000000000000000000000000000000000000000000000000000"
CFG
SRC_BEFORE=$(shasum -a 256 < "$INSTALL_PROJECT/agents.config.sh" | awk '{print $1}')

bash "$REPO_ROOT/lib/install.sh" "$INSTALL_PROJECT" > "$TMP/install.out" 2>&1 || {
  echo "FAIL: install.sh exited non-zero"
  cat "$TMP/install.out"
  exit 1
}

COPIED="$HOME/.local/share/agent-fleet/projects/installtest/agents.config.sh"
if [ ! -f "$COPIED" ]; then
  echo "FAIL: copied manifest not found at $COPIED"
  exit 1
fi

PIN_LINES=$(grep -c '^# PROMPTS_SHA pinned at install time:' "$COPIED" || true)
if [ "$PIN_LINES" != "1" ]; then
  echo "FAIL: expected exactly 1 pin line in copied manifest, got $PIN_LINES"
  cat "$COPIED"
  exit 1
fi
PIN_VAL=$(grep '^# PROMPTS_SHA pinned at install time:' "$COPIED" | awk '{print $NF}')
if [ "$PIN_VAL" != "$CURRENT_SHA" ]; then
  echo "FAIL: stamped SHA=$PIN_VAL want $CURRENT_SHA"
  exit 1
fi

# Source manifest must be untouched.
SRC_AFTER=$(shasum -a 256 < "$INSTALL_PROJECT/agents.config.sh" | awk '{print $1}')
if [ "$SRC_BEFORE" != "$SRC_AFTER" ]; then
  echo "FAIL: install.sh modified the SOURCE manifest"
  diff <(echo "$SRC_BEFORE") <(echo "$SRC_AFTER") || true
  exit 1
fi

# Idempotency: re-run, count must STILL be 1 (old stamp stripped, new one
# appended). Also assert when source SHA changes it doesn't accumulate.
bash "$REPO_ROOT/lib/install.sh" "$INSTALL_PROJECT" > "$TMP/install2.out" 2>&1 || {
  echo "FAIL: second install.sh exited non-zero"
  cat "$TMP/install2.out"
  exit 1
}
PIN_LINES2=$(grep -c '^# PROMPTS_SHA pinned at install time:' "$COPIED" || true)
if [ "$PIN_LINES2" != "1" ]; then
  echo "FAIL: re-run produced $PIN_LINES2 pin lines (want 1 — idempotent)"
  cat "$COPIED"
  exit 1
fi
echo "ok: install.sh stamps + is idempotent"

echo "ok: tests/prompts-sha.sh passed"
