#!/bin/bash
# tests/lessons-promote.sh — bin/fleet lessons-promote end-to-end.
#
# Ticket 0028. One assertion block per acceptance-criteria checkbox in
# docs/backlog/0028-fleet-lessons-promote-cross-project.md:
#
#   AC#1  default --scope all appends the matched paragraph under the
#         slug's existing `## <slug>` section, before the next sibling
#         `## ` heading.
#   AC#2  if the `## <slug>` section is missing, the command creates it
#         at EOF and appends the lesson there.
#   AC#3  idempotent: same lesson (by SHA of normalized text) under the
#         same slug section is a no-op (exit 0, no append, no event).
#   AC#4  same body under a DIFFERENT slug section → write a
#         `> Already seen under ## <other-slug>` ref AND emit the event
#         with `dup_under=<other-slug>`.
#   AC#5  --scope <slug> writes to
#         <FLEET_CROSS_LESSONS_ROOT>/projects/<scope>/CROSS_LESSONS.md.override
#         instead of the shared file.
#   AC#6  unknown --scope → "no project with SLUG=... found under <root>"
#         to stderr, exit 2.
#   AC#7  --lesson substring matcher: zero matches exit 2, multiple
#         matches exit 2, single match succeeds (3 sub-asserts).
#   AC#8  --headline-exact matches the full headline.
#   AC#9  --dry-run prints proposed append + does NOT mutate any file
#         + does NOT emit any event.
#   AC#10 event lesson_promoted lands in the SOURCE project's
#         events.jsonl with the right payload (source/text_sha/scope).
#
# Per LESSONS 2026-05-26 stubs live in $HOME/.local/bin (otherwise
# common.sh's hardcoded PATH wipes a $TMP/bin). Per LESSONS 2026-05-27
# we use `cp` for backup/restore of fixture files — never `$(cat …)`.

set -euo pipefail

REPO_ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
FLEET="$REPO_ROOT/bin/fleet"
FIXTURES="$REPO_ROOT/tests/fixtures/lessons-promote"

TMP="$(mktemp -d -t fleet-lessons-promote-test.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

# Isolate from the host — HOME shapes both the default cross-lessons
# root and the default events.jsonl path (~/.cache/<slug>-agent/...).
export HOME="$TMP/home"
mkdir -p "$HOME" "$HOME/.local/bin"

# Mirror the fixture tree into a writable tmp dir so the test can copy
# and mutate freely without touching the repo's pristine fixtures.
PROJECTS="$TMP/projects"
mkdir -p "$PROJECTS"
cp -R "$FIXTURES/agent-fleet" "$PROJECTS/agent-fleet"
cp -R "$FIXTURES/courtiq"     "$PROJECTS/courtiq"
cp -R "$FIXTURES/almanac"     "$PROJECTS/almanac"

export FLEET_DISCOVERY_ROOT="$PROJECTS"

# Direct the writer at a tmp cross-lessons tree so the test never
# mutates the host's real ~/.local/share/agent-fleet/.
CROSS_ROOT="$TMP/cross"
mkdir -p "$CROSS_ROOT"
export FLEET_CROSS_LESSONS_ROOT="$CROSS_ROOT"

# Seed the shared CROSS_LESSONS.md with the section-exists fixture so
# AC#1 can assert the "append under existing section" branch.
cp "$FIXTURES/CROSS_LESSONS.md" "$CROSS_ROOT/CROSS_LESSONS.md"

# Source project gets its own events channel so AC#10 can read it.
SOURCE_CACHE="$HOME/.cache/agent-fleet-agent"
mkdir -p "$SOURCE_CACHE"

# ---------------------------------------------------------------------------
# AC#1 — default --scope all, single match, append under existing section.
# ---------------------------------------------------------------------------
"$FLEET" lessons-promote agent-fleet --lesson "printf '- foo'" \
  > "$TMP/ac1.out" 2> "$TMP/ac1.err"
RC=$?
if [ "$RC" != "0" ]; then
  echo "FAIL: AC#1 — promote exited $RC on a single substring match"
  cat "$TMP/ac1.err"
  exit 1
fi

CROSS="$CROSS_ROOT/CROSS_LESSONS.md"
# The new lesson heading (demoted to ### per the lessons-sync convention)
# must appear under ## agent-fleet AND before the next ## heading.
if ! grep -qF -- "### 2026-05-28 — printf '- foo' treats the leading dash as a flag" "$CROSS"; then
  echo "FAIL: AC#1 — appended heading missing from $CROSS"
  cat "$CROSS"
  exit 1
