---
id: 0056
title: fleet share <pr> composes a one-line shareable testimonial about a single merged PR
status: in-progress
priority: P1
area: observability
created: 2026-06-17
owner: gtm-innovation
---

## User story

As a fleet operator who just merged PR #42 on `sidebrew` — a clean
autonomous PR the loop opened on Tuesday, ran through one heal cycle,
and ATTACHED a `fleet pr-footer` (0044) ROI comment to before they
hit "merge" — who is now in their browser thinking "this is the
exact moment to tweet about agent-fleet but I don't want to manually
compose the prose AND look up the cost AND fish out the runtime" —
I want `bin/fleet share sidebrew 42` to emit ONE pre-composed line
(with optional `--copy` to `pbcopy` it straight onto my clipboard)
shaped exactly for Twitter / a Slack DM / the body of a blog post,
listing the slug, PR number, lines changed, runtime, dollar cost,
heal-cycles, and any cited LESSONS — REDACTED to operator-pseudonym
form (`project-a`, `PR #aaa`, cost band) when `--redact` is passed,
so I can paste a testimonial in the 30 seconds after the merge while
the dopamine is still warm, without typing a single character of
prose.

## Why now (four lenses)

### Product Owner
The kit already has two sharing surfaces — `fleet portfolio
--redact` (0053) is the FLEET-WIDE one-pager for a blog post, and
`fleet pr-footer` (0044) is the per-merge ROI comment that lands
ON the PR for the reviewing human. There is no SINGLE-PR,
operator-pulled, sharing surface designed for the moment when the
operator wants to evangelize ONE concrete win. The pr-footer
comment IS the data — but it lives on the PR thread; pasting that
into a tweet requires a manual extraction. The portfolio is FLEET-
SHAPED, not PR-shaped — it doesn't surface "the cool thing
sidebrew shipped on Tuesday." The smallest meaningful unit of
value is one composed line per merged PR, ready to paste:

```
$ fleet share sidebrew 42 --redact
🟢 project-a PR #aaa shipped autonomously by agent-fleet — 312
lines changed, 18 min runtime, ~$0.50, no send-backs. LESSONS
cited: 2026-06-15. https://github.com/<redacted>/<repo-a>/pull/42
```

(without `--redact`, slug names, PR number, exact cost, and full
repo URL are preserved for sharing with peers who already have
context).

Subtraction: the operator stops composing the tweet from scratch
every time. Per P-5 (operator confidence over feature richness),
the win is the testimonial-prose-no-longer-blocking the operator
from sharing.

`--copy` pipes the result through `pbcopy` on macOS so the
operator's clipboard holds the line the instant the command
returns. The README documents the natural usage: `fleet share
sidebrew 42 --redact --copy && open https://twitter.com`. Two
seconds from "merged" to "tweet composed."

