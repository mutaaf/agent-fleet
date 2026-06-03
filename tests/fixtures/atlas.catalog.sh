#!/bin/bash
# tests/fixtures/atlas.catalog.sh — fixture catalog for tests/atlas.sh.
#
# A copy of lib/heal-catalog.sh's FLEET_HEAL_PATTERNS array, plus one
# synthetic 5th entry (`synth_pattern`) that has NO preceding `# LESSON:`
# comment — this exercises the `(no lesson)` branch from AC#5 in
# docs/backlog/0031-fleet-atlas-failure-mode-frequency.md.
#
# Loaded by `bin/fleet atlas` via the FLEET_HEAL_CATALOG env override (the
# same hook `fleet_match_infra_flake` in lib/common.sh honours). The atlas
# command parses this file as text via awk — it does NOT need to be sourced
# — so the `bash` interpreter path above is only for editor affinity.

# shellcheck disable=SC2034  # consumed by atlas_parse_catalog as text
FLEET_HEAL_PATTERNS=(
  # LESSON: agent-fleet 2026-05-26 — GitHub Actions can silently stop firing
  # for a PR. statusCheckRollup is empty and mergeStateStatus stays BLOCKED.
  # Match the empty-rollup signature OR an explicit "no runs found" trailer.
  "actions_silent|\"statusCheckRollup\":\\[\\]|no runs found"

  # LESSON: courtiq 2026-05-25 (ticket 0029) — `supabase start` fails with a
  # transient port collision on docs-only PRs. Match the literal bind error.
  "supabase_port_bind|failed to bind host port for [0-9.:]+ ?: address already in use"

  # LESSON: courtiq PR #314 2026-05-26 — actions/checkout@v4 403s with
  # "Your account is suspended" and self-clears within minutes.
  "account_suspended|Your account is suspended"

  # LESSON: courtiq 2026-05-21 (ticket 0012) — `gh pr checks --watch` aborts
  # on a transient GraphQL 502. Match the GraphQL-502 signature.
  "gh_graphql_502|GraphQL.*HTTP 502|GraphQL: .*502"

  "synth_pattern|fixture only — no real LESSON for this token"
)
