---
id: 0062
title: fleet why <slug> composes the one-paragraph argument for keeping the kit installed against the slug's own telemetry
status: groomed
priority: P2
area: docs
created: 2026-06-19
owner: gtm-innovation
---

## User story

As a fleet operator at week 14 of running `agent-fleet` against
`sidebrew` — who is asked by a peer "why agent-fleet instead of
just `cursor` or `aider`?" and finds themselves composing the
answer from scratch every time, citing different numbers each
attempt because the truth is buried across `fleet weekly` (0025),
`fleet ticket-cost` (0047), and `fleet recap` (0048) — I want
`bin/fleet why sidebrew` to emit ONE composed paragraph (≤6
sentences, plain English, no jargon) drawn entirely from the
slug's actual telemetry that explains, with citations to specific
events, why this kit was the right choice for THIS slug right
now ("over the last 8 weeks sidebrew shipped 47 PRs at $0.42 each,
with 3 stuck-PR recoveries the loop handled without me touching
them, and 2 LESSONS learned that now defuse the same trap in 4
other projects. The Cursor Pro alternative would have cost $160
and would not have produced the cross-project memory. Replacing
the kit today would forfeit the LESSONS feed."), so the next time
a peer asks I copy-paste the paragraph rather than rebuild the
argument.

## Why now (four lenses)

### Product Owner
The kit's existing growth surfaces are all data-shaped — 0027
badge is one line of metrics, 0044 pr-footer is a per-merge
comment, 0048 recap is a narrative window, 0053 portfolio is
the fleet-wide one-pager, 0056 share is a per-PR testimonial,
0061 invoice is the monthly receipt. NONE of them compose the
ARGUMENT — the "why this kit, why now, why for me" paragraph
the operator needs when they are EXPLAINING the choice to
themselves or a peer. The closest is 0048 recap (narrative
window), but recap is descriptive ("here's what happened");
why is persuasive ("here's why it's worth what it cost"). The
smallest meaningful unit of value is one composed paragraph:

```
$ fleet why sidebrew
why sidebrew runs agent-fleet — drawn from 14 weeks of telemetry

  Over the last 8 weeks sidebrew shipped 47 PRs at $0.42
  each (median $0.38, p95 $0.71). The loop handled 3 stuck-
  PR recoveries you did not touch — two BEHIND rebases (PRs
  #117, #128) and one DRAFT auto-merge re-arm (#142). Across
  the same window the kit's reviewer added 2 LESSONS that
  now defuse the same trap in 4 sibling projects (courtiq,
  levelup-kids, fleet-control, agent-fleet itself). The
  Cursor Pro alternative would have cost ~$160 over the same
  window and would not have produced the cross-project
  LESSONS feed; the contractor alternative (~$2,800) would
  not exist as a comparison. Replacing the kit today would
  forfeit both the cross-project memory and the 4 currently-
  pinned prompt revisions sidebrew specifically benefited
  from.

  ... cites: 47× pr_footer_posted, 3× stuck-PR unblock
  events (gh-derived), 2× lesson_promoted (cross-fleet),
  4× prompts_pin_changed.
```

The "cites" footer lists the event-type counts so the
operator can verify the claim (and so a skeptical peer can
ask "show me those").

Subtraction: the operator stops re-composing the argument
every time the question comes up. Per P-5 (operator
confidence over feature richness), the win is the absent
"every time I have to think about whether I'm getting my
money's worth, I have to reason from scratch."

A `--audience` flag tunes the prose for the audience:
`peer` (default — plain English, technical), `manager`
(business-friendly, dollar-framed), `self` (terse, like a
journal entry the operator addresses to themselves). The
event counts are the same; the framing differs.

`--why-not` inverts the framing: composes the argument
against keeping the kit installed for slugs where the
telemetry doesn't support the case (e.g. a slug that ships
1 PR per month at the budget cap). Honest tooling that
helps the operator know when to STOP using the kit for one
slug is the same retention move as helping them know when
to keep it — both build trust.

### Stakeholder
This is **moat-deepening on the trust axis** — the kit's
first surface that helps the operator THINK CLEARLY about
their own usage. Per P-6 (telemetry is the source of
truth), `why` is a PURE READER over each slug's
`events.jsonl`, `runs.jsonl`, the cross-LESSONS file (for
the cross-project memory claim), and the slug's
`PROMPTS_SHA` history (for the pinned-prompt claim). NO
writes, NO new event types, NO `lib/common.sh` changes.
The diff is the citation walker + the prose composer +
the renderer. ~280 lines.

