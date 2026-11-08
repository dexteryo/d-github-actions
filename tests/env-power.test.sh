#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
script="$root/scripts/env-power.sh"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

mkdir -p "$work/bin"
cp "$root/tests/fixtures/aws-stub.sh" "$work/bin/aws"

export PATH="$work/bin:$PATH"
export AWS_STUB_LOG="$work/aws.log"

failures=0
run() {
  : > "$AWS_STUB_LOG"
  AWS_STUB_MODE=$1 AWS_STUB_DB_STATUS=$2 "$script" "${@:3}" > "$work/out.txt" 2> "$work/err.txt"
}

expect_exit() {
  local description=$1 expected=$2 mode=$3 status=$4 actual=0
  shift 4
  run "$mode" "$status" "$@" || actual=$?
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

expect_order() {
  local description=$1 first=$2 second=$3 file=$4 first_line second_line
  first_line=$(grep -n -m1 -- "$first" "$file" | cut -d: -f1)
  second_line=$(grep -n -m1 -- "$second" "$file" | cut -d: -f1)
  if [ -n "$first_line" ] && [ -n "$second_line" ] && [ "$first_line" -lt "$second_line" ]; then
    echo "ok   - $description"
  else
    echo "FAIL - $description ('$first' at ${first_line:-none}, '$second' at ${second_line:-none})"
    failures=$((failures + 1))
  fi
}

expect_exit "a stopped environment starts" 0 full stopped example-int start true
expect_log "the database is started" "rds start-db-instance --db-instance-identifier example-int-postgres" "$AWS_STUB_LOG"
expect_log "it waits for the database" "rds wait db-instance-available --db-instance-identifier example-int-postgres" "$AWS_STUB_LOG"
expect_log "services get the count of their start schedule" "ecs update-service --cluster example-int --service example-api-int --desired-count 2" "$AWS_STUB_LOG"
expect_log "every service is started" "ecs update-service --cluster example-int --service example-auth-int --desired-count 1" "$AWS_STUB_LOG"
expect_order "the database is available before services scale up" "rds wait db-instance-available" "ecs update-service" "$AWS_STUB_LOG"
expect_log "it waits for services to settle" "ecs wait services-stable --cluster example-int --services example-api-int" "$AWS_STUB_LOG"
expect_no_log "stop schedules are not read on start" "get-schedule --group-name example-int --name example-int-stop" "$AWS_STUB_LOG"

expect_exit "a running database is not started again" 0 full available example-int start true
expect_no_log "no start call for an available database" "rds start-db-instance" "$AWS_STUB_LOG"
expect_log "services are still scaled up" "ecs update-service --cluster example-int --service example-api-int --desired-count 2" "$AWS_STUB_LOG"

expect_exit "start without waiting" 0 full stopped example-int start false
expect_no_log "no database wait" "rds wait" "$AWS_STUB_LOG"
expect_no_log "no service wait" "ecs wait" "$AWS_STUB_LOG"

expect_exit "a running environment stops" 0 full available example-int stop true
expect_log "services scale to zero" "ecs update-service --cluster example-int --service example-api-int --desired-count 0" "$AWS_STUB_LOG"
expect_log "the database is stopped" "rds stop-db-instance --db-instance-identifier example-int-postgres" "$AWS_STUB_LOG"
expect_order "services stop before the database" "ecs update-service" "rds stop-db-instance" "$AWS_STUB_LOG"

expect_no_log "start schedules are not read on stop" "get-schedule --group-name example-int --name example-int-start" "$AWS_STUB_LOG"

expect_exit "a stopped database is not stopped again" 0 full stopped example-int stop false
expect_no_log "no stop call for a stopped database" "rds stop-db-instance" "$AWS_STUB_LOG"

expect_exit "a database in another state fails the start" 1 full backing-up example-int start true
expect_no_log "services are not started when the database cannot start" "ecs update-service" "$AWS_STUB_LOG"

export AWS_STUB_SECOND_DB_STATUS=backing-up
expect_exit "a start fails when any database cannot start" 1 two-databases stopped example-int start true
expect_no_log "no database starts when a later one cannot" "rds start-db-instance" "$AWS_STUB_LOG"
expect_log "the error names the database" "example-int-postgres is backing-up and cannot be started now" "$work/err.txt"

expect_exit "a stop fails when any database cannot stop" 1 two-databases available example-int stop true
expect_no_log "no service scales down when a database cannot stop" "ecs update-service" "$AWS_STUB_LOG"
expect_no_log "no database stops when a later one cannot" "rds stop-db-instance" "$AWS_STUB_LOG"
expect_log "the stop error reads correctly" "cannot be stopped now; nothing was changed" "$work/err.txt"
unset AWS_STUB_SECOND_DB_STATUS

expect_exit "two stopped databases both start" 0 two-databases stopped example-int start false
expect_log "the first database starts" "rds start-db-instance --db-instance-identifier example-int-ledger" "$AWS_STUB_LOG"
expect_log "the second database starts" "rds start-db-instance --db-instance-identifier example-int-postgres" "$AWS_STUB_LOG"

expect_exit "a group with services only works" 0 services-only available example-int start false
expect_no_log "no database calls without database schedules" "rds " "$AWS_STUB_LOG"

expect_exit "a group without schedules fails" 1 empty available example-int start true
expect_log "the error names the group" "no start schedules found in schedule group example-int" "$work/err.txt"

expect_exit "an AWS error fails the run" 254 denied available example-int start true
expect_no_log "nothing is changed after an AWS error" "update-service\|start-db-instance" "$AWS_STUB_LOG"

expect_exit "an unknown action is refused" 2 full available example-int restart true
expect_exit "an invalid group name is refused" 2 full available 'example int' start true
expect_exit "an invalid wait value is refused" 2 full available example-int start yes

if [ "$failures" -gt 0 ]; then
  echo "$failures failure(s)"
  exit 1
fi
