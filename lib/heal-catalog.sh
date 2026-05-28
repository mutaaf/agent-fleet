#!/bin/bash
# agent-fleet/lib/heal-catalog.sh — pinned CI infra-flake catalog (ticket 0020).
#
# Sourced by `lib/common.sh` (look for `FLEET_HEAL_CATALOG`). Tests override
# the path via `FLEET_HEAL_CATALOG=…` to drop in a fixture catalog without
# monkey-patching the installed copy.
#
# Shape: each entry in `FLEET_HEAL_PATTERNS` is a single string
# `<token>|<ERE>`. `fleet_match_infra_flake` walks the array in order; first
# `grep -E -q "<ERE>" <log>` win prints `<token>`.
#
# Adding a pattern is one line — bump the array, add a fixture log to
# `tests/heal-infra-flake.sh`, add a one-line LESSONS reference inline below
# so future readers can find the failure mode this codifies.
#
# Hand-curated only. Out of scope for this ticket: ML-mined patterns and a
# `fleet heal-catalog` subcommand (see docs/backlog/0020 § Out of scope).

# shellcheck disable=SC2034  # consumed by fleet_match_infra_flake in common.sh
FLEET_HEAL_PATTERNS=(
  # LESSON: agent-fleet 2026-05-26 — GitHub Actions can silently stop firing
  # for a PR. statusCheckRollup is empty and mergeStateStatus stays BLOCKED.
  # Match the empty-rollup signature OR an explicit "no runs found" trailer.
  "actions_silent|\"statusCheckRollup\":\\[\\]|no runs found"

  # LESSON: courtiq 2026-05-25 (ticket 0029) — `supabase start` fails with a
  # transient port collision on docs-only PRs. Match the literal bind error.
  "supabase_port_bind|failed to bind host port for [0-9.:]+ ?: address already in use"

  # LESSON: courtiq PR #314 — actions/checkout@v4 403s with
  # "Your account is suspended" and self-clears within minutes.
  "account_suspended|Your account is suspended"

  # LESSON: courtiq 2026-05-21 (ticket 0012) — `gh pr checks --watch` aborts
  # on a transient GraphQL 502. Match the GraphQL-502 signature.
  "gh_graphql_502|GraphQL.*HTTP 502|GraphQL: .*502"
)
