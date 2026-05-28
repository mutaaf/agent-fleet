---
id: 0020
title: Heal phase detects infra-flake CI failures and reruns instead of code-fixing
status: groomed
priority: P1
area: safety
created: 2026-05-28
owner: gtm-innovation
---

## User story

As a fleet operator who has watched the heal step waste two attempts and
~$1.50 trying to "fix" a GitHub Actions outage, a Supabase port collision,
or a transient GitHub account suspension, I want the heal phase to
recognize known infra-only failure patterns in the failed job log, run
`gh run rerun <run-id> --failed` once, emit an `infra_flake_rerun`
event, and exit cleanly without spending a heal attempt, so that
transient infra failures stop draining my heal budget and my tokens.

## Why now (four lenses)

### Product Owner
The heal loop's current contract is "red gating check → run the local
gate, fix the root cause, commit `heal:`, push." That contract assumes
every red CI failure is fixable with a code change. CROSS_LESSONS
documents at least four recurring patterns where it is not:

- GitHub Actions silently stops firing for a PR (agent-fleet LESSON
  2026-05-26).
- `supabase start` fails with `failed to bind host port for 0.0.0.0:54322
  ... address already in use` on a docs-only PR (courtiq LESSON 2026-05-25,
  ticket 0029).
- `actions/checkout@v4` 403s with `Your account is suspended` and the
  suspension self-clears within minutes (courtiq LESSON, PR #314).
- `gh pr checks --watch` aborts on a transient GraphQL 502 (courtiq
  LESSON 2026-05-21, ticket 0012).

For each, the right action is `gh run rerun --failed` (or a no-op heal
commit to re-trigger), not a code edit. Today the heal step burns
attempt 1 on a fabricated "fix", attempt 2 on another fabricated fix,
then escalates — three runs and a real claude bill for a problem that
clears itself. Smallest unit of value: a regex catalog plus one
`gh run rerun` call, gated by the catalog.

### Stakeholder
Widens the moat on `safety` and on cost discipline. The kit's claim is
"the loop self-pauses when it's broken"; today it self-burns on
infra-only failures because the heal step has no way to distinguish
"my code is wrong" from "GitHub coughed." The lessons file already
catalogs the patterns — codifying them in `lib/` is the first time
the lessons become enforced behavior rather than human-only memory.
This is exactly the kind of "the kit absorbs lessons" property that
makes the moat compound.

### User (operator at 9am looking at last night's logs)
Today they see three ship runs on the same PR, three `heal:` commits
that didn't help, and an escalation comment. They have to read the
CI log to discover it was a Supabase port bind. After this ticket
they see one ship run, one `infra_flake_rerun` event in `fleet tail`,
and a re-armed auto-merge — no fabricated heal commits cluttering the
PR's history, no wasted budget. The "stuck PR" feeling goes away for
the infra-flake class.

### Growth
Catalog-based infra-flake detection is the kind of thing every
autonomous-agent kit eventually needs and almost none ship. Naming
the catalog publicly (the regexes live in `lib/heal-catalog.sh`,
visible in `bin/fleet overview` or a `fleet heal-catalog` subcommand
later) makes the moat legible: "here are the failure modes my fleet
already knows about." A friend running their own loop can copy the
catalog directly.

## Acceptance criteria

Each box maps 1:1 to a test scenario in `tests/heal-infra-flake.sh`.

- [ ] A new shell function `fleet_match_infra_flake <log-file>` (in
      `lib/common.sh`) reads a CI log file and prints one of:
      `actions_silent` | `supabase_port_bind` | `account_suspended` |
      `gh_graphql_502` | (empty string if no match). Patterns are
      regexes pinned in `lib/heal-catalog.sh` — a separate file so
      adding a new pattern is one line plus a fixture, not a code
      change in common.sh.
- [ ] `lib/heal-catalog.sh` ships with the four patterns above. Each
      pattern has an inline comment naming the LESSONS entry it
      codifies (date + repo).
- [ ] `tests/heal-infra-flake.sh` provides four fixture log files (one
      per pattern), asserts each maps to its expected token via
      `fleet_match_infra_flake`, and asserts an unrelated red log
      (e.g. a real shellcheck failure) returns empty.
- [ ] When the heal step (in `prompts/ship.prompt.md` Phase 1 — RED
      branch) encounters a red gating check, BEFORE running the local
      gate and writing a `heal:` commit it: (a) downloads the failed
      job log via `gh run view <run-id> --log-failed`, (b) passes the
      log to `fleet_match_infra_flake`, (c) if a token is returned,
      runs `gh run rerun <run-id> --failed` exactly once, emits
      `fleet_emit_event infra_flake_rerun pattern=<token> run_id=<id>
      pr=<N>`, prints `INFRA_FLAKE <token> — rerunning run <id>` to
      stdout, and EXITS the ship run with status 0. No heal commit
      is created; the heal attempt counter is NOT incremented. The
      prompt change is asserted by grepping `prompts/ship.prompt.md`
      for the string `fleet_match_infra_flake` and for `gh run rerun`.
- [ ] If the same infra-flake token has already been rerun on the
      same `run_id` within the last 2h (looked up by scanning
      `events.jsonl` for `infra_flake_rerun pattern=<token>
      run_id=<id>`), the step does NOT rerun again — it falls through
      to the normal heal path. This prevents rerun loops on a
      genuinely-broken infra. Test asserts the second invocation
      hits the normal heal path.
- [ ] AGENTS.md § Telemetry gains an `infra_flake_rerun` event-type
      entry under the existing bullet list (same format as
      `rollback_opened` and `events_rotated`).
- [ ] `tests/heal-infra-flake.sh` covers the four positive matches,
      the negative case (real failure → empty match → normal heal),
      and the dedupe case (second match within 2h → no rerun).
- [ ] `lib/common.sh` public API unchanged: the new function is
      additive and named with the `fleet_` prefix. No existing
      function signature moves.

## Out of scope

- Auto-detecting NEW infra flakes (machine-learning a catalog). The
  catalog is hand-curated from LESSONS entries; growth happens via
  a follow-up ticket that scrapes new patterns.
- A `fleet heal-catalog` subcommand to list the patterns. v1 ships
  the catalog file; an inspection subcommand is a separate ticket
  if anyone asks.
- Reruns for non-gating checks. Only checks named in AGENTS.md §
  Agent parameters `Gating checks` are considered.
- Cross-PR aggregation (e.g. "GitHub Actions is down for the whole
  fleet, pause all ship runs"). That is the right next step but
  belongs in a separate ticket; this one is per-PR.
- Touching `prompts/PRINCIPLES.md`. The principle is unchanged
  (P-3: heal in-flight before new work); only the mechanic for
  Phase 1 RED gains a pre-step.

## Engineering notes

- `lib/heal-catalog.sh` — new file, sourced by `lib/common.sh`.
  Pinned regexes in shell arrays so the catalog is grep-friendly.
- `lib/common.sh` — adds `fleet_match_infra_flake` (after
  `fleet_emit_event`). Adds one constant
  `FLEET_HEAL_CATALOG="${FLEET_HEAL_CATALOG:-$_dir/heal-catalog.sh}"`
  so tests can point it at a fixture catalog without monkey-patching
  the installed copy.
- `prompts/ship.prompt.md` — Phase 1 RED branch gains the pre-step
  described in AC#4. Add a `## YYYY-MM-DD` entry to
  `prompts/CHANGELOG.md` describing the change so `check-prompts-changelog.mjs`
  (ticket 0013) stays green.
- AGENTS.md § Telemetry — append the `infra_flake_rerun` event-type
  bullet to the existing list.
- New deps: none. Uses existing `gh`, `grep`, `awk`.
- `tests/heal-infra-flake.sh` — `mktemp -d` fixtures, stubbed `gh`
  recording argv (assert `gh run rerun --failed` ran exactly once),
  seeded `events.jsonl` for the dedupe case. Reuses the
  `$HOME/.local/bin` stub pattern from `tests/dry-run.sh` (per
  LESSONS 2026-05-26: stubs must live in the reset PATH's first dir).
- Reinstall required: YES — touches `lib/common.sh` and
  `lib/heal-catalog.sh` and `prompts/ship.prompt.md`. PR body must
  include `Reinstall: all projects` per LESSONS 2026-05-25.
- Public API: additive (`fleet_match_infra_flake`,
  `infra_flake_rerun` event-type). No existing `fleet_*` signature
  changes. Do NOT mark `BREAKING:`.

## Implementation log

(Appended by the implementation-dev agent during execution.)
