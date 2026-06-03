---
id: 0029
title: fleet provenance <pr> reconstructs the prompts SHA, lessons, and heal patterns behind a shipped PR
status: in-progress
priority: P1
area: governance
created: 2026-06-03
owner: gtm-innovation
---

## User story

As a fleet operator who just merged PR #137 and woke up six weeks later
wanting to answer "what prompts SHA shipped this? which heal patterns
fired? which LESSONS were in the cross-feed at the time? which review
verdict signed it off?" — without grepping `events.jsonl` by hand and
cross-referencing `prompts/CHANGELOG.md` against `git log` — I want
`bin/fleet provenance <slug> <pr-number> [--format text|json|md]` to
print a single-page receipt that pins exactly what went into shipping
that PR, so that the kit's "the loop is auditable" claim becomes a
one-command demonstration instead of an after-the-fact archaeology dig.

## Why now (four lenses)

### Product Owner
The kit's strongest internal claim is that every PR is the deterministic
output of a pinned prompts SHA + the LESSONS at PHASE 0 + the heal
catalog patterns that fired + the review verdict. Today that claim is
TRUE but UNVERIFIABLE without an operator running five separate
queries — `gh pr view`, `awk` against `events.jsonl`, `git log
prompts/CHANGELOG.md`, `gh pr view --comments` for the review, and a
manual scan of `docs/LESSONS.md` for the appended draft. The smallest
meaningful unit of value is one command that does all five and emits
ONE artifact. Subtraction: the operator stops having to remember the
five queries — `fleet provenance courtiq 137` IS the audit. This is
the same shape as `fleet badge` (0027) — a pure consumer of telemetry
that turns existing channel data into a single-glance artifact. Per
P-5 (operator confidence over feature richness), this is confidence
infrastructure: it lets the operator answer "why did the agent do
that?" without grepping transcripts.

### Stakeholder
This widens the moat in the specific direction that distinguishes
agent-fleet from "just running claude in a loop": auditable lineage.
Every other autonomous-agent tool's "explainability" story is a
transcript log. agent-fleet's is a typed event stream pinned to a
content-addressable prompts SHA. `fleet provenance` is the operator-
facing surface that EXERCISES that distinction. It compounds 0005
(PROMPTS_SHA pin), 0013 (prompts/CHANGELOG.md), 0021 (replay), 0022
(lesson drafts), 0024 (prompts-score). None of those tickets shipped
a single command that joins them; provenance is the join. Critically,
it adds NO new event types — it's a read-only consumer per P-6, which
means it can ship without a fleet-wide reinstall. It does, however,
EXPOSE the existing channel's design: every consumer of the kit
suddenly sees that the channel is the moat, not the prompts. That is
the right thing to make visible.

### User (operator, 9am, someone asked "did the agent really write
ticket 0037?")
Runs `bin/fleet provenance agent-fleet 51 --format md`. Sees:

```
# Provenance — agent-fleet PR #51

shipped:        2026-06-01T11:23:04Z (squash a5f9c2b)
ticket:         0028 — fleet lessons-promote curates a local lesson into cross-project feed
branch:         feat/0028-fleet-lessons-promote-cross-project
prompts SHA:    7a3e1c0… (pinned in agents.config.sh; matched prompts/ at run time)
prompts version: changelog entry 2026-05-29 (CHANGELOG.md line ~118)
heal attempts:  0
infra-flake reruns: 1 (gh_graphql_502 at 2026-06-01T10:48:21Z)
review verdict: --comment (auto-merge proceeded)
lesson drafts emitted: 0
cross-fleet lessons at PHASE 0: 14 (digest sha 9c1ab2…)
budget block events: 0
spend: $0.46
```

`--format text` is the same content, no markdown. `--format json` is
the machine-readable variant fleet-control can stitch into a "PR
lineage" pane next to the diff. Operator gets ONE answer: "yes, the
agent really wrote it, here is the recipe."

