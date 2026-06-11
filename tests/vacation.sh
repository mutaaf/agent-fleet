#!/bin/bash
# tests/vacation.sh — `fleet vacation --until <date> --reason "<text>"`
# suspends ship/eng work across the whole fleet, schedules an auto-resume
# launchd job, and prints a one-paragraph "while you're away" briefing.
# Ticket 0046.
#
# Twelve acceptance-criteria scenarios, mapped 1:1 to the ticket's AC boxes.
# Strategy mirrors tests/quiet-hours.sh:
#   * Stubs `launchctl` and `gh` under $HOME/.local/bin so the PATH reset
#     in lib/common.sh keeps them visible (LESSONS 2026-05-26).
#   * Backs up + restores `bin/fleet`-installed state files via `cp` so a
#     trailing newline survives byte-for-byte (LESSONS 2026-05-27).
#   * Freezes the clock via FLEET_NOW_OVERRIDE so date math is
#     deterministic, and pins `--until` inputs to a fixed reference day
#     (2026-06-15) so "today is X UTC" calculations don't drift.
#   * The `_fleet_check_vacation` helper is invoked WITHOUT `$(…)` so the
#     FLEET_VACATION_SKIP_EMITTED guard persists in the parent shell
#     (LESSONS 2026-06-05 export-in-subshell trap).
#   * Reason text is ASCII-only — the JSON escape relies on
#     preflight_json_escape which short-circuits high bytes
#     (LESSONS 2026-06-03).
#   * Counts use `awk … END { print n+0 }` (LESSONS 2026-06-01: grep -c
#     double-prints on zero matches).
#   * grep patterns leading with `-` go through `grep -qF -- pat` (LESSONS
#     2026-05-30).
#
# Self-contained: stubs $HOME under $TMP and exits non-zero on any failure.

set -euo pipefail

REPO_ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"

TMP="$(mktemp -d -t fleet-vacation-test.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

# Isolate from the real fleet cache.
export HOME="$TMP/home"
mkdir -p "$HOME/.local/bin" "$HOME/.cache" "$HOME/Library/LaunchAgents"

# --- stubs (LESSONS 2026-05-26) -------------------------------------------
STUB_BIN="$HOME/.local/bin"
LAUNCHCTL_LOG="$TMP/launchctl.log"
GH_LOG="$TMP/gh.log"
CLAUDE_LOG="$TMP/claude.log"
GIT_LOG="$TMP/git.log"
: > "$LAUNCHCTL_LOG"
: > "$GH_LOG"
: > "$CLAUDE_LOG"
: > "$GIT_LOG"

cat > "$STUB_BIN/launchctl" <<STUB
#!/bin/bash
printf '%s\n' "launchctl \$*" >> "$LAUNCHCTL_LOG"
# The production code calls bootout/bootstrap/print/enable; always exit 0.
exit 0
STUB
chmod +x "$STUB_BIN/launchctl"

cat > "$STUB_BIN/gh" <<STUB
#!/bin/bash
printf '%s\n' "gh \$*" >> "$GH_LOG"
exit 0
STUB
chmod +x "$STUB_BIN/gh"

cat > "$STUB_BIN/claude" <<STUB
#!/bin/bash
printf '%s\n' "claude \$*" >> "$CLAUDE_LOG"
cat >/dev/null 2>&1 || true
printf '%s\n' '{"result":"unused","total_cost_usd":0,"session_id":"x","duration_ms":1,"num_turns":1,"usage":{},"is_error":false}'
exit 0
STUB
chmod +x "$STUB_BIN/claude"

export PATH="$STUB_BIN:$PATH"

# Helper: reset stub logs + cache for the next scenario.
reset_state() {
  : > "$LAUNCHCTL_LOG"
  : > "$GH_LOG"
  : > "$CLAUDE_LOG"
  rm -f "$HOME/.cache/fleet/vacation-state"
  rm -rf "$HOME/.cache/vacalpha-agent" "$HOME/.cache/vacbravo-agent"
  unset FLEET_VACATION_VERDICT FLEET_VACATION_SKIP_EMITTED
}

# Two-slug discovery root for the v1 fleet-wide path. The dispatcher's
# `vacation_discover_slugs` reads `agents.config.sh` files under
# FLEET_DISCOVERY_ROOT (working tree wins) or
# ~/.local/share/agent-fleet/projects (installed copies). We set the env
# to point at the fixture dir copied into $TMP so the host's real
# ~/Desktop tree isn't scanned.
mk_discovery_root() {
  local root="$TMP/discovery"
  rm -rf "$root"
  mkdir -p "$root/vacalpha" "$root/vacbravo"
  cp "$REPO_ROOT/tests/fixtures/vacation/slug-alpha.agents.config.sh" \
     "$root/vacalpha/agents.config.sh"
  cp "$REPO_ROOT/tests/fixtures/vacation/slug-bravo.agents.config.sh" \
     "$root/vacbravo/agents.config.sh"
  printf '%s\n' "$root"
}

FLEET_BIN="$REPO_ROOT/bin/fleet"

