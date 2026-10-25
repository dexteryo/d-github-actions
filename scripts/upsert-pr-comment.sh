#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "usage: upsert-pr-comment.sh <owner/repo> <pull-request-number> <marker> <author-login> <body-file>" >&2
  exit 2
}

[ "$#" -eq 5 ] || usage

repository=$1
pull_request=$2
marker=$3
author=$4
body_file=$5

if [ ! -r "$body_file" ]; then
  echo "body file not found: $body_file" >&2
  exit 2
fi

comment_id=$(gh api --paginate "repos/$repository/issues/$pull_request/comments" \
  | jq -rs --arg author "$author" --arg marker "$marker" \
    '[.[][] | select(.user.login == $author and (.body | contains($marker)))] | last | .id // empty')

if [ -n "$comment_id" ]; then
  gh api -X PATCH "repos/$repository/issues/comments/$comment_id" -F "body=@$body_file" > /dev/null
  echo "updated comment $comment_id"
else
  gh api -X POST "repos/$repository/issues/$pull_request/comments" -F "body=@$body_file" > /dev/null
  echo "created a comment"
fi
