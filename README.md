# d-github-actions

Reusable GitHub Actions and workflows for building container images, deploying them to Amazon ECS (Fargate) and checking, planning and applying Terraform, all with GitHub OIDC. No static AWS keys, ever.

This repository is public. It contains no account identifiers, hostnames or secrets; every example uses placeholders such as `123456789012`.

## Contents

| Path | Purpose |
| --- | --- |
| `actions/ecr-build-push` | Composite action: OIDC login, Buildx build, push to ECR, output `repo@digest` |
| `actions/ecr-push-image` | Composite action: load an image archive and push it to ECR, output `repo@digest` |
| `actions/ecs-deploy` | Composite action: new task definition revision with swapped images, service update, wait; optional `require-digest` |
| `actions/promotion-plan` | Composite action: validates the ordered `environments` list of a promotion |
| `actions/terraform-gate` | Composite action: `terraform fmt`, `terraform validate` per root module, tflint, checkov |
| `actions/terraform-plan` | Composite action: OIDC login, `terraform plan`, summary, one pull request comment per root module, edited in place |
| `actions/terraform-apply` | Composite action: OIDC login, plan, apply the saved plan |
| `.github/workflows/ecs-service-deploy.yml` | Reusable workflow: build N images in parallel, then deploy to one environment, optional Slack |
| `.github/workflows/ecs-promote.yml` | Reusable workflow: build once, scan, push by digest, deploy to up to three environments in order |
| `.github/workflows/terraform.yml` | Reusable workflow: gate, then plan (read-only) or apply (write role, optional environment approval) |
| `scripts/rewrite-task-definition.sh` | The `jq` rewrite used by `ecs-deploy` (testable locally) |
| `scripts/promotion-plan.sh`, `scripts/check-image-refs.sh` | Validation of the environment list and of digest-only image references |
| `scripts/check-no-foreign-identifiers.sh` | Fails on a hashed deny-list of foreign identifiers and on 12-digit numbers other than `123456789012` |
| `scripts/check-deployment.sh` | Decides from `describe-services` JSON whether the new revision rolled out (0 done, 10 keep polling, 1 failed) |
| `scripts/terraform-plan-summary.sh`, `scripts/terraform-plan-comment.sh`, `scripts/upsert-pr-comment.sh` | One-line plan summary from the exit code and log; markdown body of the pull request comment, ending in a hidden marker; edit the comment that carries the marker, or create it |
| `examples/caller.yml` | Copy-paste caller workflow |
| `examples/caller-terraform.yml` | Copy-paste caller for the Terraform workflow |
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

Each environment has its own IAM role. The GitHub OIDC trust policy of the role is scoped to the repository and the environment through the `sub` claim, `repo:<owner>/<repo>:environment:<name>`, so a job that does not run in that environment cannot assume the role. Create the roles with `modules/ci-oidc-role` of `d-tf-modules`. The role needs ECR push on the repositories (first environment) and the ECS permissions listed in the quick start.

## Terraform

`terraform.yml` replaces a long inline `infra.yml`. It has three jobs.

- `gate` always runs: `terraform fmt -check -recursive`, `terraform validate` in every root module (after `init -backend=false`), `tflint --init && tflint --recursive`, and `checkov -d .` with a pinned version.
- `plan` runs when `apply` is `false` and `plan` is `true`. It assumes the plan role, runs `terraform init`, then `terraform plan -no-color -lock=false -refresh=<plan-refresh> -detailed-exitcode -out=tfplan`. The summary (`No changes.`, `Plan: N to add...`, `Changes to outputs only.` or `Plan failed (exit N).`) goes to the job summary and to a pull request comment titled after the root module. Each comment ends in a hidden marker, `<!-- d-github-actions:terraform-plan:<root> -->`; a later plan of the same root edits the newest comment by `github-actions[bot]` that carries its marker, so several plans on one pull request (one call per root) each keep their own comment. A comment by anyone else that copies the marker is never edited. The job fails only when the plan itself failed.
- `apply` runs when `apply` is `true`, after `gate`, in the GitHub `environment` you name, so required reviewers can approve it. It assumes the apply role, plans, and applies that saved plan. It fails at once when `apply-role-to-assume` is empty.

`plan` and `apply` work in the first entry of `roots`; the gate validates all of them. A caller with several environments calls the workflow once per root, one job per environment, each listing its own root first.

The plan and apply jobs each have a concurrency group made of the job kind, the first root (with `working-directory`) and the ref. A newer plan for the same root and ref cancels an older one; applies for the same root queue behind each other and are never cancelled, so merging a pull request while an apply runs does not interrupt it. Two calls in one run that list different roots first have different groups and never cancel each other.

| Input | Required | Description |
| --- | --- | --- |
| `working-directory` | no | Default `.` |
| `roots` | yes | Root module directories, one per line, relative to `working-directory`. The gate validates all of them; plan and apply use the first |
| `terraform-version` | yes | Terraform version to install |
| `aws-region` | yes | AWS region |
| `plan-role-to-assume` | yes | Read-only role for plans |
| `apply-role-to-assume` | no | Write role; required when `apply` is `true` |
| `apply` | no | Default `false`; `true` runs the apply job instead of the plan job |
| `environment` | no | GitHub environment of the apply job |
| `checkov`, `tflint` | no | Default `true` |
| `checkov-version` | no | Default `3.3.29` |
| `plan` | no | Default `true`; set `false` to run only the gate |
| `plan-refresh` | no | Default `true`; `false` plans without refreshing the state, see below |

