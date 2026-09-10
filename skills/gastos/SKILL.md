---
name: gastos
description: "Read and record recurring household expenses in gastos (ARS + USD). Trigger on: 'whats unpaid this month', 'how much did we spend', 'how much do we usually spend on X', 'mark X as paid'."
---

# gastos

Track recurring monthly household expenses in two currencies (ARS + USD). A **period** is one row per `(expense, month)` — the month's **total**, in both currencies, at that month's blue-dollar rate. Most expenses are paid once a month. Some are flagged `accumulate`: those can take several payments in a month, and the period holds their running sum. Answer spending questions and record payments.

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
| `pay <expenseId> <year> <month> <currency> <amount> [--add\|--set]` | Record a payment (`month` 0-indexed, `currency` `USD`/`ARS`, `amount` whole units) |

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
Returns `{ ok: true, categories: [...], expenses: [ { id, name, category_id, category, due_day, accumulate } ] }`.
Match what the user said against `name` to get the `id` that `pay` needs — and read
`accumulate` while you are here, since it decides which flag `pay` needs.

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
scripts/gastos.sh pay 9 2026 6 USD 220             # expense 9, Jul 2026 — the month's total is 220
scripts/gastos.sh pay 34 2026 6 USD 5 --add        # accumulate expense — one more payment of 5
scripts/gastos.sh pay 9 2026 6 USD 0 --set         # mark handled-but-zero (not "unpaid")
```
The server converts to the other currency at the current blue rate and stamps `paid_at`.
What it does with `amount` depends on the flag:

- **`--set`** replaces the month's total. Passing no flag means `set` for an ordinary
  expense — and a `400` for an accumulate one, which is deliberate.
- **`--add`** records one more payment; the server adds it to the running total.

Returns `{ ok: true, usd, ars, fxRate, op }`. **`usd` and `ars` are the period's new
totals, not what you just sent** — an `--add` of 5 onto 277 comes back as 282. Report
those and the rate, never the number you passed in.

## Workflow

1. User names an expense ("Colegio") → `scripts/gastos.sh expenses` to resolve it to an `expense_id`.
2. "What's unpaid?" → `scripts/gastos.sh unpaid` → list each with its `due_date`, flag overdue.
3. "How much did we spend…?" → `scripts/gastos.sh periods` over the range → sum/average → report **both** currencies.
4. "Mark X as paid" → resolve X via `expenses` and read its `accumulate` flag.
   - `accumulate: false` → `scripts/gastos.sh pay …` with the amount and currency given.
   - `accumulate: true` → the same, plus `--add`. Recording a payment is what `--add`
     is for, and step 1's lookup is what tells you to reach for it.

   Report the `usd`/`ars` that come back — the month's new totals, not the amount given.

**`--set` on an accumulate expense discards every other payment in that month**, with no
warning and no undo. Use it only when the user has said they are correcting or replacing
the month's total. Never infer it from "pagué 5000 de Actividades Tomi" — that is an
`--add`. If you genuinely can't tell, pass no flag at all: the API refuses the write and
says why, which is exactly what that error exists for.

## Gotchas

- An `accumulate` expense rejects a `pay` with no `--add`/`--set` — `400`, nothing written. That's a caller who skipped the `expenses` lookup, not a step in the normal path: read the flag first and pass the right one.
- **Individual payments are never stored.** Only the period's running total survives a write, so "what were the three payments for Actividades Tomi in July" is not something the API can answer. Don't hunt for a breakdown — report the total.
- `month` in `pay` is **0-indexed** (0 = January, 6 = July) — but `--month` / `periods` ranges use `YYYY-MM` (1-indexed). Don't mix them up.
- `--set 0` marks a month **handled**, not unpaid — it drops out of `unpaid` and shows in `periods` with zero amounts. Use `--set 0` for this every time: `--add 0` creates a zero row on an empty month but silently changes nothing on a month that already has payments, while still restamping `paid_at` so the row looks freshly touched.
- Only **active** expenses appear in `expenses` and `unpaid`. `periods` still resolves names for expenses that have since been deactivated.
- `pay` needs the numeric `expense_id`, not the name — resolve it via `expenses` first. A `404` means the id doesn't exist.
- Amounts are **whole units only** and the script rejects decimals. Rounding happens per payment *before* the sum, so three `0.5` payments land at `3` and two `0.4` payments land at `0`. Worse, the two currencies round independently off the raw amount — a fractional USD payment can store `0` USD against a non-zero ARS balance that still feeds every later total. Round it yourself and confirm the whole number with the user.
- A `502` (`fx unavailable`) means the blue rate couldn't be fetched and **nothing was recorded**. Don't report the payment as saved; it has to be retried.
- `due_day` is clamped to 1–28, so an expense due on the 29th–31st reports a `due_date` of the 28th — it will look overdue a few days early.
- `periods` default range is the trailing 12 months; pass `--from`/`--to` for anything longer.
- A `401` means the token is set but wrong — the script catches an *unset* one itself, so don't read this as the API being down. Check `GASTOS_AUTH_TOKEN`.
