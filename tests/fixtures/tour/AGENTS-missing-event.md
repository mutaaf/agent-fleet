# Fixture AGENTS.md for tests/tour.sh — DO NOT use as a real contract.

Mirrors the shape of the real AGENTS.md § Telemetry but adds one
deliberately-undefined event type (`hypothetical_future_event`) so
`node scripts/check-tour-catalog.mjs` should fail when pointed at
this file with `lib/tour-catalog.sh`.

## Telemetry

- **Event types** emitted by the kit today:
  - `run_started {pid}` — fired right after `fleet_log_init`
  - `run_completed {exit, duration_ms}` — fired right before final exit
  - `hypothetical_future_event {payload}` — not in tour-catalog yet

Add new event types in the same file.
