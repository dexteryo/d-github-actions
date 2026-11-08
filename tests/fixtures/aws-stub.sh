#!/usr/bin/env bash
set -euo pipefail

echo "$*" >> "$AWS_STUB_LOG"

case "$1 $2" in
  "lambda get-function")
    case "$AWS_STUB_MODE" in
      exists) echo "arn:aws:lambda:eu-west-1:123456789012:function:example" ;;
      missing)
        echo "An error occurred (ResourceNotFoundException) when calling the GetFunction operation: Function not found" >&2
        exit 254
        ;;
      denied)
        echo "An error occurred (AccessDeniedException) when calling the GetFunction operation: not authorized" >&2
        exit 254
        ;;
    esac
    ;;
  "lambda update-function-code")
    zip_argument=""
    previous=""
    for argument in "$@"; do
      if [ "$previous" = "--zip-file" ]; then zip_argument=${argument#fileb://}; fi
      previous=$argument
    done
    unzip -Z1 "$zip_argument" > "$AWS_STUB_ZIP_LISTING"
    echo "{}"
    ;;
  "lambda wait") ;;
  "ecr describe-images")
    case "$AWS_STUB_MODE" in
      exists) echo "sha256:1111111111111111111111111111111111111111111111111111111111111111" ;;
      missing)
        echo "An error occurred (ImageNotFoundException) when calling the DescribeImages operation: The image with imageId {imageTag:'0.0.0'} does not exist" >&2
        exit 254
        ;;
      denied)
        echo "An error occurred (AccessDeniedException) when calling the DescribeImages operation: not authorized" >&2
        exit 254
        ;;
    esac
    ;;
  "scheduler list-schedules")
    case "$AWS_STUB_MODE" in
      empty) echo "None" ;;
      denied)
        echo "An error occurred (AccessDeniedException) when calling the ListSchedules operation: not authorized" >&2
        exit 254
        ;;
      services-only) printf 'example-int-start-svc-api\texample-int-stop-svc-api\n' ;;
      two-databases) printf 'example-int-start-db-ledger\texample-int-start-db-main\texample-int-start-svc-api\texample-int-stop-db-ledger\texample-int-stop-db-main\texample-int-stop-svc-api\n' ;;
      *) printf 'example-int-start-db-main\texample-int-start-svc-api\texample-int-start-svc-auth\texample-int-stop-db-main\texample-int-stop-svc-api\texample-int-stop-svc-auth\n' ;;
    esac
    ;;
  "scheduler get-schedule")
    name=""
    previous=""
    for argument in "$@"; do
      if [ "$previous" = "--name" ]; then name=$argument; fi
      previous=$argument
    done
    case "$name" in
      *-start-db-main) echo '{"DbInstanceIdentifier":"example-int-postgres"}' ;;
      *-stop-db-main) echo '{"DbInstanceIdentifier":"example-int-postgres"}' ;;
      *-db-ledger) echo '{"DbInstanceIdentifier":"example-int-ledger"}' ;;
      *-start-svc-api) echo '{"Cluster":"example-int","Service":"example-api-int","DesiredCount":2}' ;;
      *-stop-svc-api) echo '{"Cluster":"example-int","Service":"example-api-int","DesiredCount":0}' ;;
      *-start-svc-auth) echo '{"Cluster":"example-int","Service":"example-auth-int","DesiredCount":1}' ;;
      *-stop-svc-auth) echo '{"Cluster":"example-int","Service":"example-auth-int","DesiredCount":0}' ;;
    esac
    ;;
  "rds describe-db-instances")
    case "$*" in
      *example-int-postgres*) echo "${AWS_STUB_SECOND_DB_STATUS:-${AWS_STUB_DB_STATUS:-available}}" ;;
      *) echo "${AWS_STUB_DB_STATUS:-available}" ;;
    esac
    ;;
  "rds start-db-instance" | "rds stop-db-instance") echo "{}" ;;
  "rds wait") ;;
  "ecs update-service") echo "example" ;;
  "ecs wait") ;;
  *)
    echo "unexpected aws call: $*" >&2
    exit 1
    ;;
esac
