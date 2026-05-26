#!/bin/bash
# tests/budget.sh — fleet_check_budget daily-cap enforcement test.
#
# Ticket 0004. Seeds a stub $CACHE_DIR/runs.jsonl with two records dated today
# (UTC) summing to $4.50, then with MAX_DAILY_USD=5 asserts fleet_check_budget
# returns 0 (proceed). Bumps the sum to $5.10 and asserts it returns 1 (abort)
# AND that a typed `budget_block` event lands in events.jsonl with the
# documented keys (reason=daily_cap, spent, cap).
#
# Also asserts the no-cap fast path (MAX_DAILY_USD unset → always 0) and the
# missing-file / missing-field tolerances called out in the acceptance
# criteria.
#
# Self-contained: stubs $HOME so we never touch real ~/.cache state. Exits
# non-zero on any failure.

set -euo pipefail

REPO_ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"

TMP="$(mktemp -d -t fleet-budget-test.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

# Isolate from the real fleet cache. CACHE_DIR is derived from $HOME + $SLUG.
export HOME="$TMP/home"
mkdir -p "$HOME"

MANIFEST_DIR="$TMP/project"
mkdir -p "$MANIFEST_DIR"
cat > "$MANIFEST_DIR/agents.config.sh" <<'CFG'
SLUG="budgettest"
PROJECT_NAME="budgettest"
REPO_URL="https://github.com/example/budgettest.git"
SELF_CANCEL="20990101"
CFG

CACHE="$HOME/.cache/budgettest-agent"
RUNS="$CACHE/runs.jsonl"
EVENTS="$CACHE/events.jsonl"
mkdir -p "$CACHE"

TODAY="$(date -u +%Y-%m-%d)"
YESTERDAY="$(date -u -v-1d +%Y-%m-%d 2>/dev/null || date -u -d 'yesterday' +%Y-%m-%d)"

# --- assertion 1: no MAX_DAILY_USD → returns 0 (no cap, default behavior) ---
(
  set -euo pipefail
  # shellcheck disable=SC1091
  source "$REPO_ROOT/lib/common.sh"
  fleet_load_manifest "$MANIFEST_DIR"
  FLEET_PHASE="ship"; export FLEET_PHASE
  unset MAX_DAILY_USD || true
  if ! fleet_check_budget; then
    echo "FAIL: fleet_check_budget returned non-zero with MAX_DAILY_USD unset"
    exit 1
  fi
) || exit 1

# --- assertion 2: missing runs.jsonl is tolerated (treated as 0 spend) -----
rm -f "$RUNS"
(
  set -euo pipefail
  # shellcheck disable=SC1091
  source "$REPO_ROOT/lib/common.sh"
  fleet_load_manifest "$MANIFEST_DIR"
  FLEET_PHASE="ship"; export FLEET_PHASE
  MAX_DAILY_USD=5
  if ! fleet_check_budget; then
    echo "FAIL: missing runs.jsonl should be treated as 0 spend, not block"
    exit 1
  fi
) || exit 1

# --- assertion 3: sum $4.50 today < $5 cap → returns 0 (proceed) ----------
# Three records: two today summing to $4.50, one yesterday at $99 that MUST
# be excluded from today's sum.
cat > "$RUNS" <<JSONL
{"slug":"budgettest","phase":"ship","ts_start":"${TODAY}T01:00:00Z","ts_end":"${TODAY}T01:00:30Z","exit":0,"total_cost_usd":2.25}
{"slug":"budgettest","phase":"groom","ts_start":"${TODAY}T02:00:00Z","ts_end":"${TODAY}T02:00:30Z","exit":0,"total_cost_usd":2.25}
{"slug":"budgettest","phase":"ship","ts_start":"${YESTERDAY}T23:00:00Z","ts_end":"${YESTERDAY}T23:00:30Z","exit":0,"total_cost_usd":99.00}
JSONL

