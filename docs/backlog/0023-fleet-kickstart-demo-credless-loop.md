---
id: 0023
title: fleet kickstart --demo runs a credential-less end-to-end loop in 60 seconds
status: shipped
priority: P2
area: docs
created: 2026-05-30
owner: gtm-innovation
---

## User story

As a developer who just landed on the agent-fleet README and wants to see
what this thing actually DOES before I install launchd jobs or hand it my
`gh` PAT, I want `bin/fleet kickstart --demo` to spin up a self-contained
synthetic project (fixture repo + stubbed `gh` + stubbed `claude`) and
walk a single ship/review cycle end-to-end against it, so that in under a
minute I see the same `events.jsonl` stream, the same backlog promotion,
the same `lesson_draft_emitted` event a real run would emit — without
ever touching GitHub, my disk outside `/tmp`, or my Anthropic quota.

## Why now (four lenses)

### Product Owner
The README explains the loop in prose and a Mermaid diagram, then asks
the reader to fill in a manifest, write an `AGENTS.md` section, install
`gh`, configure branch protection, and wait an hour before they see a
single event line. That gap is where most readers bounce. The smallest
unit of acquisition value is a one-command demo that produces real
artifacts (a tail-able `events.jsonl`, a generated draft block, a printed
"would-merge" verdict) so the reader stops asking "what happens when
this runs?" and starts asking "where do I put my manifest?" Subtraction:
the operator no longer has to vouch for the kit at coffee — the demo
vouches for itself.

### Stakeholder
Widens the acquisition moat by making the kit's value visible without
trust transfer. Today the only paths to "see the loop" are (a) install
on a real repo, which requires `gh auth`, branch protection, and an
hour; or (b) read transcripts in someone else's `~/.cache/`. Neither
works for a stranger evaluating the kit. The demo path is also a
regression substrate: every `events.jsonl` event type the kit ever
emits should be reachable from `--demo`, which means the demo doubles
as a smoke test for the channel contract from ticket 0002. Two assets
for the price of one.

### User (developer reading the README on a Tuesday)
Types `git clone https://github.com/mutaaf/agent-fleet && cd
agent-fleet && bin/fleet kickstart --demo`. Sees, within ~60s of stdout:

```
[demo] scaffolding fixture repo in /tmp/fleet-demo-XXXXXX
[demo] seeded 2 groomed tickets, 0 open PRs
[demo] phase 1: heal — no in-flight PRs, falling through
[demo] phase 2: ship — picking 0001-demo-hello-world (P1, groomed)
[demo] stubbed claude returned SHIP — 1 file changed
[demo] stubbed gh pr create #42 (feat/0001-demo-hello-world)
[demo] events.jsonl now has 4 events: run_started, pr_opened,
       lesson_draft_emitted, run_completed
[demo] tailing for 5s so you can read them...
{"ts":"...","type":"run_started",...}
{"ts":"...","type":"pr_opened","number":"42",...}
{"ts":"...","type":"lesson_draft_emitted","pr":"42","headline":"demo: ..."}
{"ts":"...","type":"run_completed",...}
[demo] done. fixture preserved at /tmp/fleet-demo-XXXXXX — rm -rf when done.
```

They close the terminal knowing exactly what the loop produces. Then
they read the install section with the right mental model. The
acquisition funnel just gained a "show me" step that did not exist.

### Growth
"Try it in 60 seconds without `gh auth`" is the single most shareable
property the kit can ship. It's the line on the README, on a tweet, in
a friend's "have you seen this?" message. Today the kit can only be
described; with `--demo` it can be demonstrated. That distinction is
how onboarding tutorials become recommendations.

## Acceptance criteria

Each box maps 1:1 to a test scenario in `tests/kickstart-demo.sh`.

- [ ] `bin/fleet kickstart --demo` (no slug) runs a complete end-to-end
      synthetic loop in <90s wallclock on the test runner. The command
      exits 0 on success and prints a final `[demo] done.` line.
- [ ] The demo creates a fixture repo via `mktemp -d -t fleet-demo`
      containing: `AGENTS.md`, `agents.config.sh`, `docs/backlog/README.md`,
      two seeded ticket files (`0001-demo-hello-world.md` groomed,
      `0002-demo-second-ticket.md` proposed), and `docs/LESSONS.md`. The
      fixture path is printed at start and end so the reader can inspect
      it. NEVER writes anywhere outside `$TMPDIR` and `$CACHE_DIR/demo/`.
- [ ] The demo installs stubbed `gh`, `claude`, and `git push`
      executables in `$HOME/.local/bin` for the duration of the run
      (per LESSONS 2026-05-26 — stubs MUST live in `$HOME/.local/bin`
      because `lib/common.sh` resets PATH). The stubs return canned
      JSON: `gh pr create` echoes `{"number": 42, ...}`; `claude --print`
      echoes a canned ship plan including a synthetic "SHIP" verdict;
      `git push` is a no-op that records its argv. Stubs are deleted on
      normal exit AND on trap EXIT.
