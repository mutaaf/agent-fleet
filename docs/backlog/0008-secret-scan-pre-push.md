---
id: 0008
title: Secret-scan pre-push hook in agent checkouts
status: in-progress
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

Each box maps 1:1 to a test scenario in `tests/secret-scan.sh`.

- [ ] `lib/common.sh` exposes `fleet_install_prepush_hook <checkout_dir>`
      which writes an executable `.git/hooks/pre-push` to that checkout.
      Called automatically by `fleet_checkout` after the
      `git config user.email`/`user.name` block.
- [ ] Given a checkout where the hook ran a `git commit` adding a file
      containing `sk-ant-api03-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAA`, the hook
      exits 1 with a stderr line matching `secret detected:` and the
      pattern name.
- [ ] Given a checkout where the hook ran with a clean commit (no
      secret-like strings), the hook exits 0 silently.
- [ ] The built-in fallback regex MUST match each of these patterns (one
      test case per pattern):
      `sk-ant-[A-Za-z0-9_-]{30,}` (Anthropic), `ghp_[A-Za-z0-9]{36}`
      (GitHub PAT), `gho_[A-Za-z0-9]{36}` (GitHub OAuth),
      `AKIA[0-9A-Z]{16}` (AWS), `sk-[A-Za-z0-9]{20,}` (OpenAI-shape),
      and `(?i)(api[_-]?key|secret|token|bearer)\s*[:=]\s*["']?[A-Za-z0-9_\-]{20,}`.
- [ ] If `gitleaks` is on PATH, the hook delegates to
      `gitleaks detect --no-banner --redact --staged` and respects its exit
      code. The test stubs `gitleaks` on PATH with a script that exits 1
      and asserts the hook propagates the failure.
- [ ] When the hook blocks a push, `fleet_emit_event push_blocked
      reason=secret_match pattern=<name>` is emitted.
- [ ] `AGENTS.md` Hard NOs already covers "never commit secrets"; add a
      one-line cross-reference: "Enforced locally by the pre-push hook
      installed by `fleet_install_prepush_hook` — see ticket 0008."

## Out of scope

- Server-side scanning (GitHub's secret scanning is already on by default
  for public repos; that's the second line of defense).
- Allow-list management. False positives mean the operator handles them
  manually by amending the commit.
- Scanning files already in `main`. Pre-push only — historical leaks are
  out of scope.

## Engineering notes

- `lib/common.sh` — `fleet_install_prepush_hook` near `fleet_checkout`. The
  hook body is a heredoc; keep under 60 lines, self-contained, no `jq`
  dependency.
- The hook reads `git diff --cached` (or `git log -p $local_sha ^$remote_sha`
  for pre-push specifically) and pipes through `grep -E` for each pattern.
- `tests/secret-scan.sh` — `mktemp -d`, `git init`, stage a file with a
  fake matching string per pattern, invoke the hook directly (not via
  `git push`, which needs a remote), assert exit code and stderr text.
- Public API: additive.
- Reinstall: all projects.

## Implementation log

- 2026-05-26 — implementation-dev picked up the ticket. Approach:
  - Add `fleet_install_prepush_hook <checkout_dir>` to `lib/common.sh`
    near `fleet_checkout`, called automatically after the
    `git config user.email`/`user.name` block.
  - Hook body is a self-contained heredoc (<= 60 lines, no `jq`), delegates
    to `gitleaks` when on PATH, otherwise greps `git diff --cached` (no
    remote required during test) against the six built-in patterns.
  - On block, hook emits `fleet_emit_event push_blocked
    reason=secret_match pattern=<name>` by re-sourcing `lib/common.sh`
    when reachable; falls back to a plain stderr message otherwise.
  - Tests in `tests/secret-scan.sh` invoke the hook directly (not via
    `git push`) and use obvious fake fixtures (e.g. `sk-ant-api03-`
    followed by `A`*30, `ghp_` followed by `0`*36) so the test file
    itself does not self-trip when committed.
