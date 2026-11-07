#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "usage: release-gate.sh <owner/repo> <version> <tag-prefix> <release-suffix> <environment> [ecr-repository]" >&2
  exit 2
}

[ "$#" -eq 5 ] || [ "$#" -eq 6 ] || usage

repository=$1
version=$2
prefix=$3
suffix=$4
environment=$5
ecr_repository=${6:-}

refuse() { echo "$1" >&2; exit 2; }
[[ "$repository" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || refuse "repository must be owner/name, got '$repository'"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || refuse "version must be X.Y.Z, got '$version'"
[[ "$prefix" =~ ^[A-Za-z0-9_-]*$ ]] || refuse "tag-prefix may only hold letters, digits, _ and -, got '$prefix'"
[[ "$suffix" =~ ^-[A-Za-z0-9.-]+$ ]] || refuse "release-suffix must start with - and hold letters, digits, . and -, got '$suffix'"
[[ "$environment" =~ ^[A-Za-z0-9_.-]+$ ]] || refuse "environment may only hold letters, digits, _, . and -, got '$environment'"

base_tag="$prefix$version"
release_tag="$base_tag$suffix"
errors=$(mktemp)
trap 'rm -f "$errors"' EXIT

tag_commit() {
  local tag=$1 ref type sha
  if ! ref=$(gh api "repos/$repository/git/ref/tags/$tag" 2> "$errors"); then
    grep -q "HTTP 404" "$errors" && return 3
    cat "$errors" >&2
    exit 1
  fi
  type=$(jq -r '.object.type' <<<"$ref")
  sha=$(jq -r '.object.sha' <<<"$ref")
  if [ "$type" = tag ]; then
    sha=$(gh api "repos/$repository/git/tags/$sha" | jq -r '.object.sha')
  fi
  echo "$sha"
}

status=0
sha=$(tag_commit "$base_tag") || status=$?
case "$status" in
  0) ;;
  3) echo "tag $base_tag does not exist in $repository; a release starts from an existing version tag" >&2; exit 1 ;;
  *) exit 1 ;;
esac

status=0
release_sha=$(tag_commit "$release_tag") || status=$?
case "$status" in
  0)
    [ "$release_sha" = "$sha" ] || { echo "$release_tag points at $release_sha, but $base_tag is $sha; a release tag must sit on its version's commit" >&2; exit 1; }
    release_exists=true
    ;;
  3) release_exists=false ;;
  *) exit 1 ;;
esac

deployment_ids=$(gh api --paginate "repos/$repository/deployments?environment=$environment&sha=$sha&per_page=100" | jq -rs 'add | .[].id')
deployed=false
for id in $deployment_ids; do
  state=$(gh api "repos/$repository/deployments/$id/statuses?per_page=1" | jq -r '.[0].state // empty')
  if [ "$state" = success ]; then
    deployed=true
    break
  fi
done
[ "$deployed" = true ] || { echo "$base_tag ($sha) has no successful deployment to the $environment environment; deploy it there first" >&2; exit 1; }

if [ -n "$ecr_repository" ]; then
  if ! aws ecr describe-images --repository-name "$ecr_repository" --image-ids "imageTag=$base_tag" --query 'imageDetails[0].imageDigest' --output text > /dev/null 2> "$errors"; then
    if grep -q ImageNotFoundException "$errors"; then
      echo "image $ecr_repository:$base_tag does not exist; the $environment deploy of $base_tag never pushed it" >&2
    else
      cat "$errors" >&2
    fi
    exit 1
  fi
fi

printf 'sha=%s\nbase-tag=%s\nrelease-tag=%s\nrelease-exists=%s\n' "$sha" "$base_tag" "$release_tag" "$release_exists"
