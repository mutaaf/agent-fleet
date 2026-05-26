---
id: 0012
title: fleet digest one-line daily summary per project
status: in-progress
priority: P2
area: observability
created: 2026-05-26
owner: gtm-innovation
---

## User story

As a fleet operator, I want `fleet digest` to print a one-line summary per
project (last 24h: PRs opened/merged, $ spent, any pauses, last lesson),
so that my daily check-in is a single shell command instead of opening the
portal and clicking through five tabs.

## Why now (four lenses)

### Product Owner
Retention. Today the operator's daily ritual is "open fleet-control" — and
when the portal isn't running or they're on the phone, the loop is
invisible. A shell-native digest works from anywhere with a terminal:
`ssh` into a server, a tmux pane, a cron-mailed email. The portal stays
the rich UI; this is the keep-it-honest backup channel.

### Stakeholder
Widens the moat on `observability` and reduces dependence on fleet-control
being running. The kit becomes self-sufficient for the "what happened
today" question. The events.jsonl channel (0002) already has every signal
this needs — we just need a reader.

### User (operator at 9am with coffee)
One command. Three lines. If everything's green, glance and move on. If
something's red, the line tells you which project and why. The friction
to "check on the fleet" drops to typing 12 characters.

### Growth
A shareable property: a fleet operator who set up the kit on their
personal laptop can `crontab` `fleet digest | mail -s "fleet" me` and
get a real morning briefing. That's the kind of UX that makes someone
post about the kit.

## Acceptance criteria

Each box maps 1:1 to a test scenario in `tests/digest.sh`.

- [ ] `bin/fleet digest` (no args) prints one line per discovered project,
      in slug-alphabetical order. The line format is exactly:
      `<slug>  <state-emoji-or-tag>  <pr-summary>  $<spend>  <last-event-or-lesson>`
      where state-tag is one of `OK`, `PAUSED`, `THROTTLED`, `EXPIRED`,
      `OVER-BUDGET`, `STUCK` (no emoji unless the operator passed
      `--emoji`).
- [ ] `<pr-summary>` is `N opened / M merged` over the trailing 24h,
      computed from `runs.jsonl` (PRs referenced in `result_head`) AND
      `events.jsonl` (`pr_opened` events). When both sources disagree, the
      events.jsonl count wins (it's the source of truth).
- [ ] `<spend>` is the trailing-24h sum of `total_cost_usd` from
      `runs.jsonl`, formatted as `$X.YY`.
- [ ] `<state-tag>` derivation, in priority order: `EXPIRED` if past
      `SELF_CANCEL`; else `OVER-BUDGET` if today's spend ≥ `MAX_DAILY_USD`;
      else `PAUSED` if launchd label `agent-ship` is disabled; else
      `THROTTLED` if `$CACHE_DIR/groom-slowed-since` exists (per 0007);
      else `STUCK` if there's an open agent PR older than 24h with no
      activity in the last 6h; else `OK`.
- [ ] `<last-event-or-lesson>` is either the `type` of the most recent
      event in `events.jsonl` (with truncated extras) or, if no events in
      the last 7d, the last line of `docs/LESSONS.md`, truncated to 60
      chars.
- [ ] `bin/fleet digest --slug <name>` restricts to one project.
- [ ] `bin/fleet digest --json` prints a JSON array, one object per
      project, with all the same fields plus structured sub-fields. The
      schema is documented inline in the command help.
- [ ] `bin/fleet digest --since 7d` widens the window; default is `24h`.
      Supported units: `Nh`, `Nd`.
- [ ] Given a fixture project with seeded `runs.jsonl` + `events.jsonl`,
      `fleet digest --json --slug <name>` produces the expected JSON
      object verbatim.
- [ ] Exit code is 0 when no project is in a red state (`EXPIRED`,
      `OVER-BUDGET`, `STUCK`), 1 otherwise. This lets `crontab` / shell
      prompts use the exit code as a check.

## Out of scope

- Pushing the digest anywhere (email, Slack, Discussion). The operator
  pipes the output where they want it.
- Historical digests / time-series. v1 is "right now".
- A pretty TUI dashboard. That's fleet-control's job.

## Engineering notes

- `bin/fleet` — `digest()` function reading `events.jsonl` + `runs.jsonl`
  via `jq` if available (fallback to `awk`). Time math via `date -u +%s`.
- Discovery uses the same two-root pattern as `doctor` (0003) — reuse
  `FLEET_DISCOVERY_ROOT`.
- `tests/digest.sh` — `mktemp -d` fixtures for two projects with seeded
  jsonl files at known timestamps; assert exact stdout for the table
  format AND for `--json --slug` mode.
- Public API: additive (`bin/fleet digest`). No `lib/` changes.
- Reinstall: not required (bin only).

## Implementation log

- 2026-05-26 — implementation-dev: branched feat/0012-fleet-digest,
  flipped status to in-progress.
