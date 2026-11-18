# Coding standards

> Generated 2026-10-31 (INIT) from `v0.3.4` (`b384724`). These are the patterns the code follows consistently; match them.

## Bash scripts (`scripts/*.sh`)

Every script opens with `#!/usr/bin/env bash` and `set -euo pipefail`, is executable, and checks its argument count first. A wrong call prints a `usage:` line to stderr and exits 2 (`scripts/terraform-plan-comment.sh:4-9`, `scripts/upsert-pr-comment.sh:4-9`, `scripts/promotion-plan.sh:4-9`).

Exit codes carry meaning and tests assert them:

| Exit | Meaning |
| --- | --- |
| 0 | success |
| 1 | the input was understood and is invalid or the check failed (`check-image-refs.sh`, `promotion-plan.sh`, `check-deployment.sh`) |
| 2 | misuse: missing arguments, unreadable file, malformed argument (`terraform-plan-summary.sh:16-19`, `rewrite-task-definition.sh:19-21`) |
| 10 | `check-deployment.sh` only: not finished, poll again |

Scripts read files and arguments and write to stdout; they never touch `$GITHUB_OUTPUT` themselves. The action redirects (`"$ACTION_PATH/../../scripts/promotion-plan.sh" ... >> "$GITHUB_OUTPUT"`, `actions/promotion-plan/action.yml:38`). This keeps them runnable from a laptop with a fixture.

JSON is built and parsed with `jq` and `--arg`/`--argjson`, never by string concatenation (`rewrite-task-definition.sh:23`, `upsert-pr-comment.sh:23-24`). Untrusted text is printed with `printf '%s'`, not `echo` (`terraform-plan-comment.sh:27-29`); the test `a title that looks like an option is printed as text` holds this in place.

Variables are lower_snake_case locals (`plan_log`, `comment_key`, `max_log_bytes`). Constants that explain a rule get a name instead of a comment (`no_op_plan_line`, `required_fields`). There are no explanatory comments in scripts; the one `# shellcheck disable=SC2016` in `tests/terraform-plan-comment.test.sh:2` is a linter directive.

## Composite actions (`actions/*/action.yml`)

- Every input has a `description`. Booleans are strings, `"true"` or `"false"`, compared with `inputs.x == 'true'`.
- Every `${{ }}` value that reaches shell goes through `env:` and is quoted as `"$VAR"` in `run:`. No step interpolates `${{ inputs.* }}` directly into a `run:` script.
- Every `run:` step in an action declares `shell: bash` (composite actions require it). Steps that chain AWS, Docker or Terraform commands start with `set -euo pipefail` (`ecs-deploy`, `ecr-push-image`, `promotion-plan`, the plan and summary steps of `terraform-plan`); short guard steps such as `Require an apply role` do not.
- Scripts are called as `"$ACTION_PATH/../../scripts/<name>.sh"` with `ACTION_PATH: ${{ github.action_path }}` in `env:`.
- Outputs are written as `key=value` lines to `"$GITHUB_OUTPUT"`, grouped in a `{ ... } >> "$GITHUB_OUTPUT"` block when there are several.
- Terraform steps set `TF_IN_AUTOMATION: "true"` and `TF_INPUT: "false"` and pass `-no-color`.
- Errors meant for the run page use `echo "::error::..."`; `::warning::` for a missing optional secret.

## Reusable workflows (`.github/workflows/*.yml`)

- Top-level `permissions:` is the minimum, and jobs widen it only where needed (`terraform.yml:54-55` then `:101-104`).
- `actions/checkout` always has `persist-credentials: false`.
- Inputs use `type: boolean`/`number` in workflows (unlike actions), converted back to strings when passed down (`refresh: ${{ inputs.plan-refresh && 'true' || 'false' }}`, `terraform.yml:119`).
- Matrix inputs are JSON strings decoded with `fromJSON(inputs.images)`; optional matrix fields get defaults inline (`${{ matrix.image.context || '.' }}`).
- Third-party actions are pinned to a 40-character SHA with `# vX.Y.Z` after it. This repository's own actions are also pinned by SHA (see `security.md`).
- Job names read as sentences with the subject: `Build ${{ matrix.image.name }}`, `Deploy to ${{ ... }}`.

## Tests (`tests/*.test.sh`)

See `testing.md`. The style: a `failures=0` counter, a small `expect_equal`/`expect_exit`/`check` helper printing `ok   - ...` or `FAIL - ...`, and `[ "$failures" -eq 0 ]` as the last line.

## Prose: README and CHANGELOG

Plain declarative sentences; British/Irish spelling (`serialised`, `artefacts`, `organisation`, `stabilise`). CHANGELOG follows Keep a Changelog with `Added`, `Changed`, `Fixed`, `Security` and, where callers must act, `Migration from vX` (`CHANGELOG.md:87-91`). Placeholders only: account `123456789012`, region `eu-west-1`, names prefixed `example`.

## Commits

Conventional Commits with a scope where it narrows things: `feat(terraform-plan): ...`, `fix: ...`, `docs: ...`, `chore: release vX.Y.Z, <what it means for callers>`. Subjects are lower case and describe the effect.