fi
# The pre-existing lesson under agent-fleet must STILL be there.
if ! grep -qF -- "### 2026-05-25 — bootstrap" "$CROSS"; then
  echo "FAIL: AC#1 — destroyed pre-existing agent-fleet content"
  cat "$CROSS"
  exit 1
fi
# Order check: agent-fleet header → new lesson → almanac header.
ORDER=$(awk '
  /^## agent-fleet/   { print "A"; next }
  /^### 2026-05-28/   { print "B"; next }
  /^## almanac/       { print "C"; next }
' "$CROSS" | tr -d '\n')
case "$ORDER" in
  *ABC*) ;;
  *)
    echo "FAIL: AC#1 — section order wrong (got '$ORDER', want ABC substring)"
    cat "$CROSS"
    exit 1 ;;
esac
echo "ok AC#1: single-match append under existing slug section"

# ---------------------------------------------------------------------------
# AC#2 — slug section does not exist → create at EOF and append under it.
# ---------------------------------------------------------------------------
# Start from a CROSS_LESSONS.md that does NOT have a ## courtiq section.
cp "$FIXTURES/CROSS_LESSONS.md" "$CROSS"
"$FLEET" lessons-promote courtiq --lesson "node:sqlite" \
  > "$TMP/ac2.out" 2> "$TMP/ac2.err"
RC=$?
if [ "$RC" != "0" ]; then
  echo "FAIL: AC#2 — promote exited $RC on section-create branch"
  cat "$TMP/ac2.err"
  exit 1
fi
if ! grep -qE '^## courtiq' "$CROSS"; then
  echo "FAIL: AC#2 — ## courtiq section not created"
  cat "$CROSS"
  exit 1
fi
if ! grep -qF -- "### 2026-05-29 — node:sqlite types narrow only after .all()" "$CROSS"; then
  echo "FAIL: AC#2 — appended heading missing under new section"
  cat "$CROSS"
  exit 1
fi
# ## courtiq must be the LAST `## ` heading (appended at EOF, after almanac).
LAST_SECTION=$(grep -E '^## ' "$CROSS" | tail -1)
case "$LAST_SECTION" in
  "## courtiq") ;;
  *)
    echo "FAIL: AC#2 — new section not at EOF (last heading was: $LAST_SECTION)"
    cat "$CROSS"
    exit 1 ;;
esac
echo "ok AC#2: missing section is created at EOF"

# ---------------------------------------------------------------------------
# AC#3 — idempotent: same lesson body under same slug is a no-op (exit 0,
#        no append, no event).
# ---------------------------------------------------------------------------
# Re-run the AC#2 promote against the same target — same source, same lesson.
SHA_BEFORE=$(shasum "$CROSS" | awk '{print $1}')
EVENTS="$SOURCE_CACHE/events.jsonl"
# Snapshot the event count before AC#3 (AC#1 + AC#2 each emitted one).
LINES_BEFORE=0
if [ -f "$EVENTS" ]; then
  LINES_BEFORE=$(awk 'END { print NR+0 }' "$EVENTS")
fi
"$FLEET" lessons-promote courtiq --lesson "node:sqlite" \
  > "$TMP/ac3.out" 2> "$TMP/ac3.err"
RC=$?
if [ "$RC" != "0" ]; then
  echo "FAIL: AC#3 — idempotent re-run exited $RC"
  cat "$TMP/ac3.err"
  exit 1
fi
SHA_AFTER=$(shasum "$CROSS" | awk '{print $1}')
if [ "$SHA_BEFORE" != "$SHA_AFTER" ]; then
  echo "FAIL: AC#3 — file changed on idempotent re-run"
  exit 1
fi
LINES_AFTER=0
if [ -f "$EVENTS" ]; then
  LINES_AFTER=$(awk 'END { print NR+0 }' "$EVENTS")
fi
if [ "$LINES_BEFORE" != "$LINES_AFTER" ]; then
  echo "FAIL: AC#3 — idempotent re-run emitted an event ($LINES_BEFORE → $LINES_AFTER)"
  exit 1
fi
# The stdout banner must name the no-op explicitly.
if ! grep -qF -- "already present in CROSS_LESSONS.md" "$TMP/ac3.out"; then
  echo "FAIL: AC#3 — stdout banner does not name the no-op branch"
  cat "$TMP/ac3.out"
  exit 1
