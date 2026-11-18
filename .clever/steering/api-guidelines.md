# Public interface

> Generated 2026-10-31 (INIT) from `v0.3.4` (`b384724`). The YAML files are the source of truth; README tables mirror them.

There is no HTTP API. The public interface is the `inputs`, `secrets` and `outputs` of the three reusable workflows and seven composite actions, plus the paths callers put in `uses:`. Anything a caller can name is a contract.

## Reusable workflows

### `ecs-service-deploy.yml`

| Input | Type | Required / default |
| --- | --- | --- |
| `environment` | string | required |
| `aws-region` | string | required |
| `role-to-assume` | string | required |
| `images` | string (JSON array) | required |
| `cluster`, `service`, `task-definition-family` | string | required |
| `wait-for-stability` | boolean | `true` |
| `timeout-minutes` | number | `15` |
| `slack-notify` | boolean | `false` |

Secret: `SLACK_WEBHOOK_URL`, optional. No workflow-level `outputs`.

### `ecs-promote.yml`

| Input | Type | Required / default |
| --- | --- | --- |
| `aws-region` | string | required (default for environments without their own) |
| `images` | string (JSON array) | required |
| `environments` | string (JSON array, 1 to 3) | required; items need `name`, `role-to-assume`, `cluster`, `service`, `task-definition-family`; optional `aws-region`; names unique |
| `promote` | boolean | `true` |
| `scan-severity` | string | `HIGH,CRITICAL` |
| `scan-ignore-unfixed` | boolean | `true` |
| `scan-ignore-file` | string | `""` |
| `wait-for-stability` | boolean | `true` |
| `timeout-minutes` | number | `15` |
| `slack-notify` | boolean | `false` |

Secret: `SLACK_WEBHOOK_URL`, optional. No workflow-level `outputs`.

### `terraform.yml`

| Input | Type | Required / default |
| --- | --- | --- |
| `working-directory` | string | `.` |
| `roots` | string (one per line) | required |
| `terraform-version` | string | required |
| `aws-region` | string | required |
| `plan-role-to-assume` | string | required |
| `apply-role-to-assume` | string | `""`; must be set when `apply` is true |
| `apply` | boolean | `false` |
| `environment` | string | `""` |
| `checkov`, `tflint` | boolean | `true` |
| `checkov-version` | string | `3.3.29` |
| `plan` | boolean | `true` |
| `plan-refresh` | boolean | `true` |

No secrets, no outputs. Callers must grant `id-token: write`, `contents: read`, `pull-requests: write` on every calling job (see `security.md`).

## Composite actions

All action inputs are strings; booleans are `"true"`/`"false"`.

| Action | Inputs (required in bold) | Outputs |
| --- | --- | --- |
| `ecr-build-push` | **`ecr-repository`**; `aws-region`, `role-to-assume` (needed when `push` is `"true"`), `context` `.`, `dockerfile` `Dockerfile`, `platforms` `linux/amd64`, `build-args`, `image-tag` (commit SHA), `push` `"true"`, `output-path` `image.tar` | `image-uri` (`registry/repo@sha256:...`), `image-tag`, `image-digest` (empty when not pushed), `image-path` |
| `ecr-push-image` | **`aws-region`**, **`role-to-assume`**, **`ecr-repository`**, **`image-path`**; `image-tag` | `image-uri`, `image-digest`, `image-tag` |
| `ecs-deploy` | **`aws-region`**, **`role-to-assume`**, **`cluster`**, **`service`**, **`task-definition-family`**, **`container-images`**; `wait-for-stability` `"true"`, `timeout-minutes` `"15"`, `require-digest` `"false"` | `task-definition-arn` |
| `promotion-plan` | **`environments`**, **`default-aws-region`** | `count`, `env-1`, `env-2`, `env-3` |
| `terraform-gate` | **`roots`**, **`terraform-version`**; `working-directory` `.`, `tflint` `"true"`, `checkov` `"true"`, `checkov-version` `3.3.29` | none |
| `terraform-plan` | **`working-directory`**, **`terraform-version`**, **`aws-region`**, **`role-to-assume`**; `lock` `"false"`, `refresh` `"true"`, `comment-on-pull-request` `"true"`, `comment-key` (working-directory), `comment-author` `github-actions[bot]`, `title` `Terraform plan`, `github-token` (`github.token`) | `result`, `summary` |
| `terraform-apply` | **`working-directory`**, **`terraform-version`**, **`aws-region`**, **`role-to-assume`** | none |

`terraform-gate` does not check out the repository; the caller must (`actions/terraform-gate/action.yml:2`). `ecr-build-push` reads `output-path` literally for `image-path`, even when pushing.

## Naming

Inputs and outputs are kebab-case. AWS-facing names repeat the AWS term (`role-to-assume`, `task-definition-family`, `ecr-repository`). The same concept keeps the same name across actions and workflows (`aws-region`, `role-to-assume`, `timeout-minutes`, `wait-for-stability`). The one secret is UPPER_SNAKE_CASE.

## Validation and errors

Invalid input fails early with a `::error::` line or a script message on stderr, before any AWS change where possible: empty `roots` (`terraform.yml:71-75`), missing apply role (`terraform.yml:140-143`), malformed `environments` (`scripts/promotion-plan.sh:15-27`), non-digest images under `require-digest` (`scripts/check-image-refs.sh`), unknown container names (`scripts/rewrite-task-definition.sh:28-29`), unsafe `comment-key` (`scripts/terraform-plan-comment.sh:17-20`).

## Versioning and compatibility, as practised

The repository follows SemVer (`CHANGELOG.md:3`) and is pre-1.0. The history shows these rules in use:

- A new reusable workflow or set of actions has been a minor bump: v0.2.0 added `ecs-promote.yml`; v0.3.0 added the Terraform set.
- New optional inputs with defaults that keep old behaviour have been patch bumps: v0.3.3 (`refresh`, `plan-refresh`), v0.3.4 (`comment-key`, `comment-author`).
- Changing an input from required to optional is treated as compatible (v0.2.0 made `aws-region` and `role-to-assume` optional on `ecr-build-push`).
- A changed argument list of an internal script is listed under `Changed` without a major bump (`terraform-plan-comment.sh` gained a required fourth argument in v0.3.4), because scripts are not part of the public interface; only the actions call them.
- Each release whose callers must act gets a `Migration from vX` section (`CHANGELOG.md:87-91`). Releases that need no caller action say "No functional change" or describe the default-preserving behaviour.
- No input, output or secret has been removed or renamed in any release so far. There is no precedent for how such a breaking change would be versioned.
- Internal `uses:` refs move with each release (`@v0.1.0` → `@v0.2.0` → `@v0.3.0` → commit SHAs since v0.3.1).

Callers pin by full SHA with a `# vX.Y.Z` comment (the one workspace caller) or by tag (the README and examples, `@v0.3.4`).
