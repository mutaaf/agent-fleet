#!/bin/bash
# tests/resume.sh — bin/fleet resume end-to-end test against tmpdir fixtures.
#
# Ticket 0030. One assertion block per acceptance-criteria checkbox in
# docs/backlog/0030-fleet-resume-paused-slug.md (11 boxes).
#
# Strategy: stub `launchctl` under $HOME/.local/bin per LESSONS 2026-05-26
# (lib/common.sh resets PATH to put $HOME/.local/bin first; any stub
# elsewhere gets wiped the moment fleet_emit_event sources common.sh).
# The stub appends every invocation to $TMP/launchctl.log and reads
# $TMP/launchctl-state to simulate the agent-ship label state for
# `launchctl print` calls.
#
# Per LESSONS 2026-05-27, fixture content is copied via `cp` (never
# `$(cat …)`) so trailing newlines survive round-trips. The fixture
# events.jsonl files we write here use fresh `date -u +%FT%TZ` minus
# offsets so the 24h-window logic is deterministic.
#
# Per LESSONS 2026-05-30, all help-text greps use `grep -qF --` to dodge
# the BSD-grep dash-as-option trap. Per LESSONS 2026-06-01, the test
# never uses `grep -c … || echo 0` for integer accounting (the impl
# uses awk; the tests count lines via awk too).
#
# Per LESSONS 2026-06-01 (dispatcher fall-through), this test asserts
# that `fleet resume --help` emits ONLY the help block — no trailing
# `fleet status` table.

set -euo pipefail

REPO_ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
FLEET="$REPO_ROOT/bin/fleet"

TMP="$(mktemp -d -t fleet-resume-test.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

# Isolate from the host: HOME is the test's, all caches land under $TMP.
export HOME="$TMP/home"
mkdir -p "$HOME/.local/bin"

# Per LESSONS 2026-05-26: stubs MUST live under $HOME/.local/bin because
# lib/common.sh exports a hardcoded PATH with that dir first. A stub
# anywhere else gets shadowed.
STUB_DIR="$HOME/.local/bin"
LAUNCHCTL_LOG="$TMP/launchctl.log"
LAUNCHCTL_STATE="$TMP/launchctl-state"   # "enabled" | "disabled"
: > "$LAUNCHCTL_LOG"
echo "disabled" > "$LAUNCHCTL_STATE"

cat > "$STUB_DIR/launchctl" <<STUB
#!/bin/bash
# Test stub. Records argv (one line) to the log, then dispatches based
# on the first arg.
printf '%s\n' "launchctl \$*" >> "$LAUNCHCTL_LOG"
state=\$(cat "$LAUNCHCTL_STATE" 2>/dev/null || echo "disabled")
case "\${1:-}" in
  print)
    # Emulate "launchctl print gui/UID/label" output — only the state
    # line is read by resume_label_state.
    printf 'com.example.agent-ship = {\n\tstate = %s\n}\n' "\$state"
    exit 0
    ;;
  enable)
    # Honour LAUNCHCTL_ENABLE_NOFLIP=1 to simulate the rare "enable
    # returned 0 but the label is still disabled" scenario (AC#10).
    if [ "\${LAUNCHCTL_ENABLE_NOFLIP:-0}" != "1" ]; then
      echo "enabled" > "$LAUNCHCTL_STATE"
    fi
    exit 0
    ;;
  *)
    exit 0
    ;;
esac
STUB
chmod +x "$STUB_DIR/launchctl"

# Make sure $HOME/.local/bin is on PATH for the bin/fleet call too. (bin/fleet
# does NOT source common.sh on its top-level path, but resume() does — and
# the stub must be visible to both.)
export PATH="$STUB_DIR:$PATH"

FIXTURE="$TMP/projects"
mkdir -p "$FIXTURE"
cp -R "$REPO_ROOT/tests/fixtures/resume/clear-streak"  "$FIXTURE/clear-streak"
cp -R "$REPO_ROOT/tests/fixtures/resume/active-streak" "$FIXTURE/active-streak"

