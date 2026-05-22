# agent-fleet

One engine for the autonomous coding agents that run across my projects. Instead
of hand-cloning the ship/groom/review loop into every repo (and watching it
drift), the loop lives here once and each project supplies a small manifest.

- **`DOCTRINE.md`** — the standard every project's agents target, and the
  canonical decisions (backlog model, review depth, merge authority, cadence).
- **`MIGRATION.md`** — drift/overlap audit + the plan to converge Almanac,
  CourtIQ, and Digital Craft onto the standard.
- **`manifest.example.sh`** — the per-project config schema (copy → fill in).

```
agent-fleet/
├── bin/fleet              # fleet status — one-glance survey of every project
├── lib/                   # the shared engine (config-driven, project-agnostic)
│   ├── common.sh          #   env, manifest load, self-cancel, fresh checkout
│   ├── ship.sh            #   heal in-flight PR, else ship top ticket
│   ├── groom.sh           #   refill/regroom the backlog
│   ├── review.sh          #   grade open agent PRs (comment / request-changes)
│   ├── eng.sh             #   optional engineering queue worker
│   ├── install.sh         #   copy to TCC-safe dir + generate launchd plists
│   └── uninstall.sh
├── prompts/               # generic agent prompts (read AGENTS.md at runtime)
├── templates/             # what a project copies in on adoption
└── manifest.example.sh
```

## How it works

`install.sh <project>` copies the engine to a TCC-safe location under
`~/.local/share/agent-fleet/`, copies the project's `agents.config.sh`, and
generates launchd jobs from the manifest's cadence. At runtime each agent clones
the repo fresh into `~/.cache/<slug>-agent/`, reads `AGENTS.md` for the project's
specifics, and runs against the local `claude` CLI (Max subscription — no API
keys, no per-session billing).

**Plumbing is shared; semantics live in the repo.** The shell reads
`agents.config.sh`; the agent reads `AGENTS.md § Agent parameters`. Edit the
engine once → the whole fleet changes.

## Use it

```bash
# survey everything
./bin/fleet status

# add / refresh a project
cp manifest.example.sh /path/to/repo/agents.config.sh   # then edit
bash lib/install.sh /path/to/repo

# run one now / remove
launchctl kickstart -k gui/$UID/com.<slug>.agent-ship
bash lib/uninstall.sh /path/to/repo
```

See `DOCTRINE.md §6` to add a new project in ~10 minutes.
