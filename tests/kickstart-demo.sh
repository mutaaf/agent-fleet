#!/bin/bash
# tests/kickstart-demo.sh — fleet kickstart --demo (ticket 0023).
#
# One assertion block per acceptance-criteria checkbox in
# docs/backlog/0023-fleet-kickstart-demo-credless-loop.md. Strategy:
#
#   * Re-root $HOME under a temp dir per LESSONS 2026-05-26 so neither the
#     demo's stubs nor its cache touch the host's real ~/.local/bin or
#     ~/.cache. Per the same lesson, stubs MUST live in $HOME/.local/bin —
#     `lib/common.sh` resets PATH to `$HOME/.local/bin:/opt/homebrew/bin:...`
#     on source, so any stub placed elsewhere evaporates the moment the
#     demo's `kickstart_demo` sources common.sh.
#
#   * Install stubbed `gh`, `claude`, `git-push-stub` BEFORE invoking the
#     demo (the demo itself also installs them — we pre-install to assert
#     the demo's own install is idempotent and to leave a wrapper that
#     records argv to a log so we can detect any "real" call attempt).
#
#   * Set PATH=`$HOME/.local/bin` exclusively at invocation. The demo's
#     own source of common.sh will restore the rest of PATH; the stubs at
#     the front of PATH still win for `gh`/`claude`/`git`-push.
#
#   * No `jq` dependency for assertions — events.jsonl is parsed with
#     plain `grep -c '"type":"<t>"'` per AC#4.

set -euo pipefail

REPO_ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
FLEET="$REPO_ROOT/bin/fleet"

TMP="$(mktemp -d -t fleet-demo-test.XXXXXX)"
trap 'rm -rf "$TMP" 2>/dev/null || true' EXIT

# Re-root HOME (per LESSONS 2026-05-26).
export HOME="$TMP/home"
mkdir -p "$HOME/.local/bin"

# Cache PATH for invocations.
EXCLUSIVE_PATH="$HOME/.local/bin"
SYSTEM_PATH="$PATH"

# ------------------------------------------------------------------------
# Pre-install host-side stubs so we can record any errant "real"-tool
# invocation. The demo will also install its own stubs (overwriting these
# unconditionally — that's the test of AC#3's stub-install contract).
# We keep a separate argv log under $TMP so we can tell whether the demo
# replaced the wrapper or just used ours.
# ------------------------------------------------------------------------
HOST_LOG="$TMP/host-stubs.log"
: > "$HOST_LOG"

for binname in gh claude git; do
  cat > "$HOME/.local/bin/$binname" <<STUB
#!/bin/bash
# pre-test host stub for $binname — overwritten by the demo on first run.
printf 'host-stub:%s %s\n' "$binname" "\$*" >> "$HOST_LOG"
exit 0
STUB
  chmod +x "$HOME/.local/bin/$binname"
done

# ========================================================================
# Run the demo once under exclusive PATH and capture stdout for the rest
# of the assertions. AC#1 + AC#7 share this invocation.
# ========================================================================
run_demo() {
  # $@ = extra flags (--tail N, --keep, etc.). Returns demo exit code.
  # Stdout captured to $TMP/demo.out; stderr merged.
  PATH="$EXCLUSIVE_PATH" \
    HOME="$HOME" \
    FLEET_DEMO_FORCE_FAIL="${FLEET_DEMO_FORCE_FAIL:-}" \
    "$FLEET" kickstart --demo "$@" >"$TMP/demo.out" 2>&1
}

# Default-flagless run.
demo_start_epoch=$(date -u +%s)
run_demo || {
  echo "FAIL: AC#1 fleet kickstart --demo returned non-zero"
  echo "--- demo stdout ---"; cat "$TMP/demo.out"
  exit 1
}
demo_end_epoch=$(date -u +%s)
demo_wall=$(( demo_end_epoch - demo_start_epoch ))

# ========================================================================
# AC #1 — exits 0 in <90s and prints the final "[demo] done." line.
# ========================================================================
if [ "$demo_wall" -gt 90 ]; then
  echo "FAIL: AC#1 wallclock $demo_wall s exceeds 90s budget"
  exit 1
