---
id: 0001
title: demo hello world (the ship agent picks this first)
status: groomed
priority: P1
area: docs
created: 2026-05-30
owner: gtm-innovation
---

## User story

As an operator evaluating `agent-fleet` from the README, I want the demo
to show me a real ticket being picked up by the ship agent so I can
recognise the same shape my own backlog will use.

## Acceptance criteria

- [ ] The ship agent picks this ticket (highest priority groomed row).
- [ ] A PR is opened on a `feat/0001-demo-hello-world` branch.
- [ ] The reviewer posts a `--request-changes` verdict so the
      `lesson_draft_emitted` event fires and a DRAFT block lands in
      `docs/LESSONS.md`.

## Engineering notes

This ticket never lands — the demo is a credential-less synthetic loop.
It exists so the operator sees the exact shape a real groomed ticket
has when the ship agent picks it.