fi
echo "ok AC#3: idempotent no-op (no append, no event)"

# ---------------------------------------------------------------------------
# AC#4 — same body under a DIFFERENT slug section → write a ref line
#        AND emit `dup_under=<other-slug>`.
# ---------------------------------------------------------------------------
# The shared lesson is the `grep -qF "--flag"` one — present in BOTH
# agent-fleet's docs/LESSONS.md AND courtiq's. Step 1: promote it from
# agent-fleet (lands under ## agent-fleet as a normal para). Step 2:
# promote it from courtiq — body matches agent-fleet's, so courtiq's
# section gets a `> Already seen under ## agent-fleet` ref line AND
# the event carries `dup_under=agent-fleet`.
cp "$FIXTURES/CROSS_LESSONS.md" "$CROSS"
"$FLEET" lessons-promote agent-fleet --lesson 'grep -qF' \
  > "$TMP/ac4a.out" 2> "$TMP/ac4a.err" || {
  echo "FAIL: AC#4 — first promote (agent-fleet) failed"
  cat "$TMP/ac4a.err"
  exit 1
}

# Reset events line count to count just the second emission below.
LINES_BEFORE=0
if [ -f "$EVENTS" ]; then
  LINES_BEFORE=$(awk 'END { print NR+0 }' "$EVENTS")
fi

# courtiq has its own events channel; we want to assert THAT channel
# gets the second event (per P-6, source project is the unit of telemetry).
COURTIQ_CACHE="$HOME/.cache/courtiq-agent"
mkdir -p "$COURTIQ_CACHE"
COURTIQ_EVENTS="$COURTIQ_CACHE/events.jsonl"
COURTIQ_LINES_BEFORE=0
if [ -f "$COURTIQ_EVENTS" ]; then
  COURTIQ_LINES_BEFORE=$(awk 'END { print NR+0 }' "$COURTIQ_EVENTS")
fi

"$FLEET" lessons-promote courtiq --lesson 'grep -qF' \
  > "$TMP/ac4b.out" 2> "$TMP/ac4b.err"
RC=$?
if [ "$RC" != "0" ]; then
  echo "FAIL: AC#4 — second promote (courtiq) exited $RC"
  cat "$TMP/ac4b.err"
  exit 1
fi

# The courtiq section must now exist AND contain a `> Already seen under
# ## agent-fleet` ref. The shared lesson heading should NOT appear under
# ## courtiq (otherwise the body is duplicated).
if ! grep -qF -- "> Already seen under ## agent-fleet" "$CROSS"; then
  echo "FAIL: AC#4 — cross-section ref line not written"
  cat "$CROSS"
  exit 1
fi
COURTIQ_LINES_AFTER=0
if [ -f "$COURTIQ_EVENTS" ]; then
  COURTIQ_LINES_AFTER=$(awk 'END { print NR+0 }' "$COURTIQ_EVENTS")
fi
if [ "$COURTIQ_LINES_AFTER" -le "$COURTIQ_LINES_BEFORE" ]; then
  echo "FAIL: AC#4 — courtiq events.jsonl did not grow"
  exit 1
fi
LAST_EVENT=$(tail -1 "$COURTIQ_EVENTS")
case "$LAST_EVENT" in
  *'"dup_under":"agent-fleet"'*) ;;
  *)
    echo "FAIL: AC#4 — last event missing dup_under=agent-fleet"
    echo "$LAST_EVENT"
    exit 1 ;;
esac
echo "ok AC#4: cross-section dedup (ref + dup_under payload)"

# ---------------------------------------------------------------------------
# AC#5 — --scope <slug> writes to projects/<scope>/CROSS_LESSONS.md.override
#        instead of the shared file.
# ---------------------------------------------------------------------------
cp "$FIXTURES/CROSS_LESSONS.md" "$CROSS"
SHARED_SHA_BEFORE=$(shasum "$CROSS" | awk '{print $1}')
"$FLEET" lessons-promote agent-fleet --lesson "printf '- foo'" \
  --scope courtiq > "$TMP/ac5.out" 2> "$TMP/ac5.err"
RC=$?
if [ "$RC" != "0" ]; then
  echo "FAIL: AC#5 — scoped promote exited $RC"
  cat "$TMP/ac5.err"
  exit 1
fi
OVERRIDE="$CROSS_ROOT/projects/courtiq/CROSS_LESSONS.md.override"
if [ ! -f "$OVERRIDE" ]; then
  echo "FAIL: AC#5 — override file not written to $OVERRIDE"
  exit 1
