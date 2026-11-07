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
| `plugins/async_parallel/`      | `async_parallel`      | Zero-cost isolate management primitives                                               |
| `plugins/ecsly_world_sync/`    | `ecsly_world_sync`    | World sync over the convergence kernel and session core                               |
| `plugins/ecsly_world_zones/`   | `ecsly_world_zones`   | Zone travel: the mesh sync pulse as an ordinary system                                |
| `plugins/ecsly_async_parallel/` | `ecsly_async_parallel` | ECS-aware parallel task systems built on `async_parallel`                           |
| `plugins/ecsly_world_sync_bridge/` | `ecsly_world_sync_bridge` | Live World→delta bridge at flush boundaries                                    |
| `plugins/ecsly_flutter_scene/` | `ecsly_flutter_scene` | 3D scene adapter on `flutter_scene`                                                   |

Packages, experiments, tools, docs, and validation tracks outside this
repository are not public contracts.

## Repository Boundary

Consumers depend on public package identities (`ecsly`, `ecsly_app`,
`ecsly_codegen`, `ecsly_flutter`, `ecsly_serialization`, `ecsly_replay`,
`async_parallel`, `ecsly_world_sync`, `ecsly_world_zones`,
`ecsly_async_parallel`, `ecsly_world_sync_bridge`, `ecsly_flutter_scene`).
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