# A pinned "today" anchor for every scenario that touches date math.
# 2026-06-11 is the ticket creation date; --until 2026-06-21 is 10 days away.
NOW_TODAY="2026-06-11T08:00:00Z"
UNTIL_OK="2026-06-21"
UNTIL_PAST="2026-06-01"
UNTIL_FAR="2026-12-31"  # ~203 days away → triggers the long-vacation warning

# ===========================================================================
# AC #1 — `--until` and `--reason` REQUIRED; missing or non-ASCII reason
# refuses with the documented banner and exit 2.
# ===========================================================================
reset_state

# AC#1a: missing --until
AC1A_STDERR="$TMP/ac1a.stderr"
set +e
FLEET_NOW_OVERRIDE="$NOW_TODAY" \
  FLEET_DISCOVERY_ROOT="$(mk_discovery_root)" \
  "$FLEET_BIN" vacation --reason "10-day trip" 2> "$AC1A_STDERR"
AC1A_EXIT=$?
set -e
if [ "$AC1A_EXIT" -ne 2 ]; then
  echo "FAIL: AC#1a missing --until want exit 2, got $AC1A_EXIT"
  cat "$AC1A_STDERR"; exit 1
fi
if ! grep -qF -- 'vacation: usage: bin/fleet vacation --until YYYY-MM-DD --reason' "$AC1A_STDERR"; then
  echo "FAIL: AC#1a stderr missing usage banner"
  cat "$AC1A_STDERR"; exit 1
fi

# AC#1b: missing --reason
AC1B_STDERR="$TMP/ac1b.stderr"
set +e
FLEET_NOW_OVERRIDE="$NOW_TODAY" \
  FLEET_DISCOVERY_ROOT="$(mk_discovery_root)" \
  "$FLEET_BIN" vacation --until "$UNTIL_OK" 2> "$AC1B_STDERR"
AC1B_EXIT=$?
set -e
if [ "$AC1B_EXIT" -ne 2 ]; then
  echo "FAIL: AC#1b missing --reason want exit 2, got $AC1B_EXIT"
  cat "$AC1B_STDERR"; exit 1
fi
if ! grep -qF -- 'vacation: --reason is required (one-line ASCII) for the audit trail' "$AC1B_STDERR"; then
  echo "FAIL: AC#1b stderr missing required-reason banner"
  cat "$AC1B_STDERR"; exit 1
fi

# AC#1c: non-ASCII reason (the em-dash is 3-byte UTF-8 — sign-extension trap).
AC1C_STDERR="$TMP/ac1c.stderr"
set +e
FLEET_NOW_OVERRIDE="$NOW_TODAY" \
  FLEET_DISCOVERY_ROOT="$(mk_discovery_root)" \
  "$FLEET_BIN" vacation --until "$UNTIL_OK" --reason "10-day trip — back Sat" 2> "$AC1C_STDERR"
AC1C_EXIT=$?
set -e
if [ "$AC1C_EXIT" -ne 2 ]; then
  echo "FAIL: AC#1c non-ASCII --reason want exit 2, got $AC1C_EXIT"
  cat "$AC1C_STDERR"; exit 1
fi
if ! grep -qF -- 'vacation: --reason must be ASCII for v1' "$AC1C_STDERR"; then
  echo "FAIL: AC#1c stderr missing ASCII-only banner"
  cat "$AC1C_STDERR"; exit 1
fi

echo "ok: AC#1 missing/non-ASCII flags refuse with documented banners and exit 2"

# ===========================================================================
# AC #2 — Successful invocation writes
# $HOME/.cache/fleet/vacation-state as a single JSON line with
# {since, until, reason, slugs_suspended}. JSON-escaped via
# preflight_json_escape; file mode 0644.
# ===========================================================================
reset_state
AC2_STDOUT="$TMP/ac2.stdout"
DISCOVERY="$(mk_discovery_root)"
set +e
FLEET_NOW_OVERRIDE="$NOW_TODAY" \
  FLEET_DISCOVERY_ROOT="$DISCOVERY" \
  "$FLEET_BIN" vacation --until "$UNTIL_OK" --reason "10-day trip, back Sat" > "$AC2_STDOUT" 2>&1
AC2_EXIT=$?
set -e
if [ "$AC2_EXIT" -ne 0 ]; then
  echo "FAIL: AC#2 successful invocation want exit 0, got $AC2_EXIT"
  cat "$AC2_STDOUT"; exit 1
fi
STATE_FILE="$HOME/.cache/fleet/vacation-state"
if [ ! -f "$STATE_FILE" ]; then
  echo "FAIL: AC#2 state file missing at $STATE_FILE"
  ls -la "$HOME/.cache/fleet/" 2>/dev/null || true
  exit 1
fi
# AC#9 piggyback: the directory must be created with mkdir -p if absent.
if [ ! -d "$HOME/.cache/fleet" ]; then
  echo "FAIL: AC#2/AC#9 $HOME/.cache/fleet was not created by mkdir -p"
  exit 1
