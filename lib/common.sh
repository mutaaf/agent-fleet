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

  # Trainee-mode export (ticket 0014). Computed once and exported so subagents
  # spawned via fleet_run_claude inherit it through the env. The function
  # itself caches per process — see FLEET_TRAINEE_REMAINING_CACHED below.
  FLEET_TRAINEE_REMAINING="$(fleet_trainee_remaining)"
  export FLEET_TRAINEE_REMAINING
}

# --- trainee mode (ticket 0014) ------------------------------------------
# fleet_trainee_remaining — print the integer max(0, TRAINEE_PR_COUNT - merged)
# where merged = count of merged feat/ PRs to main, queried once via `gh`.
#
# When TRAINEE_PR_COUNT is unset, 0, or non-numeric, print 0 and return — no
# gh call, fast-out path so the no-trainee-mode case stays free.
#
# Result is cached for the rest of this process in FLEET_TRAINEE_REMAINING_CACHED
# so a single ship run never pays for two API hits even if the prompt asks for
# the value multiple times.
#
# If `gh` is missing or the API call fails, we conservatively treat the merged
# count as 0 (i.e. all of TRAINEE_PR_COUNT remains) — the safer direction:
# operator approval requested rather than skipped. The doctor's `gh_auth`
# check surfaces the missing-gh case separately.
fleet_trainee_remaining() {
  local cap="${TRAINEE_PR_COUNT:-0}"
  # Non-numeric or 0 -> disabled.
  case "$cap" in
    ''|0|*[!0-9]*) echo 0; return 0 ;;
  esac

  if [ -n "${FLEET_TRAINEE_REMAINING_CACHED:-}" ]; then
    echo "$FLEET_TRAINEE_REMAINING_CACHED"
    return 0
  fi

  local merged=0
  if command -v gh >/dev/null 2>&1; then
    local raw
    raw="$(gh pr list \
              --state merged \
              --search "head:feat/ base:main" \
              --json number \
              --limit 100 \
              ${REPO:+--repo "$REPO"} \
            2>/dev/null || true)"
    if [ -n "$raw" ] && [ "$raw" != "[]" ]; then
      if command -v jq >/dev/null 2>&1; then
        merged="$(printf '%s' "$raw" | jq 'length' 2>/dev/null || echo 0)"
      else
        # Count `"number":` occurrences as a portable fallback.
        merged="$(printf '%s' "$raw" | tr -cd '{' | wc -c | tr -d ' ')"
      fi
    fi
  fi
  # Sanitize merged in case the fallback produced something odd.
  case "$merged" in
    ''|*[!0-9]*) merged=0 ;;
  esac

  local remaining=$(( cap - merged ))
  [ "$remaining" -lt 0 ] && remaining=0
  FLEET_TRAINEE_REMAINING_CACHED="$remaining"
  export FLEET_TRAINEE_REMAINING_CACHED
  echo "$remaining"
}

# --- prompt-version pinning ----------------------------------------------
# Ticket 0005. The optional `PROMPTS_SHA` manifest var pins the SHA256 of the
# kit's prompts/ tree that the operator last reinstalled against. If a future
# kit update changes any prompts/ file, the live runner notices the drift and
# warns — without aborting — so the operator sees the change before behavior
# silently shifts.
#
# Formula (must match `bin/fleet prompts-sha`):
#   find prompts -type f -name '*.md' | sort | xargs cat | shasum -a 256
#
# Resolution of the kit's prompts dir:
#   1. $FLEET_PROMPTS (set by this file at source time → the canonical path).
#   2. $FLEET_KIT_ROOT/prompts (escape hatch for tests / fleet-control).
#
# Behavior:
#   - PROMPTS_SHA unset  → no-op (return 0), no warn, no event.
#   - matches            → return 0, no event.
#   - mismatch           → log a warning, emit ONE `prompts_drift` event per
#                          run (guarded by FLEET_PROMPTS_DRIFT_EMITTED), and
#                          STILL return 0. This is a signal, not an abort —
#                          a fatal abort would block every project after a
#                          benign prompt edit.
#
# Public name: `fleet_check_prompts_sha` (peer of `fleet_check_budget`).
_fleet_compute_prompts_sha() {
  local dir="${FLEET_PROMPTS:-${FLEET_KIT_ROOT:-}/prompts}"
  [ -d "$dir" ] || return 1
  ( cd "$dir/.." && find prompts -type f -name '*.md' | sort | xargs cat ) \
    | shasum -a 256 | awk '{print $1}'
}

