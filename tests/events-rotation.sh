#!/bin/bash
# tests/events-rotation.sh — fleet_rotate_events + fleet_emit_event integration.
#
# Ticket 0016. Size-based rotation of $CACHE_DIR/events.jsonl into
# $CACHE_DIR/events.jsonl.archive/<UTC-stamp>.jsonl when the file crosses
# FLEET_EVENTS_MAX_BYTES (default 1 MiB). One assertion block per acceptance-
# criteria checkbox in docs/backlog/0016-events-rotation.md. The fleet doctor
# `events_size` check is covered here too because it shares the same fixture
# layout (a controlled CACHE_DIR with seeded events.jsonl).
#
# Self-contained: stubs $HOME so the test never touches the real ~/.cache
# state. Exits non-zero on any failure.

set -euo pipefail

REPO_ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"

TMP="$(mktemp -d -t fleet-events-rotation-test.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

# Isolate from the real fleet cache + any existing ~/.local/bin stubs. The
# rotated test cases call into fleet_emit_event, which uses CACHE_DIR derived
# from $HOME + $SLUG.
export HOME="$TMP/home"
mkdir -p "$HOME"

# Minimal manifest used by every block. SLUG drives the CACHE_DIR.
MANIFEST_DIR="$TMP/project"
mkdir -p "$MANIFEST_DIR"
cat > "$MANIFEST_DIR/agents.config.sh" <<'CFG'
SLUG="rotatest"
PROJECT_NAME="rotatest"
REPO_URL="https://github.com/example/rotatest.git"
SELF_CANCEL="20990101"
CFG

CACHE_DIR="$HOME/.cache/rotatest-agent"
EVENTS_FILE="$CACHE_DIR/events.jsonl"
ARCHIVE_DIR="$CACHE_DIR/events.jsonl.archive"

# Reset cache between blocks. Lets every AC start from a clean state without
# leaking the previous block's archive directory or guard-variable.
reset_cache() {
  rm -rf "$CACHE_DIR"
  mkdir -p "$CACHE_DIR"
}

# Run a subshell that sources common.sh, loads the manifest, sets the phase,
# then runs whatever the caller passed as positional args via `eval`. Each
# block invokes `run_lib '<commands>'`. We deliberately spawn a new subshell
# per block so the FLEET_EVENTS_ROTATE_CHECKED guard from one block does NOT
# bleed into the next (matches the "at most once per process" contract).
run_lib() {
  (
    set -euo pipefail
    # shellcheck disable=SC1091
    source "$REPO_ROOT/lib/common.sh"
    fleet_load_manifest "$MANIFEST_DIR"
    FLEET_PHASE="ship"
    export FLEET_PHASE
    eval "$1"
  )
}

# ========================================================================
# AC #1 — `fleet_rotate_events` is exposed by lib/common.sh and is a no-op
#         when events.jsonl does not exist OR is smaller than
#         ${FLEET_EVENTS_MAX_BYTES:-1048576}. The no-op returns 0 silently.
# ========================================================================
reset_cache

run_lib '
  # Sanity: function exists in the loaded shell.
  if ! declare -F fleet_rotate_events >/dev/null; then
    echo "FAIL: AC#1 fleet_rotate_events is not declared by lib/common.sh"
    exit 1
  fi

  # File does not exist -> no-op, returns 0, no archive dir created.
  rm -f "$CACHE_DIR/events.jsonl"
  rm -rf "$CACHE_DIR/events.jsonl.archive"
  if ! fleet_rotate_events; then
    echo "FAIL: AC#1 fleet_rotate_events returned non-zero with missing events.jsonl"
    exit 1
  fi
  if [ -d "$CACHE_DIR/events.jsonl.archive" ]; then
    echo "FAIL: AC#1 archive dir created when no events.jsonl exists"
    exit 1
  fi

  # File under threshold -> no-op, returns 0, no archive.
  printf "small\n" > "$CACHE_DIR/events.jsonl"
  if ! fleet_rotate_events; then
    echo "FAIL: AC#1 fleet_rotate_events returned non-zero with under-threshold file"
    exit 1
  fi
  if [ -d "$CACHE_DIR/events.jsonl.archive" ]; then
    echo "FAIL: AC#1 archive dir created when events.jsonl is under threshold"
    exit 1
  fi
'
echo "ok: AC#1 fleet_rotate_events exposed; no-op under threshold"

# ========================================================================
# AC #2 — When the file is at/above the threshold, fleet_rotate_events moves
#         it to $CACHE_DIR/events.jsonl.archive/<YYYYMMDD>-<HHMMSS>.jsonl
#         (UTC), creates an empty new events.jsonl, and the NEW file's first
#         line is an `events_rotated archived=<path> bytes=<n>` event.
# ========================================================================
reset_cache

