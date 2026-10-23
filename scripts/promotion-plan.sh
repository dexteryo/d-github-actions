#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "usage: promotion-plan.sh <environments-json> <default-aws-region>" >&2
  exit 2
}

[ "$#" -eq 2 ] || usage

environments=$1
default_region=$2
required_fields='["name","role-to-assume","cluster","service","task-definition-family"]'

if ! jq -e 'type == "array"' <<<"$environments" >/dev/null 2>&1; then
  echo "environments must be a JSON array" >&2
  exit 1
fi

jq -e --argjson required "$required_fields" '
  length >= 1 and length <= 3
  and all(.[]; type == "object" and (. as $e | all($required[]; ($e[.] // "") | type == "string" and length > 0)))
  and (map(.name) | length == (unique | length))
' <<<"$environments" >/dev/null || {
  echo "environments needs 1 to 3 items with unique names and non-empty: name, role-to-assume, cluster, service, task-definition-family" >&2
  exit 1
}

echo "count=$(jq 'length' <<<"$environments")"
for position in 1 2 3; do
  jq -c --argjson index "$((position - 1))" --arg region "$default_region" \
    '"env-'"$position"'=" + ((.[$index] // {}) | if length == 0 then . else . + {"aws-region": (."aws-region" // $region)} end | tojson)' \
    -r <<<"$environments"
done
