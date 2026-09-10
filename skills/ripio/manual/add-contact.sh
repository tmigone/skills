#!/usr/bin/env bash
# add-contact.sh — save a bank contact on Ripio.
#
# This lives outside scripts/ on purpose. Withdrawals only reach saved contacts,
# so this list is the allowlist of where money can go, and adding to it is the
# one action that widens it. The agent-facing skill (scripts/ripio.sh) has no
# contact-creation command; this is the human's half of that split.
#
# Use a SEPARATE credential from the withdrawal one:
#   RIPIO_CONTACTS_API_KEY / RIPIO_CONTACTS_API_SECRET
# If those aren't set it falls back to RIPIO_API_KEY / RIPIO_API_SECRET, which
# works but collapses the split — the same key then both approves destinations
# and sends money to them.
#
# usage:
#   ./add-contact.sh <cvu|cbu|alias>
set -euo pipefail

BASE="https://api.ripio.com"
PATH_="/wallet/contacts/"

die() { echo "add-contact: $*" >&2; exit 1; }

command -v jq >/dev/null 2>&1 || die "jq is required but not on PATH"
command -v openssl >/dev/null 2>&1 || die "openssl is required but not on PATH"

[ $# -eq 1 ] || { echo "usage: add-contact.sh <cvu|cbu|alias>" >&2; exit 1; }
entity_number="$1"
[ -n "$entity_number" ] || die "account number must not be empty"

# Credentials resolve as a PAIR. Falling back per-variable would silently mix a
# contacts key with a withdrawal secret, and a mismatched pair fails as
# "Invalid signature" — which looks like a signing bug, not a config mistake.
if [ -n "${RIPIO_CONTACTS_API_KEY:-}" ] || [ -n "${RIPIO_CONTACTS_API_SECRET:-}" ]; then
  KEY="${RIPIO_CONTACTS_API_KEY:-}"
  SECRET="${RIPIO_CONTACTS_API_SECRET:-}"
  [ -n "$KEY" ] || die "RIPIO_CONTACTS_API_SECRET is set but RIPIO_CONTACTS_API_KEY is not — set both, or neither"
  [ -n "$SECRET" ] || die "RIPIO_CONTACTS_API_KEY is set but RIPIO_CONTACTS_API_SECRET is not — set both, or neither"
else
  KEY="${RIPIO_API_KEY:-}"
  SECRET="${RIPIO_API_SECRET:-}"
  [ -n "$KEY" ] && [ -n "$SECRET" ] \
    || die "set RIPIO_CONTACTS_API_KEY + RIPIO_CONTACTS_API_SECRET (preferred), or RIPIO_API_KEY + RIPIO_API_SECRET"
  echo "add-contact: warning — using the withdrawal credential; a separate contacts key keeps the two capabilities apart" >&2
fi

# BSD date has no %N, so `date +%s%3N` yields a literal "3N" on macOS.
ts=$(python3 -c 'import time;print(int(time.time()*1000))' 2>/dev/null \
  || perl -MTime::HiRes -e 'printf "%d", Time::HiRes::time()*1000' 2>/dev/null \
  || date +%s000)

# Compact JSON, so the string signed is byte-identical to the one sent.
body=$(jq -cn --arg n "$entity_number" '{type:"bank",entity_number:$n}')
sig=$(printf %s "${ts}POST${PATH_}${body}" \
  | openssl dgst -sha256 -hmac "$SECRET" -binary | openssl base64 -A)

echo "Adding bank contact: $entity_number" >&2
if out=$(curl -sS --fail-with-body --max-time 30 -X POST "$BASE$PATH_" \
  -H "Content-Type: application/json" \
  -H "Authorization: $KEY" \
  -H "Signature: $sig" \
  -H "Timestamp: $ts" \
  -d "$body"); then
  printf '%s\n' "$out"
else
  printf '%s\n' "$out" >&2
  # "Invalid signature" means the server's HMAC differs from ours, which almost
  # always means the secret doesn't belong to the key — not that the signing is
  # wrong. A complete-but-mismatched pair looks identical to a code bug from
  # here, so say it out loud.
  case "$out" in
    *"Invalid signature"*)
      echo >&2
      echo "add-contact: that means the secret does not match the key." >&2
      echo "  Re-copy the secret for $([ -n "${RIPIO_CONTACTS_API_KEY:-}" ] && echo RIPIO_CONTACTS_API_KEY || echo RIPIO_API_KEY) from app.ripio.com." >&2
      echo "  To verify which pair authenticates, GET /wallet/contacts/ with each." >&2
      ;;
  esac
  exit 1
fi
echo
