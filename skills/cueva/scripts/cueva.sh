#!/usr/bin/env bash
# cueva.sh — wrapper for the cueva fee API.
# Reads historical exchange fees and records new ones.
# Auth: reads the Bearer token from $CUEVA_AUTH_TOKEN.
# Base URL: reads $CUEVA_API_URL (no default — the deployment is not public).
#
# usage:
#   cueva.sh fees [--from YYYY-MM-DD] [--to YYYY-MM-DD] [--location <name>]
#   cueva.sh log  <date> <fee> <location>
set -euo pipefail

die() { echo "cueva.sh: $*" >&2; exit 1; }

usage() {
  cat >&2 <<'EOF'
usage:
  cueva.sh fees [--from YYYY-MM-DD] [--to YYYY-MM-DD] [--location <name>]
  cueva.sh log  <date> <fee> <location>
    date is YYYY-MM-DD; fee is a bare non-negative number; quote multi-word locations
EOF
  exit "${1:-1}"
}

[ $# -ge 1 ] || usage 1
[ -n "${CUEVA_AUTH_TOKEN:-}" ] || die "CUEVA_AUTH_TOKEN is not set — export it first"
[ -n "${CUEVA_API_URL:-}" ] || die "CUEVA_API_URL is not set — export it first (e.g. https://cueva.example.com)"

# Strip a trailing slash so "$BASE/api/x" can't become "//api/x".
BASE="${CUEVA_API_URL%/}"

# GET <path> — authenticated GET, fail on HTTP >= 400 (curl --fail-with-body
# prints the JSON error body and returns non-zero).
api_get() {
  curl -sS --fail-with-body \
    -H "Authorization: Bearer $CUEVA_AUTH_TOKEN" \
    "$BASE$1"
}

# POST <path> <json-body>
api_post() {
  curl -sS --fail-with-body \
    -X POST \
    -H "Authorization: Bearer $CUEVA_AUTH_TOKEN" \
    -H "content-type: application/json" \
    -d "$2" \
    "$BASE$1"
}

# url-encode a value for a query string. Location names contain spaces, and an
# unencoded one silently returns the wrong rows rather than erroring.
urlenc() {
  local s="$1" out="" c i
  for (( i=0; i<${#s}; i++ )); do
    c="${s:i:1}"
    case "$c" in
      [a-zA-Z0-9._~-]) out+="$c" ;;
      *) out+=$(printf '%%%02X' "'$c") ;;
    esac
  done
  printf '%s' "$out"
}

# Emit a quoted, escaped JSON string. Locations are free text, so a stray quote
# or backslash would otherwise produce a malformed body. Keeps jq optional.
json_str() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  printf '"%s"' "$s"
}

DATE_RE='^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
FEE_RE='^[0-9]+(\.[0-9]+)?$'

cmd="$1"; shift

case "$cmd" in
  fees)
    from="" to="" location=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --from)     from="${2:-}";     shift 2 || die "--from needs a value" ;;
        --to)       to="${2:-}";       shift 2 || die "--to needs a value" ;;
        --location) location="${2:-}"; shift 2 || die "--location needs a value" ;;
        *) die "unknown arg for fees: $1" ;;
      esac
    done
    q=""
    if [ -n "$from" ]; then
      [[ "$from" =~ $DATE_RE ]] || die "--from must be YYYY-MM-DD"
      q="from=$from"
    fi
    if [ -n "$to" ]; then
      [[ "$to" =~ $DATE_RE ]] || die "--to must be YYYY-MM-DD"
      q="${q:+$q&}to=$to"
    fi
    if [ -n "$location" ]; then
      q="${q:+$q&}location=$(urlenc "$location")"
    fi
    api_get "/api/fees${q:+?$q}"
    ;;

  log)
    [ $# -eq 3 ] || usage 1
    date="$1" fee="$2" location="$3"
    [[ "$date" =~ $DATE_RE ]] || die "date must be YYYY-MM-DD"
    [[ "$fee"  =~ $FEE_RE ]]  || die "fee must be a non-negative number (0 is valid — a waived fee)"
    [ -n "$location" ] || die "location must not be empty"
    body=$(printf '{"date":%s,"fee":%s,"location":%s}' \
      "$(json_str "$date")" "$fee" "$(json_str "$location")")
    api_post "/api/fees" "$body"
    ;;

  -h|--help|help) usage 0 ;;
  *) die "unknown command: $cmd (try: fees, log)" ;;
esac
