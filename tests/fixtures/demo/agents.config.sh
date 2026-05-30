# tests/fixtures/demo/agents.config.sh — synthetic manifest used by
# `bin/fleet kickstart --demo`. The literal __DEMO_SLUG__ token is replaced
# at runtime with a per-invocation random slug so concurrent demos cannot
# collide on a single CACHE_DIR.
SLUG="__DEMO_SLUG__"
PROJECT_NAME="agent-fleet demo"
NAMESPACE="com.fleet.demo"
REPO_URL="https://github.com/example/agent-fleet-demo.git"
# Far-future kill switch — the demo is short-lived but fleet_self_cancel
# is not called on the synthetic path; this keeps the manifest valid for
# any consumer that re-loads it after the demo exits.
SELF_CANCEL="20990101"
# Demo's cache lives next to the fixture so cleanup is one rm -rf. The
# real CACHE_DIR derivation in fleet_load_manifest is `$HOME/.cache/${SLUG}-agent`,
# so by setting SLUG to a unique demo slug we get an isolated cache
# automatically; this comment is for the reader poking at the fixture.
