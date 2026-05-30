---
id: 0025
title: fleet weekly prints a Sunday ROI rollup with draft-promotion debt per project
status: in-progress
priority: P1
area: observability
created: 2026-05-30
owner: gtm-innovation
---

## User story

As a fleet operator on Sunday morning with coffee, deciding whether the
fleet was worth running this week and what — if anything — I need to do
about it, I want `bin/fleet weekly` to print a one-screen per-project
rollup covering the last 7 days: PRs shipped, dollars spent, draft
LESSONS waiting on me to promote, heal attempts spent, infra-flake
reruns, send-back streak status, and the SELF_CANCEL countdown — so
that I have a single artifact to glance at, paste into my own notes,
or take a screenshot of, instead of running five subcommands and
piecing the picture together.

## Why now (four lenses)

### Product Owner
`fleet digest` (ticket 0012) gives a daily-glance line. `fleet
overview` (ticket 0019) gives a real-time cross-project table.
Neither answers "was this week worth it?" The retention failure mode
is not knowing the answer to that — the operator stops trusting the
loop after 3-4 weeks because nothing has summarized the gains in a
way they can hand to a future self or a friend. `fleet weekly` is
explicitly NOT a real-time dashboard. It is a once-a-week ledger.
Smallest unit of value: one command, one rollup, one decision per
project (keep running / pause / bump self-cancel / promote N drafts).
Subtraction: the operator stops doing five-subcommand sweeps every
weekend.

### Stakeholder
Closes a retention gap that has been growing since ticket 0022 made
`lesson_draft_emitted` a first-class event. Draft promotion debt is
the canonical "what does the operator owe the loop?" signal, and
today nobody surfaces it — the operator has to open LESSONS.md and
count `<!-- DRAFT` markers. `weekly` makes the debt visible and
actionable. It also pairs with `prompts-score` (ticket 0024): the
weekly view tells you the headline number; `prompts-score` tells you
why. Together they make the kit's value visible week-over-week
without anyone scraping transcripts.

### User (operator on Sunday at 9:43am)
Runs `bin/fleet weekly`. Sees:

```
WEEK OF 2026-05-24 – 2026-05-30 (7d)

PROJECT       SHIPPED  $SPEND   DRAFTS↑  HEAL  INFRA  PAUSED  SELF-CANCEL
─────────────────────────────────────────────────────────────────────────
agent-fleet      6     $2.14    2*       3     1      no      29d
almanac          4     $1.87    0        2     0      no      42d
courtiq          0     $0.00    0        0     0      14d!    EXPIRED ✗
digitalcraft     2     $0.92    1*       1     0      no      5d ⚠

5* drafts waiting on you. Promote in <repo>/docs/LESSONS.md or run
`fleet digest --slug <slug>` for the per-project event tail.

ALL: 12 PRs shipped, $4.93 spent ($0.41/PR avg), 4 heal attempts,
     1 infra-flake rerun, 1 paused, 1 expired.
```

They see: courtiq expired and they hadn't noticed; digitalcraft is
≤7 days from expiry; 3 drafts across 2 projects want a 30-second pass.
Three decisions in 60 seconds: bump courtiq's `SELF_CANCEL`, do the
draft pass, ignore everything else. The "did the fleet earn its keep
this week?" question now has a yes-or-no answer (12 PRs for $4.93 →
yes).

