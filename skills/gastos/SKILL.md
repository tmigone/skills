---
name: gastos
description: "Read and record recurring household expenses in gastos (ARS + USD). Trigger on: 'whats unpaid this month', 'how much did we spend', 'how much do we usually spend on X', 'mark X as paid'."
---

# gastos

Track recurring monthly household expenses in two currencies (ARS + USD). A **period** is one expense's record for one month: the amount paid, in both currencies, at that month's blue-dollar rate. Answer spending questions and record payments.

## Prerequisites

- **Dependencies:** `curl`, `jq` (optional, for reading JSON)
- **Environment:** `GASTOS_AUTH_TOKEN` (Bearer token for the gastos API), `GASTOS_API_URL` (base URL of the gastos deployment, e.g. `https://gastos.example.com`)

## Usage

- **`scripts/gastos.sh`** — Read the roster, list unpaid items, query recorded payments, or record a payment

```bash
scripts/gastos.sh <command> [args]
```

| Command | Description |
|---------|-------------|
| `expenses` | List the roster: categories and active expenses (with `due_day`) |
| `unpaid [--month YYYY-MM]` | Active expenses with no payment for the month (default: current) |
| `periods [--from YYYY-MM] [--to YYYY-MM]` | Recorded-payment rows over a range (default: trailing 12 months) |
| `pay <expenseId> <year> <month> <currency> <amount>` | Record a payment (`month` 0-indexed, `currency` `USD`/`ARS`) |

## Currency rule (important)

Always report **both** currencies when you state an amount. But reason about
**trends over time in USD**: ARS is stored nominally at each month's rate and
inflates heavily, so comparing ARS across months is misleading. USD is the
stable measure; ARS is meaningful within a single month (e.g. "what do I owe
right now").

## Usage Examples

### List what's tracked
```bash
scripts/gastos.sh expenses                        # resolve a name → expense_id, see the roster
```
Returns `{ ok: true, categories: [...], expenses: [ { id, name, category_id, category, due_day } ] }`.
Match what the user said against `name` to get the `id` that `pay` needs.

### What's unpaid
```bash
scripts/gastos.sh unpaid                           # current month
scripts/gastos.sh unpaid --month 2026-06           # a specific month
```
Returns `{ ok: true, month, count, unpaid: [ { expense_id, expense, category, due_date } ] }`.
The items are under `unpaid` — flag any whose `due_date` has passed.

### Query spending
```bash
scripts/gastos.sh periods                                    # trailing 12 months
scripts/gastos.sh periods --from 2026-06 --to 2026-06        # one month
scripts/gastos.sh periods --from 2026-02 --to 2026-07        # last 6 months
```
Returns `{ ok: true, from, to, count, periods: [ { expense_id, expense, category, month, amount_usd, amount_ars, fx_rate, paid_at } ] }`.
The rows are under `periods` — sum or average them yourself (sum `amount_usd` for a total; average `amount_usd` filtered to one `expense` for "how much do we usually spend on X").

### Record a payment
```bash
scripts/gastos.sh pay 9 2026 6 USD 220             # expense 9, Jul 2026, USD 220
scripts/gastos.sh pay 9 2026 6 USD 0               # mark handled-but-zero (not "unpaid")
```
The server converts to the other currency at the current blue rate, sets `paid_at`, and upserts on `(expense, month)`.
Returns `{ ok: true, usd, ars, fxRate }` — report both amounts and the rate that was used.

## Workflow

1. User names an expense ("Colegio") → `scripts/gastos.sh expenses` to resolve it to an `expense_id`.
2. "What's unpaid?" → `scripts/gastos.sh unpaid` → list each with its `due_date`, flag overdue.
3. "How much did we spend…?" → `scripts/gastos.sh periods` over the range → sum/average → report **both** currencies.
4. "Mark X as paid" → resolve X, then `scripts/gastos.sh pay …` with the amount and currency the user gives.

## Gotchas

- `month` in `pay` is **0-indexed** (0 = January, 6 = July) — but `--month` / `periods` ranges use `YYYY-MM` (1-indexed). Don't mix them up.
- A recorded `0` counts as **handled**, not unpaid — it disappears from `unpaid` and appears in `periods` with zero amounts.
- Only **active** expenses appear in `expenses` and `unpaid`. `periods` still resolves names for expenses that have since been deactivated.
- `pay` needs the numeric `expense_id`, not the name — resolve it via `expenses` first. A `404` means the id doesn't exist.
- Amounts are rounded to **whole units** — `pay … USD 220.50` stores `221`. Confirm back the `usd`/`ars` from the response, not the number the user said.
- A `502` (`fx unavailable`) means the blue rate couldn't be fetched and **nothing was recorded**. Don't report the payment as saved; it has to be retried.
- `due_day` is clamped to 1–28, so an expense due on the 29th–31st reports a `due_date` of the 28th — it will look overdue a few days early.
- `periods` default range is the trailing 12 months; pass `--from`/`--to` for anything longer.
- A `401` means the token is set but wrong — the script catches an *unset* one itself, so don't read this as the API being down. Check `GASTOS_AUTH_TOKEN`.
