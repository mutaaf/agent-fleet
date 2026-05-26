#!/bin/bash
# tests/trainee.sh — trainee-mode operator-approval gate test.
#
# Ticket 0014. Asserts the eight acceptance-criteria boxes:
#
#   1. manifest gains an optional TRAINEE_PR_COUNT variable; default unset
#      preserves current behavior (manifest.example.sh documents it inline).
#   2. fleet_trainee_remaining returns max(0, TRAINEE_PR_COUNT - merged_feat).
#   3. fleet_load_manifest exports FLEET_TRAINEE_REMAINING.
#   4. prompts/ship.prompt.md contains the trainee-mode gate language so the
#      dev agent knows to skip `gh pr merge --auto` when remaining > 0.
#   5. trainee_pr_opened event fires when fleet_emit_event is called for it
#      (we drive it directly here, the prompt drives it in production).
#   6. bin/fleet doctor adds a trainee_mode check visible in --json.
#   7. Math: TRAINEE_PR_COUNT=3 with 1 merged feat/ PR -> remaining=2; with
#      5 merged -> remaining=0; with TRAINEE_PR_COUNT unset -> remaining=0.
#   8. AGENTS.md § Telemetry documents the trainee_pr_opened event row.
#
# Self-contained: stubs $HOME and `gh` so the real fleet cache + GitHub never
# come into play. Exits non-zero on any failure.

set -euo pipefail

REPO_ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"

TMP="$(mktemp -d -t fleet-trainee-test.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

# Isolate from real ~/.cache.
export HOME="$TMP/home"
mkdir -p "$HOME"

MANIFEST_DIR="$TMP/project"
mkdir -p "$MANIFEST_DIR"
cat > "$MANIFEST_DIR/agents.config.sh" <<'CFG'
SLUG="traineetest"
PROJECT_NAME="traineetest"
REPO_URL="https://github.com/example/traineetest.git"
NAMESPACE="com.fleet.traineetest"
SELF_CANCEL="20990101"
TRAINEE_PR_COUNT=3
CFG

CACHE="$HOME/.cache/traineetest-agent"
EVENTS="$CACHE/events.jsonl"
mkdir -p "$CACHE"

# --- gh stub: driven by $TMP/gh-merged-count ($TMP/gh-merged.json fed to gh pr list)
STUB_BIN="$TMP/bin"
mkdir -p "$STUB_BIN"
cat > "$STUB_BIN/gh" <<GH_EOF
#!/bin/bash
# Logs invocations, returns a canned merged-feat-PR list when asked.
{
  printf 'gh'
  for a in "\$@"; do printf ' %s' "\$a"; done
  printf '\n'
} >> "$TMP/gh-calls.log"

case " \$* " in
  *" pr list "*)
    cat "$TMP/gh-merged.json"
    ;;
  *)
    # Other gh invocations (auth, etc.) succeed silently.
    exit 0
    ;;
esac
GH_EOF
chmod +x "$STUB_BIN/gh"

# ===========================================================================
# AC #1 — manifest.example.sh documents TRAINEE_PR_COUNT in spend-bound section
# ===========================================================================
if ! grep -q 'TRAINEE_PR_COUNT' "$REPO_ROOT/manifest.example.sh"; then
  echo "FAIL: manifest.example.sh does not document TRAINEE_PR_COUNT"
  exit 1
fi

# ===========================================================================
# AC #2 + AC #7 — fleet_trainee_remaining math
# ===========================================================================
# Case A: TRAINEE_PR_COUNT=3 + 1 merged feat/ PR -> remaining=2
echo '[{"number":11}]' > "$TMP/gh-merged.json"
(
  set -euo pipefail
  # shellcheck disable=SC1091
  source "$REPO_ROOT/lib/common.sh"
  # common.sh resets PATH for launchd-safety; re-prepend the stubs AFTER
  # sourcing so `command -v gh` resolves to our test stub.
  export PATH="$STUB_BIN:$PATH"
  fleet_load_manifest "$MANIFEST_DIR"
  FLEET_PHASE="ship"; export FLEET_PHASE
  if ! type fleet_trainee_remaining >/dev/null 2>&1; then
    echo "FAIL: fleet_trainee_remaining function not defined"
    exit 1
  fi
  got="$(fleet_trainee_remaining)"
  if [ "$got" != "2" ]; then
    echo "FAIL: TRAINEE_PR_COUNT=3 - 1 merged should print 2, got '$got'"
    exit 1
  fi
) || exit 1