### Growth
"Sunday morning, one screen, the whole fleet" is the line that turns
a curious adopter into a regular operator. It is also the artifact a
careful person screenshots and shares ("here's what my agent fleet
shipped this week"). That kind of share is high-leverage acquisition
content that costs the operator nothing extra to produce. Today
that artifact does not exist; the operator would have to assemble
it by hand.

## Acceptance criteria

Each box maps 1:1 to a test scenario in `tests/weekly.sh`.

- [ ] `bin/fleet weekly` (no flags) defaults to `--since 7d` and the
      current UTC week boundary, exits 0, and prints a table with
      columns: `PROJECT | SHIPPED | $SPEND | DRAFTS↑ | HEAL | INFRA |
      PAUSED | SELF-CANCEL`. Headers are printed once; one row per
      discovered project (same discovery as `digest` / `overview` —
      reuses `discover()` from `bin/fleet` line ~42).
- [ ] Metrics per row:
      - `SHIPPED` = count of merged agent PRs in the window, computed
        from `runs.jsonl` rows whose `result_head` starts with `SHIP `
        OR (preferred when both exist) from `events.jsonl`
        `pr_opened` event count crossed with the PR's
        `mergedAt` field — for v1 use the `runs.jsonl` heuristic
        only (no `gh api` call so the command works offline).
      - `$SPEND` = `digest_spend_since` reused (line ~1162), rendered
        `$N.NN`.
      - `DRAFTS↑` = count of `lesson_draft_emitted` events in the
        window from ticket 0022. Suffixed with `*` when > 0 to draw
        the eye. Zero is rendered as `0` (no asterisk).
      - `HEAL` = count of `gate_failed` events in window.
      - `INFRA` = count of `infra_flake_rerun` events in window
        (ticket 0020).
      - `PAUSED` = `Nd!` where N is days the agent-ship label has been
        disabled (via launchctl), or `no` if not paused. Reuses
        `digest_state`'s PAUSED detection (line ~1274).
      - `SELF-CANCEL` = days remaining (`Nd`, `Nd ⚠` if ≤7, `EXPIRED ✗`
        if past). Reuses `days_until()` (line ~61).
      The test fixtures runs/events for each metric and asserts
      against a checked-in golden table.
- [ ] Trailing summary line: `N* drafts waiting on you. Promote in
      <repo>/docs/LESSONS.md or run \`fleet digest --slug <slug>\` for
      the per-project event tail.` Only printed when sum(`DRAFTS↑`) > 0.
      Test asserts both branches.
- [ ] All-projects summary line: `ALL: <P> PRs shipped, $<spend>
      spent ($<avg>/PR avg), <heal> heal attempts, <infra> infra-flake
      rerun, <paused> paused, <expired> expired.` `<avg>` is omitted
      when no PRs shipped. Test asserts the summary on a fixture
      with two projects.
- [ ] `--since <Nh|Nd>` parses via `digest_parse_since` (line ~1133)
      and overrides the default 7d window. `--since 14d` is the
      operator's "biweekly" shortcut. Invalid input prints
      `weekly: invalid --since "<v>" (use Nh or Nd)` to stderr and
      exits 2. Test covers `7d`, `30d`, and `30` (invalid).
- [ ] `--slug <SLUG>` filters to one project. The trailing ALL line
      is suppressed when a slug is given. Test asserts the one-row
      table.
- [ ] `--json` prints one JSON object per project plus one trailing
      summary object. Schema:
      `{"slug":"...","shipped":N,"spend":N.NN,"drafts":N,
       "heal":N,"infra":N,"paused_days":N|null,
       "self_cancel_days":N|null,"self_cancel_state":"ok|warn|expired"}`.
      The summary object uses `{"summary":true,"prs":N,"spend":N.NN,
      "avg_per_pr":N.NN|null,"heal":N,"infra":N,"paused":N,
      "expired":N,"window_days":N}`. Test parses every line through
      `node -e 'JSON.parse(...)'`.
- [ ] Expired and paused projects appear in the table (NOT suppressed)
      — the whole point is to surface state the operator may have
      forgotten about. Test asserts both an expired and a paused
      fixture project render correctly.
- [ ] When a project has zero events AND zero runs in the window, it
      still appears with all-zero metrics. Test fixtures a "cold"
      project and asserts the row.
- [ ] `tests/weekly.sh` covers all nine boxes with `$HOME/.local/bin`
      stubs and `FLEET_DISCOVERY_ROOT` redirected to a fixture (per
      the existing `tests/overview.sh` pattern, ticket 0019). The
      fixture seeds three synthetic projects with controlled
      `runs.jsonl` + `events.jsonl` content. Asserts the table via
      a golden file at `tests/fixtures/weekly.golden.txt`. Run-time
      budget: <15s.
- [ ] No new events. `weekly` is a pure consumer of the existing
      telemetry channel (P-6: telemetry is the source of truth;
      readers compose, they do not invent). The PR body affirms
      "no new event types" so the reviewer's telemetry-contract
      check stays satisfied.

## Out of scope

The dev agent will NOT do these even if they seem related.

- A real email/push delivery of the rollup. Output is stdout. The
  operator pipes to `mail`, `ntfy`, or a file themselves. Adding a
  delivery mechanism couples the kit to one channel and bloats the
  PR.
- Time-bucketed sub-tables (day-by-day breakout within the week).
  v1 is a single column of totals. The day-by-day view is what
  `fleet tail` and `fleet digest` already deliver.
- Cross-week trend lines ("you shipped 3 fewer PRs than last week").
  Trends are `prompts-score` (ticket 0024) territory and would need
  a stable storage format for past weeks. `weekly` is point-in-time.
- HTML / PNG output. The kit stays text-only. Fleet-control can
  render later.
- Auto-promotion of LESSONS drafts. `weekly` flags the debt; the
  operator does the work (per P-9: promotion is the operator's job).
- Touching `digest` or `overview`. Those subcommands exist; this is
  a third sibling, not a refactor. Resist the urge to extract a
  shared "weekly engine."
- A scheduled launchd job for `weekly`. The operator runs it by
  hand on Sunday. Scheduling it adds a plist, a uninstall surface,
  and a "did weekly fire?" failure mode for zero added value.

## Engineering notes

- `bin/fleet` — new `weekly()` dispatcher next to `digest()` (line
  ~1324). The render is deliberately separate from `digest` because
  the column set differs (no LAST line, adds DRAFTS, PAUSED, INFRA).
  Sharing the helpers (`digest_parse_since`, `digest_iso_to_epoch`,
  `digest_spend_since`, `digest_event_count_since`,
  `digest_spend_today` — though `weekly` does not need today's
  number) keeps the row computation cheap.
- `bin/fleet` — `weekly_draft_count_since()` is the one new helper.
  It is exactly `digest_event_count_since` with
  `want_type="lesson_draft_emitted"` — name it for clarity rather
  than inlining a literal. Same for `weekly_heal_count_since` and
  `weekly_infra_flake_count_since`.
- `bin/fleet` — `weekly_paused_days()` reads
  `launchctl print-disabled gui/$UID` once, scans for the slug's
  `agent-ship` label, and reports the duration via the mtime of the
  `~/Library/LaunchAgents/com.<slug>.agent-ship.plist` (a proxy —
  the plist mtime updates on each `install.sh` run; if a project
  has been paused for less than the time since the last install,
  this overstates. Acceptable for v1 — document the limitation in
  the function comment).
- `bin/fleet` — discovery reuses `discover()` (line ~42), so
  `FLEET_DISCOVERY_ROOT` works as it does for `digest` and
  `overview`. Test uses the same root-redirect pattern.
- `tests/fixtures/weekly/` — NEW directory under `tests/fixtures/`
  holding the synthetic `agents.config.sh` files for the three
  projects the test seeds, plus the golden file. Pattern lifted
  from `tests/overview.sh` (ticket 0019).
- `lib/common.sh` — NO changes. `weekly` is a pure reader; per P-6
  it does not emit new events.
- `prompts/` — NO changes. The command is operator-facing only;
  no agent prompt reads `fleet weekly`.
- Telemetry: NO new event types. `weekly` reads only existing
  types: `lesson_draft_emitted` (0022), `gate_failed` (0002),
  `infra_flake_rerun` (0020), `pr_opened` (0002), plus runs.jsonl.
  PR body affirms "no AGENTS.md § Telemetry append needed."
- Reinstall required: NO. `lib/` and `prompts/` are untouched. PR
  body does NOT need `Reinstall: all projects`.
- BREAKING flag: NO. No `fleet_*` signature changes.
- File-edit safety: the golden file is checked in as-is; the test
  asserts via `diff -u golden actual` and fails on any byte
  difference. Per LESSONS 2026-05-27, the test NEVER does
  `$(cat golden)` then writes back — `cp` for backups, `mv` for
  swaps. This is a fresh file, not a round-trip, so the trap does
  not apply directly, but applying the rule anyway keeps tests
  consistent.
- `printf` safety per LESSONS 2026-05-28: every header / row format
  starting with a literal char is fine; if any cell value can
  start with `-` (e.g. a slug starting with `-`, which is invalid
  per the AGENTS.md spec but defensive), use `printf -- 'fmt' val`.
- Run discoverability: the new subcommand goes into `bin/fleet`'s
  help text and into the `README.md` "Daily ops" code block, on
  its own line next to `digest`. README is the only docs surface
  touched.
- Naming clash check (per LESSONS 2026-05-26 — `tail` shadowed
  `/usr/bin/tail`): `weekly` does not collide with any common
  binary on macOS or Linux. Confirmed via `command -v weekly`
  returning nothing on a fresh shell. No `_cmd` suffix needed.

## Implementation log

(Appended by the implementation-dev agent during execution.)

- 2026-05-30: Picked up by implementation-dev. Branch
  `feat/0025-fleet-weekly-roi-rollup`. Plan:
  1. Write `tests/weekly.sh` with one assertion block per AC checkbox
     and a `tests/fixtures/weekly/` directory seeding three synthetic
     projects (with `runs.jsonl` + `events.jsonl`) plus a checked-in
     golden file `tests/fixtures/weekly.golden.txt`.
  2. Implement `weekly()` in `bin/fleet` next to `digest()` —
     dispatcher + helpers (`weekly_draft_count_since`,
     `weekly_heal_count_since`, `weekly_infra_flake_count_since`,
     `weekly_paused_days`, `weekly_ship_count_since`).
  3. Add the new subcommand to the help banner at the top of
     `bin/fleet` and to README.md "Daily ops" code block.
  4. Run the local gate (`shellcheck lib/*.sh bin/fleet && bash -n
     lib/*.sh bin/fleet && node scripts/check-backlog.mjs`) green
     and `bash tests/weekly.sh` green.
  5. PR with the standard trailer; no `Reinstall:` line (no `lib/`
     or `prompts/` touch).