### Growth
"Look at this — every PR the fleet ships comes with a one-command
receipt of the prompts SHA, the lessons in scope, and which infra
flakes the loop self-healed past" is a credibility-on-rails pitch.
The badge (0027) makes the OUTPUT visible; provenance makes the
PROCESS visible. A friend evaluating an autonomous-agent kit reads
`fleet provenance` output and immediately understands the kit's
unique posture: this isn't a chatbot loop, it is a content-addressable
build system whose artifacts happen to be GitHub PRs. The md output
is also paste-friendly into the PR body as a comment — `gh pr comment
N --body-file <(fleet provenance ... --format md)` becomes a one-line
operator habit that compounds the audit trail every shipping cycle.

## Acceptance criteria

Each box maps 1:1 to a test scenario in `tests/provenance.sh`.

- [ ] `bin/fleet provenance <slug> <pr>` (no flags) defaults to
      `--format text` and exits 0 on a happy-path lookup. Prints a
      block whose first line is `Provenance — <slug> PR #<n>` and
      whose subsequent lines are key/value pairs in the fixed order:
      `shipped`, `ticket`, `branch`, `prompts SHA`, `prompts version`,
      `heal attempts`, `infra-flake reruns`, `review verdict`,
      `lesson drafts emitted`, `cross-fleet lessons at PHASE 0`,
      `budget block events`, `spend`. Test fixtures a synthetic
      `events.jsonl` + `runs.jsonl` and asserts the exact ordered
      block via a checked-in golden `tests/fixtures/provenance.text
      .golden.txt`.
- [ ] `--format md` renders the same fields under a `# Provenance
      — <slug> PR #<n>` H1 and a fenced metadata block. The trailing
      line ends with a `<!-- generated by fleet provenance -->`
      marker (same regenerate convention as `fleet badge`, AC#3 of
      ticket 0027) so a future cron can sed-replace the block in
      place. Byte-exact assertion against
      `tests/fixtures/provenance.md.golden.txt`.
- [ ] `--format json` emits one JSON object with the same keys
      (snake_cased: `shipped_at`, `ticket_id`, `ticket_title`,
      `branch`, `prompts_sha`, `prompts_changelog_entry`,
      `heal_attempts`, `infra_flake_reruns`, `review_verdict`,
      `lesson_drafts_emitted`, `cross_lessons_count`,
      `cross_lessons_sha`, `budget_block_events`, `spend_usd`).
      Parsed via `node -e 'JSON.parse(require("fs").readFileSync("/dev/stdin","utf8"))'`
      — fails the test on parse error. No trailing newline before
      the close brace. Per LESSONS 2026-06-01 awk newline trap,
      composing values via `_json_escape`, NOT `awk -v var=$multi`.
- [ ] `prompts SHA` resolves from the `events.jsonl` entries written
      during the ship run: scan for the last `prompts_drift` event
      BEFORE the `pr_opened {number=<pr>}` event on this slug — if
      drift fired, the `actual` field is the SHA that shipped, else
      the manifest's `PROMPTS_SHA=` value at squash time (read via
      `git show <merge-sha>:agents.config.sh` if the slug's repo is
      local, else from the cached manifest). Test fixtures both
      branches (with-drift, without-drift) and asserts the right
      SHA wins.
- [ ] `prompts version` resolves the `prompts/CHANGELOG.md` entry
      whose `## YYYY-MM-DD` heading immediately precedes the
      shipped SHA in chronological order. Reuses
      `prompts_diff_changelog` (line ~217 of `bin/fleet`) to walk
      changelog entries. When no changelog entry matches, prints
      `(no changelog entry — pre-CHANGELOG ship)` and continues —
      this is informational, never fatal. Test asserts both
      branches.
