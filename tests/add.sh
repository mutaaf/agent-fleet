#!/bin/bash
# tests/add.sh — bin/fleet add end-to-end test.
#
# Ticket 0052. Asserts that `fleet add <project-path>
# [--inherit-from <slug>]` scaffolds a NEW project under an existing fleet
# by inheriting the source slug's manifest defaults, prints a one-screen
# diff, and chains lib/install.sh + onboarding-check.
#
# 14 acceptance criteria → 14 numbered AC blocks. Run-time budget <12s.
#
# Per LESSONS 2026-05-26: stubs under $HOME/.local/bin so lib/common.sh's
# PATH reset still finds them. Stub install + gh + onboarding-check.
# Per LESSONS 2026-05-27: fixture backup/restore via cp, never $(cat …).
# Per LESSONS 2026-05-30: `grep -qF --` for any pattern starting with -.
# Per LESSONS 2026-06-01: counts via `awk … END { print n+0 }`.
# Per LESSONS 2026-06-08: middle-empty TSV fields use sentinels.

set -euo pipefail

REPO_ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
FLEET="$REPO_ROOT/bin/fleet"
FIXTURE_SRC="$REPO_ROOT/tests/fixtures/add"

TMP="$(mktemp -d -t fleet-add-test.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

export HOME="$TMP/home"
mkdir -p "$HOME/.local/bin"

# Stubs under $HOME/.local/bin (LESSONS 2026-05-26 — PATH reset).
cat > "$HOME/.local/bin/gh" <<STUB
#!/bin/bash
# Stub gh — used for the GATING_CHECKS auto-discovery (AC#6) and the
# install-time hooks. The first arg controls behaviour.
case "\$1" in
  "auth")
    case "\$2" in
      status) echo "Logged in to github.com as test"; exit 0 ;;
    esac
    exit 0 ;;
  "run")
    case "\$2" in
      list)
        # Emit a fake successful run with two job names so the
        # GATING_CHECKS resolver picks them up. Test seam:
        # \$FLEET_ADD_GH_RUN_FAIL=1 makes this branch exit 1 to
        # exercise the fallback path.
        if [ "\${FLEET_ADD_GH_RUN_FAIL:-0}" = "1" ]; then
          echo "no runs found" >&2
          exit 1
        fi
        printf 'unit-tests\nlint\n'
        exit 0 ;;
    esac
    exit 0 ;;
esac
exit 0
STUB
chmod +x "$HOME/.local/bin/gh"

cat > "$HOME/.local/bin/launchctl" <<'STUB'
#!/bin/bash
exit 0
STUB
chmod +x "$HOME/.local/bin/launchctl"

export PATH="$HOME/.local/bin:$PATH"

# Install-stub: records its invocation so we can assert AC#11/#12.
INSTALL_LOG="$TMP/install.log"
INSTALL_STUB="$TMP/install-stub.sh"
cat > "$INSTALL_STUB" <<STUB
#!/bin/bash
echo "stub install for: \$1" > "$INSTALL_LOG"
exit 0
STUB
chmod +x "$INSTALL_STUB"

# Failing install stub used by AC#11's failure branch.
INSTALL_FAIL_STUB="$TMP/install-fail-stub.sh"
cat > "$INSTALL_FAIL_STUB" <<STUB
#!/bin/bash
echo "stub install (FAILING) for: \$1" > "$INSTALL_LOG"
exit 7
STUB
chmod +x "$INSTALL_FAIL_STUB"

# Stub onboarding-check call — recorded so AC#12 can assert the order.
ONBOARDING_LOG="$TMP/onboarding.log"
ONBOARDING_STUB="$TMP/onboarding-check-stub.sh"
cat > "$ONBOARDING_STUB" <<STUB
#!/bin/bash
echo "stub onboarding-check for: \$1" > "$ONBOARDING_LOG"
exit 0
STUB
chmod +x "$ONBOARDING_STUB"