# Case B: TRAINEE_PR_COUNT=3 + 5 merged feat/ PRs -> remaining=0 (max(0,-2))
echo '[{"number":11},{"number":12},{"number":13},{"number":14},{"number":15}]' > "$TMP/gh-merged.json"
(
  set -euo pipefail
  # shellcheck disable=SC1091
  source "$REPO_ROOT/lib/common.sh"
  # common.sh resets PATH for launchd-safety; re-prepend the stubs AFTER
  # sourcing so `command -v gh` resolves to our test stub.
  export PATH="$STUB_BIN:$PATH"
  fleet_load_manifest "$MANIFEST_DIR"
  FLEET_PHASE="ship"; export FLEET_PHASE
  got="$(fleet_trainee_remaining)"
  if [ "$got" != "0" ]; then
    echo "FAIL: TRAINEE_PR_COUNT=3 - 5 merged should clamp to 0, got '$got'"
    exit 1
  fi
) || exit 1

# Case C: TRAINEE_PR_COUNT unset -> remaining=0, no gh call
cat > "$MANIFEST_DIR/agents.config.sh" <<'CFG'
SLUG="traineetest"
PROJECT_NAME="traineetest"
REPO_URL="https://github.com/example/traineetest.git"
NAMESPACE="com.fleet.traineetest"
SELF_CANCEL="20990101"
CFG
: > "$TMP/gh-calls.log"
echo '[{"number":11}]' > "$TMP/gh-merged.json"
(
  set -euo pipefail
  # shellcheck disable=SC1091
  source "$REPO_ROOT/lib/common.sh"
  # common.sh resets PATH for launchd-safety; re-prepend the stubs AFTER
  # sourcing so `command -v gh` resolves to our test stub.
  export PATH="$STUB_BIN:$PATH"
  fleet_load_manifest "$MANIFEST_DIR"
  FLEET_PHASE="ship"; export FLEET_PHASE
  got="$(fleet_trainee_remaining)"
  if [ "$got" != "0" ]; then
    echo "FAIL: TRAINEE_PR_COUNT unset should print 0, got '$got'"
    exit 1
  fi
) || exit 1
# Also assert it did NOT call gh in the unset path — fast-out matters.
if grep -q '^gh ' "$TMP/gh-calls.log"; then
  echo "FAIL: fleet_trainee_remaining should not call gh when TRAINEE_PR_COUNT is unset"
  cat "$TMP/gh-calls.log"
  exit 1
fi

# Restore the TRAINEE_PR_COUNT=3 manifest for the remaining assertions.
cat > "$MANIFEST_DIR/agents.config.sh" <<'CFG'
SLUG="traineetest"
PROJECT_NAME="traineetest"
REPO_URL="https://github.com/example/traineetest.git"
NAMESPACE="com.fleet.traineetest"
SELF_CANCEL="20990101"
TRAINEE_PR_COUNT=3
CFG

# ===========================================================================
# AC #3 — fleet_load_manifest exports FLEET_TRAINEE_REMAINING
# ===========================================================================
echo '[{"number":11}]' > "$TMP/gh-merged.json"
(
  set -euo pipefail
  # shellcheck disable=SC1091
  source "$REPO_ROOT/lib/common.sh"
  # common.sh resets PATH for launchd-safety; re-prepend the stubs AFTER
  # sourcing so `command -v gh` resolves to our test stub.
  export PATH="$STUB_BIN:$PATH"
  fleet_load_manifest "$MANIFEST_DIR"
  FLEET_PHASE="ship"; export FLEET_PHASE
  # fleet_load_manifest must export it. The value is computed lazily here;
  # we accept either "the export exists and equals fleet_trainee_remaining"
  # OR "the export exists with the integer value 2".
  if ! env | grep -q '^FLEET_TRAINEE_REMAINING='; then
    echo "FAIL: FLEET_TRAINEE_REMAINING not exported after fleet_load_manifest"
    env | grep -i trainee || true
    exit 1
  fi
  if [ "${FLEET_TRAINEE_REMAINING:-}" != "2" ]; then
    echo "FAIL: FLEET_TRAINEE_REMAINING='${FLEET_TRAINEE_REMAINING:-}' (want 2)"
    exit 1
  fi
) || exit 1

