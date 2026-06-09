#!/bin/bash
# tests/onboarding-check.sh — bin/fleet onboarding-check end-to-end test.
#
# Ticket 0041. Builds a synthetic "freshly-installed" project under $HOME
# (stubbed to $TMP) and asserts the verifier walks the 11 checks +
# synthetic ship cycle correctly.
#
# 12 acceptance criteria → 12 numbered AC blocks.
#
# Per LESSONS 2026-05-26: stubs under $HOME/.local/bin so lib/common.sh's
# PATH reset still finds them.
# Per LESSONS 2026-05-27: fixture restore via cp, never $(cat …).
# Per LESSONS 2026-05-30: `grep -qF --` for any pattern starting with -.
# Per LESSONS 2026-06-01: counts via `awk … END { print n+0 }`.
# Per LESSONS 2026-06-08: middle-empty TSV fields use sentinels.

set -euo pipefail

REPO_ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
FLEET="$REPO_ROOT/bin/fleet"
FIXTURE_SRC="$REPO_ROOT/tests/fixtures/onboarding-check"

TMP="$(mktemp -d -t fleet-onboarding-test.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

export HOME="$TMP/home"
mkdir -p "$HOME/.local/bin" "$HOME/.cache" "$HOME/Library/LaunchAgents"

# Per LESSONS 2026-05-26 stubs under $HOME/.local/bin (the head of the
# reset PATH inside lib/common.sh).

GH_LOG="$TMP/gh.invocations"
: > "$GH_LOG"
cat > "$HOME/.local/bin/gh" <<STUB
#!/bin/bash
# Record every invocation so AC#9 can assert no real gh pr create fired.
printf '%s\n' "\$*" >> "$GH_LOG"
case "\$1 \$2" in
  "auth status")
    echo "github.com"
    echo "  Logged in to github.com account mutaaf"
    echo "  Token scopes: 'repo', 'read:org'"
    exit 0 ;;
  "repo view")
    echo "example/healthy-app"
    exit 0 ;;
esac
exit 0
STUB
chmod +x "$HOME/.local/bin/gh"

LCTL_LOG="$TMP/launchctl.invocations"
: > "$LCTL_LOG"
cat > "$HOME/.local/bin/launchctl" <<STUB
#!/bin/bash
printf '%s\n' "\$*" >> "$LCTL_LOG"
case "\$1" in
  print)
    case "\$2" in
      *com.healthy.app.agent-ship*|*com.healthy.app.agent-groom*) exit 0 ;;
      *) exit 1 ;;
    esac
    ;;
  print-disabled)
    case "\$3" in
      *com.healthy.app.agent-groom*)
        if [ -f "$TMP/groom-disabled" ]; then echo "disabled"; else echo "enabled"; fi
        exit 0 ;;
      *com.healthy.app.agent-ship*)
        echo "enabled"
        exit 0 ;;
    esac
    exit 0 ;;
  bootstrap|bootout|enable|disable|kickstart) exit 0 ;;
  *) exit 0 ;;
esac
STUB
chmod +x "$HOME/.local/bin/launchctl"

CLAUDE_LOG="$TMP/claude.invocations"
: > "$CLAUDE_LOG"
cat > "$HOME/.local/bin/claude" <<STUB
#!/bin/bash
printf '%s\n' "\$*" >> "$CLAUDE_LOG"
exit 0
STUB
chmod +x "$HOME/.local/bin/claude"

export PATH="$HOME/.local/bin:$PATH"

# Build the fixture project under $TMP. The fixture is COPIED with `cp -R`
# per LESSONS 2026-05-27 so we can mutate it freely.
mkdir -p "$TMP/code"
cp -R "$FIXTURE_SRC/project" "$TMP/code/myproject"

