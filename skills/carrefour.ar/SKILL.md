---
name: carrefour.ar
description: "Use this skill to search products, build shopping lists, and generate checkout URLs for Carrefour Argentina. Activate when the user wants to buy groceries online in Argentina, manage a shopping list, or create a shareable cart link — even if they don't explicitly mention 'Carrefour',  'supermercado' or 'super'."
version: "0.2.0"
---

# Carrefour Argentina Shopping Assistant

Build a shopping list over days or weeks, then generate a shareable cart URL. The skill never buys anything: `checkout` emits links that a human opens while logged in to carrefour.com.ar and pays for themselves. Everything before that is list-building against the public product catalog.

## Prerequisites

- **Dependencies:** `curl`, `jq`, `bc`
- **Environment:** `SKILLS_STATE_DIR` (optional; defaults to `<skill>/state`)

## Data Storage

Shopping list persists at:
```
$SKILLS_STATE_DIR/carrefour.ar/shopping_list.json
```
If `SKILLS_STATE_DIR` is not set, defaults to `<skill>/state/carrefour.ar/`.

## Usage

- **`scripts/carrefour.sh`** — Search products, manage shopping list, generate checkout URLs

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
Returns one or more URLs. Share with the person who will complete the purchase. They should:
1. Login to carrefour.com.ar
2. Click every URL, in order — items accumulate in the cart rather than replacing it
3. Complete checkout

## Workflow

1. User asks to add groceries → `scripts/carrefour.sh search` to find products
2. Present options with prices → user picks → `scripts/carrefour.sh add` to list
3. Repeat over days/weeks
4. When ready → `scripts/carrefour.sh checkout` to generate URL(s)
5. Share URL with human → they login and pay

## Gotchas

- Cart URLs break at ~4000 characters — the script auto-splits into multiple URLs
- The cart holds 300 items total. A list built up over weeks can drift into this — warn before it does
- Product names from the API can be very long — truncate for display
- Adding the same SKU twice increases quantity rather than creating a duplicate
