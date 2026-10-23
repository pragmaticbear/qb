#!/usr/bin/env bash
# Shared helpers for qb hooks. Portable to bash 3.2 (macOS default).

# Read a top-level string field from a JSON document on $1.
# Prefers jq, then python3, then a best-effort sed fallback.
json_field() {
  local json="$1" field="$2" force="${QB_FORCE_PARSER:-}"
  if { [ -z "$force" ] || [ "$force" = jq ]; } && command -v jq >/dev/null 2>&1; then
    printf '%s' "$json" | jq -r --arg f "$field" '
      def find($f): (.[$f]? // .tool_input[$f]? // empty);
      find($f) | if type == "string" then . else tostring end' 2>/dev/null
    return 0
  fi
  if { [ -z "$force" ] || [ "$force" = python ]; } && command -v python3 >/dev/null 2>&1; then
    printf '%s' "$json" | python3 -c '
import json, sys
f = sys.argv[1]
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
v = d.get(f)
if v is None and isinstance(d.get("tool_input"), dict):
    v = d["tool_input"].get(f)
if v is not None:
    print(v if isinstance(v, str) else json.dumps(v))
' "$field" 2>/dev/null
    return 0
  fi
  # Last resort. The value regex accepts escaped characters so an escaped quote
  # does not truncate the field (a truncated command would fail open in the
  # Bash guard); then the common JSON escapes are decoded. \u003e, \u003c and
  # \u0026 are decoded; phase-guard.sh fails closed on any other \u left over.
  local v bs='\' q='"' nl=$'\n' ph=$'\001' fs=/ gt='>' lt='<' am='&'
  v=$(printf '%s' "$json" | tr '\n' ' ' \
    | sed -nE "s/.*\"$field\"[[:space:]]*:[[:space:]]*\"(([^\"\\\\]|\\\\.)*)\".*/\\1/p" | head -n1)
  v=${v//"$bs$bs"/$ph}; v=${v//"$bs$q"/$q}; v=${v//"$bs$fs"/$fs}  # fs in a variable: bash 3.2 reads a quoted / in ${v//p/r} as the delimiter
  v=${v//"${bs}n"/$nl}; v=${v//"${bs}t"/$'\t'}
  v=${v//"${bs}u003e"/$gt}; v=${v//"${bs}u003c"/$lt}; v=${v//"${bs}u0026"/$am}
  printf '%s\n' "${v//"$ph"/$bs}"
}

# Escape a string for embedding in a JSON string literal.
json_escape() {
  local s="$1"
  s=${s//\\/\\\\}
  s=${s//\"/\\\"}
  s=${s//$'\n'/\\n}
  s=${s//$'\r'/}
  s=${s//$'\t'/\\t}
  # strip remaining control characters
  printf '%s' "$s" | LC_ALL=C tr -d '\000-\010\013\014\016-\037'
}

# Resolve the project root and state paths.
dt_init() {
  local input="$1" cwd=""
  if [ -n "${CLAUDE_PROJECT_DIR:-}" ]; then
    DT_ROOT="$CLAUDE_PROJECT_DIR"
  else
    cwd=$(json_field "$input" cwd)
    DT_ROOT="${cwd:-$PWD}"
  fi
  DT_DIR="$DT_ROOT/.claude/qb"
  DT_STATE="$DT_DIR/state"
  DT_CHECKS="$DT_DIR/checks"
}

# state_get <key> — prints value or nothing.
state_get() {
  [ -f "$DT_STATE" ] || return 0
  grep -E "^$1[[:space:]]*:" "$DT_STATE" 2>/dev/null | head -n1 \
    | sed -E "s/^$1[[:space:]]*:[[:space:]]*//; s/[[:space:]]+$//"
}

# state_set <key> <value> — replaces or appends, atomically.
state_set() {
  local key="$1" val="$2" tmp
  [ -f "$DT_STATE" ] || return 0
  tmp="$DT_STATE.tmp.$$"
  awk -v k="$key" -v v="$val" '
    BEGIN { done = 0 }
    $0 ~ "^" k "[[:space:]]*:" { print k ": " v; done = 1; next }
    { print }
    END { if (!done) print k ": " v }
  ' "$DT_STATE" > "$tmp" && mv "$tmp" "$DT_STATE"
}
