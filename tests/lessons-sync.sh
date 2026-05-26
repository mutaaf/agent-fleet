#!/bin/bash
# tests/lessons-sync.sh — bin/fleet lessons-sync end-to-end against tmpdir fixtures.
#
# Ticket 0009. One assertion block per acceptance-criteria checkbox in
# docs/backlog/0009-cross-project-lessons.md:
#
#   A. Two projects with distinct LESSONS.md content → merged file has
#      `## almanac` AND `## courtiq` headings with each project's
#      lessons underneath.
#   B. A byte-identical lesson line shared by both projects appears in
#      the merged file exactly once with a `(also seen in <other>)`
#      annotation.
#   C. Idempotent: a second run produces a byte-identical file AND
#      does NOT bump the mtime when content would be unchanged.
#   D. `lib/common.sh` exports FLEET_CROSS_LESSONS pointing to the
#      synced file path.
#   E. `prompts/ship.prompt.md` and `prompts/groom.prompt.md` reference
#      the exact string FLEET_CROSS_LESSONS in their PHASE 0 read.
#   F. `lib/install.sh` invokes `bin/fleet lessons-sync` at the end of
#      its run (stubbed bin/fleet on PATH; assert called exactly once).
#   G. Project with no docs/LESSONS.md is skipped without error.
#
# Self-contained: stubs HOME, sets FLEET_DISCOVERY_ROOT at a tmpdir
# fixture, never touches the host's ~/.local/share/agent-fleet (the
# install location is computed from HOME, which we override).

set -euo pipefail

REPO_ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
FLEET="$REPO_ROOT/bin/fleet"

TMP="$(mktemp -d -t fleet-lessons-test.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

# Isolate from the host: the merged file lands under $HOME/.local/share/...
export HOME="$TMP/home"
mkdir -p "$HOME"

FIXTURE="$TMP/projects"
mkdir -p "$FIXTURE/almanac/docs" "$FIXTURE/courtiq/docs"

cat > "$FIXTURE/almanac/agents.config.sh" <<'CFG'
SLUG="almanac"
PROJECT_NAME="almanac"
NAMESPACE="com.almanac"
REPO_URL="https://github.com/example/almanac"
SELF_CANCEL="20990101"
CFG

cat > "$FIXTURE/courtiq/agents.config.sh" <<'CFG'
SLUG="courtiq"
PROJECT_NAME="courtiq"
NAMESPACE="com.courtiq"
REPO_URL="https://github.com/example/courtiq"
SELF_CANCEL="20990101"
CFG

# Two unique paragraphs in each LESSONS.md, plus one byte-identical line
# shared between the two (for AC#B). The shared line is wrapped in a
# distinctive prefix so grep can find it deterministically below.
cat > "$FIXTURE/almanac/docs/LESSONS.md" <<'MD'
# LESSONS

## 2026-05-20 — almanac-only lesson #1

When the run hits an empty cache the bootstrap path must seed the
schema before the first INSERT, otherwise FOREIGN KEY checks fail.

## 2026-05-21 — shared-with-courtiq

SHARED: never name a shell function `tail` — it shadows /usr/bin/tail.
MD

cat > "$FIXTURE/courtiq/docs/LESSONS.md" <<'MD'
# LESSONS

## 2026-05-22 — courtiq-only lesson #1

The scoreboard rendering pass must run AFTER hydration completes;
otherwise the initial DOM serialises with stale ranks.

## 2026-05-21 — shared-with-almanac

SHARED: never name a shell function `tail` — it shadows /usr/bin/tail.
MD

export FLEET_DISCOVERY_ROOT="$FIXTURE"

# ---------------------------------------------------------------------------
# AC#A — two projects with distinct LESSONS.md produce a merged file with
#        `## almanac` and `## courtiq` headings.
# ---------------------------------------------------------------------------
"$FLEET" lessons-sync >/dev/null

MERGED="$HOME/.local/share/agent-fleet/CROSS_LESSONS.md"
if [ ! -f "$MERGED" ]; then
  echo "FAIL: AC#A — merged file $MERGED not created"
  exit 1
fi

if ! grep -q '^## almanac' "$MERGED"; then
  echo "FAIL: AC#A — missing '## almanac' heading in $MERGED"
  sed -n '1,40p' "$MERGED"
  exit 1
fi
if ! grep -q '^## courtiq' "$MERGED"; then
  echo "FAIL: AC#A — missing '## courtiq' heading in $MERGED"
  sed -n '1,40p' "$MERGED"
  exit 1
fi
if ! grep -q 'almanac-only lesson #1' "$MERGED"; then
  echo "FAIL: AC#A — almanac-only lesson content missing"
  exit 1
fi
if ! grep -q 'courtiq-only lesson #1' "$MERGED"; then
  echo "FAIL: AC#A — courtiq-only lesson content missing"
  exit 1
