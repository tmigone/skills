---
name: cueva
description: "Read and record fees for crypto operations in local exchanges. Trigger on: 'anota el costo para bajar cripto en Cueva Loca', 'AlbertoFernandez esta bajando a 1%', 'cual es el ultimo dato de comision para bajar cripto?'"
version: "0.2.0"
---

# cueva

Track and query the fees paid to exchange cryptocurrency for cash at local exchanges ("cuevas"). Look up historical fees or record a new one.

## Prerequisites

- **Dependencies:** `curl`, `jq` (optional, for reading JSON)
- **Environment:** `CUEVA_AUTH_TOKEN` (Bearer token for the cueva API), `CUEVA_API_URL` (base URL of the cueva deployment, e.g. `https://cueva.example.com`)

## Usage

- **`scripts/cueva.sh`** — Read historical fees or log a new one

```bash
scripts/cueva.sh <command> [args]
```

| Command | Description |
|---------|-------------|
| `fees [--from YYYY-MM-DD] [--to YYYY-MM-DD] [--location <name>]` | List fees (all filters optional and additive) |
| `log <date> <fee> <location>` | Record a new fee (`date` = `YYYY-MM-DD`) |

## Usage Examples

### Look up fees
```bash
scripts/cueva.sh fees                                     # all fees
scripts/cueva.sh fees --location "Cueva Loca"              # one location
scripts/cueva.sh fees --from 2026-01-01 --to 2026-12-31   # a date range
```
Returns `{ ok: true, count: N, fees: [ { date, fee, location } ] }` — the rows are
under `fees`, and `count` is how many matched. Sum, average, or group them
yourself to answer the question (e.g. average `fee` for a location).

### Record a fee
```bash
scripts/cueva.sh log 2026-07-30 1.25 "Cueva Loca"          # a 1.25% fee at Cueva Loca
```
Returns `{ ok: true, fee: { date, fee, location } }` — the row as stored. Echo it
back so the user can confirm what was written.

## Workflow

1. User asks about past fees → `scripts/cueva.sh fees` (with filters) → summarize the rows (latest, average, by location).
2. User reports a fee they just paid → `scripts/cueva.sh log <date> <fee> <location>`.
3. Report back what was read or written so the user can confirm.

## Gotchas

- `fee` is a bare percentage — report it with a `%`, and never convert it to an amount of money.
- `location` matches **exactly** and is case-sensitive — reuse the spelling already in the log (e.g. `"Cueva Loca"`), don't invent a new variant.
- `--from`/`--to` are both inclusive — `--from 2026-01-01 --to 2026-01-31` covers both endpoints.
- Rows come back newest-first — the first row is the latest fee.
- A recorded fee of `0` is a real entry (fee waived), not a missing one.
- Quote multi-word locations so they arrive as one argument.
- A `401` means the token is set but wrong — the script catches an *unset* one itself, so don't read this as the API being down. Check `CUEVA_AUTH_TOKEN`.
