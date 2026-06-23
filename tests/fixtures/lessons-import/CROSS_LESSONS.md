# CROSS_LESSONS

Starter file used by tests/lessons-import.sh. Four paragraphs below are
byte-identical to bodies in dedupe-collision.pack.json so the dedupe
walker can prove its filter.

## agent-fleet

### 2026-05-25 — bootstrap

Pre-existing lesson under agent-fleet; the import path must not touch
this section when the namespace section heading is `## from peer-good:...`.

### 2026-06-01 — dedupe collision A

This body is byte-identical to dedupe-collision.pack.json lesson #1.
Imports MUST skip this one and emit dedup_skipped+=1.

### 2026-06-02 — dedupe collision B

This body is byte-identical to dedupe-collision.pack.json lesson #2.
Imports MUST skip this one and emit dedup_skipped+=1.

## almanac

### 2026-05-22 — dedupe collision C

This body is byte-identical to dedupe-collision.pack.json lesson #3.
Imports MUST skip this one too.

### 2026-05-23 — dedupe collision D

This body is byte-identical to dedupe-collision.pack.json lesson #4.
Final dedupe candidate.
