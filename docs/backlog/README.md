# Backlog — agent-fleet

The shared kit's backlog. Tickets here ship via the kit dogfooded on itself:
`implementation-dev` picks the top groomed row, `gtm-innovation` proposes new
ones, `review` grades them.

## Conventions

- `id` is a 4-digit zero-padded integer; the filename is `NNNN-kebab-title.md`.
- `status` is one of: `proposed`, `groomed`, `in-progress`, `shipped`,
  `rejected`, `needs-discovery`.
- `priority` is `P0` (oncall-now), `P1` (this week), `P2` (next), `P3` (later).
- `area` is one of: `engine`, `telemetry`, `governance`, `safety`,
  `observability`, `docs`.
- The table below MUST stay in sync with the frontmatter of each ticket file.
  CI gate `validate` runs `node scripts/check-backlog.mjs` and rejects drift.

## Index

| id | title | priority | status | area |
|----|-------|----------|--------|------|
| 0001 | Per-slug flock prevents overlapping launchd runs | P0 | shipped | safety |
| 0002 | Structured events.jsonl telemetry channel | P0 | shipped | telemetry |
| 0003 | fleet doctor subcommand for fleet health | P1 | shipped | observability |
| 0004 | Per-slug daily $ budget caps | P1 | shipped | governance |
| 0005 | Prompt-version pinning in agents.config.sh | P1 | shipped | governance |
| 0014 | Trainee mode requires operator approval for the first N PRs | P1 | shipped | safety |
| 0006 | Auto-pause ship after N consecutive send-backs | P1 | shipped | safety |
| 0011 | fleet onboard bootstraps a new project in one command | P1 | groomed | engine |
| 0008 | Secret-scan pre-push hook in agent checkouts | P1 | groomed | safety |
| 0012 | fleet digest one-line daily summary per project | P2 | groomed | observability |
| 0007 | Adaptive groom cadence when backlog is empty | P2 | groomed | engine |
| 0009 | Cross-project LESSONS aggregation | P2 | groomed | engine |
| 0010 | AGENT_DRY_RUN end-to-end mode | P2 | groomed | safety |
| 0013 | prompts/CHANGELOG.md + fleet prompts-diff explain drift | P2 | proposed | governance |
