# Operations

> Generated 2026-10-31 (INIT) from `v0.3.4` (`b384724`). Code wins over this file.

This repository is not deployed. It is "released" by pushing a git tag, and it runs only inside callers' GitHub Actions runs, on GitHub-hosted `ubuntu-latest` runners. There are no servers, dashboards or alerts of its own.

## Distribution

Callers reference `dexteryo/d-github-actions/.github/workflows/<file>.yml@<ref>` or `dexteryo/d-github-actions/actions/<name>@<ref>`. A new tag changes nothing for an existing caller until that caller moves its ref. The one in-workspace caller, `workspace/finn-app-brazil/.github/workflows/infra.yml`, is on `681de421…` (`v0.3.3`), one release behind; v0.3.4 fixes the plan comment for callers with more than one root, and that caller plans a single root (`envs/nonprod`), so it is not affected.

## What a run produces

| Workflow | Visible output |
| --- | --- |
| `ecs-service-deploy.yml` | `deploy` job output `task-definition-arn` (not re-exported as a workflow output); `image-ref-<name>` artefacts, 1-day retention; optional Slack message |
| `ecs-promote.yml` | `image-archive-<name>` artefacts (1 day), `image-ref-<name>` artefacts (7 days); Trivy table in the scan job log; optional Slack message |
| `terraform.yml` | Plan summary and log in the job summary (`$GITHUB_STEP_SUMMARY`); on `pull_request`, one comment per root module, edited in place |

## Failure modes and how they surface

| Situation | Behaviour | Where |
| --- | --- | --- |
| ECS circuit breaker rolls back, or `rolloutState` is `FAILED` | Job fails, last ten service events printed | `actions/ecs-deploy/action.yml:111-115` |
| Rollout not complete within `timeout-minutes` (default 15) | Job fails with a timeout error, events printed; polling is every 15 s and is not bound by the AWS CLI waiter's 10-minute cap | `actions/ecs-deploy/action.yml:116-121`, `README.md:223` |
| Container name in `images` not in the task definition | `rewrite-task-definition.sh` errors with `unknown containers: ...` before registering | `scripts/rewrite-task-definition.sh:28-29` |
| Tag reference reaches a promote deploy | `check-image-refs.sh` fails the job | `scripts/check-image-refs.sh` |
| Trivy finds a vulnerability at `scan-severity` | Scan job fails, no push, no deploy | `ecs-promote.yml:127-136` |
| Terraform plan errors | Comment and summary say `Plan failed (exit N).`; the job then fails | `actions/terraform-plan/action.yml:124-132` |
| Plan has changes | Job succeeds; `result` output is `changes` | same |
| Caller job lacks a permission the called workflow asks for | `startup_failure`, no logs | `README.md:180` |
| Pull request from a fork | Token is read-only; the plan comment cannot be posted | `README.md:182` |
| `slack-notify: true` without the secret | Warning, job succeeds | `ecs-service-deploy.yml:151-154` |

## Rollback

For ECS, the deploy registers a new task definition revision and updates the service; the previous revision stays registered. Because images are referenced by digest, redeploying an earlier revision or digest gives the same image (`README.md:225`). This repository provides no rollback workflow; the ECS deployment circuit breaker is configured on the caller's service (`modules/ecs-service` in `d-tf-modules`).

For Terraform there is no rollback; a revert goes through a new plan and apply.

For this library, a caller rolls back by moving its pinned ref to the previous SHA or tag.

## Concurrency and serialisation

Deploys of the same service and environment queue and are never cancelled (`ecs-service-deploy.yml:48-50`); promotions per repository and ref likewise (`ecs-promote.yml:52-54`). Terraform plans for the same root and ref cancel older ones; applies queue and are never cancelled (`terraform.yml:96-98,125-127`). Job timeouts are set only in `terraform.yml` (15 minutes for gate and plan, 30 for apply); the ECS jobs use GitHub's default.

## Caller-side observations (from the in-workspace caller)

`finn-app-brazil`'s `infra.yml` passes `plan-refresh: ${{ github.event_name != 'pull_request' }}`, chooses a read role on pull requests and a write role otherwise, gates `plan` on a `TF_BACKEND_READY` variable, and does not set `environment` on its apply call, so its apply job runs without a GitHub environment approval. Its `infra/README.md:54` says the roles and the OIDC provider are managed by hand in the console. These are that caller's choices, recorded here because they exercise this repository's inputs.
