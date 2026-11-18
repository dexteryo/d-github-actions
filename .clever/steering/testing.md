# Testing

> Generated 2026-10-31 (INIT) from `v0.3.4` (`b384724`). Last local run: 2026-10-31, all green.

## What is tested, and what is not

Only the scripts under `scripts/` have automated tests. The YAML (workflows and actions) is checked by `actionlint` in CI and never executed by this repository; there is no `act` setup and no integration test against AWS or GitHub. That is the design that makes the three layers worth having: any decision worth testing lives in a script (see `architecture.md`).

| Test file | Script under test | Cases |
| --- | --- | --- |
| `tests/check-deployment.test.sh` | `check-deployment.sh` | 4: completed, rolled back, FAILED, IN_PROGRESS (exit 10) |
| `tests/rewrite-task-definition.test.sh` | `rewrite-task-definition.sh` | 7: images replaced, read-only fields stripped, task shape preserved, untouched container, unknown container, malformed pair, `{taskDefinition: ...}` envelope |
| `tests/promotion-plan.test.sh` | `promotion-plan.sh` and `check-image-refs.sh` | 12 |
| `tests/terraform-plan-summary.test.sh` | `terraform-plan-summary.sh` | 14 |
| `tests/terraform-plan-comment.test.sh` | `terraform-plan-comment.sh` | 20, including marker injection keys and a 100 kB log cut to 60000 bytes |
| `tests/upsert-pr-comment.test.sh` | `upsert-pr-comment.sh` | 7, with a fake `gh` |
| `tests/check-no-foreign-identifiers.test.sh` | `check-no-foreign-identifiers.sh` | 12, ending with a scan of the real repository |

## How to run

```bash
bash -c 'for t in tests/*.test.sh; do "$t" || exit 1; done'   # all, as pre-commit does
tests/upsert-pr-comment.test.sh                              # one file
```

Each file prints `ok   - <case>` or `FAIL - <case> (...)` per case and exits non-zero when any case failed. Run them from any directory; each resolves the repository root from `BASH_SOURCE`.

## Conventions

Each test file is self-contained bash with `set -euo pipefail`, a `failures=0` counter, and one tiny helper (`expect_equal description expected actual`, `expect_exit description code fixture`, or `check description command...`). The last line is `[ "$failures" -eq 0 ]` (or `exit "$failures"` in the foreign-identifier test). No test framework (bats, shunit) is used.

Case descriptions are full sentences that state the rule: `"a copied marker in someone else's comment is never edited; a new comment is made"`. Write new ones the same way.

Exit codes are asserted with the `status=0; cmd || status=$?` idiom, so `set -e` does not abort the test.

Fixtures live in `tests/fixtures/` and use the same placeholders as the README (account `123456789012`, `eu-west-1`, `example-*` names, `ordering-agent`/`ordering-mcp` containers). Fixtures model the exact API or tool output the script consumes: `describe-services` JSON, `gh api --paginate` output (one JSON array per page, `pr-comments-two-pages.json`), and Terraform plan logs.

## Mocking

External commands are faked by putting a stub earlier on `PATH`. `tests/upsert-pr-comment.test.sh:21-38` writes a fake `gh` that logs its arguments to `$GH_CALLS` and prints `$GH_COMMENTS` for `api --paginate`; the test asserts the PATCH or POST call line. The foreign-identifier test points the check at a throwaway deny-list through `FOREIGN_IDENTIFIERS_DENYLIST` and builds forbidden values at runtime (`printf '%s%s' 210987 654321`) so the test file itself stays clean.

Temporary files go in `mktemp -d` with a `trap 'rm -rf ...' EXIT`.

## Coverage

There is no coverage tool. In practice every script has a test file and every bug fix in the CHANGELOG arrived with cases that pin it (for example the marker and paging cases in v0.3.4). Inline `run:` logic in actions (tag resolution, `docker load` parsing in `ecr-push-image`, the polling loop in `ecs-deploy`) is not covered by tests.
