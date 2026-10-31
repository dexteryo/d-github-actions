#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
script="$root/scripts/lambda-deploy.sh"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

mkdir -p "$work/bin" "$work/dist/nested"
cp "$root/tests/fixtures/aws-stub.sh" "$work/bin/aws"
echo "exports.handler = async () => ({});" > "$work/dist/intake.cjs"
echo "exports.handler = async () => ({});" > "$work/dist/other.cjs"
echo "secret" > "$work/dist/nested/not-listed.txt"

export PATH="$work/bin:$PATH"
export AWS_STUB_LOG="$work/aws.log"
export AWS_STUB_ZIP_LISTING="$work/zip-listing.txt"

failures=0
run() {
  : > "$AWS_STUB_LOG"
  : > "$AWS_STUB_ZIP_LISTING"
  AWS_STUB_MODE=$1 "$script" "${@:2}" > "$work/out.txt" 2> "$work/err.txt"
}

expect_exit() {
  local description=$1 expected=$2 mode=$3 actual=0
  shift 3
  run "$mode" "$@" || actual=$?
  if [ "$actual" -eq "$expected" ]; then
    echo "ok   - $description"
  else
    echo "FAIL - $description (exit $actual, expected $expected)"
    failures=$((failures + 1))
  fi
}

expect_log() {
  local description=$1 pattern=$2 file=$3
  if grep -q -- "$pattern" "$file"; then
    echo "ok   - $description"
  else
    echo "FAIL - $description (no '$pattern' in $file)"
    failures=$((failures + 1))
  fi
}

expect_no_log() {
  local description=$1 pattern=$2 file=$3
  if grep -q -- "$pattern" "$file"; then
    echo "FAIL - $description ('$pattern' found in $file)"
    failures=$((failures + 1))
  else
    echo "ok   - $description"
  fi
}

expect_exit "an existing function is updated" 0 exists example-fn "$work/dist" arm64 true true intake.cjs
expect_log "the code is pushed with the architecture" "update-function-code --function-name example-fn .*--architectures arm64" "$AWS_STUB_LOG"
expect_log "it waits for the update" "lambda wait function-updated-v2 --function-name example-fn" "$AWS_STUB_LOG"
expect_log "only the listed file is in the zip, at its root" "^intake.cjs$" "$AWS_STUB_ZIP_LISTING"
expect_no_log "unlisted files stay out of the zip" "not-listed" "$AWS_STUB_ZIP_LISTING"

expect_exit "several files go into one zip" 0 exists example-fn "$work/dist" x86_64 true true intake.cjs other.cjs
expect_log "the second file is in the zip" "^other.cjs$" "$AWS_STUB_ZIP_LISTING"
expect_log "the other architecture is passed on" "--architectures x86_64" "$AWS_STUB_LOG"

expect_exit "waiting can be switched off" 0 exists example-fn "$work/dist" arm64 true false intake.cjs
expect_no_log "no wait call is made" "lambda wait" "$AWS_STUB_LOG"

expect_exit "a missing function is skipped with a notice" 0 missing example-fn "$work/dist" arm64 true true intake.cjs
expect_log "the notice names the function" "example-fn does not exist yet" "$work/out.txt"
expect_no_log "nothing is pushed for a missing function" "update-function-code" "$AWS_STUB_LOG"

expect_exit "a missing function fails when skipping is off" 1 missing example-fn "$work/dist" arm64 false true intake.cjs
expect_exit "any other error from AWS fails" 1 denied example-fn "$work/dist" arm64 true true intake.cjs
expect_log "the AWS error is shown" "AccessDeniedException" "$work/err.txt"
expect_no_log "nothing is pushed after an AWS error" "update-function-code" "$AWS_STUB_LOG"

expect_exit "a function name with a space is refused" 2 exists "bad name" "$work/dist" arm64 true true intake.cjs
expect_exit "an unknown architecture is refused" 2 exists example-fn "$work/dist" mips true true intake.cjs
expect_exit "a missing directory is refused" 2 exists example-fn "$work/nowhere" arm64 true true intake.cjs
expect_exit "a missing file is refused" 2 exists example-fn "$work/dist" arm64 true true absent.cjs
expect_exit "a path outside the directory is refused" 2 exists example-fn "$work/dist" arm64 true true ../dist/intake.cjs
expect_exit "an absolute path is refused" 2 exists example-fn "$work/dist" arm64 true true "$work/dist/intake.cjs"
expect_exit "no files at all is refused" 2 exists example-fn "$work/dist" arm64 true true

[ "$failures" -eq 0 ]
