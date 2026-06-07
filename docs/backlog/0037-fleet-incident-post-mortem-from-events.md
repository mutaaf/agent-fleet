---
id: 0037
title: fleet incident assembles a window of events into a single structured post-mortem
status: in-progress
priority: P1
area: observability
created: 2026-06-07
owner: gtm-innovation
---

## User story

As a fleet operator who at 8am Monday discovers that over the weekend
agent-fleet emitted a `ship_paused` after a 3-PR send-back streak,
followed by two `lesson_draft_emitted` and one `rollback_opened`, and
who needs to reconstruct what actually happened in what order — before
writing the LESSONS paragraph that will keep the same failure mode from
recurring — I want `bin/fleet incident --since 72h [--slug NAME]` to
emit ONE structured markdown post-mortem (timeline + cluster summary +
the open recovery actions still on my plate) so I can read it, edit
it lightly, and either paste it into LESSONS or open it as a one-shot
GitHub Issue — instead of `jq`-grepping four event files and three
gh-PR-view outputs and reconstructing the story by hand at 8:15am.

## Why now (four lenses)

### Product Owner
The kit emits 17 typed events today (per `AGENTS.md § Telemetry`) and
the operator has every tool to query them one at a time — `fleet
tail`, `fleet provenance`, `fleet atlas`, `fleet overview`. None of
those tools answers the question that actually shows up after an
incident: **"give me the narrative arc of what just happened in this
window."** Every previous reader is a SNAPSHOT (one PR, one prompt
revision, one project's posture) or a TAIL (the live stream). An
incident is neither — it is a cluster of related events across phases
that span hours or days, and reading the narrative is a synthesis the
operator currently does in their head while flipping between
fleet-control panes. The smallest meaningful unit of value is one
command that produces a complete, dated, ordered markdown document:

```
# INCIDENT — agent-fleet, 2026-06-05T18:32Z → 2026-06-07T08:00Z

## Timeline

- 2026-06-05T18:32Z — `pr_opened` #88 feat/0033-quiet-hours
- 2026-06-05T19:14Z — `lesson_draft_emitted` PR #88 "QUIET_HOURS edge case…"
- 2026-06-06T02:11Z — `pr_opened` #89 feat/0033-quiet-hours-v2
- 2026-06-06T02:48Z — `lesson_draft_emitted` PR #89 "QUIET_HOURS edge case…"
- 2026-06-06T03:55Z — `pr_opened` #90 feat/0033-quiet-hours-v3
- 2026-06-06T04:33Z — `lesson_draft_emitted` PR #90 "QUIET_HOURS edge case…"
- 2026-06-06T04:33Z — `ship_paused` reason=sendback_streak count=3 prs=88,89,90
- 2026-06-06T05:12Z — `rollback_opened` pr=91 reverts=86 merge_commit=…

## Cluster summary

- 3 consecutive send-backs on the same ticket family (0033 / quiet-hours).
- All three reviewer comments converge on the same critical sub-clause.
- `ship_paused` fired correctly; PHASE 1 (heal) still allowed.
- One pre-pause merge (#86) was rolled back at 05:12Z.

## Open recovery actions

- `fleet resume agent-fleet` after promoting the 3 outstanding drafts.
- `fleet lessons-promote` to convert PR-88 / PR-89 / PR-90 drafts.
- consider `fleet prompts-revert` if review prompt is the regression.
```

Subtraction: the operator stops having to assemble this story by hand
from `events.jsonl`, `gh pr view`, and four LESSONS draft blocks.
The output IS the LESSONS source material (the cluster summary is
the symptom→cause→fix paragraph already half-written) AND the
operator's hand-off note if they need to ask a human reviewer to
look at it. Per P-5 (operator confidence over feature richness), the
win is making post-incident clarity cheap; today it is expensive
enough that operators skip it and the kit forgets.

