---
id: 0030
title: fleet resume <slug> unpauses a ship-paused project with one confirmed command
status: shipped
priority: P1
area: safety
created: 2026-06-03
owner: gtm-innovation
---

## User story

As a fleet operator who opened `fleet inbox` and saw `paused projects
2 — courtiq paused 3d ago — launchctl enable
gui/$UID/com.courtiq.agent-ship` and DOES NOT want to memorize the
launchctl incantation (and definitely does not want to paste a literal
`$UID` accidentally), I want
`bin/fleet resume <slug> [--reason "<one-line>"] [--force]` to
re-enable the paused ship label safely, verify the launchd state
flipped, append a one-line resume marker to the project's events
channel, and refuse without `--force` when the underlying cause
(send-back streak in the last 24h) hasn't actually cleared — so that
recovering from `ship_paused` is one command on the same surface that
told me about the pause, instead of three commands across two
manuals.

## Why now (four lenses)

### Product Owner
Ticket 0006 shipped the auto-pause. Ticket 0026 shipped the inbox
that surfaces the pause. The recovery, however, is still the
launchctl incantation the inbox prints as a "hint." That's the kit's
last operator-cliff: the loop self-pauses gracefully but unpauses
manually. The smallest meaningful unit of value is the inverse of
`fleet_check_sendback_streak` (lib/common.sh line ~330): one
command, one verification ("did the streak clear?"), one launchctl
call, one event. Subtraction: the operator stops having to remember
the launchctl syntax — `fleet resume courtiq` IS the recovery. The
`--force` gate exists because the pause is BY DESIGN — the operator
should know they're overriding the safety, not stumble into it.

### Stakeholder
The kit's safety story (`ship_paused`, `budget_block`, `trainee_pr_
opened`, `infra_flake_rerun`) is rich on the PAUSE side and bare on
the RESUME side. This asymmetry is felt: every safety event has a
launchctl-flavored recovery that operators have to look up. Closing
this asymmetry for ship_paused first is the right precedent — it
sets the shape future "auto-pause + manual resume" pairs follow.
Each resume also EMITS a typed event (`ship_resumed`), which means
fleet-control and `fleet weekly` (0025) can render a pause-streak
duration like a real safety metric instead of inferring it from the
launchctl print state at scrape time. This is the smallest possible
moat-deepening artifact: it turns a manual recovery into a logged
recovery, and logged recoveries compound the audit trail (which is
what provenance — see ticket 0029 — reads from).

### User (operator at 9am, courtiq paused yesterday after a flaky
test cascade; the test was fixed by a human merge to main last
evening)
Runs `bin/fleet resume courtiq`. Sees:

```
fleet resume: checking pause cause for courtiq …
  last 24h send-backs: 0 (cleared from 3 at pause time 2026-06-02T07:14Z)
  agent-ship label state: disabled
proceeding (--force not required).
launchctl enable gui/501/com.courtiq.agent-ship — OK
verified: agent-ship label state now: enabled
emitted ship_resumed source=courtiq paused_for=23h reason="streak cleared"
fleet resume: courtiq will pick up its next ship cycle at the next launchd interval.
```

Next inbox run shows courtiq removed from the "paused projects"
section. The operator never typed a `$UID`, never had to remember
`gui/`. If the send-back streak HAD NOT cleared:

```
fleet resume: REFUSING — courtiq still has 4 send-backs in the last 24h
  (the same condition that triggered ship_paused).
  Diagnose with: gh pr list --repo mutaaf/courtiq --search 'review:changes-requested'
  Override (only after manual triage): fleet resume courtiq --force --reason "…"
