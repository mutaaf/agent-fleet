# LESSONS

## 2026-06-09 — Test wrote to a non-isolated path

Tests under `tests/` MUST create their working tree under `mktemp -d` and
clean up on exit. Symptom: a test left a stray file under the host's `$HOME`
and the next run's pre-push hook flagged it. Fix: every test wraps its
workspace in `TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT`.

## 2026-06-10 — Some unrelated lesson that should not match

Body text.
