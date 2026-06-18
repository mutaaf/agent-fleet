# LESSONS

Operational memory for agent-fleet test fixture (ticket 0057).

## 2026-04-15 — top promote entry (preflight_json_escape wrapper trap)

The most-cited entry in this fixture. Cited 14× in bin/fleet, 1× in
lib/common.sh, 1× in each of backlog/0001..0005 — 20 hits across 7
unique files — squarely above the promote-candidate threshold of
≥10 cites AND ≥5 files. Older than 30 days vs the frozen clock
(2026-06-17), so the prune-candidate floor does not apply.

## 2026-04-20 — second promote entry (awk arr count zero)

Second most-cited entry. Cited 7× in bin/fleet, 5× in backlog/0001..0005
— 12 hits across 6 files. Above the promote threshold. Older than 30
days; not prune-eligible because citation count > 1.

## 2026-05-01 — boundary keep entry (10 cites across 4 files)

Boundary test for the promote threshold: exactly 10 cites BUT only
across 4 unique files (bin/fleet, lib/common.sh, backlog/0001,
backlog/0002). Files-cited fails the ≥5 floor, so no promote tag.
Older than 30 days but citation count > 1, so no prune tag either.
Renders as keep.

## 2026-05-03 — boundary keep entry (9 cites across 5 files)

Boundary test for the promote threshold from the other side: 9 cites
across 5 unique files (bin/fleet, lib/common.sh, backlog/0001..0003).
Citation count fails the ≥10 floor, so no promote tag. Older than 30
days but citation count > 1, so no prune tag.

## 2026-05-05 — boundary promote entry (10 cites across 5 files)

Boundary test for the promote threshold exactly met: 10 cites across
5 unique files (bin/fleet, lib/common.sh, backlog/0001..0003). Both
thresholds met — must render the promote-candidate tag.

## 2026-05-15 — recent non-prune entry (2 cites, 33d ago)

Older than 30 days but cited 2× — citation count exceeds the prune
floor of ≤1, so no prune-candidate tag. Renders as keep.

## 2026-06-01 — very recent no-tag entry (0 cites, 16d ago)

Cited zero times, but the heading date is only 16 days before the
frozen clock — younger than the 30-day prune floor. Renders as keep
even though the citation count would qualify.

## 2026-05-12 — clear prune entry (1 cite, 36d ago)

Cited exactly 1× and the heading date is more than 30 days before the
frozen clock. Both prune-candidate conditions met — must render the
prune-candidate tag with EXPIRES suggestion (today+30d).

## 2026-04-10 — self-citation exclusion entry (0 cites externally)

This entry appears in LESSONS.md itself (this very heading) but NO
fixture file outside LESSONS.md cites the date 2026-04-10. The
heading-extractor MUST exclude self-citations so the renderer reports
0× across 0 files. Older than 30 days, so prune-eligible.

## 2026-04-25 — include-tests sentinel entry

Cited zero times across the four default trees, BUT cited 5× under
tests/lessons-rank-fixture.sh. Default behavior renders 0/0 prune
(>30d, ≤1 cite). With --include-tests the count becomes 5/1, which
is above the prune floor, so the recommendation flips to keep.
