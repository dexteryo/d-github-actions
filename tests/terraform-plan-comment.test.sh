#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
comment="$root/scripts/terraform-plan-comment.sh"
fixtures="$root/tests/fixtures"
workdir=$(mktemp -d)
trap 'rm -rf "$workdir"' EXIT

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

body=$("$comment" "Plan: 1 to add, 0 to change, 0 to destroy." "$fixtures/terraform-plan-changes.log" "Terraform plan")

expect_equal "heading is first" "### Terraform plan" "$(sed -n 1p <<<"$body")"
expect_equal "summary is bold" "**Plan: 1 to add, 0 to change, 0 to destroy.**" "$(sed -n 3p <<<"$body")"
expect_equal "details block opens" "<details><summary>Plan output</summary>" "$(sed -n 5p <<<"$body")"
expect_equal "code fence opens" '```' "$(sed -n 7p <<<"$body")"
expect_equal "the log is included" "1" "$(grep -c '^  + logs_bucket = "example-logs"$' <<<"$body")"
expect_equal "code fence closes" '```' "$(tail -n 2 <<<"$body" | head -n 1)"
expect_equal "details block closes" "</details>" "$(tail -n 1 <<<"$body")"

head -c 100000 /dev/zero | tr '\0' 'a' > "$workdir/big.log"
printf 'TAIL-MARKER\n' >> "$workdir/big.log"
big_body=$("$comment" "Plan: 1 to add, 0 to change, 0 to destroy." "$workdir/big.log" "Terraform plan")
expect_equal "an oversized log keeps its tail" "1" "$(grep -c 'TAIL-MARKER' <<<"$big_body")"
expect_equal "an oversized log is cut to 60000 bytes" "60000" "$(sed -n '8,$p' <<<"$big_body" | grep -v -e '^```$' -e '^</details>$' | wc -c | tr -d ' ')"

printf 'no trailing newline' > "$workdir/unterminated.log"
unterminated_body=$("$comment" "summary" "$workdir/unterminated.log" "Terraform plan")
expect_equal "an unterminated log still closes the fence on its own line" '```' "$(tail -n 2 <<<"$unterminated_body" | head -n 1)"

status=0
"$comment" "summary" /nonexistent.log "Terraform plan" >/dev/null 2>&1 || status=$?
expect_equal "a missing log is rejected" "2" "$status"

status=0
"$comment" "summary" >/dev/null 2>&1 || status=$?
expect_equal "missing arguments print usage" "2" "$status"

[ "$failures" -eq 0 ]
