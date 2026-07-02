# ecsly Public Repo Working Agreement

This is the public canonical repo for migrated, publishable `ecsly` packages.
It is intentionally smaller than the private development repo.

## Documentation Router

| Need | Go to |
| --- | --- |
| Global repo purpose, owned surfaces, non-goals, proof rules | `docs/NORTH_STAR.mdx` |
| Repo-wide design rationale | `docs/DESIGN_FAQ.mdx` |
| Repo-wide maintainer and contributor workflows | `docs/DX_FAQ.mdx` |
| Package ownership and layout | `ARCHITECTURE.md` |
| Public landing and user route map | `README.md` |
| Release automation | `docs/release.mdx` |
| Steward contract and actions | `steward.yaml` |
| Architectural decisions | `docs/decisions/` |

## Current Scope

- Canonical here: `core_packages/ecsly`, `core_packages/ecsly_app`,
  `core_packages/ecsly_codegen`, and `core_packages/ecsly_flutter`.
- Not canonical here: packages, tools, experiments, or validation tracks that are
  not present in this repository.
- Do not add compatibility sync scripts or bidirectional mirror machinery.

## Package Boundary

Keep the core package pure Dart and runtime-focused:

- entities, archetypes, resources, events, commands, plugins, schedules;
- no Flutter dependency in core;
- no assumptions about paths outside this repository;
- no claims that absent packages or tools are public contracts.

Internal consumers may use these packages through normal dependencies or local
path overrides during migration.

## Skill Steward

This repo adopts Skill Steward as a local stewardship and handoff layer, with
`justfile` as the human command hub.

- Use `just` to list the local command surface.
- Use `just check` before ordinary PRs.
- Use `just release-check` before release automation changes.
- Use `steward map` to inspect the agent-facing repo map.
- Use `steward doctor --json` to validate the Steward contract.
- Use `steward probe --profile quick --json` for the quick-safe Steward smoke
  check.
- Use the native package validation commands below for product/package proof.
  Steward proof is routing and contract proof, not a substitute for package
  tests, publish dry-runs, or runtime evidence.

Before durable structural changes, read `docs/NORTH_STAR.mdx` and classify
North Star impact as one of:
`none`, `applies`, `clarifies`, `sub_star`, `amends`, or `conflicts`.
`amends` and `conflicts` need ADR work before the repo center moves.
Temporary plans are not durable docs; extract outcomes to ADRs, FAQs, code, or
Steward actions, then remove stale plan files.

## Validation

Default package loop:

```sh
dart pub get
cd core_packages/ecsly
dart analyze
dart test
dart pub publish --dry-run
```

Core internals change: update `core_packages/ecsly/DESIGN_FAQ.md` and
`core_packages/ecsly/doc/ecs_architecture_diagram.md` when relevant.
Public usage changes: update `core_packages/ecsly/DX_FAQ.md`.

Companion package loops:

```sh
cd core_packages/ecsly_app && dart test
cd core_packages/ecsly_codegen && dart test
cd core_packages/ecsly_flutter && flutter test
```

## Release Automation

This repo uses Release Please for independent Dart package releases:

- Config: `release-please-config.json`.
- Manifest: `.release-please-manifest.json`.
- Release PRs update the touched package `pubspec.yaml` and `CHANGELOG.md`.
- Release tags use `<package>-v<version>`, for example
  `ecsly-v0.0.1-dev.11` or `ecsly_flutter-v0.1.0-dev.2`.
- Tag pushes run `.github/workflows/pub-publish.yml`, which validates the tag
  with `tool/release/pub_package.dart` before publishing that one package.

Publishing requires pub.dev automated publishing to be enabled per package with:

- Repository: `Arenukvern/ecsly`
- Tag pattern: `<package>-v{{version}}`
- Push events enabled
- Environment: `pub.dev`

Use `dart tool/release/pub_package.dart --all --skip-existing` for local
publish dry-runs across all publishable packages.
