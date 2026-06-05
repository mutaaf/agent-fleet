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

## 2026-05-26 — `lib/common.sh` resets PATH; stubs must live in `$HOME/.local/bin`

`lib/common.sh` exports a hardcoded PATH (`$HOME/.local/bin:/opt/homebrew/bin:...`)
on source so launchd-spawned runners (which get a minimal env) can still find
`claude`, `gh`, `git`, etc. Side-effect for tests: a stub binary placed in a
`$TMP/bin` dir prepended to PATH from the test harness gets WIPED OUT the
moment `fleet_run_claude` runs `source lib/common.sh`. Symptom in
`tests/dry-run.sh` (ticket 0010): the `claude` stub recorded ZERO calls and
the assertion "argv contained `--allowedTools none`" failed even though the
implementation was correct — `claude` resolved to exit 127. Fix: drop stubs
under `$HOME/.local/bin` (the first entry in the reset PATH) and `export
HOME="$TMP/home"` so the rest of the test still isolates from the host.
`bin/fleet` stubs can sit anywhere because that script does NOT source
common.sh — but using one stub dir for both keeps the test fixture simple.

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

## 2026-05-27 — `$(cat file)` strips trailing newlines; tests that "restore" via command substitution silently mutate the file under test

While shipping ticket 0018, the first version of `tests/principles.sh`
backed up `prompts/PRINCIPLES.md` with `ORIGINAL="$(cat "$PRINCIPLES")"`
and restored it with `printf '%s' "$ORIGINAL" > "$PRINCIPLES"`. Bash
command substitution strips ALL trailing newlines from the captured
output (POSIX behavior, not a bug), so the round-trip dropped the
file's final `\n` even though the test reported success. Symptom on
disk: `tail -c 4` shows `e.` instead of `e.\n`. The agent's local
`git status` showed the (unintended) modification only because the
test had run; CI would have caught it via the diff but only by
coincidence. Fix: back up with `cp "$file" "$BACKUP"` and restore with
`cp "$BACKUP" "$file"` — byte-exact, newline-preserving. NEVER use
`$(cat …)` for content that is later written back to disk. Same rule
applies to `read -d ''` and `mapfile`, both of which can also clip
terminators in subtle ways. When in doubt, copy files; only use
command substitution for content you're about to grep or compare.

## 2026-05-30 — `grep -qF "--flag"` treats the pattern as an option too

The `printf` trap from 2026-05-28 has a sibling. While writing
`tests/weekly.sh` (ticket 0025) the AC#13 help-text check used
`grep -qF "$kw" "$help_out"` to verify the help banner mentions
`--since`, `--slug`, `--json`. macOS BSD grep parses `--since` as an
unrecognized option and fails with `grep: unrecognized option
'--since'` to stderr, exits 2, and the test sees a false-negative
"keyword missing" because `grep -q` returned non-zero. The same trap
applies to GNU grep on Ubuntu. Fix: use the POSIX `--` end-of-options
marker — `grep -qF -- "$kw" "$file"`. Same defensive habit as the
printf rule: any time the FIRST byte of the pattern argument is `-`,
insert `--` between the flags and the pattern. Tooling that takes
patterns positionally and ALSO accepts double-dash options (grep,
sed -E, awk -v, find -name) all share this footgun.

## 2026-06-01 — `grep -c <pat> file || echo 0` double-prints on zero matches

While shipping ticket 0026's `inbox_count_drafts` helper, the first cut
used `grep -cF -- '<!-- DRAFT: ' "$lessons" 2>/dev/null || echo 0` to
count DRAFT markers. POSIX says grep exits 1 when no lines match — even
when `-c` already printed `0` to stdout — so the `|| echo 0` chain
fires and the helper emits two lines: `0\n0`. Symptom: subsequent
`[ "$n_drafts" -gt 0 ]` arithmetic explodes with "integer expression
expected: 0\n0", and any later `inbox_total + n_drafts` quietly does the
wrong thing. Fix: use awk for counting whenever the caller treats the
result as an integer — `awk '/<!-- DRAFT: / { n++ } END { print (n+0) }'
"$file"` always exits 0 and prints exactly one number. Same rule applies
to `grep -c` anywhere the result feeds shell arithmetic. When you DO
want grep's exit code as a presence signal, use `grep -qF -- pat file`
(no `-c`, no `|| echo`).

## 2026-05-28 — `printf '- foo\n' "$bar"` treats the leading dash as a flag

