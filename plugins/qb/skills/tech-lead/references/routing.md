# Routing rubric

Route to the cheapest developer who can do the ticket well. Score the ticket,
then sanity-check against the hard rules.

## Hard rules (override the score)

Always **lead (you)**:
- Database schema changes, data migrations, backfills
- Authentication, authorization, secrets, crypto, payment or billing logic
- Public API contracts (HTTP endpoints other teams call, exported library APIs)
- Anything irreversible or expensive to roll back
- Choosing between architectures

Never **junior-dev**:
- Concurrency, caching, or anything with ordering/race concerns
- Changes spanning more than ~3 files or more than one module boundary
- Tickets where the acceptance criteria leave a design decision open
- Code with no existing pattern in the repo to follow

## Score (1 point each)

| Signal | +1 if… |
|---|---|
| Spread | touches more than 2 files or more than one module |
| Ambiguity | a reasonable dev could build it two different ways |
| Novelty | no existing pattern in the codebase to copy |
| Coupling | other code depends on the shape of what's built |
| Blast radius | a bug here breaks something users notice |
| Testability | hard to verify with an automated test |

- **0–1 → junior-dev**
- **2–4 → senior-dev**
- **5–6 → lead**, or split the ticket until pieces score lower

## Good junior tickets

- Add a field to an existing form following the pattern of the other fields
- Write unit tests for an existing, already-correct function
- Rename / move with no behavior change
- Fix a bug with a clear repro and an obvious local cause
- Copy text, config values, simple styling changes

## Good senior tickets

- New endpoint + handler + tests following existing conventions
- Refactor a module behind an unchanged interface
- Performance fix with profiling
- Feature work across UI and API inside the current architecture

## Splitting to route cheaper

A senior ticket can often become one senior ticket that establishes the
pattern plus several junior tickets that apply it. Do this when the repeated
part is large; don't do it when coordination would cost more than it saves.