### Stakeholder
This is moat-deepening of a kind no other autonomous-agent kit
ships: **incident-cluster reconstruction as a first-class read of
the event channel.** Today the kit has best-in-class write-side
telemetry (every interesting transition is a typed event) and
single-event read tools, but no SYNTHESIS reader. The competitive
analog is sentry/datadog's "issue grouping" — events related by
fingerprint get rolled up into one narrative. `fleet incident`
does the same for the autonomous loop, except the fingerprint is
shell-recognizable and dated rather than ML-mined. The cluster
summary is the synthesis layer: which events causally relate (a
`ship_paused` AFTER 3 `lesson_draft_emitted` on different PRs in
24h IS the streak, not a coincidence); which actions are still
outstanding (a `ship_paused` without a corresponding `ship_resumed`
is an open action); which PRs are involved. The kit's safety net
goes from "pauses when broken" to "pauses when broken AND tells
you a coherent story about why." That story IS the LESSONS draft;
the operator now edits a coherent draft instead of writing from
scratch — which compounds 0028 (`fleet lessons-promote`)'s curation
flow. Also a natural feeder for `fleet provenance` (ticket 0029):
the incident report cross-references each PR by number so
`fleet provenance <pr>` is a one-click drill-down from any
timeline row.

### User (operator Monday 8:05am, sees overnight ship_paused)
Types `fleet incident --since 72h`. Reads the timeline (15 seconds).
Reads the cluster summary (15 seconds). Sees the three open
recovery actions at the bottom. Pastes the cluster summary into
LESSONS.md as a `## 2026-06-07 — quiet-hours edge case caused
3-PR send-back streak` paragraph (the date stamp is already in the
report header), edits two sentences. Runs `fleet
lessons-promote` and `fleet resume agent-fleet`. Total elapsed: 5
minutes. Compare with today's path: open `events.jsonl`, scroll,
remember the right `jq` filter, cross-reference three PR-view
outputs in the browser, write the LESSONS paragraph from a blank
line. Today: 20 minutes if the operator stays focused. The
incident reader collapses the synthesis step from 15 minutes to
30 seconds.

### Growth
Every autonomous-agent kit eventually ships ONE big public
post-mortem ("here's how our loop went sideways and how it
recovered"). For the operators running the kit, the post-mortem
artifact IS the story they tell their team about why the autonomous
loop is worth running. Without `fleet incident`, that artifact is
hand-written and so it rarely gets written. With it, the artifact
is one command and reads as if it were authored — because the loop
DID author it from its own typed events. A friend running their
own loop sees an incident report shared in a screenshot and
immediately understands the moat: the kit is auditable in
narrative form, not just in transcript form. Pairs perfectly with
`fleet badge` (ticket 0027) as the resilience screenshot — `badge`
says "loop shipped 23 PRs this week"; `incident` says "loop also
caught and recovered from this." Compounds 0006 (`ship_paused`
event), 0017 (`rollback_opened` event), 0022
(`lesson_draft_emitted` event), 0028 (`lesson_promoted` event —
already-promoted drafts are excluded from the open-actions list),
0029 (`fleet provenance` is the per-PR drill-down).

## Acceptance criteria

Each box maps 1:1 to a test scenario in `tests/incident.sh`.

- [ ] `bin/fleet incident --since <Nh|Nd>` walks every project
      discovered under `FLEET_DISCOVERY_ROOT`, reads each
      project's `events.jsonl` (plus archive files per ticket
      0016's rotation contract), filters events in the window,
      and prints ONE markdown document to stdout. Exits 0 on
      success. The document has exactly four sections in this
      order: `# INCIDENT — <slug-list>, <iso-start> → <iso-end>`,
      `## Timeline`, `## Cluster summary`, `## Open recovery
      actions`. Test fixtures three project event channels (one
      with a clean week, one with a `ship_paused` cluster, one
      with a `prompts_drift` followed by `prompts_reverted`)
      and asserts the assembled output for the cluster-bearing
      slug against a checked-in golden
      `tests/fixtures/incident.text.golden.md`.
