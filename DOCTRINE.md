# Fleet Doctrine — the one standard every project's agents target

This is the canonical design for autonomous coding agents across the fleet
(Almanac, CourtIQ, Digital Craft, and whatever comes next). It exists because
the same loop was hand-cloned into three repos and started drifting. One
standard, one engine, per-project config.

The rule that makes it scalable:

> **Plumbing is shared and parameterized. Semantics live in the repo.**
> The shell engine (`lib/*.sh`) is identical for every project and reads only
> `agents.config.sh`. Everything that requires judgment — gating checks, branch
> prefixes, the local gate command, voice, hard NOs — lives in that project's
> `AGENTS.md`, which the agent reads from a fresh checkout at runtime.

Edit the engine once → the whole fleet changes. Edit a manifest → one project
changes. No more porting a fix to N shell scripts by hand.

---

## 1. The loop

```
GROOM ───► SHIP ───► REVIEW ───► auto-merge ───► auto-deploy
(refills    (heals     (grades vs      (GitHub, on      (host, on
 backlog;    in-flight  AGENTS.md +     green gating      push to
 self-gates  PR FIRST,  the ticket;     checks + no       main)
 when full)  then ships  comment /       blocking
             top ticket) request-changes) review)
   ▲                                              │
   └──────────── docs/LESSONS.md ◄────────────────┘
        (append-only operational memory; every run reads it, appends novel lessons)

(optional) ENG ───► REVIEW ───► auto-merge   — peer worker on the eng/ queue
```

Four agents, three required:

| Agent | Cadence | Reads | Writes | Never |
|---|---|---|---|---|
| **groom** (gtm-innovation) | every 6h | backlog, LESSONS | tickets, index, groom PR | code, tests |
| **ship** (implementation-dev) | hourly | AGENTS, ticket, LESSONS | feature branch + PR, heal commits | main directly |
| **review** | every 5 min | AGENTS, diff, ticket, LESSONS | `--comment` / `--request-changes` | `--approve`, the PR branch |
| **eng** (eng-dev) *(optional)* | every 6h | eng backlog, AGENTS, LESSONS | `eng/` branch + PR | user-facing behavior |

---

## 2. Canonical decisions (cherry-picked from all three lineages)

These are the points where the three projects had diverged. The standard picks
one winner for each, and explains why.

