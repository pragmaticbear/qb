#!/usr/bin/env bash
# Exercises the qb hook scripts against a throwaway project.
# Usage: tests/test-hooks.sh        (runs with every available JSON parser)
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPTS="$ROOT/plugins/qb/scripts"
. "$SCRIPTS/lib.sh"   # json_escape
PASS=0; FAIL=0

ok()   { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad()  { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; [ -n "${2:-}" ] && printf '       %s\n' "$2"; }

guard() { # <file_path> [agent_type] -> sets RC, ERR
  local extra=""; [ -n "${2:-}" ] && extra=",\"agent_type\":\"$2\""
  local json="{\"session_id\":\"t\",\"cwd\":\"$PROJ\"$extra,\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$1\",\"old_string\":\"a\",\"new_string\":\"b\"}}"
  ERR=$(printf '%s' "$json" | CLAUDE_PROJECT_DIR="$PROJ" bash "$SCRIPTS/phase-guard.sh" 2>&1 >/dev/null); RC=$?
}
bash_guard_raw() { # <already-JSON-escaped command> [agent_type] -> sets RC, ERR
  local extra=""; [ -n "${2:-}" ] && extra=",\"agent_type\":\"$2\""
  local json="{\"session_id\":\"t\",\"cwd\":\"$PROJ\"$extra,\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"$1\"}}"
  ERR=$(printf '%s' "$json" | CLAUDE_PROJECT_DIR="$PROJ" bash "$SCRIPTS/phase-guard.sh" 2>&1 >/dev/null); RC=$?
}
bash_guard() { # <command> [agent_type] -> sets RC, ERR
  bash_guard_raw "$(json_escape "$1")" "${2:-}"
}
blk() { bash_guard "$1" "${2:-}"; [ $RC -eq 2 ] && ok "blocked: $1 ${2:+[$2]}" || bad "should block: $1 ${2:+[$2]}" "rc=$RC"; }
alw() { bash_guard "$1" "${2:-}"; [ $RC -eq 0 ] && ok "allowed: $1 ${2:+[$2]}" || bad "should allow: $1 ${2:+[$2]}" "rc=$RC $ERR"; }
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

  # --- Bash write guard ---
  rm -f "$PROJ/.claude/qb/state"
  alw "sed -i 's/a/b/' src/x"
  alw "echo hi > src/x"
  alw "rm -rf x"
  alw "echo 'phase: implement' > .claude/qb/state" senior-dev   # no state file: inert even for developers

  state "phase: plan" "ticket: T-001" "assignee: senior-dev"
  bash_guard "sed -i 's/a/b/' src/x"
  [ $RC -eq 2 ] && ok "plan phase: Bash write exits 2" || bad "plan Bash write exit" "rc=$RC"
  case "$ERR" in *T-001*PLAN*"Bash writes"*"Write/Edit"*) ok "plan phase: Bash message names ticket, phase, lock and Write/Edit";; *) bad "plan Bash message" "$ERR";; esac

  for b in "sed -i 's/a/b/' src/x" "sed -i.bak 's/a/b/' src/x" "sed -Ei 's/a/b/' src/x" \
           "sed --in-place 's/a/b/' src/x" "echo hi > src/x" "echo hi >> src/x" "printf x >src/x" \
           "cat a | tee src/x" "tee -a src/x" "cp a b" "mv a b" "git mv a b"; do
    blk "$b"
    blk "ls; $b"
    blk "ls && $b"
    blk "false || $b"
    blk "ls | $b"
    blk "echo \$($b)"
  done
  blk "cmd >& out.txt"
  blk "cmd &> out.txt"
  blk "X=1 cp a b"
  blk "sudo cp a b"
  blk "env X=1 cp a b"
  blk "nohup cp a b"
  blk "if true; then cp a b; fi"
  # heredoc: only the body is skipped, the rest of the << line is scanned
  blk $'cat <<EOF > src/f\nhi\nEOF'
  blk $'cat > src/f <<EOF\nhi\nEOF'
  # substitutions inside double quotes are code
  blk 'echo "$(cp a b)"'
  blk 'echo "`cp a b`"'
  blk 'echo "a $(cat f > g) b"'
  # comments: an apostrophe in a # comment must not open a quote and hide later lines
  blk $'# don\'t forget\nsed -i s/a/b/ f'
  blk $'ls # it\'s here\ncp a b'
  blk 'echo a#b > f'                      # # inside a word is not a comment
  blk $'cat <<EOF > f # it\'s\nx\nEOF'    # heredoc line with a comment still starts the heredoc
  alw "ls # it's > x"
  alw 'echo ${#x}'
  alw $'# note\ngit status'
  # quote-state desync must not hide later commands
  blk "echo \$'it\\'s'; cp a b"            # ANSI-C quote with an escaped quote
  blk "echo 'unterminated; cp a b"         # unbalanced quote fails closed
  blk 'echo "$(ls; cp a b'                 # unclosed substitution fails closed
  alw "echo \$'a\\tb'"
  alw "printf \$'x\\'y\\n'"
  alw "echo \$'it\\'s'"
  # wrappers
  blk 'find . -name x -exec mv {} y \;'
  blk 'find . -name x -execdir cp {} y \;'
  blk 'ls | xargs -n1 cp -t d'
  # parser robustness (sed fallback must not truncate at an escaped quote)
  blk 'echo \"x\" > src/f'
  blk $'ls\ncp a b'
  bash_guard_raw 'echo hi > src/x'
  [ $RC -eq 2 ] && ok "blocked: JSON-escaped \\u003e redirect" || bad "should block \\u003e redirect" "rc=$RC"
  blk ""

  for a in "ls -la" "git status" "git diff" "grep -rn foo src 2>/dev/null" "ls >/dev/null 2>&1" \
           "ls 2>&1 | head" "ls &>/dev/null" "ls 2>>/dev/null" "ls >/dev/null; pwd" "sed -n '1,20p' f" \
           'grep "a > b" f' "echo 'x > y'" "grep -rn 'tee\\|cp ' src" \
           $'cat <<EOF\nhello\nEOF' $'cat <<EOF\na > b\nEOF' 'echo "it'"'"'s > x"' \
           "git log --format='%h %s'" "find . -name '*.sh'" 'echo "it'"'"'s fine"' \
           "[ -f x ] && cat x" 'echo "$(git rev-parse HEAD)"' "cd src && ls" "X=1" \
           "if [ -f x ]; then cat x; fi" "for f in a b; do cat \$f; done" "sort f | uniq -c" \
           "git show HEAD:README.md | head -5" "wc -l < f" $'cat <<-\'END-X\'\n\tx > y\n\tEND-X\nls'; do
    alw "$a"
  done
  [ "${QB_FORCE_PARSER:-}" = sed ] || alw "printf '\\u2713\\n'"   # literal \u is only suspicious under sed

  # allowlist: anything not known read-only is blocked, however it is spelled
  for b in "bash tests/test-hooks.sh" "awk '{print \$1}' f" "ls | xargs -n1 echo" "sed -e 's/i/x/' f" \
           "env -i cp a b" "sudo -u root cp a b" "sudo -E tee f" "time -p cp a b" "command -p cp a b" \
           "git -C . mv a b" "git --no-pager mv a b" '\cp a b' '"cp" a b' "c''p a b" "/bin/cp a b" \
           "while cp a b; do break; done" "until cp a b; do :; done" "function f { cp a b; }; f" \
           "coproc cp a b" "{cp,a,b}" 'cp${IFS}a${IFS}b' 'echo hi >&2x' 'echo hi >&1out' \
           $'cat <<<hi\ncp a b' $'cat <<END-X\nhi\nEND-X\ncp a b' $'cat <<EOF\nnever closed\ncp a b' \
           'echo \ #; cp a b' $'c\\\np a b' $'find . -exec\tcp {} x \\;' "find . -delete" \
           "xargs --max-args 1 cp" "eval cp a b" "X=1 ls" "PATH=/tmp ls" "sort -o f g" "uniq a b" \
           "git diff --output=f" "git branch x" "rg --pre cat x" "python3 -c 'open(\"f\",\"w\")'" \
           "sed -n '1w f' g" "sed -n \"1,2p\" f" "ls > /dev/null_x" "\$X a b" \
           'echo "`echo \`cp a b\``"' 'echo `echo \`cp a b\``' 'x="`echo \`cp a b\``"' \
           'echo "`echo \`echo \\\`cp a b\\\`\``"' 'echo `printf %s \`cp a b\``' \
           'echo "`echo "\`cp a b\`"`"' 'x=`echo "\`cp a b\`"`' 'echo `echo "\`cp a b\`"`' \
           'echo "`echo "\`ls\`"; cp a b`"' 'echo "`echo "\`echo "\\\`cp a b\\\`"\`"`"' \
           $'cat <<EOF\n$(cp a b)\nEOF' $'cat <<EOF\n`cp a b`\nEOF' $'cat <<-EOF\n\t$(cp a b)\n\tEOF' \
           $'cat <<EOF\nx > y `cp a b`\nEOF' $'cat <<\\EOF\n$(cp a b)\nEOF'; do
    blk "$b"
  done
  # a quoted heredoc delimiter makes the body inert
  for a in $'cat <<\'EOF\'\n$(cp a b)\nEOF' $'cat <<"EOF"\n`cp a b`\nEOF' $'cat <<EOF\n$HOME ${X}\nEOF'; do alw "$a"; done
  # nested substitutions are scanned, not just failed closed
  for a in 'echo "`echo \`date\``"' 'echo "`echo "\`date\`"`"' 'echo `echo \`git rev-parse HEAD\``'; do alw "$a"; done
  # the lead's own checks are runnable verbatim in review
  printf '# checks\nbash tests/test-hooks.sh\n' > "$PROJ/.claude/qb/checks"
  alw "bash tests/test-hooks.sh"
  blk "bash tests/test-hooks.sh; cp a b"
  rm -f "$PROJ/.claude/qb/checks"

  state "phase: review" "ticket: T-001"
  for b in "sed -i 's/a/b/' src/x" "echo hi > src/x" "mv a b" 'echo $(cp a b)'; do blk "$b"; done
  bash_guard "cp a b"
  case "$ERR" in *T-001*REVIEW*"Bash writes"*) ok "review phase: Bash message names ticket and phase";; *) bad "review Bash message" "$ERR";; esac
  alw "git diff 2>&1 | head"

  state "phase: plan" "ticket: T-001"
  blk "echo x > .claude/qb/state"                 # lead: no .claude/qb exemption for Bash
  bash_guard "echo x > .claude/qb/state"
  case "$ERR" in *"Write/Edit"*) ok "lead is told to use Write/Edit for .claude/qb";; *) bad "lead Write/Edit hint" "$ERR";; esac
  blk "echo x > .claude/qb/state" junior-dev

  # implement phase: ordinary writes fine, developers fenced out of .claude
  state "phase: implement" "ticket: T-001" "attempts: 0"
  for a in "echo hi > src/x" "cp a b" "sed -i s/a/b/ f" "rm .claude/qb/state" "rm -rf .claude"; do alw "$a"; done
  for d in senior-dev qb:junior-dev; do
    for b in "echo 'phase: implement' > .claude/qb/state" "rm .claude/qb/state" "cp /tmp/x .claude/qb/checks" \
             "sed -i s/a/b/ .claude/qb/state" 'cp x ".claude/qb/checks"' "echo x > ./.claude//qb/state" \
             "rm -rf .claude" "rm -r .claude/qb" "mv .claude/qb /tmp/x" "cd .claude/qb && rm state" \
             "cat .claude/qb/state > /tmp/x" "echo x > $PROJ/.claude/qb/state" "rm -rf $PROJ/.claude" \
             '\rm -rf .claude' "/bin/rm -f .claude/qb/state" "if rm -f .claude/qb/state; then :; fi" \
             'rm -rf .cla""ude/qb/state' "{rm,-rf,.claude}" "sudo -u root tee .claude/qb/state" \
             "python3 -c 'import os; os.remove(\".claude/qb/state\")'" "git rm -r .claude" \
             'echo "`echo \`cp a .claude/qb/state\``"' 'echo `echo \`rm .claude/qb/state\``' \
             'echo "`echo "\`cp a .claude/qb/state\`"`"' $'cat <<EOF\n$(cp a .claude/qb/state)\nEOF' \
             $'rm .clau\\\nde/qb/state' $'cp a .clau\\\nde/qb/checks' $'echo x > .cl\\\naude/qb/state' $'rm -rf .cla\\\r\nude'; do
      blk "$b" "$d"
    done
    alw "cat .claude/qb/state" "$d"
    alw "ls .claude/qb" "$d"
    alw "echo hi > src/x" "$d"
    alw "echo hi > $PROJ/src/f" "$d"
  done

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