- [ ] `--slug NAME` narrows the report to a single project (per
      the `--slug` filter on `fleet weekly` and the
      forthcoming `fleet morning`). Empty `events.jsonl` for
      the requested slug in the window: prints
      `# INCIDENT — <slug>, <iso-start> → <iso-end>\n\nNo
      events in window. fleet is quiet — this is normal.` and
      exits 0. Test asserts both the populated and empty
      branches.
- [ ] The Timeline section lists EVERY event in the window in
      strict ISO8601 chronological order across all surveyed
      slugs, one bullet per event:
      `- <iso-ts> — \`<type>\` <one-line-payload-render>`
      where the payload render is the same shape `fleet
      tail` (ticket 0015) uses for the live stream — reuse
      the existing `tail_render_event` helper (per P-1,
      composition not duplication). Per LESSONS 2026-06-05
      (dispatcher forward-reference trap), confirm
      `tail_render_event` is defined ABOVE the `incident`
      dispatcher block, OR inline a local copy. Test
      asserts the per-event format against three event-type
      fixtures (`pr_opened`, `ship_paused`,
      `rollback_opened`).
- [ ] The Cluster summary section detects the four named
      clusters and renders a one-line bullet for each
      detected cluster ONLY (no bullet means cluster not
      detected). The clusters are:
      `sendback_streak` (>=3 `lesson_draft_emitted` events on
      DIFFERENT PRs within 24h ending in a `ship_paused`),
      `rollback_after_merge` (a `rollback_opened` event whose
      `reverts` field names a PR that earlier emitted a
      `pr_opened` in the window),
      `prompts_revision_walk` (a `prompts_drift` or
      `prompts_pin_changed` followed by a
      `prompts_reverted` within 7 days, all in the window),
      `budget_block_recurrence` (>=2 `budget_block` events
      on different UTC days within the window). Test
      asserts each of the four cluster detectors via a
      separate fixture, and asserts that a window with NO
      detectable cluster renders the bullet "No clusters
      detected — events are independent." in the section.
- [ ] The Open recovery actions section lists ONLY actions
      that have a typed-event opener but no typed-event
      closer in the channel. Specifically:
      `ship_paused` without a later `ship_resumed` → action
      `fleet resume <slug>`;
      `lesson_draft_emitted` without a later
      `lesson_promoted` whose `text_sha` cross-references
      the draft → action `fleet lessons-promote` (one row
      per outstanding draft, count summarized);
      `rollback_opened` whose revert PR is not merged
      (per `gh pr view --json state`) → action
      `merge or close revert PR #<N>`. Empty list:
      `No open actions — every incident in the window has
      a recorded recovery.` Test asserts the all-three-
      branches case AND the empty-case.
- [ ] `--json` emits one JSON object combining the three
      synthesis sections (timeline omitted from JSON to
      keep payload small — `fleet tail --json` already
      serves that need): `{"window":{"start":"<iso>",
      "end":"<iso>"},"slugs":[...],"clusters":[{"type":
      "<token>","slug":"<slug>","prs":[...],"first_ts":
      "<iso>","last_ts":"<iso>"}],"open_actions":[{"kind":
      "<resume|promote|merge_revert>","slug":"<slug>",
      "remediation":"<command-line>"}]}`. Parsed via
      `node -e 'JSON.parse(...)'`. Per LESSONS 2026-06-03
      (UTF-8 sign-extension trap) the JSON renderer uses
      `provenance_json_escape` (or an inlined copy per
      LESSONS 2026-06-05) — NEVER bare
      `doctor_json_escape`. Per LESSONS 2026-06-01 (awk
      -v multiline trap), any cluster payload that
      contains a multi-line value goes through a tmp file
      via `getline line < file`.
