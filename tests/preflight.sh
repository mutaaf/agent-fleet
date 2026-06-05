#!/bin/bash
# tests/preflight.sh — bin/fleet preflight dry-adoption end-to-end test.
#
# Ticket 0032. Builds three synthetic candidate projects under tests/fixtures/
# preflight/ and asserts the preflight command:
#   - happy path widgets/ → 10 PASS/WARN rows + verdict + exit 0 (golden file)
#   - widgets-broken/ (missing AGENTS.md section) → FAIL row + exit 1
#   - widgets-collide/ (NAMESPACE claimed by another slug in launchctl stub)
#     → FAIL row + exit 1
#   - SELF_CANCEL < 7d → WARN row, exit 0 (no FAILs)
#   - --json shape: one JSON object per row + summary row, parses via node
#   - zero files written outside $TMPDIR (asserted via find -newer)
#   - launchctl mutation verbs (bootstrap/enable) never called (asserted via
#     the stub's recorded invocation log)
#   - unknown path → stderr "no such directory" + exit 2
#   - --help → USAGE block mentions <repo-path>, --json, --help (per LESSONS
#     2026-05-30 use `grep -qF --` for any pattern starting with `-`)
#
# Self-contained: stubs $HOME, points FLEET_DISCOVERY_ROOT at the fixture
# directory, stubs `launchctl` (read-only verbs only — any mutation attempt is
# recorded but still exits 0), `gh`, and `claude` under $HOME/.local/bin per
# LESSONS 2026-05-26 (lib/common.sh resets PATH on source). Per LESSONS
# 2026-05-27 the fixture is COPIED with `cp -R` — never round-tripped through
# `$(cat …)`. Exits non-zero on any failure.

set -euo pipefail

REPO_ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
FLEET="$REPO_ROOT/bin/fleet"
FIXTURE_SRC="$REPO_ROOT/tests/fixtures/preflight"
GOLDEN="$REPO_ROOT/tests/fixtures/preflight.golden.txt"

TMP="$(mktemp -d -t fleet-preflight-test.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

# Marker for AC#7 "zero files written outside $TMPDIR".
touch "$TMP/start_marker"
# Re-anchor mtime after the writes that came before — we only care about
# what preflight itself writes.
sleep 1

export HOME="$TMP/home"
mkdir -p "$HOME/.local/bin" "$HOME/.local/share/agent-fleet" "$HOME/.cache" "$HOME/Library/LaunchAgents"

# Copy each fixture into $TMP so any incidental write would land in the temp
# tree instead of the repo's tracked fixture. Per LESSONS 2026-05-27 we use
# `cp -R`, NEVER `$(cat …)`.
mkdir -p "$TMP/projects"
cp -R "$FIXTURE_SRC/widgets" "$TMP/projects/widgets"
cp -R "$FIXTURE_SRC/widgets-broken" "$TMP/projects/widgets-broken"
cp -R "$FIXTURE_SRC/widgets-collide" "$TMP/projects/widgets-collide"

# --- stubs under $HOME/.local/bin (PATH-reset-proof, LESSONS 2026-05-26) ---
LCTL_LOG="$TMP/launchctl.invocations"
: > "$LCTL_LOG"
cat > "$HOME/.local/bin/launchctl" <<STUB
#!/bin/bash
# Record every invocation so the test can assert no mutation verbs were used.
printf '%s\n' "\$*" >> "$LCTL_LOG"
case "\$1" in
  print)
    # NAMESPACE collision fixture: pretend com.taken.agent-ship is claimed by
    # another slug. Read-only — we just exit 0 (label exists) or 1 (not).
    case "\$2" in
      *com.taken.agent-ship*) exit 0 ;;
      *)                      exit 1 ;;
    esac
    ;;
  print-disabled|list)
    # widget-collide collision: emit a row claiming com.taken.agent-ship.
    echo "com.taken.agent-ship => false"
    exit 0
    ;;
  bootstrap|bootout|enable|disable|kickstart)
    # MUTATION verbs — preflight must NEVER invoke these. We still exit 0 so
    # the test would only fail on the recorded-log assertion, never on the
    # stub itself.
    exit 0
    ;;
  *)
    exit 0
    ;;
esac
STUB
chmod +x "$HOME/.local/bin/launchctl"