# Pre-populate the installed copy tree (the AGENT-FLEET kit's TCC-safe lib).
mkdir -p "$HOME/.local/share/agent-fleet/lib"
mkdir -p "$HOME/.local/share/agent-fleet/projects/healthy-app"
cp "$FIXTURE_SRC/share/agent-fleet/lib/common.sh" "$HOME/.local/share/agent-fleet/lib/common.sh"
cp "$FIXTURE_SRC/share/agent-fleet/projects/healthy-app/agents.config.sh" \
   "$HOME/.local/share/agent-fleet/projects/healthy-app/agents.config.sh"

# Install the launchd plists so the plist-presence check passes.
cp "$FIXTURE_SRC/launchd/com.healthy.app.agent-ship.plist" \
   "$HOME/Library/LaunchAgents/com.healthy.app.agent-ship.plist"
cp "$FIXTURE_SRC/launchd/com.healthy.app.agent-groom.plist" \
   "$HOME/Library/LaunchAgents/com.healthy.app.agent-groom.plist"

# Stamp the manifest's PROMPTS_SHA so the matching-pin check is GREEN by
# default. The fixture file ships with PROMPTS_SHA="" and we compute the
# kit's prompts SHA from this repo at test time.
ACTUAL_SHA="$("$FLEET" prompts-sha 2>/dev/null)"
sed -i.bak "s|^PROMPTS_SHA=.*|PROMPTS_SHA=\"$ACTUAL_SHA\"|" \
  "$TMP/code/myproject/agents.config.sh"
rm -f "$TMP/code/myproject/agents.config.sh.bak"

# Freeze the clock for any time-sensitive output.
export FLEET_NOW_OVERRIDE="2026-06-09T12:00:00Z"

# --- AC#1: usage / not-a-directory ---------------------------------------
# Missing positional → exit 2 + stderr message; not-a-dir → exit 2 + stderr.
set +e
"$FLEET" onboarding-check > "$TMP/usage.out" 2> "$TMP/usage.err"
USAGE_EXIT=$?
set -e
if [ "$USAGE_EXIT" != "2" ]; then
  echo "FAIL AC#1: missing-arg exit code = $USAGE_EXIT (want 2)"
  cat "$TMP/usage.err"
  exit 1
fi
if ! grep -qF -- "onboarding-check: usage: bin/fleet onboarding-check" "$TMP/usage.err"; then
  echo "FAIL AC#1: missing-arg stderr lacks usage line"
  cat "$TMP/usage.err"
  exit 1
fi
set +e
"$FLEET" onboarding-check "$TMP/does-not-exist" > "$TMP/nodir.out" 2> "$TMP/nodir.err"
NODIR_EXIT=$?
set -e
if [ "$NODIR_EXIT" != "2" ]; then
  echo "FAIL AC#1: not-a-directory exit = $NODIR_EXIT (want 2)"
  cat "$TMP/nodir.err"
  exit 1
fi
if ! grep -qF -- "onboarding-check: $TMP/does-not-exist: not a directory" "$TMP/nodir.err"; then
  echo "FAIL AC#1: stderr lacks 'not a directory' message"
  cat "$TMP/nodir.err"
  exit 1
fi
echo "PASS AC#1: usage / not-a-directory → exit 2"

# --- AC#2: eleven checks run in order ------------------------------------
HAPPY="$TMP/happy.out"
set +e
"$FLEET" onboarding-check "$TMP/code/myproject" > "$HAPPY" 2>&1
HAPPY_EXIT=$?
set -e
if [ "$HAPPY_EXIT" != "0" ]; then
  echo "FAIL AC#2: happy path exit code = $HAPPY_EXIT (want 0)"
  cat "$HAPPY"
  exit 1
fi
for kw in \
  "agents.config.sh" \
  "AGENTS.md" \
  "docs/backlog/README.md" \
  ".local/share/agent-fleet/lib" \
  "launchd plist" \
  "launchd labels" \
  "events.jsonl writable" \
  "gh CLI auth" \
  "claude CLI" \
  "prompts SHA" \
  "synthetic ship cycle"; do
  if ! grep -qF -- "$kw" "$HAPPY"; then
    echo "FAIL AC#2: row missing keyword: $kw"
    cat "$HAPPY"
    exit 1
  fi
