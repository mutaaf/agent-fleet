# Migration — converging the three projects onto the fleet standard

State as audited 2026-05-22. This is the map from "three hand-cloned loops" to
"one engine + three manifests." Read `DOCTRINE.md` first for the target.

---

## Where we started (the drift)

Two lineages, not three:

- **Twins** — Almanac and CourtIQ. CourtIQ is essentially a fork of Almanac's
  loop; the scripts are ~95% identical. Same ship/groom/review trio, same
  cadence (`:41` / `:17` / 300s), same ticket-file backlog + validator, same
  4-lens specs, same GitHub auto-merge model.
- **Cousin** — Digital Craft. An older, separately-grown loop: inline checklist
  backlog (no ticket files, no validator), reviewer-owns-the-merge, two-stage
  review, a **second** engineering queue, singular `AGENT.md`, different cadences.

| Axis | Almanac | CourtIQ | Digital Craft | Standard (target) |
|---|---|---|---|---|
| Backlog | ticket files + validator | ticket files + validator | inline checklist | **ticket files + validator** |
| Spec rigor | 4-lens | 4-lens | one-liners | **4-lens** |
| Queues | 1 | 1 | 2 (gtm+eng) | **gtm req, eng optional** |
| Review stages | 1 | 1 | 2 | **2** |
| Merge | auto-merge | auto-merge | reviewer merges | **auto-merge** |
| Spec file | AGENTS.md | AGENTS.md | AGENT.md | **AGENTS.md** |
| Cadence | 41/17/5m | 41/17/5m | 17/daily/15m | **41/17/5m + eng 6h** |
| Namespace | `com.almanac` | **`com.sportsiq`** ⚠ | `com.digitalcraft` | `com.<repo>` |
| Self-cancel | 2026-05-28 | 2026-06-03 | 06-02 / 06-12 | manifest + `fleet status` |
| Engine | 3 hand-edited .sh | 3 hand-edited .sh | 4 hand-edited .sh | **shared `lib/*.sh`** |

The overlap was the tax: every loop improvement (e.g. the 2026-05-20
self-healing patch) had to be hand-ported. It reached the twins; Digital Craft
still has a different, older healing approach.

---

## What the kit changes

- **One engine.** `lib/{common,ship,groom,review,eng,install,uninstall}.sh` +
  `prompts/*` are identical for all projects. Per-project surface shrinks to
  `agents.config.sh` + `AGENTS.md § Agent parameters` + subagent voice.
- **One dashboard.** `bin/fleet status` surveys every project: installed?, last
  run, open agent PRs, lessons, days-to-self-cancel.
- **Deliberate convergence**, picking the best of each lineage (DOCTRINE §2):
  ticket-files+validator and 4-lens (from the twins); dual-queue and two-stage
  review (from Digital Craft); auto-merge and bounded self-heal (from the twins).

---

## Migration order & steps

Sequenced low-risk → high-risk. The agents are LIVE (shipping to `main`), so each
step is reversible and verified before the next.

### Phase A — Twins (Almanac, CourtIQ) — lowest risk, nearly aligned already

For each:
1. Add `agents.config.sh` (from `manifest.example.sh`). Set a fresh `SELF_CANCEL`.
2. Add a `## Agent parameters` section to the existing `AGENTS.md` (gating checks,
   branch prefixes, local gate command, subagents, areas). The semantics already
   exist in prose — this just makes them the one place the generic prompts read.
3. **CourtIQ only:** fix the namespace. It installs under `com.sportsiq.*` /
   `~/.cache/sportsiq-agent/` (legacy name). Set `SLUG=courtiq`,
   `NAMESPACE=com.courtiq`. On reinstall, `bootout` the old `com.sportsiq.*` jobs
   so they don't double-run alongside the new `com.courtiq.*` ones.
4. Reinstall via the kit: `bash lib/install.sh /abs/path/to/<repo>`.
   - This is idempotent for Almanac (same labels/schedule) — effectively a no-op
     swap to the shared engine.
   - Verify no PR is mid-flight first (`fleet status` PRS column / `gh pr list`);
     reinstalling between runs is safe, the in-flight PR is healed next tick.
5. Retire the repo's own `scripts/agent-*.sh` and `install-agents.sh` once the
   kit-installed jobs are confirmed (keep them one cycle as a rollback).