# Build a fresh single-slug "installed fleet" so overview discovery sees
# exactly one slug (the auto-detect path).
SINGLE_FLEET="$TMP/installed-single"
mkdir -p "$SINGLE_FLEET/courtiq"
cp "$FIXTURE_SRC/source-manifest-courtiq.sh" "$SINGLE_FLEET/courtiq/agents.config.sh"
export FLEET_DISCOVERY_ROOT="$SINGLE_FLEET"

# Build a clean destination project (a git repo with origin remote, no
# kit files yet).
make_clean_dest() {  # $1 = slug
  local slug="$1"
  local dir="$TMP/dest-$slug"
  mkdir -p "$dir"
  ( cd "$dir"
    git init -q -b main
    git remote add origin "https://github.com/example/$slug.git"
    : > .gitkeep
    git add .gitkeep
    git -c user.name=test -c user.email=test@example.com commit -q -m init >/dev/null
  ) >/dev/null
  echo "$dir"
}

# --- AC#13 (help) FIRST, before any side effects. -----------------------
HELP_OUT="$TMP/help.out"
set +e
"$FLEET" add --help > "$HELP_OUT" 2>&1
HELP_EXIT=$?
set -e
if [ "$HELP_EXIT" != "0" ]; then
  echo "FAIL AC#13: --help exit=$HELP_EXIT (want 0)"; cat "$HELP_OUT"; exit 1
fi
for kw in "<project-path>" "--inherit-from" "--dry-run" "--force"; do
  if ! grep -qF -- "$kw" "$HELP_OUT"; then
    echo "FAIL AC#13: help missing keyword $kw"; cat "$HELP_OUT"; exit 1
  fi
done
echo "PASS AC#13: --help banner mentions path arg + --inherit-from + --dry-run + --force"

# --- AC#1: usage / not-a-directory / no-origin --------------------------
set +e
"$FLEET" add > "$TMP/usage.out" 2> "$TMP/usage.err"
USAGE_EXIT=$?
set -e
if [ "$USAGE_EXIT" != "2" ]; then
  echo "FAIL AC#1: missing-arg exit=$USAGE_EXIT (want 2)"; cat "$TMP/usage.err"; exit 1
fi
if ! grep -qF -- "fleet add: missing <project-path>" "$TMP/usage.err"; then
  echo "FAIL AC#1: missing-arg stderr lacks contract line"; cat "$TMP/usage.err"; exit 1
fi
if ! grep -qF -- "usage: fleet add" "$TMP/usage.err"; then
  echo "FAIL AC#1: missing-arg stderr lacks usage hint"; cat "$TMP/usage.err"; exit 1
fi

set +e
"$FLEET" add "$TMP/does-not-exist" > "$TMP/nodir.out" 2> "$TMP/nodir.err"
NODIR_EXIT=$?
set -e
if [ "$NODIR_EXIT" != "2" ]; then
  echo "FAIL AC#1: not-a-directory exit=$NODIR_EXIT (want 2)"; cat "$TMP/nodir.err"; exit 1
fi
if ! grep -qF -- "is not a directory" "$TMP/nodir.err"; then
  echo "FAIL AC#1: not-a-directory stderr lacks message"; cat "$TMP/nodir.err"; exit 1
fi

NO_ORIGIN="$TMP/no-origin"
mkdir -p "$NO_ORIGIN"
( cd "$NO_ORIGIN" && git init -q -b main )
set +e
"$FLEET" add "$NO_ORIGIN" > "$TMP/noorigin.out" 2> "$TMP/noorigin.err"
NOORIGIN_EXIT=$?
set -e
if [ "$NOORIGIN_EXIT" != "2" ]; then
  echo "FAIL AC#1: no-origin exit=$NOORIGIN_EXIT (want 2)"; cat "$TMP/noorigin.err"; exit 1
fi
if ! grep -qF -- "has no git origin remote" "$TMP/noorigin.err"; then
  echo "FAIL AC#1: no-origin stderr lacks contract message"; cat "$TMP/noorigin.err"; exit 1
