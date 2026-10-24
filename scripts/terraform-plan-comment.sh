#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "usage: terraform-plan-comment.sh <summary> <plan-log-file> <title>" >&2
  exit 2
}

[ "$#" -eq 3 ] || usage

summary=$1
plan_log=$2
title=$3
max_log_bytes=60000

if [ ! -r "$plan_log" ]; then
  echo "plan log not found: $plan_log" >&2
  exit 2
fi

printf '### %s\n' "$title"
echo
printf '**%s**\n' "$summary"
echo
echo '<details><summary>Plan output</summary>'
echo
echo '```'
tail -c "$max_log_bytes" "$plan_log"
[ -z "$(tail -c 1 "$plan_log")" ] || echo
echo '```'
echo '</details>'