# Seed an events.jsonl that is exactly 1 MiB + 1 byte. Past the 1 MiB default.
TARGET_BYTES=$((1048576 + 1))
# `dd` from /dev/zero is portable across BSD + GNU. Truncate via head -c is
# also portable and avoids the BSD/GNU dd "1048577" arg-style differences.
head -c "$TARGET_BYTES" /dev/zero > "$EVENTS_FILE"
SEED_BYTES="$(wc -c < "$EVENTS_FILE" | tr -d ' ')"
if [ "$SEED_BYTES" != "$TARGET_BYTES" ]; then
  echo "FAIL: AC#2 setup — seeded events.jsonl=$SEED_BYTES bytes, want $TARGET_BYTES"
  exit 1
fi

# Override the threshold for this test so we can also smoke-check a smaller
# trigger size, but for THIS block we keep the default 1 MiB (1048576) and
# the seeded file is 1 byte over.
run_lib '
  fleet_rotate_events
  rc=$?
  if [ "$rc" != "0" ]; then
    echo "FAIL: AC#2 fleet_rotate_events returned $rc"
    exit 1
  fi
'

# Archive must exist with exactly one file matching YYYYMMDD-HHMMSS.jsonl.
if [ ! -d "$ARCHIVE_DIR" ]; then
  echo "FAIL: AC#2 archive dir not created at $ARCHIVE_DIR"
  exit 1