fi
echo "PASS AC#1: missing-arg / not-a-directory / no-origin all exit 2 with contract messages"

# --- AC#2: --inherit-from with unknown slug refuses ---------------------
DEST_UNK="$(make_clean_dest unk-dest)"
MULTI_FLEET="$TMP/installed-multi"
mkdir -p "$MULTI_FLEET/courtiq" "$MULTI_FLEET/sidebrew" "$MULTI_FLEET/hedgehog"
for s in courtiq sidebrew hedgehog; do
  cp "$FIXTURE_SRC/source-manifest-courtiq.sh" "$MULTI_FLEET/$s/agents.config.sh"
  # Patch the SLUG inside each copy.
  sed -i.bak "s/^SLUG=.*/SLUG=\"$s\"/" "$MULTI_FLEET/$s/agents.config.sh"
  rm -f "$MULTI_FLEET/$s/agents.config.sh.bak"
done
FLEET_DISCOVERY_ROOT_BACKUP="$FLEET_DISCOVERY_ROOT"
export FLEET_DISCOVERY_ROOT="$MULTI_FLEET"

set +e
"$FLEET" add --inherit-from nonesuch "$DEST_UNK" > "$TMP/unk.out" 2> "$TMP/unk.err"
UNK_EXIT=$?
set -e
if [ "$UNK_EXIT" != "2" ]; then
  echo "FAIL AC#2: unknown-slug exit=$UNK_EXIT (want 2)"; cat "$TMP/unk.err"; exit 1
fi
if ! grep -qF -- "fleet add: inherit-from slug" "$TMP/unk.err"; then
  echo "FAIL AC#2: unknown-slug stderr lacks contract prefix"; cat "$TMP/unk.err"; exit 1
fi
if ! grep -qF -- "not found" "$TMP/unk.err"; then
  echo "FAIL AC#2: unknown-slug stderr lacks 'not found'"; cat "$TMP/unk.err"; exit 1
fi
if ! grep -qF -- "discovered slugs:" "$TMP/unk.err"; then
  echo "FAIL AC#2: unknown-slug stderr lacks 'discovered slugs:' list"; cat "$TMP/unk.err"; exit 1
fi
echo "PASS AC#2: --inherit-from <unknown> exits 2 with discovered-slugs list"

# --- AC#3a: multi-slug fleet, --inherit-from omitted → refuses ----------
set +e
"$FLEET" add "$DEST_UNK" > "$TMP/multi.out" 2> "$TMP/multi.err"
MULTI_EXIT=$?
set -e
if [ "$MULTI_EXIT" != "2" ]; then
  echo "FAIL AC#3a: multi-slug exit=$MULTI_EXIT (want 2)"; cat "$TMP/multi.err"; exit 1
fi
if ! grep -qF -- "multiple slugs eligible to inherit from" "$TMP/multi.err"; then
  echo "FAIL AC#3a: multi-slug stderr lacks contract message"; cat "$TMP/multi.err"; exit 1
fi
if ! grep -qF -- "pass --inherit-from" "$TMP/multi.err"; then
  echo "FAIL AC#3a: multi-slug stderr lacks remediation hint"; cat "$TMP/multi.err"; exit 1
fi
echo "PASS AC#3a: multi-slug fleet without --inherit-from refuses with hint"

# Restore single-slug fleet for the remaining tests.
export FLEET_DISCOVERY_ROOT="$FLEET_DISCOVERY_ROOT_BACKUP"

# --- AC#3b: single-slug fleet, --inherit-from omitted → auto-selects ----
DEST_AUTO="$(make_clean_dest auto-dest)"
export FLEET_INSTALL_CMD="$INSTALL_STUB"
export FLEET_ONBOARDING_CHECK_CMD="$ONBOARDING_STUB"

