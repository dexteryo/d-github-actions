#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "usage: rewrite-task-definition.sh <task-definition.json> <name=image-uri>..." >&2
  exit 2
}

[ "$#" -ge 2 ] || usage

task_definition_file=$1
shift

images_json='{}'
for pair in "$@"; do
  [ -n "$pair" ] || continue
  name=${pair%%=*}
  image=${pair#*=}
  if [ "$name" = "$pair" ] || [ -z "$name" ] || [ -z "$image" ]; then
    echo "invalid container image pair: '$pair' (expected name=image-uri)" >&2
    exit 2
  fi
  images_json=$(jq -c --arg n "$name" --arg i "$image" '. + {($n): $i}' <<<"$images_json")
done

jq --argjson images "$images_json" '
  (.taskDefinition // .) as $td
  | ($images | keys - [$td.containerDefinitions[].name]) as $unknown
  | if ($unknown | length) > 0 then error("unknown containers: " + ($unknown | join(","))) else . end
  | $td
  | .containerDefinitions |= map(if $images[.name] then .image = $images[.name] else . end)
  | del(
      .taskDefinitionArn, .revision, .status, .requiresAttributes, .compatibilities,
      .registeredAt, .registeredBy, .deregisteredAt
    )
' "$task_definition_file"
