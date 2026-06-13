#!/bin/bash
# agent-fleet/lib/tour-catalog.sh — the event-type → PRINCIPLES.md lookup
# table used by `bin/fleet tour` (ticket 0050).
#
# Each event type in AGENTS.md § Telemetry MUST have a matching
# `tour_catalog_<type>()` function below. The `scripts/check-tour-catalog.mjs`
# gate (wired into CI's `validate` job) rejects PRs that add an event type
# without a catalog entry — that forces every future telemetry change to
# also ship the "how do I explain this to a new operator" answer.
#
# CONTRACT: this file is loaded ONLY by `bin/fleet tour` (operator-pull).
# It is NEVER sourced by `lib/ship.sh`, `lib/eng.sh`, `lib/groom.sh`,
# `lib/review.sh`, or `lib/common.sh`. The runtime hot-path stays
# unaffected; the catalog is pure documentation surface.
#
# Each function echoes a single line in TAB-separated form:
#   <principle_id>\t<gloss>\t<why_this_event_exists>
#
# principle_id is one of P-1..P-9 from prompts/PRINCIPLES.md. The titles
# are quoted verbatim in tour_catalog_principle_title so the renderer can
# present "P-N (<title>)" without re-reading prompts/PRINCIPLES.md at
# runtime.
#
# Strings are single-quoted to avoid shellcheck SC2006 (backtick
# command-substitution) false positives — every literal backtick in the
# AGENTS.md prose would otherwise be flagged. Where a literal apostrophe
# is needed inside a single-quoted string we use the standard
# '\''-rebracket trick.

# --- run_started -----------------------------------------------------------
tour_catalog_run_started() {
  printf '%s\t%s\t%s\n' \
    'P-6' \
    'The ship/groom/review/eng runner just fired (launchd schedule). Every run starts here. The pid lets you grep launchd logs if a run silently disappears.' \
    'Without it you cannot tell apart "launchd never fired" from "the run started but died early".'
}

# --- run_completed ---------------------------------------------------------
tour_catalog_run_completed() {
  printf '%s\t%s\t%s\n' \
    'P-6' \
    'This cycle ended cleanly. exit and duration_ms close the run. Every run_started pairs with exactly one run_completed.' \
    'A run_started with no matching run_completed in events.jsonl is the operator signal that a run crashed mid-flight.'
}

# --- gate_failed -----------------------------------------------------------
tour_catalog_gate_failed() {
  printf '%s\t%s\t%s\n' \
    'P-3' \
    'A required CI check failed on an open agent PR. This is the heal signal — the next ship run will work the PR before picking a new ticket.' \
    'Without this signal the loop would pile up red PRs instead of healing them first.'
}

# --- pr_opened -------------------------------------------------------------
tour_catalog_pr_opened() {
  printf '%s\t%s\t%s\n' \
    'P-4' \
    'The dev agent picked the top groomed ticket and opened a PR on a branch matching the AGENTS.md branch-prefix contract.' \
    'Every pr_opened is auditable evidence the agent obeyed the priority queue instead of picking the convenient ticket.'
}

# --- self_cancel_trip ------------------------------------------------------
tour_catalog_self_cancel_trip() {
  printf '%s\t%s\t%s\n' \
    'P-5' \
    'The manifest SELF_CANCEL date has passed. The run no-ops with exit 0 instead of churning forward without operator confirmation.' \
    'Bump SELF_CANCEL and re-run install.sh to extend. The trip event is the audit trail for "why did the loop pause itself?".'
}

# --- lock_blocked ----------------------------------------------------------
tour_catalog_lock_blocked() {
  printf '%s\t%s\t%s\n' \
    'P-3' \
    'Another runner of the same phase is already holding the per-slug flock. The newcomer exits without claude/git work.' \
    'Two ship runs racing on one PR would fight each other; the lock plus this event preserve the one-PR-at-a-time invariant.'
}

