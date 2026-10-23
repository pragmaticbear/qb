<p align="center"><img src="logo.png" alt="quarterback logo" width="160"></p>

# quarterback (QB)

A tiered engineering team for [Claude Code](https://docs.claude.com/en/docs/claude-code/overview).

**Opus** is the tech lead and PM. **Sonnet** is the senior full-stack dev.
**Haiku** is the junior dev. Opus writes the tickets, routes each one to the
cheapest developer who can do it well, and has real veto power: it can reject a
plan, demand changes, reassign the ticket up a tier, or rescope it entirely.
Developers can push back on bad tickets, and the lead has to re-evaluate.

```
you ──► Opus (lead/PM)
          │  clarify → tickets → route
          ▼
      ┌── PLAN GATE ◄──── revise ────┐
      │   APPROVED / CHANGES REQUESTED / REASSIGN / RESCOPE
      ▼                              │
  Sonnet (senior) or Haiku (junior) ─┘   ← code edits are locked here
      │
      ▼  implement
      DELIVERY GATE  ← hook runs your tests; can't report DONE on red
      │   then Opus reviews the actual diff
      ▼
   ACCEPTED → next ticket
```

## Why not just use what's built in?

Claude Code already has pieces of this. None of them give the lead authority:

| Built-in | What it does | What's missing |
|---|---|---|
| `opusplan` | Opus plans in plan mode, Sonnet executes | One-way handoff. No review of Sonnet's work, no Haiku tier, no rejection loop |
| `/advisor` | The executing model can consult a second model | The executor decides when to ask, and advice is non-binding |
| Subagents with `model:` | Delegate to Sonnet/Haiku agents | No protocol, no plan gate, nothing stops a subagent from reporting "done" on a red build |
| Agent teams (experimental) | Persistent teammates with messaging | Great transport, but no roles, routing, or quality bar |

This plugin adds the missing part: a protocol (tickets, plan gate, delivery
gate, escalation rules, verdict formats) and hooks that enforce it.

## Install

In Claude Code (2.1.275 or later):

```
/plugin install qb --marketplace pragmaticbear/qb
```

On older versions, add the marketplace first:

```
/plugin marketplace add pragmaticbear/qb
/plugin install qb@quarterback
```

To try it from a local clone:

```
/plugin marketplace add ./path/to/quarterback
/plugin install qb@quarterback
```

## Use

Start Claude Code on Opus, then hand the lead a task:

```
claude --model opus
> /qb:lead add project archiving: archive button in the list view, archived projects hidden by default, an "include archived" filter
```

The lead will ask about anything the code can't answer, show you the ticket
list with assignees, then run each ticket through the gates. You'll see plans
come back, verdicts go out, and a board at `.claude/qb/board.md` that
records every decision.

| Command | What it does |
|---|---|
| `/qb:lead <task>` | Start (or resume) a run with Opus as lead |
| `/qb:status` | Show the board, current phase, and anything blocking |
| `/qb:reset` | Clear the phase lock (keeps the board and tickets) |

## How it works

**Roles.** `agents/senior-dev.md` (Sonnet) and `agents/junior-dev.md` (Haiku)
define each developer's protocol: plan first in a fixed format, wait for
approval, implement only what was approved, and finish with a structured
DONE report. The junior is told to stop and ask rather than guess; the senior
is allowed to `PUSHBACK` on tickets it thinks are wrong.

**Routing.** The lead scores each ticket on spread, ambiguity, novelty,
coupling, blast radius, and testability. Hard rules override the score: Haiku
never gets migrations, auth, payments, concurrency, or public APIs, and the
lead keeps architecture decisions for itself. See
[`routing.md`](plugins/qb/skills/tech-lead/references/routing.md).

**Escalation.** Two rejected revisions at one tier means stop coaching.
The ticket moves up a tier or gets rescoped.

**Enforcement.** The lead writes a phase lock to `.claude/qb/state`.
Two hooks read it:

- `phase-guard.sh` (PreToolUse): in `plan` and `review` phases, blocks
  Edit/Write/MultiEdit/NotebookEdit on anything outside `.claude/qb/`, and
  allows Bash only for known read-only commands (`ls`, `cat`, `grep`, `rg`,
  `find` without `-exec`/`-delete`, `sed -n 'N,Mp'`, `git status/diff/log/show`,
  and similar) with no output redirects. Anything else, including unknown
  commands, interpreters, `sudo`/`env` prefixes and renamed binaries, is
  blocked. A line of `.claude/qb/checks` may be run verbatim. Developers can
  explore but can't start coding before approval. In every phase, developers
  are also blocked from any non-read-only Bash that mentions `.claude/`
  (the lock, the checks and the board belong to the lead).
- `quality-gate.sh` (SubagentStop): in the `implement` phase, runs your
  project's checks when a developer tries to finish. Failures go back to the
  developer with the output tail. After `max_attempts` (default 3) the
  developer is released and the state is marked `gate: failed` so the lead
  must decide.

Both hooks do nothing when the state file is absent, so the plugin doesn't
interfere with normal sessions.

## Configure

**Checks.** Put one shell command per line in `.claude/qb/checks`:

```
# .claude/qb/checks
pnpm test
pnpm run lint
pnpm run typecheck
```

Without that file, the gate auto-detects `npm|pnpm|yarn|bun test` (plus
`lint` and `typecheck` scripts), `pytest`, `cargo test`, `go test ./...`,
or `make test`. If nothing is found, the gate stays out of the way and the
lead's diff review carries the weight.

**Environment variables.**

| Variable | Default | Meaning |
|---|---|---|
| `QB_MAX_GATE_ATTEMPTS` | `3` | Failed gate runs before the developer is released (also settable as `max_attempts:` in the state file) |
| `QB_CHECK_TIMEOUT` | `600` | Seconds per check command (needs `timeout`/`gtimeout` on PATH) |

**Version control.** Commit `.claude/qb/checks`. Whether to commit the
board and tickets is up to you. They're a useful design record, but you may
prefer to add `.claude/qb/state` and `.claude/qb/tickets/` to
`.gitignore`.

**Agent teams.** If you run with `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`,
the lead can spawn the developers as persistent teammates and send verdicts
with `SendMessage`, so they keep context between plan and implementation.
The protocol is the same.

## Limitations

This is v0.1. Please open issues for anything that doesn't hold up.

- **The lock is a guardrail, not a sandbox.** It blocks the file-editing
  tools, and it allowlists Bash with a quote-aware word scan, not a shell
  parser. Unknown commands fail closed, so the gap is false positives rather
  than bypasses: `(( a > b ))`, `[[ a > b ]]`, writes to `/dev/stderr` and any
  read-only tool not on the list are blocked in plan and review. The developer
  fence on `.claude/` can't see paths built at runtime (`D=.cla; rm ${D}ude`).
  The lead reviews the diff either way.
- **`.claude/qb/checks` runs as shell commands.** The gate executes each line
  with `bash -c`, the same trust level as running `npm test`. Before using qb
  in a repo you didn't write, read any committed `.claude/qb/checks` file (or
  delete it). Developer subagents are blocked from editing `state` and
  `checks` through the edit tools, but see the Bash caveat above.
