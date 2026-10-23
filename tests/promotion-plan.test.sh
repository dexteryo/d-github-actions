#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
plan="$root/scripts/promotion-plan.sh"
refs="$root/scripts/check-image-refs.sh"
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

field() {
  grep "^$1=" <<<"$output" | cut -d= -f2-
}

output=$("$plan" "$(cat "$fixtures/environments-two.json")" eu-west-1)

expect_equal "count is 2" "2" "$(field count)"
expect_equal "first environment gets the default region" "eu-west-1" "$(field env-1 | jq -r '."aws-region"')"
expect_equal "second environment keeps its own region" "eu-central-1" "$(field env-2 | jq -r '."aws-region"')"
expect_equal "third environment is an empty object" "{}" "$(field env-3)"
expect_equal "each output is a single line" "4" "$(wc -l <<<"$output" | tr -d ' ')"

for fixture in environments-duplicate-names environments-missing-field environments-four; do
  status=0
  "$plan" "$(cat "$fixtures/$fixture.json")" eu-west-1 >/dev/null 2>&1 || status=$?
  expect_equal "$fixture is rejected" "1" "$status"
done

status=0
"$plan" '{"name":"x"}' eu-west-1 >/dev/null 2>&1 || status=$?
expect_equal "an object instead of an array is rejected" "1" "$status"

status=0
"$refs" < "$fixtures/image-refs-valid.txt" >/dev/null 2>&1 || status=$?
expect_equal "digest references pass" "0" "$status"

status=0
"$refs" < "$fixtures/image-refs-tag.txt" >/dev/null 2>&1 || status=$?
expect_equal "a tag reference fails" "1" "$status"

status=0
"$refs" < /dev/null >/dev/null 2>&1 || status=$?
expect_equal "no references fail" "1" "$status"

[ "$failures" -eq 0 ]
