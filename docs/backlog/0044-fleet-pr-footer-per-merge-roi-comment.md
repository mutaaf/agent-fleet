---
id: 0044
title: fleet pr-footer posts a per-merge ROI comment on every agent-shipped PR
status: shipped
priority: P1
area: observability
created: 2026-06-11
owner: gtm-innovation
---

## User story

As a fleet operator whose teammates / friends / open-source collaborators
read agent-shipped PRs and ask "wait, an autonomous agent merged this —
how much did it cost? how do I know it didn't ruin the repo?", I want
`bin/fleet pr-footer <pr>` (called once at the tail of the ship runner
right after `gh pr merge --auto --squash` succeeds and is also operator-
invocable post-hoc on any merged PR) to post a single GitHub PR comment
with a date-stamped ROI footer — `cost $0.42 · duration 6m12s ·
ticket-to-date $5.83 / 18 PRs · prompts pin <short-sha> · LESSONS read
412 lines · fleet @ <kit-sha>` — so that every skeptical reader who
opens the PR sees the trust artifact INSIDE the PR itself, without
having to install the kit, scrape events.jsonl, or take my word for
"it's cheap, I promise."

## Why now (four lenses)

### Product Owner
`fleet badge` (0027) ships a README-level artifact and `fleet weekly`
(0025) ships an operator-private terminal artifact. Neither lives at
the unit a skeptical engineer actually reads: the PR itself. Today
when an outsider lands on an agent-shipped PR they see a normal
commit, normal CI rollup, normal review trail — and zero indication
that the loop is governed, budgeted, or auditable. The footer turns
every merged PR into its own trust artifact: a one-line receipt that
answers "what did the loop spend on this and how?" in place.

Subtraction: the operator stops doing one-off "the loop cost $X" Slack
replies when a teammate asks. The footer IS the reply, and it travels
with the PR forever. Per P-5 (operator confidence over feature
richness), the win is converting a recurring outside-the-loop
question into a one-line in-the-loop answer.

The smallest meaningful unit of value is one comment per merged PR:

```
<!-- fleet-roi-footer v1 -->
🤖 **fleet receipt** · cost **$0.42** · duration **6m12s**
ticket-to-date · **$5.83** / **18 PRs** in the last 30d
pinned prompts: [`ee94b3a`](../tree/ee94b3a/prompts) ·
LESSONS: 412 lines · kit: [`8a20547`](../commit/8a20547)

_powered by [agent-fleet](https://github.com/mutaaf/agent-fleet) · this
footer is appended automatically and contains no secrets._
```