# Also: TRAINEE_PR_COUNT unset -> export equals 0.
cat > "$MANIFEST_DIR/agents.config.sh" <<'CFG'
SLUG="traineetest"
PROJECT_NAME="traineetest"
REPO_URL="https://github.com/example/traineetest.git"
NAMESPACE="com.fleet.traineetest"
SELF_CANCEL="20990101"
CFG
(
  set -euo pipefail
  # shellcheck disable=SC1091
  source "$REPO_ROOT/lib/common.sh"
  # common.sh resets PATH for launchd-safety; re-prepend the stubs AFTER
  # sourcing so `command -v gh` resolves to our test stub.
  export PATH="$STUB_BIN:$PATH"
  fleet_load_manifest "$MANIFEST_DIR"
  FLEET_PHASE="ship"; export FLEET_PHASE
  if [ "${FLEET_TRAINEE_REMAINING:-}" != "0" ]; then
    echo "FAIL: TRAINEE_PR_COUNT unset -> FLEET_TRAINEE_REMAINING should be 0, got '${FLEET_TRAINEE_REMAINING:-}'"
    exit 1
  fi
) || exit 1

# Restore TRAINEE_PR_COUNT=3 manifest.
cat > "$MANIFEST_DIR/agents.config.sh" <<'CFG'
SLUG="traineetest"
PROJECT_NAME="traineetest"
REPO_URL="https://github.com/example/traineetest.git"
NAMESPACE="com.fleet.traineetest"
SELF_CANCEL="20990101"
TRAINEE_PR_COUNT=3
CFG

# ===========================================================================
# AC #4 — prompts/ship.prompt.md instructs the dev agent on trainee mode
# ===========================================================================
SHIP_PROMPT="$REPO_ROOT/prompts/ship.prompt.md"
if ! grep -q 'FLEET_TRAINEE_REMAINING' "$SHIP_PROMPT"; then
  echo "FAIL: ship.prompt.md does not reference FLEET_TRAINEE_REMAINING"
  exit 1
fi
if ! grep -q 'trainee mode' "$SHIP_PROMPT"; then
  echo "FAIL: ship.prompt.md does not mention 'trainee mode'"
  exit 1
fi
# Must instruct skipping `gh pr merge --auto` and posting the comment.
if ! grep -qE '\[FLEET trainee mode' "$SHIP_PROMPT"; then
  echo "FAIL: ship.prompt.md missing the '[FLEET trainee mode K/N]' comment template"
  exit 1
fi

# ===========================================================================
# AC #5 — trainee_pr_opened event lands in events.jsonl with documented keys
# ===========================================================================
: > "$EVENTS" 2>/dev/null || true
echo '[{"number":11}]' > "$TMP/gh-merged.json"
(
  set -euo pipefail
  # shellcheck disable=SC1091
  source "$REPO_ROOT/lib/common.sh"
  # common.sh resets PATH for launchd-safety; re-prepend the stubs AFTER
  # sourcing so `command -v gh` resolves to our test stub.
  export PATH="$STUB_BIN:$PATH"
  fleet_load_manifest "$MANIFEST_DIR"
  FLEET_PHASE="ship"; export FLEET_PHASE
  # Simulate the prompt-driven emission. The ticket says: when a PR opens
  # under trainee mode, the dev agent fires this event. The function we
  # provide is fleet_emit_event; assert it round-trips the documented keys.
  fleet_emit_event trainee_pr_opened "number=42" "remaining=${FLEET_TRAINEE_REMAINING}"
) || exit 1
if ! grep -q '"type":"trainee_pr_opened"' "$EVENTS"; then
  echo "FAIL: trainee_pr_opened event missing from events.jsonl"
  cat "$EVENTS" 2>/dev/null || true
  exit 1
fi
node -e '
  const fs = require("fs");
  const lines = fs.readFileSync(process.argv[1], "utf8").split("\n").filter(Boolean);
  const ev = lines.map(JSON.parse).find(e => e.type === "trainee_pr_opened");
  if (!ev) { console.error("FAIL: no trainee_pr_opened event parsed"); process.exit(1); }
  if (ev.number !== "42") {
    console.error("FAIL: trainee_pr_opened.number=" + ev.number + " (want 42)");
    process.exit(1);
  }
  if (ev.remaining !== "2") {
    console.error("FAIL: trainee_pr_opened.remaining=" + ev.remaining + " (want 2)");
    process.exit(1);
  }
  console.log("ok: trainee_pr_opened event payload");
' "$EVENTS"

# ===========================================================================
# AC #6 — bin/fleet doctor adds a trainee_mode check, visible in --json
# ===========================================================================
# Build a small fixture under FLEET_DISCOVERY_ROOT so the doctor scans it.
FIXTURE="$TMP/projects"
mkdir -p "$FIXTURE/trainee-active" "$FIXTURE/trainee-off"

