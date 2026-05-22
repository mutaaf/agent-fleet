---
id: NNNN
title: Short imperative title
status: proposed
priority: P2
area: plan
created: YYYY-MM-DD
owner: gtm-innovation
---

## User story

As a [specific persona], I want [specific behavior], so that [user-visible
outcome — not engineering, not metrics].

## Why now (four lenses)

### Product Owner
What is the smallest meaningful unit of value? What gets *simpler* for the user,
not just richer?

### Stakeholder
How does this widen the moat (e.g. persistent data / canonicalization / insight
engine / adherence loop / structured artifact / privacy)? If it doesn't widen
the moat, what specific user pain does it cure that justifies the work?

### User (in the real moment of use)
What does this *feel* like? One tap or three? Resilient to a flaky connection?
Does it work with wet hands / on a phone / mid-task?

### Growth
Why does this make someone tell one specific person about it? What is the "show
me" moment — the single screenshot a friend would want to see?

## Acceptance criteria

Each box maps 1:1 to a test scenario. The dev agent writes the tests against this
list before writing code.

- [ ] [Observable behavior 1 — be specific.]
- [ ] [Observable behavior 2.]
- [ ] [A relevant regression check.]
- [ ] [Cross-cutting check — platforms/viewports, or note what's out of scope.]
- [ ] [Privacy/security check if relevant — e.g. no new hostnames in the allow-list.]

## Out of scope

Explicit anti-goals — the dev agent will not do these even if they seem related.

- ...

## Engineering notes

Files / patterns the dev should touch. Specific enough that the dev doesn't have
to re-discover the architecture.

- `src/...` — what to change here
- `tests/...` — where the test goes
- New deps: yes/no, and which
- Schema migration: yes/no, and at what version
- [Privacy/security surface change required: yes/no — justify here]

## Implementation log

(Appended by the implementation-dev agent during execution.)

- YYYY-MM-DD — branch `feat/NNNN-...` opened
- YYYY-MM-DD — failing test added in `tests/...`
- YYYY-MM-DD — PR #N opened, CI [state]
- YYYY-MM-DD — merged to main
