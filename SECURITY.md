# Security policy

## Supported versions

Only the latest release of qb gets security fixes.

## Reporting a vulnerability

Please don't open a public issue for security problems. Use GitHub's private
reporting instead: go to the **Security** tab of this repo and click
**Report a vulnerability**.

Include what you found, how to reproduce it, and what an attacker could do with
it. You should hear back within a week.

## Scope

qb ships Claude Code hooks that run shell scripts on your machine. Issues that
are in scope include:

- A way for a developer subagent to bypass the phase lock or the quality gate
  using the file-editing tools
- Command injection through hook input, state, or ticket content
- The hooks running anything outside the project directory or `.claude/qb/checks`

Known limitations listed in the README (for example, writing files through Bash
while the lock is on) are not treated as vulnerabilities, but ideas for closing
them are welcome.
