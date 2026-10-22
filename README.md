# dex-github-actions

Reusable GitHub Actions for building container images and deploying them to Amazon ECS (Fargate) with GitHub OIDC. No static AWS keys, ever.

This repository is public. It contains no account identifiers, hostnames or secrets; every example uses placeholders such as `123456789012`.

## Contents

| Path | Purpose |
| --- | --- |
| `actions/ecr-build-push` | Composite action: OIDC login, Buildx build, push to ECR, output `repo@digest` |
| `actions/ecs-deploy` | Composite action: new task definition revision with swapped images, service update, wait |
| `.github/workflows/ecs-service-deploy.yml` | Reusable workflow: build N images in parallel, then deploy, optional Slack |
| `scripts/rewrite-task-definition.sh` | The `jq` rewrite used by `ecs-deploy` (testable locally) |
| `scripts/check-deployment.sh` | Decides from `describe-services` JSON whether the new revision rolled out (0 done, 10 keep polling, 1 failed) |
| `examples/caller.yml` | Copy-paste caller workflow |
| `tests/` | Bash test and fixture for the rewrite |

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

## Using the actions directly

```yaml
- uses: dexteryo/dex-github-actions/actions/ecr-build-push@v0.1.0
  id: build
  with:
    aws-region: eu-west-1
    role-to-assume: arn:aws:iam::123456789012:role/example-github-deploy
    ecr-repository: example/app

- uses: dexteryo/dex-github-actions/actions/ecs-deploy@v0.1.0
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
tests/rewrite-task-definition.test.sh
tests/check-deployment.test.sh
```

All third-party actions are pinned to full commit SHAs with the version in a trailing comment.
