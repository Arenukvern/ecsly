# Contributing

Thanks for helping improve `ecsly`.

This public repository is the canonical home for the migrated, publishable
package family under `core_packages/`. Keep contributions scoped to packages,
docs, and release tooling that are present here.

## Before You Start

- Read [AGENTS.md](AGENTS.md).
- Check the relevant package README and FAQ.
- Keep core `ecsly` pure Dart; Flutter belongs in `ecsly_flutter`.
- Do not add references to private packages, absent tools, or internal-only
  validation tracks.

## Local Validation

Default core loop:

```sh
dart pub get
cd core_packages/ecsly
dart analyze
dart test
dart pub publish --dry-run
```

Companion packages:

```sh
cd core_packages/ecsly_app && dart test
cd core_packages/ecsly_codegen && dart test
cd core_packages/ecsly_flutter && flutter test
```

Release preflight:

```sh
dart tool/release/pub_package.dart --all --skip-existing
```

Steward smoke:

```sh
steward doctor --json
steward probe --profile quick --json
```

## Pull Requests

Use conventional commit-style PR titles when possible:

- `feat: add ...`
- `fix: repair ...`
- `docs: clarify ...`
- `chore: update ...`

Update docs when behavior, setup, package metadata, or release workflow changes.
For user-facing changes, Release Please will turn conventional commits into
package changelog entries.

## Contributor Credit

Contributor credit uses [all-contributors](https://allcontributors.org/).

```sh
npx all-contributors-cli add <github-login> code,doc
npx all-contributors-cli generate
```

Commit both `.all-contributorsrc` and `README.md`.

See [docs/contributing/contributors.mdx](docs/contributing/contributors.mdx).

## Maintainers

Release automation:

- Release Please config: `release-please-config.json`
- Manifest: `.release-please-manifest.json`
- Publish workflow: `.github/workflows/pub-publish.yml`
- Agent approval workflow: `.github/workflows/agent-auto-approve.yml`
- Local preflight: `dart tool/release/pub_package.dart --all --skip-existing`

pub.dev automated publishing must be enabled per package with repository
`Arenukvern/ecsly`, tag pattern `<package>-v{{version}}`, push events enabled,
and environment `pub.dev`.

Agent auto-approval requires a repository secret named `AUTO_APPROVE_TOKEN`.
Use a dedicated machine user token with write access to this repository. The
workflow only approves same-repo PRs from `Arenukvern` on `codex/` branches or
`github-actions[bot]` on `release-please--` branches after `Release validation`
succeeds and the PR has the `agent-auto-approve` label.
