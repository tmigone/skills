#!/usr/bin/env bash
set -euo pipefail

# Carrefour Argentina Shopping List Manager
# Uses VTEX Catalog System API

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_ROOT="${SCRIPT_DIR}/.."
DATA_DIR="${SKILLS_STATE_DIR:-${SKILL_ROOT}/state}/carrefour.ar"
LIST_FILE="${DATA_DIR}/shopping_list.json"

BASE_URL="https://www.carrefour.com.ar"
API_URL="${BASE_URL}/api/catalog_system/pub/products/search"

# Ensure data directory and list file exist
mkdir -p "$DATA_DIR"
[[ -f "$LIST_FILE" ]] || echo '{"items":[]}' > "$LIST_FILE"

# URL encode a string
urlencode() {
  jq -rn --arg s "$1" '$s | @uri'
}

# Search for products
cmd_search() {
  local json_output=false
  if [[ "${1:-}" == "--json" ]]; then
    json_output=true
    shift
  fi

  local query="${1:-}"
  if [[ -z "$query" ]]; then
    echo "Usage: carrefour.sh search [--json] <query>" >&2
    exit 1
  fi

  local encoded=$(urlencode "$query")
  local results=$(curl -s "${API_URL}?ft=${encoded}")

  if [[ "$json_output" == true ]]; then
    echo "$results" | jq '[.[] | select(.items[0].sellers[0].commertialOffer.Price > 0) | {sku: .items[0].itemId, name: .productName, price: .items[0].sellers[0].commertialOffer.Price}]'
  else
    echo "$results" | jq -r '
      .[] |
      select(.items[0].sellers[0].commertialOffer.Price > 0) |
      "\(.items[0].itemId)|\(.productName)|\(.items[0].sellers[0].commertialOffer.Price)"
    ' | while IFS='|' read -r sku name price; do
      printf "%-8s %-50s \$%s\n" "$sku" "${name:0:50}" "$price"
    done
  fi
}

# Add item to shopping list
cmd_add() {
  local sku="${1:-}"
  local qty="${2:-1}"

  if [[ -z "$sku" ]]; then
    echo "Usage: carrefour.sh add <sku> [qty]" >&2
    exit 1
  fi

  # Check if SKU already exists, update qty if so
  local exists=$(jq --arg sku "$sku" '.items[] | select(.sku == $sku) | .sku' "$LIST_FILE")

  if [[ -n "$exists" ]]; then
    # Update existing item quantity
    jq --arg sku "$sku" --argjson qty "$qty" '
      .items |= map(if .sku == $sku then .qty += $qty else . end)
    ' "$LIST_FILE" > "${LIST_FILE}.tmp" && mv "${LIST_FILE}.tmp" "$LIST_FILE"
    echo "Updated: SKU $sku (added $qty more)"
  else
    # Fetch product info from API
    local product=$(curl -s "${API_URL}?fq=skuId:${sku}" | jq '.[0] // empty')

    if [[ -z "$product" ]]; then
      echo "SKU $sku not found. Adding without product info." >&2
      jq --arg sku "$sku" --argjson qty "$qty" '
        .items += [{"sku": $sku, "name": "Unknown", "price": 0, "qty": $qty, "seller": "1"}]
      ' "$LIST_FILE" > "${LIST_FILE}.tmp" && mv "${LIST_FILE}.tmp" "$LIST_FILE"
    else
      # Extract product info and add to list
      local name=$(echo "$product" | jq -r '.productName')
      local price=$(echo "$product" | jq -r '.items[0].sellers[0].commertialOffer.Price')

      jq --arg sku "$sku" --arg name "$name" --argjson price "$price" --argjson qty "$qty" '
        .items += [{"sku": $sku, "name": $name, "price": $price, "qty": $qty, "seller": "1"}]
      ' "$LIST_FILE" > "${LIST_FILE}.tmp" && mv "${LIST_FILE}.tmp" "$LIST_FILE"
      echo "Added: ${qty}x ${name} (\$${price})"
    fi
  fi
}

# Remove item from list
cmd_remove() {
  local sku="${1:-}"

  if [[ -z "$sku" ]]; then
    echo "Usage: carrefour.sh remove <sku>" >&2
    exit 1
  fi

  local before=$(jq '.items | length' "$LIST_FILE")
  jq --arg sku "$sku" '.items |= map(select(.sku != $sku))' "$LIST_FILE" > "${LIST_FILE}.tmp" && mv "${LIST_FILE}.tmp" "$LIST_FILE"
  local after=$(jq '.items | length' "$LIST_FILE")

  if [[ "$before" -eq "$after" ]]; then
    echo "SKU $sku not found in list"
  else
    echo "Removed SKU $sku"
  fi
}

