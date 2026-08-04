---
name: dolarito
description: "Use this skill to get current or historical USD/ARS exchange rates in Argentina. Activate when the user asks about dollar prices, cotización del dólar, blue dollar, dólar oficial, MEP, CCL, currency conversion between dollars and pesos, or what a rate was on some past date — even if they just say 'dólar', 'a cuánto está el blue', or 'a cuánto estaba el blue en septiembre'. Also activate when you need to convert values between USD/ARS."
version: "0.2.0"
---

# Dolarito

Fetch USD/ARS exchange rates for the Argentine market — live, or on any past date back to 2011.

Argentina has several simultaneous dollar prices, and they diverge widely. Each one is a **market** (`blue`, `oficial`, MEP, …), and each quotes two sides: **compra** (buy) and **venta** (sell).

## Prerequisites

- **Dependencies:** `curl`, `jq`
- **Environment:** none — both APIs are public and unauthenticated

## Usage

- **`scripts/dolarito.sh`** — Render the rate block for today or a past date, or return a single rate for conversions

```bash
scripts/dolarito.sh <command> [--date YYYY-MM-DD]
```

| Command | Description |
|---------|-------------|
| *(no args)* | Print the formatted rate block, ready to show the user |
| `rate [market] [compra\|venta]` | One bare number, for arithmetic (default: `contadoconliqui compra`) |
| `--json` | Raw API response (shape differs live vs `--date`, see below) |
| `--date YYYY-MM-DD` | Modifier on any of the above — historical instead of live |

The block shows six markets: `oficial`, `blue`, `bolsa` (MEP), `contadoconliqui` (CCL), `cripto`, `tarjeta`. `rate` is not limited to those — it accepts anything the APIs carry, including `mayorista`, and `solidario` on historical dates.

`--json` passes the upstream objects through unchanged, so the fields differ by mode: live rows carry `moneda`, `casa`, `nombre`, `compra`, `venta`, `fechaActualizacion`; `--date` rows carry only `casa`, `compra`, `venta`, `fecha`.

## Usage Examples

### Show the rates
```bash
scripts/dolarito.sh                          # the whole block, print it verbatim
```
```
💵 Dólar — 31 de julio de 2026

Oficial     $1.460,00  / $1.510,00  31/07 15:00
Blue        $1.540,00  / $1.560,00  31/07 17:59
MEP         $1.516,80  / $1.522,10  31/07 17:59
CCL         $1.572,20  / $1.575,70  31/07 17:59
Cripto      $1.566,74  / $1.573,02  31/07 17:59
Tarjeta     $1.898,00  / $1.963,00  31/07 15:00

(compra / venta · actualizado, hora ARG)
```

### What was it on some past date
```bash
scripts/dolarito.sh --date 2024-09-07        # the whole block, as of that day
```
```
💵 Dólar — 7 de septiembre de 2024

Oficial     $936,50    / $976,50
Blue        $1.240,00  / $1.260,00
MEP         $1.244,00  / $1.246,60
CCL         $1.236,70  / $1.252,20
Cripto      $1.259,60  / $1.264,00
Tarjeta     $1.498,40  / $1.562,40

(compra / venta · cotización del 2024-09-07)
```

### Convert an amount
```bash
scripts/dolarito.sh rate                            # CCL compra — the default for conversions
scripts/dolarito.sh rate blue venta                 # a specific market and side
scripts/dolarito.sh rate blue venta --date 2024-09-07   # what it was back then
```
Returns a bare number. Multiply or divide it yourself, and say which rate you used.

## Workflow

1. User asks about dollar rates → `scripts/dolarito.sh` → return the block as-is.
2. User asks what a rate *was* → resolve their phrasing to a `YYYY-MM-DD` → `scripts/dolarito.sh --date …`, or `rate <market> --date …` for a single figure.
3. User asks to convert an amount → `scripts/dolarito.sh rate` → do the arithmetic → state the rate you applied.
4. User names a specific market ("a cuánto el blue") → `scripts/dolarito.sh rate blue` for a number, or the full block if they want the picture.

## Gotchas

- The `casa` key for CCL is **`contadoconliqui`** — squashed, no spaces or accent. The readable `"Contado con liquidación"` is the `nombre` field. Filtering on the pretty version silently matches nothing and drops the row.
- `bolsa` is what the API calls MEP. The script maps both; only these two labels differ from `nombre`.
- The APIs return more markets than are shown — `mayorista` (and `solidario`, historically) are fetched but deliberately not displayed.
- **Live and historical come from different APIs** — `dolarapi.com` for today, `argentinadatos.com` for `--date`. They agree on the `casa` vocabulary but not the response shape: historical rows have no `nombre`/`moneda`, and date their values with `fecha` rather than `fechaActualizacion`. If you ever bypass the script, don't assume one parser works for both.
- **History starts `2011-01-03`**; earlier dates fail fast. Newer markets simply don't exist on older dates — `cripto`, MEP and CCL show `(sin dato)` before roughly 2018, which is missing history, not a broken request.
- Weekends and holidays return the **previous close** carried forward rather than an error, so a Saturday quote is really Friday's. Don't present it as if the market traded that day.
- Each row carries its own `fechaActualizacion`, and they diverge: `oficial` and `tarjeta` update on a banking schedule while the rest move continuously. On a Monday morning `oficial` may still be Friday's rate, so the per-row timestamp matters — don't collapse them into a single "as of today".
- Conversions default to CCL `compra` unless the user says otherwise. Whatever you use, name it — the spread between markets is wide enough that an unstated rate is a wrong answer.
