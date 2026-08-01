#!/usr/bin/env bash
#
# gen-email.sh — deterministically assemble an invoice email from a client's
# YAML template. Every line of the output is copied verbatim from the config;
# the only variation is *which* entries get picked. No text is ever invented.
#
# Layout of the assembled email:
#
#   <one random opening>
#
#   <one random report_heading>
#
#   * <random task from report_tasks>
#   * ...
#
#   <one random closing>
#
# The number of task bullets is a random count between the config's `min_tasks`
# and `max_tasks` (clamped to how many tasks actually exist in the catalog).

set -euo pipefail

# --- locate skill root + state dir -----------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
STATE_DIR="${SKILLS_STATE_DIR:-$SKILL_ROOT/state}/invoice-email"
CONFIGS_DIR="$STATE_DIR/configs"

usage() {
  cat <<EOF
Usage: gen-email.sh -c <client> [-h]

  -c, --config <client>   Client name (looks up \$CONFIGS_DIR/<client>.yaml)
                          or a direct path to a .yaml/.yml file.
  -l, --list              List available client configs and exit.
  -h, --help              Show this help.

Configs directory: $CONFIGS_DIR
EOF
}

die() { echo "gen-email: $*" >&2; exit 1; }

command -v yq >/dev/null 2>&1 || die "yq is required but not on PATH (https://github.com/mikefarah/yq)"

# --- parse args -------------------------------------------------------------
CONFIG_ARG=""
while [ $# -gt 0 ]; do
  case "$1" in
    -c|--config) CONFIG_ARG="${2:-}"; shift 2 ;;
    -l|--list)
      if [ -d "$CONFIGS_DIR" ]; then
        find "$CONFIGS_DIR" -maxdepth 1 \( -name '*.yaml' -o -name '*.yml' \) \
          -exec basename {} \; | sed 's/\.[^.]*$//' | sort
      fi
      exit 0 ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown argument: $1 (see --help)" ;;
  esac
done

[ -n "$CONFIG_ARG" ] || { usage; exit 1; }

# --- resolve config file ----------------------------------------------------
if [ -f "$CONFIG_ARG" ]; then
  CONFIG="$CONFIG_ARG"
elif [ -f "$CONFIGS_DIR/$CONFIG_ARG.yaml" ]; then
  CONFIG="$CONFIGS_DIR/$CONFIG_ARG.yaml"
elif [ -f "$CONFIGS_DIR/$CONFIG_ARG.yml" ]; then
  CONFIG="$CONFIGS_DIR/$CONFIG_ARG.yml"
else
  die "no config found for '$CONFIG_ARG' (looked in $CONFIGS_DIR)"
fi

# --- small helpers ----------------------------------------------------------
# Length of a top-level list, 0 if missing/null.
len() { yq "(.$1 | length) // 0" "$CONFIG"; }

# Pick one random entry from a top-level list; fail loudly if it's empty, since
# an opening/heading/closing with no options means the template is incomplete.
pick_one() {
  local key="$1" n idx
  n="$(len "$key")"
  [ "$n" -gt 0 ] || die "config '$CONFIG' has no entries under '$key'"
  idx=$(( RANDOM % n ))
  yq ".$key[$idx]" "$CONFIG"
}

# --- gather pieces ----------------------------------------------------------
# Opening and closing are the skeleton of the email, so they're required. The
# task report, however, is entirely optional: a client whose template has no
# report_tasks (or no heading/bounds) simply gets a bare opening + closing.
opening="$(pick_one opening)"
closing="$(pick_one closing)"

# Heading is only meaningful when there are tasks to head, so pick it lazily.
heading=""
[ "$(len report_heading)" -gt 0 ] && heading="$(pick_one report_heading)"

# Decide how many task bullets (if any) to include.
chosen=()
total_tasks="$(len report_tasks)"
if [ "$total_tasks" -gt 0 ]; then
  min="$(yq '.min_tasks // 3' "$CONFIG")"
  max="$(yq '.max_tasks // 6' "$CONFIG")"
  [ "$min" -le "$max" ] || die "min_tasks ($min) must be <= max_tasks ($max)"

  # Can't ask for more bullets than the catalog holds.
  [ "$max" -le "$total_tasks" ] || max="$total_tasks"
  [ "$min" -le "$total_tasks" ] || min="$total_tasks"

  count=$(( min + RANDOM % (max - min + 1) ))
  if [ "$count" -gt 0 ]; then
    # Fisher–Yates shuffle of task indices, then take the first `count`.
    indices=()
    for (( i = 0; i < total_tasks; i++ )); do indices+=( "$i" ); done
    for (( i = total_tasks - 1; i > 0; i-- )); do
      j=$(( RANDOM % (i + 1) ))
      tmp="${indices[i]}"; indices[i]="${indices[j]}"; indices[j]="$tmp"
    done
    chosen=( "${indices[@]:0:count}" )
  fi
fi

# --- assemble ---------------------------------------------------------------
printf '%s\n' "$opening"
if [ "${#chosen[@]}" -gt 0 ]; then
  printf '\n'
  [ -n "$heading" ] && printf '%s\n\n' "$heading"
  for idx in "${chosen[@]}"; do
    printf '* %s\n' "$(yq ".report_tasks[$idx]" "$CONFIG")"
  done
fi
printf '\n%s\n' "$closing"