fi
echo "ok AC#A: merged file has both project headings"

# ---------------------------------------------------------------------------
# AC#B — duplicate lesson line appears exactly once with
#        `(also seen in <other-slug>)` annotation under one heading.
# ---------------------------------------------------------------------------
# The shared lesson body — `grep -F` so the backticks and em-dash are
# matched literally. The annotation lives on the SAME line, so the bare
# prefix should appear exactly once (the second project's copy was
# replaced with a `> Already seen under ## <slug>` ref).
SHARED_PREFIX='SHARED: never name a shell function `tail`'
SHARED_COUNT=$(grep -cF "$SHARED_PREFIX" "$MERGED" || true)
if [ "$SHARED_COUNT" != "1" ]; then
  echo "FAIL: AC#B — shared line prefix appears $SHARED_COUNT times in merged file (want 1)"
  echo "--- merged ---"
  cat "$MERGED"
  exit 1
fi
if ! grep -E '\(also seen in (almanac|courtiq)\)' "$MERGED" >/dev/null; then
  echo "FAIL: AC#B — no '(also seen in <other>)' annotation present"
  cat "$MERGED"
  exit 1
fi
# The annotation must be attached to the SHARED line (not some other
# unrelated paragraph). Find the line carrying SHARED_PREFIX and assert
# `(also seen in ...)` is on that same line.
SHARED_HIT=$(grep -F "$SHARED_PREFIX" "$MERGED" | head -1)
case "$SHARED_HIT" in
  *"(also seen in "*) ;;
  *)
    echo "FAIL: AC#B — shared line is missing its (also seen in ...) annotation"
    echo "got: $SHARED_HIT"
    cat "$MERGED"
    exit 1 ;;
esac
echo "ok AC#B: shared line de-duped with annotation"

# ---------------------------------------------------------------------------
# AC#C — idempotency: a second run is byte-identical AND does not bump
#        the file's mtime when content would be unchanged.
# ---------------------------------------------------------------------------
FIRST_SHA=$(shasum "$MERGED" | awk '{print $1}')
FIRST_MTIME=$(stat -f %m "$MERGED" 2>/dev/null || stat -c %Y "$MERGED" 2>/dev/null)
# Sleep just enough that an unconditional rewrite would bump the integer
# mtime — proves the writer noticed identical bytes and skipped the touch.
sleep 1
"$FLEET" lessons-sync >/dev/null
SECOND_SHA=$(shasum "$MERGED" | awk '{print $1}')
SECOND_MTIME=$(stat -f %m "$MERGED" 2>/dev/null || stat -c %Y "$MERGED" 2>/dev/null)
if [ "$FIRST_SHA" != "$SECOND_SHA" ]; then
  echo "FAIL: AC#C — second run changed bytes (sha $FIRST_SHA -> $SECOND_SHA)"
  exit 1
fi
if [ "$FIRST_MTIME" != "$SECOND_MTIME" ]; then
  echo "FAIL: AC#C — second run bumped mtime ($FIRST_MTIME -> $SECOND_MTIME) despite identical content"
  exit 1
fi
echo "ok AC#C: second run byte-identical, mtime preserved"

# ---------------------------------------------------------------------------
# AC#D — lib/common.sh exports FLEET_CROSS_LESSONS pointing to the
#        synced file path. We source it in a subshell and assert.
# ---------------------------------------------------------------------------
(
  set -euo pipefail
  # shellcheck disable=SC1091
  source "$REPO_ROOT/lib/common.sh"
  if [ -z "${FLEET_CROSS_LESSONS:-}" ]; then
    echo "FAIL: AC#D — FLEET_CROSS_LESSONS not set after sourcing lib/common.sh"
    exit 1
  fi
  case "$FLEET_CROSS_LESSONS" in
    */CROSS_LESSONS.md) ;;
    *)
      echo "FAIL: AC#D — FLEET_CROSS_LESSONS=$FLEET_CROSS_LESSONS does not look like a CROSS_LESSONS.md path"
      exit 1 ;;
  esac
  # The export must be inherited by child processes — not just a plain var.
  CHILD_VAL="$(bash -c 'echo "${FLEET_CROSS_LESSONS:-}"')"
  if [ "$CHILD_VAL" != "$FLEET_CROSS_LESSONS" ]; then
    echo "FAIL: AC#D — FLEET_CROSS_LESSONS not exported (child saw '$CHILD_VAL')"
    exit 1
  fi
) || exit 1
echo "ok AC#D: lib/common.sh exports FLEET_CROSS_LESSONS"