# --- budget_block ----------------------------------------------------------
tour_catalog_budget_block() {
  printf '%s\t%s\t%s\n' \
    'P-5' \
    'Today UTC spend for this slug has reached the manifest MAX_DAILY_USD cap. Runners soft-abort with exit 0 immediately.' \
    'Operator confidence depends on the loop respecting a declared dollar boundary; the event tells you exactly when it tripped.'
}

# --- prompts_drift ---------------------------------------------------------
tour_catalog_prompts_drift() {
  printf '%s\t%s\t%s\n' \
    'P-7' \
    'The manifest PROMPTS_SHA pin does not match the kit current prompts/ SHA. Fires at most once per process and the runner continues — drift is a signal.' \
    'PRs that touch prompts/ require a reinstall before installed projects see the new behavior; this event makes the gap visible.'
}

# --- ship_paused -----------------------------------------------------------
tour_catalog_ship_paused() {
  printf '%s\t%s\t%s\n' \
    'P-3' \
    'Three or more agent PRs in the last 24h received REQUEST_CHANGES and closed unresolved. PHASE 2 (new tickets) is now forbidden; PHASE 1 (heal) still runs.' \
    'Without this guard the loop would keep proposing while the reviewer is rejecting — wasted effort and operator confidence.'
}

# --- rollback_opened -------------------------------------------------------
tour_catalog_rollback_opened() {
  printf '%s\t%s\t%s\n' \
    'P-3' \
    'An operator invoked fleet rollback and a revert PR opened against the originally-shipped commit. The revert branch is auditable.' \
    'Recovery is a normal step in the loop; the event marks the recovery cleanly so "why was this reverted?" has a single answer.'
}

# --- events_rotated --------------------------------------------------------
tour_catalog_events_rotated() {
  printf '%s\t%s\t%s\n' \
    'P-6' \
    'events.jsonl reached FLEET_EVENTS_MAX_BYTES and was moved into events.jsonl.archive/<UTC-stamp>.jsonl. This marker is the first line of the fresh channel.' \
    'Consumers tailing the channel see an explicit rotation boundary without comparing inode numbers; archives stay part of the contract.'
}

# --- infra_flake_rerun -----------------------------------------------------
tour_catalog_infra_flake_rerun() {
  printf '%s\t%s\t%s\n' \
    'P-3' \
    'The heal step classified the failed CI as a known infra-flake pattern (catalog in lib/heal-catalog.sh) and triggered one gh run rerun instead of coding a fix.' \
    'Infra-flake retries are bounded (dedupe by pattern plus run_id within 2h) so a genuinely broken infra cannot trap the runner in a rerun loop.'
}

# --- lesson_draft_emitted --------------------------------------------------
tour_catalog_lesson_draft_emitted() {
  printf '%s\t%s\t%s\n' \
    'P-9' \
    'The reviewer posted a --request-changes verdict and a date-stamped DRAFT block landed at the top of docs/LESSONS.md for operator promotion.' \
    'Send-backs are candidate lessons; the operator stays responsible for what LESSONS says. Count drafts vs. promotions for promotion debt.'
}

# --- prompts_pin_changed ---------------------------------------------------
tour_catalog_prompts_pin_changed() {
  printf '%s\t%s\t%s\n' \
    'P-7' \
    'An install.sh run found the project PROMPTS_SHA would change. Carries phase=install so consumers can distinguish bootstrap pin transitions from runtime drift.' \
    'Every transition here becomes a row boundary in fleet prompts-score — the timeline of behavioral revisions.'
}

# --- lesson_promoted -------------------------------------------------------
tour_catalog_lesson_promoted() {
  printf '%s\t%s\t%s\n' \
    'P-8' \
    'The operator promoted one paragraph from a project docs/LESSONS.md into the cross-project CROSS_LESSONS feed via fleet lessons-promote.' \
    'Cross-project memory is curated, not automatic. Promotion lives in the source project events.jsonl (P-6: project is the unit).'
}

# --- trainee_pr_opened -----------------------------------------------------
tour_catalog_trainee_pr_opened() {
  printf '%s\t%s\t%s\n' \
    'P-5' \
    'TRAINEE_PR_COUNT has not yet graduated; the dev agent opened the PR but skipped gh pr merge --auto and posted a "please review and merge manually" comment.' \
    'New projects earn auto-merge trust by merging the first N agent PRs by hand. The event tracks remaining trainee budget.'
}