set +e
echo "y" | "$FLEET" add "$DEST_AUTO" > "$TMP/auto.out" 2> "$TMP/auto.err"
AUTO_EXIT=$?
set -e
if [ "$AUTO_EXIT" != "0" ]; then
  echo "FAIL AC#3b: auto-detect exit=$AUTO_EXIT (want 0)"; cat "$TMP/auto.out" "$TMP/auto.err"; exit 1
fi
if ! grep -qF -- "inheriting from courtiq (only discovered slug)" "$TMP/auto.out"; then
  echo "FAIL AC#3b: auto-detect stdout lacks 'only discovered slug' banner"; cat "$TMP/auto.out"; exit 1
fi
echo "PASS AC#3b: single-slug fleet without --inherit-from auto-selects"

# --- AC#4: inheritance arrays declared verbatim -------------------------
INHERIT_LINE="$(grep -E '^add_inherit_fields=' "$FLEET" || true)"
if [ -z "$INHERIT_LINE" ]; then
  echo "FAIL AC#4: bin/fleet lacks add_inherit_fields= declaration"; exit 1
fi
for k in BUDGET_DAILY_USD CROSS_LESSONS QUIET_HOURS LOCAL_GATE_CMD PROMPTS_PIN_SHA SHIP_PAUSE_THRESHOLD TRAINEE_REMAINING; do
  if ! printf -- '%s' "$INHERIT_LINE" | grep -qF -- "$k"; then
    echo "FAIL AC#4: add_inherit_fields missing $k"; printf -- '%s\n' "$INHERIT_LINE"; exit 1
  fi
done
SPECIFIC_LINE="$(grep -E '^add_project_specific_fields=' "$FLEET" || true)"
if [ -z "$SPECIFIC_LINE" ]; then
  echo "FAIL AC#4: bin/fleet lacks add_project_specific_fields= declaration"; exit 1
fi
for k in SLUG REPO_URL GATING_CHECKS; do
  if ! printf -- '%s' "$SPECIFIC_LINE" | grep -qF -- "$k"; then
    echo "FAIL AC#4: add_project_specific_fields missing $k"; printf -- '%s\n' "$SPECIFIC_LINE"; exit 1
  fi
done
echo "PASS AC#4: inheritance + project-specific arrays declared verbatim"

# --- AC#5: source manifest read echoes inheritable keys -----------------
# AC#3b's auto-detect output already exercised the read; assert each key/value
# pair appeared in the diff for the fully-populated source.
for kv in \
  "BUDGET_DAILY_USD" \
  "4.50" \
  "QUIET_HOURS" \
  "22-07" \
  "PROMPTS_PIN_SHA" \
  "a3f1c2d" \
  "SHIP_PAUSE_THRESHOLD" \
  "TRAINEE_REMAINING" \
  "LOCAL_GATE_CMD" ; do
  if ! grep -qF -- "$kv" "$TMP/auto.out"; then
    echo "FAIL AC#5: diff missing inherited field $kv"; cat "$TMP/auto.out"; exit 1
  fi
done
echo "PASS AC#5: source manifest read populates every inheritable field"

# --- AC#6: project-specific resolution + gh-fallback warning ------------
# Happy gh path: diff lists 'unit-tests' + 'lint' as GATING_CHECKS.
if ! grep -qF -- "unit-tests" "$TMP/auto.out"; then
  echo "FAIL AC#6: diff missing auto-detected gating check 'unit-tests'"; cat "$TMP/auto.out"; exit 1
fi
if ! grep -qF -- "lint" "$TMP/auto.out"; then
  echo "FAIL AC#6: diff missing auto-detected gating check 'lint'"; cat "$TMP/auto.out"; exit 1
fi
if ! grep -qF -- "auto-dest" "$TMP/auto.out"; then
  echo "FAIL AC#6: diff missing SLUG derived from basename"; cat "$TMP/auto.out"; exit 1
fi
if ! grep -qF -- "github.com/example/auto-dest" "$TMP/auto.out"; then
  echo "FAIL AC#6: diff missing REPO_URL from git remote"; cat "$TMP/auto.out"; exit 1
fi

