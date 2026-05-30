---
id: 0002
title: demo second ticket (waits behind 0001)
status: proposed
priority: P2
area: docs
created: 2026-05-30
owner: gtm-innovation
---

## User story

As an operator reading the demo's backlog index, I want a second row in
a different status so I can see what `proposed` vs `groomed` look like
side-by-side without consulting the README.

## Acceptance criteria

- [ ] This ticket appears as `status: proposed` in the index.
- [ ] The ship agent does NOT pick it (it's behind 0001 and not
      groomed).

## Engineering notes

Stays `proposed` for the lifetime of the demo. The groom agent would
normally promote this to `groomed` after a refresh cycle; the demo
does not run the groom agent.