```

Operator gets the safety blocked behind a deliberate, traceable
override.

### Growth
The kit is a story about "the loop pauses when broken and resumes
when fixed." The PAUSE half is already concrete (`ship_paused` event,
inbox row, GitHub Issue). The RESUME half today is a launchctl
incantation. Closing that gap turns the story into a one-paragraph
demo: "show me how recovery works — `fleet resume courtiq`." Friends
running their own loop pick this up immediately because it solves a
problem they will ALL have on day 30. It is also the natural
launchpoint for fleet-control's "Resume" button to land safely:
the button shells out to `fleet resume <slug>` and inherits the
safety gate for free.

## Acceptance criteria

Each box maps 1:1 to a test scenario in `tests/resume.sh`.

- [ ] `bin/fleet resume <slug>` (no flags) on a project whose
      `agent-ship` label IS disabled AND whose `events.jsonl`
      shows zero `lesson_draft_emitted` events in the last 24h
      (the send-back streak proxy used by
      `fleet_check_sendback_streak`, lib/common.sh line ~330)
      runs `launchctl enable gui/$UID/<namespace>.agent-ship`,
      verifies the label state flipped via `launchctl print`,
      emits one `ship_resumed` event, and exits 0. Prints the
      block above to stdout. Test stubs `launchctl` under
      `$HOME/.local/bin` per LESSONS 2026-05-26 to record the
      enable call AND simulate the print-state flip.
- [ ] On a project whose `agent-ship` label is ALREADY enabled
      (not actually paused), the command prints `fleet resume:
      <slug> is not paused (agent-ship label state: enabled) —
      nothing to do.` and exits 0. Does NOT call `launchctl
      enable`. Does NOT emit a `ship_resumed` event. Idempotent
      no-op.
- [ ] On a project whose `agent-ship` is disabled but whose
      `lesson_draft_emitted` count in the last 24h is >= 3 (the
      pause-trigger threshold from ticket 0006), the command
      refuses: prints the REFUSING block to stderr, exits 2,
      does NOT call `launchctl enable`, does NOT emit a
      `ship_resumed` event. Test asserts the refusal branch.
- [ ] `--force` (with or without `--reason`) bypasses the
      streak check and proceeds with the enable. The
      `ship_resumed` event carries `forced=1` and
      `reason="<--reason value or 'forced by operator'>"`. Test
      asserts the forced path AND the event payload.
- [ ] `--reason "<one-line>"` is mandatory when `--force` is
      present (per safety: forced overrides must be auditable).
      `--force` without `--reason` prints `fleet resume:
      --force requires --reason "<one-line>" (auditable
      override)` to stderr, exit 2. Test asserts the missing-
      reason branch.
- [ ] `--reason` value with leading `-` is accepted (operators
      might paste `--reason "-streak was a false positive"`).
      Per LESSONS 2026-05-28 (printf leading-dash trap), the
      command parses `--reason` via `case $1 in --reason)
      shift; reason="$1"; shift ;; --reason=*)
      reason="${1#--reason=}"; shift ;;` and ALL downstream
      `printf` calls use `printf -- '%s' "$reason"`. Test
      asserts a leading-dash reason renders correctly in the
      output AND in the emitted event payload.
- [ ] `ship_resumed` event payload: `{source: <slug>,
      paused_for: <duration>, reason: <string>, forced: 0|1}`.
      `paused_for` is human-formatted ("23h", "3d", etc. —
      reuses `human_age` from bin/fleet line ~60) computed from
      the most recent `ship_paused` event's ts. If no
      `ship_paused` event exists (operator force-paused
      out-of-band), `paused_for` is `unknown`. Event lands in
      the SOURCE project's `$CACHE_DIR/events.jsonl` (NOT a
      global one — project is the unit of telemetry per P-6).
      Event carries `phase=resume`. AGENTS.md § Telemetry gets
      one new entry per the kit's convention.
- [ ] `AGENTS.md § Telemetry` is updated in the same PR with a
      new bullet for `ship_resumed {source, paused_for, reason,
      forced}` following the existing entry style (verbatim
      shape: see ticket 0028's `lesson_promoted` paragraph and
      0017's `rollback_opened` paragraph). Reviewer's telemetry-
      contract check requires this to land in the same diff.
- [ ] Unknown slug: `resume: no project with SLUG=<slug> found
      (looked under FLEET_DISCOVERY_ROOT=<path>)` to stderr,
      exit 2. Test asserts the exact error.
- [ ] launchctl verify-failure (the enable call returned 0 but
      `launchctl print` still reads disabled — rare, but
      possible if the user's launchd session has a stale state):
      the command prints `fleet resume: launchctl enable
      returned 0 but agent-ship label is still disabled —
      diagnose with launchctl print gui/$UID/<ns>.agent-ship`
      to stderr, exit 1. Does NOT emit `ship_resumed`. Test
      stubs `launchctl print` to return the bad state to
      exercise this branch.
- [ ] Help: `bin/fleet resume --help` prints a USAGE block
      mentioning `--force`, `--reason`, `--help`. Test asserts
      via `grep -qF -- "$kw" "$help_out"` per LESSONS
      2026-05-30. Help block ends with `exit 0` per LESSONS
      2026-06-01 (dispatcher fall-through trap).
- [ ] `tests/resume.sh` covers all 11 boxes using
      `$HOME/.local/bin` stubs (per LESSONS 2026-05-26) for
      `launchctl`. `FLEET_DISCOVERY_ROOT` redirected to
      `tests/fixtures/resume/`. The stub records every
      invocation to a temp file the test asserts against.
      Per LESSONS 2026-05-27, the test uses `cp` for
      backup/restore — never `$(cat …)`. Run-time budget:
      <10s.

## Out of scope

The dev agent will NOT do these even if they seem related.

- Resuming `budget_block` (i.e. bumping `MAX_DAILY_USD`). Budget
  recovery is "wait for tomorrow" (the cap is daily) or "edit
  the manifest" — both already trivial and neither has a
  symmetrical pause-event-to-resume-event shape. Future ticket
  if needed.
- Resuming a `--force`-paused project via fleet-control. The
  CLI is the contract; the portal can shell out later. Same
  shape as `fleet rollback` / `fleet kickstart` precedents.
- Auto-resuming on a launchd schedule. Auto-resume defeats the
  safety — the whole point is the operator makes the call.
- A `fleet pause` companion command. The kit pauses via the
  auto-pause path; the operator can disable a label by hand if
  they want a manual pause. Adding a symmetrical command would
  imply "pause as a feature" which contradicts the design.
- Editing the GitHub Issue the pause opened (ticket 0006). The
  Issue is the human-readable comm channel; resume does not
  close it because the operator's triage may want to keep it
  open as context. Future ticket if a "close on resume" knob
  is needed.
- A `--dry-run` flag. The command's behavior is one launchctl
  call + one event emission; --dry-run would not meaningfully
  change anything an operator could verify cheaper by reading
  the help block. Sibling commands `rollback` and `kickstart`
  similarly do not ship --dry-run on a single-action surface.
- Triggering an immediate ship cycle after resume. The launchd
  schedule fires the next interval (`:37` per AGENTS.md "How
  the loop runs"); forcing a cycle would invent a parallel
  schedule the kit does not support.

## Engineering notes

Files / patterns the dev should touch. Specific enough that the
dev doesn't have to re-discover the architecture.

- `bin/fleet` — new `resume()` dispatcher next to `rollback()`
  (line ~3564) and `kickstart_cmd()` (line ~4112). Shape mirrors
  `rollback()`: same `*_resolve_manifest` pattern (line ~3022
  for rollback's helper) — extract a new
  `resume_resolve_manifest()` that wraps the same union.
- `bin/fleet` — three helpers:
  - `resume_label_state()` — wraps `launchctl print
    gui/$UID/<ns>.agent-ship 2>/dev/null | awk '/state =/
    {print $3; exit}'`; echoes `enabled` / `disabled` / empty.
  - `resume_sendback_count_24h()` — counts
    `lesson_draft_emitted` events with `ts` in the last 24h on
    the slug's `events.jsonl`. Reuses the awk pattern from
    `inbox_budget_block_today` (line ~2246) — JSON scan
    without jq.
  - `resume_paused_for()` — reads the slug's `events.jsonl`
    for the most recent `ship_paused` ts and runs `human_age`
    against `(now - ts)`. Falls back to `unknown` when no
    event found.
