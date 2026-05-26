# LESSONS

Operational memory for the autonomous loop. Append, never reorder. Each entry
is one paragraph: symptom → cause → fix. Lessons here are read at the start of
every ship/groom run.

## 2026-05-25 — bootstrap

The kit is dogfooding itself for the first time. The seatbelts: CI gates on
`shellcheck` + `validate`, branch protection requires both contexts, and the
review subagent enforces AGENTS.md § Hard NOs. Lessons below are the agents'
collective memory across all runs on this repo.

## 2026-05-25 — `lib/` changes need a fleet-wide reinstall

When a PR modifies anything under `lib/` or `prompts/`, the change only lands
in this repo on merge — every installed project still runs the old engine from
`~/.local/share/agent-fleet/`. The post-merge action is to re-run
`bash lib/install.sh /path/to/project` for every project in the fleet. Until a
ticket automates this, ship PRs that touch `lib/` should add a one-liner to
the PR body: `Reinstall: all projects`.

## 2026-05-26 — `gh pr create` needs `--head <user>:<branch>` from agent runs

`gh pr create` without `--head` sometimes refuses with "you must first push
the current branch to a remote" even after a successful `git push -u origin
HEAD` — the upstream tracking ref doesn't always survive whatever isolates
the agent's checkout. Workaround: pass `--repo mutaaf/agent-fleet
--head mutaaf:<branch>` explicitly. Also include `--base main` to be safe.

## 2026-05-26 — bash scripts launched with `&` cannot be SIGINT-tested

POSIX says: "a signal set to be ignored on entry to a process shall remain
ignored." When the test harness launches `./script.sh &`, bash inherits
SIGINT as SIG_IGN from the job-control context, so any subsequent
`trap '...' INT` inside the script does NOT install — `trap -p INT` echoes
empty afterwards. Symptom: a test that sends `kill -INT $PID` to a
backgrounded helper waits forever even though Ctrl-C in a real terminal
would work fine. Workaround: in tests, use `kill -TERM` (which is honoured)
AND add a source-level grep assertion that the production code installs
`trap <fn> INT TERM` — that pair exercises the cleanup path the test needs
without requiring `setsid` (missing on macOS) or a pseudo-tty wrapper. See
the AC#6 block in `tests/tail.sh` (ticket 0015) for the pattern.

## 2026-05-26 — naming a shell function `tail` shadows `/usr/bin/tail`

When `bin/fleet` declared a `tail()` function for the `fleet tail`
subcommand, every internal `tail -F "$file"` call resolved to the shell
function (which re-ran the subcommand recursively with `-F` as an
unknown flag) instead of the system binary. Symptoms: "fleet tail:
unknown flag '-F'" lines in the formatter output and lines from the
fixture's events.jsonl never appearing live. Fix: name the dispatch
function something OTHER than `tail` — we used `tail_cmd()`. Same
pattern applies to any subcommand that would collide with a coreutils
binary the same script also shells out to (`head`, `cat`, `sort`,
`uniq`, etc.). When in doubt, prefix the dispatcher with `_cmd` or run
the binary via `command tail …` to bypass the function.

## 2026-05-26 — GitHub Actions can silently stop firing for a PR

While shipping ticket 0006, four consecutive pushes to
`feat/0006-auto-pause-on-sendbacks` registered ZERO workflow runs over
~40 minutes — neither `CI` nor `auto-merge`. The PR head SHA's
`/check-runs` was empty, `/actions/runs?branch=...` returned 0, the PR
state stayed `mergeStateStatus=BLOCKED` with an empty `statusCheckRollup`.
GitHub Actions service status was "All Systems Operational". No
quota/banner appeared. Close+reopen, empty commits, content-changing
commits, all failed to nudge a run. Symptom: the very same workflow that
green-checked PRs #2–#6 within 20s simply doesn't fire on #7. Almost
certainly a transient on the GitHub side (queue, billing-limit, or
account-level flag), NOT something the loop did. Mitigation when seen:
(a) wait 30+ min and re-push, (b) try a fresh branch name (push the same
commits to `feat/<id>-<slug>-v2`), (c) escalate to a human via a PR
comment rather than `gh pr merge --admin` (admin merge violates the
"never bypass branch protection" Hard NO). Do NOT use `--admin` to
unstick. The PR can sit with auto-merge armed and complete itself the
moment CI fires.
