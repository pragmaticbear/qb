---
description: Clear the dev-team phase lock so edits are unblocked (keeps the board and tickets)
---

Delete `.claude/dev-team/state` if it exists. Leave `board.md` and
`tickets/` untouched so the history is kept. Then confirm in one line that
the phase lock is cleared and the hooks are inactive until a new
`/dev-team:lead` run sets it again.

If the user asked to wipe everything ("full reset", "start over
completely"), also delete `.claude/dev-team/board.md` and
`.claude/dev-team/tickets/`, but keep `.claude/dev-team/checks` since it's
project configuration.