The argument composer IS the moat: it codifies "the
kit's value proposition" in code, parameterized by the
operator's actual telemetry. Every kit fact the operator
might claim ("the loop handled 3 stuck-PR recoveries you
did not touch") is BACKED by a citation to the events
that prove it. A peer who reads the paragraph and asks
"prove the 3 stuck-PR claim" can be answered with the
event IDs. That auditable-argument shape is unusual in
SaaS-adjacent tooling and becomes a thing the kit is
known for.

Per LESSONS 2026-06-15 (per-day shellout inside per-
slug loops is O(window × N_slugs)) the per-slug walk
is ONE awk pass over events.jsonl plus ONE awk pass
over runs.jsonl plus ONE grep of cross-LESSONS for the
slug's promoted entries — three subprocesses per slug,
~150ms total.

Per LESSONS 2026-06-15 (`while (match(s, /pat/))
infinite loop`) the prose template substitution uses
the CURSOR-based walk pattern, NOT the recursive
`s = before repl after` shape — every `${PR_COUNT}` /
`${COST_PER_PR}` substitution.

Per LESSONS 2026-05-28 every printf of a slug name or
dollar amount goes through `printf -- '%s'`.

Compounds 0061 (`fleet invoice` — why is the argument
shape of invoice's number shape), 0048 (`fleet recap`
— recap narrates events; why argues from them), 0028
(`lesson_promoted` event — why's cross-project claim
reads it), 0024 (`prompts_pin_changed` event — why's
"4 pinned revisions" claim reads it), 0047 (`fleet
ticket-cost` — why's per-PR cost claim uses the same
source), 0044 (`pr_footer_posted` — why's PR-count
claim reads it), 0019 (`fleet overview` — reuses
`overview_discover_slugs`).

Differentiated from `fleet invoice` (0061): invoice is
the numerical receipt; why is the persuasive
paragraph drawn FROM those numbers. Differentiated
from `fleet recap` (0048): recap is "what happened";
why is "why what happened was worth what it cost."
Differentiated from `fleet share <pr>` (0056): share
is per-PR; why is per-slug-lifetime.

### User (operator on a Friday DM with a peer)
The operator is in a Slack DM with a peer at 4pm
Friday. The peer asks "I'm thinking about agent-fleet
but I already pay for Cursor — what's the case for
adding another tool?" The operator types `fleet why
sidebrew --audience peer` in a terminal, copies the
paragraph, pastes it. The peer reads it, asks ONE
follow-up about the cross-LESSONS claim, the operator
runs `fleet lessons-rank --slug sidebrew` (0057) and
pastes the top three citations. The peer is converted;
or they aren't, but the conversation has been
PROVABLE on both sides. Per P-5 the win is the
operator's argument being defensible without
preparation.

Sub-scenario: the operator runs `fleet why sidebrew
--audience self` once a quarter as a journal entry.
The terse render is "47 PRs this quarter at $0.42;
3 stuck recoveries; 2 LESSONS shared; keep going."
Self-justification as a feature.

Sub-scenario: `fleet why --all` walks every slug and
emits one paragraph per slug, marking each `(keep)`
or `(consider removing)` based on the per-slug
verdict (same threshold as 0061 invoice).

### Growth
This is the surface that turns an evangelist
operator into a MORE EFFECTIVE evangelist. Most
acquisition flows assume the operator can
articulate the value proposition; in practice
operators struggle to. The kit composing the
argument FOR them — with citations — turns every
Slack DM into a potential adoption conversation
without the operator needing to be a marketer.
Per the brief's "why does a friend running their
own autonomous-agent setup want to adopt it?" —
why is the answer, composable on demand.

Differentiated from a marketing landing page:
landing pages are GENERIC; why is SPECIFIC to
the operator's slug. The peer asking the question
gets an answer rooted in REAL deployment
evidence, not a synthetic case study.

## Acceptance criteria

Each box maps 1:1 to a test scenario in `tests/why.sh`.

- [ ] `bin/fleet why <slug>` is a new subcommand.
      Required arg is the slug name (OR `--all`).
      Missing slug AND no `--all`: prints `why:
      usage: bin/fleet why <slug|--all> [--audience
      peer|manager|self] [--why-not] [--json]` to
      stderr, exit 2 per LESSONS 2026-06-01.
      Unknown slug: prints `why: slug <name> not
      found. discovered slugs: <list>` to stderr,
      exit 2. Per LESSONS 2026-05-30 the test
      assertion uses `grep -qF -- "$kw"`. Test
      asserts both refusals.
- [ ] The default audience is `peer`. The composed
      paragraph is ≤6 sentences AND ≤480
      characters total. Each sentence carries at
      least one CITATION token (a number drawn
      from the telemetry). Test asserts via
      fixture that the paragraph's sentence count
      is between 3 and 6 AND the character count
      is ≤480.
- [ ] The PR-count claim reads `pr_footer_posted`
      events in the trailing 8 weeks. The cost-
      per-PR claim reads each PR's row in
      `runs.jsonl` and computes the median. The
      stuck-PR-recovery claim counts events where
      the slug had an `infra_flake_rerun` event
      followed by a `run_completed exit=0` for
      the same PR (per 0020). The cross-LESSONS
      claim counts `lesson_promoted` events with
      `scope=all` in the slug's events.jsonl. The
      pinned-prompts claim counts
      `prompts_pin_changed` events in the same
      window. Per LESSONS 2026-06-08 every awk
      pass declares `BEGIN { count = 0 }`. Per
      LESSONS 2026-06-08 IFS=$'\t' middle-
      empty-field uses `-` sentinel. Test asserts
      all five counts via fixture.
- [ ] The "Cursor Pro alternative" cost is
      computed as `weeks × $5 / week` (Cursor
      Pro $20/mo ÷ 4 weeks). The "contractor
      alternative" cost is `PR_count ×
      MANUAL_PR_MINUTES / 60 ×
      CONTRACTOR_USD_PER_HOUR` (same manifest
      knobs from 0061 invoice, same defaults).
      Per LESSONS 2026-06-05 (export-in-
      subshell) the manifest read happens
      inside `( … )`. Test asserts via fixture.
- [ ] `bin/fleet why <slug> --audience peer`
      emits plain-English technical prose. The
      `manager` audience emits business-
      framed prose ("agent-fleet delivered N
      shipped features at $X each, below the
      $Y alternative cost"). The `self`
      audience emits terse journal-entry prose
      ("N PRs, $X each, K LESSONS shared,
      keep going"). All three share the same
      citations but differ in wording. Test
      asserts via fixture that each audience
      produces distinct first-sentence text.
- [ ] `bin/fleet why <slug> --why-not` inverts
      the argument: composes the case AGAINST
      keeping the kit installed for this slug.
      The threshold mirrors 0061 invoice's
      verdict: if `kit_cost > 1.1 ×
      min(cursor_alt, contractor_alt)`, the
      argument is GENUINELY against; otherwise
      the paragraph begins `against expectation,
      sidebrew's telemetry does NOT support
      removing the kit:` and then makes the
      positive case (honest tooling). Test
      asserts both branches via fixture.
- [ ] `bin/fleet why --all` walks every
      discovered slug and emits one paragraph
      per slug, each prefixed with the slug
      name and the verdict tag `(keep)` or
      `(consider removing)`. Per LESSONS
      2026-06-15 the per-slug loop runs ONE awk
      pass over events.jsonl AND ONE awk pass
      over runs.jsonl per slug — NOT per-
      audience re-walks. Test asserts via
      fixture with 3 slugs that each render
      with the appropriate verdict tag.
- [ ] The cross-LESSONS file path resolution
      uses `${FLEET_CROSS_LESSONS:-$HOME/.local/
      share/agent-fleet/CROSS_LESSONS.md}` —
      same convention as 0028 lessons-promote
      and 0009 cross-lessons. If the file is
      missing the cross-project claim renders
      as `cross-project memory: file not yet
      created — run \`fleet lessons-promote\`
      to seed`. Test asserts via fixture with
      and without the file present.
- [ ] `bin/fleet why <slug> --json` emits one
      structured JSON object: `{"slug":
      "<name>", "audience": "peer|manager|self",
      "verdict": "keep|consider_removing",
      "paragraph": "<text>", "citations":
      {"prs_merged": <int>, "cost_per_pr_usd":
      <number>, "stuck_recoveries": <int>,
      "lessons_promoted": <int>,
      "prompts_pinned": <int>}, "alternatives":
      {"cursor_usd": <number>, "contractor_usd":
      <number>}}`. JSON escape via
      `preflight_json_escape` per LESSONS
      2026-06-03 called directly per LESSONS
      2026-06-13 (no `*_json_escape` wrapper).
      Test asserts JSON validity via Node.
- [ ] The prose composer uses a template
      substitution shape (e.g.
      `Over the last ${WEEKS} weeks ${SLUG}
      shipped ${PR_COUNT} PRs at $${COST_PER_PR}
      each.`) where every `${TOKEN}` is
      replaced from the citations map. Per
      LESSONS 2026-06-15 (`while (match(s,
      /pat/)) { s = before repl after }`
      infinite-loop trap — `repl` may contain
      chars matching `pat`, e.g. `$5` matching
      `/\$[0-9]+/`) the substitution uses the
      CURSOR-based walk pattern. Test asserts
      via fixture that a token whose value
      contains `$<digit>` substring renders
      without infinite-looping AND the
      resulting string contains the literal
      value.
- [ ] `bin/fleet why --help` prints USAGE
      mentioning `--all`, `--audience`,
      `--why-not`, `--json`. Per LESSONS
      2026-05-30 test asserts via `grep -qF
      -- "$kw" "$help_out"`. Help block ends
      with `exit 0` per LESSONS 2026-06-01.
- [ ] `bin/fleet why` is a PURE READER. NO
      `events.jsonl` writes, NO
      `fleet_emit_event` calls, NO writes to
      `runs.jsonl` or `agents.config.sh` or
      the cross-LESSONS file. Test asserts
      every slug's `events.jsonl`,
      `runs.jsonl`, and the cross-LESSONS
      file byte sizes are unchanged before
      and after invocation.
- [ ] `lib/common.sh` — NO changes.
      `prompts/` — NO changes. No new event
      types. Test asserts via `git diff
      --name-only main...HEAD -- lib/common.sh
      prompts/` returns empty.
- [ ] `tests/why.sh` covers all 13 boxes
      above using `$HOME/.local/bin` stubs
      per LESSONS 2026-05-26 (PATH reset).
      Fixture `events.jsonl`, `runs.jsonl`,
      `agents.config.sh`, and a synthetic
      `CROSS_LESSONS.md` live under
      `tests/fixtures/why/`. Per LESSONS
      2026-05-27 backup/restore via `cp`.
      Counts use `awk … END { print n+0 }`
      per LESSONS 2026-06-01. Per LESSONS
      2026-06-08 every awk script declares
      `BEGIN { count = 0 }`. Per LESSONS
      2026-06-08 IFS=$'\t' middle-empty-
      field uses `-` sentinel. Per LESSONS
      2026-06-11 (BSD `date -j -f` fills
      missing time fields) any window math
      uses `date +%s` minus `weeks * 7 *
      86400`, no `date -j -f` involved.
      The clock is frozen via
      `FLEET_NOW_OVERRIDE`. Run-time
      budget: <8s.

## Out of scope

The dev agent will NOT do these even if they seem related.

- AUTO-POSTING the why paragraph as a PR
  comment, a README badge, or a tweet. v1 is
  operator-pulled. The operator pipes the
  output where they want it.
- A `--language <code>` flag for non-English
  prose. v1 ships English only.
- A WEBSITE TEMPLATE that hosts the why
  paragraph publicly (a Jekyll-style "why I
  use agent-fleet" page). v1 ships text;
  publishing is the operator's job.
- AI-GENERATED prose variation (calling
  Claude to rephrase the paragraph). v1 uses
  deterministic template substitution. No
  Claude calls. Adding nondeterminism to a
  growth surface is a separate ticket with
  its own risk surface.
- A `--audience funder` mode for VC pitch
  decks. v1 ships peer/manager/self.
- A LIFETIME claim (since first install). v1
  windows at 8 weeks of trailing data so the
  claim is current. Lifetime is a v2
  candidate.
- AUTO-FIRING when the operator runs
  `fleet morning` or `fleet weekly`. v1 is
  standalone. Composability is good but v1
  doesn't change existing surfaces.
- INTEGRATING why into the `fleet pulse`
  prompt-line (a "verdict character" per
  slug). v1 is a paragraph; pulse stays a
  glance.
- A `--diff <slug-a> <slug-b>` mode
  comparing two slugs' arguments. v1 is
  per-slug.
- WRITING the paragraph to a state file the
  operator can `cat`-out later. v1 prints
  fresh every time; staleness is more
  expensive than recompute (~150ms).

## Engineering notes

Files / patterns the dev should touch.

- `bin/fleet` — new `why()` dispatcher
  function placed next to the existing
  `share()` block (find via `grep -n
  '^share()' bin/fleet`). Per LESSONS
  2026-05-26 (`tail` shadow) `why` does not
  collide with any coreutils binary.
- `bin/fleet` — eight helpers, ALL defined
  ABOVE the dispatcher block per LESSONS
  2026-06-05 (forward-reference trap):
  - `why_discover_slugs` — wraps
    `overview_discover_slugs`, returns
    alphabetical order.
  - `why_walk_citations` — ONE awk pass per
    slug over events.jsonl AND ONE awk pass
    over runs.jsonl, building the citations
    map (PR count, cost-per-PR median, stuck
    recoveries, lessons promoted, prompts
    pinned). Per LESSONS 2026-06-08
    `BEGIN { count = 0; promoted = 0 }`.
    Per LESSONS 2026-06-08 IFS=$'\t'
    middle-empty-field uses `-` sentinel.
    Per LESSONS 2026-06-15 the bucket math
    is pure awk arithmetic.
  - `why_read_cross_lessons` — counts the
    slug's promoted entries in the cross-
    LESSONS file via `grep -c` (per LESSONS
    2026-06-01 the count is read through
    awk to avoid the `grep -c file || echo
    0` double-print trap).
  - `why_compute_verdict` — pure-shell
    classifier returning `keep |
    consider_removing` per the 0061-aligned
    threshold.
  - `why_compose_paragraph` — template
    substitution using the CURSOR-based
    walk pattern per LESSONS 2026-06-15
    (the values may contain `$<digit>`
    substrings that match a naive
    `/\$[0-9]+/` regex used to find the
    next token, infinite-looping the
    recursive shape). Three audience
    templates: peer, manager, self.
  - `why_compose_why_not` — same composer
    but inverted prose for the
    `--why-not` path.
  - `why_render_text` — text formatter.
    Width via `preflight_visible_width`
    per LESSONS 2026-06-05. Per LESSONS
    2026-05-28 every printf of a slug
    name goes through `printf -- '%s'`.
  - `why_render_json` — JSON formatter.
    JSON escape via
    `preflight_json_escape` per LESSONS
    2026-06-03 called directly per
    LESSONS 2026-06-13 (no
    `*_json_escape` wrapper).
- `bin/fleet` — `why()` end-state must be
  `exit 0` / `exit 2` on every code path
  per LESSONS 2026-06-01.
- `bin/fleet` — dispatcher block: `if [
  "$CMD" = "why" ]; then why "$@"; fi`.
  Place AFTER the `share` dispatcher.
- `bin/fleet` — help banner block at the
  top of the file gets ONE new line:
  `fleet why <slug> compose the case for
  keeping the kit installed against the
  slug's own telemetry`. README "Daily
  ops" code block gets the same line,
  appended via the same single-edit
  pattern that avoided LESSONS 2026-05-25.
- `AGENTS.md` — NO content change.
- `lib/common.sh` — NO changes.
- `prompts/` — NO changes.
- `tests/fixtures/why/` — NEW directory
  holding four slug subdirs (`keep-strong`,
  `keep-marginal`, `remove-candidate`,
  `first-week`) each with `events.jsonl`,
  `runs.jsonl`, `agents.config.sh`. A
  synthetic `CROSS_LESSONS.md` covers AC
  #8's cross-project claim. A fifth
  `missing-cross-lessons` slug exercises
  the file-absent branch.
- `tests/why.sh` — top of file mirrors
  `tests/recap.sh` (closest prior reader;
  shares the composed-prose pattern).
  Stubs live under `$HOME/.local/bin` per
  LESSONS 2026-05-26 (PATH reset). Counts
  use `awk … END { print n+0 }` per
  LESSONS 2026-06-01. Per LESSONS
  2026-05-27 backup/restore via `cp`. The
  clock is frozen via `FLEET_NOW_OVERRIDE`.
  Per LESSONS 2026-06-15 the events.jsonl
  walk is ONE awk pass per slug. Run-time
  budget: <8s.
- New deps: none. Pure shell + awk + Node
  (already a kit dep for JSON validation
  in the test).
- Public API: additive — `bin/fleet why`
  is a new subcommand. ZERO new event
  types, ZERO event writes, ZERO
  `lib/common.sh` changes, ZERO
  `prompts/` changes. Reuses the two
  optional `agents.config.sh` knobs
  introduced by 0061 (`MANUAL_PR_MINUTES`,
  `CONTRACTOR_USD_PER_HOUR`) with the
  same defaults. Sequencing note: 0061
  should ship BEFORE 0062 so the manifest-
  knob convention is settled; if 0062
  ships first, why inlines the same
  defaults and 0061 picks them up.
- BREAKING flag: NO. PR body affirms
  "pure reader, no events.jsonl writes,
  no `fleet_*` signature changes, no new
  manifest knobs (reuses 0061's)."
- Reinstall required: NO. `lib/` and
  `prompts/` are untouched.
- LESSONS to defend against: 2026-05-25
  (README "Daily ops" code block addition),
  2026-05-26 (`tail` shadow), 2026-05-26
  (PATH reset — stubs in
  `$HOME/.local/bin`), 2026-05-27
  (`$(cat)` trap — use `cp` for backup/
  restore in tests), 2026-05-28 (printf
  leading-dash — every slug-name /
  dollar-amount printf goes through
  `printf -- '%s'`), 2026-05-30 (`grep
  -F --` trap), 2026-06-01 (`grep -c
  file || echo 0` double-print —
  cross-LESSONS count uses `awk … END
  { print n+0 }`), 2026-06-01
  (dispatcher fall-through — every code
  path ends `exit 0/2`), 2026-06-03
  (UTF-8 sign-extension — JSON escape
  via `preflight_json_escape`),
  2026-06-05 (dispatcher forward-
  reference — all `why_*` helpers
  defined ABOVE the dispatcher),
  2026-06-05 (bash 3.2 LC_ALL caching —
  any string-length op via `LC_ALL=C
  awk`), 2026-06-05 (export-in-subshell
  trap — manifest reads inside
  `( … )`), 2026-06-08 (awk empty-
  string-key — `BEGIN { count = 0 }`),
  2026-06-08 (IFS=$'\t' middle-empty-
  field — sentinel `-`), 2026-06-11
  (BSD `date -j -f` fills missing time
  fields with NOW-of-day — window math
  uses `date +%s` minus `weeks * 7 *
  86400`, no `date -j -f` involved),
  2026-06-13 (no `*_json_escape`
  wrapper around
  `preflight_json_escape` — called
  directly), 2026-06-15 (per-day
  shellout inside per-slug loops is
  O(window × N_slugs) — events.jsonl
  walk is one awk pass per slug),
  2026-06-15 (awk `while (match(s,
  /pat/)) { s = before repl after }`
  infinite-loop trap — template
  substitution uses CURSOR-based walk
  pattern, NOT recursive shape, because
  citation values may contain `$<digit>`
  substrings matching the token regex).
- This ticket compounds 0061 (`fleet
  invoice` — why is the argument shape
  of invoice's number shape; reuses the
  two manifest knobs), 0048 (`fleet
  recap` — recap narrates; why argues),
  0028 (`lesson_promoted` event — why's
  cross-project claim reads it), 0024
  (`prompts_pin_changed` event — why's
  pinned-prompts claim reads it),
  0047 (`fleet ticket-cost` — why's
  per-PR cost claim uses the same
  source), 0044 (`pr_footer_posted` —
  why's PR-count claim reads it),
  0019 (`fleet overview` — reuses
  `overview_discover_slugs`), 0020
  (`infra_flake_rerun` event — why's
  stuck-recovery claim reads it).
  Per P-1 the diff is small: ~280
  lines of `why_*` helpers + ~270
  lines of test + 5 fixture slug
  subdirs + one help-text line + one
  README line.

## Implementation log

(Appended by the implementation-dev agent during execution.)