fi
# Mode 0644 (some envs default umask to 022 → 0644). We only enforce
# the "world-readable + owner-writable" subset to stay portable.
PERMS="$(stat -f '%Lp' "$STATE_FILE" 2>/dev/null || stat -c '%a' "$STATE_FILE")"
case "$PERMS" in
  644|0644) ;;
  *)
    echo "FAIL: AC#2 state file mode $PERMS (want 644)"
    exit 1 ;;
esac
# Parse and validate the JSON shape.
node -e '
  const fs = require("fs");
  const raw = fs.readFileSync(process.argv[1], "utf8").trim();
  let obj;
  try { obj = JSON.parse(raw); }
  catch (e) {
    console.error("FAIL: AC#2 vacation-state is not valid JSON: " + e.message);
    console.error("raw: " + raw);
    process.exit(1);
  }
  for (const k of ["since","until","reason","slugs_suspended"]) {
    if (!(k in obj)) {
      console.error("FAIL: AC#2 missing key " + k + " in " + JSON.stringify(obj));
      process.exit(1);
    }
  }
  if (!Array.isArray(obj.slugs_suspended)) {
    console.error("FAIL: AC#2 slugs_suspended is not an array: " + JSON.stringify(obj.slugs_suspended));
    process.exit(1);
  }
  if (obj.slugs_suspended.length < 2) {
    console.error("FAIL: AC#2 expected 2 discovered slugs, got " + obj.slugs_suspended.length);
    process.exit(1);
  }
  if (obj.reason !== "10-day trip, back Sat") {
    console.error("FAIL: AC#2 reason round-trip wrong: " + obj.reason);
    process.exit(1);
  }
  // since: ISO8601 with Z anchor; until: YYYY-MM-DDT00:00:00Z form.
  if (!/^2026-06-11T/.test(obj.since)) {
    console.error("FAIL: AC#2 since not anchored to today: " + obj.since);
    process.exit(1);
  }
  if (obj.until !== "2026-06-21T00:00:00Z") {
    console.error("FAIL: AC#2 until want 2026-06-21T00:00:00Z, got " + obj.until);
    process.exit(1);
  }
  console.log("ok: AC#2 vacation-state JSON shape verified");
' "$STATE_FILE"

# ===========================================================================
# AC #3 — Installs com.agent-fleet.vacation-resume launchd job whose
# StartCalendarInterval fires once at <until> 00:00 UTC and runs
# `bin/fleet vacation --return`. Re-invocation REPLACES (not duplicates).
# ===========================================================================
PLIST="$HOME/Library/LaunchAgents/com.agent-fleet.vacation-resume.plist"
if [ ! -f "$PLIST" ]; then
  echo "FAIL: AC#3 launchd plist missing at $PLIST"
  ls -la "$HOME/Library/LaunchAgents/" 2>/dev/null || true
  exit 1
fi
# Plist must mention --return, --until's year/month/day, and the
# StartCalendarInterval key.
if ! grep -qF -- 'StartCalendarInterval' "$PLIST"; then
  echo "FAIL: AC#3 plist missing StartCalendarInterval key"
  cat "$PLIST"; exit 1
fi
if ! grep -qF -- '<string>vacation</string>' "$PLIST"; then
  echo "FAIL: AC#3 plist missing 'vacation' subcommand"
  cat "$PLIST"; exit 1
fi
if ! grep -qF -- '<string>--return</string>' "$PLIST"; then
  echo "FAIL: AC#3 plist missing '--return' argument"
  cat "$PLIST"; exit 1
fi
# StartCalendarInterval Year=2026 Month=6 Day=21 Hour=0 Minute=0.
node -e '
  const fs = require("fs");
  const xml = fs.readFileSync(process.argv[1], "utf8");
  // Pull out the StartCalendarInterval dict integer pairs.
  // We look for <key>X</key><integer>N</integer> sequences in document
  // order. Robust enough for our generated plist (no nested dicts).
  const pairs = {};
  const re = /<key>([A-Za-z]+)<\/key>\s*<integer>(-?\d+)<\/integer>/g;
  let m;
  while ((m = re.exec(xml)) !== null) {
    pairs[m[1]] = parseInt(m[2], 10);
  }
  const want = { Year: 2026, Month: 6, Day: 21, Hour: 0, Minute: 0 };
  for (const k of Object.keys(want)) {
    if (pairs[k] !== want[k]) {
      console.error("FAIL: AC#3 StartCalendarInterval " + k + " = " + pairs[k] + " (want " + want[k] + ")");
      process.exit(1);
    }
  }
  console.log("ok: AC#3 StartCalendarInterval Year/Month/Day/Hour/Minute match --until 2026-06-21");
' "$PLIST"

# Confirm launchctl bootstrap was invoked (idempotent — bootout first
# then bootstrap, per the resume-plist pattern).
if ! grep -qF -- 'bootstrap' "$LAUNCHCTL_LOG"; then
  echo "FAIL: AC#3 launchctl bootstrap not invoked"
  cat "$LAUNCHCTL_LOG"; exit 1