- [ ] `--since` is REQUIRED — there is no implicit window
      (different shape from `digest` / `weekly` /
      `atlas`'s defaulted windows, because an incident
      report is incoherent without an explicit scope).
      Missing `--since`: `incident: --since <Nh|Nd> is
      required` to stderr, exit 2. Invalid value:
      `incident: invalid --since "<v>" (use Nh or Nd)`
      to stderr, exit 2. Reuses `digest_parse_since`
      from `bin/fleet`.
- [ ] `--out FILE` writes the markdown to `FILE` instead of
      stdout (and prints `incident: wrote post-mortem to
      <FILE>` to stderr). Useful for piping into a GitHub
      Issue body. Test asserts the file path receives the
      same byte-content as stdout would on the same fixture.
- [ ] Help: `bin/fleet incident --help` prints a USAGE
      block mentioning `--since`, `--slug`, `--json`,
      `--out`. Test asserts via `grep -qF -- "$kw"
      "$help_out"` per LESSONS 2026-05-30. Help block ends
      with `exit 0` per LESSONS 2026-06-01 (dispatcher
      fall-through trap).
- [ ] The dispatcher block (`if [ "$CMD" = "incident" ];
      then incident "$@"; fi`) and the `incident()` function
      each end with explicit `exit N` on every code path
      per LESSONS 2026-06-01. Per LESSONS 2026-06-05
      (dispatcher forward-reference trap), every helper
      `incident()` calls (`tail_render_event`,
      `digest_parse_since`, `provenance_json_escape`) is
      either defined above the dispatcher block or
      inlined locally.
- [ ] `tests/incident.sh` covers all 10 boxes using
      `$HOME/.local/bin` stubs (per LESSONS 2026-05-26)
      for `gh`. The clock is frozen via
      `FLEET_NOW_OVERRIDE`. Per LESSONS 2026-05-27, the
      test uses `cp` for fixture backup/restore. Per
      LESSONS 2026-06-01 (`grep -c file || echo 0`
      double-print trap), every cluster-count uses
      `awk … END { print n+0 }`. Run-time budget:
      <15s.

## Out of scope

The dev agent will NOT do these even if they seem related.

- AUTO-emitting an `incident_report` event when a cluster is
  detected. The cluster detector is read-only by design — the
  operator is the consumer of synthesis, not another
  automation. An autonomous "emit when cluster detected"
  pathway would recursively self-incident on its own emissions.
  v1 is reader-only.
- Posting the incident report to GitHub as an Issue
  automatically. `--out FILE` + the operator's manual
  `gh issue create --body-file <file>` is the workflow; the
  command does NOT shell out to `gh issue create` itself, per
  the same posture as `fleet rollback` (which opens a PR but
  does not merge it).
- ML-grouping unrelated events into a "fuzzy" cluster. The
  four named clusters are fingerprint matches against the
  typed-event shape; any future cluster type is a discrete
  ticket. No statistical grouping in v1.
- Reading from fleet-control's portal database for any field.
  Per P-6 the source is `events.jsonl`. The portal is a
  CONSUMER of the same channel.
- Cross-fleet (`agents.config.sh` from a foreign machine).
  The report is local to this operator's discovered projects.
- A `--watch` mode that live-updates the report. The report
  is post-hoc by definition.
- Reformatting historical events to a new schema. The
  channel contract from AGENTS.md § Telemetry stands —
  unknown event types must be tolerated and rendered as
  raw lines in the timeline section.

## Engineering notes

Files / patterns the dev should touch. Specific enough that the dev
doesn't have to re-discover the architecture.

- `bin/fleet` — new `incident()` dispatcher function placed
  BELOW the helpers it calls (`tail_render_event`,
  `digest_parse_since`, `provenance_json_escape`). Per
  LESSONS 2026-06-05 (dispatcher forward-reference trap),
  confirm the order via `grep -n '^tail_render_event\|
  ^digest_parse_since\|^provenance_json_escape\|^incident'
  bin/fleet`. If any helper is defined below `incident()`,
  either move `incident()` further down OR inline a local
  copy (the same shape ticket 0034's
  `replay_batch_json_escape` resolved).
