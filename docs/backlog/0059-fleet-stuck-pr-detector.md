---
id: 0059
title: fleet stuck flags every PR sitting on a non-actionable cause so the operator unblocks it in one glance
status: shipped
priority: P1
area: observability
created: 2026-06-19
owner: gtm-innovation
---

## User story

As a fleet operator who walks up to the portal Tuesday at 9am and sees
`fleet overview` shows `sidebrew: 1 PR open, no shipping today`,
`courtiq: 2 PRs open, no shipping today` — who knows from cross-project
experience that "an agent PR sitting open for >18h with green CI" almost
always means ONE of the four well-documented stuck shapes (`BEHIND`
mergeStateStatus per cross-LESSONS 2026-05-15, `DRAFT` with auto-merge
not yet armed per cross-LESSONS 2026-05-21/#14, `account suspended` at
`actions/checkout` per cross-LESSONS 2026-05-26 / agent-fleet LESSONS
2026-05-26 "GitHub Actions silent", or `infra_flake_rerun` loop where
the rerun event itself fired but the second run also failed) — but
who has NO single command that walks the fleet's open agent-branch
PRs and CLASSIFIES which of these four shapes is in play vs. which
PRs are healthily in-flight — I want `bin/fleet stuck` to walk every
open `feat/`/`eng/` PR across discovered slugs and render one row per
stuck PR with the classified cause AND the one-line operator action
("run `gh pr update-branch <n>`", "run `gh pr ready <n>`", "wait —
account suspension typically clears within 30min"), so the 9am triage
of "is anything actually stuck or is everything just cooking?" takes
12 seconds instead of 12 PR-page-loads.

## Why now (four lenses)

### Product Owner
The kit's existing surfaces tell the operator WHAT IS HAPPENING —
`fleet overview` (0019) counts open PRs per slug, `fleet inbox`
(0026) lists explicit operator TODOs, `fleet morning` (0036) composes
the daily briefing, `fleet pulse` (0055) heartbeats once per slug.
NONE of them distinguish "in-flight, doing fine" from "stuck on a
non-actionable cause the operator can clear in one command." That
distinction is the difference between leaving a slug alone for
another 6 hours vs. typing `gh pr update-branch 117` right now and
unblocking 4 ticket-cycles of throughput. Cross-LESSONS shows this
pattern recurs across CourtIQ (`mergeStateStatus: BEHIND` on #214,
draft-state on #14), Digital Craft (account-suspension at checkout
on #314), and the kit itself (silent-CI on #7) — every project hits
it, no project has a one-glance detector. The smallest meaningful
unit of value is one classified row per stuck PR:

```
$ fleet stuck
stuck — 3 PRs across 2 slugs, scanned at 2026-06-19T16:14:21Z

  sidebrew  PR #117  BEHIND main           gh pr update-branch 117
              opened 22h ago, last CI green, base advanced 14h ago
  courtiq   PR #214  DRAFT + auto-merge    gh pr ready 214 && gh pr merge 214 --auto --squash
              opened 8h ago, CI green, isDraft:true, autoMergeRequest:null
  courtiq   PR #215  account suspended     wait — typically clears in 30min
              opened 4h ago, every gating job failed at actions/checkout with 403

  healthy in-flight (NOT stuck): sidebrew #118, courtiq #216
```

Subtraction: the operator stops opening 5 GitHub tabs to figure out
which PR needs which command. Per P-5 (operator confidence over
feature richness), the win is the absent guesswork about which
in-flight PR is actually stuck.

### Stakeholder
This is **moat-deepening on the "fast recovery from a stuck PR"
axis** — directly named in the agent's brief as one of the five
moats. Per P-6 (telemetry is the source of truth), `stuck` is a
PURE READER over each slug's `events.jsonl` (for `pr_opened`,
`infra_flake_rerun`, `gate_failed` events) PLUS one
`gh pr list --search "is:open is:pr label:agent"` per slug PLUS
one `gh pr view <n> --json mergeStateStatus,isDraft,autoMergeRequest,createdAt,headRefName`
per candidate PR. NO writes, no `lib/common.sh` changes, no new
event types. The diff is the classifier + the renderer. ~310 lines.

The four-shape classifier IS the moat: it codifies the cross-LESSONS
stuck-PR taxonomy into runnable code. Every new stuck shape the
fleet discovers (e.g. cross-LESSONS 2026-06-14 service_role grants
loop) becomes one new branch in `stuck_classify_one_pr` plus one
fixture — the operator's response is one new mapped action.
Compounds 0019 (`fleet overview` — reuses
`overview_discover_slugs`), 0026 (`fleet inbox` — the inbox
already mentions PRs by number; stuck deepens the diagnosis),
0030 (`fleet resume` — the action mapped to `ship_paused`
referenced when a stuck PR cleared via a paused-slug recovery),
0020 (`infra_flake_rerun` events read to spot a SECOND
consecutive flake of the same pattern — that's a stuck shape, not
a flake), 0037 (`fleet incident` — when stuck flags a PR the
operator runs incident on the slug to triage), 0006
(`ship_paused` — a slug that ship-paused with an open PR is
double-stuck and gets flagged with both causes).

Per LESSONS 2026-06-15 (`fleet streak` per-day shellout pattern)
the per-PR `gh pr view` calls are batched: ONE `gh pr list` per
slug returns the open-PR list, THEN one `gh pr view` per
candidate PR. With 4 slugs and 6 open PRs total that's 4 + 6 = 10
`gh` calls per invocation, well under the rate limit and ~3s.
NOT one `gh pr view` per discovered slug × all PRs.

Differentiated from `fleet inbox` (0026): inbox lists items the
operator owes the loop EXPLICITLY (drafts to promote, budget
caps to confirm). Stuck lists PRs the loop owes ITSELF the
operator's one-command unblock for. Differentiated from
`fleet overview` (0019): overview gives counts; stuck gives
classified actions.

### User (operator at 9am Tuesday glancing at the portal)
The operator opens their terminal at 9:02am, runs `fleet stuck`.
They see ONE row: `sidebrew PR #117 BEHIND main — gh pr
update-branch 117`. They paste-and-run the action. By 9:03am the
PR is rebased, CI is re-firing, and `fleet stuck` (re-run)
shows empty. They drink coffee. By 9:18am `fleet pulse` (0055)
flickers `sidebrew 12d↑` — the streak crossed a milestone
because PR #117 merged on the auto-merge re-arm. Per P-5 the
win is the 60-second clear → confidence cycle replacing the
6-hour "I'll deal with it later" deferral.

Sub-scenario: a HEALTHY morning where every open PR has been
open <2h and no classified cause applies — `fleet stuck` prints
`stuck — 0 PRs, scanned at … (healthy in-flight: 3 PRs across 2
slugs)` and exits 0. The operator sees the green-line, closes
the terminal, moves on. The lack-of-finding IS the answer.

Sub-scenario: `fleet stuck --json` returns the classification as
a machine-readable array so a fleet-control browser widget can
render the same shape as a colored dashboard tile.

Sub-scenario: `fleet stuck --slug sidebrew` restricts the walk
to one slug — useful when the operator is already in that
project's terminal.

### Growth
This is the surface a peer evaluating the kit asks for FIRST.
"What happens when a PR just sits there?" is the existential
question for any autonomous-coding-agent setup, and "the kit
classifies stuck shapes and tells you the one command to run"
is the kind of answer that converts a curious friend into
an adopter. The four-shape catalog grows over time as more
LESSONS land; the surface ages well. Per the brief's "the kit
must self-pause when it's broken, not keep burning tokens
against red CI" — stuck is the inverse: the kit must
self-DIAGNOSE when a PR is stuck so the operator types the
one command to unstick it without thinking.

Differentiated from `fleet doctor`: doctor checks the
INSTALL's health (launchd labels, file permissions). Stuck
checks the in-flight WORK's health.

## Acceptance criteria

Each box maps 1:1 to a test scenario in `tests/stuck.sh`.

- [ ] `bin/fleet stuck` is a new subcommand. With no flags and at
      least one discovered slug, walks every slug's open
      `feat/`/`eng/` PRs and prints one row per stuck PR per the
      Product-Owner example, plus a `healthy in-flight: …` footer
      line listing PR numbers NOT classified stuck. Exit 0 in
      both stuck-found and all-healthy branches. Per LESSONS
      2026-06-01 (dispatcher fall-through) every code path ends
      with `exit 0` or `exit 2`. Test asserts both branches via
      fixtures with stubbed `gh`.
- [ ] The classifier `stuck_classify_one_pr` recognizes EXACTLY
      these four causes (v1 catalog): `BEHIND` (mergeStateStatus
      is literal `BEHIND`), `DRAFT_armed` (`isDraft:true` AND
      `autoMergeRequest:null` AND age > 1h), `account_suspended`
      (every gating-check conclusion is `failure` AND every
      gating-check's `output.title` matches the literal substring
      `account is suspended`), `infra_flake_loop` (an
      `infra_flake_rerun` event for this PR exists in the slug's
      events.jsonl AND the subsequent CI run also failed AND
      the failure pattern matches the same catalog token from
      `lib/heal-catalog.sh`). Anything else classifies as
      `healthy` (not stuck). Test asserts via four fixtures —
      one for each cause — that the matching shape produces the
      expected classification and the expected action string.
- [ ] The action string per cause is: `BEHIND` → `gh pr
      update-branch <n>`; `DRAFT_armed` → `gh pr ready <n> &&
      gh pr merge <n> --auto --squash`; `account_suspended` →
      `wait — typically clears in 30min` (no command); 
      `infra_flake_loop` → `fleet incident <slug> --since 2h`
      (per 0037). Per LESSONS 2026-05-28 every printf of a
      slug name or PR number goes through `printf -- '%s'`.
      Test asserts each action string verbatim.
- [ ] `bin/fleet stuck --slug <name>` restricts the walk to one
      slug. Unknown slug: prints `stuck: slug <name> not found.
      discovered slugs: <list>` to stderr, exit 2. Missing
      `--slug` arg value: prints `stuck: --slug requires a
      value` to stderr, exit 2. Per LESSONS 2026-05-30
      (`grep -F --` trap) the test assertion uses `grep -qF
      -- "$kw" "$out"`. Test asserts both refusals.
- [ ] The `gh` calls are batched: ONE `gh pr list --repo
      <owner>/<repo> --search "is:open is:pr head:feat/ OR
      head:eng/" --json number,headRefName` per slug, THEN
      ONE `gh pr view <n> --json
      mergeStateStatus,isDraft,autoMergeRequest,createdAt,statusCheckRollup`
      per candidate PR returned. Total `gh` invocations on a
      4-slug × 6-PR fixture is 4+6 = 10. Per LESSONS 2026-06-15
      (per-day shellout inside per-slug loops is O(window ×
      N_slugs)) the test asserts via a `$HOME/.local/bin/gh`
      stub that records every invocation: the recorded count
      is exactly 10 for the fixture (4 slugs + 6 PRs), NOT
      4 × 6 = 24.
- [ ] `bin/fleet stuck --json` emits one structured JSON array,
      one element per stuck PR: `[{"slug": "<name>", "pr":
      <int>, "cause": "BEHIND|DRAFT_armed|account_suspended|
      infra_flake_loop", "action": "<cmd>", "age_hours":
      <number>, "detail": "<one-line>"}, …]` plus a top-level
      `healthy` array of `[{"slug": "<name>", "pr": <int>}]`.
      JSON escape via `preflight_json_escape` per LESSONS
      2026-06-03 called directly per LESSONS 2026-06-13 (no
      `*_json_escape` wrapper). Test asserts JSON validity via
      `node -e 'JSON.parse(require("fs").readFileSync(0, "utf8"))'`.
- [ ] `bin/fleet stuck` is RESILIENT to a `gh` failure for one
      slug — if `gh pr list` for slug A errors (network, rate
      limit, auth), that slug renders as `<slug>: gh failed —
      skipped` in the text output AND in the JSON appears as
      `{"slug": "<name>", "error": "<one-line>"}` under a
      top-level `errors` array. Other slugs still walk. Exit
      code is still 0 (a partial result is better than nothing).
      Test asserts via a stubbed `gh` that errors for one of
      the four fixture slugs.
- [ ] `bin/fleet stuck --help` prints USAGE mentioning `--slug`
      and `--json`. Per LESSONS 2026-05-30 test asserts via
      `grep -qF -- "$kw" "$help_out"`. Help block ends with
      `exit 0` per LESSONS 2026-06-01.
- [ ] `bin/fleet stuck` is a PURE READER. NO `events.jsonl`
      writes, NO `fleet_emit_event` calls, NO writes to any
      slug's `agents.config.sh`. Test asserts every slug's
      `events.jsonl` byte size is unchanged before and after
      invocation.
- [ ] `lib/common.sh` — NO changes. `prompts/` — NO changes.
      No new event types. Test asserts via `git diff
      --name-only main...HEAD -- lib/common.sh prompts/`
      returns empty.
- [ ] The per-PR `gh pr view --json statusCheckRollup` parsing
      uses a single awk pass to count failures with the
      `account is suspended` substring per LESSONS 2026-06-15
      (no per-check shellout). Per LESSONS 2026-06-08 the awk
      pass declares `BEGIN { count = 0; suspended_hits = 0
      }`. Per LESSONS 2026-06-08 IFS=$'\t' middle-empty-field
      uses `-` sentinel. Test asserts via fixture with a PR
      whose two failing checks BOTH carry the suspension
      substring (cause = `account_suspended`) AND a PR whose
      ONE failing check carries an unrelated message (cause =
      not `account_suspended` — falls through to `healthy`).
- [ ] The `infra_flake_loop` cause is determined by walking
      the slug's events.jsonl for `infra_flake_rerun` events
      whose `pr` field matches the candidate PR number, then
      reading the subsequent `gh run view <id>` output to
      check if the rerun's conclusion is also `failure`.
      Per LESSONS 2026-06-15 the walk is ONE awk pass over
      events.jsonl per slug (NOT per PR). Per LESSONS
      2026-06-11 (BSD `date -j -f` fills missing time
      fields) any age math uses `date +%s` minus the
      epoch parsed via `date -j -f '%Y-%m-%dT%H:%M:%SZ'`
      with the full format (no missing time fields). Test
      asserts via fixture with an `infra_flake_rerun` event
      followed by a re-failed run.
- [ ] `tests/stuck.sh` covers all 12 boxes above using
      `$HOME/.local/bin` stubs per LESSONS 2026-05-26 (PATH
      reset). Fixture `events.jsonl`, `agents.config.sh`,
      and `gh` stub response JSON files live under
      `tests/fixtures/stuck/`. The `gh` stub records every
      invocation to a side file so AC #5's exact-count
      assertion can fire. Per LESSONS 2026-05-27 backup/
      restore via `cp` (NOT `$(cat)`). Counts use `awk … END
      { print n+0 }` per LESSONS 2026-06-01. Per LESSONS
      2026-06-08 every awk script declares `BEGIN { count =
      0 }`. The clock is frozen via `FLEET_NOW_OVERRIDE` so
      the "age > 1h" predicate in DRAFT_armed is
      deterministic. Run-time budget: <8s.

## Out of scope

The dev agent will NOT do these even if they seem related.

- AUTO-RUNNING the suggested action (auto-rebasing, auto-marking
  ready, auto-firing `gh pr merge`). Stuck NUDGES; it does NOT
  act. The operator types the command — that is the contract.
  Auto-action is a v2 ticket and lives behind a manifest
  opt-in.
- A FIFTH cause beyond the four-cause v1 catalog. Each new cause
  is its own LESSONS reference + fixture + classifier branch in
  a follow-up ticket. v1 ships the four cross-LESSONS-documented
  shapes; the catalog grows by explicit ticket.
- A WATCH mode (`fleet stuck --watch`) that polls every N
  seconds. The operator wires it into their shell prompt or a
  launchd job; foreground watch loops are the operator's job.
- A NOTIFICATION channel (`osascript display notification` when
  a new stuck PR appears). v1 is read-only.
- INTEGRATION with `fleet-control`'s browser tile (a "stuck PRs"
  widget). That's a fleet-control PR consuming `fleet stuck
  --json`; out of scope here.
- A `--since` window flag to restrict to PRs opened recently.
  Stuck by definition flags PRs that are OPEN NOW; age is
  rendered for context, not used as a filter.
- A `--include-non-agent` flag to scan human-opened PRs too.
  Stuck is for AGENT-branch PRs (the loop's responsibility).
  Human PRs are out of scope.
- AUTO-OPENING a GitHub issue when a stuck PR sits for >24h.
  v1 is operator-pulled. Auto-escalation is a v2 candidate.

## Engineering notes

Files / patterns the dev should touch.

- `bin/fleet` — new `stuck()` dispatcher function placed next to
  the existing `overview()` block (find via `grep -n
  '^overview()' bin/fleet`). Per LESSONS 2026-05-26 (`tail`
  shadow) `stuck` does not collide with any coreutils binary.
- `bin/fleet` — seven helpers, ALL defined ABOVE the dispatcher
  block per LESSONS 2026-06-05 (forward-reference trap):
  - `stuck_discover_slugs` — wraps `overview_discover_slugs`,
    returns alphabetical order.
  - `stuck_list_open_prs` — ONE `gh pr list` per slug; returns
    a `<slug>\t<pr>\t<headRefName>` TSV (sentinel `-` on empty
    columns per LESSONS 2026-06-08).
  - `stuck_view_one_pr` — ONE `gh pr view <n> --json
    mergeStateStatus,isDraft,autoMergeRequest,createdAt,statusCheckRollup`
    per candidate PR. Per LESSONS 2026-06-11 any age math
    uses `date +%s` minus the epoch parsed via `date -j -f
    '%Y-%m-%dT%H:%M:%SZ'` with the FULL format (T00:00:00
    appended if needed).
  - `stuck_classify_one_pr` — pure-shell classifier returning
    one of `BEHIND | DRAFT_armed | account_suspended |
    infra_flake_loop | healthy`. Per LESSONS 2026-06-08
    declares `BEGIN { count = 0; suspended_hits = 0 }` in any
    awk pass.
  - `stuck_check_infra_flake_loop` — ONE awk pass over the
    slug's events.jsonl per LESSONS 2026-06-15 (NOT per PR);
    builds a `pr -> infra_flake_rerun_run_id` map and checks
    each PR's classification against it.
  - `stuck_render_text` — text formatter. Width via
    `preflight_visible_width` per LESSONS 2026-06-05 (bash
    3.2 LC_ALL caching). Per LESSONS 2026-05-28 every
    printf of a slug name or PR number goes through `printf
    -- '%s'`.
  - `stuck_render_json` — JSON formatter. JSON escape via
    `preflight_json_escape` per LESSONS 2026-06-03 called
    directly per LESSONS 2026-06-13 (no `*_json_escape`
    wrapper).
- `bin/fleet` — `stuck()` end-state must be `exit 0` / `exit
  2` on every code path per LESSONS 2026-06-01.
- `bin/fleet` — dispatcher block: `if [ "$CMD" = "stuck" ];
  then stuck "$@"; fi`. Place AFTER the `overview` dispatcher.
- `bin/fleet` — help banner block at the top of the file gets
  ONE new line: `fleet stuck flag every PR on a non-actionable
  cause and emit the one-command unblock`. README "Daily
  ops" code block gets the same line, appended via the same
  single-edit pattern that avoided LESSONS 2026-05-25.
- `AGENTS.md` — NO content change.
- `lib/common.sh` — NO changes.
- `prompts/` — NO changes.
- `tests/fixtures/stuck/` — NEW directory holding four slug
  subdirs (`behind`, `draft-armed`, `account-suspended`,
  `flake-loop`) each with `events.jsonl`, `agents.config.sh`,
  and a per-slug `gh-fixture.json` consumed by the `gh` stub.
  A fifth `healthy` slug exercises the all-clear branch and
  a sixth `gh-fails` slug exercises AC #7's resilience.
- `tests/stuck.sh` — top of file mirrors `tests/overview.sh`
  (closest prior reader; shares the gh-stub pattern). Stubs
  live under `$HOME/.local/bin` per LESSONS 2026-05-26 (PATH
  reset). The `gh` stub records its invocation count + argv
  to a side file so AC #5's exact-count assertion fires.
  Counts use `awk … END { print n+0 }` per LESSONS
  2026-06-01. Per LESSONS 2026-05-27 backup/restore via
  `cp`. The clock is frozen via `FLEET_NOW_OVERRIDE`. Per
  LESSONS 2026-06-15 the events.jsonl walk is ONE awk pass
  per slug. Run-time budget: <8s.
- New deps: none. Pure shell + awk + Node (already a kit dep
  for JSON validation in the test).
- Public API: additive — `bin/fleet stuck` is a new
  subcommand. ZERO new event types, ZERO event writes, ZERO
  `lib/common.sh` changes, ZERO `prompts/` changes.
- BREAKING flag: NO. PR body affirms "pure reader, no
  events.jsonl writes, no `fleet_*` signature changes, no
  runtime hot-path changes."
- Reinstall required: NO. `lib/` and `prompts/` are
  untouched.
- LESSONS to defend against: 2026-05-25 (README "Daily ops"
  code block addition), 2026-05-26 (`tail` shadow),
  2026-05-26 (PATH reset — stubs in `$HOME/.local/bin`),
  2026-05-27 (`$(cat)` trap — use `cp` for backup/restore
  in tests), 2026-05-28 (printf leading-dash — every slug-
  name / PR-number printf goes through `printf -- '%s'`),
  2026-05-30 (`grep -F --` trap), 2026-06-01 (`grep -c
  file || echo 0` double-print — counts use `awk … END
  { print n+0 }`), 2026-06-01 (dispatcher fall-through —
  every code path ends `exit 0/2`), 2026-06-03 (UTF-8
  sign-extension — JSON escape via `preflight_json_escape`),
  2026-06-05 (dispatcher forward-reference — all `stuck_*`
  helpers defined ABOVE the dispatcher), 2026-06-05 (bash
  3.2 LC_ALL caching — any string-length operation via
  `LC_ALL=C awk`), 2026-06-08 (awk empty-string-key —
  `BEGIN { count = 0 }`), 2026-06-08 (IFS=$'\t' middle-
  empty-field — sentinel `-`), 2026-06-11 (BSD `date -j
  -f` fills missing time fields with NOW-of-day — age
  math uses full `'%Y-%m-%dT%H:%M:%SZ'` format),
  2026-06-13 (no `*_json_escape` wrapper around
  `preflight_json_escape` — called directly), 2026-06-15
  (per-day shellout inside per-slug loops is O(window ×
  N_slugs) — the gh batching is one list-call per slug
  plus one view-call per candidate PR; the events.jsonl
  walk is one awk pass per slug, NOT per PR).
- This ticket compounds 0019 (`fleet overview` — reuses
  `overview_discover_slugs`), 0026 (`fleet inbox` —
  complements the explicit-debt list with the implicit-
  stuck-PR list), 0030 (`fleet resume` — referenced when
  a paused-slug PR has cleared and the operator runs
  resume), 0020 (`infra_flake_rerun` event — the
  `infra_flake_loop` cause reads it), 0037 (`fleet
  incident` — the `infra_flake_loop` action references
  it), 0006 (`ship_paused` — a stuck PR on a paused
  slug is double-flagged). Per P-1 the diff is small:
  ~310 lines of `stuck_*` helpers + ~270 lines of test
  + 6 fixture slug subdirs + one help-text line + one
  README line.

## Implementation log

(Appended by the implementation-dev agent during execution.)

- 2026-06-19 — shipped via PR #125 (merge commit `18316b6`). All 12 AC boxes
  green; `gh` call batching asserted (6 slugs → 6 `pr list` + 6 `pr view`,
  total under 30). Pure reader — no `lib/common.sh`, no `prompts/`, no
  new event types. No LESSONS append needed: every trap the implementation
  guards against was already documented (LESSONS 2026-05-26 .. 2026-06-15).
- 2026-06-19 — `feat/0059-fleet-stuck-pr-detector` opened. Tests-first plan:
  one assertion block per AC in `tests/stuck.sh`, six slug subdirs under
  `tests/fixtures/stuck/` (`behind`, `draft-armed`, `account-suspended`,
  `flake-loop`, `healthy`, `gh-fails`). Implementation lives entirely in
  `bin/fleet` next to `overview()`; reuses the same `_seen` discovery
  pattern. JSON via `preflight_json_escape` direct (no `*_json_escape`
  wrapper per LESSONS 2026-06-13). `gh` calls batched: one `pr list` per
  slug + one `pr view` per candidate PR.