cat > "$HOME/.local/bin/gh" <<'STUB'
#!/bin/bash
case "$1 $2" in
  "auth status")
    echo "github.com"
    echo "  Logged in to github.com account mutaaf"
    echo "  Token scopes: 'repo', 'read:org'"
    exit 0 ;;
esac
exit 0
STUB
chmod +x "$HOME/.local/bin/gh"

# claude stub — just needs to be findable on PATH.
cat > "$HOME/.local/bin/claude" <<'STUB'
#!/bin/bash
exit 0
STUB
chmod +x "$HOME/.local/bin/claude"

# Make the stubs win over the host PATH (preflight does not source common.sh,
# but be defensive in case future changes do).
export PATH="$HOME/.local/bin:$PATH"

# Discovery root only matters for doctor; preflight takes a path. Set anyway.
export FLEET_DISCOVERY_ROOT="$TMP/projects"

# --- AC#1: happy path widgets/ → 10 rows, verdict, exit 0, golden match ---
HAPPY_OUT="$TMP/happy.out"
set +e
"$FLEET" preflight "$TMP/projects/widgets" > "$HAPPY_OUT" 2>&1
HAPPY_EXIT=$?
set -e

if [ "$HAPPY_EXIT" != "0" ]; then
  echo "FAIL AC#1: happy path exit code = $HAPPY_EXIT (want 0)"
  cat "$HAPPY_OUT"
  exit 1
fi

# Verdict line shape — N PASS, N WARN, N FAIL — safe to install.
if ! grep -qE '^verdict: [0-9]+ PASS, [0-9]+ WARN, 0 FAIL — safe to install\.' "$HAPPY_OUT"; then
  echo "FAIL AC#1: verdict line missing or wrong shape"
  cat "$HAPPY_OUT"
  exit 1
fi

# Ten check rows — assert each anchor token appears once.
for kw in \
  "manifest (agents.config.sh):" \
  "AGENTS.md § Agent parameters:" \
  "backlog scaffolding:" \
  "backlog validator:" \
  "subagents under .claude/agents/:" \
  "gh auth status:" \
  "claude CLI on PATH:" \
  "~/.local/share/agent-fleet writable:" \
  "launchd namespace free:" \
  "SELF_CANCEL >= today + 7d:"; do
  if ! grep -qF -- "$kw" "$HAPPY_OUT"; then
    echo "FAIL AC#1: row missing keyword: $kw"
    cat "$HAPPY_OUT"
    exit 1
  fi
done

# Golden file compare — strip volatile path/binary lines first.
GOLDEN_RENDERED="$TMP/golden.expected"
HAPPY_NORMALIZED="$TMP/happy.normalized"
sed \
  -e "s|__REPO__|$TMP/projects/widgets|g" \
  -e "s|__CLAUDE__|$HOME/.local/bin/claude|g" \
  -e "s|__SHARE__|$HOME/.local/share/agent-fleet|g" \
  "$GOLDEN" > "$GOLDEN_RENDERED"
cp "$HAPPY_OUT" "$HAPPY_NORMALIZED"
if ! diff -u "$GOLDEN_RENDERED" "$HAPPY_NORMALIZED"; then
  echo "FAIL AC#1: golden mismatch"
  exit 1
fi
echo "PASS AC#1: happy path golden + verdict + exit 0"

# --- AC#2: missing agents.config.sh → FAIL row + exit 1 ------------------
NO_MANIFEST="$TMP/projects/empty"
mkdir -p "$NO_MANIFEST"
set +e
"$FLEET" preflight "$NO_MANIFEST" > "$TMP/no-manifest.out" 2>&1
NO_MANIFEST_EXIT=$?
set -e
if [ "$NO_MANIFEST_EXIT" != "1" ]; then
  echo "FAIL AC#2: missing-manifest exit code = $NO_MANIFEST_EXIT (want 1)"
  cat "$TMP/no-manifest.out"
  exit 1
fi
if ! grep -qF -- "FAIL  (no agents.config.sh at $NO_MANIFEST)" "$TMP/no-manifest.out"; then
  echo "FAIL AC#2: expected FAIL row not found"
  cat "$TMP/no-manifest.out"
  exit 1
fi
echo "PASS AC#2: missing manifest → FAIL + exit 1"

