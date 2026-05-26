---
id: 0008
title: Secret-scan pre-push hook in agent checkouts
status: groomed
priority: P1
area: safety
created: 2026-05-26
owner: gtm-innovation
---

## User story

As a fleet operator, I want every agent push to be blocked locally if the
diff contains anything that looks like a secret, so that I don't have to
trust the dev agent's judgment on credential leakage across every project.

## Why now (four lenses)

### Product Owner
A guardrail that costs one shell hook and prevents a category of
catastrophic mistakes (a leaked PAT in a public repo). The dev agent's
"never commit secrets" Hard NO is good; this is the seatbelt under it.

### Stakeholder
Widens the moat on `safety`. Uniform secret-scanning across every project
without per-repo configuration — install once, applied everywhere.

### Operator
"Did the agent accidentally push my Anthropic key?" — no, because the push
itself fails locally with a clear message and the cache-dir checkout still
holds the change for inspection.

### Growth
"Pre-push secret scan baked in" is table stakes for a serious autonomous-agent
kit. Compare to "trust the LLM not to do it."

## Acceptance criteria

- [ ] `lib/common.sh` exposes `fleet_install_prepush_hook` which writes a
      `.git/hooks/pre-push` to the current checkout. The hook runs
      `gitleaks detect --no-banner --redact --staged` if `gitleaks` is on
      `PATH`, else falls back to a small built-in regex scan of
      `git diff --cached`.
- [ ] The built-in fallback regex catches: `(?i)(api[_-]?key|secret|token|
      bearer)\s*[:=]\s*["']?[A-Za-z0-9_\-]{20,}`, `sk-[a-zA-Z0-9]{20,}`,
      `ghp_[A-Za-z0-9]{36}`, `gho_[A-Za-z0-9]{36}`, AWS access key ids
      (`AKIA[0-9A-Z]{16}`), and Anthropic API keys (`sk-ant-[A-Za-z0-9_-]{30,}`).
- [ ] `fleet_checkout` calls `fleet_install_prepush_hook` after the
      `git config user.email`/`user.name` block.
- [ ] When the hook fires on a real match, it exits non-zero with a one-line
      reason on stderr. The push command (run by the dev agent later) fails;
      the dev agent must then handle the error.
- [ ] `tests/secret-scan.sh` creates a fake commit with a fake `sk-ant-`
      string and asserts the hook exits 1; then with a clean commit asserts
      exit 0.
- [ ] `AGENTS.md` Hard NOs already covers "never commit secrets"; add a
      one-line link to this hook for context.

## Out of scope

- Server-side scanning (GitHub's secret scanning is already on by default
  for public repos; that's the second line of defense).
- Allow-list management. False positives mean the operator handles them
  manually.

## Engineering notes

- `lib/common.sh` — `fleet_install_prepush_hook` near `fleet_checkout`. The
  hook content is a heredoc; make it small and self-contained.
- `tests/secret-scan.sh` — `mktemp -d`, `git init`, stage a file with a
  known secret-like string, run the hook directly, assert exit code.
- Public API: additive.
- Reinstall: all projects.

## Implementation log

(Appended by the implementation-dev agent during execution.)
