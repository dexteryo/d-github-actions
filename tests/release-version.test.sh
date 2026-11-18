#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
script="$root/scripts/release-version.sh"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

commit_sha=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
tag_object_sha=cccccccccccccccccccccccccccccccccccccccc

mkdir -p "$work/bin"
cat > "$work/bin/gh" <<'FAKE'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$GH_CALLS"
repo=repos/example/repo
tag=${GH_PREFIX:-}1.9.1
case "$*" in
  "api $repo")
    printf '{"default_branch":"main"}\n'
    ;;
  "api $repo/branches/release/uat")
    printf '{"name":"release/uat","protected":%s}\n' "$GH_PROTECTED"
    ;;
  "api $repo/branches/"*)
    echo "gh: Branch not found (HTTP 404)" >&2
    exit 1
    ;;
  "api $repo/git/ref/tags/$tag")
    case "$GH_TAG" in
      lightweight) printf '{"object":{"type":"commit","sha":"%s"}}\n' "$COMMIT_SHA" ;;
      annotated) printf '{"object":{"type":"tag","sha":"%s"}}\n' "$TAG_OBJECT_SHA" ;;
      missing) echo "gh: Not Found (HTTP 404)" >&2; exit 1 ;;
      error) echo "gh: Server Error (HTTP 500)" >&2; exit 1 ;;
    esac
    ;;
  "api $repo/git/tags/$TAG_OBJECT_SHA")
    printf '{"object":{"type":"commit","sha":"%s"}}\n' "$COMMIT_SHA"
    ;;
  "api $repo/compare/$COMMIT_SHA..."*)
    printf '{"status":"%s"}\n' "$GH_COMPARE"
    ;;
  *)
    echo "unexpected gh call: $*" >&2
    exit 1
    ;;
esac
FAKE
chmod +x "$work/bin/gh"

export PATH="$work/bin:$PATH"
export GH_CALLS="$work/gh.log"
export COMMIT_SHA=$commit_sha TAG_OBJECT_SHA=$tag_object_sha

failures=0
run() {
  : > "$GH_CALLS"
  "$script" "$@" > "$work/out.txt" 2> "$work/err.txt"
}

expect_exit() {
  local description=$1 expected=$2 actual=0
  shift 2
  run "$@" || actual=$?
  if [ "$actual" -eq "$expected" ]; then
    echo "ok   - $description"
  else
    echo "FAIL - $description (exit $actual, expected $expected; $(tr '\n' ' ' < "$work/err.txt"))"
    failures=$((failures + 1))
  fi
}

expect_log() {
  local description=$1 pattern=$2 file=$3
  if grep -q -- "$pattern" "$file"; then
    echo "ok   - $description"
  else
    echo "FAIL - $description (no '$pattern' in $file: $(tr '\n' ' ' < "$file"))"
    failures=$((failures + 1))
  fi
}

expect_no_log() {
  local description=$1 pattern=$2 file=$3
  if grep -q -- "$pattern" "$file"; then
    echo "FAIL - $description ('$pattern' in $file)"
    failures=$((failures + 1))
  else
    echo "ok   - $description"
  fi
}

export GH_TAG=lightweight GH_COMPARE=identical GH_PROTECTED=true
expect_exit "a version on the default branch passes" 0 example/repo 1.9.1 "" main
expect_log "it reports the commit" "^sha=$commit_sha$" "$work/out.txt"
expect_log "it reports the tag" "^tag=1.9.1$" "$work/out.txt"
expect_no_log "the default branch is not checked for protection" "branches/" "$GH_CALLS"

GH_COMPARE=ahead expect_exit "a version behind the branch head passes" 0 example/repo 1.9.1 "" main

GH_COMPARE=diverged expect_exit "a version that diverged from the branch fails" 1 example/repo 1.9.1 "" main
expect_log "the failure names the branch and status" "not on main (compare status: diverged)" "$work/err.txt"

GH_COMPARE=behind expect_exit "a version ahead of the branch fails" 1 example/repo 1.9.1 "" main

GH_TAG=annotated expect_exit "an annotated tag is followed to its commit" 0 example/repo 1.9.1 "" main
expect_log "the annotated tag resolves to the commit" "^sha=$commit_sha$" "$work/out.txt"

GH_TAG=missing expect_exit "a tag that does not exist fails" 1 example/repo 1.9.1 "" main
expect_log "the failure names the missing tag" "tag 1.9.1 does not exist" "$work/err.txt"

GH_TAG=error expect_exit "an API error on the tag fails" 1 example/repo 1.9.1 "" main
expect_log "the API error is shown" "HTTP 500" "$work/err.txt"
expect_no_log "an API error is not reported as a missing tag" "does not exist" "$work/err.txt"

expect_exit "a version on a protected release branch passes" 0 example/repo 1.9.1 "" release/uat
expect_log "the release branch is checked for protection" "branches/release/uat" "$GH_CALLS"
expect_log "the commit is compared with the release branch" "compare/$commit_sha...release/uat" "$GH_CALLS"

GH_PROTECTED=false expect_exit "an unprotected release branch fails" 1 example/repo 1.9.1 "" release/uat
expect_log "the failure says to protect it" "release/uat is not protected" "$work/err.txt"
expect_no_log "the tag is not read before the branch passes" "git/ref/tags" "$GH_CALLS"

expect_exit "a branch that is neither the default nor release/* fails" 1 example/repo 1.9.1 "" feature/x
expect_log "the failure names the allowed branches" "main or release/<name>" "$work/err.txt"

expect_exit "a release branch that does not exist fails" 1 example/repo 1.9.1 "" release/gone
expect_log "the API error is shown" "HTTP 404" "$work/err.txt"

GH_PREFIX=v expect_exit "a tag prefix is applied" 0 example/repo 1.9.1 v main
expect_log "the prefixed tag is reported" "^tag=v1.9.1$" "$work/out.txt"

expect_exit "a version that is not X.Y.Z is refused" 2 example/repo 1.9 "" main
expect_exit "a version with a suffix is refused" 2 example/repo 1.9.1-release "" main
expect_exit "a branch with a query character is refused" 2 example/repo 1.9.1 "" "main?x=1"
expect_exit "a repository that is not owner/name is refused" 2 example 1.9.1 "" main
expect_exit "a wrong number of arguments is refused" 2 example/repo 1.9.1

[ "$failures" -eq 0 ] || { echo "$failures failure(s)"; exit 1; }