fi
if ! grep -qF -- 'com.agent-fleet.vacation-resume' "$LAUNCHCTL_LOG"; then
  echo "FAIL: AC#3 launchctl invocation did not name vacation-resume label"
  cat "$LAUNCHCTL_LOG"; exit 1
fi

# Re-invoke with a NEW --until and confirm the plist updates and the
# state file is replaced (not duplicated).
: > "$LAUNCHCTL_LOG"
set +e
FLEET_NOW_OVERRIDE="$NOW_TODAY" \
  FLEET_DISCOVERY_ROOT="$DISCOVERY" \
  "$FLEET_BIN" vacation --until "2026-06-25" --reason "extended trip" > "$TMP/ac3b.out" 2>&1
AC3B_EXIT=$?
set -e
if [ "$AC3B_EXIT" -ne 0 ]; then
  echo "FAIL: AC#3 re-invocation want exit 0, got $AC3B_EXIT"
  cat "$TMP/ac3b.out"; exit 1
fi
# Second invocation should bootout first, then bootstrap.
BOOTOUT_COUNT="$(awk '/bootout/ { n++ } END { print n+0 }' "$LAUNCHCTL_LOG")"
BOOTSTRAP_COUNT="$(awk '/bootstrap/ { n++ } END { print n+0 }' "$LAUNCHCTL_LOG")"
if [ "$BOOTOUT_COUNT" -lt 1 ]; then
  echo "FAIL: AC#3 re-invocation did not bootout the prior plist"
  cat "$LAUNCHCTL_LOG"; exit 1
fi
if [ "$BOOTSTRAP_COUNT" -lt 1 ]; then
  echo "FAIL: AC#3 re-invocation did not bootstrap the updated plist"
  cat "$LAUNCHCTL_LOG"; exit 1
fi
# Plist Year/Month/Day must reflect the NEW --until.
node -e '
  const fs = require("fs");
  const xml = fs.readFileSync(process.argv[1], "utf8");
  const pairs = {};
  const re = /<key>([A-Za-z]+)<\/key>\s*<integer>(-?\d+)<\/integer>/g;
  let m;
  while ((m = re.exec(xml)) !== null) pairs[m[1]] = parseInt(m[2], 10);
  if (pairs.Day !== 25) {
    console.error("FAIL: AC#3 re-invocation plist Day=" + pairs.Day + " (want 25)");
    process.exit(1);
  }
  console.log("ok: AC#3 re-invocation replaces plist (Day=25) and prior bootout fired");
' "$PLIST"

# ===========================================================================
# AC #4 — lib/ship.sh and lib/eng.sh PHASE 0 (right after fleet_self_cancel)
# read $HOME/.cache/fleet/vacation-state. If active, emit ONE
# vacation_skip {until, reason} per process and exit 0. Multi-call dedup
# via FLEET_VACATION_SKIP_EMITTED.
# ===========================================================================
reset_state
# Write a state file that's clearly active in the test window.
mkdir -p "$HOME/.cache/fleet"
cat > "$HOME/.cache/fleet/vacation-state" <<'STATE'
{"since":"2026-06-11T08:00:00Z","until":"2026-06-21T00:00:00Z","reason":"10-day trip","slugs_suspended":["vacalpha","vacbravo"]}
STATE

# Build a one-off project dir for the runner so fleet_load_manifest has
# something to chew on. SLUG=vacalpha so events.jsonl lands at
# $HOME/.cache/vacalpha-agent/events.jsonl.
SHIP_PROJ="$TMP/ship-proj"
mkdir -p "$SHIP_PROJ"
cp "$REPO_ROOT/tests/fixtures/vacation/slug-alpha.agents.config.sh" \
   "$SHIP_PROJ/agents.config.sh"

# Run lib/ship.sh — should suppress + emit + exit 0 + NOT touch claude/gh.
SHIP_OUT="$TMP/ac4-ship.out"
: > "$CLAUDE_LOG"
: > "$GH_LOG"
set +e
FLEET_NOW_OVERRIDE="2026-06-15T12:00:00Z" \
  bash "$REPO_ROOT/lib/ship.sh" "$SHIP_PROJ" > "$SHIP_OUT" 2>&1
SHIP_EXIT=$?
set -e
if [ "$SHIP_EXIT" -ne 0 ]; then
  echo "FAIL: AC#4 ship runner under active vacation want exit 0, got $SHIP_EXIT"
  cat "$SHIP_OUT"; exit 1
fi
if [ -s "$CLAUDE_LOG" ]; then
  echo "FAIL: AC#4 ship runner invoked claude on the suppress path"
  cat "$CLAUDE_LOG"; exit 1
fi
SHIP_EVENTS="$HOME/.cache/vacalpha-agent/events.jsonl"
if [ ! -f "$SHIP_EVENTS" ]; then
  echo "FAIL: AC#4 events.jsonl missing for ship suppress"
  exit 1
