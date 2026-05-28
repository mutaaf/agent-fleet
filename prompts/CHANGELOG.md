# prompts CHANGELOG

Operator-curated record of behavioral changes to the prompts. Newest first.
Each entry: `## YYYY-MM-DD — <one-line title>` heading + a short prose
paragraph explaining the *intent* of the change (not the diff — that's
`fleet prompts-diff`). This file is part of `prompts/`, so its bytes feed
into `bin/fleet prompts-sha` and any change here surfaces as drift in
`fleet doctor`'s `prompts_pinned` check. That is intentional: an entry
landing here IS the behavioral commit.

The companion command is `bin/fleet prompts-diff` (ticket 0013):

- `fleet prompts-diff` — unified diff of installed vs current prompts/.
- `fleet prompts-diff --since <SHA>` — diff against a historical pin.
- `fleet prompts-diff --changelog` — print all entries newer than the
  installed-prompts SHA (verbatim markdown from this file).

## 2026-05-28 — ship PHASE 1 RED gains an infra-flake pre-step

The heal step's contract was "red gating check → run the local gate,
fix the root cause, commit `heal:`". That assumption burns two heal
attempts and real claude budget on failures that are NOT the agent's
code — GitHub Actions silently stopping, `supabase start` losing a
port-bind race, transient `Your account is suspended` 403s from
`actions/checkout@v4`, `gh pr checks --watch` aborting on a GraphQL
502. Ticket 0020 introduces `lib/heal-catalog.sh` (four hand-curated
regexes pinned to the LESSONS entry each one codifies) and two new
shell helpers in `lib/common.sh`: `fleet_match_infra_flake <log>`
prints the matching catalog token (or empty), and
`fleet_infra_flake_already_rerun <token> <run_id>` answers the dedupe
question from `events.jsonl`. The ship prompt's PHASE 1 (a) branch
now downloads the failed job log via `gh run view <id> --log-failed`,
runs it through `fleet_match_infra_flake`, and on a match: triggers
`gh run rerun <id> --failed` exactly once, emits
`infra_flake_rerun pattern=<token> run_id=<id> pr=<N>`, prints
`INFRA_FLAKE <token> — rerunning run <id>`, and exits with no `heal:`
commit and no heal-attempt counter advance. A second match on the
same `<token>+<run_id>` within 2h falls through to the normal heal
path so a genuinely-broken infra cannot trap the runner in a rerun
loop. Catalog growth: one line in `lib/heal-catalog.sh` + a fixture
log in `tests/heal-infra-flake.sh` + an inline LESSON reference
(date + repo) per pattern. Auto-detection of NEW infra flakes is
out of scope; that lives in a follow-up ticket.

## 2026-05-27 — PRINCIPLES.md adds the constitutional layer

Introduces `prompts/PRINCIPLES.md` — eight numbered principles (`P-1` ..
`P-8`) that name the loop's behavioral doctrine in one place: smallest
viable change, tests-first, heal in-flight PR before new work, ship the
top groomed ticket (never the convenient one), operator confidence over
feature richness, telemetry is the source of truth, reinstall on prompt/
lib drift, append memory never reorder. The three runner prompts
(`ship`, `groom`, `eng`) gain a one-line PHASE 0 directive instructing
the agent to read PRINCIPLES.md first and cite `P-N` ids in any
contested decision. `lib/review.sh` adds a single rubric line so the
reviewer can request changes citing the violated principle. AGENTS.md
gains a `## Doctrine` section pointing at PRINCIPLES.md. Mechanics
unchanged — every principle is summary of existing behavior, not new
behavior. Ticket 0018.

## 2026-05-26 — initial entry

Bootstrap entry. No behavioral changes since the kit's bootstrap — this
file is born at prompts SHA `2633dbfc560139067e606dbbd0d86f6e4561c7c5a8f27d914494bc483109250a`
(captured via `bin/fleet prompts-sha` BEFORE this CHANGELOG was added; the
SHA after addition will differ because the CHANGELOG is part of the
`find prompts -type f -name '*.md'` glob that feeds the hash). Operators
who pinned a SHA prior to this entry should re-run `install.sh` to bump
their pin once they've reviewed the new file.
