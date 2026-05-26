---
id: 0003
title: fleet doctor subcommand for fleet health
status: shipped
priority: P1
area: observability
created: 2026-05-26
owner: gtm-innovation
---

## User story

As a fleet operator, I want `fleet doctor` to validate every installed project
in one command, so that "is the fleet healthy?" has a one-line answer instead
of grep-through-launchctl-and-config-files.

## Why now (four lenses)

### Product Owner
A single diagnostic replaces five ad-hoc checks. Run it before a long break
or after a kit update — get a green light or a list of exactly what to fix.

### Stakeholder
Widens the moat on `observability`. The kit becomes diagnose-itself. New
contributors find broken state in seconds instead of bisecting launchd.

### Operator
"After I upgraded the kit, is everything still working?" — one command
answers. Includes prompt-SHA drift (ticket 0005), missing gh auth, stale
checkouts, and self-cancel within 3 days.

### Growth
"It tells you what's wrong" is the kind of polish that makes the kit
demo-worthy. Compare to setting up CI from scratch with no doctor.

## Acceptance criteria

- [ ] `bin/fleet doctor` scans `~/Desktop/projects/*/agents.config.sh` and
      for each project reports PASS/WARN/FAIL on:
      - `agents.config.sh` parseable; required vars set (SLUG, REPO_URL,
        SELF_CANCEL)
      - SELF_CANCEL not in the past (FAIL) and >3 days out (otherwise WARN)
      - `AGENTS.md § Agent parameters` section present
      - `docs/backlog/README.md` and `scripts/check-backlog.mjs` exist
      - launchd labels for `com.<slug>.agent-{ship,groom,review,eng?}` are
        loaded (`launchctl print` succeeds)
      - `~/.local/share/agent-fleet/lib` SHA matches this repo's `lib/` SHA
        (computed via `find lib -type f -name '*.sh' | sort | xargs shasum`)
      - `gh auth status` succeeds
- [ ] Output is one block per project, prefixed `[PASS]`/`[WARN]`/`[FAIL]`,
      with a one-line reason per failed check. Exit 0 if no FAIL, 1 if any
      FAIL.
- [ ] `--json` flag prints a machine-readable summary
      (`{"projects":[{"slug":..., "checks":[{"name":..,"status":..,"reason":..}]}]}`)
      that fleet-control will consume.
- [ ] `--slug NAME` filter restricts to one project.
- [ ] `tests/doctor.sh` runs `bin/fleet doctor --json` on a tmpdir fixture
      with two synthetic projects (one healthy, one missing AGENTS.md) and
      asserts the expected check rows.
- [ ] `README.md` "Daily ops" section gets a one-line callout for the new
      subcommand.

## Out of scope

- Auto-fix. Doctor only diagnoses; ticketing fixes is the operator's call.
- Cross-host diagnostics. Single machine only.
- A web UI for doctor (that belongs in fleet-control, separate ticket).

## Engineering notes

- `bin/fleet` is a single bash script; add a `doctor()` function and dispatch
  from the top-level case statement.
- `tests/doctor.sh` — create a fixture dir layout under `mktemp -d`, point
  `FLEET_DISCOVERY_ROOT=$tmpdir` (introduce this env override), assert the
  JSON output.
- Reinstall: not required (this is `bin/`, not `lib/`).
- Public API: additive.

## Implementation log

- 2026-05-26 — implementation-dev — opened `feat/0003-fleet-doctor`. Plan: add a
  `doctor()` function plus the top-level `doctor` case branch to `bin/fleet`,
  introduce `FLEET_DISCOVERY_ROOT` as the test-friendly override for the
  scanned roots, ship `--json` + `--slug NAME` flags, and back it with a
  fixture-based `tests/doctor.sh`.
- 2026-05-26 — implementation-dev — shipped. Added `doctor()` to `bin/fleet`
  with seven checks (config, self_cancel, agents_md, backlog, launchd_loaded,
  installed_lib_sha, gh_auth), `--json` + `--slug NAME` flags, and the
  `FLEET_SKIP_INSTALLED_LIB_SHA` env override so test hosts without an install
  WARN rather than misleadingly PASS. Wrote `tests/doctor.sh` with a two-project
  tmpdir fixture (one healthy, one missing AGENTS.md), stubbing `launchctl` and
  `gh` on PATH so the test is host-independent. Added a "Daily ops" subsection
  to the README's `bin/fleet` dashboard section. Local gate green:
  `shellcheck -S warning lib/*.sh bin/fleet && bash -n lib/*.sh bin/fleet &&
  node scripts/check-backlog.mjs && bash tests/{doctor,lock,events}.sh`.