# Per LESSONS 2026-05-27: rewrite events.jsonl with fresh epoch math so
# the 24h-window logic in resume_sendback_count_24h is deterministic
# regardless of the host's wallclock at test time.
now_epoch="$(date -u +%s)"
ts_at() {  # offset_seconds_back → ISO8601 UTC
  local off="$1" ep
  ep=$(( now_epoch - off ))
  date -u -r "$ep" +%FT%TZ 2>/dev/null || date -u -d "@$ep" +%FT%TZ
}
# clear-streak: one ship_paused 23h ago, zero lesson_draft_emitted.
PAUSED_TS_CLEAR="$(ts_at $(( 23 * 3600 )))"
{
  printf '{"ts":"%s","slug":"clear-streak","phase":"ship","type":"ship_paused","reason":"sendback_streak","count":"3","prs":"55,56,57"}\n' \
    "$PAUSED_TS_CLEAR"
} > "$FIXTURE/clear-streak/events.jsonl"

# active-streak: one ship_paused 23h ago, three lesson_draft_emitted in the
# last 24h (5h, 12h, 20h ago).
PAUSED_TS_ACTIVE="$(ts_at $(( 23 * 3600 )))"
{
  printf '{"ts":"%s","slug":"active-streak","phase":"ship","type":"ship_paused","reason":"sendback_streak","count":"3","prs":"77,78,79"}\n' \
    "$PAUSED_TS_ACTIVE"
  printf '{"ts":"%s","slug":"active-streak","phase":"review","type":"lesson_draft_emitted","pr":"77","headline":"flaky test"}\n' \
    "$(ts_at $(( 20 * 3600 )))"
  printf '{"ts":"%s","slug":"active-streak","phase":"review","type":"lesson_draft_emitted","pr":"78","headline":"race condition"}\n' \
    "$(ts_at $(( 12 * 3600 )))"
  printf '{"ts":"%s","slug":"active-streak","phase":"review","type":"lesson_draft_emitted","pr":"79","headline":"port collision"}\n' \
    "$(ts_at $(( 5  * 3600 )))"
} > "$FIXTURE/active-streak/events.jsonl"

export FLEET_DISCOVERY_ROOT="$FIXTURE"

# Per-slug caches (where new events.jsonl appends will land — bin/fleet's
# resume helper writes to $HOME/.cache/<slug>-agent/events.jsonl, the
# same convention every fleet_emit_event consumer uses).
mkdir -p "$HOME/.cache/clear-streak-agent" "$HOME/.cache/active-streak-agent"
# Pre-seed the cache events.jsonl with the SAME content as the fixture so
# resume_paused_for and resume_sendback_count_24h see them.
cp "$FIXTURE/clear-streak/events.jsonl"  "$HOME/.cache/clear-streak-agent/events.jsonl"
cp "$FIXTURE/active-streak/events.jsonl" "$HOME/.cache/active-streak-agent/events.jsonl"

CLEAR_EVENTS="$HOME/.cache/clear-streak-agent/events.jsonl"
ACTIVE_EVENTS="$HOME/.cache/active-streak-agent/events.jsonl"

# Helper: copy of the original cache file so we can restore between test
# blocks without `$(cat …)` (LESSONS 2026-05-27).
CLEAR_BACKUP="$TMP/clear-events.bak.jsonl"
ACTIVE_BACKUP="$TMP/active-events.bak.jsonl"
cp "$CLEAR_EVENTS"  "$CLEAR_BACKUP"
cp "$ACTIVE_EVENTS" "$ACTIVE_BACKUP"

reset_clear() {
  cp "$CLEAR_BACKUP" "$CLEAR_EVENTS"
  : > "$LAUNCHCTL_LOG"
  echo "disabled" > "$LAUNCHCTL_STATE"
  unset LAUNCHCTL_ENABLE_NOFLIP
}
reset_active() {
  cp "$ACTIVE_BACKUP" "$ACTIVE_EVENTS"
  : > "$LAUNCHCTL_LOG"
  echo "disabled" > "$LAUNCHCTL_STATE"
  unset LAUNCHCTL_ENABLE_NOFLIP
}

# Count `ship_resumed` events in a slug's cache events.jsonl. Per
# LESSONS 2026-06-01, use awk — never `grep -c … || echo 0`.
count_resumed() {
  local f="$1"
  [ -f "$f" ] || { echo 0; return 0; }
  awk '/"type":"ship_resumed"/ { n++ } END { print (n+0) }' "$f"
}

# Extract the LAST ship_resumed line from a slug's cache events.jsonl.
last_resumed_line() {
  local f="$1"
  [ -f "$f" ] || return 0
  awk '/"type":"ship_resumed"/ { line = $0 } END { print line }' "$f"
}