- [ ] `heal attempts` is the count of commits on the merge SHA's
      first-parent chain whose subject begins with `heal:`. Reuses
      `git log --format=%s <base>..<merge>` where `<base>` is the
      branch's first commit. Caps the count at 2 (per AGENTS.md
      Hard NOs — the 2-attempt heal cap means anything >2 is a
      data bug, surface it). Test fixtures a 0/1/2 heal branch.
- [ ] `infra-flake reruns` is the count of `infra_flake_rerun`
      events (per ticket 0020) on this slug's events.jsonl whose
      `pr=<pr>` matches AND whose `ts` falls between the PR's
      `pr_opened` and the merge `ts`. Each rerun's `pattern` is
      listed parenthetically in the text/md output. Reuses the
      heal-catalog patterns from `lib/heal-catalog.sh` (4 patterns
      today). Test asserts a zero-rerun PR and a 1-rerun PR
      (pattern `gh_graphql_502`).
- [ ] `review verdict` is either `--request-changes` (any
      `lesson_draft_emitted` event with `pr=<pr>` before merge ⇒
      a send-back fired) or `--comment` (sign-off; no draft). The
      command does NOT call `gh api` — the events channel is the
      source of truth per P-6. Test asserts both branches.
- [ ] `cross-fleet lessons at PHASE 0` is a count + first-8-char
      SHA of the kit's `CROSS_LESSONS.md` content AT THE TIME of
      the merge SHA. Reconstructed by reading the kit's git history
      for that file at the merge timestamp (`git log -1
      --until=<ts> --format=%H -- CROSS_LESSONS.md` then
      `git show <sha>:CROSS_LESSONS.md` and counting `^### ` lines).
      Falls back to the current file's count when the kit repo
      isn't a git checkout (test asserts both). Per LESSONS
      2026-05-27 ($(cat) trap), the content is piped through awk,
      not captured to a variable that gets written back.
- [ ] `spend` reuses `digest_spend_since` (line ~1169) restricted
      to the window `[pr_opened.ts, merged.ts]` for this slug, NOT
      a calendar day. Rendered as `$N.NN`. Test asserts a
      non-zero-spend branch.
- [ ] Unknown PR: `provenance: PR #<n> not found in
      events.jsonl for <slug> (no pr_opened or run_completed
      event matched)` to stderr, exit 2. Test asserts the exact
      error and exit code. NO `gh api` fallback — the absence of
      the event is the answer (per P-6 telemetry is the source
      of truth).
- [ ] Unknown slug: `provenance: no project with SLUG=<slug>
      found (looked under FLEET_DISCOVERY_ROOT=<path>)` to stderr,
      exit 2. Test asserts the exact error.
- [ ] Help: `bin/fleet provenance --help` prints a USAGE block
      mentioning `--format`, `--help`, the three format values,
      and one example. Test asserts via `grep -qF -- "$kw"
      "$help_out"` per LESSONS 2026-05-30. Help block ends with
      `exit 0` per LESSONS 2026-06-01 (dispatcher fall-through
      trap).
- [ ] `tests/provenance.sh` covers all 13 boxes using
      `$HOME/.local/bin` stubs (per LESSONS 2026-05-26) for any
      command shelled out to. `FLEET_DISCOVERY_ROOT` redirected
      to `tests/fixtures/provenance/`. `gh` and `git` are stubbed
      to fail-on-invoke for the "no network" assertion — the
      command MUST succeed reading only local channel files and
      a synthetic git replay dir. Per LESSONS 2026-05-27, the
      test uses `cp` for backup/restore — never `$(cat …)`.
      Run-time budget: <10s.
- [ ] No new event types. `provenance` is a pure consumer of the
      existing telemetry channel (P-6). The PR body affirms "no
      new event types added; no AGENTS.md § Telemetry append
      needed."

## Out of scope

The dev agent will NOT do these even if they seem related.

- Cryptographic signing of the receipt (e.g. emitting a signed
  manifest the operator can publish). That is `fleet attestation`
  territory — a sibling moat-deepening ticket. v1 is plain text /
  md / json, no signature.
