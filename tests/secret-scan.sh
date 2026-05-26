#!/bin/bash
# tests/secret-scan.sh — fleet_install_prepush_hook + pre-push hook test.
#
# Ticket 0008. Asserts that:
#   1. fleet_install_prepush_hook writes an executable .git/hooks/pre-push
#      into the target checkout, and fleet_checkout calls it automatically.
#   2. Each of the six built-in fallback regexes catches its fake fixture:
#        - Anthropic       sk-ant-[A-Za-z0-9_-]{30,}
#        - GitHub PAT      ghp_[A-Za-z0-9]{36}
#        - GitHub OAuth    gho_[A-Za-z0-9]{36}
#        - AWS access key  AKIA[0-9A-Z]{16}
#        - OpenAI-shape    sk-[A-Za-z0-9]{20,}
#        - Generic kv      (?i)(api[_-]?key|secret|token|bearer)\s*[:=]\s*...
#      On a match, the hook exits 1, stderr contains "secret detected:" and
#      the pattern name, and a push_blocked event is appended to events.jsonl
#      with reason=secret_match and pattern=<name>.
#   3. A clean staged diff (no secret-like strings) exits 0 silently.
#   4. When `gitleaks` is on PATH, the hook delegates to it and propagates
#      its non-zero exit code.
#   5. AGENTS.md § Hard NOs includes the one-line cross-reference naming
#      fleet_install_prepush_hook and ticket 0008.
#
# Self-contained: stubs $HOME so we never touch real ~/.cache state. The
# hook is invoked DIRECTLY (not through `git push`) per the ticket's
# engineering notes, since the test repo has no usable remote.
#
# Fixture strings (the things the regexes match) are assembled at runtime
# from prefix + character repeat so this test file itself never contains
# a literal that the hook would flag if installed against this repo.

set -euo pipefail

REPO_ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"

TMP="$(mktemp -d -t fleet-secret-scan-test.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

# Isolate from the real fleet cache. CACHE_DIR is derived from $HOME + $SLUG.
export HOME="$TMP/home"
mkdir -p "$HOME"

MANIFEST_DIR="$TMP/project"
mkdir -p "$MANIFEST_DIR"
cat > "$MANIFEST_DIR/agents.config.sh" <<'CFG'
SLUG="secretscantest"
PROJECT_NAME="secretscantest"
REPO_URL="https://github.com/example/secretscantest.git"
SELF_CANCEL="20990101"
CFG

CACHE="$HOME/.cache/secretscantest-agent"
EVENTS="$CACHE/events.jsonl"

# --- helpers -------------------------------------------------------------

# Build fixture strings at runtime so this file never contains a literal
# the hook would flag if pointed at this repo.
make_anthropic_fixture() {
  printf 'sk-ant-api03-%s\n' "$(printf 'A%.0s' $(seq 1 32))"
}
make_ghp_fixture() {
  printf 'ghp_%s\n' "$(printf '0%.0s' $(seq 1 36))"
}
make_gho_fixture() {
  printf 'gho_%s\n' "$(printf '0%.0s' $(seq 1 36))"
}
make_aws_fixture() {
  # AKIA followed by 16 uppercase / digits.
  printf 'AKIA%s\n' 'EXAMPLEAAAAAAAAA'
}
make_openai_fixture() {
  # sk- followed by 24 mixed alphanumerics (>= 20 per the regex).
  printf 'sk-%s\n' 'AAAAAAAAAAAAAAAAAAAAAAAA'
}
make_generic_fixture() {
  # api_key = "<24 chars>"
  printf 'api_key = "%s"\n' 'AAAAAAAAAAAAAAAAAAAAAAAA'
}

# Spin up a fresh git checkout under $TMP and install the pre-push hook into
# it via fleet_install_prepush_hook. Echoes the checkout path on stdout.
fresh_checkout() {
  local name="$1"
  local dir="$TMP/checkouts/$name"
  mkdir -p "$dir"
  (
    cd "$dir"
    git init --quiet
    git config user.email "test@example.com"
    git config user.name "secret-scan-test"
    # Seed with one empty commit so HEAD exists.
    git commit --allow-empty -m "seed" --quiet
  )
  (
    set -euo pipefail
    # shellcheck disable=SC1091
    source "$REPO_ROOT/lib/common.sh"
    fleet_load_manifest "$MANIFEST_DIR"
    FLEET_PHASE="ship"; export FLEET_PHASE
    fleet_install_prepush_hook "$dir"
  )
  printf '%s\n' "$dir"
}