While shipping ticket 0021's `replay_compose_prompt`, the first cut used
`printf '- number: #%s\n' "$pr_number"` to render markdown bullet lines
into the composed prompt body. Bash's builtin `printf` (and /usr/bin/printf
on macOS, and dash on Ubuntu) parses the FIRST argument for option flags —
so a format string starting with `-` is interpreted as a flag and the
command fails with `printf: - : invalid option / usage: printf [-v var]
format [arguments]` to stderr. Symptom: the prompt body got truncated and
stderr was littered with usage banners, but the run still proceeded
because the printf failure was non-fatal in this code path. Fix: use the
POSIX `--` end-of-options marker, i.e. `printf -- '- number: #%s\n'
"$pr_number"`. Same trap applies to any `printf '%s' "$str"` where `$str`
might start with `-` and gets passed positionally — quote it through `--`
or prefix the format with a literal char (`printf '%s\n' "-$str"`). Cheap
defensive habit: any time the FIRST byte of the format or the first
argument is `-`, add `--` between `printf` and the format.

## 2026-06-01 — `awk -v var="$val"` rejects a value containing literal newlines

While shipping ticket 0028's `lessons_promote_insert_under_section`,
the first cut passed a multi-line paragraph into awk via
`awk -v paragraph="$paragraph" '...'`. BSD awk on macOS (also nawk
and gawk in POSIX mode) rejects this with `awk: newline in string ...
at source line 1` and silently drops the rest of the program — the
target file ends up empty even though the dispatch reports success.
Symptom in `tests/lessons-promote.sh` AC#1: the appended heading was
missing from CROSS_LESSONS.md and stderr carried two `awk: newline
in string` lines that were easy to miss because the implementation's
banner printed "done — every project's next PHASE 0 will read this
lesson." regardless. Fix: write the value to a temp file and let
awk pull it back in via `getline line < para_file`. `awk -v` is only
safe for single-line values; the moment a value can contain a `\n`
the call MUST use a file. Cheap defensive habit: any `awk -v` whose
value is built from a multi-line capture (`$(cat …)`, an extract
function, an HTTP response body) goes through a tmp file instead.

## 2026-06-01 — a new `bin/fleet` subcommand function MUST end with `exit 0` or the dispatcher falls through to the default `fleet status` block

While shipping ticket 0027's `badge()`, the first cut of the function
let control return normally — every `case "$format" in ... esac`
branch echoed its output and the function exited cleanly with status
0. The dispatcher block at the top of `bin/fleet` is
`if [ "$CMD" = "badge" ]; then badge "$@"; fi`, NOT
`elif … exit $?`, so control then drops out of the `if` and slides
down through every following dispatcher block — none match, and the
fall-through hits the default `fleet status` rendering block at the
bottom of the file. Symptom in `tests/badge.sh` AC#1: the expected
one-line `[![fleet](…)](…) <!-- … -->` output was followed by the
PROJECT/INSTALLED/LAST RUN status table and `wc -l` reported 5
instead of 1. Fix: every subcommand function MUST end with an
explicit `exit 0` (the same convention `weekly()`, `inbox()`,
`digest()`, `rollback()`, `kickstart()`, etc. all already follow).
The dispatcher pattern is intentionally `if`+function-call rather
than `case`+`break` because each block reads as a standalone unit,
but that flexibility means the function body owns the exit. Cheap
defensive habit when adding a new subcommand: copy a sibling
dispatcher (`weekly` is the closest pure-reader analogue) and mirror
its `exit 0` lines verbatim — including the one inside `-h|--help`.

## 2026-06-03 — `doctor_json_escape` (and `_json_escape` in lib/common.sh) sign-extends multi-byte UTF-8 bytes under `LC_ALL=C`