- **One ticket at a time.** The phase lock is global.
- **Hook input fields.** The gate filters on the `agent_type` field of the
  SubagentStop input. If your Claude Code version doesn't send it, the gate
  runs for any subagent that stops during the `implement` phase. That's
  usually fine, since the lead shouldn't spawn other subagents mid-implementation.
- **Requires bash.** On Windows, use Git Bash or WSL. `jq` or `python3` is
  used for JSON parsing when present, with a sed fallback.
- **Cost.** Every plan review is an Opus turn. The two-gate loop pays for
  itself on medium and large work; for one-line fixes, just ask Claude directly.

## Repo layout

```
.claude-plugin/marketplace.json      marketplace manifest
plugins/qb/
  .claude-plugin/plugin.json         plugin manifest
  agents/senior-dev.md               Sonnet developer
  agents/junior-dev.md               Haiku developer
  commands/lead.md                   /qb:lead
  commands/status.md                 /qb:status
  commands/reset.md                  /qb:reset
  skills/tech-lead/SKILL.md          the lead's playbook
  skills/tech-lead/references/       routing, ticket template, review checklists
  hooks/hooks.json                   hook registration
  scripts/                           phase-guard, quality-gate, shared lib
tests/test-hooks.sh                  hook test suite
```

## Contributing

Run the hook tests before sending a PR:

```
bash tests/test-hooks.sh
```

The most valuable contributions right now are transcripts of real runs,
especially ones where the lead approved something it shouldn't have or
bounced something it shouldn't have. Those drive changes to the review
checklists and routing rubric.

## Security

Please report vulnerabilities privately. See [SECURITY.md](SECURITY.md).

## License

MIT
