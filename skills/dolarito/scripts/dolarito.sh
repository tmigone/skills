#!/usr/bin/env bash
# dolarito.sh — fetch USD/ARS rates for the Argentine market and render them.
#
# The display block is assembled here rather than by the agent: the number
# format (Argentine locale), the column alignment, the casa→label mapping and
# the market filter are all fixed rules, and getting one subtly wrong produces
# output that still looks right. Emitting it from one place makes that
# impossible.
#
# usage:
#   dolarito.sh [--date YYYY-MM-DD]                        the formatted block
#   dolarito.sh rate [market] [compra|venta] [--date ...]  one bare number
#   dolarito.sh --json [--date YYYY-MM-DD]                 raw API response
#
# Two public APIs, neither authenticated:
#   current    https://dolarapi.com/v1/dolares
#   historical https://api.argentinadatos.com/v1/cotizaciones/dolares
# They share the `casa` vocabulary but not the response shape — the historical
# one has no `nombre`/`moneda` and dates its rows with `fecha`, not
# `fechaActualizacion`. History starts 2011-01-03.
set -euo pipefail

API="https://dolarapi.com/v1/dolares"
HIST="https://api.argentinadatos.com/v1/cotizaciones/dolares"
HIST_START="2011-01-03"

die() { echo "dolarito.sh: $*" >&2; exit 1; }

command -v jq >/dev/null 2>&1 || die "jq is required but not on PATH"

# The six markets we show, in display order, as "casa|label". `mayorista` and
# `solidario` are deliberately absent. Note `contadoconliqui` — the API's casa
# key is squashed, it is NOT the "contado con liquidación" of the `nombre` field.
MARKETS=(
  "oficial|Oficial"
  "blue|Blue"
  "bolsa|MEP"
  "contadoconliqui|CCL"
  "cripto|Cripto"
  "tarjeta|Tarjeta"
)

MESES=(enero febrero marzo abril mayo junio julio agosto septiembre octubre noviembre diciembre)

DATE_RE='^[0-9]{4}-[0-9]{2}-[0-9]{2}$'

# --- fetching ---------------------------------------------------------------

fetch_current() {
  curl -sS --fail-with-body --max-time 15 "$API"
}

# One market on one date. The historical API answers 404 with a JSON body rather
# than an empty response, so callers test for `.compra` instead of exit status —
# a missing market on an old date is normal, not an error.
fetch_hist_one() {
  local market="$1" date="$2"
  curl -sS --max-time 15 "$HIST/$market/${date:0:4}/${date:5:2}/${date:8:2}" 2>/dev/null || true
}

# --- formatting -------------------------------------------------------------

# Argentine number format: '.' for thousands, ',' for decimals, 2 places.
# 1460 -> 1.460,00   1516.8 -> 1.516,80
ars() {
  local n int dec out=""
  n=$(printf '%.2f' "$1")
  int="${n%.*}"; dec="${n#*.}"
  while [ ${#int} -gt 3 ]; do
    out=".${int: -3}$out"
    int="${int:0:${#int}-3}"
  done
  printf '%s%s,%s' "$int" "$out" "$dec"
}

# ISO-8601 UTC -> "dd/mm HH:MM" in Buenos Aires time. Tries BSD then GNU date,
# and falls back to showing the raw UTC parts rather than failing the run.
fmt_ts() {
  local iso="${1%%.*}"; iso="${iso%Z}"
  local epoch=""
  epoch=$(date -j -u -f '%Y-%m-%dT%H:%M:%S' "$iso" +%s 2>/dev/null) \
    || epoch=$(date -u -d "${iso}Z" +%s 2>/dev/null) \
    || { printf '%s/%s %s UTC' "${iso:8:2}" "${iso:5:2}" "${iso:11:5}"; return; }
  TZ="America/Argentina/Buenos_Aires" date -r "$epoch" +'%d/%m %H:%M' 2>/dev/null \
    || TZ="America/Argentina/Buenos_Aires" date -d "@$epoch" +'%d/%m %H:%M'
}

# "2024-09-07" -> "7 de septiembre de 2024"
fecha_larga() {
  local y="${1:0:4}" m="${1:5:2}" d="${1:8:2}"
  printf '%d de %s de %d' "$((10#$d))" "${MESES[10#$m-1]}" "$((10#$y))"
}

hoy() {
  local d m y
  d=$((10#$(date +%d))); m=$((10#$(date +%m))); y=$(date +%Y)
  printf '%d de %s de %d' "$d" "${MESES[m-1]}" "$y"
}

# --- arg parsing ------------------------------------------------------------
# --date may appear anywhere after the subcommand, so pull it out first and
# leave the remaining positionals in order.

CMD="${1:-show}"
case "$CMD" in show|rate|--json|-h|--help|help) shift || true ;; *) CMD="show" ;; esac

DATE=""
POS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --date) DATE="${2:-}"; shift 2 || die "--date needs a value" ;;
    -*) die "unknown option: $1 (see --help)" ;;
    *) POS+=("$1"); shift ;;
  esac