fi
if ! grep -qF -- "### 2026-05-28 — printf '- foo'" "$OVERRIDE"; then
  echo "FAIL: AC#5 — appended heading missing from override file"
  cat "$OVERRIDE"
  exit 1
fi
SHARED_SHA_AFTER=$(shasum "$CROSS" | awk '{print $1}')
if [ "$SHARED_SHA_BEFORE" != "$SHARED_SHA_AFTER" ]; then
  echo "FAIL: AC#5 — scoped write also mutated the shared CROSS_LESSONS.md"
  exit 1
fi
echo "ok AC#5: --scope <slug> writes the override file"

# ---------------------------------------------------------------------------
# AC#6 — unknown --scope value exits 2 with a stderr message.
# ---------------------------------------------------------------------------
set +e
"$FLEET" lessons-promote agent-fleet --lesson "printf '- foo'" \
  --scope nonesuch > "$TMP/ac6.out" 2> "$TMP/ac6.err"
RC=$?
set -e
if [ "$RC" != "2" ]; then
  echo "FAIL: AC#6 — unknown scope exit code = $RC (want 2)"
  cat "$TMP/ac6.err"
  exit 1
fi
if ! grep -qF -- "no project with SLUG=nonesuch" "$TMP/ac6.err"; then
  echo "FAIL: AC#6 — error message missing"
  cat "$TMP/ac6.err"
  exit 1
fi
echo "ok AC#6: unknown scope exits 2"

# ---------------------------------------------------------------------------
# AC#7 — --lesson substring matcher: 0 / many / 1 hit branches.
# ---------------------------------------------------------------------------
# Zero hits.
set +e
"$FLEET" lessons-promote agent-fleet --lesson "this-headline-does-not-exist" \
  > "$TMP/ac7a.out" 2> "$TMP/ac7a.err"
RC=$?
set -e
if [ "$RC" != "2" ]; then
  echo "FAIL: AC#7 — zero-match exit code = $RC (want 2)"
  cat "$TMP/ac7a.err"
  exit 1
fi
if ! grep -qF -- 'no lesson matched' "$TMP/ac7a.err"; then
  echo "FAIL: AC#7 — zero-match stderr banner missing"
  cat "$TMP/ac7a.err"
  exit 1
fi

# Multiple hits — "treats" appears in TWO agent-fleet headlines (printf
# AND grep), so a substring matcher must refuse.
set +e
"$FLEET" lessons-promote agent-fleet --lesson "treats" \
  > "$TMP/ac7b.out" 2> "$TMP/ac7b.err"
RC=$?
set -e
if [ "$RC" != "2" ]; then
  echo "FAIL: AC#7 — multi-match exit code = $RC (want 2)"
  cat "$TMP/ac7b.err"
  exit 1
fi
if ! grep -qE -- 'lessons matched' "$TMP/ac7b.err"; then
  echo "FAIL: AC#7 — multi-match stderr banner missing"
  cat "$TMP/ac7b.err"
  exit 1
fi
if ! grep -qF -- "--headline-exact" "$TMP/ac7b.err"; then
  echo "FAIL: AC#7 — multi-match stderr should hint at --headline-exact"
  cat "$TMP/ac7b.err"
  exit 1
fi

# Single hit — case-INSENSITIVE substring. "PRINTF '- FOO'" should match.
cp "$FIXTURES/CROSS_LESSONS.md" "$CROSS"
"$FLEET" lessons-promote agent-fleet --lesson "PRINTF '- FOO'" \
  > "$TMP/ac7c.out" 2> "$TMP/ac7c.err"
RC=$?
if [ "$RC" != "0" ]; then
  echo "FAIL: AC#7 — case-insensitive single-match exit code = $RC"
  cat "$TMP/ac7c.err"
  exit 1
fi
echo "ok AC#7: zero/many/one substring-match branches"

# ---------------------------------------------------------------------------
# AC#8 — --headline-exact matches the full headline literally.
# ---------------------------------------------------------------------------
cp "$FIXTURES/CROSS_LESSONS.md" "$CROSS"
"$FLEET" lessons-promote agent-fleet --headline-exact \
  "grep -qF \"--flag\" treats the pattern as an option too" \
  > "$TMP/ac8.out" 2> "$TMP/ac8.err"
