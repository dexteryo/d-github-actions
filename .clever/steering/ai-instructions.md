# Instructions for AI agents

> Generated 2026-10-31 (INIT) from `v0.3.4` (`b384724`). Read `structure.md` and `security.md` before changing anything.

## Before you start

- Read the YAML you are changing and the README section that documents it. The README is detailed and kept in step with the code; when they disagree, the YAML wins and the disagreement is worth reporting.
- This repository is public. Never write a real account ID, hostname, email, company, client or project name into any tracked file, commit message, fixture or example. Use `123456789012`, `eu-west-1`, `example-*`, `example.com`. Run `scripts/check-no-foreign-identifiers.sh --git` before you finish; it also scans commit messages.
- `.clever/` is skipped by that guard. Do not put `.clever/` content into tracked files without applying the same rule by hand.
- Do not touch `.clever/ralph/`; it is scratch output of an unrelated agent loop.

## Where a change belongs

| Change | Put it in |
| --- | --- |
| A decision that can be tested from a file or argument (parsing, validation, choosing what to edit) | A new or existing `scripts/*.sh`, with a `tests/<script>.test.sh` |
| Tool setup, AWS login, wiring a script into a step | `actions/<name>/action.yml` |
| Job order, environments, permissions, concurrency, matrix | `.github/workflows/<name>.yml` |
| Caller usage | `examples/caller*.yml` and the README table |

Do not put logic into an inline `run:` block when it could be a script; inline logic has no tests.

## Rules that are easy to break

1. Never interpolate `${{ ... }}` inside `run:`. Pass it through `env:` and quote it.
2. Pin every third-party action to a full 40-character SHA with `# vX.Y.Z` after it. Do not use tags.
3. Workflows call this repository's own actions by full SHA. If you change an action or a script it runs, the workflow's pin for that action must move to a commit that contains your change; otherwise callers keep running the old code. Follow the release steps in `development-workflow.md`.
4. Actions locate scripts as `"$ACTION_PATH/../../scripts/<name>.sh"`. Keep that layout; if a script moves, every action that calls it must change in the same commit.
5. Keep `persist-credentials: false` on every checkout.
6. Keep top-level `permissions:` minimal and widen per job. If you add a permission to any job of `terraform.yml`, every caller job needs it too, or callers hit `startup_failure`; say so in the CHANGELOG and README.
7. Inputs to actions are strings (`"true"`/`"false"`); inputs to workflows are typed. Convert at the boundary as `terraform.yml:119` does.
8. Do not rename or remove an input, output or secret, and do not change a default's behaviour, without the user's agreement; no release so far has done that (`api-guidelines.md`).
9. A rollback or a non-digest image under `require-digest` must stay a failure.
10. Do not weaken the plan comment guards: the key regex in `terraform-plan-comment.sh` and the author match in `upsert-pr-comment.sh`.

## Script and test style

Follow `coding-standards.md` and `testing.md`: `#!/usr/bin/env bash`, `set -euo pipefail`, usage on stderr with exit 2, `jq --arg`, `printf '%s'`, no comments. Tests are plain bash with a `failures` counter and sentence-style case names; fake external commands through `PATH`. The scripts and tests currently run under macOS `/bin/bash` 3.2.57 (verified 2026-10-31), which is what the pre-commit hook gets on a Mac; keep `mapfile`, associative arrays and `${var,,}` out of `scripts/` and `tests/` so that stays true. Inline action steps run on `ubuntu-latest` and may use bash 4+.

When you add a test file, add a step for it to `.github/workflows/ci.yml`; CI lists test files one by one.

## Verify before you report

```bash
bash -c 'for t in tests/*.test.sh; do "$t" || exit 1; done'
scripts/check-no-foreign-identifiers.sh --git
shellcheck scripts/*.sh tests/*.sh     # if installed
actionlint                              # if installed
```

On 2026-10-31 `shellcheck` and `actionlint` were not installed on Dexter's Mac; say so if you could not run them rather than reporting them as passing.

## Documentation duties with any change

Update the README table for any new or changed input, add a CHANGELOG entry under the right Keep a Changelog heading, and update `examples/` when the calling pattern changes. Do not tag, push or move a ref in a caller repository unless asked.

## Cross-repo awareness

Changes to role expectations or ECS behaviour may need matching changes in `workspace/d-tf-modules` (`modules/ci-oidc-role`, `modules/ecs-service`, `modules/ecr`). The in-workspace caller is `workspace/finn-app-brazil/.github/workflows/infra.yml`, pinned to `v0.3.3` by SHA; it does not move when this repository releases.
