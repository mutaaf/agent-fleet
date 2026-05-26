#!/bin/bash
# tests/cadence.sh — adaptive groom cadence (ticket 0007).
#
# Five acceptance-criteria scenarios, one per AC checkbox:
#   A. Empty/sparse backlog → fleet_check_groom_cadence writes
#      $CACHE_DIR/groom-slowed-since, emits one `groom_throttled` event
#      with reason=empty_backlog + since=<iso>, and returns 1 (caller
#      `|| exit 0` skips the spawn).
#   B. Marker exists + <12h old → returns 1, emits a SECOND
#      `groom_throttled` event whose `since` field equals the ORIGINAL
#      timestamp baked in the marker (not "now").
#   C. Marker exists + 12h+ old → returns 0 (proceed), removes the marker
#      before exit, emits NO `groom_throttled` event.
#   D. No marker AND backlog has groomed P0/P1 work → returns 0, no
#      `groom_throttled` event emitted.
#   E. `bin/fleet doctor` exposes a `groom_cadence` check: PASS when the
#      marker is absent or stale; WARN with the marker timestamp in the
#      `reason` field when the marker is fresh (throttled). The --json
#      shape includes the check name and the reason string.
#
# Self-contained: stubs $HOME, builds a fake checkout under $TMP with a
# controlled docs/backlog/README.md, and uses `touch -t` to age the marker
# file across the 12h boundary. BSD touch interprets -t as local time —
# we work around that with explicit relative offsets in UTC.

set -euo pipefail

REPO_ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"

TMP="$(mktemp -d -t fleet-cadence-test.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

export HOME="$TMP/home"
mkdir -p "$HOME"

MANIFEST_DIR="$TMP/project"
mkdir -p "$MANIFEST_DIR"
cat > "$MANIFEST_DIR/agents.config.sh" <<'CFG'
SLUG="cadencetest"
PROJECT_NAME="cadencetest"
REPO_URL="https://github.com/example/cadencetest.git"
NAMESPACE="com.fleet.cadencetest"
SELF_CANCEL="20990101"
CFG

CACHE="$HOME/.cache/cadencetest-agent"
EVENTS="$CACHE/events.jsonl"
MARKER="$CACHE/groom-slowed-since"
mkdir -p "$CACHE"

# Build a fake "checkout" the cadence gate will inspect. We point the
# function at this dir via FLEET_CADENCE_CHECKOUT (a test seam) so we
# don't have to clone anything.
FAKE_CHECKOUT="$TMP/checkout"
mkdir -p "$FAKE_CHECKOUT/docs/backlog"

# ---------------------------------------------------------------------------
# CASE A — empty/sparse backlog: no `proposed` rows, fewer than 3 groomed
# P0/P1 rows. The function should write the marker, emit one event, return 1.
# ---------------------------------------------------------------------------
cat > "$FAKE_CHECKOUT/docs/backlog/README.md" <<'README'
# Backlog

## Index

| id | title | priority | status | area |
|----|-------|----------|--------|------|
| 0001 | already shipped thing | P0 | shipped | engine |
| 0002 | done done done        | P1 | shipped | engine |
| 0003 | one lonely groomed    | P0 | groomed | engine |
README

: > "$EVENTS"
rm -f "$MARKER"

(
  set -euo pipefail
  # shellcheck disable=SC1091
  source "$REPO_ROOT/lib/common.sh"
  fleet_load_manifest "$MANIFEST_DIR"
  FLEET_PHASE="groom"; export FLEET_PHASE
  export FLEET_CADENCE_CHECKOUT="$FAKE_CHECKOUT"
  if fleet_check_groom_cadence; then
    echo "FAIL: case A — sparse backlog should throttle (return 1)"
    exit 1
  fi
) || exit 1

if [ ! -f "$MARKER" ]; then
  echo "FAIL: case A — marker file $MARKER not written"
  exit 1
fi

