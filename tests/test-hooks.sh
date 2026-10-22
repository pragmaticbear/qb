#!/usr/bin/env bash
# Exercises the qb hook scripts against a throwaway project.
# Usage: tests/test-hooks.sh        (runs with every available JSON parser)
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPTS="$ROOT/plugins/qb/scripts"
PASS=0; FAIL=0

ok()   { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad()  { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; [ -n "${2:-}" ] && printf '       %s\n' "$2"; }

guard() { # <file_path> [agent_type] -> sets RC, ERR
  local extra=""; [ -n "${2:-}" ] && extra=",\"agent_type\":\"$2\""
  local json="{\"session_id\":\"t\",\"cwd\":\"$PROJ\"$extra,\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$1\",\"old_string\":\"a\",\"new_string\":\"b\"}}"
  ERR=$(printf '%s' "$json" | CLAUDE_PROJECT_DIR="$PROJ" bash "$SCRIPTS/phase-guard.sh" 2>&1 >/dev/null); RC=$?
}
gate() { # [agent_type] -> sets RC, OUT
  local extra=""; [ -n "${1:-}" ] && extra=",\"agent_type\":\"$1\""
  local json="{\"session_id\":\"t\",\"cwd\":\"$PROJ\",\"hook_event_name\":\"SubagentStop\"$extra}"
  OUT=$(printf '%s' "$json" | CLAUDE_PROJECT_DIR="$PROJ" bash "$SCRIPTS/quality-gate.sh" 2>/dev/null); RC=$?
}
state() { mkdir -p "$PROJ/.claude/qb"; printf '%s\n' "$@" > "$PROJ/.claude/qb/state"; }
sget()  { grep -E "^$1:" "$PROJ/.claude/qb/state" | sed -E "s/^$1:[[:space:]]*//"; }

run_suite() {
  PROJ=$(mktemp -d)
  echo "== parser: ${QB_FORCE_PARSER:-auto} =="

  # --- phase guard ---
  guard "$PROJ/src/app.js"
  [ $RC -eq 0 ] && ok "no state file: edits allowed" || bad "no state file: edits allowed" "rc=$RC"

  state "phase: plan" "ticket: T-001" "assignee: junior-dev" "attempts: 0"
  guard "$PROJ/src/app.js"
  [ $RC -eq 2 ] && ok "plan phase: source edit blocked (exit 2)" || bad "plan phase: source edit blocked" "rc=$RC"
  case "$ERR" in *T-001*PLAN*) ok "plan phase: reason names ticket and phase";; *) bad "plan phase reason" "$ERR";; esac

  guard "$PROJ/.claude/qb/board.md"
  [ $RC -eq 0 ] && ok "plan phase: board edit allowed" || bad "plan phase: board edit allowed" "rc=$RC"

  guard "$PROJ/pkg/.claude/qb/notes.md"
  [ $RC -eq 2 ] && ok "plan phase: qb dir outside project root still blocked" || bad "plan phase: foreign qb dir blocked" "rc=$RC"

  guard "$PROJ/.claude/qb/../../src/app.js"
  [ $RC -eq 2 ] && ok "plan phase: traversal through qb dir still blocked" || bad "plan phase: traversal blocked" "rc=$RC"

  state "phase: review" "ticket: T-001"
  guard "$PROJ/src/app.js"
  [ $RC -eq 2 ] && ok "review phase: source edit blocked" || bad "review phase: source edit blocked" "rc=$RC"

  state "phase: implement" "ticket: T-001" "attempts: 0"
  guard "$PROJ/src/app.js"
  [ $RC -eq 0 ] && ok "implement phase: edits allowed" || bad "implement phase: edits allowed" "rc=$RC"

  for f in "$PROJ/.claude/qb/state" "$PROJ/.claude/qb/checks" ".claude/qb/checks" \
           "./.claude/qb/state" "$PROJ/./.claude//qb/checks" "$PROJ/src/../.claude/qb/state"; do
    guard "$f" senior-dev
    [ $RC -eq 2 ] && ok "implement phase: developer blocked from $f" || bad "dev blocked from $f" "rc=$RC"
  done
  guard "$PROJ/.claude/qb/checks" qb:junior-dev
  [ $RC -eq 2 ] && ok "namespaced developer blocked from checks" || bad "namespaced dev blocked from checks" "rc=$RC"
  guard "$PROJ/.claude/qb/checks"
  [ $RC -eq 0 ] && ok "lead may edit checks" || bad "lead may edit checks" "rc=$RC"
  guard "$PROJ/src/state" senior-dev
  [ $RC -eq 0 ] && ok "developer may edit an unrelated file named state" || bad "dev unrelated state file" "rc=$RC"

  state "phase: plan" "ticket: T-001"
  guard "$PROJ/.claude/qb/state" junior-dev
  [ $RC -eq 2 ] && ok "plan phase: developer cannot unlock by editing state" || bad "plan phase dev state edit" "rc=$RC"
  guard "$PROJ/.claude/qb/state"
  [ $RC -eq 0 ] && ok "plan phase: lead may edit state" || bad "plan phase lead state edit" "rc=$RC"

  # --- quality gate ---
  state "phase: plan" "ticket: T-001"
  printf 'false\n' > "$PROJ/.claude/qb/checks"
  gate senior-dev
  [ $RC -eq 0 ] && [ -z "$OUT" ] && ok "gate inert outside implement phase" || bad "gate inert outside implement" "$OUT"

  state "phase: implement" "ticket: T-002" "attempts: 0" "max_attempts: 2"
  printf '# comment\n\necho all good\ntrue\n' > "$PROJ/.claude/qb/checks"
  gate senior-dev
  case "$OUT" in *'"systemMessage"'*passed*) ok "gate passes when checks pass";; *) bad "gate pass" "$OUT";; esac
  [ "$(sget gate)" = passed ] && ok "state marked gate: passed" || bad "gate: passed in state"

  printf 'echo "boom: \\"quoted\\" \t tab" ; exit 3\n' > "$PROJ/.claude/qb/checks"
  gate junior-dev
  case "$OUT" in *'"decision": "block"'*) ok "gate blocks on failure";; *) bad "gate block" "$OUT";; esac
  if printf '%s' "$OUT" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["decision"]=="block" and "boom" in d["reason"] and "attempt 1 of 2" in d["reason"]' 2>/dev/null; then
    ok "block output is valid JSON with failure tail and attempt count"
  else bad "block JSON validity" "$OUT"; fi
  [ "$(sget attempts)" = 1 ] && ok "attempts incremented" || bad "attempts incremented" "$(sget attempts)"

  gate junior-dev
  case "$OUT" in *'attempt 2 of 2'*) ok "second failure still blocks";; *) bad "second block" "$OUT";; esac
  gate junior-dev
  case "$OUT" in *'"systemMessage"'*'after 2 attempts'*) ok "after max attempts: developer released";; *) bad "release after max" "$OUT";; esac
  [ "$(sget gate)" = failed ] && ok "state marked gate: failed for the lead" || bad "gate: failed in state"

  state "phase: implement" "ticket: T-003" "attempts: 0"
  gate Explore
  [ -z "$OUT" ] && ok "non-qb subagent ignored" || bad "non-dev subagent ignored" "$OUT"
  gate "qb:senior-dev"
  case "$OUT" in *block*) ok "namespaced agent type (qb:senior-dev) gated";; *) bad "namespaced agent" "$OUT";; esac

  rm "$PROJ/.claude/qb/checks"
  state "phase: implement" "ticket: T-004" "attempts: 0"
  gate senior-dev
  [ -z "$OUT" ] && ok "no checks and nothing detected: gate stays out of the way" || bad "no checks" "$OUT"

  printf '{"scripts":{"test":"exit 1"}}\n' > "$PROJ/package.json"
  gate senior-dev
  case "$OUT" in *'npm test'*) ok "auto-detects npm test from package.json";; *) bad "npm detect" "$OUT";; esac

  rm -rf "$PROJ"
}

run_suite
for p in python sed; do
  if [ "$p" = python ] && ! command -v python3 >/dev/null; then continue; fi
  QB_FORCE_PARSER=$p run_suite
done

echo
echo "passed: $PASS  failed: $FAIL"
[ $FAIL -eq 0 ]
