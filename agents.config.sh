# agents.config.sh — agent-fleet (the kit itself) fleet manifest.
# Semantics (gating checks, branch prefixes, local gate, hard NOs) live in
# AGENTS.md § Agent parameters. After editing, redeploy:
#   bash ./lib/install.sh /Users/mutaafaziz/Desktop/projects/agent-fleet

PROJECT_NAME="Agent Fleet"
SLUG="agent-fleet"
NAMESPACE="com.agent-fleet"
REPO_URL="https://github.com/mutaaf/agent-fleet"
MODEL="claude-opus-4-7"

GIT_AUTHOR_NAME="Agent Fleet Agent"
GIT_AUTHOR_EMAIL="noreply@anthropic.com"

SELF_CANCEL="20260625"

SHIP_MINUTE=37
GROOM_HOURS="2 8 14 20"
GROOM_MINUTE=11
REVIEW_INTERVAL=300

ENG_ENABLED=0
ENG_HOURS="5 11 17 23"
ENG_MINUTE=29
