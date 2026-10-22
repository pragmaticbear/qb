#!/usr/bin/env bash
# PreToolUse hook: while the qb phase lock is "plan" or "review",
# block file edits outside .claude/qb/. Inert when no state file exists.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/lib.sh"

input=$(cat)
dt_init "$input"

[ -f "$DT_STATE" ] || exit 0

path=$(json_field "$input" file_path)
[ -n "$path" ] || path=$(json_field "$input" notebook_path)

# Developer subagents may never touch the lock or the gate's checks, in any
# phase: rewriting state would unlock edits, rewriting checks would let a red
# build through the delivery gate. Only the lead maintains those files.
agent=$(json_field "$input" agent_type)
case "$agent" in
  *junior-dev*|*senior-dev*)
    norm=$(printf '%s' "$path" | sed -E 's#/+#/#g; s#(/\.)+/#/#g; s#^(\./)+##')
    case "$norm" in
      */state|*/checks)
        case "$norm" in
          "$DT_STATE"|"$DT_CHECKS"|.claude/qb/*|*/.claude/qb/*|*..*)
            printf '%s\n' "qb: developers cannot edit .claude/qb/state or .claude/qb/checks. Those belong to the tech lead. If a check is wrong, say so in your report." >&2
            exit 2 ;;
        esac ;;
    esac ;;
esac

phase=$(state_get phase)
case "$phase" in
  plan|review) ;;
  *) exit 0 ;;
esac

# Always allow the lead to maintain the board, tickets, state and checks.
# A ".." anywhere is never allowed through: it could escape the qb dir.
case "$path" in
  *..*) ;;
  "$DT_DIR"/*|.claude/qb/*) exit 0 ;;
esac

ticket=$(state_get ticket)
if [ "$phase" = "plan" ]; then
  msg="qb: ${ticket:-the current ticket} is in PLAN phase. Code edits are locked until the tech lead approves a plan. If you are a developer, return your PLAN (or PUSHBACK/QUESTION) instead of editing. If you are the lead and are taking this ticket yourself, delete .claude/qb/state first."
else
  msg="qb: ${ticket:-the current ticket} is in REVIEW phase. Edits are locked while the tech lead reviews the diff. The lead should issue a verdict and set phase to implement for a fix round, or delete .claude/qb/state to take over."
fi
printf '%s\n' "$msg" >&2
exit 2
