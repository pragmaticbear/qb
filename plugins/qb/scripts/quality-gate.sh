#!/usr/bin/env bash
# SubagentStop hook: when the qb phase lock is "implement", run the
# project's checks before a developer subagent may report done. Failing
# output is sent back to the developer, up to max_attempts times; after that
# the developer may stop and the state is marked "gate: failed" for the lead.
# Inert when no state file exists or the phase is anything else.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/lib.sh"

input=$(cat)
dt_init "$input"

[ -f "$DT_STATE" ] || exit 0
[ "$(state_get phase)" = "implement" ] || exit 0

# Only gate qb developers when Claude Code tells us the agent type.
agent=$(json_field "$input" agent_type)
if [ -n "$agent" ]; then
  case "$agent" in
    *junior-dev*|*senior-dev*) ;;
    *) exit 0 ;;
  esac
fi

cd "$DT_ROOT" || exit 0

# ---- collect checks -------------------------------------------------------
CHECKS=()
if [ -f "$DT_CHECKS" ]; then
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%%$'\r'}"
    case "$line" in ''|\#*) continue ;; esac
    CHECKS+=("$line")
  done < "$DT_CHECKS"
else
  if [ -f package.json ]; then
    pm=npm
    if [ -f pnpm-lock.yaml ]; then pm=pnpm
    elif [ -f yarn.lock ]; then pm=yarn
    elif [ -f bun.lockb ] || [ -f bun.lock ]; then pm=bun
    fi
    if grep -Eq '"test"[[:space:]]*:' package.json \
       && ! grep -q 'no test specified' package.json; then
      CHECKS+=("$pm test")
    fi
    grep -Eq '"lint"[[:space:]]*:' package.json && CHECKS+=("$pm run lint")
    grep -Eq '"typecheck"[[:space:]]*:' package.json && CHECKS+=("$pm run typecheck")
  fi
  if [ -f pyproject.toml ] || [ -f pytest.ini ] || [ -f setup.cfg ] || [ -f tox.ini ]; then
    if command -v pytest >/dev/null 2>&1; then CHECKS+=("pytest -q")
    else CHECKS+=("python3 -m pytest -q"); fi
  fi
  [ -f Cargo.toml ] && CHECKS+=("cargo test --quiet")
  [ -f go.mod ] && CHECKS+=("go test ./...")
  if [ ${#CHECKS[@]} -eq 0 ] && [ -f Makefile ] && grep -Eq '^test:' Makefile; then
    CHECKS+=("make test")
  fi
fi

# Nothing to run: let the lead's diff review carry the weight.
[ ${#CHECKS[@]} -gt 0 ] || exit 0

# ---- run checks -----------------------------------------------------------
per_check_timeout="${QB_CHECK_TIMEOUT:-600}"
TO=""
if command -v timeout >/dev/null 2>&1; then TO="timeout $per_check_timeout"
elif command -v gtimeout >/dev/null 2>&1; then TO="gtimeout $per_check_timeout"
else
  printf '%s\n' "qb: no timeout/gtimeout on PATH; checks run without a per-check limit (install coreutils to enable QB_CHECK_TIMEOUT)" >&2
fi

failed=""
report=""
passed=0
# Never fall back to a predictable name in a shared /tmp (symlink races).
tmp_out=$(mktemp 2>/dev/null) || tmp_out="$DT_DIR/gate.tmp.$$"
for cmd in "${CHECKS[@]}"; do
  if $TO bash -c "$cmd" >"$tmp_out" 2>&1; then
    passed=$((passed + 1))
  else
    code=$?
    failed="${failed}${failed:+, }\`$cmd\`"
    tail_out=$(tail -n 60 "$tmp_out")
    report="${report}
--- \`$cmd\` exited $code (last 60 lines) ---
${tail_out}
"
  fi
done
rm -f "$tmp_out"

ticket=$(state_get ticket)
ticket="${ticket:-current ticket}"

if [ -z "$failed" ]; then
  state_set attempts 0
  state_set gate passed
  printf '{"systemMessage": "%s"}\n' \
    "$(json_escape "qb: quality gate passed for $ticket ($passed check(s)).")"
  exit 0
fi

# Cap report size so we don't flood the developer's context.
if [ ${#report} -gt 8000 ]; then
  report="${report:0:8000}
...[truncated]"
fi

max=$(state_get max_attempts)
max="${QB_MAX_GATE_ATTEMPTS:-${max:-3}}"
attempts=$(state_get attempts)
case "$attempts" in ''|*[!0-9]*) attempts=0 ;; esac
attempts=$((attempts + 1))
state_set attempts "$attempts"

if [ "$attempts" -gt "$max" ]; then
  state_set gate failed
  printf '{"systemMessage": "%s"}\n' \
    "$(json_escape "qb: quality gate still failing for $ticket after $max attempts (${failed}). The developer has been allowed to stop; the tech lead must reassign, rescope, or take over. State marked gate: failed.")"
  exit 0
fi

state_set gate failing
reason="qb quality gate FAILED for $ticket (attempt $attempts of $max). You cannot report DONE while checks fail. Failing: ${failed}.
${report}
Fix the underlying cause (do not skip, delete, or weaken tests), re-run the checks yourself, then finish with your DONE report."
printf '{"decision": "block", "reason": "%s"}\n' "$(json_escape "$reason")"
exit 0