# --- quiet_hours_skip ------------------------------------------------------
tour_catalog_quiet_hours_skip() {
  printf '%s\t%s\t%s\n' \
    'P-5' \
    'The fire landed inside the operator-declared QUIET_HOURS window from agents.config.sh. ship/groom/eng no-op with exit 0; review is exempt by design.' \
    'Operator-declared policy beats schedule. The event is the audit trail for "why did the loop no-op at 2am?".'
}

# --- prompts_reverted ------------------------------------------------------
tour_catalog_prompts_reverted() {
  printf '%s\t%s\t%s\n' \
    'P-7' \
    'An operator invoked fleet prompts-revert and the kit prompts/ tree was pinned back to a known-good SHA. A revert PR opened with the operator reason.' \
    'Prompt revisions are reversible by design. The event ties the revert PR to the failing behavior so the recovery path stays auditable.'
}

# --- ship_resumed ----------------------------------------------------------
tour_catalog_ship_resumed() {
  printf '%s\t%s\t%s\n' \
    'P-3' \
    'An operator (or the streak-check) cleared a prior ship_paused state for one slug. ship runs are now allowed again.' \
    'Recovery from auto-pause is operator-initiated; the event marks when the pause cleared and whether --force overrode the streak check.'
}

# --- lessons_pruned --------------------------------------------------------
tour_catalog_lessons_pruned() {
  printf '%s\t%s\t%s\n' \
    'P-8' \
    'Operator ran fleet lessons-prune --commit. Paragraphs with EXPIRES markers moved into docs/LESSONS-ARCHIVE.md via a chore PR.' \
    'Append-only memory needs a curation primitive; this event tracks why LESSONS shrank in a given week and ties it to a reviewable PR.'
}

# --- vacation_skip ---------------------------------------------------------
tour_catalog_vacation_skip() {
  printf '%s\t%s\t%s\n' \
    'P-5' \
    'Operator declared PTO via fleet vacation --until DATE --reason TEXT. ship/eng no-op with exit 0 until the boundary; review and groom still run.' \
    'Operator-confidence boundary: "I am away, do not start new work". The event is the audit trail for every suppressed fire.'
}

# --- vacation_returned -----------------------------------------------------
tour_catalog_vacation_returned() {
  printf '%s\t%s\t%s\n' \
    'P-5' \
    'Vacation ended (auto-resume at --until OR manual fleet vacation --return). One event per previously-suspended slug, recording elapsed duration.' \
    'Mirrors ship_resumed: operator-initiated recovery actions emit one typed event so the return-to-normal moment is reconstructable.'
}

# --- self_check_failed -----------------------------------------------------
tour_catalog_self_check_failed() {
  printf '%s\t%s\t%s\n' \
    'P-8' \
    'fleet self-check (invoked with FLEET_SELF_CHECK_GATE=1) found a known LESSONS-derived call-shape trap in the kit own source.' \
    'Documented traps regress; the gate event names the pattern plus LESSON date plus file:line so the heal step can fix it before merging.'
}

# --- Principle titles (quoted from prompts/PRINCIPLES.md so the renderer
# can compose "P-N (<title>)" without re-reading the file at runtime).
tour_catalog_principle_title() {  # $1 = P-N
  case "$1" in
    P-1) printf -- 'smallest viable change' ;;
    P-2) printf -- 'tests-first' ;;
    P-3) printf -- 'heal in-flight before new work' ;;
    P-4) printf -- 'ship the top groomed ticket, never the convenient one' ;;
    P-5) printf -- 'operator confidence over feature richness' ;;
    P-6) printf -- 'telemetry is the source of truth' ;;
    P-7) printf -- 'reinstall on prompt/lib drift' ;;
    P-8) printf -- 'append memory; never reorder' ;;
    P-9) printf -- 'review send-backs draft LESSONS; the operator promotes' ;;
    *)   printf -- 'unknown principle' ;;
  esac
}
