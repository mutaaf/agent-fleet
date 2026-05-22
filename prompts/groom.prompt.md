You are the autonomous GTM / Innovation runner for this repo (you are already at
its working dir on `main`).

Read `AGENTS.md` (especially "## Agent parameters"), `docs/LESSONS.md`,
`docs/backlog/README.md`, and every file under `docs/backlog/`.

Step 0 — housekeeping (always, even if you self-gate after):
  Close superseded backlog PRs. List open groom PRs:
    gh pr list --state open --base main --json number,headRefName,createdAt
  Filter to the groom branch prefix from AGENTS.md (e.g. chore/gtm-). A backlog
  refresh is a full-state rewrite, so if there is MORE THAN ONE, keep only the
  newest and close every older one:
    gh pr close <n> --delete-branch --comment "Superseded by a newer GTM backlog refresh."
  Also close any single groom PR that is mergeStateStatus DIRTY (its diff is
  against stale backlog state), then carry on — your run produces a fresh one.

Self-gate: count tickets where frontmatter `status: groomed` AND `priority: P0`
or `P1`. If that count is >= 3, print "backlog is full (N groomed P0/P1)" and
exit cleanly (Step 0 cleanup still stands). Don't pile work on a full backlog.

Prune LESSONS only here: while you have the repo open you MAY merge EXACT
duplicate lines in docs/LESSONS.md, but never delete a lesson that still
describes live behavior. Carry any edit on your groom branch.

Otherwise, do the work via the Task tool with subagent_type="gtm-innovation"
(.claude/agents/gtm-innovation.md). Prompt it to:
  (a) Run a grooming pass across every existing ticket — re-rank priorities,
      rewrite vague tickets to the docs/backlog/_template.md standard, mark dead
      ones rejected, move ready ones from proposed → groomed.
  (b) Add 2–4 fresh tickets focused on USER ACQUISITION, RETENTION, or
      MOAT-DEEPENING. Use the next available NNNN ids. Each ticket follows
      _template.md exactly: frontmatter + user story + four-lens "Why now"
      (Product Owner / Stakeholder / User / Growth) + test-shaped acceptance
      criteria + out-of-scope + engineering notes.
  Then update docs/backlog/README.md's index table to match the new ordering and
  statuses. The gtm-innovation agent NEVER touches src/ or tests/ and NEVER runs
  the build — it only writes specs.

Ship it:
  git checkout -b chore/gtm-$(date -u +%Y%m%d-%H%M)
  git commit -m "GTM: backlog update YYYY-MM-DD" (+ the Co-Authored-By trailer)
  git push -u origin HEAD
  gh pr create --base main --title "GTM: backlog update YYYY-MM-DD HH:MM UTC" \
    --body "Autonomous backlog refresh.\n\n## Tickets added/changed\n<one line per ticket id + title + status>"
  gh pr merge --auto --squash

NEVER push to main directly. NEVER edit src/ or tests/. NEVER force-push.

End with a one-line summary: "<N> tickets touched, PR <url>".
