# Fixture: a fully-populated source manifest with every inheritable field set.
# Used by tests/add.sh to exercise the inheritance happy path (AC#5).
PROJECT_NAME="courtiq"
SLUG="courtiq"
NAMESPACE="com.courtiq"
REPO_URL="git@github.com:mutaaf/courtiq.git"
MODEL="claude-opus-4-7"
GIT_AUTHOR_NAME="courtiq Agent"
GIT_AUTHOR_EMAIL="noreply@anthropic.com"
SELF_CANCEL="20990101"
BUDGET_DAILY_USD="4.50"
CROSS_LESSONS="$HOME/.local/share/agent-fleet/CROSS_LESSONS.md"
QUIET_HOURS="22-07"
LOCAL_GATE_CMD="shellcheck lib/*.sh && bash -n lib/*.sh && node scripts/check-backlog.mjs"
PROMPTS_PIN_SHA="a3f1c2d"
SHIP_PAUSE_THRESHOLD="3"
TRAINEE_REMAINING="0"
SHIP_MINUTE=41
GROOM_HOURS="0 6 12 18"
GROOM_MINUTE=17
REVIEW_INTERVAL=300
ENG_ENABLED=0
