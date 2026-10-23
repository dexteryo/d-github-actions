# dex-github-actions

Reusable GitHub Actions for building container images and deploying them to Amazon ECS (Fargate) with GitHub OIDC. No static AWS keys, ever.

This repository is public. It contains no account identifiers, hostnames or secrets; every example uses placeholders such as `123456789012`.

## Contents

| Path | Purpose |
| --- | --- |
| `actions/ecr-build-push` | Composite action: OIDC login, Buildx build, push to ECR, output `repo@digest` |
| `actions/ecr-push-image` | Composite action: load an image archive and push it to ECR, output `repo@digest` |
| `actions/ecs-deploy` | Composite action: new task definition revision with swapped images, service update, wait; optional `require-digest` |
| `actions/promotion-plan` | Composite action: validates the ordered `environments` list of a promotion |
| `.github/workflows/ecs-service-deploy.yml` | Reusable workflow: build N images in parallel, then deploy to one environment, optional Slack |
| `.github/workflows/ecs-promote.yml` | Reusable workflow: build once, scan, push by digest, deploy to up to three environments in order |
| `scripts/rewrite-task-definition.sh` | The `jq` rewrite used by `ecs-deploy` (testable locally) |
| `scripts/promotion-plan.sh`, `scripts/check-image-refs.sh` | Validation of the environment list and of digest-only image references |
| `scripts/check-no-foreign-identifiers.sh` | Fails on a hashed deny-list of foreign identifiers and on 12-digit numbers other than `123456789012` |
| `scripts/check-deployment.sh` | Decides from `describe-services` JSON whether the new revision rolled out (0 done, 10 keep polling, 1 failed) |
| `examples/caller.yml` | Copy-paste caller workflow |
| `tests/` | Bash tests and fixtures |

## Quick start

1. Create an IAM role that trusts GitHub OIDC for your repository and environment. Grant it ECR push on the repositories, and `ecs:DescribeTaskDefinition`, `ecs:RegisterTaskDefinition`, `ecs:UpdateService`, `ecs:DescribeServices` plus `iam:PassRole` on the task and execution roles only.
2. Create a GitHub environment (for example `integration`) and add required reviewers if you want an approval gate.
3. Copy `examples/caller.yml` into your repository's `.github/workflows/` and replace the placeholders.

The caller workflow must grant `id-token: write` and `contents: read`.

## Reusable workflow inputs

| Input | Required | Description |
| --- | --- | --- |
| `environment` | yes | GitHub environment used by both jobs (approvals, scoped variables) |
| `aws-region` | yes | AWS region |
| `role-to-assume` | yes | OIDC role ARN |
| `images` | yes | JSON array of images. Each item: `name` (must equal the container name in the task definition), `ecr-repository`, optional `dockerfile`, `context`, `platforms`, `build-args` |
| `cluster`, `service`, `task-definition-family` | yes | ECS target |
| `wait-for-stability` | no | Default `true` |
| `timeout-minutes` | no | Default `15` |
| `slack-notify` | no | Default `false`; needs the `SLACK_WEBHOOK_URL` secret |

Deploys are serialised per service and environment with a `concurrency` group, and are never cancelled mid-flight.

Slack posting uses an incoming webhook through `curl`; there is no third-party action and no organisation secret is assumed. Pass your own webhook as `SLACK_WEBHOOK_URL`.

## Promotion workflow

`ecs-service-deploy.yml` builds and deploys to one environment. `ecs-promote.yml` follows the stage layout of a staged pipeline: build once, scan, push by digest, deploy to a first environment, then promote the same digest.

```text
plan -> build (archive, no push) -> scan (Trivy, HIGH/CRITICAL fail)
     -> push (first environment's role; digest fixed here)
     -> deploy-1 (automatic)
     -> deploy-2 (gate: environment protection rules) -> deploy-3 (gate)
```

Nothing is rebuilt after `push`. Each deploy job downloads the same `image-ref-*` artefacts (`name=registry/repository@sha256:...`) and `ecs-deploy` runs with `require-digest: "true"`, so a tag reference fails the deploy.

