#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
script="$root/scripts/release-gate.sh"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

commit_sha=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
other_sha=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
tag_object_sha=cccccccccccccccccccccccccccccccccccccccc

mkdir -p "$work/bin"
cp "$root/tests/fixtures/aws-stub.sh" "$work/bin/aws"
cat > "$work/bin/gh" <<'FAKE'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$GH_CALLS"
not_found() { echo "gh: Not Found (HTTP 404)" >&2; exit 1; }
ref() { printf '{"ref":"refs/tags/%s","object":{"type":"%s","sha":"%s"}}\n' "$1" "$2" "$3"; }
repo=repos/example/repo
base=${GH_PREFIX:-}1.9.1
case "$*" in
  "api $repo/git/ref/tags/$base")
    case "$GH_BASE" in
      lightweight) ref "$base" commit "$COMMIT_SHA" ;;
      annotated) ref "$base" tag "$TAG_OBJECT_SHA" ;;
      missing) not_found ;;
      error) echo "gh: Server Error (HTTP 500)" >&2; exit 1 ;;
    esac
    ;;
  "api $repo/git/ref/tags/$base-release")
    case "$GH_RELEASE" in
      missing) not_found ;;
      same) ref "$base-release" commit "$COMMIT_SHA" ;;
      other) ref "$base-release" commit "$OTHER_SHA" ;;
    esac
    ;;
  "api $repo/git/tags/$TAG_OBJECT_SHA")
    printf '{"object":{"type":"commit","sha":"%s"}}\n' "$COMMIT_SHA"
    ;;
  "api --paginate $repo/deployments?environment=staging&sha=$COMMIT_SHA&per_page=100")
    id=0
    printf '['
    for _ in $GH_STATES; do
      id=$((id + 1))
      [ "$id" -eq 1 ] || printf ','
      printf '{"id":%d}' "$id"
    done
    printf ']\n'
    ;;
  "api $repo/deployments/"*"/statuses?per_page=1")
    call="$*"
    id=${call#"api $repo/deployments/"}
    id=${id%%/*}
    read -r -a states <<<"$GH_STATES"
    printf '[{"state":"%s"}]\n' "${states[$((id - 1))]}"
    ;;
  *)
    echo "unexpected gh call: $*" >&2
    exit 1
    ;;
esac
FAKE
chmod +x "$work/bin/gh"

export PATH="$work/bin:$PATH"
export GH_CALLS="$work/gh.log" AWS_STUB_LOG="$work/aws.log"
export COMMIT_SHA=$commit_sha OTHER_SHA=$other_sha TAG_OBJECT_SHA=$tag_object_sha

failures=0
run() {
  : > "$GH_CALLS"
  : > "$AWS_STUB_LOG"
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

expect_empty() {
  local description=$1 file=$2
  if [ -s "$file" ]; then
    echo "FAIL - $description ($(tr '\n' ' ' < "$file"))"
    failures=$((failures + 1))
  else
    echo "ok   - $description"
  fi
}

export GH_BASE=lightweight GH_RELEASE=missing GH_STATES=success AWS_STUB_MODE=exists
expect_exit "a version deployed to the environment passes" 0 example/repo 1.9.1 "" -release staging
expect_log "it reports the commit" "^sha=$commit_sha$" "$work/out.txt"
expect_log "it reports the base tag" "^base-tag=1.9.1$" "$work/out.txt"
expect_log "it reports the release tag" "^release-tag=1.9.1-release$" "$work/out.txt"
expect_log "it reports that the release tag does not exist yet" "^release-exists=false$" "$work/out.txt"
expect_empty "without an ECR repository AWS is not called" "$AWS_STUB_LOG"

GH_BASE=annotated expect_exit "an annotated base tag is followed to its commit" 0 example/repo 1.9.1 "" -release staging
expect_log "the annotated tag resolves to the commit" "^sha=$commit_sha$" "$work/out.txt"

GH_BASE=missing expect_exit "a base tag that does not exist fails" 1 example/repo 1.9.1 "" -release staging
expect_log "the failure names the missing tag" "1.9.1" "$work/err.txt"

GH_BASE=error expect_exit "an API error on the base tag fails" 1 example/repo 1.9.1 "" -release staging
expect_log "the API error is shown" "HTTP 500" "$work/err.txt"
if grep -q "does not exist" "$work/err.txt"; then
  echo "FAIL - an API error is not reported as a missing tag"
  failures=$((failures + 1))
else
  echo "ok   - an API error is not reported as a missing tag"
fi

GH_STATES="" expect_exit "a version never deployed to the environment fails" 1 example/repo 1.9.1 "" -release staging
expect_log "the failure names the environment" "staging" "$work/err.txt"

GH_STATES="failure error" expect_exit "only failed deployments fail" 1 example/repo 1.9.1 "" -release staging

GH_STATES="failure success" expect_exit "one successful deployment among failed ones passes" 0 example/repo 1.9.1 "" -release staging

GH_STATES="in_progress" expect_exit "a deployment still in progress fails" 1 example/repo 1.9.1 "" -release staging

GH_RELEASE=same expect_exit "a release tag already on the same commit passes" 0 example/repo 1.9.1 "" -release staging
expect_log "it reports that the release tag exists" "^release-exists=true$" "$work/out.txt"

GH_RELEASE=other expect_exit "a release tag on another commit fails" 1 example/repo 1.9.1 "" -release staging
expect_log "the failure names both commits" "$other_sha" "$work/err.txt"

expect_exit "an image tagged with the version in ECR passes" 0 example/repo 1.9.1 "" -release staging example/api
expect_log "ECR is asked for the version tag" "ecr describe-images --repository-name example/api --image-ids imageTag=1.9.1" "$AWS_STUB_LOG"

AWS_STUB_MODE=missing expect_exit "a version with no image in ECR fails" 1 example/repo 1.9.1 "" -release staging example/api
expect_log "the failure names the image" "example/api:1.9.1" "$work/err.txt"

AWS_STUB_MODE=denied expect_exit "an ECR permission error fails" 1 example/repo 1.9.1 "" -release staging example/api
expect_log "the ECR error is shown" "AccessDeniedException" "$work/err.txt"

GH_PREFIX=v expect_exit "a tag prefix is applied to both tags" 0 example/repo 1.9.1 v -release staging example/api
expect_log "the prefixed release tag is reported" "^release-tag=v1.9.1-release$" "$work/out.txt"
expect_log "the ECR tag carries the prefix" "imageTag=v1.9.1" "$AWS_STUB_LOG"

expect_exit "a version that is not X.Y.Z is refused" 2 example/repo 1.9 "" -release staging
expect_exit "a version that already carries the suffix is refused" 2 example/repo 1.9.1-release "" -release staging
expect_exit "an empty release suffix is refused" 2 example/repo 1.9.1 "" "" staging
expect_exit "a release suffix without a leading - is refused" 2 example/repo 1.9.1 "" release staging
expect_exit "an environment name with a query character is refused" 2 example/repo 1.9.1 "" -release "staging&sha=x"
expect_exit "a repository that is not owner/name is refused" 2 example 1.9.1 "" -release staging
expect_exit "a wrong number of arguments is refused" 2 example/repo 1.9.1

[ "$failures" -eq 0 ] || { echo "$failures failure(s)"; exit 1; }