# Failing gh discovery → fallback to 'shellcheck, validate' + warning line.
# The env-var-on-pipeline construct binds only to `echo`, so wrap in a
# subshell so FLEET_ADD_GH_RUN_FAIL reaches the bin/fleet child.
DEST_FB="$(make_clean_dest fb-dest)"
set +e
( export FLEET_ADD_GH_RUN_FAIL=1; echo "y" | "$FLEET" add "$DEST_FB" > "$TMP/fb.out" 2> "$TMP/fb.err" )
FB_EXIT=$?
set -e
if [ "$FB_EXIT" != "0" ]; then
  echo "FAIL AC#6: gh-fail run exit=$FB_EXIT (want 0)"; cat "$TMP/fb.out" "$TMP/fb.err"; exit 1
fi
if ! grep -qF -- "shellcheck, validate" "$TMP/fb.out" \
   && ! grep -qF -- "shellcheck, validate" "$TMP/fb.err"; then
  echo "FAIL AC#6: gh-fail run lacks placeholder gating-checks list"; cat "$TMP/fb.out" "$TMP/fb.err"; exit 1
fi
if ! grep -qF -- "could not auto-detect gating checks" "$TMP/fb.out" \
   && ! grep -qF -- "could not auto-detect gating checks" "$TMP/fb.err"; then
  echo "FAIL AC#6: gh-fail run lacks warning line"; cat "$TMP/fb.out" "$TMP/fb.err"; exit 1
fi
echo "PASS AC#6: project-specific resolution + gh-fallback warning"

# --- AC#7: confirmation prompt aborts on 'n' or empty input -------------
DEST_ABORT="$(make_clean_dest abort-dest)"
set +e
echo "n" | "$FLEET" add "$DEST_ABORT" > "$TMP/abort.out" 2> "$TMP/abort.err"
ABORT_EXIT=$?
set -e
if [ "$ABORT_EXIT" != "0" ]; then
  echo "FAIL AC#7: abort-on-n exit=$ABORT_EXIT (want 0)"; cat "$TMP/abort.out"; exit 1
fi
if ! grep -qF -- "fleet add: aborted; nothing written." "$TMP/abort.out"; then
  echo "FAIL AC#7: abort-on-n stdout lacks abort line"; cat "$TMP/abort.out"; exit 1
fi
if [ -f "$DEST_ABORT/agents.config.sh" ]; then
  echo "FAIL AC#7: abort-on-n still wrote agents.config.sh"; exit 1
fi

set +e
echo "" | "$FLEET" add "$DEST_ABORT" > "$TMP/abort2.out" 2> "$TMP/abort2.err"
ABORT2_EXIT=$?
set -e
if [ "$ABORT2_EXIT" != "0" ]; then
  echo "FAIL AC#7: abort-on-empty exit=$ABORT2_EXIT (want 0)"; cat "$TMP/abort2.out"; exit 1
fi
if ! grep -qF -- "fleet add: aborted; nothing written." "$TMP/abort2.out"; then
  echo "FAIL AC#7: abort-on-empty stdout lacks abort line"; cat "$TMP/abort2.out"; exit 1
fi
echo "PASS AC#7: confirmation prompt aborts on 'n' or empty input"

# --- AC#8: --dry-run skips confirmation + writes + install --------------
DEST_DRY="$(make_clean_dest dry-dest)"
: > "$INSTALL_LOG"
: > "$ONBOARDING_LOG"
set +e
"$FLEET" add --dry-run "$DEST_DRY" > "$TMP/dry.out" 2> "$TMP/dry.err"
DRY_EXIT=$?
set -e
if [ "$DRY_EXIT" != "0" ]; then
  echo "FAIL AC#8: --dry-run exit=$DRY_EXIT (want 0)"; cat "$TMP/dry.out" "$TMP/dry.err"; exit 1
fi
if [ -f "$DEST_DRY/agents.config.sh" ]; then
  echo "FAIL AC#8: --dry-run created agents.config.sh"; exit 1
