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
  *)
    echo "unexpected aws call: $*" >&2
    exit 1
    ;;
esac