- `bin/fleet` — `resume()` end-state must be `exit 0` (or
  `exit 2`/`exit 1` per AC) on every code path per LESSONS
  2026-06-01 (dispatcher fall-through trap). Copy the exit-0
  pattern from `kickstart_cmd()` (line ~4112) verbatim.
- `bin/fleet` — dispatcher block at the bottom of the file:
  `if [ "$CMD" = "resume" ]; then resume "$@"; fi`. Placed
  after the existing `lessons-promote` block (line ~5920).
- `bin/fleet` — help banner block at the top of the file
  (around line ~14) gets a new line: `fleet resume <slug>
  re-enable a ship_paused project (safety-checked)`. README
  "Daily ops" code block gets the same.
- `lib/common.sh` — NO changes. `resume` is a pure caller of
  the existing `fleet_emit_event` helper (line ~975) — no new
  helper functions in common.sh. NO `fleet_*` signature
  changes. The emit path sources `lib/common.sh` the same way
  `bin/fleet` already does at the top of the file (line ~109
  area — see how `kickstart_demo` resolves it at line ~3923).
- `AGENTS.md § Telemetry` — append a new bullet for
  `ship_resumed {source, paused_for, reason, forced}` —
  emitted by `bin/fleet resume` once per successful resume.
  Carries `phase=resume`. Payload: `source` = slug;
  `paused_for` = human age ("23h" / "3d" / "unknown");
  `reason` = the `--reason` value or "streak cleared" on the
  default path; `forced` = `0` on the default path, `1` on
  `--force`. Mirrors the shape of `lesson_promoted` (0028)
  and `rollback_opened` (0017).