fi
SHIP_SKIP_N="$(awk '/"type":"vacation_skip"/ { n++ } END { print n+0 }' "$SHIP_EVENTS")"
if [ "$SHIP_SKIP_N" -ne 1 ]; then
  echo "FAIL: AC#4 want exactly 1 vacation_skip event from ship, got $SHIP_SKIP_N"
  cat "$SHIP_EVENTS"; exit 1
fi

# Validate payload shape (until + reason both present and round-trip).
node -e '
  const fs = require("fs");
  const lines = fs.readFileSync(process.argv[1], "utf8").split("\n").filter(Boolean);
  const ev = lines.map(JSON.parse).find(e => e.type === "vacation_skip");
  if (!ev) { console.error("FAIL: AC#4 no vacation_skip event parsed"); process.exit(1); }
  for (const k of ["ts","slug","phase","type","until","reason"]) {
    if (typeof ev[k] !== "string" || ev[k].length === 0) {
      console.error("FAIL: AC#4 event missing/empty " + k + ": " + JSON.stringify(ev));
      process.exit(1);
    }
  }
  if (ev.until !== "2026-06-21T00:00:00Z") {
    console.error("FAIL: AC#4 ev.until=" + ev.until); process.exit(1);
  }
  if (ev.reason !== "10-day trip") {
    console.error("FAIL: AC#4 ev.reason=" + ev.reason); process.exit(1);
  }
  console.log("ok: AC#4a ship emits one vacation_skip with {until,reason} payload");
' "$SHIP_EVENTS"

# Same for the eng runner.
ENG_PROJ="$TMP/eng-proj"
mkdir -p "$ENG_PROJ"
cp "$REPO_ROOT/tests/fixtures/vacation/slug-bravo.agents.config.sh" \
   "$ENG_PROJ/agents.config.sh"

ENG_OUT="$TMP/ac4-eng.out"
: > "$CLAUDE_LOG"
: > "$GH_LOG"
set +e
FLEET_NOW_OVERRIDE="2026-06-15T12:00:00Z" \
  bash "$REPO_ROOT/lib/eng.sh" "$ENG_PROJ" > "$ENG_OUT" 2>&1
ENG_EXIT=$?
set -e
if [ "$ENG_EXIT" -ne 0 ]; then
  echo "FAIL: AC#4 eng runner under active vacation want exit 0, got $ENG_EXIT"
  cat "$ENG_OUT"; exit 1
fi
if [ -s "$CLAUDE_LOG" ]; then
  echo "FAIL: AC#4 eng runner invoked claude on the suppress path"
  cat "$CLAUDE_LOG"; exit 1
fi
ENG_EVENTS="$HOME/.cache/vacbravo-agent/events.jsonl"
ENG_SKIP_N="$(awk '/"type":"vacation_skip"/ { n++ } END { print n+0 }' "$ENG_EVENTS")"
if [ "$ENG_SKIP_N" -ne 1 ]; then
  echo "FAIL: AC#4 want exactly 1 vacation_skip event from eng, got $ENG_SKIP_N"
  cat "$ENG_EVENTS"; exit 1
fi

# Multi-call dedup: call the helper twice in the SAME parent shell — second
# call returns the same verdict but emits NO new event.
rm -f "$HOME/.cache/vacalpha-agent/events.jsonl"
mkdir -p "$HOME/.cache/vacalpha-agent"
(
  set -euo pipefail
  # shellcheck disable=SC1091
  source "$REPO_ROOT/lib/common.sh"
  fleet_load_manifest "$SHIP_PROJ"
  FLEET_PHASE="ship"; export FLEET_PHASE
  FLEET_NOW_OVERRIDE="2026-06-15T12:00:00Z"; export FLEET_NOW_OVERRIDE
  # Call WITHOUT command substitution so the export persists.
  _fleet_check_vacation >/dev/null
  if [ "${FLEET_VACATION_VERDICT:-}" != "skip" ]; then
    echo "FAIL: AC#4 first _fleet_check_vacation verdict should be 'skip' (got '${FLEET_VACATION_VERDICT:-}')" >&2
    exit 1
  fi
  if [ -z "${FLEET_VACATION_SKIP_EMITTED:-}" ]; then
    echo "FAIL: AC#4 FLEET_VACATION_SKIP_EMITTED guard not set after first skip" >&2
    exit 1
  fi
  _fleet_check_vacation >/dev/null
  if [ "${FLEET_VACATION_VERDICT:-}" != "skip" ]; then
    echo "FAIL: AC#4 second _fleet_check_vacation verdict should still be 'skip'" >&2
    exit 1
  fi
)
DEDUP_EVENTS="$HOME/.cache/vacalpha-agent/events.jsonl"
DEDUP_SKIP_N="$(awk '/"type":"vacation_skip"/ { n++ } END { print n+0 }' "$DEDUP_EVENTS")"
if [ "$DEDUP_SKIP_N" -ne 1 ]; then
  echo "FAIL: AC#4 dedup: want exactly 1 vacation_skip event after two helper calls, got $DEDUP_SKIP_N"
  cat "$DEDUP_EVENTS"; exit 1
fi
echo "ok: AC#4 ship + eng suppress on active vacation, emit one vacation_skip each, dedup persists"