# ---------------------------------------------------------------------------
# AC#E — both prompt files reference the exact string FLEET_CROSS_LESSONS.
# ---------------------------------------------------------------------------
for p in ship.prompt.md groom.prompt.md; do
  if ! grep -q 'FLEET_CROSS_LESSONS' "$REPO_ROOT/prompts/$p"; then
    echo "FAIL: AC#E — prompts/$p does not reference FLEET_CROSS_LESSONS"
    exit 1
  fi
done
echo "ok AC#E: ship/groom prompts reference FLEET_CROSS_LESSONS"

# ---------------------------------------------------------------------------
# AC#F — lib/install.sh invokes `bin/fleet lessons-sync` at the end of its
#        run. We stub `fleet` on PATH (so the install.sh dispatcher hits
#        our stub instead of the repo bin) AND stub launchctl so the real
#        bootstrap/bootout calls are no-ops. Assert the stub is called
#        exactly once with `lessons-sync` as the first argv element.
# ---------------------------------------------------------------------------
INSTALL_TMP="$(mktemp -d -t fleet-lessons-install.XXXXXX)"
trap 'rm -rf "$TMP" "$INSTALL_TMP"' EXIT

INSTALL_HOME="$INSTALL_TMP/home"
mkdir -p "$INSTALL_HOME"
INSTALL_PROJ="$INSTALL_TMP/project"
mkdir -p "$INSTALL_PROJ"
cat > "$INSTALL_PROJ/agents.config.sh" <<'CFG'
SLUG="installtest"
PROJECT_NAME="installtest"
NAMESPACE="com.installtest"
REPO_URL="https://github.com/example/installtest"
SELF_CANCEL="20990101"
CFG

STUB_BIN="$INSTALL_TMP/bin"
mkdir -p "$STUB_BIN"
FLEET_LOG="$INSTALL_TMP/fleet-stub.log"
: > "$FLEET_LOG"
cat > "$STUB_BIN/fleet" <<STUB
#!/bin/bash
printf 'fleet %s\n' "\$*" >> "$FLEET_LOG"
exit 0
STUB
chmod +x "$STUB_BIN/fleet"
cat > "$STUB_BIN/launchctl" <<'STUB'
#!/bin/bash
exit 0
STUB
chmod +x "$STUB_BIN/launchctl"

# Run install.sh under the isolated HOME with our stubs in front of PATH.
# lib/install.sh resolves `fleet` either via PATH lookup or by an absolute
# path within $KIT_ROOT/bin/fleet — both forms must hit the stub when the
# install.sh end-of-run hook fires. To make that work we set
# FLEET_LESSONS_SYNC_CMD as an explicit override the implementation will
# honour (mirrors FLEET_INSTALL_CMD pattern from `fleet onboard`). If the
# implementation chooses to call the local kit's bin/fleet directly, the
# test will see the call too — `bin/fleet` itself is what's being driven.
export PATH="$STUB_BIN:$PATH"
export FLEET_LESSONS_SYNC_CMD="$STUB_BIN/fleet"
HOME="$INSTALL_HOME" bash "$REPO_ROOT/lib/install.sh" "$INSTALL_PROJ" >/dev/null 2>&1 || {
  echo "FAIL: AC#F — lib/install.sh exited non-zero under stubs"
  cat "$FLEET_LOG"
  exit 1
}

LESSONS_CALLS=$(grep -c 'lessons-sync' "$FLEET_LOG" || echo 0)
if [ "$LESSONS_CALLS" != "1" ]; then
  echo "FAIL: AC#F — fleet lessons-sync called $LESSONS_CALLS times (want exactly 1)"
  cat "$FLEET_LOG"
  exit 1
fi
echo "ok AC#F: lib/install.sh invokes fleet lessons-sync exactly once"

# ---------------------------------------------------------------------------
# AC#G — a project with no docs/LESSONS.md is skipped without error.
# ---------------------------------------------------------------------------
mkdir -p "$FIXTURE/empty"
cat > "$FIXTURE/empty/agents.config.sh" <<'CFG'
SLUG="empty"
PROJECT_NAME="empty"
NAMESPACE="com.empty"
REPO_URL="https://github.com/example/empty"
SELF_CANCEL="20990101"
CFG
# Intentionally no docs/LESSONS.md under $FIXTURE/empty.

set +e
"$FLEET" lessons-sync > "$TMP/empty.out" 2>&1
RC=$?
set -e
if [ "$RC" != "0" ]; then
  echo "FAIL: AC#G — sync exited $RC when one project has no LESSONS.md"
  cat "$TMP/empty.out"
  exit 1
fi
# The merged file should still exist and not have an `## empty` heading.
if grep -q '^## empty' "$MERGED"; then
  echo "FAIL: AC#G — merged file has a heading for the project with no LESSONS.md"
  cat "$MERGED"
  exit 1
fi
echo "ok AC#G: project with no LESSONS.md is silently skipped"

echo "ok: tests/lessons-sync.sh passed"