| Input | Required | Description |
| --- | --- | --- |
| `aws-region` | yes | Default region; an environment can set its own `aws-region` |
| `images` | yes | Same shape as in `ecs-service-deploy.yml` |
| `environments` | yes | JSON array of 1 to 3 items in promotion order: `name`, `role-to-assume`, `cluster`, `service`, `task-definition-family`, optional `aws-region` |
| `promote` | no | Default `true`. Set `false` to stop after the first environment |
| `scan-severity` | no | Default `HIGH,CRITICAL` |
| `scan-ignore-unfixed` | no | Default `true` |
| `scan-ignore-file` | no | Path of a reviewed Trivy ignore file in the caller repository; changes go through code review |
| `wait-for-stability`, `timeout-minutes`, `slack-notify` | no | As in `ecs-service-deploy.yml` |

### The deploy gate

The gate is the GitHub environment, not workflow logic. Create one environment per entry of `environments`:

- first environment: no required reviewers, so the push and the first deploy run automatically;
- later environments: required reviewers, optionally a wait timer and a branch restriction to `main`.

The `push` job runs in the first environment, because the first environment's role is the one allowed to push. Do not put required reviewers on it.

### Roles per environment

Each environment has its own IAM role. The GitHub OIDC trust policy of the role is scoped to the repository and the environment through the `sub` claim, `repo:<owner>/<repo>:environment:<name>`, so a job that does not run in that environment cannot assume the role. Create the roles with `modules/ci-oidc-role` of `dex-tf-modules`. The role needs ECR push on the repositories (first environment) and the ECS permissions listed in the quick start.

## Reference pipeline patterns

Carried over: stage order (build, scan, push, deploy), build once and promote by digest, short-lived role assumption through an OIDC ID token (no stored keys), a vulnerability gate on image scans with a severity threshold, separate roles per environment, a deploy gate before the later environments, serialised deploys per ref.

Deliberately not carried over: change-ticket automation, per-branch and protected-branch role profile files (a role per environment replaces them), Docker-in-Docker, language-specific test stages (callers run those in their own workflows), CodeDeploy blue/green (ECS rolling deploys with the circuit breaker are used), outbound proxy settings, vulnerability suppress lists passed as environment variables (a reviewed ignore file is used instead), repository creation from the pipeline (Terraform creates repositories through `modules/ecr`).

## Using the actions directly

```yaml
- uses: dexteryo/dex-github-actions/actions/ecr-build-push@v0.2.0
  id: build
  with:
    aws-region: eu-west-1
    role-to-assume: arn:aws:iam::123456789012:role/example-github-deploy
    ecr-repository: example/app

- uses: dexteryo/dex-github-actions/actions/ecs-deploy@v0.2.0
  with:
    aws-region: eu-west-1
    role-to-assume: arn:aws:iam::123456789012:role/example-github-deploy
    cluster: example-integration
    service: example-app
    task-definition-family: example-app
    container-images: |
      app=${{ steps.build.outputs.image-uri }}
```

Pin `@main` to a tag or full commit SHA once you cut a release.

### How the deploy works

Terraform owns the shape of the task (CPU, roles, secrets, ports). `ecs-deploy` downloads the latest revision of the family, removes read-only fields (`taskDefinitionArn`, `revision`, `status`, `requiresAttributes`, `compatibilities`, `registeredAt`, `registeredBy`), replaces the `image` of each named container, registers the result and points the service at it. A name that does not exist in the task definition fails the deploy. After registering, the action polls the service every 15 seconds until the PRIMARY deployment is the new task definition revision and its `rolloutState` is `COMPLETED`. If the ECS deployment circuit breaker rolls back (the PRIMARY deployment returns to an older revision, or `rolloutState` is `FAILED`), the job fails and the last ten service events are printed; a rollback is never reported as success. The wait is bounded by `timeout-minutes` (default 15, no 10 minute AWS waiter cap); on timeout the job fails and prints the same events.

Images are referenced by digest, so a rollback is deterministic.

## Development

```
brew install actionlint shellcheck jq
actionlint
shellcheck scripts/*.sh tests/*.sh
for test in tests/*.test.sh; do "$test"; done
scripts/check-no-foreign-identifiers.sh --git
```

`pre-commit install` runs the same checks. `scripts/foreign-identifiers.sha256` holds SHA-256 digests of lower-case tokens, so the deny-list does not reveal what it denies; the check also rejects 12-digit numbers other than `123456789012` and email addresses outside placeholder domains.

All third-party actions are pinned to full commit SHAs with the version in a trailing comment.