6. `fleet status` → confirm `yes` installed and a recent last-run.

### Phase B — Digital Craft — the real convergence (do after twins prove out)

Bigger lift because its data model differs. Order within:
1. **Rename** `AGENT.md` → `AGENTS.md`; add `## Agent parameters` + `## Hard NOs`.
   Keep `CLAUDE.md` (it's the tech reference) and `ENGINEERING.md` (becomes the
   eng queue's backlog).
2. **Convert the backlog** from the inline tier checklist to ticket files:
   `docs/backlog/NNNN-*.md` + `README.md` index + `_template.md`, and add
   `scripts/check-backlog.mjs` to CI as a gating step. (Can be incremental:
   migrate open/Tier-7 items first; archive the completed tiers as a CHANGELOG.)
3. **Switch merge model** to GitHub auto-merge: add an `auto-merge` workflow (or
   arm `gh pr merge --auto`) and stop the reviewer from running `gh pr merge`.
   The reviewer becomes vote-only, matching D5.
4. **Adopt standard subagent names**: gtm-worker→gtm-innovation,
   →implementation-dev, gtm-reviewer→review, eng-worker→eng-dev.
5. `agents.config.sh` with `ENG_ENABLED=1`; reinstall via `lib/install.sh`;
   bootout the old `com.digitalcraft.*` hand-rolled jobs.
6. Fold its lessons (em-dash rule, two-stage review) into the standard prompts if
   not already covered.

### DC cutover (gated runbook)

Phase B's additive prep is **done and on a PR** (DC #27): `agents.config.sh`,
`AGENTS.md` + `## Agent parameters`, the four `.claude/agents/` subagents, the
`docs/backlog/` ticket system + validator (4 items seeded), and the validator
wired into CI. All of it is **dormant** — the legacy `gtm`/`eng` shell agents read
`AGENT.md` + the inline checklist, which are untouched, so #27 is safe to merge
without changing the running loop.

The remaining steps are the **behavioral cutover**, gated because DC is a live
daily-committing marketing site and the change is real (not the near-identical
swap the twins were). Do these together, watching the first ship run:

1. Merge DC #27 to `main`.
2. **Convert the remaining 7 legacy Tier-7 items** to ticket files (or let the
   first kit groom run do it), then delete the inline backlog from `AGENT.md` and
   point the file at `docs/backlog/`.
3. **Add `.github/workflows/auto-merge.yml`** (mirror CourtIQ's) so the reviewer
   becomes vote-only — this changes merge authority, so don't add it until step 5.
4. **Decide detection**: the kit detects agent PRs by branch prefix
   (`feat/`/`chore/gtm-`/`eng/`), DC's legacy loop used the `gtm-agent`/`eng-agent`
   *labels*. The new subagents already open prefixed branches; confirm branch
   protection requires `build` + `smoke-required`.
5. **Cut over launchd**: `bash agent-fleet/lib/install.sh <dc>` to create
   `com.digitalcraft.agent-{ship,groom,review,eng}`, then bootout the legacy
   `com.digitalcraft.{gtm-worker,gtm-groomer,gtm-reviewer,eng-worker}`. (Note: a
   `gtm-worker` run was observed hung for hours — clear it on cutover.)
6. **Watch the first ship + review runs** (`~/.cache/digitalcraft-agent/logs/`,
   `fleet status`) before walking away. Confirm the first PR respects the no-touch
   zones (`/api/`), the em-dash ban, and dark-mode variants.

Rollback: `bash agent-fleet/lib/uninstall.sh <dc>` then re-run DC's original
`scripts/install plists` (the `gtm-*-local.sh` scripts are untouched).

### Phase C — Fleet hygiene (ongoing)

- `fleet status` becomes the morning glance. Bump `SELF_CANCEL` from one place.
- New projects follow DOCTRINE §6 (~10 min each), never hand-roll a loop again.
- Loop improvements land in `lib/`/`prompts/` once and reach everyone on reinstall.

---

## Rollback

Each project's original `scripts/` are untouched until Phase A step 5 / Phase B
step 5. To revert one project: `bash <kit>/lib/uninstall.sh <repo>` then re-run
its original `scripts/install-agents.sh`. The kit and the repos are independent.
