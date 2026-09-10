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
#   gastos.sh pay <expenseId> <year> <month> <currency> <amount> [--add|--set]
set -euo pipefail

die() { echo "gastos.sh: $*" >&2; exit 1; }

usage() {
  cat >&2 <<'EOF'
usage:
  gastos.sh expenses
  gastos.sh unpaid  [--month YYYY-MM]
  gastos.sh periods [--from YYYY-MM] [--to YYYY-MM]
  gastos.sh pay <expenseId> <year> <month> <currency> <amount> [--add|--set]
    month is 0-indexed (0=Jan, 6=Jul); currency is USD or ARS
    amount is a whole number
    --add  record one more payment on top of the month's running total
    --set  replace the month's total with this amount
    neither: the server defaults to "set", and refuses the write outright for
             expenses whose accumulate flag is true (see: gastos.sh expenses)
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

# accumulate_rejected <response-body> — true when the write was refused because
# the expense holds several payments per month. Keys on the `accumulate` field
# rather than the message, which is prose and free to change. jq stays optional.
accumulate_rejected() {
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$1" | jq -e '.accumulate == true' >/dev/null 2>&1
  else
    printf '%s' "$1" | grep -q '"accumulate"[[:space:]]*:[[:space:]]*true'
  fi
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
    op=""
    args=()
    while [ $# -gt 0 ]; do
      case "$1" in
        --add|--set)
          [ -z "$op" ] || die "--add and --set are mutually exclusive, and take no repeats"
          op="${1#--}"; shift ;;
        --*) die "unknown arg for pay: $1" ;;
        *) args+=("$1"); shift ;;
      esac
    done
    [ ${#args[@]} -eq 5 ] || usage 1
    expense_id="${args[0]}" year="${args[1]}" month="${args[2]}"
    currency="${args[3]}" amount="${args[4]}"
    [[ "$expense_id" =~ ^[0-9]+$ ]] || die "expenseId must be an integer"
    [[ "$year"       =~ ^[0-9]{4}$ ]] || die "year must be YYYY"
    [[ "$month"      =~ ^[0-9]+$ ]] && [ "$month" -ge 0 ] && [ "$month" -le 11 ] \
      || die "month must be 0-11 (0-indexed: 0=Jan, 6=Jul)"
    case "$currency" in USD|ARS) ;; *) die "currency must be USD or ARS" ;; esac
    # Whole units only. The API rejects negatives with a 400, and it rounds each
    # currency independently off the raw amount — so a fractional payment can
    # store 0 in the currency you sent while the other column keeps a real
    # balance. Nothing server-side catches that, and the bad row is invisible in
    # every total built on it afterwards, so refuse the decimal here instead.
    [[ "$amount" =~ ^[0-9]+$ ]] \
      || die "amount must be a whole number (a fraction rounds each currency separately and corrupts the row; 0 is valid with --set)"

    if [ -n "$op" ]; then
      body=$(printf '{"expenseId":%d,"year":%d,"month":%d,"currency":"%s","amount":%s,"op":"%s"}' \
        "$expense_id" "$year" "$month" "$currency" "$amount" "$op")
    else
      # No op key at all. The server defaults to "set" for ordinary expenses and
      # refuses accumulate ones outright — and that refusal is the point: it is
      # what stands in for a silent overwrite when the caller skipped the lookup.
      body=$(printf '{"expenseId":%d,"year":%d,"month":%d,"currency":"%s","amount":%s}' \
        "$expense_id" "$year" "$month" "$currency" "$amount")
    fi

    rc=0
    out=$(api_post "/api/period" "$body") || rc=$?
    if [ "$rc" -eq 0 ]; then
      printf '%s\n' "$out"
    else
      printf '%s\n' "$out" >&2
      if accumulate_rejected "$out"; then
        cat >&2 <<EOF

gastos.sh: expense $expense_id can hold several payments in one month, so the
write needs an explicit op. Nothing was recorded. Re-run with one of:
  --add   count $amount as one more payment on top of the month's total
  --set   make $amount the month's total, discarding payments already recorded
EOF
      fi
      exit "$rc"
    fi
    ;;

  -h|--help|help) usage 0 ;;
  *) die "unknown command: $cmd (try: expenses, unpaid, periods, pay)" ;;
esac
