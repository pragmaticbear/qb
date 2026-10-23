#!/usr/bin/env bash
# PreToolUse hook: while the qb phase lock is "plan" or "review",
# block file edits outside .claude/qb/ and any Bash command that isn't a known
# read-only one. Developers are also fenced out of .claude in every phase.
# Inert when no state file exists.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/lib.sh"

# Neutralise quoting and drop heredoc bodies so quoted text is never read as
# code. Double-quoted and ANSI-C spans become "_"; single-quoted spans become
# "_Q" plus their text with every shell metacharacter turned into "_" (so
# `sed -n '1,20p'` stays checkable). $( ) and backticks, including nested
# backticks written with escaped backticks, are code: they are emitted unquoted,
# between ";" separators, and the rest of a double-quoted string becomes the
# argument of a ":" no-op.
strip_quotes() {
  awk '
  { buf = buf $0 "\n" }
  END {
    n = length(buf); out = ""; st = ""; sp = 0; pend = ""; unterm = 0; i = 1
    while (i <= n) {
      c = substr(buf, i, 1)
      if (st == "s") {
        if (c == "\047") { st = ""; gsub(/[^A-Za-z0-9,.$\/%:=+@^_-]/, "_", q); out = out "_Q" q }
        else q = q c
        i++; continue
      }
      if (st == "a") {   # ANSI-C quote (dollar + single quote): a backslash escapes the next char
        if (c == "\\") { i += 2; continue }
        if (c == "\047") { st = ""; out = out "_" }
        i++; continue
      }
      # Backticks. Each enclosing backtick level strips one layer of backslashes
      # ("\\" -> "\", "\`" -> "`"), so walk the levels: an even count closes the
      # innermost level, an odd one is passed inward. Whatever reaches the
      # innermost context opens a new level (even) or is a literal (odd).
      if ((st == "" || st == "d") && (c == "`" || c == "\\")) {
        nb = 0; while (substr(buf, i+nb, 1) == "\\") nb++
        if (substr(buf, i+nb, 1) == "`") {
          bd = 0; for (k = 1; k <= sp; k++) if (stk[k] == "b`") bd++
          r = nb; act = "open"
          for (k = 1; k <= bd; k++) {
            if (r % 2 == 0) { act = (k == bd && stk[sp] == "b`") ? "close" : "bad"; break }
            r = (r - 1) / 2
          }
          if (act == "open" && r % 2 == 1) act = "lit"
          if (act == "close") { st = sav[sp]; sp--; out = out (st == "d" ? ";: " : ";") }
          else if (act == "open") { stk[++sp] = "b`"; sav[sp] = st; st = ""; out = out ";" }
          else if (act == "lit") out = out "_"
          else out = out "\n>"      # closes a level that is not innermost: desync, fail closed
          i += nb + 1; continue
        }
      }
      if (st == "d") {
        if (c == "\\") { i += 2; continue }
        if (c == "\"") { st = ""; out = out "_"; i++; continue }
        if (c == "$" && substr(buf, i+1, 1) == "(") { stk[++sp] = "d("; dep[sp] = 0; st = ""; out = out ";"; i += 2; continue }
        i++; continue
      }
      if (sp > 0 && stk[sp] == "d(") {
        if (c == "(") dep[sp]++
        else if (c == ")") { if (dep[sp] == 0) { sp--; st = "d"; out = out ";: "; i++; continue } dep[sp]-- }
      }
      # comment: a "#" that starts a word (judged on the output, so an escaped
      # space before it does not count). Skip to, not past, the newline so a
      # pending heredoc still fires.
      if (c == "#" && (out == "" || index(" \t\n;|&(", substr(out, length(out), 1)) > 0)) {
        i += index(substr(buf, i), "\n") - 1; continue
      }
      if (c == "\\") {
        if (substr(buf, i+1, 1) != "\n") out = out "_"   # backslash-newline joins lines
        i += 2; continue
      }
      if (c == "$" && substr(buf, i+1, 1) == "\047") { st = "a"; i += 2; continue }
      if (c == "\047") { st = "s"; q = ""; i++; continue }
      if (c == "\"") { st = "d"; i++; continue }
      if (c == "\n" && pend != "") {
        out = out "\n"; j = i + 1; found = 0
        while (j <= n) {
          e = index(substr(buf, j), "\n"); line = substr(buf, j, e - 1); j += e
          t = line; sub(/^\t+/, "", t); if (t == pend) { found = 1; break }
          # an unquoted delimiter means bash expands $( ) and backticks in the body: fail closed
          if (!pq && (index(line, "$(") || index(line, "`"))) unterm = 1
        }
        if (!found) unterm = 1
        pend = ""; i = j; continue
      }
      if (substr(buf, i, 3) == "<<<") { out = out "<<<"; i += 3; continue }
      if (substr(buf, i, 2) == "<<") {
        rest = substr(buf, i + 2); k = 0
        if (match(rest, /^-?[ \t]*/)) k = RLENGTH
        r2 = substr(rest, k + 1)
        if (match(r2, /^\047[^\047]*\047/) || match(r2, /^"[^"]*"/)) { pend = substr(r2, 2, RLENGTH - 2); L = RLENGTH; pq = 1 }
        else if (match(r2, /^[^ \t\n;|&<>()\047"\\]+/)) { pend = substr(r2, 1, RLENGTH); L = RLENGTH; pq = 0 }
        else { out = out c; i++; continue }
        out = out "<<_"; i += 2 + k + L; continue
      }
      out = out c; i++
    }
    # A real shell rejects unbalanced quotes, so ending inside one (or with a
    # heredoc whose delimiter never shows up) means the scanner desynced; an
    # unquoted heredoc body with $( ) or a backtick is code we did not scan.
    # Either way emit a ">" line so the command counts as a write (fail closed).
    if (st != "" || sp > 0 || unterm) out = out "\n>"
    printf "%s", out
  }'
}

# seg_ok <segment>: 0 if the quote-stripped segment is a known read-only
# command. Anything unknown, renamed (/bin/cp, \cp, "cp"), prefixed (sudo, env,
# VAR=x cmd) or carrying a surviving ">" is not.
seg_ok() {
  local s="$1" prev w n=0 nf= sc=
  case "$s" in *'>'*) return 1 ;; esac
  while :; do   # control keywords run nothing themselves; check what follows
    prev=$s
    s=$(printf '%s' "$s" | sed -E 's/^[[:space:]]+//; s/^(if|elif|then|else|fi|while|until|do|done|esac|!|[{]|[}])([[:space:]]+|$)//')
    [ "$s" = "$prev" ] && break
  done
  set -f; set -- $s; set +f
  [ $# -eq 0 ] && return 0
  case "${1%%=*}" in
    "$1"|*[!A-Za-z0-9_]*) ;;
    *) # assignments only (X=1) are fine; an assignment prefixing a command is not
      for w; do case "$w" in *=*) ;; *) return 1 ;; esac; done; return 0 ;;
  esac
  w=$1; shift
  case "$w" in
    ls|cat|head|tail|wc|grep|egrep|fgrep|cut|tr|nl|tac|rev|paste|column|comm|cmp|diff|\
    basename|dirname|realpath|readlink|pwd|date|uname|whoami|id|printenv|seq|true|false|:|\
    od|strings|shasum|sha256sum|md5sum|md5|file|stat|du|df|jq|echo|printf|test|'['|'[['|\
    cd|type|which|for|case|exit|break|continue)
      return 0 ;;
    command) [ "${1:-}" = -v ] || [ "${1:-}" = -V ]; return ;;
    rg) for w; do case "$w" in --pre*) return 1 ;; esac; done; return 0 ;;
    tree) for w; do case "$w" in -o*) return 1 ;; esac; done; return 0 ;;
    sort) for w; do case "$w" in --output*|--compress-program*) return 1 ;; --*) ;; -*o*) return 1 ;; esac; done; return 0 ;;
    uniq) for w; do case "$w" in -*) ;; *) n=$((n+1)) ;; esac; done; [ $n -le 1 ]; return ;;
    find)
      for w; do case "$w" in -exec|-execdir|-ok|-okdir|-delete|-fprint|-fprint0|-fprintf|-fls) return 1 ;; esac; done
      return 0 ;;
    sed) # only `sed -n 'N,Mp' [files]`: a print-only script we can see
      for w; do
        case "$w" in
          -*[!nEr]*) return 1 ;;
          -*) case "$w" in *n*) nf=1 ;; esac ;;
          *) [ -n "$sc" ] || sc=$w ;;
        esac
      done
      [ -n "$nf" ] || return 1
      case "${sc#_Q}" in ''|*[!0-9,\$p]*) return 1 ;; *p) return 0 ;; esac
      return 1 ;;
    git)
      while [ $# -gt 0 ]; do
        case "$1" in --no-pager) shift ;; -C) shift; [ $# -gt 0 ] && shift ;; *) break ;; esac
      done
      w=${1:-}; [ $# -gt 0 ] && shift
      for prev; do case "$prev" in --output*|-O*|--open-files-in-pager*) return 1 ;; esac; done
      case "$w" in
        status|diff|log|show|blame|grep|ls-files|rev-parse|shortlog|describe) return 0 ;;
        branch)
          for prev; do
            case "$prev" in -a|-r|-v|-vv|-l|--list|--all|--remotes|--verbose|--show-current|--no-color) ;; *) return 1 ;; esac
          done
          return 0 ;;
      esac ;;
  esac
  return 1
}