MARKER_TS="$(cat "$MARKER")"
case "$MARKER_TS" in
  ????-??-??T??:??:??Z) ;;
  *)
    echo "FAIL: case A — marker contents not ISO8601 UTC: '$MARKER_TS'"
    exit 1 ;;
esac

if ! grep -q '"type":"groom_throttled"' "$EVENTS"; then
  echo "FAIL: case A — groom_throttled event missing"
  cat "$EVENTS"
  exit 1
fi

node -e '
  const fs = require("fs");
  const lines = fs.readFileSync(process.argv[1], "utf8").split("\n").filter(Boolean);
  const evs = lines.map(JSON.parse).filter(e => e.type === "groom_throttled");
  if (evs.length !== 1) {
    console.error("FAIL: case A — want exactly 1 groom_throttled event, got " + evs.length);
    process.exit(1);
  }
  const ev = evs[0];
  if (ev.reason !== "empty_backlog") {
    console.error("FAIL: case A — event reason = " + ev.reason + " (want empty_backlog)");
    process.exit(1);
  }
  if (!ev.since || !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/.test(ev.since)) {
    console.error("FAIL: case A — event.since not ISO8601 UTC: " + JSON.stringify(ev.since));
    process.exit(1);
  }
  console.log("ok case A: event shape valid");
' "$EVENTS"

# ---------------------------------------------------------------------------
# CASE B — marker exists, <12h old (we just wrote it in CASE A). The function
# should NOT touch the marker, return 1, and emit a second event whose
# `since` field equals the ORIGINAL marker contents (not "now").
# ---------------------------------------------------------------------------
ORIGINAL_TS="$MARKER_TS"

(
  set -euo pipefail
  # shellcheck disable=SC1091
  source "$REPO_ROOT/lib/common.sh"
  fleet_load_manifest "$MANIFEST_DIR"
  FLEET_PHASE="groom"; export FLEET_PHASE
  export FLEET_CADENCE_CHECKOUT="$FAKE_CHECKOUT"
  if fleet_check_groom_cadence; then
    echo "FAIL: case B — fresh marker should keep throttling (return 1)"
    exit 1
  fi
) || exit 1

if [ ! -f "$MARKER" ]; then
  echo "FAIL: case B — marker should still exist while throttled"
  exit 1
fi
if [ "$(cat "$MARKER")" != "$ORIGINAL_TS" ]; then
  echo "FAIL: case B — marker contents changed (was '$ORIGINAL_TS', now '$(cat "$MARKER")')"
  exit 1
fi

node -e '
  const fs = require("fs");
  const orig = process.argv[2];
  const lines = fs.readFileSync(process.argv[1], "utf8").split("\n").filter(Boolean);
  const evs = lines.map(JSON.parse).filter(e => e.type === "groom_throttled");
  if (evs.length !== 2) {
    console.error("FAIL: case B — want 2 groom_throttled events total, got " + evs.length);
    process.exit(1);
  }
  if (evs[1].since !== orig) {
    console.error("FAIL: case B — second event since=" + evs[1].since + " (want original " + orig + ")");
    process.exit(1);
  }
  console.log("ok case B: throttle reuses original timestamp");
' "$EVENTS" "$ORIGINAL_TS"

# ---------------------------------------------------------------------------
# CASE C — marker is 12h+ old (we backdate it to 13h ago). The function
# should proceed (return 0), remove the marker, emit NO event.
# ---------------------------------------------------------------------------
: > "$EVENTS"
# Write a stale timestamp explicitly and also age the file's mtime so
# either signal (mtime or content) is unambiguously >12h.
STALE_TS="$(date -u -v-13H +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
              || date -u -d '13 hours ago' +%Y-%m-%dT%H:%M:%SZ)"
printf '%s\n' "$STALE_TS" > "$MARKER"
# BSD touch -t uses LOCAL time. Compute the local-time stamp for 13h ago.
LOCAL_STALE="$(date -v-13H +%Y%m%d%H%M 2>/dev/null \
                || date -d '13 hours ago' +%Y%m%d%H%M)"