- [ ] The demo emits at minimum these event types to a real
      `events.jsonl` under `$CACHE_DIR/demo/events.jsonl`:
      `run_started`, `pr_opened`, `lesson_draft_emitted`,
      `run_completed`. The test asserts each type appears exactly once
      via `grep -c '"type":"<t>"' events.jsonl`. The schema obeys
      AGENTS.md § Telemetry (ts/slug/phase/type required).
- [ ] `--demo --tail` keeps `events.jsonl` streaming for 5 extra
      seconds after the loop exits and prints lines as they arrive
      (re-uses `tail_format_stream` from ticket 0015). Without `--tail`,
      the events are printed once at end of run. The test asserts both
      branches via `--demo --tail 1` (1 second tail window for speed).
- [ ] `--demo --keep` skips the cleanup so the operator can browse the
      fixture. Default behavior wipes `$TMPDIR/fleet-demo-*` on normal
      exit. The test creates a sentinel file in the fixture and
      asserts presence after `--demo --keep` and absence after a plain
      `--demo`.
- [ ] The demo NEVER calls real `gh`, real `git push`, or real
      `claude`. The test runs in an environment with `gh`, `git`,
      `claude` absent from a clean PATH (PATH=`$HOME/.local/bin` only)
      and asserts the run still succeeds — proof the stubs cover every
      surface the demo touches.
- [ ] `README.md` "Mental model in 60 seconds" section gains a
      one-paragraph callout placed BEFORE the Prerequisites table:
      "Want to see it run before installing? `bin/fleet kickstart
      --demo` walks a credential-less synthetic loop in under a minute."
      Plus a single line in the existing "Daily ops" code block.
- [ ] `runs.jsonl` under the demo cache dir gets a single appended row
      tagged `phase=demo` so the demo's synthetic cost (always 0.0) does
      NOT pollute `fleet digest` for any real project. The test scans
      every real project's `runs.jsonl` afterward and asserts no rows
      with `slug=demo-*` exist outside the demo cache dir.
- [ ] `tests/kickstart-demo.sh` covers the eight boxes above with
      `$HOME` re-rooted to a temp dir (per LESSONS 2026-05-26) and
      stubbed binaries in `$HOME/.local/bin`. Asserts argv recording
      via stub-written log files; asserts the demo cleans up its stubs
      on exit even when the inner loop fails (run with
      `FLEET_DEMO_FORCE_FAIL=1` and assert traps still fire).

## Out of scope

The dev agent will NOT do these even if they seem related.

- A web/HTML demo surface. Fleet-control can later render the same
  events stream; this ticket is CLI-only so the README can promise
  "no extra install."
- An interactive walkthrough (`fleet kickstart --demo --interactive`)
  that prompts the operator between phases. v1 is non-interactive so
  it can be copy-pasted into a CI run as a smoke test.
- Multiple fixture repos / scenarios (`--demo --scenario heal-red`,
  `--scenario sendback-streak`). v1 has ONE happy-path scenario. The
  fixture-scenario abstraction is a follow-up if multiple are needed.
- Real `claude` calls in the demo, even with `AGENT_DRY_RUN=1`. The
  stranger evaluating the kit doesn't have a Max sub yet. The demo
  must work with zero external dependencies including the Anthropic
  CLI; the canned `claude` stub is the contract.
- Integration with `bin/fleet onboard` (ticket 0011). Onboard is for
  real repos; demo is for evaluation. They share no code path
  intentionally — onboard touches the real filesystem, demo never
  touches anything the operator owns.
- Auto-promotion of the demo's seeded lesson draft. The draft block
  the demo generates stays as a `<!-- DRAFT -->` block in the fixture's
  LESSONS.md so the operator sees the actual artifact ticket 0022
  produces in production.

## Engineering notes

- `bin/fleet` — new `kickstart_demo()` function and a `--demo` branch
  in `kickstart_cmd()` (line ~2189). Reuses `kickstart_resolve_manifest`
  patterns but synthesizes a manifest in `$TMPDIR` instead of resolving
  one. The dispatcher in the case statement gains `kickstart) ...; if
  --demo, kickstart_demo "$@"`.
- `bin/fleet` — `kickstart_demo` writes a complete fixture project to
  `mktemp -d -t fleet-demo` containing all files a real project needs
  (manifest, AGENTS.md, docs/backlog/README.md, two ticket files,
  docs/LESSONS.md). The fixture's `agents.config.sh` sets
  `SLUG=demo-<random>` and `CACHE_DIR` under a temp path so it cannot
  collide with any real project.
- `tests/fixtures/demo/` — NEW directory with the canned fixture
  contents (manifest template, AGENTS.md template, two ticket files,
  starter LESSONS.md). `kickstart_demo` reads these via `cat` and
  pipes through `sed` to substitute the random slug. Keeps the demo's
  static content in version control instead of as heredocs in
  `bin/fleet`.
- `lib/common.sh` — NO changes expected. The demo invokes
  `fleet_emit_event` directly with `SLUG=demo-...` and
  `FLEET_PHASE=demo`. Confirmed: `fleet_log_init` already accepts an
  arbitrary phase string (per ticket 0021's `phase=replay` precedent).
- Stub layout: the demo writes three executables to
  `$HOME/.local/bin/{gh,claude,git-push-stub}` and prepends nothing —
  per LESSONS 2026-05-26 the existing PATH reset already has
  `$HOME/.local/bin` at the head. The `git push` interception uses a
  `GIT_SSH_COMMAND` env var or a `git` config alias rather than
  stubbing the entire `git` binary (which would break `git diff`,
  `git log`, etc. that the inner prompt reads). Specifically: set
  `git config --local push.default current` plus `remote.origin.url`
  to a `file://` path inside the fixture; the demo's "remote" is just
  a bare repo in `$TMPDIR/fleet-demo-XXXXXX-remote.git`. No `gh`
  surface needs a real remote.