fleet_check_prompts_sha() {
  local pin="${PROMPTS_SHA:-}"
  [ -z "$pin" ] && return 0   # unset = current; no warn (per acceptance #2)

  local cur
  cur="$(_fleet_compute_prompts_sha 2>/dev/null || echo "")"
  if [ -z "$cur" ]; then
    # Can't compute → can't decide. Don't warn (would be noise across hosts
    # that vendor prompts elsewhere); return 0 quietly.
    return 0
  fi

  [ "$pin" = "$cur" ] && return 0   # matches → silent PASS

  # Mismatch. Emit one event per run; the FLEET_PROMPTS_DRIFT_EMITTED guard
  # makes a second call in the same process a silent no-op.
  if [ -z "${FLEET_PROMPTS_DRIFT_EMITTED:-}" ]; then
    echo "${SLUG:-?} prompts_drift — pinned=$pin actual=$cur (reinstall to bump or revert)"
    fleet_emit_event prompts_drift "pinned=$pin" "actual=$cur" || true
    FLEET_PROMPTS_DRIFT_EMITTED=1
    export FLEET_PROMPTS_DRIFT_EMITTED
  fi
  return 0
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

# --- budget cap -----------------------------------------------------------
# fleet_check_budget — soft-abort gate. Ticket 0004.
#
# Sums today's (UTC) `total_cost_usd` from $CACHE_DIR/runs.jsonl for this slug
# and compares against the optional MAX_DAILY_USD cap from agents.config.sh.
#   - returns 0 (proceed) when MAX_DAILY_USD is unset/empty (no cap).
#   - returns 0 when today's spend < cap.
#   - returns 1 when today's spend >= cap, AND emits a `budget_block` event
#     with reason=daily_cap so fleet-control can see WHY we no-op'd.
#
# Tolerates a missing runs.jsonl (treats spend as 0) and a record with a
# missing `total_cost_usd` field (treats that record as 0). Uses `jq` when
# available (fast, exact); falls back to a portable awk regex sum so the
# kit keeps working on minimal hosts. Comparison is float-safe via awk.
#
# Caller convention mirrors fleet_self_cancel: `fleet_check_budget || exit 0`.
fleet_check_budget() {
  local cap="${MAX_DAILY_USD:-}"
  [ -z "$cap" ] && return 0    # no cap configured = current behavior

  local runs="$CACHE_DIR/runs.jsonl"
  local today; today=$(date -u +%Y-%m-%d)
  local spent="0"

  if [ -f "$runs" ]; then
    if command -v jq >/dev/null 2>&1; then
      # jq path: filter by ts_start prefix == today and by slug, coerce
      # missing total_cost_usd to 0, sum. Best-effort: a malformed line
      # collapses the whole sum to 0, which is the safe direction (don't
      # block on a parse glitch).
      spent="$(jq -rs --arg day "$today" --arg slug "$SLUG" '
        [ .[]
          | select((.ts_start // "") | startswith($day))
          | select((.slug // "") == $slug)
          | (.total_cost_usd // 0)
        ] | add // 0
      ' "$runs" 2>/dev/null || echo 0)"
    else
      # awk fallback: regex out ts_start, slug, and total_cost_usd. The kit's
      # runs.jsonl is single-line JSON (one record per line, no embedded
      # newlines), so a per-line regex is sufficient. Missing field → 0.
      spent="$(awk -v day="$today" -v slug="$SLUG" '
        {
          ts=""; sl=""; cost=0
          if (match($0, /"ts_start"[[:space:]]*:[[:space:]]*"[^"]*"/)) {
            ts=substr($0, RSTART, RLENGTH)
            sub(/.*"ts_start"[[:space:]]*:[[:space:]]*"/, "", ts)
            sub(/".*/, "", ts)
          }
          if (match($0, /"slug"[[:space:]]*:[[:space:]]*"[^"]*"/)) {
            sl=substr($0, RSTART, RLENGTH)
            sub(/.*"slug"[[:space:]]*:[[:space:]]*"/, "", sl)
            sub(/".*/, "", sl)
          }
          if (match($0, /"total_cost_usd"[[:space:]]*:[[:space:]]*-?[0-9.eE+-]+/)) {
            c=substr($0, RSTART, RLENGTH)
            sub(/.*:[[:space:]]*/, "", c)
            cost=c+0
          }
          if (index(ts, day)==1 && sl==slug) sum+=cost
        }
        END { printf("%.6f", sum+0) }
      ' "$runs" 2>/dev/null || echo 0)"
    fi
  fi

  # Float-safe comparison. Exit 0 if spent < cap, 1 otherwise.
  if awk -v s="$spent" -v c="$cap" 'BEGIN { exit !(s+0 < c+0) }'; then
    return 0
  fi

  fleet_emit_event budget_block "reason=daily_cap" "spent=$spent" "cap=$cap" || true
  echo "${SLUG} budget_block — spent=\$${spent} >= cap=\$${cap} (UTC ${today})"
  return 1
}

# --- send-back streak auto-pause (ticket 0006) ---------------------------
# fleet_check_sendback_streak — soft-abort gate that pauses PHASE 2 of `ship`
# when the loop has been visibly failing to make progress.
#
# The signal: the last few agent-branch PRs were closed after a
# REQUEST_CHANGES review without resolution. If 3 or more of those happened
# in the last 24h, the loop is almost certainly stuck on a problem it can't
# fix without an operator, and continuing to ship new tickets just burns
# tokens. So we:
#   1. emit `ship_paused reason=sendback_streak count=<n>` on events.jsonl,
#   2. post (or update if it already exists) a meta-issue titled
#      `[FLEET] ship paused after N send-backs` carrying the PR numbers,
#   3. invoke `launchctl disable gui/$UID/$NAMESPACE.agent-ship` so the pause
#      persists across runner invocations (resume = explicit `launchctl
#      enable` by the operator or fleet-control's "Resume" action),
#   4. export FLEET_SHIP_PAUSED=1 and return 1, so `lib/ship.sh` can do
#      `fleet_check_sendback_streak || exit 0` AFTER `fleet_checkout` and
#      BEFORE handing off to the dev subagent.
#
# PHASE 1 (heal the in-flight PR) is intentionally NOT disabled here. The
# heal path runs inside the same claude invocation as ship, but it's gated
# inside the ship.prompt.md by the agent itself; if the agent sees a stuck
# in-flight PR and the env var FLEET_SHIP_PAUSED=1, it heals and stops
# without picking up a new ticket. We surface the decision through an env
# var rather than a separate code path so PHASE 1 and PHASE 2 share one
# source of truth.
#
# Agent-branch prefixes: hard-coded `feat/`, `eng/`, `chore/gtm-` per the
# ticket's engineering notes. These are fleet-wide conventions enforced by
# AGENTS.md § Agent parameters. Anything else (human cleanup branches,
# release branches) is excluded from the streak count.
#
# The window is the last 24h, measured from "now" (UTC). A PR's `closedAt`
# timestamp drives inclusion. The function tolerates a missing `reviews`
# array (treats it as "no reviews → not a send-back, skip the PR"). The
# `gh` JSON is parsed with `jq` when available and a portable awk fallback
# otherwise — same convention as fleet_check_budget.
#
# All `gh` and `launchctl` work is best-effort: a failure to post the issue
# or disable the launchd label still pauses the run (event is emitted,
# function returns 1) so we don't accidentally un-pause on a network blip.
FLEET_SENDBACK_THRESHOLD="${FLEET_SENDBACK_THRESHOLD:-3}"
FLEET_SENDBACK_WINDOW_SECONDS="${FLEET_SENDBACK_WINDOW_SECONDS:-86400}"

_fleet_is_agent_branch() {
  case "$1" in
    feat/*|eng/*|chore/gtm-*) return 0 ;;
    *) return 1 ;;
  esac
}

# Echo the ISO8601 UTC timestamp for `now - $1` seconds. Cross-platform:
# BSD `date -u -v-Ns` on macOS, GNU `date -u -d "@$(( now - N ))"` on Linux.
# We compare in the ISO8601 string space rather than parsing each PR's
# closedAt to an epoch, because ISO8601 UTC strings are lexicographically
# sortable AND BSD `date -j -f` is wonky about parsing the `Z` suffix.
_fleet_cutoff_iso() {
  local seconds="${1:?_fleet_cutoff_iso: seconds arg required}"
  date -u -v-"${seconds}"S +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
    || date -u -d "@$(( $(date -u +%s) - seconds ))" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
    || echo "1970-01-01T00:00:00Z"
}

fleet_check_sendback_streak() {
  # Need `gh` to make any decision. If it's not on PATH, conservatively
  # return 0 (proceed) — we'd rather risk a wasted ship than pause the
  # whole fleet on a missing dependency. Operator's `fleet doctor` will
  # call this out separately.
  if ! command -v gh >/dev/null 2>&1; then
    return 0
  fi

  local threshold="$FLEET_SENDBACK_THRESHOLD"
  local window="$FLEET_SENDBACK_WINDOW_SECONDS"
  local cutoff_iso
  cutoff_iso="$(_fleet_cutoff_iso "$window")"

  # Query the last 5 closed PRs that had a changes-requested review. We
  # include the reviews array so we can confirm a CHANGES_REQUESTED state
  # actually fired (gh's search operator is fuzzy enough that a defensive
  # check is cheap insurance).
  local raw
  raw="$(gh pr list \
            --state closed \
            --search 'review:changes-requested' \
            --json number,closedAt,headRefName,reviews \
            --limit 5 \
            ${REPO:+--repo "$REPO"} \
         2>/dev/null || true)"
  [ -z "$raw" ] && return 0
  # `gh` sometimes prints `[]` on an empty result; treat that as "no recent
  # send-backs" and proceed.
  [ "$raw" = "[]" ] && return 0

  # Parse: collect PR numbers whose head branch is an agent prefix AND whose
  # closedAt is within the window AND whose reviews include CHANGES_REQUESTED.
  local prs=""
  local count=0

  if command -v jq >/dev/null 2>&1; then
    # One line per PR: `<number>\t<closedAt>\t<headRefName>\t<has_changes>`
    local number closed_at branch has_changes
    while IFS=$'\t' read -r number closed_at branch has_changes; do
      [ -z "$number" ] && continue
      [ "$has_changes" = "true" ] || continue
      _fleet_is_agent_branch "$branch" || continue
      # ISO8601 UTC strings are lexicographically ordered. closedAt >= cutoff
      # means "closed within the window".
      [ -n "$closed_at" ] || continue
      [ "$closed_at" \> "$cutoff_iso" ] || [ "$closed_at" = "$cutoff_iso" ] || continue
      prs="${prs:+$prs }#$number"
      count=$((count + 1))
    done < <(printf '%s' "$raw" | jq -r '
      .[] | [
        (.number // empty),
        (.closedAt // ""),
        (.headRefName // ""),
        ((.reviews // []) | any(.state == "CHANGES_REQUESTED"))
      ] | @tsv')
  else
    # awk fallback: scrape `number`, `closedAt`, `headRefName`, and a
    # CHANGES_REQUESTED occurrence per PR object. The kit's typical host has
    # jq installed, but we keep this branch so a stripped-down environment
    # still gets correct behavior.
    #
    # Split the JSON into one object per line by inserting newlines between
    # top-level `},{` boundaries — works because gh's --json output never
    # embeds those tokens inside string values without escaping.
    local objs row
    objs="$(printf '%s' "$raw" | tr -d '\n' | sed -e 's/^\[//' -e 's/\]$//' -e 's/},{/}\n{/g')"
    while IFS= read -r row; do
      [ -z "$row" ] && continue
      local number closed_at branch
      number="$(printf '%s' "$row" | sed -n 's/.*"number"[[:space:]]*:[[:space:]]*\([0-9][0-9]*\).*/\1/p')"
      closed_at="$(printf '%s' "$row" | sed -n 's/.*"closedAt"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
      branch="$(printf '%s' "$row" | sed -n 's/.*"headRefName"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
      [ -z "$number" ] && continue
      printf '%s' "$row" | grep -q 'CHANGES_REQUESTED' || continue
      _fleet_is_agent_branch "$branch" || continue
      [ -n "$closed_at" ] || continue
      [ "$closed_at" \> "$cutoff_iso" ] || [ "$closed_at" = "$cutoff_iso" ] || continue
      prs="${prs:+$prs }#$number"
      count=$((count + 1))
    done <<< "$objs"
  fi

  if [ "$count" -lt "$threshold" ]; then
    return 0
  fi

  # --- Trip path -----------------------------------------------------------
  fleet_emit_event ship_paused "reason=sendback_streak" "count=$count" "prs=$prs" || true
  echo "${SLUG} ship_paused — $count send-backs in last $((window/3600))h (prs: $prs)"

  # Post or update the meta-issue. Idempotency: search for an open issue
  # whose title starts with `[FLEET] ship paused after` before creating one.
  local issue_title="[FLEET] ship paused after $count send-backs"
  local issue_body
  issue_body="$(printf 'Auto-paused by lib/common.sh: %d send-backs in the last %dh.\n\nPRs: %s\n\nResume: launchctl enable gui/%s/%s.agent-ship\n' \
                  "$count" "$((window/3600))" "$prs" "${UID:-$(id -u)}" "${NAMESPACE:-com.fleet.$SLUG}")"

  local existing_number=""
  local issue_raw
  issue_raw="$(gh issue list \
                  --state open \
                  --search '[FLEET] ship paused after in:title' \
                  --json number,title \
                  --limit 5 \
                  ${REPO:+--repo "$REPO"} \
               2>/dev/null || true)"
  if [ -n "$issue_raw" ] && [ "$issue_raw" != "[]" ]; then
    if command -v jq >/dev/null 2>&1; then
      existing_number="$(printf '%s' "$issue_raw" \
        | jq -r '[.[] | select((.title // "") | startswith("[FLEET] ship paused after"))] | .[0].number // empty')"
    else
      existing_number="$(printf '%s' "$issue_raw" \
        | tr -d '\n' \
        | sed -n 's/.*"number"[[:space:]]*:[[:space:]]*\([0-9][0-9]*\).*/\1/p' \
        | head -n1)"
    fi
  fi

  if [ -n "$existing_number" ]; then
    gh issue comment "$existing_number" \
      --body "$issue_body" \
      ${REPO:+--repo "$REPO"} \
      >/dev/null 2>&1 || true
  else
    gh issue create \
      --title "$issue_title" \
      --body "$issue_body" \
      ${REPO:+--repo "$REPO"} \
      >/dev/null 2>&1 || true
  fi

  # Persistent pause via launchd. `launchctl disable` survives reboots; the
  # only way out is an explicit `launchctl enable`.
  local namespace="${NAMESPACE:-com.fleet.$SLUG}"
  local uid="${UID:-$(id -u)}"
  launchctl disable "gui/$uid/$namespace.agent-ship" >/dev/null 2>&1 || true

  FLEET_SHIP_PAUSED=1
  export FLEET_SHIP_PAUSED
  return 1
}

# --- logging --------------------------------------------------------------
# $1 = phase (ship/groom/review/eng). Redirects all output to a timestamped log.
fleet_log_init() {
  local phase="$1"
  local ts; ts=$(date -u +%Y%m%d-%H%M%S)
  FLEET_LOG="$LOG_DIR/${phase}-${ts}.log"
  exec >"$FLEET_LOG" 2>&1
  RUN_STARTED_UTC="$(date -u +%FT%TZ)"
  # Epoch seconds for run_completed's duration_ms calc.
  # shellcheck disable=SC2034  # consumed by sourced runners (ship/groom/eng/review)
  RUN_STARTED_EPOCH=$(date -u +%s)
  # Exported so fleet_emit_event tags events with this phase.
  FLEET_PHASE="$phase"; export FLEET_PHASE
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
  fleet_install_prepush_hook "$workdir"
}

# --- pre-push secret scan (ticket 0008) ----------------------------------
# fleet_install_prepush_hook <checkout_dir>  — write an executable
# .git/hooks/pre-push into the given checkout that blocks the push if the
# staged/about-to-be-pushed diff contains anything that looks like a secret.
#
# The hook is self-contained (≤60 lines of body, no `jq` dependency) and:
#   1. Delegates to `gitleaks detect --no-banner --redact --staged` when
#      `gitleaks` is on PATH, propagating its exit code.
#   2. Otherwise greps the diff against six fallback patterns: anthropic,
#      github_pat, github_oauth, aws_access_key, openai, generic_kv.
#   3. On a match, exits 1 with `secret detected: <pattern>` on stderr AND
#      appends a `push_blocked reason=secret_match pattern=<name>` event to
#      $CACHE_DIR/events.jsonl by re-sourcing this lib/common.sh (path is
#      baked into the hook at install time).
#
# Diff source: when stdin carries pre-push refs (`<lref> <lsha> <rref>
# <rsha>`), the hook scans `git log -p $lsha ^$rsha`. When stdin is empty
# (the direct-invocation path used by tests), it falls back to `git diff
# --cached`, so the hook is unit-testable without a configured remote.
fleet_install_prepush_hook() {
  local checkout_dir="${1:?fleet_install_prepush_hook: checkout_dir required}"
  local hooks_dir="$checkout_dir/.git/hooks"
  [ -d "$hooks_dir" ] || return 0  # not a git checkout — nothing to install
  local hook="$hooks_dir/pre-push"
  # Bake the absolute path to this lib so the hook can re-source it for
  # fleet_emit_event regardless of where the agent's checkout lives. SLUG
  # and CACHE_DIR are also baked so the event lands in the right channel
  # even when the hook runs outside the runner's process.
  local lib_path="$FLEET_LIB/common.sh"
  local slug="${SLUG:-unknown}"
  local cache_dir="${CACHE_DIR:-$HOME/.cache/${slug}-agent}"
  cat > "$hook" <<HOOK_EOF
#!/bin/bash
# Auto-installed by fleet_install_prepush_hook (ticket 0008). DO NOT EDIT —
# any change is overwritten on the next fleet_checkout. See lib/common.sh.
set -uo pipefail
FLEET_LIB_PATH="$lib_path"
export SLUG="$slug" CACHE_DIR="$cache_dir" FLEET_PHASE="\${FLEET_PHASE:-ship}"
_emit() {
  if [ -f "\$FLEET_LIB_PATH" ]; then
    # shellcheck disable=SC1090
    ( source "\$FLEET_LIB_PATH" >/dev/null 2>&1 && \
      fleet_emit_event push_blocked "reason=secret_match" "pattern=\$1" ) || true
  fi
}
# Pick the diff source. Stdin has pre-push refs in production; empty under
# direct test invocation, in which case we fall back to the staged diff.
DIFF=""
if [ ! -t 0 ]; then
  while read -r _LREF LSHA _RREF RSHA; do
    [ -z "\$LSHA" ] && continue
    if [ "\$RSHA" = "0000000000000000000000000000000000000000" ] || [ -z "\$RSHA" ]; then
      DIFF+="\$(git log -p "\$LSHA" 2>/dev/null)"
    else
      DIFF+="\$(git log -p "\$LSHA" "^\$RSHA" 2>/dev/null)"
    fi
  done
fi
[ -z "\$DIFF" ] && DIFF="\$(git diff --cached 2>/dev/null)"
if command -v gitleaks >/dev/null 2>&1; then
  if ! gitleaks detect --no-banner --redact --staged >&2; then
    _emit gitleaks
    echo "secret detected: gitleaks reported a finding" >&2
    exit 1
  fi
  exit 0
fi
# Fallback regex set. Pattern name → ERE; order matters only for reporting.
scan() {
  local name="\$1" regex="\$2"
  if printf '%s' "\$DIFF" | grep -E -q "\$regex"; then
    echo "secret detected: \$name (pre-push blocked)" >&2
    _emit "\$name"
    exit 1
  fi
}
scan anthropic       'sk-ant-[A-Za-z0-9_-]{30,}'
scan github_pat      'ghp_[A-Za-z0-9]{36}'
scan github_oauth    'gho_[A-Za-z0-9]{36}'
scan aws_access_key  'AKIA[0-9A-Z]{16}'
scan openai          'sk-[A-Za-z0-9]{20,}'
scan generic_kv      '([Aa][Pp][Ii][_-]?[Kk][Ee][Yy]|[Ss][Ee][Cc][Rr][Ee][Tt]|[Tt][Oo][Kk][Ee][Nn]|[Bb][Ee][Aa][Rr][Ee][Rr])[[:space:]]*[:=][[:space:]]*"?[A-Za-z0-9_/+=-]{20,}'
exit 0
HOOK_EOF
  chmod +x "$hook"
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

# --- per-slug lock --------------------------------------------------------
# Prevents two launchd invocations of the same slug+phase from racing each
# other on the same checkout. macOS ships without flock(1), so we use
# `mkdir`-as-mutex: mkdir is atomic on HFS+/APFS, so the first invocation wins
# and the second's `mkdir` fails with EEXIST. Lock dir lives at
# $CACHE_DIR/lock/<phase> (per-slug because $CACHE_DIR is per-slug; cross-slug
# locking is intentionally out of scope — see ticket 0001 § Out of scope).
#
# A lock older than 6 hours is treated as stale (the holder crashed without
# releasing) and reclaimed. Six hours is well past any sane ship/groom cycle
# but short enough that a wedged runner self-heals before the next business day.
FLEET_LOCK_STALE_SECONDS="${FLEET_LOCK_STALE_SECONDS:-21600}"  # 6h

# fleet_acquire_lock <phase>  — returns 0 on success, 1 if another runner holds
# the lock (caller does `|| exit 0`). On success, exports FLEET_LOCK_DIR so
# fleet_release_lock knows what to remove.
fleet_acquire_lock() {
  local phase="${1:?fleet_acquire_lock: phase required}"
  local lock_parent="$CACHE_DIR/lock"
  local lock_dir="$lock_parent/$phase"
  mkdir -p "$lock_parent"

  if mkdir "$lock_dir" 2>/dev/null; then
    echo "$$" > "$lock_dir/pid"
    export FLEET_LOCK_DIR="$lock_dir"
    return 0
  fi

  # Lock dir exists. Is it stale?
  local now mtime age
  now=$(date -u +%s)
  # macOS stat -f %m; GNU stat -c %Y. Try BSD first (this kit runs on macOS).
  mtime=$(stat -f %m "$lock_dir" 2>/dev/null || stat -c %Y "$lock_dir" 2>/dev/null || echo "$now")
  age=$(( now - mtime ))
  if [ "$age" -gt "$FLEET_LOCK_STALE_SECONDS" ]; then
    echo "stale lock: claiming (age=${age}s > ${FLEET_LOCK_STALE_SECONDS}s, $lock_dir)"
    rm -rf "$lock_dir"
    if mkdir "$lock_dir" 2>/dev/null; then
      echo "$$" > "$lock_dir/pid"
      export FLEET_LOCK_DIR="$lock_dir"
      return 0
    fi
  fi

  local holder="unknown"
  [ -f "$lock_dir/pid" ] && holder="$(cat "$lock_dir/pid" 2>/dev/null || echo unknown)"
  # Ticket 0001: until events.jsonl (0002) ships, this skip is a plain log line.
  echo "${SLUG}-${phase} skipped — locked by ${holder}"
  return 1
}

# fleet_release_lock [phase]  — idempotent. Uses FLEET_LOCK_DIR if set
# (the common case via trap); otherwise derives the path from $1.
fleet_release_lock() {
  local target="${FLEET_LOCK_DIR:-}"
  if [ -z "$target" ] && [ -n "${1:-}" ]; then
    target="$CACHE_DIR/lock/$1"
  fi
  [ -n "$target" ] || return 0
  # Only remove if we own it. Cheap guard against blowing away another
  # runner's lock when the trap fires after our acquire failed.
  if [ -f "$target/pid" ] && [ "$(cat "$target/pid" 2>/dev/null || echo)" = "$$" ]; then
    rm -rf "$target"
  fi
  unset FLEET_LOCK_DIR
}

# --- structured events ----------------------------------------------------
# events.jsonl is the kit's typed telemetry channel (ticket 0002). One line per
# event, append-only, schema { ts, slug, phase, type, ...extras }. Shell-only —
# no jq dependency for writing. Reading still uses jq where available.
#
# _json_escape <s>  — print the JSON-string body (NO surrounding quotes) of $1.
# Escapes the two characters JSON forbids in a string ("\\" and "\"") plus the
# control chars JSON forbids unescaped (\b \f \n \r \t and the rest as \u00XX).
_json_escape() {
  local s="${1-}" out="" i ch code
  for (( i=0; i<${#s}; i++ )); do
    ch="${s:i:1}"
    case "$ch" in
      '\') out+='\\' ;;
      '"') out+='\"' ;;
      $'\b') out+='\b' ;;
      $'\f') out+='\f' ;;
      $'\n') out+='\n' ;;
      $'\r') out+='\r' ;;
      $'\t') out+='\t' ;;
      *) printf -v code '%d' "'$ch"
         if [ "$code" -lt 32 ]; then printf -v out '%s\\u%04x' "$out" "$code"
         else out+="$ch"; fi ;;
    esac
  done
  printf '%s' "$out"
}

# fleet_emit_event <type> [k=v ...]  — append one JSON line to events.jsonl.
# Every event carries ts (ISO8601 UTC), slug, phase, type. Extras are taken
# verbatim as k=v pairs and rendered as JSON keys. Best-effort: failures here
# never break the runner (caller usually invokes with `|| true`).
fleet_emit_event() {
  local type="${1:?fleet_emit_event: type required}"; shift || true
  local ts slug phase line kv k v esc_v
  ts="$(date -u +%FT%TZ)"
  slug="${SLUG:-unknown}"
  phase="${FLEET_PHASE:-unknown}"
  line="{\"ts\":\"$ts\",\"slug\":\"$(_json_escape "$slug")\""
  line+=",\"phase\":\"$(_json_escape "$phase")\""
  line+=",\"type\":\"$(_json_escape "$type")\""
  for kv in "$@"; do
    k="${kv%%=*}"
    if [ "$k" = "$kv" ]; then v=""; else v="${kv#*=}"; fi
    [ -z "$k" ] && continue
    esc_v="$(_json_escape "$v")"
    line+=",\"$(_json_escape "$k")\":\"$esc_v\""
  done
  line+="}"
  mkdir -p "$CACHE_DIR" 2>/dev/null || true
  printf '%s\n' "$line" >> "$CACHE_DIR/events.jsonl"
}