done
echo "PASS AC#2: eleven check rows present"

# --- AC#3: three-way verdict (GREEN / YELLOW / RED) ----------------------
# GREEN is already covered above. Test YELLOW (groom disabled) and RED
# (agents.config.sh removed).

# YELLOW: agent-groom disabled.
YELLOW_DIR="$TMP/code/myproject-yellow"
cp -R "$TMP/code/myproject" "$YELLOW_DIR"
touch "$TMP/groom-disabled"
set +e
"$FLEET" onboarding-check "$YELLOW_DIR" > "$TMP/yellow.out" 2>&1
YELLOW_EXIT=$?
set -e
rm -f "$TMP/groom-disabled"
if [ "$YELLOW_EXIT" != "0" ]; then
  echo "FAIL AC#3 YELLOW: exit = $YELLOW_EXIT (want 0 — YELLOW does not block)"
  cat "$TMP/yellow.out"
  exit 1
fi
if ! grep -qE 'launchd labels.*YELLOW' "$TMP/yellow.out"; then
  echo "FAIL AC#3 YELLOW: expected YELLOW row missing"
  cat "$TMP/yellow.out"
  exit 1
fi

# RED: remove agents.config.sh in a third copy.
RED_DIR="$TMP/code/myproject-red"
cp -R "$TMP/code/myproject" "$RED_DIR"
rm "$RED_DIR/agents.config.sh"
set +e
"$FLEET" onboarding-check "$RED_DIR" > "$TMP/red.out" 2>&1
RED_EXIT=$?
set -e
if [ "$RED_EXIT" != "1" ]; then
  echo "FAIL AC#3 RED: exit = $RED_EXIT (want 1 — RED blocks)"
  cat "$TMP/red.out"
  exit 1
fi
if ! grep -qE 'agents.config.sh.*RED' "$TMP/red.out"; then
  echo "FAIL AC#3 RED: expected RED row missing"
  cat "$TMP/red.out"
  exit 1
fi
echo "PASS AC#3: GREEN / YELLOW / RED verdict shape"

# --- AC#4: synthetic ship cycle emits exactly four events ---------------
# Find the kit-as-project events channel and assert the last four events
# are the four core types with phase=onboarding-check + a synthetic slug.
EVENTS_CHANNEL=""
for slug_dir in "$HOME/.cache"/onboarding-check-*-agent; do
  [ -d "$slug_dir" ] || continue
  EVENTS_CHANNEL="$slug_dir/events.jsonl"
  break
done
if [ -z "$EVENTS_CHANNEL" ] || [ ! -f "$EVENTS_CHANNEL" ]; then
  echo "FAIL AC#4: no synthetic events.jsonl found under \$HOME/.cache/onboarding-check-*-agent/"
  ls -la "$HOME/.cache" >&2
  exit 1
fi
node -e '
  const fs = require("fs");
  const text = fs.readFileSync(process.argv[1], "utf8").trim();
  const lines = text.split("\n").filter(s => s.length > 0);
  if (lines.length < 4) {
    console.error("FAIL AC#4: events.jsonl has " + lines.length + " lines, want >= 4");
    process.exit(1);
  }
  const last4 = lines.slice(-4);
  const types = [];
  for (const l of last4) {
    const o = JSON.parse(l);
    if (o.phase !== "onboarding-check") {
      console.error("FAIL AC#4: event phase = " + o.phase + " (want onboarding-check)");
      process.exit(1);
    }
    if (!/^onboarding-check-[0-9a-f]{6}$/.test(o.slug)) {
      console.error("FAIL AC#4: event slug = " + o.slug + " (want onboarding-check-<6-hex>)");
      process.exit(1);
    }
    types.push(o.type);
  }
  const want = ["run_started", "pr_opened", "lesson_draft_emitted", "run_completed"];
  for (const t of want) {
    if (!types.includes(t)) {
      console.error("FAIL AC#4: missing event type " + t + " — saw " + JSON.stringify(types));
      process.exit(1);
    }
  }