- A `fleet provenance --all` that batches every recent PR. The
  shape is one PR, one receipt — aggregation is `fleet weekly`'s
  job (0025).
- Re-running the prompts that shipped the PR (that's `fleet
  replay`, ticket 0021). Provenance READS what happened; replay
  RE-RUNS it. Coexist.
- Posting the receipt to the PR as a comment automatically. The
  operator pipes it themselves (`gh pr comment N --body-file <(...)`).
  Auto-posting adds a side-effect on the PR thread the kit
  shouldn't take.
- Fleet-control UI rendering. The command emits the JSON contract;
  the portal builds on it later. Adding a portal coupling here
  would re-introduce the moat-tax fleet-control is supposed to
  pay, not us.
- A "diff against previous PR's provenance" view. Useful eventually,
  but the diff primitive belongs in a sibling ticket once two
  receipts exist in the wild.
- Editing `events.jsonl` to backfill missing events for a PR
  shipped before this command existed. The channel is append-only
  per AGENTS.md; missing events read as "(no event recorded)" in
  the output and the operator accepts the gap.

## Engineering notes

Files / patterns the dev should touch. Specific enough that the dev
doesn't have to re-discover the architecture.

- `bin/fleet` — new `provenance()` dispatcher next to `replay()`
  (line ~4385) and `prompts_score()` (line ~2906). Shape mirrors
  `replay()`: same `*_resolve_manifest` pattern (sibling helpers
  at line ~3841 for kickstart, ~4267 for replay) — extract a new
  `provenance_resolve_manifest()` that wraps the same union.
- `bin/fleet` — five helpers, all pure readers:
  - `provenance_find_pr_window()` — scans the slug's
    `events.jsonl` for the `pr_opened {number=<pr>}` event AND
    the `run_completed` event whose ts most-immediately follows
    the squash; echoes `<open_ts>\t<merge_ts>\t<merge_sha>` or
    empty.
  - `provenance_prompts_sha()` — walks events between the
    window for the last `prompts_drift`; falls back to
    `git show <merge_sha>:agents.config.sh | sed -n
    's/^PROMPTS_SHA=//p'`.
  - `provenance_changelog_entry()` — reuses
    `prompts_diff_changelog` (line ~217) to find the YYYY-MM-DD
    entry whose date precedes the merge ts.
  - `provenance_heal_count()` — `git log --format=%s
    <branch-base>..<merge_sha>` then `grep -c '^heal:'` —
    capped at 2.
  - `provenance_render_text/md/json()` — one per `--format`. The
    JSON path goes through `_json_escape` (lib/common.sh line
    ~849) — never `awk -v var=$multiline` per LESSONS
    2026-06-01.
- `bin/fleet` — dispatcher block at the bottom of the file:
  `if [ "$CMD" = "provenance" ]; then provenance "$@"; fi`.
  The `provenance()` function body MUST end with explicit
  `exit 0` per LESSONS 2026-06-01 (dispatcher fall-through
  trap) — verify by copying `weekly()`'s exit-0 pattern verbatim
  (line ~2042 ends `exit 0`).
- `bin/fleet` — help banner block at the top of the file
  (around the `fleet badge`/`fleet lessons-promote` lines, ~14)
  gets a new line: `fleet provenance <slug> <pr>  one-command
  audit receipt for a shipped PR (text/md/json)`. README "Daily
  ops" code block gets the same.
- `lib/common.sh` — NO changes. `provenance` is a pure reader;
  per P-6 it does not emit new events. The PR body affirms this
  so the reviewer's telemetry-contract check stays satisfied. NO
  `fleet_*` signature changes — additive subcommand only.
- `prompts/` — NO changes. The command is operator-facing only;
  no agent prompt reads `fleet provenance`. No `Reinstall: all
  projects` line is needed because `lib/` and `prompts/` are
  untouched.
- `tests/fixtures/provenance/` — NEW directory under
  `tests/fixtures/` holding:
  - one synthetic `<slug>/agents.config.sh` with a
    `PROMPTS_SHA=` line and a `REPO_URL=` line
  - one synthetic `events.jsonl` with `pr_opened`,
    `prompts_drift`, `infra_flake_rerun`,
    `lesson_draft_emitted`, `run_completed` rows across two
    PRs (one with drift + rerun, one clean)
  - one synthetic `runs.jsonl` row with a non-zero spend
  - one synthetic git replay dir holding `git show
    <sha>:agents.config.sh` output for the merge SHA branch
    (a flat file, the stub `git` reads it positionally)
  - three goldens: `provenance.text.golden.txt`,
    `provenance.md.golden.txt`, `provenance.json.golden.txt`
- `tests/provenance.sh` — top of file mirrors `tests/badge.sh`:
  redirect `FLEET_DISCOVERY_ROOT`, stub `gh` and `git` under
  `$HOME/.local/bin` (`$HOME` set to `$TMP/home` per LESSONS
  2026-05-26) — the `gh` stub fails on invoke (asserts the
  command does not require network); the `git` stub reads from
  the synthetic replay dir for `git show <sha>:<path>` and
  `git log --format=%s`. The JSON test parses output via
  `node -e 'JSON.parse(require("fs").readFileSync(0,"utf8"))'`.
- New deps: none. Pure shell + awk + existing
  `digest_spend_since`, `digest_parse_since`,
  `prompts_diff_changelog`, `_json_escape` (common.sh ~849).
  No `jq` (writer side stays shell-only per ticket 0002; the
  test READS json via node, which is already a pre-existing
  test dep — see `scripts/check-backlog.mjs`).
- Public API: additive — `bin/fleet provenance` is a new
  subcommand, no new event types, no `fleet_*` signature changes.
- BREAKING flag: NO. PR body affirms "no `fleet_*` signature
  changes" and "no new event types added."
- Reinstall required: NO. `lib/` and `prompts/` are untouched.
- LESSONS to defend against: 2026-05-26 (`tail` shadow — verify
  `provenance` does not collide with a coreutils binary; `command
  -v provenance` is empty on macOS and Ubuntu). LESSONS
  2026-05-27 ($(cat) trap — every fixture read uses `cp`/awk,
  never command substitution that round-trips to disk). LESSONS
  2026-05-28 (printf leading-dash trap — every `printf "$key:
  $value"` becomes `printf -- '%s: %s\n' "$key" "$value"`).
  LESSONS 2026-05-30 (`grep -F --` flag trap — every help-text
  assertion uses `grep -qF --`). LESSONS 2026-06-01 (awk -v
  multiline trap — JSON composition goes through
  `_json_escape`, multi-line values go through a tmp file +
  `getline`). LESSONS 2026-06-01 (dispatcher fall-through trap —
  `provenance()` ends with explicit `exit 0`, mirroring `badge`
  / `weekly` / `lessons_promote`).
- This ticket compounds 0002 (events.jsonl), 0005 (prompts SHA
  pin), 0013 (prompts/CHANGELOG.md), 0020 (heal-catalog +
  infra_flake_rerun events), 0021 (replay — the runs.jsonl row
  shape), 0022 (lesson_draft_emitted events), 0024
  (prompts-score's CHANGELOG walker). It introduces ZERO new
  substrate; every primitive it reads already exists. Per P-1
  the diff is small: ~300 lines of `provenance*` helpers + ~120
  lines of test fixture content + 3 goldens + one help-text
  line.

## Implementation log

- 2026-06-03 — implementation-dev: branch `feat/0029-fleet-provenance-pr-forensics`,
  failing test first in `tests/provenance.sh` covering all 13 ACs, then
  `provenance()` + helpers in `bin/fleet` (pure consumer; no `lib/` /
  `prompts/` edits, no new event types).
