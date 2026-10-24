#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "usage: terraform-plan-summary.sh <exit-code> <plan-log-file>" >&2
  exit 2
}

[ "$#" -eq 2 ] || usage

exit_code=$1
plan_log=$2
no_op_plan_line="Plan: 0 to add, 0 to change, 0 to destroy."

case "$exit_code" in
  '' | *[!0-9]*)
    echo "exit code must be a number, got '$exit_code'" >&2
    exit 2
    ;;
esac

case "$exit_code" in
  0)
    echo "No changes."
    ;;
  2)
    if [ ! -r "$plan_log" ]; then
      echo "plan log not found: $plan_log" >&2
      exit 2
    fi
    plan_line=$(grep -E '^Plan:' "$plan_log" | tail -n 1 || true)
    if grep -q '^Changes to Outputs:' "$plan_log" && { [ -z "$plan_line" ] || [ "$plan_line" = "$no_op_plan_line" ]; }; then
      echo "Changes to outputs only."
    else
      echo "$plan_line"
    fi
    ;;
  *)
    echo "Plan failed (exit $exit_code)."
    ;;
esac