RC=$?
if [ "$RC" != "0" ]; then
  echo "FAIL: AC#8 — exact-match exit code = $RC"
  cat "$TMP/ac8.err"
  exit 1
fi
if ! grep -qF -- 'grep -qF "--flag" treats the pattern as an option too' "$CROSS"; then
  echo "FAIL: AC#8 — exact-match heading not appended"
  cat "$CROSS"
  exit 1
fi
echo "ok AC#8: --headline-exact"

# ---------------------------------------------------------------------------
# AC#9 — --dry-run: print the proposed append, do NOT mutate any file,
#        do NOT emit any event.
# ---------------------------------------------------------------------------
cp "$FIXTURES/CROSS_LESSONS.md" "$CROSS"
SHA_BEFORE=$(shasum "$CROSS" | awk '{print $1}')
LINES_BEFORE=0
if [ -f "$EVENTS" ]; then
  LINES_BEFORE=$(awk 'END { print NR+0 }' "$EVENTS")
fi
"$FLEET" lessons-promote agent-fleet --lesson "naming a shell function" \
  --dry-run > "$TMP/ac9.out" 2> "$TMP/ac9.err"
RC=$?
if [ "$RC" != "0" ]; then
  echo "FAIL: AC#9 — dry-run exit code = $RC"
  cat "$TMP/ac9.err"
  exit 1
fi
SHA_AFTER=$(shasum "$CROSS" | awk '{print $1}')
if [ "$SHA_BEFORE" != "$SHA_AFTER" ]; then
  echo "FAIL: AC#9 — dry-run mutated $CROSS"
  exit 1
fi
LINES_AFTER=0
if [ -f "$EVENTS" ]; then
  LINES_AFTER=$(awk 'END { print NR+0 }' "$EVENTS")
fi
if [ "$LINES_BEFORE" != "$LINES_AFTER" ]; then
  echo "FAIL: AC#9 — dry-run emitted an event"
  exit 1
fi
# Stdout must contain the heading the operator is previewing.
if ! grep -qF -- "naming a shell function" "$TMP/ac9.out"; then
  echo "FAIL: AC#9 — dry-run stdout missing proposed heading"
  cat "$TMP/ac9.out"
  exit 1
fi
echo "ok AC#9: --dry-run is read-only"

# ---------------------------------------------------------------------------
# AC#10 — event lands in SOURCE project's events.jsonl with the right
#         payload keys (source/text_sha/scope/phase=promote/type).
# ---------------------------------------------------------------------------
# Clean slate so the event we assert on is the one we just emitted.
rm -f "$EVENTS"
cp "$FIXTURES/CROSS_LESSONS.md" "$CROSS"
"$FLEET" lessons-promote agent-fleet --lesson "printf '- foo'" \
  > "$TMP/ac10.out" 2> "$TMP/ac10.err"
RC=$?
if [ "$RC" != "0" ]; then
  echo "FAIL: AC#10 — promote for event-assert exited $RC"
  cat "$TMP/ac10.err"
  exit 1
fi
if [ ! -f "$EVENTS" ]; then
  echo "FAIL: AC#10 — events.jsonl not created at $EVENTS"
  exit 1
fi
LAST_EVENT=$(tail -1 "$EVENTS")
# Parse via node so the test asserts JSON shape, not byte fragments.
node -e '
  const line = process.argv[1];
  const obj = JSON.parse(line);
  const want = {
    type: "lesson_promoted",
    phase: "promote",
    slug: "agent-fleet",
    source: "agent-fleet",
    scope: "all"
  };
  for (const k of Object.keys(want)) {
    if (obj[k] !== want[k]) {
      console.error(`FAIL: AC#10 — event.${k} = ${JSON.stringify(obj[k])}, want ${JSON.stringify(want[k])}`);
      process.exit(1);
    }
  }
  if (!obj.text_sha || !/^[0-9a-f]{8}$/.test(obj.text_sha)) {
    console.error(`FAIL: AC#10 — text_sha not 8-hex: ${JSON.stringify(obj.text_sha)}`);
    process.exit(1);
  }
  if (!obj.ts || !/^\d{4}-\d{2}-\d{2}T/.test(obj.ts)) {
    console.error(`FAIL: AC#10 — ts missing/wrong shape: ${JSON.stringify(obj.ts)}`);
    process.exit(1);
  }
' "$LAST_EVENT"
echo "ok AC#10: lesson_promoted event has right payload"

echo "ok: tests/lessons-promote.sh passed"