' "$EVENTS_CHANNEL"
echo "PASS AC#4: synthetic cycle emitted four core events with phase=onboarding-check"

# --- AC#5: --json shape --------------------------------------------------
JSON_OUT="$TMP/checks.json"
set +e
"$FLEET" onboarding-check --json "$TMP/code/myproject" > "$JSON_OUT" 2>&1
JSON_EXIT=$?
set -e
if [ "$JSON_EXIT" != "0" ]; then
  echo "FAIL AC#5: --json exit = $JSON_EXIT (want 0)"
  cat "$JSON_OUT"
  exit 1
fi
node -e '
  const fs = require("fs");
  const text = fs.readFileSync(process.argv[1], "utf8").trim();
  const lines = text.split("\n").filter(s => s.length > 0);
  if (lines.length !== 12) {
    console.error("FAIL AC#5: expected 11 rows + 1 summary = 12 JSON objects, got " + lines.length);
    process.exit(1);
  }
  for (let i = 0; i < 11; i++) {
    const o = JSON.parse(lines[i]);
    if (!o.check || !o.result || typeof o.hint !== "string") {
      console.error("FAIL AC#5: row " + i + " missing keys: " + lines[i]);
      process.exit(1);
    }
    if (!["green","yellow","red"].includes(o.result)) {
      console.error("FAIL AC#5: bad result " + o.result + " on row " + i);
      process.exit(1);
    }
  }
  const sum = JSON.parse(lines[11]);
  if (!sum.summary) {
    console.error("FAIL AC#5: summary row missing");
    process.exit(1);
  }
  for (const k of ["green","yellow","red","exit"]) {
    if (!(k in sum.summary)) {
      console.error("FAIL AC#5: summary missing key " + k);
      process.exit(1);
    }
  }
' "$JSON_OUT"
echo "PASS AC#5: --json shape (11 rows + summary)"

# --- AC#6: --help --------------------------------------------------------
HELP_OUT="$TMP/help.out"
set +e
"$FLEET" onboarding-check --help > "$HELP_OUT" 2>&1
HELP_EXIT=$?
set -e
if [ "$HELP_EXIT" != "0" ]; then
  echo "FAIL AC#6: --help exit = $HELP_EXIT (want 0)"
  cat "$HELP_OUT"
  exit 1
fi
for kw in "--json" "<repo-path>" "checks"; do
  if ! grep -qF -- "$kw" "$HELP_OUT"; then
    echo "FAIL AC#6: --help missing keyword: $kw"
    cat "$HELP_OUT"
    exit 1
  fi
done
# Make sure --help didn't fall through to fleet status (LESSONS 2026-06-01).
if grep -qE '^PROJECT[[:space:]]+INSTALLED' "$HELP_OUT"; then
  echo "FAIL AC#6: --help fell through to fleet status"
  cat "$HELP_OUT"
  exit 1
fi
echo "PASS AC#6: --help banner present, no fall-through"

# --- AC#7: RED-path NEXT block lists copy-pasteable remediation ---------
if ! grep -qF -- "NEXT" "$TMP/red.out"; then
  echo "FAIL AC#7: RED output missing NEXT section"
  cat "$TMP/red.out"
  exit 1
fi
# At least one suggested fix should mention agents.config.sh.
if ! grep -qF -- "agents.config.sh" "$TMP/red.out"; then
  echo "FAIL AC#7: NEXT block lacks a remediation hint for the RED row"
  cat "$TMP/red.out"
  exit 1
fi
echo "PASS AC#7: RED NEXT block lists remediation"