(
  set -euo pipefail
  # shellcheck disable=SC1091
  source "$REPO_ROOT/lib/common.sh"
  fleet_load_manifest "$MANIFEST_DIR"
  FLEET_PHASE="ship"; export FLEET_PHASE
  MAX_DAILY_USD=5
  if ! fleet_check_budget; then
    echo "FAIL: spent=4.50 < cap=5 should return 0; got non-zero"
    exit 1
  fi
) || exit 1

# Confirm no budget_block event was emitted by the proceed path.
if [ -f "$EVENTS" ] && grep -q '"type":"budget_block"' "$EVENTS"; then
  echo "FAIL: budget_block emitted while under cap"
  cat "$EVENTS"
  exit 1
fi

# --- assertion 4: bump to $5.10 today >= $5 cap → returns 1 (block) ------
# Add a $0.60 record today; new today-sum is $5.10.
cat >> "$RUNS" <<JSONL
{"slug":"budgettest","phase":"review","ts_start":"${TODAY}T03:00:00Z","ts_end":"${TODAY}T03:00:30Z","exit":0,"total_cost_usd":0.60}
JSONL

(
  set -euo pipefail
  # shellcheck disable=SC1091
  source "$REPO_ROOT/lib/common.sh"
  fleet_load_manifest "$MANIFEST_DIR"
  FLEET_PHASE="ship"; export FLEET_PHASE
  MAX_DAILY_USD=5
  if fleet_check_budget; then
    echo "FAIL: spent=5.10 >= cap=5 should return 1; got 0"
    exit 1
  fi
)

# --- assertion 5: a budget_block event was emitted with the documented keys -
if [ ! -f "$EVENTS" ]; then
  echo "FAIL: events.jsonl was not created by the budget_block emission"
  exit 1
fi
if ! grep -q '"type":"budget_block"' "$EVENTS"; then
  echo "FAIL: no budget_block event in events.jsonl"
  cat "$EVENTS"
  exit 1
fi
node -e '
  const fs = require("fs");
  const lines = fs.readFileSync(process.argv[1], "utf8").split("\n").filter(Boolean);
  const ev = lines.map(JSON.parse).find(e => e.type === "budget_block");
  if (!ev) { console.error("FAIL: no budget_block event parsed"); process.exit(1); }
  if (ev.reason !== "daily_cap") {
    console.error("FAIL: budget_block.reason=" + ev.reason + " (want daily_cap)");
    process.exit(1);
  }
  // spent and cap are emitted as strings via the k=v channel.
  if (!ev.spent || !ev.cap) {
    console.error("FAIL: budget_block missing spent/cap: " + JSON.stringify(ev));
    process.exit(1);
  }
  const spent = parseFloat(ev.spent);
  const cap = parseFloat(ev.cap);
  if (!(spent >= 5.09 && spent <= 5.11)) {
    console.error("FAIL: budget_block.spent=" + ev.spent + " (want ~5.10)");
    process.exit(1);
  }
  if (cap !== 5) {
    console.error("FAIL: budget_block.cap=" + ev.cap + " (want 5)");
    process.exit(1);
  }
  console.log("ok: budget_block event payload");
' "$EVENTS"

# --- assertion 6: records missing total_cost_usd are treated as 0 ---------
# Clear runs.jsonl, add a record with NO total_cost_usd field, set cap=5.
# Sum should be 0 → returns 0 (proceed).
: > "$RUNS"
cat > "$RUNS" <<JSONL
{"slug":"budgettest","phase":"ship","ts_start":"${TODAY}T01:00:00Z","ts_end":"${TODAY}T01:00:30Z","exit":0}
JSONL

(
  set -euo pipefail
  # shellcheck disable=SC1091
  source "$REPO_ROOT/lib/common.sh"
  fleet_load_manifest "$MANIFEST_DIR"
  FLEET_PHASE="ship"; export FLEET_PHASE
  MAX_DAILY_USD=5
  if ! fleet_check_budget; then
    echo "FAIL: a record with missing total_cost_usd should be treated as 0"
    exit 1
  fi
) || exit 1

echo "ok: tests/budget.sh passed"