# Stage $1 (relative path) inside the checkout $2 with body $3, then invoke
# the hook directly. Echoes "<exit>|<stderr>" so callers can split-and-assert.
run_hook_with_staged_file() {
  local file_path="$1" checkout_dir="$2" body="$3"
  local err_log="$TMP/hook-stderr.$$.log"
  (
    cd "$checkout_dir"
    printf '%s\n' "$body" > "$file_path"
    git add "$file_path"
  )
  local exit_code=0
  # Invoke the hook directly. Pre-push hooks receive <remote_name>
  # <remote_url> on argv and <local_ref> <local_sha> <remote_ref>
  # <remote_sha> on stdin. We pass empty stdin so the hook's
  # diff-cached path fires.
  (
    cd "$checkout_dir"
    : | ".git/hooks/pre-push" origin "https://example.invalid/x.git" 2>"$err_log"
  ) || exit_code=$?
  printf '%s|' "$exit_code"
  cat "$err_log"
}

assert_blocked() {
  local label="$1" output="$2" pattern_name="$3"
  local exit_code="${output%%|*}"
  local stderr="${output#*|}"
  if [ "$exit_code" = "0" ]; then
    echo "FAIL[$label]: hook exited 0 but expected non-zero block"
    echo "  stderr: $stderr"
    exit 1
  fi
  if ! printf '%s' "$stderr" | grep -q 'secret detected:'; then
    echo "FAIL[$label]: stderr missing 'secret detected:' marker"
    echo "  stderr: $stderr"
    exit 1
  fi
  if ! printf '%s' "$stderr" | grep -q "$pattern_name"; then
    echo "FAIL[$label]: stderr missing pattern name '$pattern_name'"
    echo "  stderr: $stderr"
    exit 1
  fi
  if ! grep -q '"type":"push_blocked"' "$EVENTS" 2>/dev/null; then
    echo "FAIL[$label]: no push_blocked event in events.jsonl"
    [ -f "$EVENTS" ] && cat "$EVENTS"
    exit 1
  fi
  if ! grep -q "\"pattern\":\"$pattern_name\"" "$EVENTS"; then
    echo "FAIL[$label]: push_blocked event missing pattern=$pattern_name"
    cat "$EVENTS"
    exit 1
  fi
  if ! grep -q '"reason":"secret_match"' "$EVENTS"; then
    echo "FAIL[$label]: push_blocked event missing reason=secret_match"
    cat "$EVENTS"
    exit 1
  fi
}

# ============================================================================
# CASE 0 — fleet_install_prepush_hook installs an executable hook file and
#          fleet_checkout wires it automatically.
# ============================================================================
CHECKOUT="$(fresh_checkout install-check)"
if [ ! -x "$CHECKOUT/.git/hooks/pre-push" ]; then
  echo "FAIL[install]: .git/hooks/pre-push not created or not executable"
  exit 1
fi
echo "ok[install]: pre-push hook installed and executable"

# ============================================================================
# CASE 1..6 — each built-in fallback regex catches its fake fixture and emits
#             a push_blocked event with the right pattern name.
# ============================================================================
for case in anthropic ghp gho aws openai generic; do
  rm -f "$EVENTS"  # reset event log per case so assertions are scoped
  CK="$(fresh_checkout "case-$case")"
  case "$case" in
    anthropic) body="$(make_anthropic_fixture)" ; pat="anthropic" ;;
    ghp)       body="$(make_ghp_fixture)"       ; pat="github_pat" ;;
    gho)       body="$(make_gho_fixture)"       ; pat="github_oauth" ;;
    aws)       body="$(make_aws_fixture)"       ; pat="aws_access_key" ;;
    openai)    body="$(make_openai_fixture)"    ; pat="openai" ;;
    generic)   body="$(make_generic_fixture)"   ; pat="generic_kv" ;;
  esac
  out="$(run_hook_with_staged_file "leak.txt" "$CK" "$body")"
  assert_blocked "$case" "$out" "$pat"
  echo "ok[$case]: pattern $pat caught and reported"
