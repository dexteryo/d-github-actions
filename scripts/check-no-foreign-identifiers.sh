#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
denylist=${FOREIGN_IDENTIFIERS_DENYLIST:-$root/scripts/foreign-identifiers.sha256}
scan_git_history=false
paths=()

for argument in "$@"; do
  case "$argument" in
    --git) scan_git_history=true ;;
    *) paths+=("$argument") ;;
  esac
done

if [ ! -r "$denylist" ]; then
  echo "deny-list not found: $denylist" >&2
  exit 2
fi

list_files() {
  if [ "${#paths[@]}" -gt 0 ]; then
    find "${paths[@]}" -type f -not -path '*/.git/*' -not -path '*/.terraform/*'
  else
    (cd "$root" && git ls-files --cached --others --exclude-standard)
  fi
}

read -r -d '' scanner <<'PY' || true
import hashlib, os, re, sys

denylist_path, root, mode = sys.argv[1], sys.argv[2], sys.argv[3]
with open(denylist_path, encoding="ascii") as handle:
    denied = {line.strip() for line in handle if line.strip()}

allowed_account_ids = {"123456789012"}
allowed_email_domains = {"example.com", "example.org", "example.test", "users.noreply.github.com"}
skipped_names = {".terraform.lock.hcl", "foreign-identifiers.sha256"}
skipped_parts = {".clever", ".git", ".terraform"}
token_pattern = re.compile(r"[a-z0-9]+")
account_pattern = re.compile(r"(?<![0-9A-Za-z])[0-9]{12}(?![0-9A-Za-z])")
email_pattern = re.compile(r"([A-Za-z0-9._%+-]+)@([A-Za-z0-9.-]+\.[A-Za-z]{2,})")
longest_phrase = 3


def digest(text):
    return hashlib.sha256(text.encode()).hexdigest()


def findings_in(line, check_email=True):
    tokens = token_pattern.findall(line.lower())
    for start in range(len(tokens)):
        for width in range(1, longest_phrase + 1):
            window = tokens[start:start + width]
            if len(window) < width:
                break
            hashed = digest("".join(window))
            if hashed in denied:
                yield f"denied term (sha256 {hashed[:8]})"
    for number in account_pattern.findall(line):
        if number not in allowed_account_ids and len(set(number)) > 1:
            yield "12-digit number that is not the placeholder account id"
    for local_part, domain in email_pattern.findall(line) if check_email else []:
        if domain.lower() not in allowed_email_domains and (local_part, domain.lower()) != ("git", "github.com"):
            yield "email address outside the placeholder domains"


failed = False


def report(label, text, check_email=True):
    global failed
    for number, line in enumerate(text.splitlines(), start=1):
        for finding in findings_in(line, check_email):
            print(f"{label}:{number}: {finding}")
            failed = True


if mode == "history":
    report("git-metadata", sys.stdin.read(), check_email=False)
    sys.exit(1 if failed else 0)

for relative in sys.stdin.read().splitlines():
    path = relative if os.path.isabs(relative) else os.path.join(root, relative)
    parts = set(relative.split(os.sep))
    if parts & skipped_parts or os.path.basename(path) in skipped_names or not os.path.isfile(path):
        continue
    if os.path.getsize(path) > 2_000_000:
        continue
    with open(path, "rb") as handle:
        raw = handle.read()
    if b"\0" in raw:
        continue
    report(relative, raw.decode("utf-8", errors="ignore"))

sys.exit(1 if failed else 0)
PY

scan() {
  python3 -I -c "$scanner" "$denylist" "$root" "$1"
}

status=0
list_files | scan files || status=$?

if [ "$scan_git_history" = true ]; then
  git -C "$root" log --all --format='%an%n%ae%n%cn%n%ce%n%B' | scan history || status=$?
fi

if [ "$status" -ne 0 ]; then
  echo "foreign identifiers found; rewrite the pattern in your own words" >&2
fi
exit "$status"