# ===========================================================================
# AC #5 — lib/review.sh and lib/groom.sh IGNORE the vacation state. The
# vacation state file's presence does not cause them to suppress.
# ===========================================================================
# We use a static-text contract here: review.sh and groom.sh must NOT
# call _fleet_check_vacation. (Running them end-to-end is awkward because
# review.sh polls and groom.sh shells out to claude; a source-level grep
# is the cheap, robust assertion that mirrors how AGENTS.md's "review is
# exempt" check is documented in tests/quiet-hours.sh.)
for f in lib/review.sh lib/groom.sh; do
  if grep -qF -- '_fleet_check_vacation' "$REPO_ROOT/$f"; then
    echo "FAIL: AC#5 $f must not call _fleet_check_vacation (vacation does not suspend review/groom)"
    exit 1
  fi
done
# And the helper itself must exist (a guard against accidentally
# removing the check from ship+eng).
if ! grep -qF -- '_fleet_check_vacation' "$REPO_ROOT/lib/common.sh"; then
  echo "FAIL: AC#5 lib/common.sh missing the _fleet_check_vacation helper"
  exit 1
fi
for f in lib/ship.sh lib/eng.sh; do
  if ! grep -qF -- '_fleet_check_vacation' "$REPO_ROOT/$f"; then
    echo "FAIL: AC#5 $f must call _fleet_check_vacation at PHASE 0"
    exit 1
  fi
done
echo "ok: AC#5 review.sh + groom.sh do not call _fleet_check_vacation; ship.sh + eng.sh do"

# ===========================================================================
# AC #6 — `fleet vacation --return` ends the suspension. Deletes the
# state file, runs launchctl bootout, emits one vacation_returned per
# suspended slug. forced=1 when manual, forced=0 when from auto-resume.
# ===========================================================================
reset_state
# Stage an active vacation suspending two slugs.
mkdir -p "$HOME/.cache/fleet" "$HOME/.cache/vacalpha-agent" "$HOME/.cache/vacbravo-agent"
cat > "$HOME/.cache/fleet/vacation-state" <<'STATE'
{"since":"2026-06-11T08:00:00Z","until":"2026-06-21T00:00:00Z","reason":"10-day trip","slugs_suspended":["vacalpha","vacbravo"]}
STATE
touch "$PLIST"
: > "$LAUNCHCTL_LOG"

set +e
FLEET_NOW_OVERRIDE="2026-06-15T18:00:00Z" \
  FLEET_DISCOVERY_ROOT="$DISCOVERY" \
  "$FLEET_BIN" vacation --return > "$TMP/ac6.out" 2>&1
AC6_EXIT=$?
set -e
if [ "$AC6_EXIT" -ne 0 ]; then
  echo "FAIL: AC#6 --return want exit 0, got $AC6_EXIT"
  cat "$TMP/ac6.out"; exit 1
fi
if [ -f "$HOME/.cache/fleet/vacation-state" ]; then
  echo "FAIL: AC#6 state file not deleted by --return"
  exit 1
fi
if ! grep -qF -- 'bootout' "$LAUNCHCTL_LOG"; then
  echo "FAIL: AC#6 launchctl bootout not invoked by --return"
  cat "$LAUNCHCTL_LOG"; exit 1
fi

# One vacation_returned event per slug, both with forced=1 (manual --return).
for slug in vacalpha vacbravo; do
  ev_file="$HOME/.cache/${slug}-agent/events.jsonl"
  if [ ! -f "$ev_file" ]; then
    echo "FAIL: AC#6 events.jsonl missing for $slug after --return"
    exit 1
  fi
  n="$(awk '/"type":"vacation_returned"/ { n++ } END { print n+0 }' "$ev_file")"
  if [ "$n" -ne 1 ]; then
    echo "FAIL: AC#6 want exactly 1 vacation_returned for $slug, got $n"
    cat "$ev_file"; exit 1
  fi
  node -e '
    const fs = require("fs");
    const lines = fs.readFileSync(process.argv[1], "utf8").split("\n").filter(Boolean);
    const ev = lines.map(JSON.parse).find(e => e.type === "vacation_returned");
    for (const k of ["since","duration_h","forced"]) {
      if (!(k in ev)) {
        console.error("FAIL: AC#6 vacation_returned missing key " + k + ": " + JSON.stringify(ev));
        process.exit(1);
      }
    }
    if (ev.forced !== "1") {
      console.error("FAIL: AC#6 manual --return should set forced=1, got " + ev.forced);
      process.exit(1);
    }
  ' "$ev_file"
done

# Auto-resume path: FLEET_VACATION_AUTO_RESUME=1 should set forced=0.
reset_state
mkdir -p "$HOME/.cache/fleet" "$HOME/.cache/vacalpha-agent"
cat > "$HOME/.cache/fleet/vacation-state" <<'STATE'
{"since":"2026-06-11T08:00:00Z","until":"2026-06-21T00:00:00Z","reason":"10-day trip","slugs_suspended":["vacalpha"]}
STATE
touch "$PLIST"
set +e
FLEET_NOW_OVERRIDE="2026-06-21T00:00:00Z" \
  FLEET_DISCOVERY_ROOT="$DISCOVERY" \
  FLEET_VACATION_AUTO_RESUME=1 \
  "$FLEET_BIN" vacation --return > "$TMP/ac6auto.out" 2>&1
