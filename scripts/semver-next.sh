#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "usage: semver-next.sh <commit> <initial-version> [tag-prefix]" >&2
  exit 2
}

[ "$#" -eq 2 ] || [ "$#" -eq 3 ] || usage

target=$1
initial=$2
prefix=${3:-}

[[ "$initial" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "initial-version must be X.Y.Z, got '$initial'" >&2; exit 2; }
[[ "$prefix" =~ ^[A-Za-z0-9_-]*$ ]] || { echo "tag-prefix may only hold letters, digits, _ and -, got '$prefix'" >&2; exit 2; }

target_sha=$(git rev-parse --verify --quiet "$target^{commit}") || { echo "unknown commit: $target" >&2; exit 1; }

previous=$(git tag --merged "$target_sha" \
  | grep -E "^${prefix}[0-9]+\.[0-9]+\.[0-9]+$" \
  | sed "s/^${prefix}//" \
  | sort -t. -k1,1n -k2,2n -k3,3n \
  | tail -n 1 || true)

emit() {
  printf 'previous=%s\nversion=%s\ntag=%s\nbump=%s\n' "${previous:+$prefix$previous}" "$1" "$prefix$1" "$2"
}

if [ -z "$previous" ]; then
  emit "$initial" initial
  exit 0
fi

if [ "$(git rev-parse "$prefix$previous^{commit}")" = "$target_sha" ]; then
  emit "$previous" none
  exit 0
fi

range="$prefix$previous..$target_sha"
subjects=$(git log --no-merges --format=%s "$range")
bodies=$(git log --no-merges --format=%b "$range")

if grep -Eq '^[[:alpha:]]+(\([^)]*\))?!:' <<<"$subjects" || grep -Eq '^BREAKING[ -]CHANGE:' <<<"$bodies"; then
  bump="major"
elif grep -Eiq '^feat(\([^)]*\))?:' <<<"$subjects"; then
  bump="minor"
else
  bump="patch"
fi

IFS=. read -r major minor patch <<<"$previous"
case "$bump" in
  major) next="$((major + 1)).0.0" ;;
  minor) next="$major.$((minor + 1)).0" ;;
  patch) next="$major.$minor.$((patch + 1))" ;;
esac

emit "$next" "$bump"
