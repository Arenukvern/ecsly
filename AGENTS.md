# ecsly Public Repo Working Agreement

This is the public canonical repo for migrated, publishable `ecsly` packages.
It is intentionally smaller than the private development repo.

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