done

if [ -n "$DATE" ]; then
  [[ "$DATE" =~ $DATE_RE ]] || die "--date must be YYYY-MM-DD"
  [[ "$DATE" > "$HIST_START" || "$DATE" == "$HIST_START" ]] \
    || die "history starts $HIST_START — no data for $DATE"
fi

# --- commands ---------------------------------------------------------------

case "$CMD" in
  --json)
    if [ -n "$DATE" ]; then
      for m in "${MARKETS[@]}"; do fetch_hist_one "${m%%|*}" "$DATE"; done | jq -s '.'
    else
      fetch_current
    fi
    ;;

  rate)
    market="${POS[0]:-contadoconliqui}"
    side="${POS[1]:-compra}"
    case "$side" in compra|venta) ;; *) die "side must be compra or venta" ;; esac

    if [ -n "$DATE" ]; then
      val=$(fetch_hist_one "$market" "$DATE" | jq -r --arg s "$side" '.[$s] // empty')
      [ -n "$val" ] || die "no '$market' rate for $DATE (unknown market, or it didn't exist yet)"
    else
      val=$(fetch_current | jq -r --arg c "$market" --arg s "$side" \
        '(.[] | select(.casa == $c) | .[$s]) // empty')
      [ -n "$val" ] || die "no rate for market '$market' (try: oficial blue bolsa contadoconliqui cripto tarjeta)"
    fi
    printf '%s\n' "$val"
    ;;

  show)
    if [ -n "$DATE" ]; then
      printf '💵 Dólar — %s\n\n' "$(fecha_larga "$DATE")"
      for m in "${MARKETS[@]}"; do
        market="${m%%|*}"; label="${m##*|}"
        row=$(fetch_hist_one "$market" "$DATE" | jq -r 'select(.compra != null) | "\(.compra)\t\(.venta)"')
        if [ -z "$row" ]; then
          printf '%-11s %s\n' "$label" "(sin dato)"
          continue
        fi
        IFS=$'\t' read -r compra venta <<<"$row"
        printf '%-11s %-10s / %s\n' "$label" "\$$(ars "$compra")" "\$$(ars "$venta")"
      done
      printf '\n(compra / venta · cotización del %s)\n' "$DATE"
    else
      data=$(fetch_current)
      printf '💵 Dólar — %s\n\n' "$(hoy)"
      for m in "${MARKETS[@]}"; do
        market="${m%%|*}"; label="${m##*|}"
        row=$(printf '%s' "$data" | jq -r --arg c "$market" \
          '(.[] | select(.casa == $c) | "\(.compra)\t\(.venta)\t\(.fechaActualizacion)") // empty')
        if [ -z "$row" ]; then
          printf '%-11s %s\n' "$label" "(sin dato)"
          continue
        fi
        IFS=$'\t' read -r compra venta ts <<<"$row"
        # Prefix the '$' before padding, so the sign never floats off the digits.
        printf '%-11s %-10s / %-10s %s\n' \
          "$label" "\$$(ars "$compra")" "\$$(ars "$venta")" "$(fmt_ts "$ts")"
      done
      printf '\n(compra / venta · actualizado, hora ARG)\n'
    fi
    ;;

  -h|--help|help)
    cat >&2 <<'EOF'
usage:
  dolarito.sh [--date YYYY-MM-DD]                      the formatted rate block
  dolarito.sh rate [market] [compra|venta] [--date ..] one bare number
                                                       (default: contadoconliqui compra)
  dolarito.sh --json [--date YYYY-MM-DD]               raw API response

markets: oficial blue bolsa contadoconliqui cripto tarjeta
Without --date, rates are live. With it, history back to 2011-01-03.
EOF
    exit 0
    ;;
esac
