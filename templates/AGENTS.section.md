<!-- Paste these two sections into the project's AGENTS.md. The generic fleet
     prompts read them at runtime — they are the contract between the shared
     engine and this specific repo. Replace every bracketed value. -->

## Agent parameters

- **Gating checks** — EXACTLY these GitHub check names gate a merge. Every other
  check (Vercel, preview comments, informational suites) is informational and
  MUST be ignored when deciding mergeability or what to "fix":
  - `[Typecheck + build]`
  - `[E2E (chromium)]`
  - `[E2E (mobile-webkit)]`
- **Agent branch prefixes**:
  - `feat/` — feature work (ship agent)
  - `chore/gtm-` — backlog refresh (groom agent)
  - `eng/` — engineering work (eng agent, only if ENG_ENABLED)
- **Local gate command** — what the heal/dev step runs locally before pushing
  (must be green): `[npm run typecheck && npm run build && npx playwright test --project=chromium]`
- **Subagents** (in `.claude/agents/`): `implementation-dev`, `gtm-innovation`,
  `review`[, `eng-dev`]
- **Backlog areas**: `[labs | plan | meals | today | progress | settings | infra | privacy | growth]`
- **Backlog validator**: `node scripts/check-backlog.mjs` (wired into the
  `[Typecheck + build]` gating job — keeps ticket files and the index in sync)

## Hard NOs

The reviewer treats any of these as an automatic `--request-changes`. They are
the contract, not suggestions.

- Never push to `main` directly; never bypass branch protection; never merge with
  a red gating check.
- Never disable, weaken, or skip a passing test to make a PR green.
- Never "fix" a non-gating check — ignore it.
- Never exceed 2 `heal:` attempts on one PR — escalate via a human comment.
- `[Privacy/security rule — e.g. never widen the egress allow-list / never add a
  backend, analytics SDK, or proxy / never collect more on minors / never weaken
  webhook signature verification.]`
- `[Voice rule — e.g. banned words: journey, amazing, exciting; no emoji; no
  purple-gradient AI-generic UI.]`