# --- AC#8: GREEN-path NEXT block --------------------------------------
# Three lines: hourly :37 mention, launchctl kickstart, fleet tail --slug.
for kw in ":37" "launchctl kickstart" "fleet tail --slug"; do
  if ! grep -qF -- "$kw" "$HAPPY"; then
    echo "FAIL AC#8: GREEN NEXT block missing keyword: $kw"
    cat "$HAPPY"
    exit 1
  fi
done
echo "PASS AC#8: GREEN NEXT block (hourly, kickstart, tail)"

# --- AC#9: prompts SHA pinned-vs-installed -----------------------------
# Unset PROMPTS_SHA → YELLOW with hint about drift firing silently.
UNSET_DIR="$TMP/code/myproject-unset"
cp -R "$TMP/code/myproject" "$UNSET_DIR"
sed -i.bak "s|^PROMPTS_SHA=.*|PROMPTS_SHA=\"\"|" "$UNSET_DIR/agents.config.sh"
rm -f "$UNSET_DIR/agents.config.sh.bak"
set +e
"$FLEET" onboarding-check "$UNSET_DIR" > "$TMP/unset.out" 2>&1
UNSET_EXIT=$?
set -e
if [ "$UNSET_EXIT" != "0" ]; then
  echo "FAIL AC#9: unset PROMPTS_SHA exit = $UNSET_EXIT (want 0; YELLOW does not block)"
  cat "$TMP/unset.out"
  exit 1
fi
if ! grep -qE 'prompts SHA.*YELLOW' "$TMP/unset.out"; then
  echo "FAIL AC#9: expected prompts-SHA YELLOW row missing"
  cat "$TMP/unset.out"
  exit 1
fi
# Happy path already proved the matching branch is GREEN.
if ! grep -qE 'prompts SHA.*GREEN' "$HAPPY"; then
  echo "FAIL AC#9: matching prompts SHA should be GREEN in happy path"
  cat "$HAPPY"
  exit 1
fi
echo "PASS AC#9: prompts SHA YELLOW on unset, GREEN on match"

# --- AC#10: synthetic cycle does NOT call claude ------------------------
# The claude stub records argv; count must be exactly 0 after happy run.
# Per LESSONS 2026-06-01 we count via awk.
N_CLAUDE="$(awk 'END { print NR+0 }' "$CLAUDE_LOG")"
if [ "$N_CLAUDE" != "0" ]; then
  echo "FAIL AC#10: claude was invoked $N_CLAUDE times (want 0)"
  cat "$CLAUDE_LOG"
  exit 1
fi
echo "PASS AC#10: claude stub recorded zero invocations"

# --- AC#11: lib/common.sh unchanged -------------------------------------
# Diff against main to assert no public API churn. Run against main…HEAD.
if git -C "$REPO_ROOT" rev-parse --verify main >/dev/null 2>&1; then
  CHANGED_LIB="$(git -C "$REPO_ROOT" diff --name-only main...HEAD -- lib/common.sh 2>/dev/null || true)"
  if [ -n "$CHANGED_LIB" ]; then
    echo "FAIL AC#11: lib/common.sh changed on this branch: $CHANGED_LIB"
    exit 1
  fi
fi
echo "PASS AC#11: lib/common.sh untouched"

# --- AC#12: prompts/ unchanged -------------------------------------------
if git -C "$REPO_ROOT" rev-parse --verify main >/dev/null 2>&1; then
  CHANGED_PROMPTS="$(git -C "$REPO_ROOT" diff --name-only main...HEAD -- prompts/ 2>/dev/null || true)"
  if [ -n "$CHANGED_PROMPTS" ]; then
    echo "FAIL AC#12: prompts/ changed on this branch: $CHANGED_PROMPTS"
    exit 1
  fi
fi
echo "PASS AC#12: prompts/ untouched"

# Extra sanity: no real gh pr create was attempted in the synthetic cycle.
if grep -qE '^pr create' "$GH_LOG"; then
  echo "FAIL extra: gh pr create called during onboarding-check"
  cat "$GH_LOG"
  exit 1
fi

echo
echo "ALL onboarding-check tests passed."