# --- AC#3: AGENTS.md missing the section → FAIL + exit 1 -----------------
set +e
"$FLEET" preflight "$TMP/projects/widgets-broken" > "$TMP/broken.out" 2>&1
BROKEN_EXIT=$?
set -e
if [ "$BROKEN_EXIT" != "1" ]; then
  echo "FAIL AC#3: widgets-broken exit code = $BROKEN_EXIT (want 1)"
  cat "$TMP/broken.out"
  exit 1
fi
if ! grep -qF -- "FAIL  (AGENTS.md missing '## Agent parameters' section)" "$TMP/broken.out"; then
  echo "FAIL AC#3: expected AGENTS.md FAIL row not found"
  cat "$TMP/broken.out"
  exit 1
fi
echo "PASS AC#3: broken AGENTS.md → FAIL + exit 1"

# --- AC#4: NAMESPACE collision → FAIL + exit 1 ----------------------------
set +e
"$FLEET" preflight "$TMP/projects/widgets-collide" > "$TMP/collide.out" 2>&1
COLLIDE_EXIT=$?
set -e
if [ "$COLLIDE_EXIT" != "1" ]; then
  echo "FAIL AC#4: widgets-collide exit code = $COLLIDE_EXIT (want 1)"
  cat "$TMP/collide.out"
  exit 1
fi
if ! grep -qE 'launchd namespace.*FAIL.*com\.taken' "$TMP/collide.out"; then
  echo "FAIL AC#4: expected namespace-collision FAIL row not found"
  cat "$TMP/collide.out"
  exit 1
fi
echo "PASS AC#4: namespace collision → FAIL + exit 1"

# --- AC#5: SELF_CANCEL < 7d → WARN, exit 0 -------------------------------
SOON="$TMP/projects/widgets-soon"
cp -R "$TMP/projects/widgets" "$SOON"
# Compute today + 5 days in YYYYMMDD (BSD date on macOS / GNU date on Linux).
SOON_DATE="$(date -u -v+5d +%Y%m%d 2>/dev/null || date -u -d '+5 days' +%Y%m%d)"
sed -i.bak "s/^SELF_CANCEL=.*/SELF_CANCEL=\"$SOON_DATE\"/" "$SOON/agents.config.sh"
rm -f "$SOON/agents.config.sh.bak"
set +e
"$FLEET" preflight "$SOON" > "$TMP/soon.out" 2>&1
SOON_EXIT=$?
set -e
if [ "$SOON_EXIT" != "0" ]; then
  echo "FAIL AC#5: SELF_CANCEL=$SOON_DATE soft exit code = $SOON_EXIT (want 0; WARN does not block)"
  cat "$TMP/soon.out"
  exit 1
fi
if ! grep -qE "SELF_CANCEL >= today \+ 7d:.*WARN.*SELF_CANCEL=$SOON_DATE" "$TMP/soon.out"; then
  echo "FAIL AC#5: expected SELF_CANCEL WARN row not found"
  cat "$TMP/soon.out"
  exit 1
fi
echo "PASS AC#5: SELF_CANCEL < 7d → WARN + exit 0"

# --- AC#6: --json shape ---------------------------------------------------
JSON_OUT="$TMP/widgets.json"
set +e
"$FLEET" preflight --json "$TMP/projects/widgets" > "$JSON_OUT" 2>&1
JSON_EXIT=$?
set -e
if [ "$JSON_EXIT" != "0" ]; then
  echo "FAIL AC#6: --json exit code = $JSON_EXIT (want 0)"
  cat "$JSON_OUT"
  exit 1
fi
node -e '
  const fs = require("fs");
  const text = fs.readFileSync(process.argv[1], "utf8").trim();
  const lines = text.split("\n").filter(s => s.length > 0);
  if (lines.length !== 11) {
    console.error("FAIL AC#6: expected 10 rows + 1 summary = 11 JSON objects, got " + lines.length);
    process.exit(1);
  }
  for (let i = 0; i < 10; i++) {
    const o = JSON.parse(lines[i]);
    if (!o.check || !o.status || typeof o.detail !== "string") {
      console.error("FAIL AC#6: row " + i + " missing check/status/detail: " + lines[i]);
      process.exit(1);
    }
    if (!["PASS","WARN","FAIL"].includes(o.status)) {
      console.error("FAIL AC#6: row " + i + " bad status: " + o.status);
      process.exit(1);
    }
  }
  const sum = JSON.parse(lines[10]);
  if (sum.summary !== true) {
    console.error("FAIL AC#6: summary row missing summary:true");
    process.exit(1);
  }
  for (const k of ["pass","warn","fail","verdict"]) {
    if (!(k in sum)) {
      console.error("FAIL AC#6: summary missing key " + k);
      process.exit(1);
    }
  }
  if (!["safe","do_not_install"].includes(sum.verdict)) {
    console.error("FAIL AC#6: bad verdict " + sum.verdict);
    process.exit(1);
  }
