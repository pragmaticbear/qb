---
description: Show the dev-team board, the current phase lock, and what's blocking
---

Read `.claude/dev-team/board.md` and `.claude/dev-team/state` (either may be
missing). Report in a few lines:

- Current ticket, assignee, and phase (or "no active run" if there's no state file)
- If the state shows `gate: failed`, say so prominently: the delivery gate
  hit its retry limit and the ticket needs a lead decision
- Tickets done / in progress / not started
- Anything waiting on the user (open questions, scope changes needing approval)

Then show the board table as-is. Don't change any files.
