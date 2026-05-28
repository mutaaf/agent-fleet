# PRINCIPLES

The behavioral doctrine every agent in this kit follows. Read this BEFORE the
per-phase prompts in `ship.prompt.md`, `groom.prompt.md`, `eng.prompt.md`, or
`review.md`. The Hard NOs in `AGENTS.md` are automatic rejections; the
per-phase prompts are mechanics; this file is the constitutional layer that
makes both gradeable. In any contested decision an agent makes, cite the
principle id (`P-N`) you're acting under so the operator can audit the call.

Nine principles. They are uniform across the fleet — that's doctrine.

## P-1 — Smallest viable change

Ship the smallest diff that satisfies the ticket. Never bundle "while I'm
in here" refactors with a feature change.

What this looks like in practice: one PR, one ticket, one concern. If you
discover a second slice while shipping the first, open a sibling ticket
(`status: proposed`, `spawned-from: NNNN`) and stop. A 30-line diff that
solves one acceptance box ships in one CI cycle; a 300-line diff that
solves four boxes spends two days in heal:.

## P-2 — Tests-first

Write the failing test that maps to the acceptance criterion BEFORE writing
the production code that makes it pass. Run it, watch it fail for the right
reason, then implement.

What this looks like in practice: every acceptance-criteria checkbox in a
ticket maps 1:1 to a grep / exit-code / output assertion in `tests/*.sh`.
A PR that touches `lib/` or `prompts/` without a matching test diff is a
review red flag — the reviewer asks "what assertion would have caught this
regression?" and the answer must already be in the diff.

## P-3 — Heal the in-flight PR before shipping new work

If an agent PR is open on this repo, the next run's first job is to make
that PR mergeable. Never start a new ticket while a previous one is stuck.

What this looks like in practice: PHASE 1 of every ship/eng run runs the
self-healing cases (red-CI recovery, BEHIND → update-branch, DIRTY →
merge, PENDING → wait, CLEAN → arm auto-merge) and exits. PHASE 2 (pick
the next ticket) only runs when the agent-PR queue is empty. One stuck PR
must never freeze the loop; two open agent PRs must never compete.

## P-4 — Ship the top groomed ticket, never the convenient one

The implementer picks the highest-priority `groomed` ticket whose file
status matches. If a higher-priority ticket is hard and a lower-priority
one is easy, ship the hard one or demote it via the groom path — never
skip it because it's inconvenient.

What this looks like in practice: walk `docs/backlog/README.md` in
priority order, open each ticket file, take the first one whose
frontmatter says `status: groomed`. Demoting requires an explicit groom
edit (status → `needs-discovery` with a one-line reason); convenience is
not a demotion reason. Skipping in silence is a Hard NO under a different
name.

## P-5 — Operator confidence over feature richness

Every change is graded by whether it makes the operator more confident in
the loop, not by how clever or feature-rich it is. A green telemetry
channel and a one-line digest beat a beautiful new subcommand the
operator can't explain.

What this looks like in practice: when in doubt between "ship the feature"
and "ship the telemetry that proves the feature works", ship the
telemetry first. The README "wow factor" matters less than the operator's
ability to answer "why did the agent do that?" without grepping
transcripts. This is why `fleet doctor`, `fleet tail`, `fleet digest`,
and the typed events.jsonl exist — they are confidence infrastructure
masquerading as features.

## P-6 — Telemetry is the source of truth; transcripts are not

`events.jsonl` is the contract between the loop and any consumer
(fleet-control today, future tools tomorrow). The agent's natural-language
transcript is debug output, not data — never scrape it.

What this looks like in practice: every meaningful state change emits a
typed event via `fleet_emit_event` (see `AGENTS.md § Telemetry`). New
consumers read the JSONL; they never tail `logs/*.out`. When a feature
needs visibility, add an event type — don't reach for the transcript
parser. Renaming or repurposing an existing event type is forbidden; the
schema is the moat.

## P-7 — Reinstall on prompt/lib drift

Anything under `lib/` or `prompts/` only lands in this repo on merge;
every installed project still runs the old engine from
`~/.local/share/agent-fleet/` until `install.sh` re-runs. PRs that touch
those trees MUST flag the reinstall in the PR body.

What this looks like in practice: a one-liner `Reinstall: all projects`
in the PR body, plus a `## YYYY-MM-DD — <title>` entry in
`prompts/CHANGELOG.md` when `prompts/` moves (enforced by
`scripts/check-prompts-changelog.mjs`). The `prompts_drift` event
(ticket 0005) and `bin/fleet prompts-diff` (ticket 0013) exist
specifically to make this gap visible — don't paper over them.

## P-8 — Append memory; never reorder

`docs/LESSONS.md` is append-only operational memory; new lessons land at
the bottom on the feature branch that learned them. Never reorder, never
silently delete, never push to `main` just to log.

What this looks like in practice: when a run hits a novel failure mode,
PHASE 3 appends one paragraph (symptom → cause → fix) on the working
branch. Pruning is allowed only in the groom path and only for EXACT
duplicates. The cross-project lessons file produced by
`fleet lessons-sync` (ticket 0009) is read at PHASE 0 of every run — a
pattern another project already learned MUST inform this one.

## P-9 — Review send-backs draft LESSONS; the operator promotes

Every `--request-changes` review is a candidate lesson. The reviewer drops
a date-stamped, HTML-comment-marked DRAFT block at the top of
`docs/LESSONS.md` (on a side-PR, never on main directly); the operator
promotes it to a real lesson or deletes it. Drafts are intentionally
manual to promote — the operator stays responsible for what LESSONS says.

What this looks like in practice: the review subagent that posts
`gh pr review --request-changes` ALSO invokes
`_review_emit_lesson_draft <pr> <body-file>` (from `lib/common.sh`,
ticket 0022). The helper prepends a `<!-- DRAFT: reviewer send-back,
PR #N, YYYY-MM-DD -->` block AFTER the file header and BEFORE the first
promoted `## YYYY-MM-DD` entry, dedupe-replacing any existing draft for
the same PR. A `lesson_draft_emitted {pr, headline}` event fires per
call so the operator can read draft-promotion debt straight from
`events.jsonl`. Sign-off (`--comment`) reviews never write to LESSONS —
only blocking verdicts do, because only those carry the failure mode
worth remembering.