# bash_readonly <command>: 0 if every segment of the command is read-only.
# ponytail: allowlist over a quote-aware word scan, not a shell parser. Known
#   false positives: (( a > b )), [[ a > b ]], writes to /dev/stderr, case-arm
#   patterns, anything not on the list (add it to seg_ok). A scanner desync that
#   ends unbalanced fails closed. Upgrade path: run the Bash tool in a sandbox.
bash_readonly() {
  local seps=$';|&()\x60' cleaned seg
  cleaned=$(printf '%s' "$1" | strip_quotes \
    | sed -E 's/[0-9]*>&([0-9]+|-)([[:space:];|&)`]|$)/ \2/g; s/(&>>?|[0-9]*>>?)[[:space:]]*\/dev\/null([[:space:];|&)`]|$)/ \2/g' \
    | tr "$seps" '\n\n\n\n\n\n')
  while IFS= read -r seg; do
    seg_ok "$seg" || return 1
  done <<EOF
$cleaned
EOF
  return 0
}

# checks_line <command>: 0 if the command is, verbatim, a line of the lead's
# .claude/qb/checks (developers cannot edit that file), so checks run in review.
checks_line() {
  local l
  [ -f "$DT_CHECKS" ] || return 1
  while IFS= read -r l || [ -n "$l" ]; do
    case "$l" in ''|'#'*) continue ;; esac
    [ "$l" = "$1" ] && return 0
  done < "$DT_CHECKS"
  return 1
}

