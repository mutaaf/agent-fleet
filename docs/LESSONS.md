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

## 2026-06-05 — a new helper in `bin/fleet` cannot call a function defined LATER in the file when reached via the inline `if [ "$CMD" = "<sub>" ]` dispatcher

While shipping ticket 0034's `replay_one_pr_json_line`, the first cut
called `provenance_json_escape` (defined at line ~6044) to escape the
PR title and rationale into the per-PR JSON line. The new helper sits
near `replay()` (~line 4986) and is invoked through the dispatcher
block `if [ "$CMD" = "replay" ]; then replay "$@"; fi` at ~line 5597
— which runs AT EXECUTION TIME, not at parse time. When the user runs
`fleet replay --batch …`, bash has only parsed up to line 5597 by the
time the dispatcher fires; everything between 5597 and 6044 (including
`provenance_json_escape`) is not yet a known function. Symptom in
`tests/replay-batch.sh` AC#7: stderr carried
`bin/fleet: line 5091: provenance_json_escape: command not found` and
the JSON renderer emitted broken rows. AC#1-#6 passed because they
never reached the JSON-escape codepath (text-mode `replay_batch_
render_text` doesn't escape values). Fix: inline a local copy of the
helper (`replay_batch_json_escape`) defined BEFORE the helper that
needs it. The copy is bit-for-bit identical so the LESSONS 2026-06-03
UTF-8 sign-extension guard remains in force. Cheap defensive habit:
any new helper added near the top of `bin/fleet` that needs a JSON
escaper / parser / formatter from further down the file must either
(a) be moved below the dependency, (b) use one of the
already-early-defined helpers (`preflight_json_escape` at ~line 726
is a safe choice), or (c) duplicate the helper inline with a comment
pointing at the canonical copy. The "use the existing later helper"
shortcut works ONLY when the subcommand dispatcher block sits at the
very bottom of the file — `bin/fleet`'s dispatcher is interleaved
with the function bodies (one inline `if [ "$CMD" = "<sub>" ]` block
per subcommand), so the forward-reference window is narrow but real.

## 2026-06-08 — awk `arr[count] = v; count++` with no `BEGIN { count = 0 }` stores the first value under the empty-string key

While shipping ticket 0038's `diff_paused_hours`, the first cut of the
awk-based ship_paused/ship_resumed pairing helper accumulated events
into two parallel arrays via `events_ts[count] = ep; events_ty[count] =
type; count++` in the per-line block. POSIX awk treats undeclared
scalars as initially the empty string `""`, not 0; the first iteration
therefore stored values under `events_ts[""]` and `events_ty[""]`,
then `count++` numerically incremented `""` to 1 (because `"" + 1 == 1`
in awk's coerce-to-number context). Subsequent iterations stored under
indices 1, 2, 3 — so the FIRST event was silently lost. Symptom in
`tests/diff.sh` AC#1: slug-b's paused-hours metric rendered as 0
instead of the expected 26, because the `ship_paused` event (the
opener of the interval) landed under `events_ts[""]` and never
appeared in the final `for (i=0; i<count; i++)` walk. Only the
`ship_resumed` event under index 1 was visible, and the unmatched
`pause_start = 0` branch silently dropped it. Fix: add an explicit
`BEGIN { count = 0 }` block so the counter is a true integer 0 from
the first per-line block onward. Cheap defensive habit: any awk
script that uses `arr[ctr] = v; ctr++` MUST `BEGIN { ctr = 0 }`,
even when "obviously" the counter starts at zero — POSIX awk's
implicit-empty-string trap is locale-stable, version-stable, and
silent. Same rule applies to `arr[++ctr]` (the increment happens
before the indexing on a pre-increment, but `++""` still yields 1
not 0, just by a different path).

## 2026-06-07 — composing a reader that writes a wall-clock-stamped state file (inbox) into a golden-tested briefing forces a banner-strip pass

While shipping ticket 0036's `fleet morning`, the first cut composed the
INBOX section by indenting the full `bin/fleet inbox` output verbatim
under a `INBOX` heading. `inbox`'s first line is `FLEET INBOX —
<today> (since last run <Nh|Nd> ago)` and its trailing line is
`nothing else owes you a click. last weekly: <Nh|Nd> ago`. Both ages
are computed as `FLEET_INBOX_FAKE_NOW - stat -m
$HOME/.cache/fleet/inbox-state`, where the state file's mtime is
written at REAL wall-clock time by every `inbox` invocation — even
the helper invocations `morning` makes internally to compute the
verdict counters (`morning_count_owes_click`,
`morning_count_paused`, `morning_next_hint`). Symptom in
`tests/morning.sh`'s golden byte-match: the first run produced
`since last run never` / `last weekly: never` locally (no marker yet);
the second run on CI produced `since last run 5h ago` /
`last weekly: 5h ago` (real-CI-clock minus fake_now = 5h on a
2026-06-07 anchor). `diff -u` against the golden flagged both
lines and the test failed despite the underlying composition being
correct. The fix is to make the composed briefing OWN the time-
sensitive header line and STRIP inbox's own banner + trailing line
on render: `awk 'NR<=2 { next } /^nothing else owes you a click\.
last weekly:/ { next } { print "  " $0 }' "$inbox_body"`. The verdict
line at the top of `morning` already encodes the "what changed since
last run" question; the inbox section just needs the five section
blocks, indented. Cheap defensive habit: when composing a reader
that writes a wall-clock-stamped marker file as a side effect, the
composer MUST either (a) STRIP the reader's mtime-dependent lines
(this fix), (b) explicitly touch the marker file's mtime to the
fake clock anchor BEFORE every internal invocation, or (c) avoid
the reader entirely and re-aggregate from the underlying telemetry.
Option (a) is the simplest when the composer owns its own
"freshness" surface (a verdict line, a NEXT footer); options (b)
and (c) only pay off when the composer needs to expose the
reader's freshness to the operator unchanged.

## 2026-06-08 — `IFS=$'\t' read -r f1 f2 f3 f4 f5` shifts fields left when a middle column is empty

While shipping ticket 0039's `lessons_prune_scan`, the first cut
emitted one TSV record per LESSONS paragraph in the shape
`head\tend\torig\texpires\theadline`, where `expires` is an empty
string for paragraphs without an `<!-- EXPIRES: -->` marker. The
dispatcher consumed those records with
`while IFS=$'\t' read -r head end orig expires headline; do …`.
Bash 5.1's `read` builtin, when IFS is set to a NON-whitespace
single character (here `\t`) and the input has two ADJACENT
delimiters (an empty middle field), collapses them into one — so
the empty `expires` field disappeared, the headline shifted left
into `expires`, and `headline` came out empty. Symptom in
`tests/lessons-prune.sh` AC#3: the unmarked paragraph's classifier
warned `paragraph "" has invalid EXPIRES "bootstrap entry without
expiry marker"` and the dry-run table missed two of its columns.
This is documented bash behavior — POSIX says non-whitespace IFS
chars produce one empty field per delimiter, but the bash manual
notes "if the input contains adjacent delimiters that are not in
IFS whitespace, no empty fields are produced" — confusing
phrasing for a confusing rule. Fix: emit a sentinel string (we
used `-`) in the optional column from awk, and map it back to
empty in the dispatcher (`[ "$expires" = "-" ] && expires=""`).
Cheap defensive habit: any TSV-with-`read` pipeline where ANY
middle column can be empty must use a sentinel, NOT a true empty
string. Same trap applies to space-separated columns under
`IFS=' '` and to comma-separated under `IFS=','`. The only
delimiter where `read` "does the right thing" with consecutive
delimiters is whitespace IFS (the default), where adjacent
whitespace IS treated as one separator — but that's the OPPOSITE
problem and only safe when no column can contain spaces.

## 2026-06-11 — macOS BSD `date -j -f '%Y-%m-%d' <date> '+%s'` fills missing time fields with NOW-of-day, not midnight

While shipping ticket 0045's `prompts_suggest_parse_since`, the first
cut accepted `--since YYYY-MM-DD` and resolved the target epoch via
`date -u -j -f '%Y-%m-%d' "$raw" '+%s'`. macOS BSD date, when the
input format omits time components, silently fills the missing fields
with the CURRENT wall-clock time-of-day (not 00:00:00). So
`date -u -j -f '%Y-%m-%d' '2026-06-06' '+%s'` returns the epoch of
"2026-06-06 at HH:MM:SS RIGHT NOW (UTC)" rather than the epoch of
"2026-06-06 00:00:00 UTC". Symptom in `tests/prompts-suggest.sh` AC#4:
the test passed on the first run (when wall-clock matched the fixture's
`FLEET_NOW_OVERRIDE=2026-06-11T12:00:00Z` closely) but FAILED on the
next run minutes later because the parsed epoch had shifted by a few
minutes, dragging the `since` value across the cluster's boundary so a
"none recur ≥3" diagnostic flipped to "no events found in window".
GNU `date -d "$raw"` has the same quirk on some Linux distros (it
defaults to midnight, but the behavior is GNU-version-dependent and not
contractual). Fix: pin the time component explicitly — append
`T00:00:00` to the input and use the full format
`'%Y-%m-%dT%H:%M:%S'`. The resulting epoch is locale- and wall-clock-
stable. Cheap defensive habit: any user-facing `YYYY-MM-DD` arg that
gets passed to `date -j -f` MUST be normalized to a full
`YYYY-MM-DDTHH:MM:SS` (with `00:00:00`) before the date call, and the
format string must list every field. Same rule applies to
`%Y-%m-%dT%H:%M` (missing seconds) and `%Y` (missing month/day) —
anywhere BSD date has to invent a value, it invents NOW-of-day.

## 2026-06-13 — a `*_json_escape`-suffixed wrapper around `preflight_json_escape` trips `fleet self-check` even when the body is just a delegation

While shipping ticket 0048's `recap`, the first cut added a tiny
`recap_json_escape() { preflight_json_escape "$1"; }` wrapper around
the canonical JSON escaper so the recap helpers could call a
locally-named function alongside its sibling `recap_*` family.
`bin/fleet self-check`'s `json-escape-sign-extension` pattern walks
every function matching `^[a-z_][a-z_0-9]*_json_escape\(\)` and
flags those whose BODY does NOT contain the `code -ge 0` UTF-8
sign-extension guard from LESSONS 2026-06-03. The linter explicitly
excludes the canonical `_json_escape` name (no alpha prefix) but
has no notion of "this body is a passthrough wrapper around a
guarded helper" — so `recap_json_escape` trips the rule despite
delegating to a function that does carry the guard. Symptom:
`FLEET_SELF_CHECK_GATE=1 bin/fleet self-check` jumped from 3 hits
(the on-main baseline) to 4 hits on the feature branch, and the
local-gate composition `… && … && … && bin/fleet self-check`
failed at the gate step. Fix: drop the wrapper entirely and call
`preflight_json_escape` directly at each site. The wrapper bought
nothing — the canonical name is already short, no other recap
helper depends on the indirection. Cheap defensive habit: any
NEW shell helper that needs JSON escaping in this kit MUST call
`preflight_json_escape` directly (or `provenance_json_escape` /
the local-inlined copy when the dispatcher forward-reference rule
forces an inline duplicate, per LESSONS 2026-06-05). NEVER add a
`<prefix>_json_escape() { canonical_helper "$@"; }` wrapper — the
self-check pattern cannot see through the call and will flag every
such wrapper as a regression. If a project really needs a
prefixed name for stylistic consistency, the body must duplicate
the guarded escape loop verbatim (then carry its own LESSONS
2026-06-03 reference).

## 2026-06-15 — awk `while (match(s, /pat/)) { s = before repl after }` loops forever when `repl` contains chars that re-match `pat`

While shipping ticket 0053's `portfolio_redact_text`, the first cut
of the dollar-band rewrite was
`while (match(s, /\$[0-9]+(\.[0-9]+)?/)) { s = before band after }`,
where `band` is one of the nine band strings (`<$1`, `~$1`, `~$2`,
`~$5`, …, `~$100`, `>$100`). Every band token CONTAINS a `$<digits>`
substring (`~$5` literally contains `$5`), so the next `match(s, ...)`
call re-found the band's own embedded `$5` and re-banded it forever.
Two awk subprocesses ate 100% CPU for ~5 minutes before I noticed
`tests/portfolio.sh` hadn't returned. Same trap fired separately on the
repo-URL rewrite: the replacement `github.com/<redacted>/<repo>`
contains the literal `github.com` the regex itself matches, so
`while (match(s, /github\.com[:\/]…/))` looped indefinitely. The
slug-name rewrite did NOT trip the trap because `index(rest, name)`
on the not-yet-consumed `rest` advances past the match site each
iteration — it's the `s = before X after; while (match(s, ...))`
shape specifically that bites, because `before` and `after` are
folded back into `s` (the new `s` may now contain matches inside the
replacement). Fix: use a CURSOR-based walk — keep an `out` accumulator
and a `rest` tail, and after each match append `substr(rest, 1,
RSTART - 1) repl` to `out` and slide `rest = substr(rest, RSTART +
RLENGTH)`. Final `s = out rest`. The regex now only ever scans the
not-yet-rewritten tail, so a self-matching `repl` is harmless. Cheap
defensive habit: any time a `while (match(s, /pat/))` block's
replacement string COULD contain characters that match `pat`, switch
to the cursor pattern instead. Quick audit: every band/wrap/decorate
substitution (anything that adds a prefix/suffix to the matched value)
is suspect; pure replacements (e.g. `<path>` for a `/...` regex —
`<path>` has no `/`) are usually safe but using the cursor for
symmetry costs nothing. Distinct from `gsub` which always
short-circuits self-match because it walks the string ONCE.

## 2026-06-15 — `fleet streak --slug X --since 90d` shells out to `date -j -v +1d` once per day; a per-slug reader that calls it inside a `--all` loop pays O(window × N_slugs) subprocess cost

While shipping ticket 0054's `fleet maturity`, step 6's first cut
honored the AC literally: shell out to `fleet streak <slug> --json
--since 14d` and parse the `current` field via inline `node -e`.
That LOOKS like a cheap one-off — until you put it inside
`fleet maturity --all` which walks every discovered slug. For each
slug, streak's per-day awk walker shells out to BSD `date -u -j
-v +1d -f %Y-%m-%d` once per day in the window to advance the
cursor. With 20 fixture slugs and the default 90-day window that
is 1,800 subprocess spawns per `--all` invocation, costing ~54s
on my macOS bash 3.2. Even `--since 14d` is ~5.6s for 20 slugs —
still untenable inside a test budget. The pattern repeats for
ANY reader that shells out to `fleet streak`, `fleet doctor`,
`fleet inbox` etc inside a per-slug loop (look for the shape
`while ... read s_slug ... do; some_reader "$s_slug"; done`).
Fix: replicate the GREEN-DAY predicate inline via one `awk` pass
with awk-internal date arithmetic (Julian-day formula or a small
`prev_day()` function that subtracts a day from a `YYYY-MM-DD`
string in pure awk math). Same predicate, ~50ms per slug instead
of ~600ms. Per LESSONS 2026-06-13 the inline parser is NOT
wrapped in a `*_json_escape`-shaped helper — it's an inline awk.
The wider cheap defensive habit: any new reader that's called
from `--all` paths MUST do its day-walks in pure awk; shelling
out to `date -j -v +1d` per day is fine for one-shot
operator-invoked commands (the streak walker itself stays as-is
because its operator-facing budget is per-invocation), but
becomes O(window × N_slugs) the moment a caller wraps it in a
fleet-wide loop. Quick audit: grep for `date -u -j -v` inside
awk `cmd | getline` blocks AND for `while … read … do; "$FLEET"
streak "$slug" --json` shapes in any new `--all` helper.

## 2026-06-19 — a `local` variable inside a new subcommand whose name matches ANOTHER subcommand's function (e.g. `rank`, `streak`, `stuck`) trips `fleet self-check`'s `dispatcher-forward-reference` pattern as a false positive

While shipping ticket 0060's `flaky()`, the renderer loop used
`local rendered_rows="" rank=0; … rank=$(( rank + 1 ))` to compose the
"rank N <check>" table rows. `fleet self-check`'s
`self_check_ax_dispatcher_forward_reference` walks every function body
and, for each lowercase identifier at line start, looks up whether a
function by that name is defined LATER in the file AND whether the
ENCLOSING function is reached via an inline `if [ "$CMD" = "<sub>" ]; then`
dispatcher block (the forward-reference trap from LESSONS 2026-06-05).
`rank()` IS such a subcommand function (defined at line ~19220) and
`flaky()` IS reached via an inline dispatcher, so the local variable
assignment `rank=...` (NOT a function call) was flagged at line 16480
and the gate composition `… && bin/fleet self-check` jumped from the
on-main baseline of 3 hits to 4. Symptom: an otherwise-clean PR's gate
step fails one over the baseline with no actual runtime trap — the
local var shadows nothing at runtime because bash distinguishes
variable assignments from command invocations syntactically.
Fix: rename the local variable to something the self-check
heuristic cannot mistake for a function call. We used `row_rank`. The
same trap will fire for any new subcommand that uses a local named
`rank`, `streak`, `stuck`, `digest`, `weekly`, `recap`, `incident`,
`diff`, `morning`, `inbox`, `replay`, `tour`, `add`, `flaky`, etc. —
the catalog of subcommand names is the kit's own `^[a-z_]+\(\)`
definition set. Cheap defensive habit when adding a new subcommand:
audit every `local <name>` inside the body against
`grep -E '^[a-z_][a-z_0-9]*\(\) \{' bin/fleet` and rename any
collision to `<prefix>_<name>` (e.g. `row_rank`, `cur_streak`,
`my_diff`). Distinct from LESSONS 2026-05-26 (`tail()` shadows
`/usr/bin/tail` at runtime — a real subprocess-resolution trap)
because this is a self-check FALSE POSITIVE; the runtime behavior is
correct. The self-check pattern could be tightened to require the
matched token to appear as a command invocation (no `=` or `+=`
operator immediately after), but until that lands, the rename is the
one-line fix.

## 2026-06-23 — `sha256(tar -cf <stage>)` is non-deterministic; a self-verifying export manifest MUST hash a content-digest LIST, not the tarball bytes

While shipping ticket 0063's `migrate_compute_sansmanifest_sha256`, the
first cut packed the export's staging directory (sans the manifest
file) into a tmp tarball and hashed THAT: `tar -cf $tmp -C $stage . &&
shasum -a 256 < $tmp`. The same computation runs on both the export
side (to SEAL the manifest with `tarball_sha256`) and the import side
(to VALIDATE the manifest by re-computing and comparing). Symptom in
`tests/migrate.sh` AC #6: the import refused EVERY healthy export with
`migrate: tarball sha256 mismatch (expected <X>, got <Y>)` even though
the file content round-tripped byte-exact through `tar -xzf`. Cause:
`tar`'s ustar header embeds the mtime of each file at archive time,
plus uname/gname/mode bits — so a freshly-built staging dir (mktemp -d
under the export's HOME, mtimes "now") produces a DIFFERENT tarball
sha than the freshly-extracted staging dir on the import side (mktemp
-d under a different HOME, mtimes from `tar -xzf` defaulting to
extract-time). Even on the SAME machine, two consecutive `tar -cf`
passes seconds apart produced different sha256s. The trap also bites
any future attempt to use `--mtime`/`--owner` flags as a portability
fix — BSD `tar` and GNU `tar` disagree on those flag names and the
test harness must run on macOS + Linux. Fix: hash a CONTENT-DIGEST
LIST instead — for every regular file under the stage EXCEPT
`fleet-export.json` (and any sidecar files), emit
`<sorted-rel-path>\t<file-sha256>\n` and hash the resulting stream.
File CONTENTS round-trip byte-exact through `tar -xzf` regardless of
metadata, so the same digest list is reconstructible on both ends.
Cheap defensive habit: any future hash-in-manifest pattern in this
kit MUST hash file CONTENTS, never tar bytes. Same trap applies to
`zip`, `cpio`, and any container format whose headers carry mtimes;
the content-digest-list shape is portable across all of them. (A
deterministic `tar` does exist via `--mtime --owner --group --sort` on
GNU `tar` but NOT on BSD `tar` — and the kit dogfoods macOS where BSD
`tar` ships by default. Don't go down that path.)
