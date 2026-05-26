---
id: 0015
title: fleet tail streams live events for one or all projects
status: shipped
priority: P1
area: observability
created: 2026-05-26
owner: gtm-innovation
---

## User story

As a fleet operator at 9am with coffee, I want `fleet tail` (or `fleet tail
<slug>`) to stream events.jsonl entries live, formatted for human eyes, so
that I can watch a ship run progress in real time without `tail -f`-ing
multiple log files and parsing raw JSON.

## Why now (four lenses)

### Product Owner
`fleet digest` (0012) answers "what happened in the last 24h" as a snapshot.
`fleet doctor` (0003) answers "is everything healthy" as a snapshot.
Neither answers "what is happening RIGHT NOW" — the operator either opens
fleet-control or `tail -f`s a log and squints at raw JSON. One subcommand
collapses that into the canonical operator move: type 12 characters, see
the loop breathe. Pure subtraction over the existing daily ritual.

### Stakeholder
Widens the moat on `observability` by making events.jsonl the operator-
facing telemetry surface, not just a machine-readable channel for
fleet-control. Every new event type (added per AGENTS.md rules) lights up
the tail output automatically — consumers don't lag behind producers.

### User (operator triggering a kickstart)
After `launchctl kickstart -k gui/$UID/com.<slug>.agent-ship`, the operator
runs `fleet tail <slug>` in a separate pane and sees:

```
14:37:09  almanac/ship    run_started      pid=43210
14:37:11  almanac/ship    pr_opened        number=42 branch=feat/0019-...
14:42:18  almanac/ship    run_completed    exit=0 duration_ms=309117
```

Without the tail, the same operator opens fleet-control, refreshes, opens a
log file, refreshes. Three steps to one.

### Growth
A shareable property: anyone running the kit on their own machine can leave
`fleet tail` open in a tmux pane the way ops people leave `top` open. That's
the "show me you live with this" demo move. Pairs naturally with the
"watch me put a new repo on the fleet in 30 seconds" onboard pitch (0011).

## Acceptance criteria

Each box maps 1:1 to a test scenario in `tests/tail.sh`.

- [ ] `bin/fleet tail` (no args) follows every discovered project's
      `$CACHE_DIR/events.jsonl` concurrently. New lines stream as they
      arrive, prefixed `<HH:MM:SS>  <slug>/<phase>  <type>  <extras>`
      where `<extras>` is the `k=v` rendering of every JSON key except
      `ts`, `slug`, `phase`, `type` (those are already shown).
- [ ] `bin/fleet tail <slug>` restricts to one project. If the slug has no
      `events.jsonl` yet, prints `waiting for events.jsonl at <path>...`
      and blocks until the file appears (poll every 1s), then begins
      streaming. Test asserts the wait message and the eventual stream.
- [ ] `bin/fleet tail --since 5m` replays every event from the last 5
      minutes BEFORE following live. Supported units: `Ns`, `Nm`, `Nh`,
      `Nd`. The replay window is computed in UTC seconds (`date -u +%s`).
- [ ] `bin/fleet tail --json` skips human formatting and pipes raw JSON
      lines (the event objects exactly as they appear in events.jsonl).
      Useful for piping into `jq`. Test asserts a sample line parses
      cleanly via `node -e "JSON.parse(...)"`.
- [ ] `bin/fleet tail --type pr_opened,run_completed` filters to a comma-
      separated list of event types. Test asserts events outside the
      filter are NOT printed.
- [ ] `bin/fleet tail` exits 0 on SIGINT (Ctrl-C) and cleans up any
      background `tail -F` PIDs it started (no orphans). The test sends
      SIGINT to a launched-in-background tail invocation and asserts the
      subshell process tree is empty afterward.
- [ ] `tests/tail.sh` uses `mktemp -d` fixtures with two synthetic
      projects and appends lines to their events.jsonl files in
      background subshells while the tail runs in another, asserting
      exact stdout (formatted lines + replay output) via diff against an
      expected fixture.
- [ ] `README.md` "Daily ops" section gains a one-line callout for
      `fleet tail`.

## Out of scope

- A TUI dashboard with colored panels. Plain stdout, pipeable.
- Cross-machine event aggregation. Single host only.
- Mutating events.jsonl (e.g. ack / clear). Tail is read-only.
- Replay-without-follow mode. `fleet timeline` (a future ticket) is the
  one-shot historical reader; `tail` always follows.

## Engineering notes

- `bin/fleet` — `tail()` function. Discovery reuses the same two-root
  pattern as `doctor` (0003): `$FLEET_DISCOVERY_ROOT` and
  `~/.local/share/agent-fleet/projects`.
- Implementation strategy: shell `tail -F` (capital F survives file
  rotation, important once 0016 ships) one background process per
  discovered slug, each piping into a small formatter that runs in the
  parent process. A trap on SIGINT/SIGTERM kills the background PIDs.
- No `jq` dependency for the formatter: parse the four required JSON
  keys via `sed`/`awk` regex against the contract schema documented in
  AGENTS.md § Telemetry. Anything beyond the four required keys
  becomes `k=v` extras via a small key-extraction loop. Stay shell-only.
- `--since N` pre-roll: read existing events.jsonl lines, filter by
  parsed `ts` >= cutoff, format, print, THEN start `tail -F` from end-
  of-file.
- `tests/tail.sh` — drives the tail in a background subshell, appends
  fixture lines to events.jsonl, gives it a half-second to drain, kills
  the subshell with SIGINT, asserts stdout. Use a deterministic clock
  by overriding the formatter's timestamp via env (e.g.
  `FLEET_TAIL_FAKE_NOW=...` for the `--since` path).
- Public API: additive (`bin/fleet tail`). No `lib/` changes.
- Reinstall: not required (this is `bin/` only).
- Backwards compatibility: depends on events.jsonl schema being stable
  (it is, per AGENTS.md § Telemetry). Unknown event types must format
  generically (the schema invariant says consumers tolerate unknowns).

## Implementation log

(Appended by the implementation-dev agent during execution.)

- 2026-05-26 — implementation-dev picked up ticket. Plan: write
  `tests/tail.sh` first with one assertion block per AC, then add a
  `tail()` function to `bin/fleet` that discovers projects via the same
  two-root pattern as `doctor`, runs `tail -F` per slug in the
  background, and pipes lines through a small shell-only formatter.
  `--since`, `--type`, and `--json` flags share the same per-line
  filter+format path so the live stream and replay are identical.
- 2026-05-26 — shipped. The shell function had to be named `tail_cmd`
  (not `tail`) because a function named `tail` shadowed the system
  `tail -F` binary the background watchers spawn. The SIGINT-cleanup
  AC could not be exercised via `kill -INT` against a `&`-launched
  bash script (POSIX: a signal set to SIG_IGN on entry cannot be
  retrapped), so AC#6's test uses SIGTERM at runtime AND asserts via
  grep that the source installs `trap <fn> INT TERM` — that pair
  covers both the real-Ctrl-C path and the cleanup-of-children path.
  Replay is pre-rolled into a FIFO before the live `tail -F` watchers
  attach so historical lines stay in file order ahead of live lines.