fi
ARCHIVE_FILES=("$ARCHIVE_DIR"/*.jsonl)
if [ ! -f "${ARCHIVE_FILES[0]}" ] || [ "${#ARCHIVE_FILES[@]}" != "1" ]; then
  echo "FAIL: AC#2 archive dir does not contain exactly one .jsonl file"
  ls -la "$ARCHIVE_DIR" || true
  exit 1
fi
ARCHIVE_NAME="$(basename "${ARCHIVE_FILES[0]}")"
if ! echo "$ARCHIVE_NAME" | grep -qE '^[0-9]{8}-[0-9]{6}\.jsonl$'; then
  echo "FAIL: AC#2 archive filename $ARCHIVE_NAME does not match YYYYMMDD-HHMMSS.jsonl"
  exit 1
fi

# Archived file must equal the original bytes; new events.jsonl must exist
# and contain exactly ONE line: the events_rotated marker.
ARCHIVED_BYTES="$(wc -c < "${ARCHIVE_FILES[0]}" | tr -d ' ')"
if [ "$ARCHIVED_BYTES" != "$TARGET_BYTES" ]; then
  echo "FAIL: AC#2 archived file size=$ARCHIVED_BYTES want $TARGET_BYTES"
  exit 1
fi
if [ ! -f "$EVENTS_FILE" ]; then
  echo "FAIL: AC#2 new events.jsonl was not created after rotation"
  exit 1
fi
NEW_LINES="$(wc -l < "$EVENTS_FILE" | tr -d ' ')"
if [ "$NEW_LINES" != "1" ]; then
  echo "FAIL: AC#2 new events.jsonl should have exactly 1 line (events_rotated marker), got $NEW_LINES"
  cat "$EVENTS_FILE"
  exit 1
fi
node -e '
  const fs = require("fs");
  const line = fs.readFileSync(process.argv[1], "utf8").trim().split("\n")[0];
  const ev = JSON.parse(line);
  if (ev.type !== "events_rotated") {
    console.error("FAIL: AC#2 first line type=" + ev.type + " (want events_rotated)");
    process.exit(1);
  }
  if (!ev.archived || !ev.archived.endsWith(".jsonl")) {
    console.error("FAIL: AC#2 events_rotated.archived missing/wrong: " + JSON.stringify(ev));
    process.exit(1);
  }
  if (!ev.bytes || Number(ev.bytes) !== '"$TARGET_BYTES"') {
    console.error("FAIL: AC#2 events_rotated.bytes=" + ev.bytes + " (want '"$TARGET_BYTES"')");
    process.exit(1);
  }
' "$EVENTS_FILE"
echo "ok: AC#2 rotation moves file + writes events_rotated marker"

# ========================================================================
# AC #3 — fleet_emit_event calls fleet_rotate_events BEFORE its own append,
#         at most once per process (guarded by FLEET_EVENTS_ROTATE_CHECKED).
#         Test seeds 1 MiB + 1 byte; calling fleet_emit_event must rotate
#         AND append the just-emitted event, so the new file has exactly
#         two lines (events_rotated marker, then the caller's event).
# ========================================================================
reset_cache

head -c "$TARGET_BYTES" /dev/zero > "$EVENTS_FILE"

run_lib '
  fleet_emit_event run_started pid=12345
  if [ -z "${FLEET_EVENTS_ROTATE_CHECKED:-}" ]; then
    echo "FAIL: AC#3 fleet_emit_event did not set FLEET_EVENTS_ROTATE_CHECKED"
    exit 1
  fi
  # Second emit in the same process MUST NOT re-rotate (guard is set).
  # Seed the file back to >threshold so a re-check WOULD rotate again if
  # the guard were missing. With the guard in place we expect the appended
  # event to land in the same (new) events.jsonl, not in a fresh archive.
  head -c '"$TARGET_BYTES"' /dev/zero >> "$CACHE_DIR/events.jsonl"
  fleet_emit_event run_completed exit=0 duration_ms=1
'

if [ ! -d "$ARCHIVE_DIR" ]; then
  echo "FAIL: AC#3 archive dir was not created during emit-triggered rotation"
  exit 1
fi
ARCHIVE_FILES=("$ARCHIVE_DIR"/*.jsonl)
if [ "${#ARCHIVE_FILES[@]}" != "1" ]; then
  echo "FAIL: AC#3 expected ONE archive file (guard prevents 2nd rotation), got ${#ARCHIVE_FILES[@]}"
  ls -la "$ARCHIVE_DIR" || true
  exit 1
fi

# events.jsonl must include: events_rotated marker, run_started, then the
# padding bytes from the second seed, then run_completed. The two JSON lines
# we care about MUST be there.
if ! grep -q '"type":"events_rotated"' "$EVENTS_FILE"; then
  echo "FAIL: AC#3 new events.jsonl missing events_rotated marker line"
  exit 1
fi
if ! grep -q '"type":"run_started"' "$EVENTS_FILE"; then
  echo "FAIL: AC#3 new events.jsonl missing the just-emitted run_started"
  exit 1
fi
if ! grep -q '"type":"run_completed"' "$EVENTS_FILE"; then
  echo "FAIL: AC#3 new events.jsonl missing the second-emit run_completed"
  exit 1
fi
echo "ok: AC#3 fleet_emit_event triggers rotation once-per-process"

# ========================================================================
# AC #4 — Under-threshold events.jsonl: fleet_emit_event appends without
#         rotating; no archive directory is created.
# ========================================================================
reset_cache

# Tiny seed, well under 1 MiB.
echo '{"ts":"2026-01-01T00:00:00Z","slug":"rotatest","phase":"ship","type":"seed"}' > "$EVENTS_FILE"
BEFORE_LINES="$(wc -l < "$EVENTS_FILE" | tr -d ' ')"

run_lib '
  fleet_emit_event run_started pid=99
'

if [ -d "$ARCHIVE_DIR" ]; then
  echo "FAIL: AC#4 archive dir created on under-threshold append"
  ls -la "$ARCHIVE_DIR" || true
  exit 1
fi
AFTER_LINES="$(wc -l < "$EVENTS_FILE" | tr -d ' ')"
if [ "$AFTER_LINES" != "$((BEFORE_LINES + 1))" ]; then
  echo "FAIL: AC#4 expected +1 line on append, got before=$BEFORE_LINES after=$AFTER_LINES"
  exit 1
fi
echo "ok: AC#4 under-threshold append does not rotate"

# ========================================================================
# AC #5 — Tunable threshold: FLEET_EVENTS_MAX_BYTES env-override rotates at
#         a lower size. Seeds a 200-byte file with the threshold at 100 and
#         asserts rotation fired.
# ========================================================================
reset_cache

head -c 200 /dev/zero > "$EVENTS_FILE"

run_lib '
  FLEET_EVENTS_MAX_BYTES=100
  export FLEET_EVENTS_MAX_BYTES
  fleet_rotate_events
'
if [ ! -d "$ARCHIVE_DIR" ]; then
  echo "FAIL: AC#5 FLEET_EVENTS_MAX_BYTES override did not trigger rotation"
  exit 1
fi
ARCHIVE_FILES=("$ARCHIVE_DIR"/*.jsonl)
if [ "${#ARCHIVE_FILES[@]}" != "1" ]; then
  echo "FAIL: AC#5 expected one archive file with custom threshold"
  exit 1
fi
echo "ok: AC#5 FLEET_EVENTS_MAX_BYTES override works"

# ========================================================================
# AC #6 — `bin/fleet doctor` reports an events_size check per project:
#         PASS when under the threshold (no rotation needed); FAIL on a
#         malformed events.jsonl line (one that does not parse as JSON).
#         Best-effort: a missing events.jsonl is PASS (nothing to check).
# ========================================================================
DOC_FIXTURE="$TMP/doc-projects"
mkdir -p "$DOC_FIXTURE/healthy"
cat > "$DOC_FIXTURE/healthy/agents.config.sh" <<'CFG'
PROJECT_NAME="Healthy"
SLUG="healthyrot"
NAMESPACE="com.healthyrot"
REPO_URL="https://github.com/example/healthyrot"
SELF_CANCEL="20990101"
CFG
cat > "$DOC_FIXTURE/healthy/AGENTS.md" <<'MD'
# AGENTS.md

## Agent parameters

- gating checks: ci
MD
mkdir -p "$DOC_FIXTURE/healthy/docs/backlog" "$DOC_FIXTURE/healthy/scripts"
echo "# Backlog" > "$DOC_FIXTURE/healthy/docs/backlog/README.md"
echo "// stub" > "$DOC_FIXTURE/healthy/scripts/check-backlog.mjs"

# Stub launchctl + gh so doctor's other checks stay deterministic.
DOC_BIN="$TMP/doc-bin"
mkdir -p "$DOC_BIN"
cat > "$DOC_BIN/launchctl" <<'STUB'
#!/bin/bash
exit 0
STUB
cat > "$DOC_BIN/gh" <<'STUB'
#!/bin/bash
exit 0
STUB
chmod +x "$DOC_BIN/launchctl" "$DOC_BIN/gh"

# Healthy events.jsonl — a couple of well-formed lines, well under threshold.
HEALTHY_CACHE="$HOME/.cache/healthyrot-agent"
mkdir -p "$HEALTHY_CACHE"
cat > "$HEALTHY_CACHE/events.jsonl" <<'EV'
{"ts":"2026-01-01T00:00:00Z","slug":"healthyrot","phase":"ship","type":"run_started","pid":"1"}
{"ts":"2026-01-01T00:00:01Z","slug":"healthyrot","phase":"ship","type":"run_completed","exit":"0"}
EV

# bin/fleet does NOT source common.sh, so we can pass it in via env vars.
PATH="$DOC_BIN:$PATH" \
FLEET_DISCOVERY_ROOT="$DOC_FIXTURE" \
FLEET_SKIP_INSTALLED_LIB_SHA=1 \
  "$REPO_ROOT/bin/fleet" doctor --json > "$TMP/doctor-pass.json" 2>/dev/null || true

# events_size for the healthy project must be PASS.
ES_STATUS=$(node -e '
  const fs = require("fs");
  const d = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
  const p = d.projects.find(p => p.slug === "healthyrot");
  if (!p) { console.error("project healthyrot not in JSON"); process.exit(1); }
  const c = p.checks.find(c => c.name === "events_size");
  if (!c) { console.error("events_size check missing"); process.exit(1); }
  console.log(c.status);
' "$TMP/doctor-pass.json")
if [ "$ES_STATUS" != "PASS" ]; then
  echo "FAIL: AC#6 events_size expected PASS for healthy fixture, got $ES_STATUS"
  cat "$TMP/doctor-pass.json"
  exit 1
fi
echo "ok: AC#6a events_size PASS when under threshold"

# Now corrupt the events.jsonl with a non-JSON line and re-run doctor.
echo 'not valid json' >> "$HEALTHY_CACHE/events.jsonl"

set +e
PATH="$DOC_BIN:$PATH" \
FLEET_DISCOVERY_ROOT="$DOC_FIXTURE" \
FLEET_SKIP_INSTALLED_LIB_SHA=1 \
  "$REPO_ROOT/bin/fleet" doctor --json > "$TMP/doctor-fail.json" 2>/dev/null
DOC_EXIT=$?
set -e
# Project has a FAIL on events_size, so doctor must exit 1 overall.
if [ "$DOC_EXIT" != "1" ]; then
  echo "FAIL: AC#6 doctor exit=$DOC_EXIT (want 1 because events_size FAILed)"
  cat "$TMP/doctor-fail.json"
  exit 1
fi
ES_STATUS=$(node -e '
  const fs = require("fs");
  const d = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
  const p = d.projects.find(p => p.slug === "healthyrot");
  if (!p) { console.error("project healthyrot not in JSON"); process.exit(1); }
  const c = p.checks.find(c => c.name === "events_size");
  if (!c) { console.error("events_size check missing on FAIL run"); process.exit(1); }
  console.log(c.status);
' "$TMP/doctor-fail.json")
if [ "$ES_STATUS" != "FAIL" ]; then
  echo "FAIL: AC#6b events_size expected FAIL on malformed JSON, got $ES_STATUS"
  cat "$TMP/doctor-fail.json"
  exit 1
fi
echo "ok: AC#6b events_size FAIL when a line does not parse as JSON"

echo "ok: tests/events-rotation.sh passed"