AC6AUTO_EXIT=$?
set -e
if [ "$AC6AUTO_EXIT" -ne 0 ]; then
  echo "FAIL: AC#6 auto-resume --return want exit 0, got $AC6AUTO_EXIT"
  cat "$TMP/ac6auto.out"; exit 1
fi
AUTO_EV="$HOME/.cache/vacalpha-agent/events.jsonl"
node -e '
  const fs = require("fs");
  const lines = fs.readFileSync(process.argv[1], "utf8").split("\n").filter(Boolean);
  const ev = lines.map(JSON.parse).find(e => e.type === "vacation_returned");
  if (!ev) { console.error("FAIL: AC#6 no vacation_returned on auto-resume"); process.exit(1); }
  if (ev.forced !== "0") {
    console.error("FAIL: AC#6 auto-resume should set forced=0, got " + ev.forced);
    process.exit(1);
  }
' "$AUTO_EV"

echo "ok: AC#6 --return deletes state, bootouts plist, emits one vacation_returned per slug (forced=1 manual, forced=0 auto)"

# ===========================================================================
# AC #7 — `fleet vacation --status` prints active state OR
# "vacation: not active". Exit 0 always.
# ===========================================================================
reset_state
mkdir -p "$HOME/.cache/fleet"
cat > "$HOME/.cache/fleet/vacation-state" <<'STATE'
{"since":"2026-06-11T08:00:00Z","until":"2026-06-21T00:00:00Z","reason":"10-day trip, back Sat","slugs_suspended":["vacalpha","vacbravo"]}
STATE
set +e
FLEET_NOW_OVERRIDE="2026-06-15T08:00:00Z" \
  FLEET_DISCOVERY_ROOT="$DISCOVERY" \
  "$FLEET_BIN" vacation --status > "$TMP/ac7-active.out" 2>&1
AC7A_EXIT=$?
set -e
if [ "$AC7A_EXIT" -ne 0 ]; then
  echo "FAIL: AC#7 --status (active) want exit 0, got $AC7A_EXIT"
  cat "$TMP/ac7-active.out"; exit 1
fi
if ! grep -qF -- 'vacation:' "$TMP/ac7-active.out"; then
  echo "FAIL: AC#7 active --status missing 'vacation:' header"
  cat "$TMP/ac7-active.out"; exit 1
fi
if ! grep -qF -- '2026-06-21' "$TMP/ac7-active.out"; then
  echo "FAIL: AC#7 active --status missing until date"
  cat "$TMP/ac7-active.out"; exit 1
fi
if ! grep -qF -- '10-day trip' "$TMP/ac7-active.out"; then
  echo "FAIL: AC#7 active --status missing reason"
  cat "$TMP/ac7-active.out"; exit 1
fi

# Not-active branch.
rm -f "$HOME/.cache/fleet/vacation-state"
set +e
"$FLEET_BIN" vacation --status > "$TMP/ac7-none.out" 2>&1
AC7B_EXIT=$?
set -e
if [ "$AC7B_EXIT" -ne 0 ]; then
  echo "FAIL: AC#7 --status (none) want exit 0, got $AC7B_EXIT"
  cat "$TMP/ac7-none.out"; exit 1
fi
if ! grep -qF -- 'vacation: not active' "$TMP/ac7-none.out"; then
  echo "FAIL: AC#7 missing 'vacation: not active' banner"
  cat "$TMP/ac7-none.out"; exit 1
fi
echo "ok: AC#7 --status prints active briefing OR 'not active' (exit 0 both branches)"

# ===========================================================================
# AC #8 — `fleet vacation --help` mentions all four flags.
# ===========================================================================
set +e
"$FLEET_BIN" vacation --help > "$TMP/ac8.out" 2>&1
AC8_EXIT=$?
set -e
if [ "$AC8_EXIT" -ne 0 ]; then
  echo "FAIL: AC#8 --help want exit 0, got $AC8_EXIT"
  cat "$TMP/ac8.out"; exit 1
fi
for kw in --until --reason --return --status; do
  if ! grep -qF -- "$kw" "$TMP/ac8.out"; then
    echo "FAIL: AC#8 --help missing keyword $kw"
    cat "$TMP/ac8.out"; exit 1
  fi
done
echo "ok: AC#8 --help mentions --until, --reason, --return, --status"

# ===========================================================================
# AC #9 — State file path uses $HOME/.cache/fleet/ created via mkdir -p.
# (Asserted as a side effect of AC#2's successful path.)
# ===========================================================================
reset_state
# Wipe the fleet cache dir entirely so we can prove mkdir -p creates it.
rm -rf "$HOME/.cache/fleet"
set +e
FLEET_NOW_OVERRIDE="$NOW_TODAY" \
  FLEET_DISCOVERY_ROOT="$DISCOVERY" \
  "$FLEET_BIN" vacation --until "$UNTIL_OK" --reason "10-day trip" > "$TMP/ac9.out" 2>&1