| # | Decision | Standard | Why it won |
|---|---|---|---|
| D1 | Backlog model | **Ticket files** `docs/backlog/NNNN-*.md` + `README.md` index + `_template.md` + **CI validator** | Drift-proof (validator gates merges), per-ticket history, test-shaped specs. (from the Almanac/CourtIQ lineage) |
| D2 | Spec rigor | **Four-lens "Why now"** (Product Owner / Stakeholder / User / Growth) + acceptance criteria that map 1:1 to tests | Produces better-reasoned, test-first work than one-line checklist items. (same lineage) |
| D3 | Queues | **Feature queue required; engineering queue optional** (`ENG_ENABLED`) with its own `eng/` prefix + independent single-PR gate | Lets code-quality work ship without competing with features. (from Digital Craft) |
| D4 | Review depth | **Two stages**: a cheap inline self-check by the worker, then an **independent** reviewer agent that owns the gate | The independent stage catches what the worker rubber-stamps. (from Digital Craft) |
| D5 | Merge authority | **GitHub auto-merge** on green gating + no blocking review. The reviewer *votes*, it does not run `gh pr merge` to land code | Least agent privilege; auditable; the merge rule lives in branch protection, not in an agent prompt. (from Almanac/CourtIQ) |
| D6 | Self-heal | Ship/eng **heal the in-flight PR first** (BEHIND→update-branch, red→bounded ≤2 recovery, DIRTY→merge, else wait/arm), heal OR ship per run | One stuck PR must never freeze the loop. (Almanac/CourtIQ; ported to all) |
| D7 | Spec file name | **`AGENTS.md`** (plural) at repo root, with a **`## Agent parameters`** section | One name across the fleet; Digital Craft's `AGENT.md` is renamed. |
| D8 | Cadence | ship hourly `:41` · groom 6h `:17` · review `300s` · eng 6h `:23` | Standardized; deviations must be justified in the manifest comment. |
| D9 | Namespace | launchd label `com.<slug>.agent-*`; cache/logs `~/.cache/<slug>-agent/` | `<slug>` MUST equal the repo name. (fixes CourtIQ's `sportsiq` drift) |
| D10 | Spend bound | `SELF_CANCEL` in the manifest; `fleet status` warns ≤3 days out | One place to see and bump every project's expiry. |
| D11 | Cost model | Local `claude` CLI on the Max subscription; **no API keys in repos**, no remote per-session billing | Cheapest for high-frequency polling; no secret surface. (all three) |
| D12 | Model | `claude-opus-4-7` for all agents | Full-context reasoning for code + review. (all three) |

---

## 3. The `## Agent parameters` contract (every AGENTS.md must have this)

Because the prompts are generic, each repo declares its specifics in one section
the agents read at runtime. Minimum fields:

```markdown
## Agent parameters

- **Gating checks** (EXACTLY these GitHub check names; everything else is
  informational and must be ignored): `Typecheck + build`, `E2E (chromium)`,
  `E2E (mobile-webkit)`
- **Agent branch prefixes**: `feat/` (features), `chore/gtm-` (groom), `eng/` (engineering)
- **Local gate command** (what heal/dev runs locally before pushing):
  `npm run typecheck && npm run build && npx playwright test --project=chromium`
- **Subagents**: implementation-dev, gtm-innovation, review[, eng-dev]
- **Backlog areas**: labs | plan | meals | today | progress | settings | infra | privacy | growth
```

Plus the binding **`## Hard NOs`** list (privacy/security/voice rules) the
reviewer enforces as auto-rejections.

---

## 4. Standard repo layout

```
<repo>/
├── AGENTS.md                      # contract + "## Agent parameters" + "## Hard NOs"
├── agents.config.sh               # the manifest (plumbing; see manifest.example.sh)
├── docs/
│   ├── LESSONS.md                 # append-only operational memory
│   └── backlog/
│       ├── README.md              # index table (ordering truth)
│       ├── _template.md           # ticket template (4-lens)
│       └── NNNN-*.md              # tickets (status truth)
├── scripts/check-backlog.mjs      # the validator, wired into CI as a gating step
└── .claude/agents/                # implementation-dev, gtm-innovation, review[, eng-dev]
```

The runner scripts, prompts, and install/uninstall do NOT live in the repo —
they live once in this kit and are copied to a TCC-safe location by `install.sh`.

---

## 5. Invariants (true for every project, enforced or asserted)

1. **Status truth is the ticket file; ordering truth is the index.** The CI
   validator fails the build if they disagree (no silent re-shipping).
2. **Only the named gating checks gate a merge.** A red Vercel/preview/info check
   is never a reason to fix anything or block a merge.
3. **The reviewer never `--approve`s** (it runs as the PR author). It blocks with
   `--request-changes` and signs off with `--comment`. Auto-merge does the landing.
4. **Heal is bounded.** ≤2 `heal:`-prefixed commits per PR, then escalate to a
   human comment. No infinite recovery loops.
5. **No secrets in the repo, no backend added by an agent.** Privacy/security
   hard NOs in AGENTS.md are auto-rejections, not suggestions.
6. **Self-cancel is real.** Past `SELF_CANCEL`, every agent no-ops until bumped.

---

## 6. Growing the fleet (add a project in ~10 minutes)

1. `cp manifest.example.sh <repo>/agents.config.sh` and fill in identity + cadence.
2. Add `## Agent parameters` + `## Hard NOs` to the repo's `AGENTS.md`.
3. Create `docs/backlog/` (`_template.md` + `README.md` index) and copy
   `templates/scripts/check-backlog.mjs` into `scripts/`; wire it into CI as a
   gating step.
4. Copy the four `.claude/agents/*.md` subagents; edit only their voice/contract
   parts — keep the names and the execution loops.
5. `bash <kit>/lib/install.sh /abs/path/to/<repo>`.
6. `fleet status` to confirm it's loaded and counting down to self-cancel.

Nothing about the loop is re-implemented. The only per-project surface is one
manifest + one AGENTS.md section + the subagent voice. That is the whole point.
