#!/bin/bash
# tests/doctor.sh — bin/fleet doctor end-to-end test against a tmpdir fixture.
#
# Ticket 0003. Builds two synthetic projects under a temp FLEET_DISCOVERY_ROOT
# (one healthy, one missing AGENTS.md) and asserts the doctor output:
#   - human form prefixes each project block with [PASS]/[WARN]/[FAIL]
#   - --json emits {"projects":[{"slug":..,"checks":[{name,status,reason}...]}]}
#   - --slug NAME restricts to one project
#   - exit code is 0 with no FAIL and 1 with any FAIL
#   - the named checks (config, self_cancel, agents_md, backlog, launchd,
#     installed_lib_sha, gh_auth) appear in the JSON, with the missing-AGENTS.md
#     project FAILing the agents_md check
#
# Self-contained: stubs $HOME, points FLEET_DISCOVERY_ROOT at the fixture,
# stubs `launchctl` and `gh` to deterministic exit codes so the test never
# depends on the host's real state. Exits non-zero on any failure.

set -euo pipefail

REPO_ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"

TMP="$(mktemp -d -t fleet-doctor-test.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

# Isolate from any real ~/.local/share/agent-fleet on the host.
export HOME="$TMP/home"
mkdir -p "$HOME"

# --- fixture: two synthetic projects under FLEET_DISCOVERY_ROOT ----------
FIXTURE="$TMP/projects"
mkdir -p "$FIXTURE/healthy" "$FIXTURE/broken"

# healthy: full manifest + AGENTS.md with the parameters section + backlog
cat > "$FIXTURE/healthy/agents.config.sh" <<'CFG'
PROJECT_NAME="Healthy"
SLUG="healthy"
NAMESPACE="com.healthy"
REPO_URL="https://github.com/example/healthy"
SELF_CANCEL="20990101"
CFG
cat > "$FIXTURE/healthy/AGENTS.md" <<'MD'
# AGENTS.md

## Agent parameters

- gating checks: ci
MD
mkdir -p "$FIXTURE/healthy/docs/backlog" "$FIXTURE/healthy/scripts"
echo "# Backlog" > "$FIXTURE/healthy/docs/backlog/README.md"
echo "// stub" > "$FIXTURE/healthy/scripts/check-backlog.mjs"

# broken: manifest is fine but AGENTS.md is missing and backlog is absent
cat > "$FIXTURE/broken/agents.config.sh" <<'CFG'
PROJECT_NAME="Broken"
SLUG="broken"
NAMESPACE="com.broken"
REPO_URL="https://github.com/example/broken"
SELF_CANCEL="20990101"
CFG

# --- stub launchctl + gh so the test is deterministic --------------------
BIN_STUB="$TMP/bin"
mkdir -p "$BIN_STUB"
cat > "$BIN_STUB/launchctl" <<'STUB'
#!/bin/bash
# Pretend every label is loaded — keeps the launchd_loaded check at PASS for
# both projects. The doctor only consumes the exit code.
exit 0
STUB
cat > "$BIN_STUB/gh" <<'STUB'
#!/bin/bash
# Stub `gh auth status` — succeed regardless of arguments.
exit 0
STUB
chmod +x "$BIN_STUB/launchctl" "$BIN_STUB/gh"
export PATH="$BIN_STUB:$PATH"

# Point discovery at the fixture so the doctor doesn't scan ~/Desktop.
export FLEET_DISCOVERY_ROOT="$FIXTURE"
# Skip the installed-lib-SHA check entirely (no install on a test host).
# The doctor honours this and emits a WARN+reason so we can still assert the row.
export FLEET_SKIP_INSTALLED_LIB_SHA=1

FLEET="$REPO_ROOT/bin/fleet"

# --- assertion 1: --json shape + per-project rows ------------------------
JSON_OUT="$TMP/doctor.json"
set +e
"$FLEET" doctor --json > "$JSON_OUT"
JSON_EXIT=$?
set -e

# Any FAIL → exit 1. The broken fixture has no AGENTS.md, so we expect FAIL.
if [ "$JSON_EXIT" != "1" ]; then
  echo "FAIL: --json exit code = $JSON_EXIT (want 1 because the broken project FAILs)"
  cat "$JSON_OUT"
  exit 1
fi

