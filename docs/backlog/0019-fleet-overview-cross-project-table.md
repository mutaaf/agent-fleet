---
id: 0019
title: fleet overview prints a single-glance cross-project health table
status: shipped
priority: P1
area: observability
created: 2026-05-28
owner: gtm-innovation
---

## User story

As a fleet operator on day 2 with 3-7 installed projects, I want
`bin/fleet overview` to print one table that answers "what is the fleet
doing right now?" (per project: last ship time, last review verdict,
today's send-back count, today's spend, ship paused y/n, in-flight PR
state), so that my morning glance is one command instead of opening
`fleet doctor`, `fleet digest`, and `gh pr list` on each repo.

## Why now (four lenses)

### Product Owner
Today's surfaces each answer one slice of "what's happening":
`fleet status` shows install state, `fleet doctor` validates one project,
`fleet digest` summarizes the last 24h. None of them answer the day-2
question — "across every project, is anything stuck, paused, or burning
money right now?" — without three commands and visual aggregation in the
operator's head. `overview` is the subtraction: one read, one table,
nothing new under the hood (every column already exists in
`events.jsonl` or `runs.jsonl` or launchctl). Smallest unit of value is
the table itself; nothing about the loop changes.

### Stakeholder
Widens the moat on `observability`. The kit's pitch is "uniform telemetry
across N projects" — but until a single screen renders that telemetry
aggregated, the operator still has to mentally fan-in. `overview` makes
the moat visible in five seconds. It is the natural CLI counterpart to
fleet-control's dashboard and a graceful fallback when the portal isn't
running. Existing events (`pr_opened`, `budget_block`, `ship_paused`,
`gate_failed`, `self_cancel_trip`) are the source columns — no new
event types needed.

### User (operator at 9am on Tuesday)
Types `fleet overview`. Sees:

```
PROJECT       SHIP       REVIEW    SENDBK  $TODAY   IN-FLIGHT     STATE
almanac       3m ago     ok 1h     0       $0.42    #187 GREEN    OK
courtiq       14m ago    block 2h  2       $1.18    #312 RED      HEAL
digitalcraft  6h ago     —         0       $0.00    —             PAUSED
fleet-control 31m ago    ok 4h     0       $0.31    #44 PENDING   OK
```

One glance: "courtiq is healing, digitalcraft is paused, the rest are
fine." Three seconds to decide whether today needs intervention. No
need to context-switch to a browser.

### Growth
A demoable property. "Here's what the fleet looks like across four
repos" is a screenshot a friend who runs autonomous agents will
actually want to copy. `fleet digest` (0012) is per-project lines;
this is the cross-project table that makes the kit's central pitch
("one engine, many repos") look obvious in one frame.

## Acceptance criteria

Each box maps 1:1 to a test scenario in `tests/overview.sh`.

- [ ] `bin/fleet overview` (no args) prints a header row plus one row
      per discovered project in slug-alphabetical order. Columns are
      exactly: `PROJECT`, `SHIP` (age of newest `~/.cache/<slug>-agent/logs/ship-*.log`),
      `REVIEW` (last review verdict from `events.jsonl` — `ok N` or
      `block N` where N is age), `SENDBK` (count of `--request-changes`
      review events for slug's agent PRs in the trailing 24h, computed
      via `gh pr list --search`), `$TODAY` (today's UTC sum from
      `runs.jsonl`), `IN-FLIGHT` (`#N` plus one of `GREEN`/`RED`/`PENDING`/`BEHIND`/`DIRTY`
      from `gh pr view --json mergeStateStatus,statusCheckRollup`, or
      `—` if no open agent PR), `STATE` (one of `OK`/`HEAL`/`PAUSED`/`OVER-BUDGET`/`EXPIRED`/`STUCK`).
- [ ] `STATE` derivation, in priority order: `EXPIRED` if past `SELF_CANCEL`;
      else `PAUSED` if launchctl label `<ns>.agent-ship` is `disabled`;
      else `OVER-BUDGET` if today's spend >= `MAX_DAILY_USD`;
      else `STUCK` if an open agent PR is older than 24h with no commit
      in the last 6h; else `HEAL` if the in-flight PR has any `heal:`
      prefixed commit on it; else `OK`. The state column reuses the
      same predicates from `digest_state` (0012) wherever possible — do
      not re-derive.
- [ ] Discovery scans the same two roots as `fleet doctor`/`fleet digest`:
      `~/Desktop/projects/*/agents.config.sh` AND `~/.local/share/agent-fleet/projects/*/agents.config.sh`,
      deduped by `SLUG`. Honors `FLEET_DISCOVERY_ROOT` override.
- [ ] `bin/fleet overview --slug NAME` restricts to one project. Same
      column shape, one data row.
- [ ] `bin/fleet overview --json` prints a JSON array of objects with
      one entry per project. Schema documented inline in the command
      help; keys map 1:1 to columns plus structured sub-fields
      (`ship.last_run_epoch`, `review.last_verdict`, `inflight.number`,
      `inflight.state`, `state.code`, `state.reason`).
- [ ] Exit code is 0 when no project is in `EXPIRED`, `OVER-BUDGET`, or
      `STUCK`; exit 1 otherwise. `HEAL` and `PAUSED` are not red — they
      are normal loop states. This mirrors `fleet digest`'s convention.
