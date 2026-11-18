# Tech

> Generated 2026-10-31 (INIT) from `v0.3.4` (`b384724`). Code wins over this file.

## Languages

| Language | Where | Notes |
| --- | --- | --- |
| GitHub Actions YAML | `.github/workflows/*.yml`, `actions/*/action.yml`, `examples/*.yml` | Reusable workflows use `on: workflow_call`; actions use `runs: using: composite`. No JavaScript or Docker actions. |
| Bash | `scripts/*.sh`, `tests/*.test.sh`, inline `run:` steps | Every script starts `#!/usr/bin/env bash` and `set -euo pipefail`. |
| jq | Inside scripts | All JSON shaping and validation (`rewrite-task-definition.sh`, `promotion-plan.sh`, `check-deployment.sh`, `upsert-pr-comment.sh`). |
| Python 3 | Embedded heredoc in `scripts/check-no-foreign-identifiers.sh:29-97` | Run as `python3 -I -c`; standard library only (`hashlib`, `os`, `re`, `sys`). |

There is no package manifest, lockfile, Makefile or build step. Nothing is compiled.

## Third-party actions (pinned by full SHA, version in a trailing comment)

| Action | Version comment | Used in |
| --- | --- | --- |
| `actions/checkout` | v7.0.1 | all three reusable workflows, `ci.yml` |
| `actions/upload-artifact` | v7.0.2 | `ecs-service-deploy.yml`, `ecs-promote.yml` |
| `actions/download-artifact` | v8.0.2 | `ecs-service-deploy.yml`, `ecs-promote.yml` |
| `aws-actions/configure-aws-credentials` | v6.3.0 | `ecr-build-push`, `ecr-push-image`, `ecs-deploy`, `terraform-plan`, `terraform-apply` |
| `aws-actions/amazon-ecr-login` | v2.1.7 | `ecr-build-push`, `ecr-push-image` |
| `docker/setup-buildx-action` | v4.4.1 | `ecr-build-push` |
| `docker/build-push-action` | v7.4.0 | `ecr-build-push` |
| `aquasecurity/trivy-action` | v0.36.0 | `ecs-promote.yml` scan job |
| `hashicorp/setup-terraform` | v4.0.1 (`terraform_wrapper: false`) | `terraform-gate`, `terraform-plan`, `terraform-apply` |
| `terraform-linters/setup-tflint` | v6.3.2 | `terraform-gate` |

## Tools invoked at runtime on the runner

| Tool | How it arrives | Where |
| --- | --- | --- |
| AWS CLI (`aws ecs ...`) | Preinstalled on `ubuntu-latest` | `actions/ecs-deploy/action.yml:70-104` |
| Docker / Buildx | Preinstalled, Buildx set up by action | `ecr-build-push`, `ecr-push-image` |
| `gh` CLI | Preinstalled on `ubuntu-latest` | `scripts/upsert-pr-comment.sh` |
| `jq`, `curl` | Preinstalled | scripts; Slack notify steps |
| Terraform | `setup-terraform`, version from the caller's `terraform-version` input | Terraform actions |
| checkov | `pip install checkov==<checkov-version>`, default `3.3.29` | `actions/terraform-gate/action.yml:71` |
| tflint | `setup-tflint`, then `tflint --init` | `terraform-gate` |
| actionlint | CI downloads v1.7.12 by script | `ci.yml:20` |
| shellcheck | Preinstalled on the CI runner | `ci.yml:22` |

All jobs run on `runs-on: ubuntu-latest`. Inline steps use bash 4 features (`mapfile` in `actions/ecs-deploy/action.yml:71`), which is fine there; the scripts under `scripts/` and the tests also ran green under macOS `/bin/bash` 3.2.57 on 2026-10-31.

## Infrastructure touched (caller-owned)

AWS only: IAM roles assumed through GitHub OIDC, ECR repositories, ECS clusters/services/task definitions, and whatever the caller's Terraform manages. This repository creates none of it. The README points callers to `modules/ci-oidc-role`, `modules/ecr` and `modules/ecs-service` in `d-tf-modules` (`README.md:90`, `README.md:186`, `README.md:196`).

Slack is reached through an incoming webhook with `curl` (`ecs-service-deploy.yml:157`), not a third-party action.

## Not applicable

No database, cache, message broker or application runtime. GitHub Actions cache is used only as the Buildx layer cache (`cache-from/to: type=gha,scope=<ecr-repository>`, `actions/ecr-build-push/action.yml:96-97`).