# trainee-active: TRAINEE_PR_COUNT=3, 1 merged PR -> remaining=2 -> INFO/WARN
cat > "$FIXTURE/trainee-active/agents.config.sh" <<'CFG'
PROJECT_NAME="TraineeActive"
SLUG="trainee-active"
NAMESPACE="com.trainee-active"
REPO_URL="https://github.com/example/trainee-active"
SELF_CANCEL="20990101"
TRAINEE_PR_COUNT=3
CFG
cat > "$FIXTURE/trainee-active/AGENTS.md" <<'MD'
# AGENTS.md

## Agent parameters

- gating checks: ci
MD
mkdir -p "$FIXTURE/trainee-active/docs/backlog" "$FIXTURE/trainee-active/scripts"
echo "# Backlog" > "$FIXTURE/trainee-active/docs/backlog/README.md"
echo "// stub" > "$FIXTURE/trainee-active/scripts/check-backlog.mjs"

# trainee-off: TRAINEE_PR_COUNT unset -> PASS
cat > "$FIXTURE/trainee-off/agents.config.sh" <<'CFG'
PROJECT_NAME="TraineeOff"
SLUG="trainee-off"
NAMESPACE="com.trainee-off"
REPO_URL="https://github.com/example/trainee-off"
SELF_CANCEL="20990101"
CFG
cat > "$FIXTURE/trainee-off/AGENTS.md" <<'MD'
# AGENTS.md

## Agent parameters

- gating checks: ci
MD
mkdir -p "$FIXTURE/trainee-off/docs/backlog" "$FIXTURE/trainee-off/scripts"
echo "# Backlog" > "$FIXTURE/trainee-off/docs/backlog/README.md"
echo "// stub" > "$FIXTURE/trainee-off/scripts/check-backlog.mjs"

# Stubs: launchctl always succeeds; gh returns 1 merged PR for the active one.
cat > "$STUB_BIN/launchctl" <<'STUB'
#!/bin/bash
exit 0
STUB
chmod +x "$STUB_BIN/launchctl"
# Override gh: return 1-element JSON for pr list searches (used by the
# trainee_mode doctor check); auth status succeeds.
cat > "$STUB_BIN/gh" <<GH_EOF
#!/bin/bash
case " \$* " in
  *" pr list "*) echo '[{"number":11}]' ;;
  *) exit 0 ;;
esac
GH_EOF
chmod +x "$STUB_BIN/gh"

export FLEET_DISCOVERY_ROOT="$FIXTURE"
export FLEET_SKIP_INSTALLED_LIB_SHA=1

FLEET="$REPO_ROOT/bin/fleet"
JSON_OUT="$TMP/doctor.json"
set +e
"$FLEET" doctor --json > "$JSON_OUT"
set -e

if [ ! -s "$JSON_OUT" ]; then
  echo "FAIL: doctor --json produced no output"
  exit 1
fi

node -e '
  const fs = require("fs");
  const data = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
  if (!data.projects || !Array.isArray(data.projects)) {
    console.error("FAIL: doctor --json has no projects array");
    process.exit(1);
  }
  for (const proj of data.projects) {
    const tm = (proj.checks || []).find(c => c.name === "trainee_mode");
    if (!tm) {
      console.error("FAIL: project " + proj.slug + " missing trainee_mode check");
      process.exit(1);
    }
    if (proj.slug === "trainee-active") {
      if (tm.status !== "WARN" && tm.status !== "INFO") {
        console.error("FAIL: trainee-active trainee_mode status=" + tm.status + " (want WARN/INFO)");
        process.exit(1);
      }
      if (!/remaining/i.test(tm.reason || "")) {
        console.error("FAIL: trainee-active trainee_mode reason missing remaining count: " + tm.reason);
        process.exit(1);
      }
    } else if (proj.slug === "trainee-off") {
      if (tm.status !== "PASS") {
        console.error("FAIL: trainee-off trainee_mode status=" + tm.status + " (want PASS)");
        process.exit(1);
      }
    }
  }
  console.log("ok: doctor trainee_mode check");
' "$JSON_OUT"

# ===========================================================================
# AC #8 — AGENTS.md § Telemetry documents trainee_pr_opened
# ===========================================================================
if ! grep -q 'trainee_pr_opened' "$REPO_ROOT/AGENTS.md"; then
  echo "FAIL: AGENTS.md does not document the trainee_pr_opened event"
  exit 1
fi

echo "ok: tests/trainee.sh passed"
