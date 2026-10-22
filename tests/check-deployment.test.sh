#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
script="$root/scripts/check-deployment.sh"
fixtures="$root/tests/fixtures"
new_arn="arn:aws:ecs:eu-west-1:123456789012:task-definition/example-app:8"

failures=0
expect_exit() {
  local description=$1 expected=$2 fixture=$3 actual=0
  "$script" "$fixtures/$fixture" "$new_arn" >/dev/null 2>&1 || actual=$?
  if [ "$actual" -eq "$expected" ]; then
    echo "ok   - $description"
  else
    echo "FAIL - $description (exit $actual, expected $expected)"
    failures=$((failures + 1))
  fi
}

expect_exit "PRIMARY is the new revision and COMPLETED passes" 0 deployment-completed.json
expect_exit "PRIMARY is the old revision after a rollback fails" 1 deployment-rolled-back.json
expect_exit "rolloutState FAILED fails" 1 deployment-failed.json
expect_exit "rolloutState IN_PROGRESS asks to keep polling" 10 deployment-in-progress.json

[ "$failures" -eq 0 ]