### Stakeholder
This is **moat-deepening on the trust axis** — the kit's first
artifact that lives WHERE THE WORK LANDS (the PR itself) rather than
in the operator's terminal. Per the brief's "trust-building artifacts
for skeptical engineers ('show me this won't ruin my repo')", this is
the most leveraged answer. A skeptical engineer reviewing an agent
PR for the first time gets:

- A cost number (proves the loop is bounded).
- A duration (proves the loop is responsive, not a long-running daemon).
- A 30-day ROI rollup (proves THIS isn't a one-off lucky run).
- A pinned prompts SHA (proves the loop is reproducible).
- A LESSONS line count (proves the loop has memory).
- A kit SHA (proves the engine is auditable).

All six are already in the local telemetry channel; no new event
types, no new state file. The footer is a PURE READER of
`runs.jsonl` (cost, duration), `events.jsonl` (PR count from
`pr_opened`), `agents.config.sh` (`PROMPTS_SHA` pin),
`docs/LESSONS.md` (line count via `wc -l`), and `git rev-parse`
(kit SHA).

Per P-6 (telemetry is the source of truth), every value in the
footer cites a single source — there's no derived "ROI" magic
number; every claim is a count or sum the reader could re-derive.
Per P-1 (smallest viable change), the diff is one composer
function + one `gh api repos/.../issues/N/comments` POST + one
test harness using a `gh` stub.

This compounds 0025 (`fleet weekly` — shares the 30-day rollup
math per slug), 0027 (`fleet badge` — shares the cost/PR-count
fold), 0029 (`fleet provenance` — shares the pinned-prompts /
kit-SHA composition). Per P-3 (heal in-flight first), the
footer is posted AFTER auto-merge succeeds; it never blocks the
heal path.

### User (skeptical engineer on a Tuesday, reviewing an agent PR
linked from a Slack message)
Friend says "look at this — an agent shipped this." Engineer opens
the PR. Sees a clean diff, sees CI green, scrolls down. The very
last comment, dated the moment of merge, is the fleet receipt:
"$0.42 to ship, 30 days of context, here's the pinned prompts
SHA, here's the kit SHA." Engineer's mental model flips from "this
is a black box" to "this is a reproducible, bounded, auditable
loop." Engineer DMs back: "OK, what's the install command?"

The operator's emotional surface shifts too: instead of
intermittent "how is the loop doing?" Slack questions, the
operator gets a quieter Slack because every PR carries its own
explanation. Per P-5, this is operator confidence in its purest
form — the loop now self-justifies on the public surface where
it ships.

### Growth
The footer is the kit's first artifact designed to be **publicly
visible by default** on every shipped PR. Anyone who lands on an
agent-shipped PR (a recruiter looking at the operator's GitHub,
a teammate reviewing for context, a search-engine crawler) sees
the kit attribution + cost transparency without the operator
doing anything.

Every PR a fleet ships becomes a passive discovery surface for
the kit — the inverse of the badge (which requires the operator
to opt-in via a README edit). With pr-footer enabled, the
default is "every merged PR is a fleet ad." Opt-out is a
manifest flag (`PR_FOOTER_ENABLED=0`); opt-in is the kit
upgrading. Per the brief's "Sharing / external visibility...
is there a next step — a public dashboard, a per-PR comment
artifact, a one-line 'ROI brag' for a README?" — this is the
direct answer.

Compounds the acquisition path: `kickstart --demo` (0023) shows
the loop, `preflight + onboarding-check` (0032 + 0041) installs
it, and pr-footer is the artifact a friend who NEVER ran the
demo encounters in the wild and asks about. Three acquisition
moments, three personas; this ticket adds the fourth, the
"discovered the kit because I happened to read a PR" path.

## Acceptance criteria

Each box maps 1:1 to a test scenario in `tests/pr-footer.sh`.

- [ ] `bin/fleet pr-footer <pr>` is a new subcommand. Takes a single
      PR number argument. Looks up the PR's metadata via `gh pr view
      <pr> --json number,title,mergedAt,mergeCommit,baseRepository,
      headRefName` and confirms (a) the PR is merged, (b) the
      branch prefix matches one of the manifest's agent prefixes
      (`feat/`, `chore/gtm-`, `eng/`). Refusal paths: not merged
      → print `pr-footer: PR #N is not merged (state: <state>);
      footer is only posted on merged PRs` to stderr exit 2;
      branch prefix mismatch → print `pr-footer: PR #N is not an
      agent PR (branch: <branch>); only feat/, chore/gtm-, eng/
      branches get a footer` to stderr exit 2. Test asserts both
      refusals via `gh` stub fixtures.
- [ ] On a valid agent-merged PR, the footer body is composed
      from six values: (1) `cost` — the `total_cost_usd` from the
      `runs.jsonl` row whose `result_head` cites this PR number
      (fallback `unknown` when not found); (2) `duration` — the
      `duration_ms` from the same row, formatted as `Nm`Ns``
      (fallback `unknown`); (3) `ticket-to-date` — the sum of
      `total_cost_usd` over `runs.jsonl` rows in the trailing
      30 days for this slug, formatted as `$X.XX`; (4) `pr-count`
      — the count of `type=pr_opened` events in the same 30-day
      window; (5) `prompts_pin` — the manifest's `PROMPTS_SHA`
      (or `unset` when not pinned); (6) `lessons_lines` — `wc -l
      < docs/LESSONS.md` from the kit's checkout; (7) `kit_sha`
      — `git rev-parse --short HEAD` from the kit's checkout. Test
      asserts each value's source helper against fixtures.
- [ ] The footer is posted via `gh pr comment <pr> --body
      "<body>"` (NOT `--edit-last`, NOT replacing an existing
      comment). The body is wrapped in a sentinel HTML comment
      `<!-- fleet-roi-footer v1 -->` on the first line so the
      idempotency check below can recognize it. Subsequent
      `bin/fleet pr-footer <pr>` invocations on the same PR
      detect the existing footer via `gh pr view <pr> --json
      comments` and SKIP re-posting with `pr-footer: PR #N
      already has a fleet-roi-footer (skipping)` to stdout exit
      0. Test asserts the idempotent re-run via a `gh`-stub
      that returns the prior comment.
- [ ] The footer body is plain markdown, ASCII-only for v1 (per
      the LESSONS 2026-06-03 sign-extension guard — a single
      `🤖` emoji is permitted because gh's REST API
      independently handles UTF-8 in the body via JSON, but the
      composer goes through `preflight_json_escape` per LESSONS
      2026-06-03 and asserts every other body character is in
      the ASCII printable range). Test asserts via
      `LC_ALL=C awk '!/^[\x20-\x7e]+$/'` on the composed body
      (with the emoji line stripped first).
- [ ] `lib/ship.sh` PHASE 1 / PHASE 2 emits a one-line hook
      after a successful `gh pr merge --auto --squash`: if
      `PR_FOOTER_ENABLED=1` is set in the manifest (default 1
      when unset — per the v1 acquisition bet) AND the manifest
      declares a `PR_FOOTER_ENABLED` value at all (treat unset
      as 1 explicitly for forward compatibility), invoke
      `bin/fleet pr-footer <pr>` in the background with output
      redirected to the run log. `PR_FOOTER_ENABLED=0` skips
      the hook. Test asserts both manifest values via a fixture
      ship run with a stubbed `gh pr merge`.
- [ ] A new manifest knob `PR_FOOTER_ENABLED` is added to
      `manifest.example.sh` with a comment explaining its
      acquisition rationale. The kit's own `agents.config.sh`
      sets `PR_FOOTER_ENABLED=1` (the kit dogfoods the
      acquisition surface). Test asserts via `grep -F --
      'PR_FOOTER_ENABLED=' manifest.example.sh`.
- [ ] `bin/fleet pr-footer --help` prints USAGE mentioning the
      PR number argument, the `PR_FOOTER_ENABLED` manifest
      knob, and the idempotency contract. Test asserts via
      `grep -qF -- "$kw" "$help_out"` per LESSONS 2026-05-30.
      Help block ends with `exit 0` per LESSONS 2026-06-01.
- [ ] The footer composer NEVER includes secrets. The body is
      pre-validated against the secret-scan regex set from
      `fleet_install_prepush_hook` (ticket 0008) before
      posting. On a regex hit (e.g. a `gh*` PAT prefix
      accidentally captured in `result_head`), the footer
      composer ABORTS with `pr-footer: refusing — composed
      body contains secret-shaped substring (regex: <which>);
      this is a bug, please open an issue` to stderr exit 3
      and does NOT post. Test asserts the abort branch via a
      fixture `runs.jsonl` row whose `result_head` contains a
      synthetic `ghp_` token.
- [ ] `bin/fleet pr-footer <pr>` is a PURE WRITER of one
      GitHub PR comment. It NEVER writes to `events.jsonl`
      (no new event type — pr-footer is a side effect of the
      ship/merge path, not a telemetry signal of its own).
      Test asserts the kit's events channel has unchanged
      byte size before and after invocation.
- [ ] When invoked OPERATOR-side post-hoc on a PR shipped
      BEFORE this ticket landed (and therefore has no
      `runs.jsonl` row matching the PR number), the composer
      degrades gracefully: `cost`, `duration`, `ticket-to-
      date`, and `pr-count` print `unknown` rather than `0`
      (which would lie). The footer is still posted with
      the three surviving values (prompts_pin, lessons_lines,
      kit_sha). Test asserts via a fixture PR number that
      has no matching runs row.
- [ ] `lib/common.sh` — NO public-API changes. A new internal
      helper `_compose_pr_footer_body` MAY be added as a
      private (underscore-prefixed) function. Test asserts
      via `git diff main…HEAD -- lib/common.sh` shows
      only additions whose function names start with `_`.
- [ ] `prompts/` — NO changes (the post-merge hook is in
      `lib/ship.sh`, not the prompt). Test asserts via
      `git diff --name-only main…HEAD -- prompts/` returns
      empty.
- [ ] `tests/pr-footer.sh` covers all 12 boxes above using
      `$HOME/.local/bin` stubs per LESSONS 2026-05-26.
      `gh` stub records every invocation to a fixture file
      and returns canned JSON; `runs.jsonl` and
      `events.jsonl` fixtures live under
      `tests/fixtures/pr-footer/`. Per LESSONS 2026-05-27
      backup/restore via `cp`. The clock is frozen via
      `FLEET_NOW_OVERRIDE`. Run-time budget: <8s.

## Out of scope

The dev agent will NOT do these even if they seem related.

- A SECOND footer on subsequent commits to the same PR (e.g. heal
  commits). The footer fires ONCE per PR, on merge. Healed PRs get
  one footer at the eventual merge moment. v2 may add a
  per-heal-attempt footer.
- A footer on REVIEWER comments (`gh pr review --comment`). The
  footer is a merge artifact, not a review artifact.
- A `--dry-run` flag that prints the would-be body without
  posting. The composer is testable via the test harness; the
  operator's "what would this look like?" answer is to run
  `bin/fleet pr-footer <some-merged-pr>` on a test PR they own.
- A SVG / image-based footer. Markdown only for v1; the badge
  ticket (0027) covers the SVG case for READMEs.
- A separate footer endpoint for `revert/` (rollback) PRs from
  ticket 0017. v1 is feat/chore/eng only. The revert PR's own
  rationale carries the trust signal.
- A "ticket-to-date" rollup that crosses project boundaries (the
  ticket-to-date is per-slug; a multi-project rollup belongs in
  `fleet weekly`, not in a per-PR footer).
- A LESSONS line-count BREAKDOWN by section. The single number
  is the trust signal; the breakdown is `fleet lessons-promote`
  / `lessons-prune` territory.
- Auto-deleting the footer if the PR is later reverted by `fleet
  rollback`. v1 leaves the footer; the revert PR carries its own
  rationale.
- A launchd schedule. The footer fires from the existing ship
  hook OR operator-on-demand; no new launchd job.
- A migration that backfills footers on previously-merged
  agent PRs. v1 is forward-only; a follow-up `--backfill`
  flag is a v2 ticket if operators ask for it.

## Engineering notes

Files / patterns the dev should touch. Specific enough that the dev
doesn't have to re-discover the architecture.

- `bin/fleet` — new `pr_footer()` dispatcher function placed
  next to the existing `badge()` block (find via `grep -n
  '^badge()' bin/fleet`, currently ~line 4404). Shape mirrors
  `badge()` for the per-slug rollup math AND `provenance()`
  (~line 8123) for the pinned-prompts / kit-SHA composition.
  Per LESSONS 2026-05-26 (`tail` shadow) the function name
  `pr_footer` does not collide with a coreutils binary.
- `bin/fleet` — five helpers, ALL defined ABOVE the dispatcher
  block per LESSONS 2026-06-05 (forward-reference trap):
  - `pr_footer_find_runs_row` — greps `runs.jsonl` for the
    row whose `result_head` cites the PR number, returns
    `cost<TAB>duration_ms` or `-<TAB>-` sentinel per LESSONS
    2026-06-08 IFS=$'\t' middle-empty-field.
  - `pr_footer_30d_rollup` — sums `total_cost_usd` over the
    trailing 30 days for the slug and counts `pr_opened`
    events. Per LESSONS 2026-06-08 the awk script declares
    `BEGIN { cost = 0; pr_count = 0 }`. Per LESSONS
    2026-06-01 count via `awk … END { print n+0 }`.
  - `pr_footer_compose_body` — assembles the markdown body
    from the six values. Per LESSONS 2026-05-28 every
    `printf` of a user-derived string uses `printf --`.
    Per LESSONS 2026-06-03 JSON escape for the gh body
    goes through `preflight_json_escape` when wrapped in
    `gh pr comment --body` JSON.
  - `pr_footer_already_posted` — checks `gh pr view <pr>
    --json comments` for an existing comment whose first
    line is `<!-- fleet-roi-footer v1 -->`. Returns 0 if
    found, 1 if not.
  - `pr_footer_secret_check` — runs the composed body
    through the same regex set as `fleet_install_prepush_
    hook` (ticket 0008) and refuses to post on a hit. Per
    LESSONS 2026-05-30 use `grep -qE --` for the regex.
- `bin/fleet` — `pr_footer()` end-state must be `exit 0` /
  `exit 2` / `exit 3` per LESSONS 2026-06-01 (dispatcher
  fall-through trap).
- `bin/fleet` — dispatcher block: `if [ "$CMD" = "pr-footer"
  ]; then pr_footer "$@"; fi`. Place AFTER the `badge`
  dispatcher (~line 4938). Note the dash-to-underscore
  function-name mapping (subcommand `pr-footer` →
  function `pr_footer`) per existing kit convention
  (`prompts-revert` → `prompts_revert`).
- `bin/fleet` — help banner block at the top of the file
  (around line ~14) gets a new line: `fleet pr-footer <pr>
  post a per-merge ROI receipt comment`. README "Daily ops"
  code block gets the same line.
- `lib/ship.sh` — after the `gh pr merge --auto --squash`
  step in BOTH PHASE 1 (heal → merge) and PHASE 2 (ship
  → merge), add a hook that reads `PR_FOOTER_ENABLED` from
  the loaded manifest (default 1 when unset) and invokes
  `bin/fleet pr-footer <pr>` in the background with
  `>/dev/null 2>&1 &` so the merge path doesn't wait on
  the gh REST roundtrip. Per the LESSONS 2026-05-26
  GitHub-actions-silent flake, a footer-post failure is
  NOT a heal trigger — the merge already happened.
- `lib/common.sh` — NO public-API changes. The
  `_compose_pr_footer_body` private helper MAY live here
  if the composer benefits from being reusable by a
  future operator-side `bin/fleet weekly --with-footers`
  rollup (out of scope for v1 — the composer can stay in
  `bin/fleet`).
- `manifest.example.sh` — new line:
  `PR_FOOTER_ENABLED=1   # post a per-merge ROI receipt comment on every agent-shipped PR (set 0 to opt out)`.
- `agents.config.sh` (the kit's own manifest) — set
  `PR_FOOTER_ENABLED=1` to dogfood the surface.
- `AGENTS.md` — NO new bullet in § Telemetry (no new event
  type). § Agent parameters MAY mention the
  `PR_FOOTER_ENABLED` knob as part of the manifest section,
  but the kit's existing manifest knobs aren't currently
  enumerated there, so no edit is required.
- `prompts/` — NO changes.
- `tests/fixtures/pr-footer/` — NEW directory holding
  `runs.jsonl`, `events.jsonl`, and `gh-pr-view-N.json`
  fixtures for each AC test scenario.
- `tests/pr-footer.sh` — top of file mirrors `tests/
  badge.sh` and `tests/provenance.sh`: stub `gh` under
  `$HOME/.local/bin` per LESSONS 2026-05-26. Per LESSONS
  2026-05-27 backup/restore via `cp`. The clock is
  frozen via `FLEET_NOW_OVERRIDE`. Run-time budget:
  <8s.
- New deps: none. Pure shell + awk + `gh` + existing
  helpers.
- Public API: additive — `bin/fleet pr-footer` is a new
  subcommand AND `lib/ship.sh` gains a post-merge hook.
  The hook reads a new manifest variable
  `PR_FOOTER_ENABLED` with safe default 1.
- BREAKING flag: NO. The default-on behavior IS a
  behavior change — every fleet on the next install
  starts posting footers — but the manifest knob is the
  opt-out and the kit's commitment per AGENTS.md is
  "secrets, public-API stability, idempotency" not
  "no new default-on side effects." PR body affirms
  "new default-on PR comment; opt out with
  `PR_FOOTER_ENABLED=0` in manifest."
- Reinstall required: YES — `lib/ship.sh` changes.
  Mark the PR body with `Reinstall: all projects` per
  the LESSONS 2026-05-25 fleet-wide-reinstall rule.
- LESSONS to defend against: 2026-05-25 (load-bearing
  docs — README "Daily ops" code block addition,
  manifest.example.sh edit), 2026-05-25 (lib/
  reinstall — `Reinstall: all projects` in PR body),
  2026-05-26 (`tail` shadow — `pr_footer` and helpers
  don't shadow coreutils), 2026-05-26 (PATH reset —
  test stubs go in `$HOME/.local/bin`), 2026-05-27
  (`$(cat)` trap — fixture restore uses `cp`),
  2026-05-28 (printf leading-dash — every
  user-derived string goes through `printf -- '%s'`),
  2026-05-30 (`grep -F --` trap), 2026-06-01 (`grep
  -c file || echo 0` double-print), 2026-06-01
  (dispatcher fall-through), 2026-06-03 (UTF-8
  sign-extension — body goes through
  `preflight_json_escape` for the gh JSON wrapper),
  2026-06-05 (dispatcher forward-reference),
  2026-06-08 (awk empty-string-key —
  `pr_footer_30d_rollup` BEGIN block initializes
  counters), 2026-06-08 (IFS=$'\t'
  middle-empty-field).
- This ticket compounds 0025 (`fleet weekly` —
  shares the 30-day rollup math), 0027 (`fleet
  badge` — shares the cost/PR-count fold), 0029
  (`fleet provenance` — shares the pinned-prompts/
  kit-SHA composition), 0008 (`secret-scan
  pre-push` — reuses the regex set for body
  validation). Per P-1 the diff is small: ~250
  lines of `pr_footer_*` helpers + ~200 lines of
  test + 5 fixture files + one `lib/ship.sh` hook
  + one `manifest.example.sh` line + one help-text
  line + one README line.

## Implementation log

(Appended by the implementation-dev agent during execution.)

- 2026-06-11 — ticket filed by gtm-innovation
- 2026-06-11 — implementation-dev picked up; branch feat/0044-fleet-pr-footer-roi-comment.
  AC#5 interpretation note: `lib/ship.sh` does NOT itself invoke `gh pr
  merge --auto --squash` (the dev agent does that inside the ship prompt).
  The "post-merge hook" therefore lands AFTER `fleet_run_claude ship`
  returns successfully — it reads the most recent `pr_opened` event from
  this run's events.jsonl and invokes `bin/fleet pr-footer <pr>` in the
  background. `pr-footer` itself refuses non-merged PRs (exit 2), so a
  ship-without-merge run is a silent no-op on the hook.
- 2026-06-11 — shipped via PR #91 (merge f54676c). Both gating checks
  (shellcheck, validate) green. AC#4 sidebar: the ticket's middle-dot
  (`·`) separators in the user-story example would have failed the
  ASCII-only assertion; the rendered body uses ASCII pipe (`|`)
  separators throughout, with the one permitted emoji (🤖) on the
  "fleet receipt" header line.
