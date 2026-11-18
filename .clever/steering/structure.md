# Structure

> Generated 2026-10-31 (INIT) from `v0.3.4` (`b384724`). Code wins over this file.

```text
.github/workflows/
  ci.yml                    # this repo's own CI: lint, shellcheck, every test, foreign-identifier check
  ecs-service-deploy.yml    # reusable: build N images -> deploy one environment -> optional Slack
  ecs-promote.yml           # reusable: plan -> build -> scan -> push -> deploy-1..3 -> optional Slack
  terraform.yml             # reusable: gate -> plan | apply
actions/
  ecr-build-push/           # build with Buildx; push to ECR or write an image archive
  ecr-push-image/           # load an archive and push it, output repo@digest
  ecs-deploy/               # register task definition revision, update service, poll
  promotion-plan/           # validate the environments JSON, emit env-1..3
  terraform-gate/           # fmt, validate per root, tflint, checkov (no checkout)
  terraform-plan/           # OIDC, plan, summary, PR comment upsert
  terraform-apply/          # OIDC, plan, apply the saved plan
scripts/                    # the logic the actions call, testable without GitHub
  foreign-identifiers.sha256
tests/
  *.test.sh                 # one file per script (check-image-refs is covered in promotion-plan.test.sh)
  fixtures/                 # JSON and log fixtures
examples/
  caller.yml, caller-promote.yml, caller-terraform.yml
.pre-commit-config.yaml
CHANGELOG.md, README.md
```

There is no `.gitignore` in the repository. `.clever/` is untracked; `.clever/ralph/` holds scratch files from an agent loop and is not part of the library.

## Layering

The repository has three layers, and each only calls the one below it.

| Layer | Path | Calls |
| --- | --- | --- |
| Reusable workflows | `.github/workflows/{ecs-service-deploy,ecs-promote,terraform}.yml` | This repo's own actions by full commit SHA, plus pinned third-party actions |
| Composite actions | `actions/<name>/action.yml` | Scripts through `"$ACTION_PATH/../../scripts/<script>.sh"`, where `ACTION_PATH` is `github.action_path` |
| Scripts | `scripts/*.sh` | `jq`, `gh`, `python3`; no AWS or GitHub context of their own |

The `../../scripts` path is load-bearing. An action finds its script relative to its own checkout, so an action pinned at commit X runs the scripts of commit X (`README.md:188-190`).

## Action → script map

| Action | Scripts |
| --- | --- |
| `ecs-deploy` | `check-image-refs.sh` (when `require-digest`), `rewrite-task-definition.sh`, `check-deployment.sh` |
| `promotion-plan` | `promotion-plan.sh` |
| `terraform-plan` | `terraform-plan-summary.sh`, `terraform-plan-comment.sh`, `upsert-pr-comment.sh` |
| `ecr-build-push`, `ecr-push-image`, `terraform-gate`, `terraform-apply` | none (inline steps only) |

`check-no-foreign-identifiers.sh` and `foreign-identifiers.sha256` are repository hygiene, used by CI and pre-commit, never by an action.

## Naming

Directories and files are kebab-case. Actions are named `<target>-<verb>` (`ecr-build-push`, `ecs-deploy`, `terraform-plan`). Tests are `tests/<script-name>.test.sh`. Fixtures are `tests/fixtures/<subject>-<case>.{json,log,txt}` (`deployment-rolled-back.json`, `terraform-plan-outputs-only.log`, `pr-comments-two-pages.json`).

## Cross-repo relationships

`workspace/d-tf-modules` creates the AWS resources these workflows act on (OIDC roles, ECR repositories, ECS services). `workspace/finn-app-brazil/.github/workflows/infra.yml` is the one caller found in the workspace. See `product.md`.