### Two roles

Use two IAM roles. The plan role is read-only: it can read the state and the resources Terraform refreshes, and it is trusted by pull request runs. The apply role can write the state and change the infrastructure; scope its OIDC trust to the `environment:<name>` claim (and keep the environment restricted to `main` with required reviewers), so a pull request can never assume it.

### Why plans use `-lock=false`

Terraform takes the state lock by writing a lock entry (a DynamoDB item or an S3 lock file, depending on the backend). A read-only role cannot write it, so a locking plan would fail for the one role you want on pull requests. A plan only reads, so skipping the lock is safe; the saved plan is not applied. `apply` plans and applies with the lock, so two applies cannot overlap. Callers that give the plan role write access to the lock can set `lock: "true"` on `actions/terraform-plan`.

### Plans without refresh

A refresh reads every managed resource, and for some resources that means reading a secret. Refreshing an `aws_secretsmanager_secret_version` calls `secretsmanager:GetSecretValue`, so a plan role that may not read secret values fails as soon as such a secret exists. Giving the plan role that permission lets anyone who can open a pull request print the secrets from a workflow they change.

Set `plan-refresh: false` for pull request runs instead, and keep refreshing where the role is trusted:

```yaml
      plan-refresh: ${{ github.event_name != 'pull_request' }}
```

The pull request plan then compares the code with the state as last written, so it shows what the change does but not drift made outside Terraform. Data sources are still read. The plan on the default branch, and the plan inside `apply`, still refresh and catch drift before anything is applied.

### What apply applies

The apply job plans again and applies that plan in the same job; it does not apply the plan that the pull request showed. State and providers can change between the two, and a saved plan from a pull request is usually stale after merge. The apply job's log shows the plan it applied.

The approval on the GitHub environment comes before the apply job starts, so approvers cannot see the plan they are approving. For a production environment where approvers must review the exact plan, split the work into an unapproved plan job that uploads the plan file and an approval-gated apply job that applies that file. This repository does not provide that yet.

### Running the gate alone

```yaml
jobs:
  terraform:
    permissions:
      id-token: write
      contents: read
      pull-requests: write
    uses: dexteryo/d-github-actions/.github/workflows/terraform.yml@v0.3.4
    with:
      working-directory: infra
      roots: |
        envs/example
      terraform-version: "1.15.3"
      aws-region: eu-west-1
      plan-role-to-assume: arn:aws:iam::123456789012:role/example-terraform-plan
      plan: false
```

Or call `actions/terraform-gate` from your own job after checking out the repository; it does not check out for you.

### Caller

Copy `examples/caller-terraform.yml`. It plans on pull requests and on pushes to `main`, and applies when started by hand (`workflow_dispatch`) on `main`.

A reusable workflow cannot raise permissions, and GitHub checks every job of the called workflow against the calling job before anything runs, including jobs that the inputs would skip. So every calling job, plan and apply alike, must grant all of them:

```yaml
permissions:
  id-token: write
  contents: read
  pull-requests: write
```

If one is missing, the run ends as `startup_failure` with no job logs. The apply job only uses `id-token` and `contents`; the token it receives still carries `pull-requests: write`, which it does not use.

A pull request from a fork gets a read-only token, so the comment step cannot post there.

### What the caller owns

The state backend, its KMS key and the OIDC roles belong to the caller. `modules/ci-oidc-role` in `d-tf-modules` creates the OIDC roles, but its permissions are shaped for ECS deploy roles; a Terraform role needs its own policy (state bucket and lock access, plus whatever the configuration manages).

### Release tag

The workflow calls its own actions by commit hash, so a moved tag cannot change what runs. The hash is the newest commit that touched `actions/` or `scripts/`: the actions find their scripts through `github.action_path`, so it must not be older than that. When you change either, merge first, then point the workflow at the merge commit in a follow-up change.

## Reference pipeline patterns

Carried over: stage order (build, scan, push, deploy), build once and promote by digest, short-lived role assumption through an OIDC ID token (no stored keys), a vulnerability gate on image scans with a severity threshold, separate roles per environment, a deploy gate before the later environments, serialised deploys per ref.

Deliberately not carried over: change-ticket automation, per-branch and protected-branch role profile files (a role per environment replaces them), Docker-in-Docker, language-specific test stages (callers run those in their own workflows), CodeDeploy blue/green (ECS rolling deploys with the circuit breaker are used), outbound proxy settings, vulnerability suppress lists passed as environment variables (a reviewed ignore file is used instead), repository creation from the pipeline (Terraform creates repositories through `modules/ecr`).

## Using the actions directly

```yaml
- uses: dexteryo/d-github-actions/actions/ecr-build-push@v0.3.4
  id: build
  with:
    aws-region: eu-west-1
    role-to-assume: arn:aws:iam::123456789012:role/example-github-deploy
    ecr-repository: example/app

- uses: dexteryo/d-github-actions/actions/ecs-deploy@v0.3.4
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
