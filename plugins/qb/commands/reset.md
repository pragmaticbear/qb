---
description: Clear the qb phase lock so edits are unblocked (keeps the board and tickets)
---

Delete `.claude/qb/state` if it exists. Leave `board.md` and
`tickets/` untouched so the history is kept. Then confirm in one line that
the phase lock is cleared and the hooks are inactive until a new
`/qb:lead` run sets it again.

If the user asked to wipe everything ("full reset", "start over
completely"), also delete `.claude/qb/board.md` and
`.claude/qb/tickets/`, but keep `.claude/qb/checks` since it's
project configuration.
