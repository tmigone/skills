#!/usr/bin/env bash
# ripio.sh — wrapper for the Ripio Wallet API.
# Reads balances and bank contacts, and creates CVU withdrawals.
#
# This script deliberately cannot add contacts. Withdrawals only reach saved
# contacts, so the contact list is the allowlist of where money can go; widening
# it is a human action with a separate credential, via ../manual/add-contact.sh.
# Do not add a contact-creation command here.
#
# Auth: RIPIO_API_KEY + RIPIO_API_SECRET.
#
# usage:
#   ripio.sh balance
#   ripio.sh contacts
#   ripio.sh withdraw <amount> <cvu|cbu|alias>
set -euo pipefail

BASE="https://api.ripio.com"

# Hard ceiling on a single withdrawal, in ARS. Note that this stops mistakes, not an
# attacker — anything holding the credentials can call the API directly.
WITHDRAW_CEILING_ARS=500000

# Backstop so a misbehaving cursor can't loop forever while paging contacts.
MAX_CONTACT_PAGES=50

die() { echo "ripio.sh: $*" >&2; exit 1; }

usage() {
  cat >&2 <<'EOF'
usage:
  ripio.sh balance                            account balances
  ripio.sh contacts                           every saved bank contact
  ripio.sh withdraw <amount> <cvu|cbu|alias>  ARS withdrawal to a saved contact

amount is ARS, up to 2 decimals, minimum 0.01, capped by the ceiling in this file.
Adding a contact is not possible here — the account owner runs ../manual/add-contact.sh.
EOF
  exit "${1:-1}"
}

command -v jq >/dev/null 2>&1 || die "jq is required but not on PATH"
command -v openssl >/dev/null 2>&1 || die "openssl is required but not on PATH"

[ $# -ge 1 ] || usage 1
cmd="$1"; shift

KEY="${RIPIO_API_KEY:-}"
SECRET="${RIPIO_API_SECRET:-}"
case "$cmd" in
  -h|--help|help) ;;
  *)
    [ -n "$KEY" ] || die "RIPIO_API_KEY is not set — export it first"
    [ -n "$SECRET" ] || die "RIPIO_API_SECRET is not set — export it first"
    ;;
esac

# Milliseconds since epoch. BSD date has no %N, so `date +%s%3N` produces a
# literal "3N" on macOS and every request fails auth with a garbage timestamp.
ms_now() {
  python3 -c 'import time;print(int(time.time()*1000))' 2>/dev/null \
    || perl -MTime::HiRes -e 'printf "%d", Time::HiRes::time()*1000' 2>/dev/null \
    || date +%s000
}

sign() {
  printf %s "$1" | openssl dgst -sha256 -hmac "$SECRET" -binary | openssl base64 -A
}

# api <METHOD> <path> [query] [body]
# The signature covers the path only; the request carries the query string.
api() {
  local method="$1" path="$2" query="${3:-}" body="${4:-}" ts sig out
  ts="$(ms_now)"
  sig="$(sign "${ts}${method}${path}${body}")"

  if [ -n "$body" ]; then
    out=$(curl -sS --fail-with-body --max-time 30 -X "$method" "$BASE$path$query" \
      -H "Content-Type: application/json" \
      -H "Authorization: $KEY" \
      -H "Signature: $sig" \
      -H "Timestamp: $ts" \
      -d "$body") || { echo "$out" >&2; exit 1; }
  else
    out=$(curl -sS --fail-with-body --max-time 30 -X "$method" "$BASE$path$query" \
      -H "Content-Type: application/json" \
      -H "Authorization: $KEY" \
      -H "Signature: $sig" \
      -H "Timestamp: $ts") || { echo "$out" >&2; exit 1; }
  fi

  # Every response uses {error_code, message, data}. A populated error_code on a
  # 2xx would otherwise read as success.
  if [ "$(printf '%s' "$out" | jq -r '.error_code // "null"')" != "null" ]; then
    printf '%s\n' "$out" >&2
    die "API returned $(printf '%s' "$out" | jq -r '.error_code'): $(printf '%s' "$out" | jq -r '.message // "no message"')"
  fi
  printf '%s\n' "$out"
}

AMOUNT_RE='^[0-9]+(\.[0-9]{1,2})?$'

case "$cmd" in
  balance)
    [ $# -eq 0 ] || die "balance takes no arguments"
    api GET /wallet/balance/
    ;;

  contacts)
    [ $# -eq 0 ] || die "contacts takes no arguments"
    # Cursors are followed here rather than exposed. Callers always want the
    # whole allowlist, and a partial page reads as "that account isn't saved" —
    # a wrong answer from a correct-looking call.
    all='[]' cursor="" pages=0
    while :; do
      # This skill is bank-only, so the filter is not optional.
      q="?contact_type=bank"
      [ -n "$cursor" ] && q="$q&cursor=$cursor"
      page=$(api GET /wallet/contacts/ "$q")
      all=$(printf '%s' "$page" | jq -c --argjson a "$all" '$a + (.data.results // [])')
      cursor=$(printf '%s' "$page" | jq -r '.data.nc // empty')
      pages=$((pages + 1))
      [ -n "$cursor" ] || break
      [ "$pages" -lt "$MAX_CONTACT_PAGES" ] \
        || die "contact cursor did not terminate after $MAX_CONTACT_PAGES pages"
    done
    jq -n --argjson r "$all" '{error_code:null,message:null,data:{results:$r,count:($r|length)}}'
    ;;

  withdraw)
    [ $# -eq 2 ] || usage 1
    amount="$1" bank_account="$2"

    [[ "$amount" =~ $AMOUNT_RE ]] || die "amount must be a positive number with at most 2 decimals"
    awk -v a="$amount" 'BEGIN{exit !(a+0 >= 0.01)}' || die "amount must be at least 0.01"
    awk -v a="$amount" -v c="$WITHDRAW_CEILING_ARS" 'BEGIN{exit !(a+0 <= c)}' \
      || die "amount $amount exceeds the ${WITHDRAW_CEILING_ARS} ARS ceiling — raise it by editing ripio.sh, there is no flag"
    [ -n "$bank_account" ] || die "destination account must not be empty"

    # bank_account is documented as an integer but the doc's own example is an
    # alias, and CVUs are 22 digits — send it as a string.
    body=$(jq -cn --arg a "$amount" --arg b "$bank_account" \
      '{amount:$a,currency:"ARS",gateway_data:{bank_account:$b}}')
    api POST /wallet/transactions/bank/withdrawal/ "" "$body"
    ;;

  contact-add|add-contact)
    die "adding contacts is not part of this skill — the account owner runs ../manual/add-contact.sh with the contacts credential"
    ;;

  -h|--help|help) usage 0 ;;
  *) die "unknown command: $cmd (try: balance, contacts, withdraw)" ;;
esac
