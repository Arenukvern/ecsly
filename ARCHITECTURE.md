# ecsly Public Architecture

This repository is the canonical home of the `ecsly` package family: the
high-performance Dart ECS runtime and the companion packages published
alongside it.

## Ownership

| Path                           | Package               | Ownership                                                                            |
| ------------------------------ | --------------------- | ------------------------------------------------------------------------------------ |
| `core_packages/ecsly/`         | `ecsly`               | Core ECS runtime: entities, archetypes, queries, schedules, commands, events, resources, benchmarks |
| `core_packages/ecsly_app/`     | `ecsly_app`           | App actions, drafts, invalidation, and cold lookup                                    |
| `core_packages/ecsly_codegen/` | `ecsly_codegen`       | Typed-column annotations and build_runner factories                                   |
| `core_packages/ecsly_flutter/` | `ecsly_flutter`       | Flutter scope, controller, selectors, actions, and loops                              |
| `plugins/ecsly_serialization/` | `ecsly_serialization` | World snapshot serialization and deserialization                                      |
| `plugins/ecsly_replay/`        | `ecsly_replay`        | World replay logs, checkpoints, and seek                                              |

`plugins/` also hosts packages in active development that are not published
(`publish_to: none`): `ecsly_flutter_scene`, `ecsly_world_sync`,
`ecsly_world_sync_bridge`, `ecsly_world_zones`, `async_parallel`, and
`ecsly_async_parallel`. Their status and design records are listed in the
[package map](docs/packages.mdx).

Packages, experiments, tools, docs, and validation tracks outside this
repository are not public contracts.

## Repository Boundary

Consumers depend on public package identities (`ecsly`, `ecsly_app`,
`ecsly_codegen`, `ecsly_flutter`, `ecsly_serialization`, `ecsly_replay`).
Inside this repository, all packages resolve through the root pub workspace;
workspace members depend on each other with key-only or manifest-aligned
constraints so `dart pub get` at the root is the single source of resolution
truth.

## Package Shape

- `core_packages/` holds the published runtime and its companions; `plugins/`
  holds runtime extensions, published and in-development.
- The core package stays pure Dart; Flutter behavior lives in
  `ecsly_flutter`, app workflows in `ecsly_app`, code generation in
  `ecsly_codegen`.
- Each publishable package keeps its README, DX FAQ, DESIGN FAQ, tests, and
  examples next to its code, and is released independently by Release Please
  under `<package>-v<version>` tags.