# Show shopping list
cmd_list() {
  local count=$(jq '.items | length' "$LIST_FILE")

  if [[ "$count" -eq 0 ]]; then
    echo "Shopping list is empty"
    return
  fi

  echo "=== Carrefour Shopping List ==="
  echo ""

  jq -r '.items[] | "\(.qty)|\(.sku)|\(.name)|\(.price)"' "$LIST_FILE" | while IFS='|' read -r qty sku name price; do
    local subtotal=$(echo "$qty * $price" | bc 2>/dev/null || echo "0")
    printf "%3sx %-45s \$%-10s = \$%s\n" "$qty" "${name:0:45}" "$price" "$subtotal"
  done

  echo ""
  echo "---"
  local total_items=$(jq '[.items[].qty] | add // 0' "$LIST_FILE")
  local total_price=$(jq '[.items[] | .qty * .price] | add // 0' "$LIST_FILE")
  echo "Total: ${total_items} items, \$${total_price} ARS"
}

# Clear shopping list
cmd_clear() {
  echo '{"items":[]}' > "$LIST_FILE"
  echo "Shopping list cleared"
}

# Generate checkout URL(s)
cmd_checkout() {
  local count=$(jq '.items | length' "$LIST_FILE")

  if [[ "$count" -eq 0 ]]; then
    echo "Shopping list is empty" >&2
    exit 1
  fi

  # Build URL params from items
  local items=$(jq -r '.items[] | "sku=\(.sku)&qty=\(.qty)&seller=\(.seller // "1")"' "$LIST_FILE")
  local params=$(echo "$items" | tr '\n' '&' | sed 's/&$//')
  local url="${BASE_URL}/checkout/cart/add?${params}"
  local url_len=${#url}

  echo "=== Checkout URLs ==="
  echo ""

  if [[ $url_len -le 4000 ]]; then
    # Single URL fits
    echo "$url"
  else
    # Need to split into batches
    local batch=1
    local current_params=""
    local item_count=0

    while IFS= read -r item_param; do
      local test_params="${current_params}&${item_param}"
      local test_url="${BASE_URL}/checkout/cart/add?${test_params}"

      if [[ ${#test_url} -gt 4000 && -n "$current_params" ]]; then
        # Output current batch
        echo "Link $batch:"
        echo "${BASE_URL}/checkout/cart/add?${current_params}"
        echo ""
        batch=$((batch + 1))
        current_params="$item_param"
        item_count=1
      else
        if [[ -n "$current_params" ]]; then
          current_params="${current_params}&${item_param}"
        else
          current_params="$item_param"
        fi
        item_count=$((item_count + 1))
      fi
    done <<< "$items"

    # Output final batch
    if [[ -n "$current_params" ]]; then
      echo "Link $batch:"
      echo "${BASE_URL}/checkout/cart/add?${current_params}"
    fi
  fi

  echo ""
  echo "---"
  echo "Instructions:"
  echo "1. Login to carrefour.com.ar"
  echo "2. Click each link above (items accumulate)"
  echo "3. Complete checkout"
}

# Main command router
main() {
  local cmd="${1:-}"
  shift || true

  case "$cmd" in
    search)   cmd_search "$@" ;;
    add)      cmd_add "$@" ;;
    remove)   cmd_remove "$@" ;;
    list)     cmd_list ;;
    clear)    cmd_clear ;;
    checkout) cmd_checkout ;;
    -h|--help|*)
      echo "Carrefour Shopping List Manager"
      echo ""
      echo "Usage: carrefour.sh <command> [args]"
      echo ""
      echo "Commands:"
      echo "  search [--json] <query>  Search for products"
      echo "  add <sku> [qty]   Add item to list"
      echo "  remove <sku>      Remove item from list"
      echo "  list              Show shopping list"
      echo "  clear             Clear shopping list"
      echo "  checkout          Generate cart URL(s)"
      echo ""
      echo "Environment:"
      echo "  SKILLS_STATE_DIR   Directory for persistent data (default: <skill>/state)"
      echo ""
      echo "Dependencies: curl, jq, bc"
      ;;
  esac
}

main "$@"
