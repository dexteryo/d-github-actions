# Changelog

All notable changes to this repository are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses [Semantic Versioning](https://semver.org/).

## [0.3.4] - 2026-10-25

### Fixed

- `actions/terraform-plan`: two plans on one pull request no longer overwrite each other's comment. The comment step edited the last comment of the token's user (`gh pr comment --edit-last`), so a caller that plans two roots, two jobs with the same bot, kept only the plan that finished last. Each comment now ends in a hidden marker, `<!-- d-github-actions:terraform-plan:<key> -->`, and a later plan edits the newest comment by `comment-author` that carries its key, or creates one. A comment by anyone else that copies the marker is never edited.

### Added

- `actions/terraform-plan`: inputs `comment-key` (default: `working-directory`) and `comment-author` (default: `github-actions[bot]`).
- `scripts/upsert-pr-comment.sh` with `tests/upsert-pr-comment.test.sh` and fixtures; CI runs it.

### Changed

- `scripts/terraform-plan-comment.sh` takes the comment key as a fourth, required argument and refuses a key outside letters, digits, `.`, `_`, `/` and `-`, so it cannot close the marker.
- `.github/workflows/terraform.yml` calls `actions/terraform-plan` at `23ee8dd` and titles each comment `Terraform plan: <root>`. The other actions stay at `95c26ea`. The README and the examples refer to `v0.3.4`.

## [0.3.3] - 2026-10-24

### Added

- `actions/terraform-plan`: a `refresh` input, default `"true"`, passed to `terraform plan -refresh`.
- `.github/workflows/terraform.yml`: a `plan-refresh` input, default `true`. Callers set it to `false` on pull requests so a plan role without `secretsmanager:GetSecretValue` can still plan a configuration that manages secret versions. The README explains the trade-off.

### Changed

- The workflow calls `actions/terraform-plan` at `277aa2f`, the commit that adds `refresh`. The other actions stay at `95c26ea`. The README and the examples refer to `v0.3.3`.

## [0.3.2] - 2026-10-24

### Fixed

- The Terraform caller example and the README gave the apply job, and the "gate alone" example, fewer permissions than the reusable workflow's `plan` job asks for. GitHub checks all jobs of a called workflow against the calling job, so such a caller ended in `startup_failure` with no logs. Both now grant `id-token`, `contents` and `pull-requests`, and the README explains why.
- The README's release-tag note described the old `@v0.3.0` action references.

## [0.3.1] - 2026-10-24

### Security

- The reusable workflows call their own actions by full commit hash (`95c26ea`, whose `actions/` and `scripts/` are identical to v0.3.0) instead of the `v0.3.0` tag. A moved tag can no longer change the code that runs with a caller's deploy or apply role.

### Changed

- The README and the examples refer to `v0.3.1`. No functional change.

## [0.3.0] - 2026-10-24

### Added

- `actions/terraform-gate`: `terraform fmt`, `terraform validate` per root module, tflint and checkov.
- `actions/terraform-plan`: plan with `-detailed-exitcode`, job summary and a pull request comment edited in place; outputs `result` and `summary`.
- `actions/terraform-apply`: plan and apply in one job; it does not apply the plan a pull request showed.
- `.github/workflows/terraform.yml`: reusable gate, plan and apply workflow. It called the actions at `@v0.3.0`; 0.3.1 pins them by commit hash.
- `scripts/terraform-plan-summary.sh`, `scripts/terraform-plan-comment.sh` with fixture tests.
- `examples/caller-terraform.yml`.

### Changed

- The ECS workflows, examples and README refer to the actions at `v0.3.0` (was `v0.2.1`). No functional change.

## [0.2.1] - 2026-10-23

Repository renamed; references updated; no functional change.

## [0.2.0] - 2026-10-23

### Added

- `.github/workflows/ecs-promote.yml`: build once, scan with Trivy, push by digest, deploy to up to three ordered environments; later environments are gated by GitHub environment protection rules and receive the same digest.
- `actions/ecr-push-image`: push an image archive to ECR and output the digest.
- `actions/promotion-plan`: validates the ordered `environments` input.
- `actions/ecr-build-push`: inputs `push` and `output-path` (build an archive without AWS access), outputs `image-digest` and `image-path`.
- `actions/ecs-deploy`: input `require-digest`.
- `scripts/promotion-plan.sh`, `scripts/check-image-refs.sh` with fixture tests.
- `scripts/check-no-foreign-identifiers.sh`, its hashed deny-list and test; wired into CI and pre-commit.
- `.pre-commit-config.yaml`, `examples/caller-promote.yml`.

### Changed

- Internal references use `@v0.2.0`.
- `actions/ecr-build-push`: `aws-region` and `role-to-assume` are optional because they are only needed when `push` is `"true"`.
- README documents the promotion flow, the deploy gate, per-environment OIDC roles and the reference patterns that were not carried over.

### Migration from v0.1.0

- No change is needed for callers of `ecs-service-deploy.yml`, `ecr-build-push` or `ecs-deploy`: every input, secret and output is unchanged; only the `@v0.1.0` refs move to `@v0.2.0`.
- To promote through several environments, switch to `ecs-promote.yml` (see `examples/caller-promote.yml`). Create one GitHub environment per entry, add required reviewers to all but the first, and one IAM role per environment (`modules/ci-oidc-role` in `d-tf-modules`, trust scoped to repository and environment).
- The first environment's role must be allowed to push to the ECR repositories.

## [0.1.0] - 2026-10-23

### Added

- `actions/ecr-build-push`, `actions/ecs-deploy` and the reusable `ecs-service-deploy.yml` workflow using GitHub OIDC.
- `scripts/rewrite-task-definition.sh` and `scripts/check-deployment.sh` with fixture tests.