touch -t "$LOCAL_STALE" "$MARKER" 2>/dev/null || true

(
  set -euo pipefail
  # shellcheck disable=SC1091
  source "$REPO_ROOT/lib/common.sh"
  fleet_load_manifest "$MANIFEST_DIR"
  FLEET_PHASE="groom"; export FLEET_PHASE
  export FLEET_CADENCE_CHECKOUT="$FAKE_CHECKOUT"
  if ! fleet_check_groom_cadence; then
    echo "FAIL: case C — stale marker should let groom proceed (return 0)"
    exit 1
  fi
) || exit 1

if [ -f "$MARKER" ]; then
  echo "FAIL: case C — marker should be removed once stale and groom resumes"
  exit 1
fi
if [ -f "$EVENTS" ] && grep -q '"type":"groom_throttled"' "$EVENTS"; then
  echo "FAIL: case C — emitted groom_throttled despite stale marker"
  cat "$EVENTS"
  exit 1
fi

# ---------------------------------------------------------------------------
# CASE D — no marker, backlog has plenty of groomed P0/P1 work AND a
# proposed row. The function should proceed and emit no event.
# ---------------------------------------------------------------------------
cat > "$FAKE_CHECKOUT/docs/backlog/README.md" <<'README'
# Backlog

## Index

| id | title | priority | status | area |
|----|-------|----------|--------|------|
| 0010 | needs grooming     | P1 | proposed | engine |
| 0011 | top groomed thing  | P0 | groomed  | engine |
| 0012 | second groomed     | P0 | groomed  | safety |
| 0013 | third groomed      | P1 | groomed  | engine |
README

: > "$EVENTS"
rm -f "$MARKER"

(
  set -euo pipefail
  # shellcheck disable=SC1091
  source "$REPO_ROOT/lib/common.sh"
  fleet_load_manifest "$MANIFEST_DIR"
  FLEET_PHASE="groom"; export FLEET_PHASE
  export FLEET_CADENCE_CHECKOUT="$FAKE_CHECKOUT"
  if ! fleet_check_groom_cadence; then
    echo "FAIL: case D — full backlog should let groom proceed (return 0)"
    exit 1
  fi
) || exit 1

if [ -f "$MARKER" ]; then
  echo "FAIL: case D — marker should not be created when backlog is full"
  exit 1
fi
if [ -f "$EVENTS" ] && grep -q '"type":"groom_throttled"' "$EVENTS"; then
  echo "FAIL: case D — emitted groom_throttled despite full backlog"
  cat "$EVENTS"
  exit 1
fi

# ---------------------------------------------------------------------------
# CASE E — `bin/fleet doctor` includes a groom_cadence check whose status
# reflects the marker. We build a tiny FLEET_DISCOVERY_ROOT fixture so the
# doctor walks one project: when the marker is fresh, the check is WARN
# and its `reason` carries the marker timestamp; with no marker, PASS.
# ---------------------------------------------------------------------------
FIXTURE="$TMP/projects"
mkdir -p "$FIXTURE/cadencetest" "$FIXTURE/cadencetest/docs/backlog" "$FIXTURE/cadencetest/scripts"
cp "$MANIFEST_DIR/agents.config.sh" "$FIXTURE/cadencetest/agents.config.sh"
cat > "$FIXTURE/cadencetest/AGENTS.md" <<'MD'
# AGENTS.md
## Agent parameters
- gating checks: ci
MD
echo "# Backlog" > "$FIXTURE/cadencetest/docs/backlog/README.md"
echo "// stub" > "$FIXTURE/cadencetest/scripts/check-backlog.mjs"

