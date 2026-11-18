# Domain vocabulary

> Generated 2026-10-31 (INIT) from `v0.3.4` (`b384724`). Terms as this repository uses them.

| Term | Meaning here | Evidence |
| --- | --- | --- |
| caller | A workflow in another repository that runs one of these reusable workflows or actions with `uses:` | `examples/caller*.yml` |
| reusable workflow | A file under `.github/workflows/` with `on: workflow_call`; called at job level | `terraform.yml:3-4` |
| composite action | `actions/<name>/action.yml` with `runs: using: composite`; called at step level | all actions |
| role-to-assume | ARN of an IAM role the job assumes through GitHub OIDC | every AWS action |
| environment | Two meanings that coincide by design: a GitHub environment (approvals, scoped variables, the OIDC `sub` claim) and the AWS target it deploys to. In `ecs-promote.yml` an entry of the `environments` JSON array carries both | `README.md:79-90` |
| images | JSON array input; each item's `name` must equal a container name in the task definition, plus `ecr-repository` and optional `dockerfile`, `context`, `platforms`, `build-args` | `README.md:45` |
| container images / pairs | Multiline `name=image-uri` lines passed to `ecs-deploy`'s `container-images` | `actions/ecs-deploy/action.yml:20-22` |
| image reference | `name=registry/repository@sha256:<digest>`, one per `image-refs/<name>.txt` file and `image-ref-<name>` artefact | `ecs-promote.yml:163-177` |
| image archive | A `docker save`-style tar written by `ecr-build-push` with `push: "false"`, uploaded as `image-archive-<name>` | `actions/ecr-build-push/action.yml:85-97` |
| digest | `sha256:<64 hex>`; fixed by the first push and reused by every later deploy | `scripts/check-image-refs.sh:4` |
| promotion | Deploying the digest already deployed to an earlier environment to the next one, without rebuilding | `README.md:57-66` |
| promotion plan | The validated `environments` list, emitted as `count` and `env-1`..`env-3` JSON outputs; `env-N` is `{}` when absent; a missing `aws-region` is filled from the default | `scripts/promotion-plan.sh` |
| deploy gate | Required reviewers (optionally wait timer and branch rule) on the GitHub environment of `deploy-2`/`deploy-3` or the Terraform apply job | `README.md:79-86` |
| task definition family | ECS family whose latest revision is the base for the new revision | `actions/ecs-deploy/action.yml:17-19` |
| read-only fields | `taskDefinitionArn`, `revision`, `status`, `requiresAttributes`, `compatibilities`, `registeredAt`, `registeredBy`, `deregisteredAt`, stripped before `register-task-definition` | `scripts/rewrite-task-definition.sh:32-35` |
| PRIMARY deployment / rolloutState | The ECS service deployment that `check-deployment.sh` inspects; success means PRIMARY is the new ARN and `COMPLETED` | `scripts/check-deployment.sh` |
| rolled back / superseded | PRIMARY is not the ARN just registered; always a failure | `scripts/check-deployment.sh:22-25` |
| root / root module | A Terraform directory with its own state, listed one per line in `roots`, relative to `working-directory`. The gate validates all; plan and apply use the first | `terraform.yml:10-13,71-76` |
| gate (Terraform) | `fmt -check -recursive`, `init -backend=false` + `validate` per root, `tflint --recursive`, `checkov -d .` | `actions/terraform-gate/action.yml` |
| plan role / apply role | Read-only role for plans, trusted by pull request runs; write role for apply, trusted only from the apply environment | `README.md:119-121` |
| plan refresh | Whether `terraform plan` refreshes state from live resources; `false` on pull requests to avoid reading secret values | `README.md:127-137` |
| plan result | `no-changes`, `changes`, `outputs-only` or `failed`, derived from the `-detailed-exitcode` exit code and the log | `actions/terraform-plan/action.yml:97-101` |
| plan summary | One line: `No changes.`, the `Plan: ...` line, `Changes to outputs only.`, `Plan has changes (no summary line found).` or `Plan failed (exit N).` | `scripts/terraform-plan-summary.sh` |
| comment key | Identifies one plan's pull request comment; defaults to `working-directory`; `[A-Za-z0-9._/-]+` only | `actions/terraform-plan/action.yml:26-28` |
| plan comment marker | `<!-- d-github-actions:terraform-plan:<comment-key> -->`, the last line of the comment, used to find it again | `scripts/terraform-plan-comment.sh:38` |
| comment author | Login whose comments may be edited; default `github-actions[bot]` | `actions/terraform-plan/action.yml:29-31` |
| upsert | Edit the newest matching comment, or create one | `scripts/upsert-pr-comment.sh` |
| foreign identifier | Any name, account number or email from a private context that must not appear in this public repository | `scripts/check-no-foreign-identifiers.sh` |
| placeholder | `123456789012`, `eu-west-1`, `example-*`, `example.com`; the only identifiers allowed | `README.md:5` |
