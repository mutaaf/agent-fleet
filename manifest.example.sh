# agents.config.sh — per-project fleet manifest (PLUMBING ONLY).
#
# Copy this to <project>/agents.config.sh and fill it in. This file holds the
# values the SHELL needs (identity, schedule, spend bound). Everything the AGENT
# needs at runtime (gating checks, branch prefixes, the local gate command,
# voice, hard NOs) lives in that project's AGENTS.md "## Agent parameters"
# section — NOT here. Keep the split clean: shell reads this; claude reads AGENTS.md.
#
# After editing, re-deploy:  bash <kit>/lib/install.sh /abs/path/to/project

# --- identity -------------------------------------------------------------
PROJECT_NAME="Almanac"                                  # human label, logs only
SLUG="almanac"                                          # cache/log dir + filenames
NAMESPACE="com.almanac"                                 # launchd label prefix
REPO_URL="https://github.com/mutaaf/almanac"            # cloned into ~/.cache/<slug>-agent
MODEL="claude-opus-4-7"                                 # all agents, all phases

# Commits the agents author under this identity (your gh token still authorizes).
GIT_AUTHOR_NAME="Almanac Agent"
GIT_AUTHOR_EMAIL="noreply@anthropic.com"

# --- spend bound ----------------------------------------------------------
# YYYYMMDD UTC. After this date all agents no-op until you bump it + reinstall.
# `fleet status` warns when this is within 3 days.
SELF_CANCEL="20260628"

# Optional per-slug daily cap in USD. When set, every runner sums today's UTC
# `total_cost_usd` from runs.jsonl before spawning claude; once spend >= cap
# all runners soft-abort (exit 0) and emit a `budget_block` telemetry event.
# Unset (the default) = no cap, current behavior. Ticket 0004.
# MAX_DAILY_USD=5

# Optional trainee-mode gate: the first N feature PRs require manual merge by
# the operator (the dev agent posts a `[FLEET trainee mode K/N]` PR comment
# instead of arming auto-merge). The count graduates automatically once N
# feat/ PRs have been merged to main. 0 or unset = disabled, full autonomy
# from the first PR (current behavior). Ticket 0014.
# TRAINEE_PR_COUNT=5

# --- cadence --------------------------------------------------------------
SHIP_MINUTE=41              # ship fires every hour at this minute
GROOM_HOURS="0 6 12 18"     # groom fires at GROOM_MINUTE on these hours (local)
GROOM_MINUTE=17
REVIEW_INTERVAL=300         # review poller period, seconds (300 = every 5 min)

# --- engineering queue (optional second worker) ---------------------------
# 1 enables a peer worker on the eng/ branch prefix consuming the engineering
# backlog, with its own single-PR gate. 0 = single feature queue only.
ENG_ENABLED=0
ENG_HOURS="3 9 15 21"
ENG_MINUTE=23