### Stakeholder
This is **moat-deepening on the growth axis** — the kit's first
surface designed for the operator to share with the ONE concrete
artifact a peer will read in 5 seconds. Per P-6 (telemetry is
the source of truth), `share` is a PURE READER over the slug's
`events.jsonl` (for `pr_opened`, `pr_footer_posted`, and any
`lesson_promoted` correlating to the PR), the slug's `runs.jsonl`
(0047's cost channel for the dollar figure), and `gh pr view
<n> --json mergedAt,additions,deletions,baseRefName,headRefName,
url` for the merge metadata. No new event types. No writes. No
`lib/common.sh` changes. The diff is the per-PR data assembler
+ the redaction pass (reused from 0053 `portfolio_redact_text`
verbatim) + the one-line composer. ~250 lines.

The composed-line shape IS a small moat: every Twitter quote
or Slack paste of `fleet share` output is a self-explanatory
ad for the kit — it lists the kit by name, the cost, the
runtime, and the LESSONS, all in one line. Per the brief's
focus on "why does a friend running their own autonomous-
agent setup want to adopt it?" — a peer who sees three
`fleet share` lines in a row knows EXACTLY what value this
loop delivered.

Per LESSONS 2026-06-15 (per-slug streak shellout) `share`
does NOT call `fleet streak` per slug. It walks the slug's
events.jsonl ONCE for the PR's data. The cost figure pulls
from `runs.jsonl` via one awk pass — same pattern 0047
`fleet ticket-cost` already uses.

Compounds 0044 (`fleet pr-footer` — the data the share line
mirrors), 0053 (`fleet portfolio --redact` — the redaction
helper `portfolio_redact_text` is reused verbatim), 0047
(`fleet ticket-cost` — the cost-aggregator helper is
reused for the dollar figure), 0022 (`lesson_draft_emitted`
— the LESSONS-cited line traces back to this event when
the operator promoted a draft from this PR), 0029 (`fleet
provenance <pr>` — the share line's "LESSONS cited"
field reuses provenance's cite resolver), 0019 (`fleet
overview` — reuses `overview_discover_slugs`).

### User (operator at 3pm Tuesday, browser open on the just-merged PR)
The operator has been waiting all week for sidebrew PR #42 to
land — it was the first PR the loop healed in-flight without
operator intervention, and the operator wants to brag about
it on Twitter. They run `fleet share sidebrew 42 --redact
--copy`. Output: `📋 copied to clipboard. preview:` plus the
composed line. They cmd-tab to their Twitter tab, cmd-V, send
the tweet. Total elapsed time: 8 seconds. Per P-5, the win is
the operator finally posting the win-they've-wanted-to-post-
all-week without having to think about prose.

Sub-scenario: an EXPERIENCED operator writing a blog post
runs `fleet share sidebrew 42 --redact` for three of their
favorite PRs across two slugs, pipes each into a file, and
pastes the three lines as bullets in the post. The
deterministic redaction (`project-a` → sidebrew, `project-b`
→ courtiq) is consistent across the three invocations within
the same session because the pseudonym allocator (reused
from 0053) sorts by slug name; across sessions, the same
slug always maps to the same letter as long as the slug
order is stable.

Sub-scenario: the operator runs `fleet share sidebrew 42`
WITHOUT `--redact` to share with a peer over Slack DM. The
real slug name, real PR number, and real repo URL appear.
This is the per-PR cousin of `fleet portfolio
--keep-slug-names`.

### Growth
This is the most direct acquisition surface in the kit.
Every successful tweet quoting `fleet share` output is a
case study; every Slack DM is a referral. Today the
operator who wants to share has to compose the prose
themselves — most don't, because the friction is enough
to kill the impulse. Per the brief's "Why does this make
the kit more shareable / extensible?" — share converts a
freshly-merged PR into a paste-ready testimonial in
under 10 seconds. That's the single largest acquisition
multiplier the kit can have, because it converts each
merged PR into a marketing artifact at zero operator
cost.

Differentiated from `fleet portfolio --redact` (0053):
portfolio is FLEET-WIDE and SUMMARY-shaped for a blog
post or peer demo. Share is SINGLE-PR and TESTIMONIAL-
shaped for a tweet or Slack DM. They share the
redaction helper but diverge on scope.

Differentiated from `fleet pr-footer` (0044): pr-footer
is AUTO-POSTED ON the PR for the reviewing human (an
artifact about merge quality). Share is OPERATOR-PULLED
and designed for OUT-of-PR sharing (an artifact about
"look what this kit did"). They share the per-PR data
but diverge on consumer.

Differentiated from `fleet badge` (0027): badge is a
shields.io-style ONE-LINE ROI shield for a project's
README (a long-lived embedded artifact). Share is a
ONE-LINE testimonial for a single transient share
moment (a tweet / DM / blog bullet).

## Acceptance criteria

Each box maps 1:1 to a test scenario in `tests/share.sh`.

- [ ] `bin/fleet share <slug> <pr-number>` is a new
      subcommand. Required args: slug name and PR number.
      Missing or partial args: prints `share: usage:
      bin/fleet share <slug> <pr-number> [--redact]
      [--copy] [--json]` to stderr, exit 2 per LESSONS
      2026-06-01. Per LESSONS 2026-05-30 (`grep -F --`
      trap) the test assertion uses `grep -qF -- "$kw"
      "$out"`. Test asserts via three branches: no args,
      slug only, slug + non-numeric PR.
- [ ] Unknown slug (not in `overview_discover_slugs`):
      prints `share: slug <name> not found. discovered
      slugs: <list>` to stderr, exit 2. PR number that
      does not correspond to any `pr_opened` event in
      the slug's events.jsonl: prints `share: <slug>
      has no merged PR #<n>. run \`fleet overview
      <slug>\` to list known PRs.` to stderr, exit 2.
      Test asserts both refusals.
- [ ] The composed line shape (no flags, real names)
      is: `🟢 <slug> PR #<n> shipped autonomously by
      agent-fleet — <additions+deletions> lines
      changed, <runtime_minutes> min runtime,
      ~$<cost>, <send_backs_phrase>. LESSONS cited:
      <dates>. <pr_url>`. The phrase choices are:
      `no send-backs` (when zero
      `lesson_draft_emitted` events correlate),
      `healed in <N> cycle(s)` (when `heal_*`
      events correlate without a send-back),
      `<N> send-back(s)` (when send-backs occurred).
      Per LESSONS 2026-05-28 every printf of the
      slug name goes through `printf -- '%s'`. Test
      asserts each phrase branch via fixtures.
- [ ] The `<runtime_minutes>` value is the wall-
      clock minutes between the PR's first
      `run_started` event and its
      `pr_footer_posted` event, rounded to the
      nearest minute. Per LESSONS 2026-06-11 (BSD
      `date -j -f` fills missing time fields with
      NOW-of-day) the runtime math uses `date +%s`
      epoch subtraction with `T00:00:00` appended
      to any date-only timestamp before parsing.
      Per LESSONS 2026-06-08 the awk timestamp
      reader declares `BEGIN { count = 0 }`. Test
      asserts via a fixture with a 18-minute
      window and a 1-hour-43-minute window.
- [ ] The `<cost>` value reads from the slug's
      `runs.jsonl` (0047's cost channel),
      summing every `cost_usd` row whose
      `pr_number` field matches the input PR
      number. Per LESSONS 2026-06-08 IFS=$'\t'
      middle-empty-field uses `-` sentinel. The
      format is `$N.NN` (two decimals) without
      `--redact`, and a cost band (`<$1`, `~$1`,
      `~$5`, etc per 0053's bands) WITH
      `--redact`. Test asserts both renders via
      fixture cost rows of $0.42 and $4.50.
- [ ] The `LESSONS cited` field lists every
      LESSONS date whose `## YYYY-MM-DD` heading
      is referenced by a `lesson_promoted` event
      OR a `lesson_draft_emitted` event whose
      `pr_number` field matches the input PR.
      Format: comma-separated `YYYY-MM-DD` list.
      When zero: omit the entire `LESSONS cited:
      …` clause from the line. Test asserts via
      fixtures with 0, 1, and 2 lessons cited.
- [ ] `bin/fleet share <slug> <pr> --redact` runs the
      reused `portfolio_redact_text` helper from 0053
      over the composed line, replacing the slug name
      with `project-a`-style pseudonym, the PR number
      with `PR #aaa`-style pseudonym, the cost with
      its band, and the repo URL with
      `github.com/<redacted>/<repo-a>`. The pseudonym
      allocator is the same `portfolio_allocate_
      pseudonyms` from 0053 — same alphabetical sort,
      same in-memory-only map. Test asserts the
      `--redact` output contains NEITHER the real
      slug name NOR the real PR number NOR the real
      repo URL via fixture with `sidebrew` /
      `PR #42` / `git@github.com:realuser/
      sidebrew.git`.
- [ ] `bin/fleet share <slug> <pr> --copy` pipes the
      composed line through `pbcopy` on macOS
      (skipped on non-Darwin platforms with the
      printed warning `share: --copy is macOS only;
      output printed to stdout instead`). After
      success, prints `📋 copied to clipboard.
      preview:` to stderr followed by the line to
      stdout. Per LESSONS 2026-05-26 (PATH reset)
      the `pbcopy` stub for the test lives under
      `$HOME/.local/bin/pbcopy` and records its
      stdin to a side file. Test asserts (a) the
      stub's stdin file contains the composed line
      and (b) the platform-mismatch branch via
      stubbing `uname` to return `Linux`.
- [ ] `bin/fleet share <slug> <pr> --json` emits one
      structured JSON object: `{"slug": "<name or
      pseudonym>", "pr": <int or string pseudonym>,
      "lines_changed": <int>, "runtime_minutes":
      <int>, "cost_usd": <number or band string>,
      "send_backs": <int>, "heal_cycles": <int>,
      "lessons_cited": ["YYYY-MM-DD", …],
      "pr_url": "<url or redacted>", "rendered":
      "<the one-line text>"}`. JSON escape via
      `preflight_json_escape` per LESSONS
      2026-06-03 called directly per LESSONS
      2026-06-13 (no `*_json_escape` wrapper). Test
      asserts JSON validity via `node -e
      'JSON.parse(require("fs").readFileSync(0,
      "utf8"))'` for both redacted and
      unredacted modes.
- [ ] The PR metadata is read via `gh pr view <n>
      --json mergedAt,additions,deletions,
      baseRefName,headRefName,url` ONCE per
      invocation. Per LESSONS 2026-05-26 (PATH
      reset) the test's `gh` stub lives under
      `$HOME/.local/bin/gh` and returns canned
      JSON. When `gh` is not on PATH or returns
      non-zero, prints `share: gh CLI required
      to fetch PR metadata. install via \`brew
      install gh\` and run \`gh auth login\`.`
      to stderr, exit 2. Test asserts both the
      happy path (canned JSON) and the missing-
      `gh` branch.
- [ ] `bin/fleet share --help` prints USAGE
      mentioning slug + PR args, `--redact`,
      `--copy`, `--json`. Per LESSONS 2026-05-30
      test asserts via `grep -qF -- "$kw"
      "$help_out"`. Help block ends with `exit 0`
      per LESSONS 2026-06-01.
- [ ] `bin/fleet share` is a PURE READER. NO
      `events.jsonl` writes, NO `fleet_emit_event`
      calls, NO writes to any slug's
      `agents.config.sh` or telemetry channel. The
      only side effect is the pbcopy invocation
      under `--copy` and an optional cache file
      under `$HOME/.cache/agent-fleet/share-gh-
      pr-<slug>-<n>.json` (gh PR metadata cache,
      24h TTL, NOT telemetry). Test asserts every
      slug's `events.jsonl` and `runs.jsonl` byte
      size is unchanged before and after
      invocation.
- [ ] `lib/common.sh` — NO changes. `prompts/` —
      NO changes. No new event types. Test asserts
      via `git diff --name-only main...HEAD --
      lib/common.sh prompts/` returns empty.
- [ ] `tests/share.sh` covers all 13 boxes above
      using `$HOME/.local/bin` stubs per LESSONS
      2026-05-26 (PATH reset). Fixture
      `events.jsonl`, `runs.jsonl`,
      `agents.config.sh`, and canned `gh pr view`
      JSON files live under
      `tests/fixtures/share/`. Per LESSONS
      2026-05-27 backup/restore via `cp` (NOT
      `$(cat)`). Counts use `awk … END { print
      n+0 }` per LESSONS 2026-06-01. Per LESSONS
      2026-06-08 every awk script declares
      `BEGIN { count = 0 }`. Per LESSONS
      2026-06-08 IFS=$'\t' middle-empty-field
      uses `-` sentinel. Per LESSONS 2026-06-15
      no per-day `date -j -v +1d` shellout (the
      runtime math is one `date +%s` epoch
      subtraction, not a day-walk). The clock
      is frozen via `FLEET_NOW_OVERRIDE`. Run-
      time budget: <8s.

## Out of scope

The dev agent will NOT do these even if they seem related.

- AUTO-POSTING the line to Twitter / Slack / GitHub
  Gist. v1 prints to stdout (and optionally
  `pbcopy`); the operator chooses the destination.
  Auto-posting violates the "no auto-upload" Hard
  NO from the brief.
- A MULTI-PR `fleet share <slug> --last 5` mode
  that composes a thread of five recent PRs into
  five lines. v1 is single-PR. Multi-PR is a v2
  if the single-PR shape proves popular.
- A `fleet share --random` mode that picks a
  recent merged PR for you. Cute but adds a
  surface the operator doesn't need; v1
  requires explicit PR selection.
- A LINUX `--copy` implementation via
  `xclip`/`wl-copy`. The kit is macOS-first per
  AGENTS.md; v1 prints the warning and skips.
- A `fleet share --thread` mode that composes a
  three-PR-deep Twitter thread shape with reply
  numbering. v1 is one line. Threading is a v2
  composer.
- INCLUDING screenshots (an attached image of
  the PR diff). Shell-only kit; no image
  composition.
- AUTO-PINGING the operator's Twitter handle in
  the line. The operator owns their own brand;
  the kit doesn't auto-tag.
- A `--draft` mode that opens the composed line
  in `$EDITOR` for the operator to edit. v1
  emits the final line; the operator edits in
  their tweet composer if they want.
- A FLEET-wide variant `fleet share-fleet`
  (covered by `fleet portfolio --redact` 0053
  already; share is single-PR by design).
- A launchd schedule. Operator-invoked only.

## Engineering notes

Files / patterns the dev should touch.

- `bin/fleet` — new `share()` dispatcher function
  placed next to the existing `pr_footer()` block
  (find via `grep -n '^pr_footer()' bin/fleet`).
  Per LESSONS 2026-05-26 (`tail` shadow) `share`
  does not collide with any coreutils binary.
- `bin/fleet` — seven helpers, ALL defined ABOVE
  the dispatcher block per LESSONS 2026-06-05
  (forward-reference trap):
  - `share_assert_slug_and_pr` — validates inputs
    per AC #1 and AC #2.
  - `share_fetch_pr_metadata` — calls `gh pr view
    <n> --json ...`, caches under `$HOME/.cache/
    agent-fleet/share-gh-pr-<slug>-<n>.json` with
    24h TTL. Per LESSONS 2026-06-11 the cache age
    math uses `date +%s` minus `stat -f %m`, no
    `date -j -f` involved.
  - `share_walk_events` — one awk pass over the
    slug's events.jsonl correlating
    `run_started`, `pr_opened`, `heal_*`,
    `lesson_draft_emitted`, `lesson_promoted`,
    and `pr_footer_posted` events by PR number.
    Per LESSONS 2026-06-08 the awk pass declares
    `BEGIN { count = 0; runtime_s = 0 }`. Per
    LESSONS 2026-06-08 IFS=$'\t' middle-empty-
    field uses `-` sentinel.
  - `share_sum_cost_for_pr` — one awk pass over
    `runs.jsonl` summing `cost_usd` rows whose
    `pr_number` matches.
  - `share_resolve_lessons_cited` — extracts
    `YYYY-MM-DD` strings from
    `lesson_promoted.headline` and
    `lesson_draft_emitted.headline` fields,
    returns the sorted unique list.
  - `share_compose_line` — assembles the final
    one-line string. Per LESSONS 2026-05-28 the
    printf goes through `printf -- '%s'`. Per
    LESSONS 2026-06-05 (bash 3.2 LC_ALL caching)
    any string-length op runs via `LC_ALL=C
    awk`.
  - `share_apply_redaction` — invokes
    `portfolio_redact_text` (from 0053)
    verbatim on the composed line. Per the
    out-of-scope clause in 0053 the helper is
    NOT duplicated — `share` reuses it. The
    pseudonym allocator is
    `portfolio_allocate_pseudonyms`, also
    reused verbatim.
  - `share_render_json` — JSON formatter. JSON
    escape via `preflight_json_escape` per
    LESSONS 2026-06-03 called directly per
    LESSONS 2026-06-13 (no `*_json_escape`
    wrapper).
- `bin/fleet` — `share()` end-state must be
  `exit 0` / `exit 2` on every code path per
  LESSONS 2026-06-01.
- `bin/fleet` — dispatcher block: `if [ "$CMD"
  = "share" ]; then share "$@"; fi`. Place
  AFTER the `portfolio` dispatcher (so the two
  redact-related commands sit next to each
  other in the dispatcher).
- `bin/fleet` — help banner block at the top
  of the file gets ONE new line: `fleet share
  <slug> <pr> compose a one-line testimonial
  for a single merged PR`. README "Daily ops"
  code block gets the same line, appended via
  the same single-edit pattern that avoided
  LESSONS 2026-05-25.
- `AGENTS.md` — NO content change.
- `lib/common.sh` — NO changes.
- `prompts/` — NO changes.
- `tests/fixtures/share/` — NEW directory
  holding three slug subdirs (`sidebrew`,
  `courtiq`, `hedgehog`) each with
  `events.jsonl`, `runs.jsonl`,
  `agents.config.sh`, and a canned `gh-pr-
  view-<n>.json` for each fixture PR. The
  events cover the phrase-branch fixtures
  (no send-backs / healed in N / N send-
  backs) plus the 0-1-2 LESSONS-cited
  fixtures.
- `tests/share.sh` — top of file mirrors
  `tests/portfolio.sh` (closest prior
  ticket; shares the redaction helper
  invocation). Stubs live under
  `$HOME/.local/bin` per LESSONS 2026-05-26
  (PATH reset). The `gh`, `pbcopy`, and
  `uname` stubs record their args/stdin to
  side files for assertions. Counts use
  `awk … END { print n+0 }` per LESSONS
  2026-06-01. Per LESSONS 2026-05-27
  backup/restore via `cp`. The clock is
  frozen via `FLEET_NOW_OVERRIDE`. Run-time
  budget: <8s.
- New deps: none. `pbcopy` is macOS
  built-in; `gh` is already a kit dep for
  `fleet onboard` (0011), `fleet provenance`
  (0029), `fleet rollback` (0017).
- Public API: additive — `bin/fleet share`
  is a new subcommand. ZERO new event
  types, ZERO event writes to telemetry
  channels, ZERO `lib/common.sh` changes,
  ZERO `prompts/` changes. The
  `share-gh-pr-*` cache file at
  `$HOME/.cache/agent-fleet/` is an
  invalidatable cache, not telemetry.
- BREAKING flag: NO. PR body affirms "pure
  reader, no events.jsonl writes, no
  `fleet_*` signature changes, no runtime
  hot-path changes, reuses
  `portfolio_redact_text` from 0053
  verbatim."
- Reinstall required: NO. `lib/` and
  `prompts/` are untouched.
- LESSONS to defend against: 2026-05-25
  (README "Daily ops" code block addition),
  2026-05-26 (`tail` shadow), 2026-05-26
  (PATH reset — stubs in
  `$HOME/.local/bin`), 2026-05-27 (`$(cat)`
  trap — use `cp` for backup/restore in
  tests), 2026-05-28 (printf leading-dash —
  every slug-name printf goes through
  `printf -- '%s'`), 2026-05-30 (`grep -F
  --` trap), 2026-06-01 (`grep -c file ||
  echo 0` double-print — counts use `awk …
  END { print n+0 }`), 2026-06-01
  (dispatcher fall-through — every code
  path ends `exit 0/2`), 2026-06-03 (UTF-8
  sign-extension — JSON escape via
  `preflight_json_escape`), 2026-06-05
  (dispatcher forward-reference — all
  `share_*` helpers defined ABOVE the
  dispatcher), 2026-06-05 (bash 3.2 LC_ALL
  caching — any string-length op via
  `LC_ALL=C awk`), 2026-06-05 (export-in-
  subshell trap — any agents.config.sh
  read happens inside `( … )`), 2026-06-08
  (awk empty-string-key — `BEGIN { count =
  0 }`), 2026-06-08 (IFS=$'\t' middle-
  empty-field — sentinel `-`), 2026-06-11
  (BSD `date -j -f` fills missing time
  fields with NOW-of-day — cache-age and
  runtime math via `date +%s` epoch
  subtraction), 2026-06-13 (no
  `*_json_escape` wrapper around
  `preflight_json_escape` — called
  directly).
- This ticket compounds 0044 (`fleet
  pr-footer` — share is the operator-
  pulled counterpart to pr-footer's auto-
  posted comment), 0053 (`fleet portfolio
  --redact` — reuses
  `portfolio_redact_text` and
  `portfolio_allocate_pseudonyms`
  verbatim), 0047 (`fleet ticket-cost` —
  reuses the cost-aggregator awk shape),
  0022 (`lesson_draft_emitted` — the
  LESSONS-cited resolver reads this event
  type), 0028 (`fleet lessons-promote` —
  the `lesson_promoted` event is the
  other LESSONS-cited source), 0029
  (`fleet provenance <pr>` — share is
  the testimonial-shaped peer of
  provenance's forensic-shaped output),
  0019 (`fleet overview` — reuses
  `overview_discover_slugs`), 0017
  (`fleet rollback` — depends on the
  same `gh pr view` plumbing). Per P-1
  the diff is small: ~250 lines of
  `share_*` helpers + ~280 lines of
  test + 12 fixture files + one help-
  text line + one README line.

## Implementation log

(Appended by the implementation-dev agent during execution.)

- 2026-06-17 — implementation-dev: opened `feat/0056-fleet-share-pr-testimonial`. Wrote tests/share.sh first (13 ACs), then implemented `share()` + 7 helpers in `bin/fleet` above the dispatcher block per LESSONS 2026-06-05. Reused `portfolio_redact_text` + `portfolio_allocate_pseudonyms` verbatim per the ticket's "no wrapper" clause. Added one help-banner line + one README "Daily ops" line. lib/, prompts/, AGENTS.md untouched.