- `prompts/` — NO changes. The command is operator-facing
  only; no agent prompt reads `fleet resume`. No `Reinstall:
  all projects` line is needed because `lib/` and `prompts/`
  are untouched.
- `tests/fixtures/resume/` — NEW directory under
  `tests/fixtures/` holding:
  - one synthetic `<slug>/agents.config.sh` with `SLUG=`
    and `NAMESPACE=` set
  - one synthetic `events.jsonl` with a `ship_paused` event
    23h ago and zero `lesson_draft_emitted` events in the
    last 24h (for the happy path)
  - one variant `events.jsonl` with 3 `lesson_draft_emitted`
    events in the last 24h (for the refusal branch)
- `tests/resume.sh` — top of file mirrors `tests/rollback.sh`:
  redirect `FLEET_DISCOVERY_ROOT`, stub `launchctl` under
  `$HOME/.local/bin` (`$HOME=$TMP/home` per LESSONS
  2026-05-26) — the stub appends every invocation to
  `$TMP/launchctl.log` and reads a `$TMP/launchctl-state` file
  for `print` calls so the test can simulate the state flip.
  The `ship_resumed` event assertion reads the source
  project's `events.jsonl` and parses the last line via
  `node -e 'JSON.parse(...)'`.
- New deps: none. Pure shell + awk + existing
  `fleet_emit_event` helper (lib/common.sh ~975), `human_age`
  helper (bin/fleet ~60), `_json_escape` (common.sh ~849)
  used indirectly via `fleet_emit_event`.
- Public API: additive — `bin/fleet resume` is a new
  subcommand. ONE new event type added (`ship_resumed`) —
  consumers MUST tolerate unknown types per the existing
  AGENTS.md § Telemetry contract, so this is additive, not
  breaking.
- BREAKING flag: NO. PR body affirms "no `fleet_*` signature
  changes" and explicitly names the new event type so the
  reviewer's telemetry-contract check passes.
- Reinstall required: NO. `lib/` and `prompts/` are
  untouched.
- LESSONS to defend against: 2026-05-26 (`tail` shadow —
  `resume` is not a coreutils binary on macOS or Ubuntu;
  confirmed via `command -v resume` returning nothing).
  LESSONS 2026-05-27 ($(cat) trap — every fixture read uses
  `cp`/awk). LESSONS 2026-05-28 (printf leading-dash trap —
  the `--reason` value can start with `-`; ALL output uses
  `printf -- '%s' "$reason"`). LESSONS 2026-05-30 (`grep -F
  --` flag trap — the help-text assertion uses `grep -qF
  --`). LESSONS 2026-06-01 (`grep -c file || echo 0` double-
  printing — the send-back counter uses awk, never `grep -c
  || echo 0`). LESSONS 2026-06-01 (dispatcher fall-through —
  `resume()` ends with explicit `exit 0` on every path,
  including the help block).
- This ticket compounds 0006 (`ship_paused` event +
  `fleet_check_sendback_streak`), 0017 (`rollback_opened`
  event shape as the precedent for a new operator-emitted
  event), 0022 (`lesson_draft_emitted` events as the
  send-back streak signal), 0026 (`fleet inbox` "paused
  projects" hint that this command answers). It introduces
  ONE new event type and ZERO `lib/` or `prompts/` changes.
  Per P-1 the diff is small: ~200 lines of `resume*` helpers
  + ~80 lines of test fixture content + one AGENTS.md
  paragraph + one help-text line.

## Implementation log

- 2026-06-03 — implementation-dev: started; branch
  `feat/0030-fleet-resume-paused-slug`. Tests-first; `tests/resume.sh`
  covers all 11 AC boxes with `launchctl` stubbed under
  `$HOME/.local/bin` per LESSONS 2026-05-26. `resume()` dispatcher +
  three helpers (`resume_label_state`, `resume_sendback_count_24h`,
  `resume_paused_for`) added to `bin/fleet`; no `lib/` or `prompts/`
  changes. AGENTS.md § Telemetry gets the new `ship_resumed` bullet.
- 2026-06-03 — shipped via PR #58
  (https://github.com/mutaaf/agent-fleet/pull/58). Both gating checks
  (shellcheck + validate) green; auto-merge fired clean. No novel
  LESSON appended — the four LESSONS the ticket flagged
  (2026-05-{26,27,28,30} + 2026-06-01 × 2) were all already
  documented and the implementation respected them on the first
  cut. The only minor course-correction was the help-block content
  (`--help` keyword was implied by `-h|--help` but the test asserts
  the literal token, so the USAGE block now names `--help` on its
  own line) — that's mechanics, not novel operational memory.