# ========================================================================
# AC#1 — Happy path: disabled label + zero lesson_draft_emitted in 24h →
#        runs launchctl enable, verifies state flipped, emits one
#        ship_resumed event, exits 0, prints the success block.
# ========================================================================
reset_clear
set +e
OUT="$("$FLEET" resume clear-streak 2>&1)"
RC=$?
set -e
if [ "$RC" -ne 0 ]; then
  echo "FAIL: AC#1 expected exit 0, got $RC"
  echo "$OUT"; cat "$LAUNCHCTL_LOG"; exit 1
fi
if ! grep -qE 'launchctl enable .*\.agent-ship' "$LAUNCHCTL_LOG"; then
  echo "FAIL: AC#1 expected 'launchctl enable …agent-ship' in stub log"
  cat "$LAUNCHCTL_LOG"; exit 1
fi
if ! grep -qE 'launchctl print .*\.agent-ship' "$LAUNCHCTL_LOG"; then
  echo "FAIL: AC#1 expected at least one 'launchctl print' verification call"
  cat "$LAUNCHCTL_LOG"; exit 1
fi
if [ "$(count_resumed "$CLEAR_EVENTS")" -ne 1 ]; then
  echo "FAIL: AC#1 expected exactly 1 ship_resumed event"
  cat "$CLEAR_EVENTS"; exit 1
fi
# Output block shape (loose grep — we don't pin every word; tickets
# describe the spirit, not byte-exact strings).
for needle in 'checking pause cause' 'agent-ship label state' 'verified' 'emitted ship_resumed'; do
  if ! grep -qF -- "$needle" <<<"$OUT"; then
    echo "FAIL: AC#1 output missing fragment '$needle'"
    echo "$OUT"; exit 1
  fi
done
echo "ok: AC#1 happy-path resume enables + verifies + emits event"

# ========================================================================
# AC#2 — Already-enabled label: idempotent no-op. No `launchctl enable`,
#        no ship_resumed event, exit 0, message says "not paused".
# ========================================================================
reset_clear
echo "enabled" > "$LAUNCHCTL_STATE"
set +e
OUT="$("$FLEET" resume clear-streak 2>&1)"
RC=$?
set -e
if [ "$RC" -ne 0 ]; then
  echo "FAIL: AC#2 expected exit 0 on already-enabled, got $RC"; echo "$OUT"; exit 1
fi
if grep -qE 'launchctl enable ' "$LAUNCHCTL_LOG"; then
  echo "FAIL: AC#2 must NOT call 'launchctl enable' when already enabled"
  cat "$LAUNCHCTL_LOG"; exit 1
fi
if [ "$(count_resumed "$CLEAR_EVENTS")" -ne 0 ]; then
  echo "FAIL: AC#2 already-enabled must NOT emit ship_resumed"
  cat "$CLEAR_EVENTS"; exit 1
fi
if ! grep -qF -- 'not paused' <<<"$OUT"; then
  echo "FAIL: AC#2 expected 'not paused' message"; echo "$OUT"; exit 1
fi
echo "ok: AC#2 already-enabled is an idempotent no-op"

# ========================================================================
# AC#3 — Disabled label + >=3 lesson_draft_emitted in last 24h → REFUSE.
#        Prints REFUSING block to stderr, exit 2, no enable, no event.
# ========================================================================
reset_active
set +e
OUT_ALL="$("$FLEET" resume active-streak 2>&1)"
RC=$?
ERR_ONLY="$("$FLEET" resume active-streak 2>&1 >/dev/null)"
set -e
if [ "$RC" -ne 2 ]; then
  echo "FAIL: AC#3 expected exit 2 on active streak, got $RC"
  echo "$OUT_ALL"; exit 1
fi
if grep -qE 'launchctl enable ' "$LAUNCHCTL_LOG"; then
  echo "FAIL: AC#3 must NOT call 'launchctl enable' when streak is active"
  cat "$LAUNCHCTL_LOG"; exit 1
fi
if [ "$(count_resumed "$ACTIVE_EVENTS")" -ne 0 ]; then
  echo "FAIL: AC#3 must NOT emit ship_resumed on refusal"
  cat "$ACTIVE_EVENTS"; exit 1
fi
if ! grep -qF -- 'REFUSING' <<<"$ERR_ONLY"; then
  echo "FAIL: AC#3 expected 'REFUSING' on stderr"; echo "$ERR_ONLY"; exit 1
fi
if ! grep -qF -- 'send-backs in the last 24h' <<<"$ERR_ONLY"; then
  echo "FAIL: AC#3 expected the send-back count phrase on stderr"
  echo "$ERR_ONLY"; exit 1
