#!/usr/bin/env bash
set -euo pipefail

pattern='^[A-Za-z0-9_.-]+=[A-Za-z0-9.-]+(:[0-9]+)?/[A-Za-z0-9._/-]+@sha256:[0-9a-f]{64}$'
status=0
count=0

while IFS= read -r line || [ -n "$line" ]; do
  line=$(printf '%s' "$line" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
  [ -n "$line" ] || continue
  count=$((count + 1))
  if ! [[ $line =~ $pattern ]]; then
    echo "not a digest reference: $line" >&2
    status=1
  fi
done

if [ "$count" -eq 0 ]; then
  echo "no image references given" >&2
  exit 1
fi
exit "$status"