- `bin/fleet` — `incident_walk_events` reads every
  surveyed project's `events.jsonl` (plus
  `events.jsonl.archive/*.jsonl` per ticket 0016's
  rotation contract) and filters to the window via an
  awk script (timestamps are lexically sortable as
  ISO8601, so no date math needed). Per LESSONS
  2026-06-01 (awk -v multiline trap), any multi-line
  payload is buffered to a tmp file before being
  joined back. Output is one event per line as a
  JSON line — the cluster detectors consume that
  intermediate stream.
- `bin/fleet` — four cluster detectors as small awk
  scripts:
  - `incident_detect_sendback_streak` — groups
    `lesson_draft_emitted` events by 24h windows
    per slug and checks for a trailing `ship_paused`.
  - `incident_detect_rollback_after_merge` —
    cross-references `rollback_opened.reverts` against
    earlier `pr_opened.number`.
  - `incident_detect_prompts_revision_walk` —
    sequences `prompts_drift` /
    `prompts_pin_changed` / `prompts_reverted`
    within 7 days.
  - `incident_detect_budget_block_recurrence` —
    groups `budget_block` events by UTC date and
    counts distinct days.
  Each detector emits zero or more cluster JSON lines
  to a tmp file; the renderer reads the tmp file
  back.
- `bin/fleet` — three open-action detectors:
  - `incident_open_resume_actions` — pairs
    `ship_paused` with later `ship_resumed`.
  - `incident_open_promote_actions` — counts
    `lesson_draft_emitted` not matched by
    `lesson_promoted` with the same `text_sha`.
  - `incident_open_revert_merge_actions` — for
    every `rollback_opened`, calls
    `gh pr view <pr> --json state` once and
    treats `MERGED` or `CLOSED` as resolved.
    Network-touching: must run in dry-run mode
    via the existing `AGENT_DRY_RUN` guard
    (skipped in tests; the stub returns
    `state:OPEN` for the fixture revert PR).
- `bin/fleet` — `incident_render_markdown` and
  `incident_render_json` output helpers.
  Per LESSONS 2026-05-28 (printf leading-dash
  trap) every slug / PR-number / iso-ts goes
  through `printf -- '%s'`. Per LESSONS
  2026-06-03 (UTF-8 sign-extension trap) the
  JSON renderer uses the UTF-8-safe escape
  pattern (inline-copy of
  `provenance_json_escape` if forward-reference
  ordering forces it).
- `bin/fleet` — help banner block at the top of
  the file (around line ~14) gets a new line:
  `fleet incident --since <Nh|Nd>  assemble a
  post-mortem from the event channel`. README
  "Daily ops" code block gets the same line.
- `lib/common.sh` — NO changes. `incident` is a
  pure consumer of `events.jsonl` (existing) and
  `gh pr view` (existing). NO new helpers, NO
  `fleet_*` signature changes, NO new event
  types.
- `lib/install.sh` — NO changes.
- `prompts/` — NO changes. No `Reinstall: all
  projects` line needed because `lib/` and
  `prompts/` are untouched.
- `AGENTS.md` — NO new telemetry bullet (no
  new event types — the reader CONSUMES the
  contract, does not extend it).
- `tests/fixtures/incident/` — NEW directory
  under `tests/fixtures/` holding four
  scenario fixtures:
  - `sendback-streak/` — 3 `lesson_draft_emitted`
    + 1 `ship_paused` + no later `ship_resumed`.
  - `rollback-cluster/` — 1 `pr_opened` + 1
    `rollback_opened` referencing the same PR.
  - `prompts-revision-walk/` — 1 `prompts_drift`
    + 1 `prompts_reverted`.
  - `clean-week/` — only `run_started` /
    `run_completed` pairs, no cluster
    detectable.
  Plus the markdown golden file and JSON golden
  file.
