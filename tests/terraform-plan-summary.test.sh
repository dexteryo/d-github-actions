#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
summary="$root/scripts/terraform-plan-summary.sh"
fixtures="$root/tests/fixtures"

failures=0
expect_equal() {
  local description=$1 expected=$2 actual=$3
  if [ "$expected" = "$actual" ]; then
    echo "ok   - $description"
  else
    echo "FAIL - $description (got '$actual', expected '$expected')"
    failures=$((failures + 1))
  fi
}

expect_equal "exit 0 is no changes" "No changes." "$("$summary" 0 "$fixtures/terraform-plan-no-changes.log")"
expect_equal "exit 0 does not need the log" "No changes." "$("$summary" 0 /nonexistent.log)"
expect_equal "exit 2 prints the plan line" "Plan: 1 to add, 0 to change, 0 to destroy." "$("$summary" 2 "$fixtures/terraform-plan-changes.log")"
expect_equal "exit 2 with outputs only" "Changes to outputs only." "$("$summary" 2 "$fixtures/terraform-plan-outputs-only.log")"
expect_equal "exit 2 with a zero plan line and outputs" "Changes to outputs only." "$("$summary" 2 "$fixtures/terraform-plan-zero-plan-line.log")"
expect_equal "exit 2 with no plan line says so" "Plan has changes (no summary line found)." "$("$summary" 2 "$fixtures/terraform-plan-no-plan-line.log")"
expect_equal "exit 1 is a failed plan" "Plan failed (exit 1)." "$("$summary" 1 "$fixtures/terraform-plan-failed.log")"
expect_equal "any other exit code is a failed plan" "Plan failed (exit 137)." "$("$summary" 137 "$fixtures/terraform-plan-failed.log")"

status=0
error=$("$summary" abc "$fixtures/terraform-plan-failed.log" 2>&1 >/dev/null) || status=$?
expect_equal "a non-numeric exit code is rejected" "2" "$status"
expect_equal "a non-numeric exit code explains itself" "exit code must be a number, got 'abc'" "$error"

status=0
"$summary" "" "$fixtures/terraform-plan-failed.log" >/dev/null 2>&1 || status=$?
expect_equal "an empty exit code is rejected" "2" "$status"

status=0
error=$("$summary" 2 /nonexistent.log 2>&1 >/dev/null) || status=$?
expect_equal "a missing log is rejected for exit 2" "2" "$status"
expect_equal "a missing log explains itself" "plan log not found: /nonexistent.log" "$error"

status=0
"$summary" 2 >/dev/null 2>&1 || status=$?
expect_equal "missing arguments print usage" "2" "$status"

[ "$failures" -eq 0 ]