input=$(cat)
dt_init "$input"

[ -f "$DT_STATE" ] || exit 0

if [ "$(json_field "$input" tool_name)" = Bash ]; then
  cmd=$(json_field "$input" command)
  # \u escapes the sed fallback could not decode: fail closed rather than mis-scan.
  # jq and python decode everything, so a literal \u from them is just text.
  sed_parser=1
  case "${QB_FORCE_PARSER:-}" in ''|jq) command -v jq >/dev/null 2>&1 && sed_parser= ;; esac
  case "${QB_FORCE_PARSER:-}" in ''|python) command -v python3 >/dev/null 2>&1 && sed_parser= ;; esac
  undecoded=
  [ -n "$sed_parser" ] && case "$cmd" in *'\u'*) undecoded=1 ;; esac

  # Developers may never touch .claude (lock, checks, board) through Bash, in any
  # phase: a command that mentions it must be read-only. Quotes and backslashes
  # are dropped (.cla""ude) and the project root stripped (absolute in-project
  # paths count as relative) before looking.
  # ponytail: a path built at runtime (D=.cla; rm ${D}ude, globs) is not seen.
  case "$(json_field "$input" agent_type)" in
    *junior-dev*|*senior-dev*)
      rel=${cmd//[\'\"\\]/}; rel=${rel//"$DT_ROOT"/}
      case "$rel" in
        *.claude*)
          if [ -n "$undecoded" ] || ! bash_readonly "$cmd"; then
            printf '%s\n' "qb: developers cannot modify .claude/ (state, checks, board) with Bash. Those belong to the tech lead. If a check is wrong, say so in your report." >&2
            exit 2
          fi ;;
      esac ;;
  esac

  phase=$(state_get phase)
  case "$phase" in
    plan|review) ;;
    *) exit 0 ;;
  esac
  checks_line "$cmd" && exit 0
  if [ -z "$cmd" ] || [ -n "$undecoded" ] || ! bash_readonly "$cmd"; then
    ticket=$(state_get ticket)
    printf '%s\n' "qb: ${ticket:-the current ticket} is in $(printf '%s' "$phase" | tr a-z A-Z) phase. Bash writes are locked: only known read-only commands run (ls, cat, grep, rg, find, sed -n 'Np', git status/diff/log/show, ...), with no output redirects. Developers: return your PLAN instead. Lead: use Write/Edit for .claude/qb/ files, run a .claude/qb/checks line verbatim, or delete .claude/qb/state to take over." >&2
    exit 2
  fi
  exit 0
fi

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