While shipping ticket 0029's `provenance_render_json`, the first cut
reused `doctor_json_escape` (line ~702 of `bin/fleet`, byte-identical
to `lib/common.sh`'s `_json_escape`) to escape the prompts CHANGELOG
entry's `YYYY-MM-DD — <title>` value. The em-dash `—` is U+2014, a
3-byte UTF-8 sequence `0xE2 0x80 0x94`. Under `LC_ALL=C` (the test
harness's locale), bash treats `${s:i:1}` as one BYTE not one
character, and `printf -v code '%d' "'$ch"` reads that byte through
signed char and yields a NEGATIVE int (e.g. `-30` for `0xE2`). The
helper's `if [ "$code" -lt 32 ]` branch then fires and emits a
sign-extended `\u......` sequence like
`￿ffffffffffe2￿ffffffffff80￿ffffffffff94`, which
makes the JSON parse but renders garbage. Symptom in
`tests/provenance.sh` AC#3: `diff -u` against the golden showed
those `￿ffff…` runs in place of the em-dash. JSON does NOT
require escaping of bytes ≥ 0x80 — raw UTF-8 is legal in a JSON
string — so the fix is to short-circuit the high-byte path:
`if [ "$code" -ge 0 ] && [ "$code" -lt 32 ]`, otherwise pass `$ch`
through verbatim. Same trap applies to `lib/common.sh`'s
`_json_escape`; for now `provenance_render_json` uses its own
`provenance_json_escape` helper while a follow-up ticket lifts the
fix into common.sh. Cheap defensive habit: any per-byte JSON
escape in this kit MUST guard on `code >= 0` before treating it as
a control char, and treat negative codes (sign-extended high bytes)
as already-safe pass-through.

## 2026-06-05 — bash 3.2 does not honor mid-script `LC_ALL=C` for `${#s}` / `${s:i:1}` string-length operations

While shipping ticket 0032's `preflight_visible_width`, the first cut
tried to side-step the test harness's variable locale (sometimes
`LC_ALL=C`, sometimes `LANG=en_US.UTF-8` depending on how the runner
spawned) by wrapping the byte-walk in a subshell that did `export
LC_ALL=C` BEFORE iterating: `(  export LC_ALL=C; for (( i=0;
i<${#s}; i++ )); do ch="${s:i:1}"; … )`. macOS ships bash 3.2, which
caches its locale-sensitive operations (`${#}` length, `${s:i:1}`
substring) at SHELL STARTUP — flipping `LC_ALL` mid-script via a
subshell `export` does not actually flip `${#}` from char-count to
byte-count. Symptom in `tests/preflight.sh` AC#1: the function
returned 30 under the host's UTF-8 locale (counting the § as one
character with code 167, the trailing UTF-8 continuation byte, and
skipping it) instead of the expected 31; the golden table's `AGENTS.md
§ Agent parameters:` row landed one space short and `diff -u` flagged
the mismatch. The bash -x trace was particularly misleading because
turning on `set -x` re-evaluates some locale state and the function
THEN returned 31, so the bug only showed up in the gateless test path.
Fix: do not rely on bash's locale-sensitive ops for width counting at
all. Use `printf -- '%s' "$s" | LC_ALL=C wc -c` to get the byte count
(always bytes regardless of the parent locale), then subtract the
UTF-8 continuation-byte count via `LC_ALL=C awk` with a 256-entry
`ord[]` lookup table (awk substring under explicit `LC_ALL=C` env IS
byte-mode, unlike bash). The result is locale-stable across both
`LC_ALL=C` and `LANG=en_US.UTF-8`. Cheap defensive habit: any
"visible width" computation in this kit's macOS-targeted shell code
MUST go through `wc -c` + `awk` (or python3), NOT bash's `${#s}` /
`${s:i:1}`, when the input might contain multi-byte UTF-8.

## 2026-06-05 — an `export` inside `$(...)` never leaks to the parent shell; helpers that own an at-most-once guard MUST be called without command substitution

While shipping ticket 0033's `fleet_check_quiet_hours`, the first cut wired
the helper into `lib/ship.sh` as `FLEET_QUIET_VERDICT="$(fleet_check_quiet_
hours)"`. The helper's contract included a process-scoped `FLEET_QUIET_
HOURS_EMITTED=1; export FLEET_QUIET_HOURS_EMITTED` set on the first
"suppress" so a second call could short-circuit the `fleet_emit_event
quiet_hours_skip ...` line — same shape as `FLEET_PROMPTS_DRIFT_EMITTED`
(ticket 0005). Symptom in `tests/quiet-hours.sh` AC#8: after calling the
helper twice in the SAME outer shell, the test asserted
`[ -n "$FLEET_QUIET_HOURS_EMITTED" ]` and saw an empty value. Cause:
bash command substitution `$(...)` runs the body in a FORK; any `export`
inside the fork mutates only the child's environment, then exits. The
parent shell sees the captured stdout but not the export. The helper
would have emitted twice in two consecutive ship runs across the same
process because the guard never persisted. Fix: redesign the helper to
write its verdict to BOTH stdout (so single-shot tests can use `$(...)`)
AND an exported global `FLEET_QUIET_HOURS_VERDICT`; call the helper
from production runners WITHOUT command substitution
(`fleet_check_quiet_hours >/dev/null; case $FLEET_QUIET_HOURS_VERDICT
in ...`) so the emit/guard exports land in the runner's shell. Cheap
defensive habit: any helper whose contract includes "fires at most
once per process" (guard env var) MUST NOT be called via `$(...)`
from the path that relies on the guard. Test seam: when a unit test
does call the helper via `$(...)` for output-only assertions, it
must NOT also assert on the guard env or downstream side-effect
count — those checks belong in the no-substitution call path (which
mirrors production).