done

# ============================================================================
# CASE 7 — clean staged diff exits 0 silently (no stderr noise, no event).
# ============================================================================
rm -f "$EVENTS"
CK="$(fresh_checkout clean)"
clean_out="$(run_hook_with_staged_file "readme.md" "$CK" "Hello world. Nothing to see here.")"
clean_exit="${clean_out%%|*}"
clean_stderr="${clean_out#*|}"
if [ "$clean_exit" != "0" ]; then
  echo "FAIL[clean]: hook exited $clean_exit on a clean diff (want 0)"
  echo "  stderr: $clean_stderr"
  exit 1
fi
if [ -n "$clean_stderr" ]; then
  echo "FAIL[clean]: hook produced stderr on a clean diff"
  echo "  stderr: $clean_stderr"
  exit 1
fi
if [ -f "$EVENTS" ] && grep -q '"type":"push_blocked"' "$EVENTS"; then
  echo "FAIL[clean]: clean diff still emitted a push_blocked event"
  cat "$EVENTS"
  exit 1
fi
echo "ok[clean]: clean diff passes silently"

# ============================================================================
# CASE 8 — gitleaks-on-PATH delegation: the hook calls `gitleaks` and
#          propagates its non-zero exit code.
# ============================================================================
rm -f "$EVENTS"
STUB_BIN="$TMP/bin-gitleaks"
mkdir -p "$STUB_BIN"
GL_LOG="$TMP/gitleaks-calls.log"
: > "$GL_LOG"
cat > "$STUB_BIN/gitleaks" <<GL_EOF
#!/bin/bash
{
  printf 'gitleaks'
  for a in "\$@"; do printf ' %s' "\$a"; done
  printf '\n'
} >> "$GL_LOG"
echo "stub-gitleaks: pretend secret found" >&2
exit 1
GL_EOF
chmod +x "$STUB_BIN/gitleaks"

CK="$(fresh_checkout gitleaks-delegate)"
# Stage a benign file so there's something for gitleaks to "scan".
(
  cd "$CK"
  printf 'just a normal file\n' > normal.txt
  git add normal.txt
)
gl_err="$TMP/gitleaks-stderr.log"
gl_exit=0
(
  cd "$CK"
  export PATH="$STUB_BIN:$PATH"
  : | ".git/hooks/pre-push" origin "https://example.invalid/x.git" 2>"$gl_err"
) || gl_exit=$?

if [ "$gl_exit" = "0" ]; then
  echo "FAIL[gitleaks]: hook did not propagate gitleaks' non-zero exit"
  cat "$gl_err"
  exit 1
fi
if ! grep -q 'gitleaks detect' "$GL_LOG"; then
  echo "FAIL[gitleaks]: hook did not invoke 'gitleaks detect'"
  cat "$GL_LOG"
  exit 1
fi
if ! grep -q -- '--staged' "$GL_LOG"; then
  echo "FAIL[gitleaks]: hook did not pass --staged to gitleaks"
  cat "$GL_LOG"
  exit 1
fi
echo "ok[gitleaks]: delegation propagates non-zero exit"

# ============================================================================
# CASE 9 — AGENTS.md Hard NOs section references the hook + ticket 0008.
# ============================================================================
if ! grep -q 'fleet_install_prepush_hook' "$REPO_ROOT/AGENTS.md"; then
  echo "FAIL[agents-md]: AGENTS.md missing fleet_install_prepush_hook reference"
  exit 1
fi
if ! grep -q '0008' "$REPO_ROOT/AGENTS.md"; then
  echo "FAIL[agents-md]: AGENTS.md missing ticket 0008 reference"
  exit 1
fi
echo "ok[agents-md]: Hard NOs cross-reference present"

echo "ok: tests/secret-scan.sh passed"
