#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
script="$root/scripts/rewrite-task-definition.sh"
fixture="$root/tests/fixtures/task-definition.json"
agent_uri="123456789012.dkr.ecr.eu-west-1.amazonaws.com/example/ordering-agent@sha256:aaaa"
mcp_uri="123456789012.dkr.ecr.eu-west-1.amazonaws.com/example/ordering-mcp@sha256:bbbb"

failures=0
check() {
  local description=$1
  shift
  if "$@" >/dev/null 2>&1; then
    echo "ok   - $description"
  else
    echo "FAIL - $description"
    failures=$((failures + 1))
  fi
}

images_replaced() {
  jq -e --arg a "$agent_uri" --arg m "$mcp_uri" \
    '(.containerDefinitions | map({(.name): .image}) | add) == {"ordering-agent": $a, "ordering-mcp": $m}' <<<"$both"
}

read_only_fields_stripped() {
  jq -e '[.taskDefinitionArn, .revision, .status, .requiresAttributes, .compatibilities, .registeredAt, .registeredBy] | all(. == null)' <<<"$both"
}

shape_preserved() {
  jq -e '.family == "example-ordering-agent" and .cpu == "512" and .taskRoleArn != null and .containerDefinitions[0].portMappings[0].containerPort == 8788' <<<"$both"
}

untouched_container_keeps_image() {
  jq -e '.containerDefinitions[1].image | endswith(":old")' <<<"$only_agent"
}

unknown_container_fails() {
  ! "$script" "$fixture" "nope=x"
}

malformed_pair_fails() {
  ! "$script" "$fixture" "no-equals-sign"
}

envelope_accepted() {
  local wrapped
  wrapped=$(mktemp)
  jq '{taskDefinition: .}' "$fixture" > "$wrapped"
  "$script" "$wrapped" "ordering-agent=x" | jq -e '.family == "example-ordering-agent"'
}

both=$("$script" "$fixture" "ordering-agent=$agent_uri" "ordering-mcp=$mcp_uri")
only_agent=$("$script" "$fixture" "ordering-agent=$agent_uri")

check "both container images are replaced" images_replaced
check "read-only fields are stripped" read_only_fields_stripped
check "task shape is preserved" shape_preserved
check "untouched container keeps its image" untouched_container_keeps_image
check "unknown container name fails" unknown_container_fails
check "malformed pair fails" malformed_pair_fails
check "describe-task-definition envelope is accepted" envelope_accepted

[ "$failures" -eq 0 ]