- `tests/incident.sh` — top of file mirrors
  `tests/atlas.sh`: stub the discovered-projects
  iteration via `FLEET_DISCOVERY_ROOT="$TMP/
  projects"`, freeze the clock via
  `FLEET_NOW_OVERRIDE`, stub `gh` for the
  `incident_open_revert_merge_actions` branch.
  Per LESSONS 2026-05-26 stubs go in
  `$HOME/.local/bin`. Per LESSONS 2026-05-27
  use `cp` for fixture backup/restore. Per
  LESSONS 2026-06-01 (`grep -c file || echo 0`
  double-print trap), counts use
  `awk … END { print n+0 }`. Run-time budget:
  <15s.
- New deps: none. Pure shell + awk + existing
  `digest_parse_since`, `tail_render_event`,
  `provenance_json_escape`.
- Public API: additive — `bin/fleet incident`
  is a new subcommand. NO new event types. NO
  `fleet_*` signature changes. NO new manifest
  fields.
- BREAKING flag: NO. PR body affirms "no
  change to the five public `fleet_*`
  signatures," "no new event types added,"
  and "read-only consumer of the existing
  events.jsonl contract."
- Reinstall required: NO. `lib/` and
  `prompts/` are untouched.
- LESSONS to defend against: 2026-05-26
  (`tail` shadow — `incident` is namespaced).
  LESSONS 2026-05-26 (PATH reset — stubs go
  in `$HOME/.local/bin`). LESSONS 2026-05-27
  (`$(cat)` trap — fixture reads use `cp`).
  LESSONS 2026-05-28 (printf leading-dash
  trap — every slug / PR / iso-ts goes
  through `printf -- '%s'`). LESSONS
  2026-05-30 (`grep -F --` flag trap — help
  text uses `grep -qF --`). LESSONS
  2026-06-01 (awk -v multiline trap — every
  event walk uses `getline line < file`).
  LESSONS 2026-06-01 (`grep -c file || echo
  0` double-print trap — counts use
  `awk … END { print n+0 }`). LESSONS
  2026-06-01 (dispatcher fall-through trap
  — `incident()` ends with explicit `exit
  N` on every path). LESSONS 2026-06-03
  (UTF-8 sign-extension trap — JSON
  renderer uses the UTF-8-safe escape
  pattern). LESSONS 2026-06-05 (dispatcher
  forward-reference trap — `incident()`
  sits below or inlines every helper it
  calls).
- This ticket compounds 0006 (`ship_paused`
  event), 0015 (`fleet tail` —
  `tail_render_event` is the per-event
  formatter), 0016 (events rotation —
  reader walks archive files too), 0017
  (`rollback_opened` event), 0022
  (`lesson_draft_emitted` event), 0028
  (`lesson_promoted` event closes the
  draft), 0029 (`fleet provenance` is the
  per-PR drill-down for each timeline row),
  0030 (`ship_resumed` event closes the
  pause), 0035 (`prompts_reverted` event
  in the revision-walk cluster). Per
  P-1 the diff is moderate: ~300 lines of
  `incident*` helpers (four cluster
  detectors are the biggest chunk) +
  ~350 lines of test + one README line +
  one help-text line. Net new SLOC ~700.

## Implementation log

(Appended by the implementation-dev agent during execution.)

- 2026-06-07 — branch `feat/0037-fleet-incident-post-mortem` opened
- 2026-06-07 — failing tests added in `tests/incident.sh`
- 2026-06-07 — `incident()` + `incident_walk_events` + 4 cluster detectors + 3 open-action detectors + markdown/JSON renderers wired into `bin/fleet`; help banner + README "Daily ops" entry added
- YYYY-MM-DD — PR #N opened, CI [state]
- YYYY-MM-DD — merged to main
