---
name: carrefour.ar
description: "Use this skill to search products, build shopping lists, and generate checkout URLs for Carrefour Argentina. Activate when the user wants to buy groceries online in Argentina, manage a shopping list, or create a shareable cart link — even if they don't explicitly mention 'Carrefour',  'supermercado' or 'super'."
---

# Carrefour Argentina Shopping Assistant

Build a shopping list over time, then generate a shareable cart URL for checkout.

## Prerequisites

- **Dependencies:** `curl`, `jq`, `bc`
- **Environment:** `SKILLS_STATE_DIR` (optional; defaults to `<skill>/state`)

## Available scripts

- **`scripts/carrefour.sh`** — Search products, manage shopping list, generate checkout URLs

## Commands

```bash
scripts/carrefour.sh <command> [args]
```

| Command | Description |
|---------|-------------|
| `search [--json] <query>` | Search for products (use `--json` for structured output) |
| `add <sku> [qty]` | Add item to shopping list (default qty: 1) |
| `remove <sku>` | Remove item from list |
| `list` | Show current shopping list with totals |
| `clear` | Empty the shopping list |
| `checkout` | Generate shareable cart URL(s) |

## Usage Examples

### Search for products
```bash
scripts/carrefour.sh search "cerveza corona"
```
Returns SKU, name, and price for matching products.

### Add items to list
```bash
scripts/carrefour.sh add 15872 6      # Add 6x Cerveza Corona 330ml
scripts/carrefour.sh add 73254 2      # Add 2x Coca Cola 1.75L
```

### View your list
```bash
scripts/carrefour.sh list
```

### Generate checkout URL
```bash
scripts/carrefour.sh checkout
```
Returns one or more URLs (max 150 items each). Share with the person who will complete the purchase. They should:
1. Login to carrefour.com.ar
2. Click the URL(s)
3. Items are added to their cart
4. Complete checkout

## Data Storage

Shopping list persists at:
```
$SKILLS_STATE_DIR/carrefour.ar/shopping_list.json
```
If `SKILLS_STATE_DIR` is not set, defaults to `<skill>/state/carrefour.ar/`.

## Workflow

1. User asks to add groceries → `scripts/carrefour.sh search` to find products
2. Present options with prices → user picks → `scripts/carrefour.sh add` to list
3. Repeat over days/weeks
4. When ready → `scripts/carrefour.sh checkout` to generate URL(s)
5. Share URL with human → they login and pay

## Gotchas

- SKUs are numeric but must be stored/passed as strings
- API returns products with `price: 0` for unavailable items — always filter these out
- Cart URLs break at ~4000 characters — the script auto-splits into multiple URLs
- The `seller` field defaults to `"1"` (Carrefour direct); other sellers exist but aren't supported
- Product names from the API can be very long — truncate for display
- Adding the same SKU twice increases quantity rather than creating a duplicate

## Technical Notes

- Uses VTEX Catalog System API (public, no auth required)
- Cart URLs support up to 150 items each (~4000 chars)
- Multiple URLs can be clicked sequentially (items accumulate)
- VTEX cart limit: 300 items total