fi
echo "ok: AC#3 active streak refuses with exit 2"

# ========================================================================
# AC#4 — `--force --reason "<text>"` bypasses the streak check, proceeds,
#        ship_resumed carries forced=1 and reason=<text>.
# ========================================================================
reset_active
REASON="manual override after triage"
set +e
OUT="$("$FLEET" resume active-streak --force --reason "$REASON" 2>&1)"
RC=$?
set -e
if [ "$RC" -ne 0 ]; then
  echo "FAIL: AC#4 --force --reason expected exit 0, got $RC"; echo "$OUT"; exit 1
fi
if ! grep -qE 'launchctl enable ' "$LAUNCHCTL_LOG"; then
  echo "FAIL: AC#4 --force must reach 'launchctl enable'"; cat "$LAUNCHCTL_LOG"; exit 1
fi
if [ "$(count_resumed "$ACTIVE_EVENTS")" -ne 1 ]; then
  echo "FAIL: AC#4 expected exactly 1 ship_resumed event"; cat "$ACTIVE_EVENTS"; exit 1
fi
LAST_LINE="$(last_resumed_line "$ACTIVE_EVENTS")"
if ! grep -qF -- '"forced":"1"' <<<"$LAST_LINE"; then
  echo "FAIL: AC#4 event missing 'forced=1'"; echo "$LAST_LINE"; exit 1
fi
if ! grep -qF -- "\"reason\":\"$REASON\"" <<<"$LAST_LINE"; then
  echo "FAIL: AC#4 event missing the --reason value"; echo "$LAST_LINE"; exit 1
fi
echo "ok: AC#4 --force --reason bypasses streak with audit fields set"

# ========================================================================
# AC#5 — `--force` without `--reason` is rejected (auditable override).
#        Exit 2 + stderr message naming both flags.
# ========================================================================
reset_active
set +e
ERR="$("$FLEET" resume active-streak --force 2>&1 >/dev/null)"
RC=$?
set -e
if [ "$RC" -ne 2 ]; then
  echo "FAIL: AC#5 --force w/o --reason expected exit 2, got $RC"; echo "$ERR"; exit 1
fi
if ! grep -qF -- '--force requires --reason' <<<"$ERR"; then
  echo "FAIL: AC#5 stderr must say '--force requires --reason'"
  echo "$ERR"; exit 1
fi
if [ "$(count_resumed "$ACTIVE_EVENTS")" -ne 0 ]; then
  echo "FAIL: AC#5 missing-reason refusal must NOT emit ship_resumed"; exit 1
fi
echo "ok: AC#5 --force without --reason refuses"

# ========================================================================
# AC#6 — `--reason "-leading-dash"` is accepted and renders correctly in
#        stdout AND in the emitted event payload (printf '%s' trap,
#        LESSONS 2026-05-28).
# ========================================================================
reset_active
DASH_REASON="-streak was a false positive"
set +e
OUT="$("$FLEET" resume active-streak --force --reason "$DASH_REASON" 2>&1)"
RC=$?
set -e
if [ "$RC" -ne 0 ]; then
  echo "FAIL: AC#6 leading-dash reason expected exit 0, got $RC"; echo "$OUT"; exit 1
fi
if ! grep -qF -- "$DASH_REASON" <<<"$OUT"; then
  echo "FAIL: AC#6 stdout did not echo the leading-dash reason verbatim"
  echo "$OUT"; exit 1
fi
LAST_LINE="$(last_resumed_line "$ACTIVE_EVENTS")"
if ! grep -qF -- "\"reason\":\"$DASH_REASON\"" <<<"$LAST_LINE"; then
  echo "FAIL: AC#6 event payload missing leading-dash reason verbatim"
  echo "$LAST_LINE"; exit 1
fi
echo "ok: AC#6 leading-dash --reason value survives printf and event payload"

# ========================================================================
# AC#7 — Default-path ship_resumed payload: source=<slug>,
#        paused_for=<human age>, reason="streak cleared", forced=0.
#        paused_for comes from the most recent ship_paused event ts.
# ========================================================================
reset_clear
"$FLEET" resume clear-streak >/dev/null 2>&1
LAST_LINE="$(last_resumed_line "$CLEAR_EVENTS")"
for needle in '"type":"ship_resumed"' '"phase":"resume"' '"source":"clear-streak"' '"forced":"0"' '"reason":"streak cleared"'; do
  if ! grep -qF -- "$needle" <<<"$LAST_LINE"; then
    echo "FAIL: AC#7 event payload missing '$needle'"; echo "$LAST_LINE"; exit 1
  fi
