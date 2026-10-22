#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 2 ]; then
  echo "usage: check-deployment.sh <describe-services.json> <expected-task-definition-arn>" >&2
  exit 2
fi

describe_json=$1
expected_arn=$2

primary=$(jq -c '.services[0].deployments | map(select(.status == "PRIMARY")) | first // empty' "$describe_json")

if [ -z "$primary" ]; then
  echo "No PRIMARY deployment found" >&2
  exit 1
fi

primary_arn=$(jq -r '.taskDefinition' <<<"$primary")
rollout_state=$(jq -r '.rolloutState // "UNKNOWN"' <<<"$primary")

if [ "$primary_arn" != "$expected_arn" ]; then
  echo "PRIMARY deployment is $primary_arn, expected $expected_arn (rolled back or superseded)" >&2
  exit 1
fi

case "$rollout_state" in
  COMPLETED) exit 0 ;;
  FAILED)
    echo "Deployment of $expected_arn failed: $(jq -r '.rolloutStateReason // ""' <<<"$primary")" >&2
    exit 1
    ;;
  *) exit 10 ;;
esac
