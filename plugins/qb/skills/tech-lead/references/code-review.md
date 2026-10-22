# Code review checklist (delivery gate)

The hook already ran tests and checks. Your review is about whether the
change is *right*, not just green. Review `git diff` — never only the
developer's summary.

## Blocking

1. **Matches the approved plan.** Deviations must be listed in the delivery
   report with a reason. Unexplained deviation = blocking.
2. **Meets every acceptance criterion.** Check each one against the diff
   and the tests, not the claim.
3. **Tests test the behavior.** Not just that the function runs: they'd fail
   if the feature broke. Edge cases from the ticket are covered. No tests
   deleted or skipped to make the build pass.
4. **No scope creep.** Unrelated changes get reverted or moved to a new ticket.
5. **Correctness.** Error paths handled; no swallowed exceptions; inputs at
   trust boundaries validated; no obvious races or N+1s.
6. **Security basics.** No secrets in code, no injection-prone string
   building, no weakened auth checks.
7. **Fits in.** Follows repo conventions (naming, structure, error handling,
   logging). Would a maintainer recognize this as house style?

## Non-blocking

- Small readability nits → note them; a junior ticket can batch them later.

## Verdict format

```
VERDICT: CHANGES REQUESTED (T-004, fix round 1)

1. `archiveProject` catches the DB error and returns 200. Let it propagate to
   the error middleware like `deleteProject` does.
2. The idempotency test calls the endpoint once. Call it twice and assert
   the second response.
```

or

```
VERDICT: ACCEPTED (T-004)
Notes: nice reuse of the existing query builder.
```