fi
if ! grep -q '^\[demo\] done\.' "$TMP/demo.out"; then
  echo "FAIL: AC#1 expected a final '[demo] done.' line in stdout"
  echo "--- demo stdout ---"; cat "$TMP/demo.out"
  exit 1
fi
echo "ok: AC#1 fleet kickstart --demo exit=0 in ${demo_wall}s with done. line"

# ========================================================================
# AC #2 — fixture has the right files under a mktemp-d -t fleet-demo dir.
# ========================================================================
# The demo prints the fixture path twice (start + end). Grep it out.
FIXTURE_PATH="$(grep -oE '/[^ ]*fleet-demo[A-Za-z0-9._-]+' "$TMP/demo.out" | head -1)"
if [ -z "$FIXTURE_PATH" ]; then
  echo "FAIL: AC#2 could not find a fleet-demo* fixture path in stdout"
  cat "$TMP/demo.out"
  exit 1
fi
# Default behaviour wipes the fixture on normal exit, so we re-run with
# --keep below for the file-presence checks. But we DO assert here that
# the path is under $TMPDIR (or /tmp/ if TMPDIR is empty) — the demo
# must never write outside $TMPDIR.
case "$FIXTURE_PATH" in
  /tmp/*|/private/tmp/*|/var/folders/*) ;;
  *)
    if [ -n "${TMPDIR:-}" ]; then
      case "$FIXTURE_PATH" in
        "$TMPDIR"*|"${TMPDIR%/}"/*) ;;
        *) echo "FAIL: AC#2 fixture path $FIXTURE_PATH outside \$TMPDIR ($TMPDIR)"; exit 1 ;;
      esac
    else
      echo "FAIL: AC#2 fixture path $FIXTURE_PATH outside /tmp/, /private/tmp/, /var/folders/"
      exit 1
    fi
    ;;
esac

# Run again with --keep so we can inspect the fixture files.
run_demo --keep
KEEP_FIXTURE="$(grep -oE '/[^ ]*fleet-demo[A-Za-z0-9._-]+' "$TMP/demo.out" | head -1)"
if [ -z "$KEEP_FIXTURE" ] || [ ! -d "$KEEP_FIXTURE" ]; then
  echo "FAIL: AC#2 --keep should leave fixture on disk; got '$KEEP_FIXTURE'"
  exit 1
fi
for f in AGENTS.md agents.config.sh docs/backlog/README.md \
         docs/backlog/0001-demo-hello-world.md \
         docs/backlog/0002-demo-second-ticket.md \
         docs/LESSONS.md; do
  if [ ! -f "$KEEP_FIXTURE/$f" ]; then
    echo "FAIL: AC#2 fixture missing $f"
    ls -R "$KEEP_FIXTURE"
    exit 1
  fi
done
# Ticket statuses: 0001 groomed, 0002 proposed.
if ! grep -q '^status: groomed' "$KEEP_FIXTURE/docs/backlog/0001-demo-hello-world.md"; then
  echo "FAIL: AC#2 0001 ticket must be status: groomed"
  exit 1
fi
if ! grep -q '^status: proposed' "$KEEP_FIXTURE/docs/backlog/0002-demo-second-ticket.md"; then
  echo "FAIL: AC#2 0002 ticket must be status: proposed"
  exit 1
fi
echo "ok: AC#2 fixture under \$TMPDIR has manifest, AGENTS.md, two tickets, LESSONS"

# ========================================================================
# AC #3 — stubs installed in $HOME/.local/bin and removed on normal exit.
# ========================================================================
# We just finished a non-keep run (which cleaned up its fixture and its
# stubs). Confirm the stubs are gone — but only the ones the demo
# claims to install (gh, claude, git-push-stub). The host pre-stubs we
# wrote are part of OUR fixture, not the demo's, so we re-install them
# at the start of each block that needs them.
#
# To assert the demo DOES install its stubs during the run, we use the
# fact that the previous keep-run also left the demo's own stubs behind
# (--keep should preserve stubs too — the operator wants to inspect).
# But the engineering notes are silent on whether --keep preserves
# stubs. Safer: assert the cleanup happens via a separate dedicated
# run that captures stubs mid-flight via a marker the demo writes
# alongside them. We rely on the demo printing the stub dir at start.
if ! grep -q 'stubs in' "$TMP/demo.out"; then
  echo "FAIL: AC#3 demo must announce the stub directory in stdout"
  cat "$TMP/demo.out"
  exit 1
fi
# Re-run with --keep AND --tail 0 to get a deterministic snapshot, then
# assert that gh/claude/git-push-stub all exist as files inside HOME's
# .local/bin at the moment the demo exits.
run_demo --keep
for s in gh claude git-push-stub; do
  if [ ! -x "$HOME/.local/bin/$s" ]; then
    echo "FAIL: AC#3 demo did not install executable stub $HOME/.local/bin/$s"
    ls -la "$HOME/.local/bin/"
    exit 1
  fi
done
# Now run without --keep; the stubs MUST be cleaned up by the demo's
# trap. We re-pre-install host stubs first so we can tell the demo's
# cleanup from "stub was never there". The demo's cleanup must remove
# its own stubs — leaving the host's behind would be polite, but the
# AC says "deleted on normal exit". We accept either: post-run, the
# files are either absent OR they're a different shape than the demo's
# (i.e. our pre-test host stubs).
for binname in gh claude git-push-stub; do
  cat > "$HOME/.local/bin/$binname" <<STUB
#!/bin/bash
echo "host-stub:$binname"
exit 0
STUB
  chmod +x "$HOME/.local/bin/$binname"
done
run_demo
# After cleanup: either the stubs are removed entirely OR they're the
# original host stubs. The demo must NOT leave its own stubs behind.
for binname in gh claude git-push-stub; do
  if [ -e "$HOME/.local/bin/$binname" ]; then
    if ! grep -q "host-stub:$binname" "$HOME/.local/bin/$binname"; then
      echo "FAIL: AC#3 demo did not remove its $binname stub on normal exit"
      cat "$HOME/.local/bin/$binname"
      exit 1
    fi
  fi
done
echo "ok: AC#3 stubs installed in \$HOME/.local/bin and removed on exit"

# ========================================================================
# AC #4 — emits 4 event types each EXACTLY once to events.jsonl under the
#         demo cache.
# ========================================================================
# Re-run with --keep so events.jsonl survives for inspection. The cache
# dir is derived from the fixture's agents.config.sh — the demo prints
# its location with a "[demo] events at <path>" line per the user-story
# block. Find it via grep, then inspect.
run_demo --keep
EVENTS_PATH="$(grep -oE '/[^ ]*events\.jsonl' "$TMP/demo.out" | head -1)"
if [ -z "$EVENTS_PATH" ] || [ ! -f "$EVENTS_PATH" ]; then
  echo "FAIL: AC#4 could not locate events.jsonl in demo stdout"
  cat "$TMP/demo.out"
  exit 1
fi
for ty in run_started pr_opened lesson_draft_emitted run_completed; do
  count=$(grep -c "\"type\":\"$ty\"" "$EVENTS_PATH" || true)
  if [ "$count" != "1" ]; then
    echo "FAIL: AC#4 expected exactly 1 '$ty' event, got $count"
    echo "--- events.jsonl ---"; cat "$EVENTS_PATH"
    exit 1
  fi
done
# Schema sanity: every line carries ts/slug/phase/type per AGENTS.md.
while IFS= read -r line; do
  for required in '"ts":' '"slug":' '"phase":' '"type":'; do
    if ! printf '%s' "$line" | grep -qF -- "$required"; then
      echo "FAIL: AC#4 event missing $required key"
      echo "line: $line"
      exit 1
    fi
  done
done < "$EVENTS_PATH"
# phase=demo on every event (the demo runs under FLEET_PHASE=demo).
demo_phase_count=$(grep -c '"phase":"demo"' "$EVENTS_PATH" || true)
total_events=$(wc -l < "$EVENTS_PATH" | tr -d ' ')
if [ "$demo_phase_count" != "$total_events" ]; then
  echo "FAIL: AC#4 expected every event to carry phase=demo ($demo_phase_count of $total_events do)"
  cat "$EVENTS_PATH"
  exit 1
fi
echo "ok: AC#4 events.jsonl has all 4 required types, all phase=demo, all four-key schema"

# ========================================================================
# AC #5 — --tail keeps streaming for the extra window; without --tail the
#         events print once at end of run. We use `--tail 1` (1s window)
#         for speed — the AC explicitly allows shorter for tests.
# ========================================================================
run_demo --tail 1
# In --tail mode the demo should print a "tailing" marker.
if ! grep -qE '\[demo\] tailing' "$TMP/demo.out"; then
  echo "FAIL: AC#5 --tail must print a '[demo] tailing' marker"
  cat "$TMP/demo.out"
  exit 1
fi
# Without --tail, NO tailing marker should appear.
run_demo
if grep -qE '\[demo\] tailing' "$TMP/demo.out"; then
  echo "FAIL: AC#5 plain --demo (no --tail) must NOT print a tailing marker"
  cat "$TMP/demo.out"
  exit 1
fi
# But it SHOULD still print the events at end-of-run.
if ! grep -q '"type":"run_started"' "$TMP/demo.out"; then
  echo "FAIL: AC#5 plain --demo must echo the events.jsonl contents at end of run"
  cat "$TMP/demo.out"
  exit 1
fi
echo "ok: AC#5 --tail streams; plain mode echoes events at end of run"

# ========================================================================
# AC #6 — --keep skips cleanup; default wipes. Sentinel file proves it.
# ========================================================================
run_demo --keep
KEEP_FIXTURE="$(grep -oE '/[^ ]*fleet-demo[A-Za-z0-9._-]+' "$TMP/demo.out" | head -1)"
if [ -z "$KEEP_FIXTURE" ] || [ ! -d "$KEEP_FIXTURE" ]; then
  echo "FAIL: AC#6 --keep should leave fixture on disk"
  exit 1
fi
# Write a sentinel into the kept fixture, then run a non-keep demo; the
# kept fixture's sentinel must still be there (the new demo writes to a
# DIFFERENT mktemp dir and only cleans up its own).
echo "kept-sentinel" > "$KEEP_FIXTURE/sentinel.txt"
run_demo
if [ ! -f "$KEEP_FIXTURE/sentinel.txt" ]; then
  echo "FAIL: AC#6 a plain --demo run wiped a different --keep fixture's sentinel"
  exit 1
fi
# Now the inverse: a plain --demo run's fixture must NOT survive after exit.
PLAIN_FIXTURE="$(grep -oE '/[^ ]*fleet-demo[A-Za-z0-9._-]+' "$TMP/demo.out" | head -1)"
if [ -d "$PLAIN_FIXTURE" ]; then
  echo "FAIL: AC#6 plain --demo did not clean up its fixture at $PLAIN_FIXTURE"
  exit 1
fi
echo "ok: AC#6 --keep preserves fixture; default wipes only its own"

# ========================================================================
# AC #7 — demo NEVER calls real gh/git/claude. PATH=$HOME/.local/bin only
#         at invocation; demo still succeeds. We re-install fresh host
#         stubs that LOG every call so any "real-tool" attempt is caught.
# ========================================================================
ARGV_LOG="$TMP/argv.log"
: > "$ARGV_LOG"
for binname in gh claude; do
  cat > "$HOME/.local/bin/$binname" <<STUB
#!/bin/bash
printf 'host-pre:%s %s\n' "$binname" "\$*" >> "$ARGV_LOG"
exit 0
STUB
  chmod +x "$HOME/.local/bin/$binname"
done
# git stub that logs argv (the demo may overwrite it with a git-push-stub
# wrapper — that's fine; we're asserting no escape to a real binary).
cat > "$HOME/.local/bin/git" <<STUB
#!/bin/bash
printf 'host-pre:git %s\n' "\$*" >> "$ARGV_LOG"
exit 0
STUB
chmod +x "$HOME/.local/bin/git"

# Confirm the only thing on PATH is $HOME/.local/bin at invocation time.
out=$(PATH="$EXCLUSIVE_PATH" HOME="$HOME" "$FLEET" kickstart --demo 2>&1) || {
  echo "FAIL: AC#7 demo exited non-zero under PATH=\$HOME/.local/bin"
  echo "$out"
  exit 1
}
# Sanity: stdout has a [demo] done line, proving the demo ran end-to-end.
if ! printf '%s' "$out" | grep -q '^\[demo\] done\.'; then
  echo "FAIL: AC#7 demo did not complete cleanly under exclusive PATH"
  echo "$out"
  exit 1
fi
# Anything logged to ARGV_LOG would mean the demo invoked a binary that
# WASN'T its own stub (since its own stubs overwrite ours). The demo's
# claude/gh stubs do not write to our $ARGV_LOG — only the host's
# pre-installed wrappers do.
if [ -s "$ARGV_LOG" ]; then
  # OK if it's a stale wrapper the demo didn't overwrite (e.g. tested
  # tools the demo never touches). But the SPECIFIC concern is gh,
  # claude, git push — assert none of those leaked through.
  if grep -qE '^host-pre:(gh|claude)' "$ARGV_LOG"; then
    echo "FAIL: AC#7 demo invoked a host-pre stub for gh/claude — should have its own"
    cat "$ARGV_LOG"
    exit 1
  fi
  # `git` may be called by the demo for non-push operations the synthetic
  # loop reads (e.g. git config, git rev-parse). That's fine because the
  # exit-0 stub satisfies them. The bar is "real network/state".
fi
echo "ok: AC#7 demo runs under PATH=\$HOME/.local/bin without leaking to real gh/claude"

# Restore SYSTEM_PATH so the remaining assertions can use grep/cat/etc.
export PATH="$SYSTEM_PATH"

# ========================================================================
# AC #8 — README.md gains a callout BEFORE Prerequisites + a one-liner
#         in the Daily ops code block.
# ========================================================================
README="$REPO_ROOT/README.md"
if ! grep -qE 'kickstart.*--demo' "$README"; then
  echo "FAIL: AC#8 README.md must mention 'kickstart --demo'"
  exit 1
fi
# The callout must appear BEFORE the "## Prerequisites" section.
prereq_line=$(grep -n '^## Prerequisites' "$README" | head -1 | cut -d: -f1)
demo_line=$(grep -nE 'kickstart.*--demo' "$README" | head -1 | cut -d: -f1)
if [ -z "$prereq_line" ] || [ -z "$demo_line" ]; then
  echo "FAIL: AC#8 could not locate Prerequisites or --demo mention in README"
  exit 1
fi
if [ "$demo_line" -ge "$prereq_line" ]; then
  echo "FAIL: AC#8 callout must appear BEFORE the Prerequisites section (callout line=$demo_line, prereq line=$prereq_line)"
  exit 1
fi
# And a line inside the Daily ops code block. Daily ops starts at a
# heading, then a fenced block; the --demo line should sit inside it.
daily_line=$(grep -n '^### Daily ops' "$README" | head -1 | cut -d: -f1)
if [ -z "$daily_line" ]; then
  echo "FAIL: AC#8 README.md missing '### Daily ops' heading"
  exit 1
fi
# Find the next ``` after Daily ops, then look within for --demo.
after="$(tail -n +"$daily_line" "$README")"
block="$(printf '%s\n' "$after" | awk 'BEGIN{n=0} /^```/ { n++; next } n==1 { print }')"
if ! printf '%s\n' "$block" | grep -qE 'kickstart.*--demo'; then
  echo "FAIL: AC#8 Daily ops code block must include a kickstart --demo line"
  exit 1
fi
echo "ok: AC#8 README has demo callout before Prerequisites + Daily ops line"

# ========================================================================
# AC #9 — runs.jsonl under the demo cache dir gets a single row tagged
#         phase=demo; no demo-* slug rows leak into any real project's
#         runs.jsonl.
# ========================================================================
PATH="$EXCLUSIVE_PATH" HOME="$HOME" "$FLEET" kickstart --demo --keep >"$TMP/demo.out" 2>&1
RUNS_PATH="$(grep -oE '/[^ ]*runs\.jsonl' "$TMP/demo.out" | head -1)"
if [ -z "$RUNS_PATH" ] || [ ! -f "$RUNS_PATH" ]; then
  echo "FAIL: AC#9 demo did not write a runs.jsonl"
  cat "$TMP/demo.out"
  exit 1
fi
PATH="$SYSTEM_PATH"
runs_count=$(wc -l < "$RUNS_PATH" | tr -d ' ')
if [ "$runs_count" != "1" ]; then
  echo "FAIL: AC#9 demo runs.jsonl should have exactly 1 row, got $runs_count"
  cat "$RUNS_PATH"
  exit 1
fi
if ! grep -q '"phase":"demo"' "$RUNS_PATH"; then
  echo "FAIL: AC#9 demo runs.jsonl row missing phase=demo tag"
  cat "$RUNS_PATH"
  exit 1
fi
# Sanity: a `slug:"demo-..."` row must NEVER land in a NON-demo cache.
# The demo's own cache dir is named `demo-XXXX-agent`, and previous
# test invocations under this re-rooted $HOME may have left additional
# `demo-YYYY-agent` caches behind — those are all demo caches and are
# fine. We add one fake non-demo cache, run the demo again, and assert
# the fake's runs.jsonl is untouched (no demo-slug row leaked in).
FAKE_CACHE="$HOME/.cache/realproject-agent"
mkdir -p "$FAKE_CACHE"
printf '{"slug":"realproject","phase":"ship","total_cost_usd":0.05}\n' > "$FAKE_CACHE/runs.jsonl"
PATH="$EXCLUSIVE_PATH" HOME="$HOME" "$FLEET" kickstart --demo >/dev/null 2>&1
PATH="$SYSTEM_PATH"
if grep -q '"slug":"demo-' "$FAKE_CACHE/runs.jsonl"; then
  echo "FAIL: AC#9 demo leaked a demo-slug row into a non-demo project's runs.jsonl"
  cat "$FAKE_CACHE/runs.jsonl"
  exit 1
fi
echo "ok: AC#9 runs.jsonl tagged phase=demo, no leak into other projects"

# ========================================================================
# AC #10 — traps fire even when the inner loop fails. With
#          FLEET_DEMO_FORCE_FAIL=1 the demo should exit non-zero but
#          still wipe its fixture and stubs.
# ========================================================================
# Re-install host stubs first so we can tell whether the demo cleaned up.
for binname in gh claude git-push-stub; do
  cat > "$HOME/.local/bin/$binname" <<STUB
#!/bin/bash
echo "host-stub:$binname"
exit 0
STUB
  chmod +x "$HOME/.local/bin/$binname"
done
FORCED_OUT="$TMP/forced.out"
set +e
PATH="$EXCLUSIVE_PATH" HOME="$HOME" FLEET_DEMO_FORCE_FAIL=1 \
  "$FLEET" kickstart --demo > "$FORCED_OUT" 2>&1
forced_rc=$?
set -e
if [ "$forced_rc" = "0" ]; then
  echo "FAIL: AC#10 FLEET_DEMO_FORCE_FAIL=1 should make demo exit non-zero (got $forced_rc)"
  cat "$FORCED_OUT"
  exit 1
fi
FORCED_FIXTURE="$(grep -oE '/[^ ]*fleet-demo[A-Za-z0-9._-]+' "$FORCED_OUT" | head -1)"
if [ -n "$FORCED_FIXTURE" ] && [ -d "$FORCED_FIXTURE" ]; then
  echo "FAIL: AC#10 cleanup trap did not wipe fixture $FORCED_FIXTURE on forced failure"
  exit 1
fi
for binname in gh claude git-push-stub; do
  if [ -e "$HOME/.local/bin/$binname" ]; then
    if ! grep -q "host-stub:$binname" "$HOME/.local/bin/$binname"; then
      echo "FAIL: AC#10 cleanup trap did not remove demo's $binname stub on forced failure"
      cat "$HOME/.local/bin/$binname"
      exit 1
    fi
  fi
done
echo "ok: AC#10 EXIT trap wipes fixture + stubs even on FLEET_DEMO_FORCE_FAIL=1"

echo
echo "all kickstart-demo.sh assertions passed."