done
# paused_for should be NON-EMPTY and not "unknown" (we wrote a 23h-old
# ship_paused). Human-formatted -- accept "h" or "d" suffix.
if ! grep -qE '"paused_for":"[0-9]+[hdm][a-z ]*"' <<<"$LAST_LINE"; then
  echo "FAIL: AC#7 paused_for should be a human-age string (e.g. 23h)"
  echo "$LAST_LINE"; exit 1
fi
echo "ok: AC#7 ship_resumed payload shape (default path)"

# ========================================================================
# AC#8 — AGENTS.md § Telemetry has a new bullet for ship_resumed.
# ========================================================================
if ! grep -qF -- 'ship_resumed' "$REPO_ROOT/AGENTS.md"; then
  echo "FAIL: AC#8 AGENTS.md missing 'ship_resumed' bullet"; exit 1
fi
if ! grep -qF -- 'paused_for' "$REPO_ROOT/AGENTS.md"; then
  echo "FAIL: AC#8 AGENTS.md ship_resumed bullet should name 'paused_for'"; exit 1
fi
echo "ok: AC#8 AGENTS.md § Telemetry lists ship_resumed"

# ========================================================================
# AC#9 — Unknown slug → "no project with SLUG=<slug> found" on stderr,
#        exit 2.
# ========================================================================
set +e
ERR="$("$FLEET" resume no-such-slug 2>&1 >/dev/null)"
RC=$?
set -e
if [ "$RC" -ne 2 ]; then
  echo "FAIL: AC#9 unknown slug expected exit 2, got $RC"; echo "$ERR"; exit 1
fi
if ! grep -qF -- 'no project with SLUG=no-such-slug found' <<<"$ERR"; then
  echo "FAIL: AC#9 stderr missing 'no project with SLUG=… found'"
  echo "$ERR"; exit 1
fi
echo "ok: AC#9 unknown slug refuses with exit 2"

# ========================================================================
# AC#10 — launchctl verify-failure: enable returns 0 but print still
#         reads disabled. Exit 1, no ship_resumed, named error on stderr.
# ========================================================================
reset_clear
export LAUNCHCTL_ENABLE_NOFLIP=1
set +e
ERR="$("$FLEET" resume clear-streak 2>&1 >/dev/null)"
RC=$?
set -e
unset LAUNCHCTL_ENABLE_NOFLIP
if [ "$RC" -ne 1 ]; then
  echo "FAIL: AC#10 verify-failure expected exit 1, got $RC"; echo "$ERR"; exit 1
fi
if ! grep -qF -- 'still disabled' <<<"$ERR"; then
  echo "FAIL: AC#10 stderr missing 'still disabled' diagnostic"
  echo "$ERR"; exit 1
fi
if [ "$(count_resumed "$CLEAR_EVENTS")" -ne 0 ]; then
  echo "FAIL: AC#10 verify-failure must NOT emit ship_resumed"; exit 1
fi
echo "ok: AC#10 verify-failure exits 1 without emitting ship_resumed"

# ========================================================================
# AC#11 — `fleet resume --help` prints USAGE with --force, --reason,
#         --help. Uses `grep -qF --` per LESSONS 2026-05-30.
#         Help block alone — no fall-through to status table per
#         LESSONS 2026-06-01.
# ========================================================================
HELP_OUT="$TMP/resume-help.out"
"$FLEET" resume --help > "$HELP_OUT" 2>&1
for kw in '--force' '--reason' '--help'; do
  if ! grep -qF -- "$kw" "$HELP_OUT"; then
    echo "FAIL: AC#11 help missing keyword '$kw'"; cat "$HELP_OUT"; exit 1
  fi
done
# Dispatcher fall-through trap: help must NOT print the status table
# header (`PROJECT INSTALLED LAST RUN PRS LESSONS SELF-CANCEL`).
if grep -qE 'PROJECT.*INSTALLED.*LAST RUN.*PRS.*LESSONS.*SELF-CANCEL' "$HELP_OUT"; then
  echo "FAIL: AC#11 help block fell through to fleet status table"
  cat "$HELP_OUT"; exit 1
fi
echo "ok: AC#11 --help prints USAGE w/o fall-through"

echo
echo "all 11 ACs passed."
exit 0
