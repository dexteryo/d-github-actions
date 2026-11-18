# Architecture

> Generated 2026-10-31 (INIT) from `v0.3.4` (`b384724`). Code wins over this file.

## Style

A library of building blocks in three layers: reusable workflow → composite action → bash script. The workflows own job ordering, concurrency, permissions and GitHub environments; the actions own tool setup and AWS login; the scripts own the decisions that can be tested offline (is this a digest, did the rollout complete, what does the plan summary say, which comment to edit). See `structure.md` for the map.

Every AWS call happens after `aws-actions/configure-aws-credentials` exchanges the job's GitHub OIDC token for short-lived role credentials. No step reads an AWS key.

## OIDC to AWS

```mermaid
sequenceDiagram
  participant Caller as Caller job (permissions: id-token write)
  participant WF as Reusable workflow job
  participant Act as Composite action
  participant GH as GitHub OIDC provider
  participant STS as AWS STS
  participant AWS as ECR / ECS / Terraform backend
  Caller->>WF: uses: .../workflow.yml@ref, with role-to-assume
  WF->>Act: uses: .../actions/x@<full SHA>
  Act->>GH: configure-aws-credentials requests ID token
  GH-->>Act: JWT, sub = repo:<owner>/<repo>[:environment:<name>]
  Act->>STS: AssumeRoleWithWebIdentity(role-to-assume)
  STS-->>Act: short-lived credentials
  Act->>AWS: aws ecs ... / docker push / terraform
```

The role's trust policy, not this repository, decides which `sub` claims may assume it. The README recommends scoping deploy and apply roles to `repo:<owner>/<repo>:environment:<name>` so only a job running in that GitHub environment can assume them (`README.md:90`, `README.md:121`).

## ecs-service-deploy.yml

```mermaid
flowchart LR
  C[caller job] --> B
  subgraph WF[ecs-service-deploy.yml, concurrency ecs-deploy-service-environment]
    B["build (matrix over images, environment)"] -->|artefact image-ref-NAME| D["deploy (environment)"]
    D --> N["notify (if slack-notify, always)"]
    B --> N
  end
  B -. uses .-> EBP[actions/ecr-build-push]
  D -. uses .-> ED[actions/ecs-deploy]
  ED -. calls .-> S1[scripts/rewrite-task-definition.sh]
  ED -. calls .-> S2[scripts/check-deployment.sh]
  N -. curl .-> SL[(Slack webhook)]
```

Each build job pushes by tag (the commit SHA unless `image-tag` is set) and writes `name=registry/repo@sha256:...` to an artefact. The deploy job concatenates those into `container-images` (`ecs-service-deploy.yml:110-118`).

## ecs-promote.yml

```mermaid
flowchart LR
  P["plan → promotion-plan action → promotion-plan.sh"] --> B["build (matrix, push: false, image archive artefact)"]
  B --> S["scan (matrix, Trivy, exit-code 1)"]
  S --> PU["push (matrix, environment = env-1, ecr-push-image)"]
  PU -->|image-ref-* artefacts, 7 days| D1["deploy-1 (env-1)"]
  D1 -->|promote and success| D2["deploy-2 (env-2, reviewers)"]
  D2 -->|promote and success| D3["deploy-3 (env-3, reviewers)"]
  D1 & D2 & D3 --> N["notify (if slack-notify)"]
```

The build job has no AWS access: `ecr-build-push` with `push: "false"` skips the credential and login steps and writes a `type=docker` archive (`actions/ecr-build-push/action.yml:62-97`). The digest is fixed at push. All deploys run `ecs-deploy` with `require-digest: "true"`, so `scripts/check-image-refs.sh` runs before any task definition is registered. Each deploy job skips unless `count` from the plan job reaches its position (`ecs-promote.yml:182,219,256`).

## ecs-deploy action

```mermaid
flowchart TD
  A[configure-aws-credentials] --> R{require-digest?}
  R -- true --> CIR[check-image-refs.sh] --> REG
  R -- false --> REG[describe-task-definition family → rewrite-task-definition.sh → register-task-definition]
  REG --> U[update-service --task-definition new ARN]
  U --> W{wait-for-stability?}
  W -- false --> Done
  W -- true --> L[describe-services → check-deployment.sh]
  L -- exit 0 --> Done[success]
  L -- exit 10 --> T{deadline passed?}
  T -- no, sleep 15 --> L
  T -- yes --> F[fail, print last 10 service events]
  L -- exit 1 --> F
```

`check-deployment.sh` exit codes are a contract: 0 done, 10 keep polling, anything else failed (`scripts/check-deployment.sh:27-34`, `actions/ecs-deploy/action.yml:106-121`).

## terraform.yml

```mermaid
flowchart LR
  G["gate: select first root → checkout → terraform-gate (fmt, validate every root, tflint, checkov)"]
  G -->|"!apply and plan"| PL["plan: terraform-plan action, lock false, refresh = plan-refresh"]
  G -->|apply| AP["apply (environment): require apply role → terraform-apply"]
  PL -. calls .-> SUM[terraform-plan-summary.sh]
  PL -. calls .-> COM[terraform-plan-comment.sh]
  PL -. calls .-> UPS[upsert-pr-comment.sh → gh api]
```

The gate validates every root in `roots`; plan and apply use only the first (`terraform.yml:71-76`). Plan runs with the plan role and `pull-requests: write`; apply runs with the apply role in the named GitHub environment.

### Plan comment flow

```mermaid
sequenceDiagram
  participant TP as terraform-plan action
  participant TF as terraform
  participant GH as GitHub REST API
  TP->>TF: plan -detailed-exitcode > log (exit code captured, not fatal)
  TP->>TP: summary.sh(exit, log) → result no-changes / changes / outputs-only / failed
  TP->>TP: comment.sh → markdown ending in <!-- d-github-actions:terraform-plan:KEY -->
  TP->>GH: GET issues/N/comments --paginate
  alt newest comment by comment-author containing marker exists
    TP->>GH: PATCH issues/comments/ID
  else
    TP->>GH: POST issues/N/comments
  end
  TP->>TP: fail the step only if result = failed
```

The comment step runs only on `pull_request` events (`actions/terraform-plan/action.yml:110`).

## Concurrency

| Workflow / job | Group | Cancel in progress |
| --- | --- | --- |
| `ecs-service-deploy.yml` (workflow) | `ecs-deploy-<service>-<environment>` | false |
| `ecs-promote.yml` (workflow) | `ecs-promote-<repository>-<ref>` | false |
| `terraform.yml` plan job | `terraform-plan-<working-directory>/<first root>-<ref>` | true |
| `terraform.yml` apply job | `terraform-apply-<working-directory>/<first root>-<ref>` | false |
