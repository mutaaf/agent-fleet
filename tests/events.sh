#!/bin/bash
# tests/events.sh — fleet_emit_event shape + JSON-correctness test.
#
# Ticket 0002. Calls fleet_emit_event with a value containing both a double
# quote and a backslash (the two characters the hand-rolled JSON encoder MUST
# escape), then validates every line of the resulting events.jsonl with
# `node -e "JSON.parse(...)"`. Also asserts the schema: every event carries
# ts (ISO8601 UTC), slug, phase, type, plus the k=v extras.
#
# Self-contained: stubs $HOME so we never touch real ~/.cache state. Exits
# non-zero on any failure.

set -euo pipefail

REPO_ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"

TMP="$(mktemp -d -t fleet-events-test.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

# Isolate from the real fleet cache. The lib derives CACHE_DIR from $HOME and
# $SLUG, so a fake HOME is enough.
export HOME="$TMP/home"
mkdir -p "$HOME"

# A tiny manifest the runner will source.
MANIFEST_DIR="$TMP/project"
mkdir -p "$MANIFEST_DIR"
cat > "$MANIFEST_DIR/agents.config.sh" <<'CFG'
SLUG="eventstest"
PROJECT_NAME="eventstest"
REPO_URL="https://github.com/example/eventstest.git"
SELF_CANCEL="20990101"
CFG

EVENTS_FILE="$HOME/.cache/eventstest-agent/events.jsonl"

# --- run a stub that sources common.sh and emits a few events ------------
(
  set -euo pipefail
  # shellcheck disable=SC1091
  source "$REPO_ROOT/lib/common.sh"
  fleet_load_manifest "$MANIFEST_DIR"
  # phase is what callers normally set via fleet_log_init; emulate it here.
  FLEET_PHASE="ship"
  export FLEET_PHASE

  # 1. Plain event — no escapes needed.
  fleet_emit_event run_started pid=12345

  # 2. The acceptance-criteria case: a value with a double quote AND a
  #    backslash. If the encoder is naive these will produce invalid JSON.
  fleet_emit_event gate_failed 'check=he said "hi" and \ backslash'

  # 3. Event with multiple k=v pairs.
  fleet_emit_event pr_opened number=42 branch=feat/0002-events-jsonl-channel

  # 4. Event with no extras at all.
  fleet_emit_event self_cancel_trip
)

# --- assertion 1: the file exists at $CACHE_DIR/events.jsonl ------------
if [ ! -f "$EVENTS_FILE" ]; then
  echo "FAIL: events.jsonl not created at $EVENTS_FILE"
  exit 1
fi

LINES=$(wc -l < "$EVENTS_FILE" | tr -d ' ')
if [ "$LINES" != "4" ]; then
  echo "FAIL: expected 4 events, got $LINES"
  cat "$EVENTS_FILE"
  exit 1
fi

# --- assertion 2: every line is valid JSON --------------------------------
# This is the ticket's headline assertion: a value with a quote and a
# backslash must round-trip through JSON.parse.
node -e '
  const fs = require("fs");
  const path = process.argv[1];
  const text = fs.readFileSync(path, "utf8");
  const lines = text.split("\n").filter(Boolean);
  for (const [i, line] of lines.entries()) {
    try {
      JSON.parse(line);
    } catch (e) {
      console.error("FAIL: line " + (i + 1) + " is not valid JSON: " + e.message);
      console.error("  raw: " + line);
      process.exit(1);
    }
  }
  console.log("ok: " + lines.length + " lines parsed");
' "$EVENTS_FILE"

# --- assertion 3: schema — ts, slug, phase, type on every event ----------
node -e '
  const fs = require("fs");
  const path = process.argv[1];
  const lines = fs.readFileSync(path, "utf8").split("\n").filter(Boolean);
  const required = ["ts", "slug", "phase", "type"];
  for (const [i, line] of lines.entries()) {
    const e = JSON.parse(line);
    for (const k of required) {
      if (!(k in e)) {
        console.error("FAIL: line " + (i + 1) + " missing required key " + k);
        console.error("  event: " + line);
        process.exit(1);
      }
    }
    if (e.slug !== "eventstest") {
      console.error("FAIL: line " + (i + 1) + " slug=" + e.slug + " (want eventstest)");
      process.exit(1);
    }
    // ISO8601 UTC: must end in Z and parse as a date.
    if (!/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/.test(e.ts)) {
      console.error("FAIL: line " + (i + 1) + " ts=" + e.ts + " is not ISO8601 UTC");
      process.exit(1);
    }
  }
  console.log("ok: schema valid on " + lines.length + " events");
' "$EVENTS_FILE"

# --- assertion 4: the escape case round-trips losslessly ----------------
# The value we passed in for `check` was: he said "hi" and \ backslash
node -e '
  const fs = require("fs");
  const path = process.argv[1];
  const lines = fs.readFileSync(path, "utf8").split("\n").filter(Boolean);
  const gate = lines.map(JSON.parse).find(e => e.type === "gate_failed");
  if (!gate) { console.error("FAIL: no gate_failed event found"); process.exit(1); }
  const want = "he said \"hi\" and \\ backslash";
  if (gate.check !== want) {
    console.error("FAIL: check field did not round-trip");
    console.error("  want: " + JSON.stringify(want));
    console.error("  got:  " + JSON.stringify(gate.check));
    process.exit(1);
  }
  console.log("ok: escape round-trip");
' "$EVENTS_FILE"

# --- assertion 5: extras land as JSON keys --------------------------------
node -e '
  const fs = require("fs");
  const path = process.argv[1];
  const lines = fs.readFileSync(path, "utf8").split("\n").filter(Boolean);
  const events = lines.map(JSON.parse);

  const run = events.find(e => e.type === "run_started");
  if (!run || run.pid !== "12345") {
    console.error("FAIL: run_started.pid not 12345, got " + JSON.stringify(run));
    process.exit(1);
  }

  const pr = events.find(e => e.type === "pr_opened");
  if (!pr || pr.number !== "42" || pr.branch !== "feat/0002-events-jsonl-channel") {
    console.error("FAIL: pr_opened extras wrong: " + JSON.stringify(pr));
    process.exit(1);
  }

  const sc = events.find(e => e.type === "self_cancel_trip");
  if (!sc) { console.error("FAIL: self_cancel_trip event missing"); process.exit(1); }
  // No extras — the only keys should be the four required ones.
  const extras = Object.keys(sc).filter(k => !["ts","slug","phase","type"].includes(k));
  if (extras.length !== 0) {
    console.error("FAIL: self_cancel_trip should have no extras, got " + JSON.stringify(extras));
    process.exit(1);
  }
  console.log("ok: extras land as JSON keys");
' "$EVENTS_FILE"

# --- assertion 6: append-only (no truncation between calls) -------------
# Re-run and verify the file grew, the old lines are still there.
BEFORE=$(wc -l < "$EVENTS_FILE" | tr -d ' ')
(
  set -euo pipefail
  # shellcheck disable=SC1091
  source "$REPO_ROOT/lib/common.sh"
  fleet_load_manifest "$MANIFEST_DIR"
  FLEET_PHASE="ship"
  export FLEET_PHASE
  fleet_emit_event run_completed exit=0 duration_ms=1234
)
AFTER=$(wc -l < "$EVENTS_FILE" | tr -d ' ')
if [ "$AFTER" != "$((BEFORE + 1))" ]; then
  echo "FAIL: events.jsonl was not append-only (before=$BEFORE after=$AFTER)"
  exit 1
fi

echo "ok: tests/events.sh passed"
