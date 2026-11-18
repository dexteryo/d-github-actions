# Development workflow

> Generated 2026-10-31 (INIT) from `v0.3.4` (`b384724`). Commands verified on macOS (Darwin 27) on 2026-10-31 unless marked otherwise.

## Prerequisites

`jq`, `python3` (the foreign-identifier check embeds a Python script), `shasum` (used by its test), `bash`. For the full lint set also `shellcheck` and `actionlint`, and `pre-commit` for the hook. The README installs `brew install actionlint shellcheck jq` (`README.md:230`); it does not list `python3`.

There is nothing to build or install in the repository itself.

## The green gate

This is what CI runs (`.github/workflows/ci.yml:19-38`), in order:

```bash
actionlint -color                                  # CI downloads v1.7.12
shellcheck scripts/*.sh tests/*.sh
tests/rewrite-task-definition.test.sh
tests/check-deployment.test.sh
tests/promotion-plan.test.sh
tests/terraform-plan-summary.test.sh
tests/terraform-plan-comment.test.sh
tests/upsert-pr-comment.test.sh
scripts/check-no-foreign-identifiers.sh --git
tests/check-no-foreign-identifiers.test.sh
```

The one-line local equivalent for the tests, as the pre-commit hook runs it (`.pre-commit-config.yaml:23`):

```bash
bash -c 'for t in tests/*.test.sh; do "$t" || exit 1; done'
```

Result on 2026-10-31 at `v0.3.4`: all seven test files passed (exit 0), and `scripts/check-no-foreign-identifiers.sh --git` passed. `shellcheck`, `actionlint` and `pre-commit` were not installed on this machine, so those two lint steps were not run locally.

A new test file must be added to `ci.yml` by hand; CI lists each file, while pre-commit globs `tests/*.test.sh`.

## Pre-commit

`.pre-commit-config.yaml` defines four local hooks, all `language: system` (so the tools must already be on `PATH`):

| Hook | Runs | Trigger |
| --- | --- | --- |
| `foreign-identifiers` | `scripts/check-no-foreign-identifiers.sh` (working tree, no `--git`) | every commit |
| `shellcheck` | `shellcheck` on staged `*.sh` | `\.sh$` |
| `actionlint` | `actionlint` | `^\.github/workflows/.*\.ya?ml$` |
| `shell-tests` | every `tests/*.test.sh` | every commit |

Install with `pre-commit install` (`README.md:237`).

## Branching and merging

Since v0.3.0 every change lands through a GitHub pull request from a short-lived branch, merged with a merge commit ("Merge pull request #N from dexteryo/<branch>"). Branch prefixes seen: `feat/`, `fix/`, `release/` (`git log --graph`). v0.1.0 to v0.2.1 were committed straight to `main`. A `renovate/configure` branch exists on the remote but is not merged; there is no Renovate config on `main`.

## Release process

The process as practised from the git history and CHANGELOG:

1. On a branch, commit the change to `actions/` and `scripts/` with its tests (for v0.3.4, `23ee8dd`).
2. Add a final commit in the same pull request that points the reusable workflow at the SHA of step 1 for the changed action, adds the CHANGELOG section, and moves the `@vX.Y.Z` references in `README.md` and `examples/*.yml` to the new version (`f568e2e` for v0.3.4, `df18d27` for v0.3.3; before v0.3.1 the workflows referenced their actions by tag, so `4440525` for v0.3.0 only moved `@v0.2.1` to `@v0.3.0`). The SHA in the workflow is therefore the feature commit, not the tagged merge commit, and the trailing comment names the release (`terraform.yml:112`, `# v0.3.4`).
3. The README states the rule behind this: an action finds its scripts through `github.action_path`, so the pinned SHA must not be older than the newest commit that touched what that action runs; it describes the safe order as merge first, then repoint in a follow-up (`README.md:188-190`). Practice since v0.3.3 has been the in-branch repoint above, which also satisfies the rule because the feature commit survives the merge commit.
4. Merge the pull request, then tag the merge commit with an annotated tag `vX.Y.Z` and push it. v0.3.0 to v0.3.4 are annotated tags on merge commits; v0.1.0 to v0.2.1 are lightweight tags on direct commits. Tags are on `origin` (`git ls-remote --tags origin`).

Versioning is SemVer per `CHANGELOG.md:3`. See `api-guidelines.md` for what has counted as minor versus patch.

No workflow in this repository creates tags or GitHub releases; tagging is manual.

## Trying a change against a real caller

There is no local runner for the workflows (no `act` config). Change validation beyond the script tests happens by pointing a caller at the branch or commit. The only in-workspace caller is `workspace/finn-app-brazil/.github/workflows/infra.yml`.
