# Plan review checklist

Read the plan against the ticket, then the code it references. Any "no" on a
blocking item is a CHANGES REQUESTED, with a numbered, concrete fix.

## Blocking

1. **Understood the goal.** The plan's restatement matches the ticket. A
   wrong restatement means stop: fix the misunderstanding before anything else.
2. **Covers every acceptance criterion.** Map each criterion to a plan step.
   Unmapped criterion = blocking.
3. **Stays in scope.** No work from "Out of scope", no drive-by refactors,
   no new dependencies the ticket didn't ask for.
4. **Fits the codebase.** Uses existing patterns, utilities, and conventions
   instead of inventing parallel ones. Check that the files and functions it
   names actually exist.
5. **Names the files.** A concrete list of files to create/modify. "Update
   the relevant components" is not a plan.
6. **Test strategy is real.** Says which tests, where, and what cases —
   including at least one edge or failure case.
7. **Risks are honest.** Anything touching shared code, data, or behavior
   other features rely on is called out. A plan with "Risks: none" on a
   non-trivial ticket gets asked to look again.

## Non-blocking (note, don't reject)

- Naming preferences
- Minor ordering of steps
- Alternative approaches that are equally good

## Signals to escalate rather than revise

- The plan reveals the ticket needs a design decision → REASSIGN up, or
  make the decision yourself and RESCOPE.
- Second revision still misses the same blocking item → REASSIGN.
- The developer's questions show the ticket was ambiguous → RESCOPE; that's
  your miss, not theirs.

## Verdict format

```
VERDICT: CHANGES REQUESTED (T-004, plan rev 1)

1. Criterion 2 (idempotent second call) isn't addressed. Add a step and a test.
2. Don't add `date-fns`; use the `formatDate` helper in `src/lib/time.ts`.
3. List the migration file explicitly — step 3 says "update schema" with no path.

Non-blocking: consider naming the handler `archiveProject` for consistency.
```