# Stub launchctl + gh so other checks don't blow up. The doctor only consumes
# their exit codes for the launchd / gh_auth checks.
STUB_BIN="$TMP/bin"
mkdir -p "$STUB_BIN"
cat > "$STUB_BIN/launchctl" <<'STUB'
#!/bin/bash
exit 0
STUB
cat > "$STUB_BIN/gh" <<'STUB'
#!/bin/bash
exit 0
STUB
chmod +x "$STUB_BIN/launchctl" "$STUB_BIN/gh"
export PATH="$STUB_BIN:$PATH"
export FLEET_DISCOVERY_ROOT="$FIXTURE"
export FLEET_SKIP_INSTALLED_LIB_SHA=1

FLEET="$REPO_ROOT/bin/fleet"

# E1 — no marker → groom_cadence PASS.
rm -f "$MARKER"
DOC_OUT="$TMP/doc.no-marker.json"
set +e
"$FLEET" doctor --slug cadencetest --json > "$DOC_OUT"
set -e
node -e '
  const fs = require("fs");
  const j = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
  const p = j.projects.find(p => p.slug === "cadencetest");
  if (!p) { console.error("FAIL: case E1 — no cadencetest project in doctor output"); process.exit(1); }
  const chk = p.checks.find(c => c.name === "groom_cadence");
  if (!chk) {
    console.error("FAIL: case E1 — no groom_cadence check (got " + p.checks.map(c=>c.name).join(",") + ")");
    process.exit(1);
  }
  if (chk.status !== "PASS") {
    console.error("FAIL: case E1 — groom_cadence status=" + chk.status + " (want PASS when no marker)");
    process.exit(1);
  }
  console.log("ok case E1: groom_cadence PASS with no marker");
' "$DOC_OUT"

# E2 — fresh marker → groom_cadence WARN with timestamp in the reason.
FRESH_TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
printf '%s\n' "$FRESH_TS" > "$MARKER"
DOC_OUT2="$TMP/doc.marker.json"
set +e
"$FLEET" doctor --slug cadencetest --json > "$DOC_OUT2"
set -e
node -e '
  const fs = require("fs");
  const j = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
  const ts = process.argv[2];
  const p = j.projects.find(p => p.slug === "cadencetest");
  const chk = p.checks.find(c => c.name === "groom_cadence");
  if (!chk) { console.error("FAIL: case E2 — no groom_cadence check"); process.exit(1); }
  if (chk.status !== "WARN") {
    console.error("FAIL: case E2 — groom_cadence status=" + chk.status + " (want WARN when marker fresh)");
    process.exit(1);
  }
  if (!chk.reason || chk.reason.indexOf(ts) === -1) {
    console.error("FAIL: case E2 — reason must include marker ts " + ts + ", got: " + JSON.stringify(chk.reason));
    process.exit(1);
  }
  console.log("ok case E2: groom_cadence WARN reason carries the timestamp");
' "$DOC_OUT2" "$FRESH_TS"

# E3 — stale marker (>12h) → groom_cadence PASS (marker is moot, will be
# cleared on the next groom run).
STALE_TS2="$(date -u -v-13H +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
               || date -u -d '13 hours ago' +%Y-%m-%dT%H:%M:%SZ)"
printf '%s\n' "$STALE_TS2" > "$MARKER"
LOCAL_STALE2="$(date -v-13H +%Y%m%d%H%M 2>/dev/null \
                  || date -d '13 hours ago' +%Y%m%d%H%M)"
touch -t "$LOCAL_STALE2" "$MARKER" 2>/dev/null || true
DOC_OUT3="$TMP/doc.stale.json"
set +e
"$FLEET" doctor --slug cadencetest --json > "$DOC_OUT3"
set -e
node -e '
  const fs = require("fs");
  const j = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
  const p = j.projects.find(p => p.slug === "cadencetest");
  const chk = p.checks.find(c => c.name === "groom_cadence");
  if (chk.status !== "PASS") {
    console.error("FAIL: case E3 — stale marker should be PASS, got " + chk.status);
    process.exit(1);
  }
  console.log("ok case E3: groom_cadence PASS with stale marker");
' "$DOC_OUT3"

echo "ok: tests/cadence.sh passed"