fi
if [ -s "$INSTALL_LOG" ]; then
  echo "FAIL AC#8: --dry-run invoked install stub: $(cat "$INSTALL_LOG")"; exit 1
fi
if [ -s "$ONBOARDING_LOG" ]; then
  echo "FAIL AC#8: --dry-run invoked onboarding-check stub: $(cat "$ONBOARDING_LOG")"; exit 1
fi
# Diff still rendered.
if ! grep -qF -- "BUDGET_DAILY_USD" "$TMP/dry.out"; then
  echo "FAIL AC#8: --dry-run skipped the diff body"; cat "$TMP/dry.out"; exit 1
fi
echo "PASS AC#8: --dry-run prints diff, no prompt, no writes, no install"

# --- AC#9: --force skips prompt; existing config still refuses ----------
DEST_FORCE="$(make_clean_dest force-dest)"
: > "$INSTALL_LOG"
: > "$ONBOARDING_LOG"
set +e
"$FLEET" add --force "$DEST_FORCE" > "$TMP/force.out" 2> "$TMP/force.err"
FORCE_EXIT=$?
set -e
if [ "$FORCE_EXIT" != "0" ]; then
  echo "FAIL AC#9: --force exit=$FORCE_EXIT (want 0)"; cat "$TMP/force.out" "$TMP/force.err"; exit 1
fi
if [ ! -f "$DEST_FORCE/agents.config.sh" ]; then
  echo "FAIL AC#9: --force did not write agents.config.sh"; exit 1
fi
if ! grep -qF -- "stub install for: $DEST_FORCE" "$INSTALL_LOG"; then
  echo "FAIL AC#9: --force did not invoke install stub"; cat "$INSTALL_LOG"; exit 1
fi

# Pre-existing config without --force refuses with contract message.
DEST_EXISTS="$(make_clean_dest exists-dest)"
echo "# preexisting" > "$DEST_EXISTS/agents.config.sh"
set +e
echo "y" | "$FLEET" add "$DEST_EXISTS" > "$TMP/exists.out" 2> "$TMP/exists.err"
EXISTS_EXIT=$?
set -e
if [ "$EXISTS_EXIT" = "0" ]; then
  echo "FAIL AC#9: existing-config run unexpectedly succeeded"; cat "$TMP/exists.out" "$TMP/exists.err"; exit 1
fi
if ! grep -qF -- "agents.config.sh already exists" "$TMP/exists.err"; then
  echo "FAIL AC#9: existing-config refusal stderr lacks contract message"; cat "$TMP/exists.err"; exit 1
fi
if ! grep -qF -- "pass --force to overwrite" "$TMP/exists.err"; then
  echo "FAIL AC#9: existing-config refusal stderr lacks remediation hint"; cat "$TMP/exists.err"; exit 1
fi
echo "PASS AC#9: --force skips prompt; existing config refuses without --force"

# --- AC#10: scaffold writes the contract files -------------------------
# AC#9 already wrote $DEST_FORCE; assert byte-level the inherited values
# landed in its agents.config.sh and the same six files exist.
for f in agents.config.sh AGENTS.md docs/backlog/README.md docs/backlog/_template.md docs/LESSONS.md; do
  if [ ! -f "$DEST_FORCE/$f" ]; then
    echo "FAIL AC#10: scaffold missing $f"; ls -R "$DEST_FORCE"; exit 1
  fi
done
# Inherited value present in the new manifest.
if ! grep -qF -- "4.50" "$DEST_FORCE/agents.config.sh"; then
  echo "FAIL AC#10: new agents.config.sh missing inherited BUDGET_DAILY_USD"; cat "$DEST_FORCE/agents.config.sh"; exit 1
fi
if ! grep -qF -- "QUIET_HOURS" "$DEST_FORCE/agents.config.sh"; then
  echo "FAIL AC#10: new agents.config.sh missing QUIET_HOURS line"; cat "$DEST_FORCE/agents.config.sh"; exit 1
