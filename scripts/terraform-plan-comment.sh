#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "usage: terraform-plan-comment.sh <summary> <plan-log-file> <title> <comment-key>" >&2
  exit 2
}

[ "$#" -eq 4 ] || usage

summary=$1
plan_log=$2
title=$3
comment_key=$4
max_log_bytes=60000

if [[ ! "$comment_key" =~ ^[A-Za-z0-9._/-]+$ ]]; then
  echo "comment key must be letters, digits, '.', '_', '/' or '-': $comment_key" >&2
  exit 2
fi

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
printf '<!-- d-github-actions:terraform-plan:%s -->\n' "$comment_key"
