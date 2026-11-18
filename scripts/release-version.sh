#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "usage: release-version.sh <owner/repo> <version> <tag-prefix> <branch>" >&2
  exit 2
}

[ "$#" -eq 4 ] || usage

repository=$1
version=$2
prefix=$3
branch=$4

refuse() { echo "$1" >&2; exit 2; }
[[ "$repository" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || refuse "repository must be owner/name, got '$repository'"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || refuse "version must be X.Y.Z, got '$version'"
[[ "$prefix" =~ ^[A-Za-z0-9_-]*$ ]] || refuse "tag-prefix may only hold letters, digits, _ and -, got '$prefix'"
[[ "$branch" =~ ^[A-Za-z0-9._/-]+$ ]] || refuse "branch may only hold letters, digits, ., _, / and -, got '$branch'"

tag="$prefix$version"
errors=$(mktemp)
trap 'rm -f "$errors"' EXIT

api() {
  gh api "$1" 2> "$errors" || { cat "$errors" >&2; exit 1; }
}

default_branch=$(api "repos/$repository" | jq -r .default_branch)
if [ "$branch" != "$default_branch" ]; then
  [[ "$branch" =~ ^release/[A-Za-z0-9._-]+$ ]] || { echo "branch must be $default_branch or release/<name>, got '$branch'" >&2; exit 1; }
  [ "$(api "repos/$repository/branches/$branch" | jq -r .protected)" = true ] || { echo "$branch is not protected; protect it before releasing from it" >&2; exit 1; }
fi

if ! ref=$(gh api "repos/$repository/git/ref/tags/$tag" 2> "$errors"); then
  grep -q "HTTP 404" "$errors" && { echo "tag $tag does not exist in $repository" >&2; exit 1; }
  cat "$errors" >&2
  exit 1
fi
sha=$(jq -r '.object.sha' <<<"$ref")
if [ "$(jq -r '.object.type' <<<"$ref")" = tag ]; then
  sha=$(api "repos/$repository/git/tags/$sha" | jq -r '.object.sha')
fi

status=$(api "repos/$repository/compare/$sha...$branch" | jq -r .status)
[[ "$status" == ahead || "$status" == identical ]] || { echo "$tag ($sha) is not on $branch (compare status: $status)" >&2; exit 1; }

echo "sha=$sha"
echo "tag=$tag"