node -e '
  const fs = require("fs");
  const j = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
  if (!j || !Array.isArray(j.projects)) {
    console.error("FAIL: top-level shape missing .projects[]");
    console.error(JSON.stringify(j));
    process.exit(1);
  }
  const slugs = j.projects.map(p => p.slug).sort();
  if (JSON.stringify(slugs) !== JSON.stringify(["broken", "healthy"])) {
    console.error("FAIL: expected slugs [broken, healthy], got " + JSON.stringify(slugs));
    process.exit(1);
  }
  const required = [
    "config", "self_cancel", "agents_md", "backlog",
    "launchd_loaded", "installed_lib_sha", "gh_auth",
  ];
  for (const p of j.projects) {
    if (!Array.isArray(p.checks)) {
      console.error("FAIL: project " + p.slug + " missing checks[]");
      process.exit(1);
    }
    const got = p.checks.map(c => c.name);
    for (const name of required) {
      if (!got.includes(name)) {
        console.error("FAIL: project " + p.slug + " missing check " + name);
        console.error("  got: " + JSON.stringify(got));
        process.exit(1);
      }
    }
    for (const c of p.checks) {
      if (!["PASS", "WARN", "FAIL"].includes(c.status)) {
        console.error("FAIL: " + p.slug + "." + c.name + " status=" + c.status);
        process.exit(1);
      }
    }
  }
  const broken = j.projects.find(p => p.slug === "broken");
  const agentsMd = broken.checks.find(c => c.name === "agents_md");
  if (agentsMd.status !== "FAIL") {
    console.error("FAIL: broken.agents_md should be FAIL, got " + agentsMd.status);
    process.exit(1);
  }
  if (!agentsMd.reason || agentsMd.reason.length === 0) {
    console.error("FAIL: agents_md FAIL should carry a reason string");
    process.exit(1);
  }
  const healthy = j.projects.find(p => p.slug === "healthy");
  const hAgents = healthy.checks.find(c => c.name === "agents_md");
  if (hAgents.status !== "PASS") {
    console.error("FAIL: healthy.agents_md should be PASS, got " + hAgents.status);
    process.exit(1);
  }
  console.log("ok: json shape + per-project checks valid");
' "$JSON_OUT"

# --- assertion 2: human output has [PASS]/[WARN]/[FAIL] block prefixes ----
HUMAN_OUT="$TMP/doctor.human"
set +e
"$FLEET" doctor > "$HUMAN_OUT"
HUMAN_EXIT=$?
set -e
if [ "$HUMAN_EXIT" != "1" ]; then
  echo "FAIL: human-mode exit code = $HUMAN_EXIT (want 1)"
  cat "$HUMAN_OUT"
  exit 1
fi
# The human form colorises the [STATUS] prefix, so strip ANSI before grepping.
STRIPPED="$TMP/doctor.human.stripped"
# shellcheck disable=SC2016
perl -pe 's/\e\[[0-9;]*m//g' < "$HUMAN_OUT" > "$STRIPPED"
if ! grep -qE '^\[(PASS|WARN|FAIL)\] healthy' "$STRIPPED"; then
  echo "FAIL: healthy block prefix missing"; cat "$STRIPPED"; exit 1
fi
if ! grep -qE '^\[FAIL\] broken' "$STRIPPED"; then
  echo "FAIL: broken block prefix should be [FAIL]"; cat "$STRIPPED"; exit 1
fi
# Reason line for the failed check must be present beneath the broken block.
if ! grep -q "agents_md" "$HUMAN_OUT"; then
  echo "FAIL: human output does not name the failed check"; cat "$HUMAN_OUT"; exit 1
fi

# --- assertion 3: --slug filter restricts to one project -----------------
SLUG_OUT="$TMP/doctor.slug.json"
set +e
"$FLEET" doctor --slug healthy --json > "$SLUG_OUT"
SLUG_EXIT=$?
set -e
# healthy alone has no FAIL → exit 0.
if [ "$SLUG_EXIT" != "0" ]; then
  echo "FAIL: --slug healthy --json exit = $SLUG_EXIT (want 0)"; cat "$SLUG_OUT"; exit 1
fi
node -e '
  const fs = require("fs");
  const j = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
  if (j.projects.length !== 1 || j.projects[0].slug !== "healthy") {
    console.error("FAIL: --slug filter returned " + JSON.stringify(j.projects.map(p=>p.slug)));
    process.exit(1);
  }
  console.log("ok: --slug filter works");
' "$SLUG_OUT"

# --- assertion 4: a non-existent --slug exits 0 with empty projects[] ----
EMPTY_OUT="$TMP/doctor.empty.json"
set +e
"$FLEET" doctor --slug nope --json > "$EMPTY_OUT"
EMPTY_EXIT=$?
set -e
if [ "$EMPTY_EXIT" != "0" ]; then
  echo "FAIL: --slug nope --json exit = $EMPTY_EXIT (want 0)"; cat "$EMPTY_OUT"; exit 1
fi
node -e '
  const fs = require("fs");
  const j = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
  if (!Array.isArray(j.projects) || j.projects.length !== 0) {
    console.error("FAIL: unknown --slug should yield empty projects[], got " + JSON.stringify(j));
    process.exit(1);
  }
  console.log("ok: unknown --slug yields empty projects[]");
' "$EMPTY_OUT"

echo "ok: tests/doctor.sh passed"
