# Fixture: a source manifest with ONLY the required-identity fields set.
# QUIET_HOURS, PROMPTS_PIN_SHA, LOCAL_GATE_CMD, CROSS_LESSONS,
# SHIP_PAUSE_THRESHOLD, TRAINEE_REMAINING are deliberately absent so the
# add command must skip those rows in the diff render.
PROJECT_NAME="lean"
SLUG="lean"
NAMESPACE="com.lean"
REPO_URL="git@github.com:example/lean.git"
MODEL="claude-opus-4-7"
SELF_CANCEL="20990101"
BUDGET_DAILY_USD="2.00"
ENG_ENABLED=0
