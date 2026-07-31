---
name: cueva
description: "Read and record fees for crypto operations in local exchanges. Trigger on: 'anota el costo para bajar cripto en Cueva Loca', 'AlbertoFernandez esta bajando a 1%', 'cual es el ultimo dato de comision para bajar cripto?'"
---

# cueva

Track and query the fees paid to exchange cryptocurrency for cash at local exchanges ("cuevas"). Look up historical fees or record a new one.

## Prerequisites

- **Dependencies:** `curl`, `jq` (optional, for reading JSON)
- **Environment:** `CUEVA_AUTH_TOKEN` (Bearer token for the cueva API), `CUEVA_API_URL` (base URL of the cueva deployment, e.g. `https://cueva.example.com`)

## Available scripts

- **`scripts/cueva.sh`** — Read historical fees or log a new one

## Commands

```bash
scripts/cueva.sh <command> [args]
```

| Command | Description |
|---------|-------------|
| `fees [--from YYYY-MM-DD] [--to YYYY-MM-DD] [--location <name>]` | List fees, newest first (all filters optional and additive) |
| `log <date> <fee> <location>` | Record a new fee (`date` = `YYYY-MM-DD`) |

## Usage Examples

### Look up fees
```bash
scripts/cueva.sh fees                                     # all fees, newest first
scripts/cueva.sh fees --location "Cueva Loca"              # one location
scripts/cueva.sh fees --from 2026-01-01 --to 2026-12-31   # a date range
```
Returns rows of `{ date, fee, location }`. Sum, average, or group them yourself
to answer the question (e.g. average `fee` for a location).

### Record a fee
```bash
scripts/cueva.sh log 2026-07-30 1.25 "Cueva Loca"          # fee of 1.25 at Cueva Loca
```

## Workflow

1. User asks about past fees → `scripts/cueva.sh fees` (with filters) → summarize the rows (latest, average, by location).
2. User reports a fee they just paid → `scripts/cueva.sh log <date> <fee> <location>`.
3. Report back what was read or written so the user can confirm.

## Gotchas

- `fee` is a single bare number (no currency, no conversion) — report it as-is.
- `location` matches **exactly** and is case-sensitive — reuse the spelling already in the log (e.g. `"Cueva Loca"`), don't invent a new variant.
- Dates are `YYYY-MM-DD`; `--from`/`--to` are both inclusive.
- Rows come back newest-first — the first row is the latest fee.
- A recorded fee of `0` is a real entry (fee waived), not a missing one.
- Quote multi-word locations so they arrive as one argument.

## Technical Notes

- Backed by the cueva HTTP API at `$CUEVA_API_URL` (Astro SSR + Supabase).
- Auth: every request sends `Authorization: Bearer $CUEVA_AUTH_TOKEN`. The script exits non-zero if either `CUEVA_AUTH_TOKEN` or `CUEVA_API_URL` is unset, or if the request fails (missing/wrong token → `401`).
- Responses are JSON: success bodies include `"ok": true`, errors are `{ "error": "..." }`.
- Endpoints wrapped: `GET /api/fees[?from=&to=&location=]` (flat rows, newest first) and `POST /api/fees` with body `{ date, fee, location }` (returns the created row, `201`).
