#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
script="$root/scripts/semver-next.sh"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.com
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.com

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

expect_exit() {
  local description=$1 expected=$2 actual=0
  shift 2
  (cd "$repo" && "$script" "$@") > /dev/null 2>&1 || actual=$?
  if [ "$actual" -eq "$expected" ]; then
    echo "ok   - $description"
  else
    echo "FAIL - $description (exit $actual, expected $expected)"
    failures=$((failures + 1))
  fi
}

new_repo() {
  repo="$work/$1"
  git init -q -b main "$repo"
  commit "chore: initial commit"
}

commit() {
  git -C "$repo" commit -q --allow-empty -m "$1"
}

next() {
  (cd "$repo" && "$script" "$(git rev-parse HEAD)" "${1:-0.1.0}" "${2:-}") | tr '\n' ' ' | sed 's/ $//'
}

new_repo no-tags
commit "fix: something"
expect_equal "with no tag the initial version is used" \
  "previous= version=0.1.0 tag=0.1.0 bump=initial" "$(next)"
expect_equal "the initial version is configurable" \
  "previous= version=1.0.0 tag=1.0.0 bump=initial" "$(next 1.0.0)"

new_repo patch
git -C "$repo" tag 1.9.1
commit "fix(api): reject an empty body"
commit "docs: explain the release"
commit "an unconventional message"
expect_equal "fix, docs and unconventional commits bump patch" \
  "previous=1.9.1 version=1.9.2 tag=1.9.2 bump=patch" "$(next)"

new_repo minor
git -C "$repo" tag 1.9.1
commit "fix: one"
commit "feat(web): new screen"
expect_equal "a feat bumps minor and resets patch" \
  "previous=1.9.1 version=1.10.0 tag=1.10.0 bump=minor" "$(next)"

new_repo major-bang
git -C "$repo" tag 1.9.1
commit "feat(api)!: drop the v0 routes"
expect_equal "a ! after the type bumps major" \
  "previous=1.9.1 version=2.0.0 tag=2.0.0 bump=major" "$(next)"

new_repo major-footer
git -C "$repo" tag 1.9.1
git -C "$repo" commit -q --allow-empty -m "refactor: rename the column" -m "BREAKING CHANGE: clients must send user_id"
expect_equal "a BREAKING CHANGE footer bumps major" \
  "previous=1.9.1 version=2.0.0 tag=2.0.0 bump=major" "$(next)"

new_repo release-suffix
git -C "$repo" tag 1.9.1
git -C "$repo" tag 1.9.1-release
commit "fix: after the release"
git -C "$repo" tag 2.0.0-release
expect_equal "tags with a suffix never count as the base version" \
  "previous=1.9.1 version=1.9.2 tag=1.9.2 bump=patch" "$(next)"

new_repo numeric-order
git -C "$repo" tag 1.2.0
commit "fix: a"
git -C "$repo" tag 1.10.0
commit "fix: b"
git -C "$repo" tag 1.9.0 HEAD~1
expect_equal "the highest version wins, compared numerically" \
  "previous=1.10.0 version=1.10.1 tag=1.10.1 bump=patch" "$(next)"

new_repo already-tagged
commit "feat: shipped"
git -C "$repo" tag 0.4.0
expect_equal "a commit that already has a version keeps it" \
  "previous=0.4.0 version=0.4.0 tag=0.4.0 bump=none" "$(next)"

new_repo unreachable
git -C "$repo" tag 0.2.0
git -C "$repo" switch -q -c other
commit "feat: on another branch"
git -C "$repo" tag 0.9.0
git -C "$repo" switch -q main
commit "fix: on main"
expect_equal "a version tagged only on another branch is ignored" \
  "previous=0.2.0 version=0.2.1 tag=0.2.1 bump=patch" "$(next)"

new_repo merges
git -C "$repo" tag 0.2.0
git -C "$repo" switch -q -c feature
commit "fix: on the branch"
git -C "$repo" switch -q main
git -C "$repo" merge -q --no-ff feature -m "feat!: a merge commit that would bump major if it counted"
expect_equal "merge commit subjects are ignored, the merged commits decide" \
  "previous=0.2.0 version=0.2.1 tag=0.2.1 bump=patch" "$(next)"

new_repo prefix
git -C "$repo" tag v1.0.0
git -C "$repo" tag 5.0.0
commit "feat: prefixed"
expect_equal "with a prefix only prefixed tags count, and the new tag carries it" \
  "previous=v1.0.0 version=1.1.0 tag=v1.1.0 bump=minor" "$(next 0.1.0 v)"

new_repo invalid
expect_exit "an initial version that is not X.Y.Z is refused" 2 "$(git -C "$repo" rev-parse HEAD)" 1.0
expect_exit "a prefix with other characters is refused" 2 "$(git -C "$repo" rev-parse HEAD)" 0.1.0 'v*'
expect_exit "an unknown commit is refused" 1 0000000000000000000000000000000000000000 0.1.0
expect_exit "a wrong number of arguments is refused" 2 HEAD

[ "$failures" -eq 0 ] || { echo "$failures failure(s)"; exit 1; }
