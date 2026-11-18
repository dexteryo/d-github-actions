# Product

> Generated 2026-10-31 (INIT) from the repository at `v0.3.4` (`b384724`). Code wins over this file.

## What it is

`d-github-actions` is a public library of reusable GitHub Actions workflows and composite actions. It lets another repository build container images, push them to Amazon ECR, deploy them to Amazon ECS (Fargate), and gate, plan and apply Terraform, all by assuming AWS roles through GitHub OIDC instead of storing AWS keys (`README.md:3`).

The repository holds no product code of its own. Its "users" are other repositories' workflow files, which call it with `uses: dexteryo/d-github-actions/...@<ref>`.

The README states the public-repository rule outright: no account identifiers, hostnames or secrets, and every example uses placeholders such as `123456789012` (`README.md:5`). A guard script enforces it (see `security.md`).

## Capabilities

| Capability | Entry point | Since |
| --- | --- | --- |
| Build N images in parallel and deploy them to one ECS environment, optional Slack notice | `.github/workflows/ecs-service-deploy.yml` | v0.1.0 |
| Build once, scan with Trivy, push by digest, deploy the same digest to up to three ordered environments | `.github/workflows/ecs-promote.yml` | v0.2.0 |
| Terraform gate (fmt, validate, tflint, checkov), then a read-only plan with a pull request comment, or an apply behind an optional GitHub environment approval | `.github/workflows/terraform.yml` | v0.3.0 |
| The same steps as standalone composite actions | `actions/*/action.yml` | per action, see `CHANGELOG.md` |

## Who uses it

Verified callers found in the hub workspace on 2026-10-31:

| Caller file | Workflow called | Pinned to |
| --- | --- | --- |
| `workspace/finn-app-brazil/.github/workflows/infra.yml:25,42` | `terraform.yml` (plan job and apply job) | commit `681de421…` with a `# v0.3.3` comment |

No caller of `ecs-service-deploy.yml` or `ecs-promote.yml` was found in the workspace. `workspace/d-tf-modules` documents itself as the companion repository: `modules/ci-oidc-role` produces the `role_arn` that callers pass as `role-to-assume` (`d-tf-modules/modules/ci-oidc-role/README.md:41`), and `modules/ecs-service` leaves `task_definition` to the `ecs-deploy` action (`d-tf-modules/modules/ecs-service/README.md:5`). Repositories that are not checked out in the workspace may also call this one; absence here is not evidence of absence.

`d-github-actions` has no entry in the hub's `system-index.yml` as of this date.

## Business rules the code enforces

- An image is deployed by digest when promoted. `ecs-promote.yml` passes `require-digest: "true"` to every deploy, and `scripts/check-image-refs.sh` rejects any `name=uri` line that is not `registry/repo@sha256:<64 hex>`.
- Nothing is rebuilt after the push in a promotion: later environments download the same `image-ref-*` artefacts (`ecs-promote.yml:186-211`).
- A rollback by the ECS circuit breaker is a failure, never a success (`scripts/check-deployment.sh:22-31`).
- Terraform's shape of the task (CPU, roles, secrets, ports) is never changed by a deploy; only the `image` of the named containers is replaced (`scripts/rewrite-task-definition.sh:26-36`).
- The workflow's plan job never takes the state lock (`terraform.yml:118`, `lock: "false"`), and an apply re-plans and applies in the same job rather than applying the plan the pull request showed (`README.md:139-143`).
- The approval gate for later environments and for apply is the GitHub environment's protection rules, not workflow logic (`README.md:79-86`).

## Not provided

The README lists what was deliberately left out (`README.md:196`): change-ticket automation, CodeDeploy blue/green, Docker-in-Docker, language-specific test stages, ECR repository creation. It also says an approval-gated apply of a saved, reviewed plan file "is not provided yet" (`README.md:143`).
