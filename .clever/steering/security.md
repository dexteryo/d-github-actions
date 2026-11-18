# Security

> Generated 2026-10-31 (INIT) from `v0.3.4` (`b384724`). Code wins over this file.

This code runs with a caller's AWS deploy and apply roles, and the repository is public. Both facts shape every control below.

## AWS access: OIDC only

No input, secret or step accepts an AWS access key. Every AWS call follows `aws-actions/configure-aws-credentials` with `role-to-assume` and `aws-region`, which exchanges the job's GitHub OIDC token for short-lived credentials (`actions/ecs-deploy/action.yml:44-48` and the same step in `ecr-build-push`, `ecr-push-image`, `terraform-plan`, `terraform-apply`). Role ARNs are inputs, not secrets.

The trust boundary is the role's trust policy, owned by the caller. What the code does to keep that boundary meaningful:

- Deploy jobs run inside a GitHub `environment` (`ecs-service-deploy.yml:56,99`; every `push` and `deploy-N` job in `ecs-promote.yml`), so the OIDC `sub` claim carries `:environment:<name>` and a role scoped to that claim cannot be assumed from elsewhere (`README.md:90`).
- `ecs-promote.yml` takes one role per environment; the push job uses the first environment's role, and the first environment is the one that must not have required reviewers (`README.md:86`).
- `terraform.yml` separates a read-only plan role from an apply role. Only the apply job runs in an `environment`; the README tells callers to scope the apply role's trust to that environment so a pull request can never assume it (`README.md:121`).
- Plans run `-lock=false` so the plan role needs no write access to the lock (`README.md:123-125`), and `plan-refresh: false` lets pull request plans avoid `secretsmanager:GetSecretValue`; the README explains that granting that read to the plan role would let anyone who can open a pull request print secrets (`README.md:127-137`).
- The apply job refuses to start with an empty `apply-role-to-assume` (`terraform.yml:135-143`) instead of falling through to some other credential.

## Workflow permissions

| Workflow | Top level | Job widening |
| --- | --- | --- |
| `ci.yml` | `contents: read` | none |
| `terraform.yml` | `contents: read` | plan: `id-token: write`, `contents: read`, `pull-requests: write`; apply: `id-token: write`, `contents: read` |
| `ecs-service-deploy.yml` | `id-token: write`, `contents: read` | none |
| `ecs-promote.yml` | `id-token: write`, `contents: read` | none |

A called workflow cannot exceed its caller, and GitHub checks every job of the called workflow before running, including skipped ones. So every job that calls `terraform.yml` must grant `id-token: write`, `contents: read` and `pull-requests: write`, or the run ends in `startup_failure` with no logs (`README.md:171-180`, fixed in v0.3.2). The ECS workflows need `id-token: write` and `contents: read` (`README.md:36`).

`actions/checkout` always has `persist-credentials: false`, so the token is not left in `.git/config` for later steps.

## Action pinning

Third-party actions are pinned to full 40-character commit SHAs with the version as a trailing comment (`README.md:239`; every `uses:` in the repository). Since v0.3.1 the reusable workflows also call this repository's own actions by full SHA rather than by tag, "so a moved tag cannot change what runs" with a caller's deploy or apply role (`CHANGELOG.md:41-43`). As of v0.3.4 two internal SHAs are in use: `95c26eac…` for everything except `terraform-plan`, which is at `23ee8dd5…` (`terraform.yml:84,112,151`, `ecs-*.yml`).

The README tells direct users of the actions to pin a tag or full SHA rather than `@main` (`README.md:219`). The one workspace caller pins `terraform.yml` by full SHA with the tag in a comment.

Two things are fetched unpinned by hash at runtime: `ci.yml:20` downloads actionlint's install script from `raw.githubusercontent.com` at tag `v1.7.12` and pipes it to bash, and `terraform-gate` installs checkov with `pip install checkov==<version>` (version pinned, no hash).

## Injection handling

Inputs never appear inside `run:` text. Every value goes through `env:` and is used as a quoted shell variable (see `coding-standards.md`). Scripts take values as arguments and use `jq --arg` and `printf '%s'`.

The plan comment marker is a trust point: `upsert-pr-comment.sh` edits a comment that contains `<!-- d-github-actions:terraform-plan:<key> -->`. Two guards protect it. `terraform-plan-comment.sh:17-20` rejects a key outside `[A-Za-z0-9._/-]`, so a key cannot close the HTML comment; and `upsert-pr-comment.sh:22-24` only selects comments whose `user.login` equals `comment-author` (default `github-actions[bot]`), so a human who copies the marker never gets their comment overwritten. Both are tested.

`ecs-deploy` with `require-digest: "true"` rejects any image that is not `registry/repo@sha256:<64 hex>` before it touches AWS (`scripts/check-image-refs.sh:4`).

## Secrets

The only secret in the public interface is `SLACK_WEBHOOK_URL`, optional, on both ECS workflows. It is read into `env:` and passed to `curl --data @-` as the URL; a missing secret is a warning, not a failure (`ecs-service-deploy.yml:151-154`). The message body is built with `jq -n --arg`. No organisation secret is assumed (`README.md:53`).

`terraform-plan` posts the full plan log (last 60000 bytes) to the pull request. Terraform redacts values marked `sensitive`, but anything not marked sensitive in the caller's configuration is published in the comment. Callers own that.

## Foreign-identifier guard

`scripts/check-no-foreign-identifiers.sh` keeps the public repository free of identifiers from any private context. It scans every tracked and untracked, non-ignored file (`git ls-files --cached --others --exclude-standard`) and, with `--git`, all commit author, committer and message text across `git log --all`. It fails on:

- any one-to-three-word run of lower-cased alphanumeric tokens, joined without separators, whose SHA-256 is in `scripts/foreign-identifiers.sha256` (20 digests). Storing digests means the list does not reveal what it denies, and a finding prints only the first eight hex characters of the digest;
- any 12-digit number other than `123456789012` (repeated-digit numbers such as `000000000000` are allowed);
- in files only, any email address outside `example.com`, `example.org`, `example.test`, `users.noreply.github.com` (and `git@github.com`).

It skips `.git`, `.terraform`, `.clever`, `.terraform.lock.hcl`, the deny-list itself, binary files and files over 2 MB (`scripts/check-no-foreign-identifiers.sh:36-39,86-93`). The `.clever` exclusion means these steering docs are not scanned, so anything written here must follow the placeholder rule by hand if `.clever/` is ever committed.

CI runs it with `--git`; pre-commit runs it on the working tree. To add a term, append `printf '%s' '<lowercasewords>' | shasum -a 256` output to the deny-list; never commit the plain term.