- [ ] When `gh` is unauthenticated or offline, the `IN-FLIGHT` column
      reads `—` (not `error`); the row still renders the local-only
      columns (`SHIP`, `$TODAY`, `STATE` minus `STUCK` detection). The
      test stubs `gh` to exit 4 and asserts the table still prints.
- [ ] Given a tmpdir fixture with three synthetic projects (alpha = OK,
      bravo = PAUSED via stubbed `launchctl print` returning
      `state = disabled`, charlie = OVER-BUDGET via a seeded
      `runs.jsonl` exceeding `MAX_DAILY_USD`), `fleet overview --json`
      produces the expected JSON array byte-for-byte.
- [ ] `README.md` "Daily ops" section gains a one-line callout for
      `fleet overview` placed between `fleet doctor` and `fleet tail`.

## Out of scope

- A TUI / curses interface. v1 is plain stdout, pipeable to `column`,
  `grep`, `awk`. The portal stays the rich UI.
- Historical roll-ups (last 7 days, sparklines). `overview` is "right
  now"; `digest` already does "last 24h" per row.
- Notifications / threshold alerts. The exit code is the alert
  primitive; the operator wires their own `cron` if they want email.
- Triggering actions from the table (resume, rollback, kickstart). Read
  only. The other subcommands do those.
- Caching. Each invocation rescans. The cost is one `gh pr list` per
  project; with 7 projects that is ~7s on a warm `gh`, acceptable for
  a daily-ish command.

## Engineering notes

- `bin/fleet` — new `overview()` function plus a dispatcher case
  branch. Reuses `discover()`, `newest_log_epoch()`, `human_age()`,
  `digest_spend_today()`, `digest_state()` from existing code paths.
  No new helpers in `lib/`.
- The `IN-FLIGHT` column needs `gh pr list --repo <repo> --state open
  --search "head:feat/ head:eng/" --json number,mergeStateStatus,statusCheckRollup,headRefName,updatedAt --limit 5`
  per project, then pick the lowest-numbered `feat/` or `eng/` PR per
  the same convention as `lib/ship.sh` Phase 1. `chore/gtm-` is
  excluded from the in-flight count (groom PRs are backlog churn, not
  shipping work).
- The `SENDBK` count for the trailing 24h reads from `events.jsonl`
  via existing `digest_event_count_since`-style parsing — no new
  event type, just filter on `type=review_blocked` (NB: that type
  does not exist yet; if a review-verdict event is missing,
  fall back to `gh pr list --search "review:changes-requested"` and
  count agent-prefix branches updated in the last 24h. Pick whichever
  is cheaper; document the choice in the engineering log).
- `tests/overview.sh` — `mktemp -d` fixture with three synthetic
  projects, stubbed `gh`, `launchctl`, and seeded `runs.jsonl` +
  `events.jsonl`. Asserts exact stdout for the table format AND for
  `--json --slug` mode. Reuses the stub patterns from `tests/digest.sh`
  and `tests/doctor.sh`.
- Public API: additive (`bin/fleet overview`). No `lib/` changes; no
  new event types. No reinstall required (bin only).
- Watch out for the `tail`-shadowing lesson (docs/LESSONS.md
  2026-05-26): name the dispatcher `overview()` — it does not collide
  with any coreutils binary, so no `_cmd` suffix is needed, but verify
  before adding.

## Implementation log

- 2026-05-28 — implementation-dev: branch `feat/0019-fleet-overview-cross-project-table`
  opened. Interpretation of the engineering notes:
  - `overview` dispatch function name is safe (no coreutils collision —
    LESSONS 2026-05-26 about `tail` shadowing). Verified `command -v
    overview` returns nothing in a fresh shell. Kept the dispatcher as
    `overview` per the ticket; no `_cmd` suffix needed.
  - `REVIEW` column source choice: `events.jsonl` has no `review_blocked`
    event type today, and the ticket explicitly authorises the fallback
    of `gh pr list --search "review:changes-requested"` per the cheapest-
    wins clause. We use the gh fallback for the absolute count
    (`SENDBK`) AND for the per-project review timestamp (`REVIEW`'s "ok
    Nh"/"block Nh" age). When `gh` is offline / unauthenticated the
    `IN-FLIGHT`, `REVIEW`, and `SENDBK` columns degrade to `—` / 0 / `—`
    respectively — the local-only columns (`SHIP`, `$TODAY`, `STATE`
    minus `STUCK`) still render. AC#7 covers this with a stubbed gh
    that exits 4.
  - State derivation reuses `digest_state` (already in bin/fleet) plus
    one delta: `digest_state` doesn't compute `HEAL` or `STUCK` from
    `gh`. The ticket asks `overview` to ADD those two; we do that in a
    second pass inside `overview()` itself, so `digest_state`'s
    predicates stay the single source of truth for `EXPIRED`/`PAUSED`/
    `OVER-BUDGET` (and `THROTTLED`, which `overview` doesn't surface).
    AC#2 priority order honoured: `EXPIRED` > `PAUSED` > `OVER-BUDGET` >
    `STUCK` > `HEAL` > `OK`.