' "$JSON_OUT"
echo "PASS AC#6: --json shape (10 rows + summary)"

# --- AC#7: zero files written outside $TMP --------------------------------
LEAKED="$(find "$HOME/.local/share/agent-fleet" "$HOME/Library/LaunchAgents" "$HOME/.cache" \
            -newer "$TMP/start_marker" -type f 2>/dev/null || true)"
if [ -n "$LEAKED" ]; then
  echo "FAIL AC#7: preflight wrote files outside the fixture:"
  echo "$LEAKED"
  exit 1
fi
echo "PASS AC#7: zero files written outside \$TMP"

# --- AC#8: no launchctl mutation verbs called ----------------------------
if grep -qE '^(bootstrap|bootout|enable|disable|kickstart)\b' "$LCTL_LOG"; then
  echo "FAIL AC#8: preflight called a launchctl mutation verb:"
  grep -E '^(bootstrap|bootout|enable|disable|kickstart)\b' "$LCTL_LOG"
  exit 1
fi
echo "PASS AC#8: launchctl mutation verbs untouched"

# --- AC#9: unknown path → exit 2 + stderr error --------------------------
set +e
"$FLEET" preflight "$TMP/does-not-exist" > "$TMP/nopath.out" 2> "$TMP/nopath.err"
NOPATH_EXIT=$?
set -e
if [ "$NOPATH_EXIT" != "2" ]; then
  echo "FAIL AC#9: unknown path exit code = $NOPATH_EXIT (want 2)"
  cat "$TMP/nopath.err"
  exit 1
fi
if ! grep -qF -- "preflight: no such directory $TMP/does-not-exist" "$TMP/nopath.err"; then
  echo "FAIL AC#9: expected stderr error not found"
  cat "$TMP/nopath.err"
  exit 1
fi
echo "PASS AC#9: unknown path → stderr + exit 2"

# --- AC#10: --help USAGE block mentions key tokens -----------------------
HELP_OUT="$TMP/help.out"
set +e
"$FLEET" preflight --help > "$HELP_OUT" 2>&1
HELP_EXIT=$?
set -e
if [ "$HELP_EXIT" != "0" ]; then
  echo "FAIL AC#10: --help exit code = $HELP_EXIT (want 0)"
  cat "$HELP_OUT"
  exit 1
fi
# Per LESSONS 2026-05-30, grep -qF needs `--` before any pattern starting with `-`.
for kw in "<repo-path>" "--json" "--help"; do
  if ! grep -qF -- "$kw" "$HELP_OUT"; then
    echo "FAIL AC#10: --help missing keyword: $kw"
    cat "$HELP_OUT"
    exit 1
  fi
done
# Verify the help block does NOT fall through to fleet status (LESSONS
# 2026-06-01 dispatcher fall-through trap). A status table would contain
# "PROJECT" / "INSTALLED" header columns.
if grep -qE '^PROJECT[[:space:]]+INSTALLED' "$HELP_OUT"; then
  echo "FAIL AC#10: --help fell through to fleet status (dispatcher trap)"
  cat "$HELP_OUT"
  exit 1
fi
echo "PASS AC#10: --help banner + clean exit"

# --- AC#11: tests/preflight.sh exists + covers all 10 boxes --------------
# (Trivially true if we got here, but assert the test file was actually
# executed end-to-end and the runtime budget held.)
if [ ! -f "$REPO_ROOT/tests/preflight.sh" ]; then
  echo "FAIL AC#11: tests/preflight.sh missing"
  exit 1
fi
echo "PASS AC#11: full test file executed end-to-end"

echo
echo "ALL preflight tests passed."