AC9_EXIT=$?
set -e
if [ "$AC9_EXIT" -ne 0 ]; then
  echo "FAIL: AC#9 want exit 0, got $AC9_EXIT"
  cat "$TMP/ac9.out"; exit 1
fi
if [ ! -d "$HOME/.cache/fleet" ]; then
  echo "FAIL: AC#9 $HOME/.cache/fleet directory not created by mkdir -p"
  exit 1
fi
if [ ! -f "$HOME/.cache/fleet/vacation-state" ]; then
  echo "FAIL: AC#9 state file missing under newly-created fleet dir"
  exit 1
fi
echo "ok: AC#9 mkdir -p creates \$HOME/.cache/fleet/ for the state file"

# ===========================================================================
# AC #10 — Past --until refuses with exit 2 + banner. >90-day --until
# WARNS but proceeds (exit 0).
# ===========================================================================
reset_state
set +e
FLEET_NOW_OVERRIDE="$NOW_TODAY" \
  FLEET_DISCOVERY_ROOT="$DISCOVERY" \
  "$FLEET_BIN" vacation --until "$UNTIL_PAST" --reason "trip" > "$TMP/ac10past.out" 2>&1
AC10P_EXIT=$?
set -e
if [ "$AC10P_EXIT" -ne 2 ]; then
  echo "FAIL: AC#10 past --until want exit 2, got $AC10P_EXIT"
  cat "$TMP/ac10past.out"; exit 1
fi
if ! grep -qF -- 'is in the past' "$TMP/ac10past.out"; then
  echo "FAIL: AC#10 past --until missing 'is in the past' banner"
  cat "$TMP/ac10past.out"; exit 1
fi
if [ -f "$HOME/.cache/fleet/vacation-state" ]; then
  echo "FAIL: AC#10 past --until still wrote a state file"
  exit 1
fi

reset_state
: > "$LAUNCHCTL_LOG"
set +e
FLEET_NOW_OVERRIDE="$NOW_TODAY" \
  FLEET_DISCOVERY_ROOT="$DISCOVERY" \
  "$FLEET_BIN" vacation --until "$UNTIL_FAR" --reason "extended" > "$TMP/ac10far.out" 2> "$TMP/ac10far.err"
AC10F_EXIT=$?
set -e
if [ "$AC10F_EXIT" -ne 0 ]; then
  echo "FAIL: AC#10 far-future --until want exit 0 (warning, not refusal), got $AC10F_EXIT"
  cat "$TMP/ac10far.out"; cat "$TMP/ac10far.err"; exit 1
fi
if ! grep -qF -- 'warning' "$TMP/ac10far.err"; then
  echo "FAIL: AC#10 far-future --until missing stderr warning"
  cat "$TMP/ac10far.err"; exit 1
fi
if [ ! -f "$HOME/.cache/fleet/vacation-state" ]; then
  echo "FAIL: AC#10 far-future --until should still write the state file"
  exit 1
fi
echo "ok: AC#10 past --until refuses (exit 2); >90d --until warns but proceeds (exit 0)"

# ===========================================================================
# AC #11 — AGENTS.md § Telemetry documents both vacation_skip and
# vacation_returned with phase=vacation.
# ===========================================================================
AGENTS="$REPO_ROOT/AGENTS.md"
for typ in vacation_skip vacation_returned; do
  if ! grep -qF -- "$typ" "$AGENTS"; then
    echo "FAIL: AC#11 AGENTS.md missing event type $typ"
    exit 1
  fi
done
if ! grep -qF -- 'phase=vacation' "$AGENTS"; then
  echo "FAIL: AC#11 AGENTS.md must document phase=vacation"
  exit 1
fi
echo "ok: AC#11 AGENTS.md documents vacation_skip + vacation_returned with phase=vacation"

# ===========================================================================
# AC #12 — `lib/common.sh` gains an underscore-prefixed private helper
# (no break to the public fleet_* API). Public surface is unchanged:
# fleet_load_manifest, fleet_self_cancel, fleet_log_init, fleet_checkout,
# fleet_run_claude still exist as before.
# ===========================================================================
COMMON="$REPO_ROOT/lib/common.sh"
if ! grep -qE '^_fleet_check_vacation\(\)' "$COMMON"; then
  echo "FAIL: AC#12 lib/common.sh missing _fleet_check_vacation() definition"
  exit 1
fi
for pub in fleet_load_manifest fleet_self_cancel fleet_log_init fleet_checkout fleet_run_claude; do
  if ! grep -qE "^${pub}\(\)" "$COMMON"; then
    echo "FAIL: AC#12 public API broken — $pub() not found in lib/common.sh"
    exit 1
  fi
done
echo "ok: AC#12 _fleet_check_vacation added (underscore-prefixed); public fleet_* API intact"

echo
echo "all vacation.sh assertions passed."
