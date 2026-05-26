#!/bin/bash
# tests/onboard.sh — bin/fleet onboard end-to-end test against a tmpdir fixture.
#
# Ticket 0011. Bootstraps a fresh git repo under mktemp -d and asserts that
# `fleet onboard` populates it with every contract file in one shot, then
# calls install.sh by default. The acceptance-criteria boxes map 1:1 to the
# assertions below:
#
#   1. happy path: writes agents.config.sh, AGENTS.md, docs/LESSONS.md,
#      docs/backlog/{README.md,_template.md}, scripts/check-backlog.mjs, and
#      .claude/agents/{implementation-dev,gtm-innovation,review}.md
#   2. SLUG derives from basename, NAMESPACE=com.<slug>, REPO_URL from git
#      remote, SELF_CANCEL = today + 21 days UTC
#   3. AGENTS.md contains "## Agent parameters" and "## Hard NOs" sections
#   4. --dry-run prints "would create" lines and writes nothing
#   5. running twice without --force exits 1 with the contract message
#   6. --force overwrites and prints "[OK] reset <file>" lines
#   7. install.sh is invoked by default (stubbed on PATH), --skip-install
#      suppresses it
#   8. final stdout line matches the exact next-step string
#
# Self-contained: stubs $HOME, stubs install.sh and launchctl on PATH so the
# test never touches the host's launchd or ~/.local/share/agent-fleet. Exits
# non-zero on any failure.

set -euo pipefail

REPO_ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
FLEET="$REPO_ROOT/bin/fleet"

TMP="$(mktemp -d -t fleet-onboard-test.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

# Isolate from any real ~/.local/share/agent-fleet on the host.
export HOME="$TMP/home"
mkdir -p "$HOME"

# --- stub install.sh + launchctl on PATH so the default invocation is safe ---
# The onboard command resolves install.sh via $KIT_ROOT/lib/install.sh (the
# real one in this repo); we don't shadow that. We DO need a launchctl stub
# because install.sh calls launchctl bootstrap/bootout, and the test runner
# isn't necessarily under a real GUI session. We also stub `gh` for the same
# reason (install.sh may invoke it indirectly via printed help text — no, it
# doesn't, but defense in depth costs nothing).
BIN_STUB="$TMP/bin"
mkdir -p "$BIN_STUB"
cat > "$BIN_STUB/launchctl" <<'STUB'
#!/bin/bash
# Pretend every launchctl subcommand succeeds. install.sh's bootstrap/bootout
# both consult the exit code only.
exit 0
STUB
chmod +x "$BIN_STUB/launchctl"
# Sentinel file the install-stub touches so the test can prove it ran.
INSTALL_MARKER="$TMP/install-was-called"
# Shadow `bash $KIT_ROOT/lib/install.sh <dir>` by exporting an env var the
# onboard command honours: FLEET_INSTALL_CMD overrides the install invocation.
# This is cleaner than shadowing `bash` on PATH.
cat > "$BIN_STUB/fleet-install-stub.sh" <<STUB
#!/bin/bash
echo "stub install.sh ran for: \$1" > "$INSTALL_MARKER"
exit 0
STUB
chmod +x "$BIN_STUB/fleet-install-stub.sh"
export PATH="$BIN_STUB:$PATH"
export FLEET_INSTALL_CMD="$BIN_STUB/fleet-install-stub.sh"

# --- fixture: fresh git repo with a remote, basename = slug --------------
make_project() {  # $1 = slug
  local slug="$1"
  local dir="$TMP/$slug"
  mkdir -p "$dir"
  ( cd "$dir"
    git init -q -b main
    git remote add origin "https://github.com/example/$slug.git"
    # Need at least one commit so git operations downstream don't choke. We
    # don't actually need it for onboarding, but it keeps the fixture realistic.
    : > .gitkeep
    git add .gitkeep
    git -c user.name=test -c user.email=test@example.com commit -q -m init
  )
  echo "$dir"
}

# --- assertion 1+2+3+7+8: happy path -------------------------------------
PROJ="$(make_project myproj)"
HAPPY_OUT="$TMP/happy.out"
set +e
"$FLEET" onboard "$PROJ" > "$HAPPY_OUT" 2>&1
HAPPY_EXIT=$?
set -e

if [ "$HAPPY_EXIT" != "0" ]; then
  echo "FAIL: happy path exit=$HAPPY_EXIT"; cat "$HAPPY_OUT"; exit 1
fi

# Files created
for f in \
  agents.config.sh \
  AGENTS.md \
  docs/LESSONS.md \
  docs/backlog/README.md \
  docs/backlog/_template.md \
  scripts/check-backlog.mjs \
  .claude/agents/implementation-dev.md \
  .claude/agents/gtm-innovation.md \
  .claude/agents/review.md ; do
  if [ ! -f "$PROJ/$f" ]; then
    echo "FAIL: happy path missing $f"; cat "$HAPPY_OUT"; exit 1
  fi
done

# Manifest derivations.
MANIFEST_SLUG=$( (set -e; source "$PROJ/agents.config.sh"; echo "$SLUG") )
MANIFEST_NS=$(   (set -e; source "$PROJ/agents.config.sh"; echo "$NAMESPACE") )
MANIFEST_URL=$(  (set -e; source "$PROJ/agents.config.sh"; echo "$REPO_URL") )
MANIFEST_SC=$(   (set -e; source "$PROJ/agents.config.sh"; echo "$SELF_CANCEL") )

if [ "$MANIFEST_SLUG" != "myproj" ]; then
  echo "FAIL: SLUG=$MANIFEST_SLUG want myproj"; exit 1
