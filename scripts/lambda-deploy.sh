#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -lt 6 ]; then
  echo "usage: lambda-deploy.sh <function-name> <package-directory> <architecture> <skip-if-missing> <wait> <file>..." >&2
  exit 2
fi

function_name=$1
package_directory=$2
architecture=$3
skip_if_missing=$4
wait_for_update=$5
shift 5

if ! [[ "$function_name" =~ ^[A-Za-z0-9_-]{1,64}$ ]]; then
  echo "function-name must be 1 to 64 letters, digits, hyphens or underscores: $function_name" >&2
  exit 2
fi

case "$architecture" in
  arm64 | x86_64) ;;
  *)
    echo "architecture must be arm64 or x86_64: $architecture" >&2
    exit 2
    ;;
esac

if [ ! -d "$package_directory" ]; then
  echo "package-directory does not exist: $package_directory" >&2
  exit 2
fi

for file in "$@"; do
  case "$file" in
    /* | *..*)
      echo "package-files must be relative paths inside package-directory: $file" >&2
      exit 2
      ;;
  esac
  if [ ! -f "$package_directory/$file" ]; then
    echo "package file not found: $package_directory/$file" >&2
    exit 2
  fi
done

work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT
errors="$work_dir/errors.txt"

if ! aws lambda get-function --function-name "$function_name" --query Configuration.FunctionArn --output text > /dev/null 2> "$errors"; then
  if grep -q ResourceNotFoundException "$errors"; then
    if [ "$skip_if_missing" = "true" ]; then
      echo "::notice::$function_name does not exist yet; it gets its code after the next infrastructure apply"
      exit 0
    fi
    echo "::error::$function_name does not exist" >&2
    exit 1
  fi
  cat "$errors" >&2
  exit 1
fi

zip_file="$work_dir/function.zip"
(cd "$package_directory" && zip -q -X "$zip_file" "$@")

aws lambda update-function-code --function-name "$function_name" --zip-file "fileb://$zip_file" --architectures "$architecture" --output json > /dev/null

if [ "$wait_for_update" = "true" ]; then
  aws lambda wait function-updated-v2 --function-name "$function_name"
fi

echo "Updated $function_name"
