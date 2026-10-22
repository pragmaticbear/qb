# Ticket template

Copy into `.claude/qb/tickets/T-###.md`.

```markdown
# T-###: <imperative title, e.g. "Add archive button to project list">

**Assignee:** junior-dev | senior-dev | lead
**Routing reason:** <one line — score and any hard rule that applied>
**Depends on:** T-### (or none)

## Goal
<1–3 sentences: what changes for the user or system, and why>

## Context
- Relevant files: `path/a.ts`, `path/b.ts`
- Pattern to follow: <existing code that does something similar>
- Constraints: <perf, compat, style, libraries to use or avoid>

## Acceptance criteria
- [ ] <observable, testable statement>
- [ ] <observable, testable statement>
- [ ] Tests cover <specific cases>
- [ ] Existing checks pass

## Out of scope
- <thing a dev might reasonably think is included but isn't>

## Verdict log
<!-- lead appends: date/rev, verdict, reasons -->
```

## Writing good acceptance criteria

Bad: "Archive works correctly."
Good: "`POST /projects/:id/archive` sets `archived_at` and returns 200 with the
updated project; calling it twice is a no-op that still returns 200;
archived projects are excluded from `GET /projects` unless `?include=archived`."

If you can't write criteria at that level, the ticket isn't ready.
