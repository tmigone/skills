#!/usr/bin/env bash
# gastos.sh — wrapper for the gastos household-expense API.
# Reads the roster, unpaid items, recorded payments, and records payments.
# Auth: reads the Bearer token from $GASTOS_AUTH_TOKEN.
# Base URL: reads $GASTOS_API_URL (no default — the deployment is not public).
#
# usage:
#   gastos.sh expenses
#   gastos.sh unpaid  [--month YYYY-MM]
#   gastos.sh periods [--from YYYY-MM] [--to YYYY-MM]
#   gastos.sh pay <expenseId> <year> <month> <currency> <amount>
set -euo pipefail

die() { echo "gastos.sh: $*" >&2; exit 1; }

usage() {
  cat >&2 <<'EOF'
usage:
  gastos.sh expenses
  gastos.sh unpaid  [--month YYYY-MM]
  gastos.sh periods [--from YYYY-MM] [--to YYYY-MM]
  gastos.sh pay <expenseId> <year> <month> <currency> <amount>
    month is 0-indexed (0=Jan, 6=Jul); currency is USD or ARS
EOF
  exit "${1:-1}"
}

[ $# -ge 1 ] || usage 1
[ -n "${GASTOS_AUTH_TOKEN:-}" ] || die "GASTOS_AUTH_TOKEN is not set — export it first"
[ -n "${GASTOS_API_URL:-}" ] || die "GASTOS_API_URL is not set — export it first (e.g. https://gastos.example.com)"

# Strip a trailing slash so "$BASE/api/x" can't become "//api/x".
BASE="${GASTOS_API_URL%/}"

# GET <path> — authenticated GET, fail on HTTP >= 400 (curl --fail-with-body
# prints the JSON error body and returns non-zero).
api_get() {
  curl -sS --fail-with-body \
    -H "Authorization: Bearer $GASTOS_AUTH_TOKEN" \
    "$BASE$1"
}

# POST <path> <json-body>
api_post() {
  curl -sS --fail-with-body \
    -X POST \
    -H "Authorization: Bearer $GASTOS_AUTH_TOKEN" \
    -H "content-type: application/json" \
    -d "$2" \
    "$BASE$1"
}

# url-encode a value for a query string (handles spaces, etc.)
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

MONTH_RE='^[0-9]{4}-[0-9]{2}$'

cmd="$1"; shift

case "$cmd" in
  expenses)
    [ $# -eq 0 ] || die "expenses takes no arguments"
    api_get "/api/expenses"
    ;;

  unpaid)
    month=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --month) month="${2:-}"; shift 2 || die "--month needs a value" ;;
        *) die "unknown arg for unpaid: $1" ;;
      esac
    done
    if [ -n "$month" ]; then
      [[ "$month" =~ $MONTH_RE ]] || die "--month must be YYYY-MM"
      api_get "/api/unpaid?month=$month"
    else
      api_get "/api/unpaid"
    fi
    ;;

  periods)
    from="" to=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --from) from="${2:-}"; shift 2 || die "--from needs a value" ;;
        --to)   to="${2:-}";   shift 2 || die "--to needs a value" ;;
        *) die "unknown arg for periods: $1" ;;
      esac
    done
    q=""
    if [ -n "$from" ]; then
      [[ "$from" =~ $MONTH_RE ]] || die "--from must be YYYY-MM"
      q="from=$from"
    fi
    if [ -n "$to" ]; then
      [[ "$to" =~ $MONTH_RE ]] || die "--to must be YYYY-MM"
      q="${q:+$q&}to=$to"
    fi
    api_get "/api/periods${q:+?$q}"
    ;;

  pay)
    [ $# -eq 5 ] || usage 1
    expense_id="$1" year="$2" month="$3" currency="$4" amount="$5"
    [[ "$expense_id" =~ ^[0-9]+$ ]] || die "expenseId must be an integer"
    [[ "$year"       =~ ^[0-9]{4}$ ]] || die "year must be YYYY"
    [[ "$month"      =~ ^[0-9]+$ ]] && [ "$month" -ge 0 ] && [ "$month" -le 11 ] \
      || die "month must be 0-11 (0-indexed: 0=Jan, 6=Jul)"
    case "$currency" in USD|ARS) ;; *) die "currency must be USD or ARS" ;; esac
    [[ "$amount" =~ ^-?[0-9]+(\.[0-9]+)?$ ]] || die "amount must be a number"
    body=$(printf '{"expenseId":%d,"year":%d,"month":%d,"currency":"%s","amount":%s}' \
      "$expense_id" "$year" "$month" "$currency" "$amount")
    api_post "/api/period" "$body"
    ;;

  -h|--help|help) usage 0 ;;
  *) die "unknown command: $cmd (try: expenses, unpaid, periods, pay)" ;;
esac
