#!/bin/bash
# agent-fleet/lib/common.sh — shared plumbing for every fleet agent runner.
#
# Sourced by ship.sh / groom.sh / review.sh / eng.sh. Never run directly.
#
# Design split that makes the kit scalable:
#   - PLUMBING (slug, namespace, repo, cadence, self-cancel) lives in each
#     project's `agents.config.sh` and is read HERE, by the shell.
#   - SEMANTICS (gating checks, branch prefixes, the local gate command, voice,
#     hard NOs) live in each project's AGENTS.md "## Agent parameters" section
#     and are read by the `claude` agent at runtime from the fresh checkout.
#
# So this file knows nothing project-specific beyond the manifest. One edit
# here changes the loop for the whole fleet.
#
# A runner is invoked as:  bash ship.sh /abs/path/to/project-config-dir
# where that dir holds the (copied) agents.config.sh.

set -euo pipefail

# launchd starts processes with a minimal environment — set PATH ourselves.
export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
export HOME="${HOME:-/Users/$(whoami)}"

# Resolve the kit layout from this file's location (lib/ and prompts/ are peers).
FLEET_LIB="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
FLEET_ROOT="$( cd "$FLEET_LIB/.." && pwd )"
# shellcheck disable=SC2034  # used by sourced runners (ship/groom/eng) via "$FLEET_PROMPTS/..."
FLEET_PROMPTS="$FLEET_ROOT/prompts"

# --- manifest -------------------------------------------------------------
# $1 = absolute path to the dir holding agents.config.sh.
fleet_load_manifest() {
  PROJECT_DIR="${1:?usage: <runner>.sh /abs/path/to/config-dir}"
  local manifest="$PROJECT_DIR/agents.config.sh"
  [ -f "$manifest" ] || { echo "no agents.config.sh in $PROJECT_DIR" >&2; exit 2; }
  # shellcheck disable=SC1090
  source "$manifest"
  : "${SLUG:?manifest missing SLUG}"
  : "${REPO_URL:?manifest missing REPO_URL}"
  : "${SELF_CANCEL:?manifest missing SELF_CANCEL}"
  PROJECT_NAME="${PROJECT_NAME:-$SLUG}"
  MODEL="${MODEL:-claude-opus-4-7}"
  GIT_AUTHOR_NAME="${GIT_AUTHOR_NAME:-$PROJECT_NAME Agent}"
  GIT_AUTHOR_EMAIL="${GIT_AUTHOR_EMAIL:-noreply@anthropic.com}"
  # owner/name slug for `gh --repo`, derived from REPO_URL.
  REPO="$(echo "$REPO_URL" | sed -E 's#https?://github.com/##; s#\.git$##')"
  CACHE_DIR="$HOME/.cache/${SLUG}-agent"
  LOG_DIR="$CACHE_DIR/logs"
  mkdir -p "$LOG_DIR"
}

# --- self-cancel ----------------------------------------------------------
# Bound autonomous spend. Return 1 (caller does `|| exit 0`) once expired.
fleet_self_cancel() {
  local today; today=$(date -u +%Y%m%d)
  if [ "$today" -ge "$SELF_CANCEL" ]; then
    echo "expired — ${SLUG} agents reached self-cancel ($SELF_CANCEL)."
    echo "Bump SELF_CANCEL in agents.config.sh, then re-run: bash <kit>/lib/install.sh <project-dir>"
    return 1
  fi
  return 0
}

# --- logging --------------------------------------------------------------
# $1 = phase (ship/groom/review/eng). Redirects all output to a timestamped log.
fleet_log_init() {
  local phase="$1"
  local ts; ts=$(date -u +%Y%m%d-%H%M%S)
  FLEET_LOG="$LOG_DIR/${phase}-${ts}.log"
  exec >"$FLEET_LOG" 2>&1
  RUN_STARTED_UTC="$(date -u +%FT%TZ)"
  echo "=== ${SLUG}-${phase} firing $(date -u) (local $(date)) ==="
  echo "project=$PROJECT_NAME  model=$MODEL  repo=$REPO"
  echo "claude=$(command -v claude || echo MISSING)"
  echo
}

# --- checkout -------------------------------------------------------------
# $1 = checkout subdir name (default "checkout"). Leaves cwd in a fresh
# checkout on main, hard-reset to origin/main, gitignored files preserved.
fleet_checkout() {
  local sub="${1:-checkout}"
  local workdir="$CACHE_DIR/$sub"
  mkdir -p "$workdir"
  if [ ! -d "$workdir/.git" ]; then
    git clone --depth=20 "$REPO_URL" "$workdir"
  fi
  cd "$workdir"
  git fetch origin --prune --quiet
  git checkout main --quiet
  git reset --hard origin/main --quiet
  git clean -fdq
  git config user.email "$GIT_AUTHOR_EMAIL"
  git config user.name "$GIT_AUTHOR_NAME"
}

# --- claude with structured capture ---------------------------------------
# fleet_run_claude <phase>  — reads the prompt on stdin, runs claude in JSON mode,
# emits the human-readable .result text to the log (back-compat for log parsers),
# AND appends a structured record to ~/.cache/<slug>-agent/runs.jsonl for the
# fleet-control cost engine (measured total_cost_usd + usage). Best-effort: if jq
# or the JSON is missing, it still prints output and the run proceeds.
fleet_run_claude() {
  local phase="$1"
  local tmp; tmp="$(mktemp)"
  claude --print --output-format json --dangerously-skip-permissions --model "$MODEL" >"$tmp" 2>/dev/null
  local exit=$?
  if command -v jq >/dev/null 2>&1 && jq -e . "$tmp" >/dev/null 2>&1; then
    jq -r '.result // empty' "$tmp"
    local rec
    rec="$(jq -c \
      --arg slug "$SLUG" --arg phase "$phase" --arg exit "$exit" \
      --arg s "${RUN_STARTED_UTC:-}" --arg e "$(date -u +%FT%TZ)" --arg model "$MODEL" \
      '{slug:$slug,phase:$phase,ts_start:$s,ts_end:$e,exit:($exit|tonumber),model:$model,
        session_id:.session_id, total_cost_usd:.total_cost_usd, duration_ms:.duration_ms,
        num_turns:.num_turns, usage:.usage, is_error:.is_error, result_head:((.result//"")[0:500])}' \
      "$tmp" 2>/dev/null)"
    [ -n "$rec" ] && printf '%s\n' "$rec" >> "$CACHE_DIR/runs.jsonl"
  else
    cat "$tmp"   # fallback: claude didn't emit JSON
  fi
  rm -f "$tmp"
  return $exit
}
