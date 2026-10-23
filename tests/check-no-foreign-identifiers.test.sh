#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
check="$root/scripts/check-no-foreign-identifiers.sh"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
failures=0

canary=plantedcanary
foreign_account=$(printf '%s%s' 210987 654321)
foreign_domain=corp.$(printf '%s' internal)
printf '%s' "$canary" | shasum -a 256 | cut -d' ' -f1 > "$work/denylist.sha256"
printf '%s' "canaryphrase" | shasum -a 256 | cut -d' ' -f1 >> "$work/denylist.sha256"
export FOREIGN_IDENTIFIERS_DENYLIST="$work/denylist.sha256"

expect_failure() {
  local name=$1 content=$2
  mkdir -p "$work/$name"
  printf '%s\n' "$content" > "$work/$name/file.txt"
  if "$check" "$work/$name" > "$work/$name.out" 2>&1; then
    echo "FAIL $name: the check passed"
    failures=$((failures + 1))
  elif grep -q "$name/file.txt:1" "$work/$name.out"; then
    echo "ok   $name"
  else
    echo "FAIL $name: no file and line in the report"
    failures=$((failures + 1))
  fi
}

expect_success() {
  local name=$1 content=$2
  mkdir -p "$work/$name"
  printf '%s\n' "$content" > "$work/$name/file.txt"
  if "$check" "$work/$name" > "$work/$name.out" 2>&1; then
    echo "ok   $name"
  else
    echo "FAIL $name: the check failed"
    cat "$work/$name.out"
    failures=$((failures + 1))
  fi
}

expect_failure planted_term "name = \"team-$canary-prod\""
expect_failure planted_term_upper_case "PLANTEDCANARY"
expect_failure planted_phrase_across_separators "see the-canary-phrase here"
expect_failure foreign_account_id "arn:aws:iam::${foreign_account}:role/x"
expect_failure foreign_email "contact someone@${foreign_domain}"
expect_success placeholder_account_id "arn:aws:iam::123456789012:role/x"
expect_success placeholder_email "contact someone@example.com"
expect_success placeholder_uuid "key/00000000-0000-0000-0000-000000000000"
expect_success ordinary_text "terraform module for ecs services"

if "$check" "$work/planted_term" 2>&1 | grep -q "$canary"; then
  echo "FAIL the report prints the denied term"
  failures=$((failures + 1))
else
  echo "ok   report hides the denied term"
fi

unset FOREIGN_IDENTIFIERS_DENYLIST
default_list="$root/scripts/foreign-identifiers.sha256"
if [ "$(grep -cEv '^[0-9a-f]{64}$' "$default_list")" -eq 0 ] && [ "$(wc -l < "$default_list")" -gt 0 ]; then
  echo "ok   default deny-list holds only sha256 digests"
else
  echo "FAIL default deny-list is not hashed"
  failures=$((failures + 1))
fi

if "$check" > "$work/repo.out" 2>&1; then
  echo "ok   repository is clean"
else
  echo "FAIL repository contains foreign identifiers"
  cat "$work/repo.out"
  failures=$((failures + 1))
fi

exit "$failures"