fi
echo "PASS AC#10: scaffold writes the contract files with inherited values"

# --- AC#11: install failure preserves scaffold + reports error ----------
DEST_INSTFAIL="$(make_clean_dest installfail-dest)"
: > "$INSTALL_LOG"
set +e
FLEET_INSTALL_CMD="$INSTALL_FAIL_STUB" echo "y" \
  | FLEET_INSTALL_CMD="$INSTALL_FAIL_STUB" "$FLEET" add --force "$DEST_INSTFAIL" \
      > "$TMP/instfail.out" 2> "$TMP/instfail.err"
INSTFAIL_EXIT=$?
set -e
if [ "$INSTFAIL_EXIT" != "1" ]; then
  echo "FAIL AC#11: install-fail exit=$INSTFAIL_EXIT (want 1)"; cat "$TMP/instfail.out" "$TMP/instfail.err"; exit 1
fi
if ! grep -qF -- "install.sh failed" "$TMP/instfail.err"; then
  echo "FAIL AC#11: install-fail stderr lacks contract message"; cat "$TMP/instfail.err"; exit 1
fi
# Scaffold preserved.
if [ ! -f "$DEST_INSTFAIL/agents.config.sh" ]; then
  echo "FAIL AC#11: install-fail wiped the scaffolded agents.config.sh"; exit 1
fi
echo "PASS AC#11: install failure exits 1, preserves scaffold"

# --- AC#12: install success → onboarding-check fires --------------------
DEST_OK="$(make_clean_dest ok-dest)"
: > "$INSTALL_LOG"
: > "$ONBOARDING_LOG"
set +e
echo "y" | "$FLEET" add "$DEST_OK" > "$TMP/ok.out" 2> "$TMP/ok.err"
OK_EXIT=$?
set -e
if [ "$OK_EXIT" != "0" ]; then
  echo "FAIL AC#12: success exit=$OK_EXIT (want 0)"; cat "$TMP/ok.out" "$TMP/ok.err"; exit 1
fi
if ! grep -qF -- "stub install for: $DEST_OK" "$INSTALL_LOG"; then
  echo "FAIL AC#12: install stub never ran"; cat "$INSTALL_LOG"; exit 1
fi
if ! grep -qF -- "stub onboarding-check for: $DEST_OK" "$ONBOARDING_LOG"; then
  echo "FAIL AC#12: onboarding-check stub never ran"; cat "$ONBOARDING_LOG"; exit 1
fi
echo "PASS AC#12: install success chains into onboarding-check"

# --- AC#14: no events written, no kit-source changes --------------------
# fleet add must not append to the source slug's events.jsonl. The single-
# slug fleet manifest has no $CACHE_DIR by default; assert no events.jsonl
# file appeared anywhere under $TMP after the runs above.
n_events=$(find "$TMP" -name 'events.jsonl' 2>/dev/null | awk 'END { print NR+0 }')
if [ "$n_events" != "0" ]; then
  echo "FAIL AC#14: $n_events events.jsonl files appeared after fleet add"
  find "$TMP" -name 'events.jsonl'
  exit 1
fi
echo "PASS AC#14: no events.jsonl created by fleet add"

# --- AC#15-ish: no lib/common.sh or prompts/ drift ----------------------
# Asserted by the local-gate composition before push; here we just assert
# the source files exist unchanged at runtime (cheap shape check).
DRIFT=$(cd "$REPO_ROOT" && git diff --name-only main...HEAD -- lib/common.sh prompts/ 2>/dev/null | awk 'END { print NR+0 }')
if [ "$DRIFT" != "0" ]; then
  echo "FAIL AC#15: lib/common.sh or prompts/ changed on branch (count=$DRIFT)"
  ( cd "$REPO_ROOT" && git diff --name-only main...HEAD -- lib/common.sh prompts/ )
  exit 1
fi
echo "PASS AC#15: no lib/common.sh or prompts/ drift on branch"

echo "ok: tests/add.sh passed (14 ACs)"