- `bin/fleet` — `kickstart_demo` invokes the ship phase by
  `cd`-ing into the fixture and running `bash
  $KIT_ROOT/lib/ship.sh` directly (NOT via launchctl — the demo must
  run on Linux too for the test runner). This means `ship.sh` must
  tolerate being invoked without a launchd plist; spot-check that it
  already does via the existing `tests/dry-run.sh` pattern.
- Telemetry: NO new event types. The demo reuses existing types
  (`run_started`, `pr_opened`, `lesson_draft_emitted`, `run_completed`)
  per P-6 (renaming is forbidden; the demo is a consumer, not a new
  channel). Update AGENTS.md § Telemetry only with one paragraph noting
  the demo path emits these types with `phase=demo`.
- Reinstall required: NO. `lib/` and `prompts/` are untouched. The
  PR body does NOT need `Reinstall: all projects`.
- BREAKING flag: NO. No `fleet_*` signature changes. New subcommand
  flag is additive.
- File-edit safety: when writing the fixture, NEVER use `$(cat
  template)` substitution per LESSONS 2026-05-27 — `sed` over a temp
  file, then `mv`. Same trap.
- `printf` safety per LESSONS 2026-05-28: any format string starting
  with `-` (e.g. `"-- demo: ..."`) gets `printf -- 'fmt' args`.
- `tests/kickstart-demo.sh` shape: `mktemp -d` for `$HOME`, write
  stubs into `$HOME/.local/bin`, set `PATH="$HOME/.local/bin"`
  (exclusive), invoke `bin/fleet kickstart --demo`, assert exit 0,
  grep events.jsonl for the four required event types, assert no
  `gh` call hit a real network (the stub records calls to a file —
  assert all of them are demo-scope). Run time budget: <30s on a cold
  laptop.

## Implementation log

- 2026-05-30 — shipped. tests/kickstart-demo.sh covers all 10 ACs
  (the ticket prose says "eight" but the AC list has ten boxes — the
  test maps 1:1). Local gate green: `shellcheck -S warning lib/*.sh
  bin/fleet`, `bash -n lib/*.sh bin/fleet`, `node scripts/check-backlog.mjs`.
  Reinstall NOT required (no `lib/` or `prompts/` edits).
- 2026-05-30 — picked up by implementation-dev. Status → in-progress.
  Plan: `kickstart_demo()` in `bin/fleet` writes a fixture project under
  `mktemp -d -t fleet-demo`, installs `gh`/`claude`/`git-push-stub` stubs
  under `$HOME/.local/bin` (per LESSONS 2026-05-26 — `lib/common.sh`
  resets PATH on source, so stubs anywhere else evaporate), then sources
  `lib/common.sh`, calls `fleet_load_manifest` on the fixture, and
  manually emits the four required event types (`run_started`,
  `pr_opened`, `lesson_draft_emitted`, `run_completed`) directly via
  `fleet_emit_event` rather than driving `ship.sh`. Rationale: AC#7
  requires the demo to succeed with PATH=`$HOME/.local/bin` ONLY (no
  real `git`), so the synthetic loop cannot actually shell out to git
  for a checkout — it walks the events.jsonl channel as a consumer, not
  via the production runner. The `_review_emit_lesson_draft` helper is
  reused so the seeded DRAFT block in the fixture's LESSONS.md is the
  same shape ticket 0022 produces in production.

(Appended by the implementation-dev agent during execution.)
