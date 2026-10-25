#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
upsert="$root/scripts/upsert-pr-comment.sh"
fixtures="$root/tests/fixtures"
workdir=$(mktemp -d)
trap 'rm -rf "$workdir"' EXIT

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

mkdir -p "$workdir/bin"
cat > "$workdir/bin/gh" <<'FAKE'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$GH_CALLS"
if [ "$1 $2" = "api --paginate" ]; then
  cat "$GH_COMMENTS"
fi
FAKE
chmod +x "$workdir/bin/gh"
printf 'new body\n<!-- d-github-actions:terraform-plan:infra/envs/example -->\n' > "$workdir/body.md"
marker="<!-- d-github-actions:terraform-plan:infra/envs/example -->"

run() {
  : > "$workdir/calls"
  PATH="$workdir/bin:$PATH" GH_CALLS="$workdir/calls" GH_COMMENTS="$fixtures/$1" \
    "$upsert" example/repo 7 "$marker" "github-actions[bot]" "$workdir/body.md" > /dev/null
  grep -v '^api --paginate' "$workdir/calls" || true
}

expect_equal "the bot's comment with this marker is edited" \
  "api -X PATCH repos/example/repo/issues/comments/102 -F body=@$workdir/body.md" "$(run pr-comments-own.json)"
expect_equal "a copied marker in someone else's comment is never edited; a new comment is made" \
  "api -X POST repos/example/repo/issues/7/comments -F body=@$workdir/body.md" "$(run pr-comments-foreign.json)"
expect_equal "with no matching comment a new one is made" \
  "api -X POST repos/example/repo/issues/7/comments -F body=@$workdir/body.md" "$(run pr-comments-none.json)"
expect_equal "with two matching comments on two pages the newest is edited" \
  "api -X PATCH repos/example/repo/issues/comments/305 -F body=@$workdir/body.md" "$(run pr-comments-two-pages.json)"
expect_equal "another root's comment is left alone" \
  "api -X POST repos/example/repo/issues/7/comments -F body=@$workdir/body.md" "$(run pr-comments-other-root.json)"

status=0
"$upsert" example/repo 7 "$marker" "github-actions[bot]" /nonexistent.md > /dev/null 2>&1 || status=$?
expect_equal "a missing body file is rejected" "2" "$status"

status=0
"$upsert" example/repo 7 > /dev/null 2>&1 || status=$?
expect_equal "missing arguments print usage" "2" "$status"

[ "$failures" -eq 0 ]