fi
if [ "$MANIFEST_NS" != "com.myproj" ]; then
  echo "FAIL: NAMESPACE=$MANIFEST_NS want com.myproj"; exit 1
fi
if [ "$MANIFEST_URL" != "https://github.com/example/myproj.git" ]; then
  echo "FAIL: REPO_URL=$MANIFEST_URL"; exit 1
fi
# SELF_CANCEL must be today+21 days UTC. Recompute and compare. macOS BSD date
# and GNU date both accept -u + appropriate flags; use a portable epoch path.
expected_sc=$(date -u -v+21d +%Y%m%d 2>/dev/null || date -u -d "+21 days" +%Y%m%d)
if [ "$MANIFEST_SC" != "$expected_sc" ]; then
  echo "FAIL: SELF_CANCEL=$MANIFEST_SC want $expected_sc"; exit 1
fi

# AGENTS.md has the two contract sections
if ! grep -q '^## Agent parameters' "$PROJ/AGENTS.md"; then
  echo "FAIL: AGENTS.md missing '## Agent parameters'"; exit 1
fi
if ! grep -q '^## Hard NOs' "$PROJ/AGENTS.md"; then
  echo "FAIL: AGENTS.md missing '## Hard NOs'"; exit 1
fi

# install.sh stub was called
if [ ! -f "$INSTALL_MARKER" ]; then
  echo "FAIL: install stub never ran"; cat "$HAPPY_OUT"; exit 1
fi
if ! grep -q "$PROJ" "$INSTALL_MARKER"; then
  echo "FAIL: install stub got wrong dir: $(cat "$INSTALL_MARKER")"; exit 1
fi

# Final stdout line is the exact contract string
expected_next="next: 'launchctl kickstart -k gui/\$UID/com.myproj.agent-ship' to trigger the first run"
last_line=$(grep -v '^$' "$HAPPY_OUT" | tail -1)
if [ "$last_line" != "$expected_next" ]; then
  echo "FAIL: last line"
  echo "  got: $last_line"
  echo "  want: $expected_next"
  exit 1
fi
echo "ok: happy path"

# --- assertion 5: already onboarded without --force exits 1 ---------------
RERUN_OUT="$TMP/rerun.out"
set +e
"$FLEET" onboard "$PROJ" > "$RERUN_OUT" 2>&1
RERUN_EXIT=$?
set -e
if [ "$RERUN_EXIT" != "1" ]; then
  echo "FAIL: rerun without --force exit=$RERUN_EXIT (want 1)"; cat "$RERUN_OUT"; exit 1
fi
if ! grep -q "already onboarded — use 'fleet onboard --force' to overwrite" "$RERUN_OUT"; then
  echo "FAIL: rerun missing contract message"; cat "$RERUN_OUT"; exit 1
fi
echo "ok: rerun without --force exits 1 with contract message"

# --- assertion 6: --force overwrites with [OK] reset lines ---------------
# Mutate the manifest so we can prove overwrite happened.
echo "# operator edit" >> "$PROJ/agents.config.sh"
FORCE_OUT="$TMP/force.out"
set +e
"$FLEET" onboard --force --skip-install "$PROJ" > "$FORCE_OUT" 2>&1
FORCE_EXIT=$?
set -e
if [ "$FORCE_EXIT" != "0" ]; then
  echo "FAIL: --force exit=$FORCE_EXIT"; cat "$FORCE_OUT"; exit 1
fi
if ! grep -q '^\[OK\] reset agents.config.sh' "$FORCE_OUT"; then
  echo "FAIL: --force missing [OK] reset agents.config.sh"; cat "$FORCE_OUT"; exit 1
fi
if grep -q '# operator edit' "$PROJ/agents.config.sh"; then
  echo "FAIL: --force did not overwrite the operator edit"; exit 1
fi
echo "ok: --force overwrites + prints [OK] reset lines"

# --- assertion 4: --dry-run writes nothing -------------------------------
PROJ2="$(make_project dryrunproj)"
DRY_OUT="$TMP/dry.out"
set +e
"$FLEET" onboard --dry-run "$PROJ2" > "$DRY_OUT" 2>&1
DRY_EXIT=$?
set -e
if [ "$DRY_EXIT" != "0" ]; then
  echo "FAIL: --dry-run exit=$DRY_EXIT"; cat "$DRY_OUT"; exit 1
fi
if [ -f "$PROJ2/agents.config.sh" ]; then
  echo "FAIL: --dry-run created files"; exit 1
fi
if ! grep -q 'would create' "$DRY_OUT"; then
  echo "FAIL: --dry-run output missing 'would create'"; cat "$DRY_OUT"; exit 1
fi
echo "ok: --dry-run writes nothing"

# --- assertion 7b: --skip-install does not run install.sh ----------------
PROJ3="$(make_project skipproj)"
rm -f "$INSTALL_MARKER"
SKIP_OUT="$TMP/skip.out"
set +e
"$FLEET" onboard --skip-install "$PROJ3" > "$SKIP_OUT" 2>&1
SKIP_EXIT=$?
set -e
if [ "$SKIP_EXIT" != "0" ]; then
  echo "FAIL: --skip-install exit=$SKIP_EXIT"; cat "$SKIP_OUT"; exit 1
fi
if [ -f "$INSTALL_MARKER" ]; then
  echo "FAIL: --skip-install still ran install stub"; cat "$INSTALL_MARKER"; exit 1
fi
echo "ok: --skip-install skips install.sh"

echo "ok: tests/onboard.sh passed"
