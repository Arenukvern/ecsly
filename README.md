# ecsly

Experimental Entity Component System packages for Dart and Flutter.

**Status:** early prerelease (`0.0.1-dev.9`). APIs may change between releases.

This repository is the canonical source for the migrated `ecsly` package family:
the headless runtime, app workflow layer, code generator, and Flutter bridge.

The North Star is a practical Dart game-engine stack over time. The honest
present shape is an R&D package family with a stabilizing core, public companion
packages, and many ideas still experimental rather than public contracts. The
core can be used from Flutter apps, Jaspr sites, Flame games, CLIs, servers, and
plain Dart tests without taking a Flutter dependency.

## Repo map

| Path | What it is |
| --- | --- |
| [`core_packages/ecsly/`](core_packages/ecsly/) | Publishable `ecsly` package — runtime, examples, tests, benchmarks |
| [`core_packages/ecsly_app/`](core_packages/ecsly_app/) | Pure Dart app layer — actions, drafts, invalidation, cold lookup |
| [`core_packages/ecsly_codegen/`](core_packages/ecsly_codegen/) | Annotation/build_runner package for typed-column factories |
| [`core_packages/ecsly_flutter/`](core_packages/ecsly_flutter/) | Flutter bridge — scope, controller, selectors, actions, loops |
| [`AGENTS.md`](AGENTS.md) | Working agreement for coding agents (scope, validation, doc updates) |
| [`ARCHITECTURE.md`](ARCHITECTURE.md) | Public package ownership and layout |
| [`docs/decisions/`](docs/decisions/) | Architecture decision records (ADRs) |
| [`pubspec.yaml`](pubspec.yaml) | Dart workspace root (`ecsly_workspace`) |

## Quick start

**Requirements:** Dart SDK `>=3.12.0`.

```sh
dart pub get
cd core_packages/ecsly
dart run example/main.dart
```

Add as a dependency:

```yaml
dependencies:
  ecsly: ^0.0.1-dev.9
```

Platforms: Android, iOS, Linux, macOS, web, Windows. Usable from Flutter,
Jaspr, CLI tools, and plain Dart tests.

## Validate

Run from the repository root:

```sh
dart pub get
cd core_packages/ecsly
dart analyze
dart test
dart pub publish --dry-run
```

Companion package checks:

```sh
cd core_packages/ecsly_app && dart test
cd core_packages/ecsly_codegen && dart test
cd core_packages/ecsly_flutter && flutter test
```

Benchmarks (optional):

```sh
cd core_packages/ecsly
dart run benchmark/run.dart --limits --samples=5 \
  --markdown-out=benchmark/results/latest.md \
  --json-out=benchmark/results/latest.json
```

## What the package provides

- generational entity IDs and world/entity wrappers
- archetype-based component storage and migration
- object components for straightforward modeling
- extension/facade components backed by typed columns for hot data paths
- resources, deferred command queues, and explicit flush semantics
- schedules, systems, plugins, and event channels
- query helpers, query caching, and structural topology revisions
- benchmark scripts and local scorecard artifacts

Start with object components; move hot numeric state to extension components
when GC pressure or iteration speed matters. See
[`core_packages/ecsly/README.md`](core_packages/ecsly/README.md) for usage
patterns, SIMD columns, and example walkthroughs.

## Documentation

| Doc | Audience | Purpose |
| --- | --- | --- |
| [`core_packages/ecsly/README.md`](core_packages/ecsly/README.md) | Developers | Install, examples, benchmarks, API lanes |
| [`core_packages/ecsly/DX_FAQ.md`](core_packages/ecsly/DX_FAQ.md) | Developers & agents | How-to patterns and terminology |
| [`core_packages/ecsly/DESIGN_FAQ.md`](core_packages/ecsly/DESIGN_FAQ.md) | Contributors | Architecture trade-offs and invariants |
| [`core_packages/ecsly_app/README.md`](core_packages/ecsly_app/README.md) | App developers | App actions, drafts, invalidation, cold lookup |
| [`core_packages/ecsly_codegen/README.md`](core_packages/ecsly_codegen/README.md) | Package authors | Typed-column factory code generation |
| [`core_packages/ecsly_flutter/README.md`](core_packages/ecsly_flutter/README.md) | Flutter developers | Scope, controller, selectors, actions, loops |
| [`core_packages/ecsly/doc/ecs_architecture_diagram.md`](core_packages/ecsly/doc/ecs_architecture_diagram.md) | Contributors | Internal layout reference |
| [`core_packages/ecsly/CHANGELOG.md`](core_packages/ecsly/CHANGELOG.md) | Everyone | Release notes |
| [API docs on pub.dev](https://pub.dev/documentation/ecsly/latest/) | Developers | Generated reference |

Runnable examples live under `core_packages/ecsly/example/`:

- `basic_world.dart` — smallest object-component flow
- `scheduled_run.dart` — schedule + extension component
- `extension_component.dart` — marker component + typed facade
- `commands_and_resources.dart` — deferred commands and resources
- `simd_columns.dart` — stride-4 `FloatColumn` and SIMD view

## For coding agents

Read [`AGENTS.md`](AGENTS.md) before changing code. Summary:

**In scope:** migrated packages under `core_packages/`. Keep Flutter out of
`core_packages/ecsly`; Flutter bindings belong in `core_packages/ecsly_flutter`.

**Hot-loop rules:** store hot data in typed columns (`Float32List`, `Int32List`,
…); avoid per-entity heap allocations in hot systems; structural changes go
through the command queue and `flush()`.

**Source layout:**

```
core_packages/ecsly/lib/src/
  archetypes/   component storage and entity migration
  entities/     generational IDs and world entity wrappers
  components/   registries, queries, columns, SIMD helpers
  commands/     deferred structural changes
  systems/      schedules and execution
  events/       event channels and typed storage
  world/        World entry point
```

**After changes:**

| Change type | Update |
| --- | --- |
| Archetypes, flush, query semantics | `DESIGN_FAQ.md`, `doc/ecs_architecture_diagram.md` |
| Public usage patterns | `DX_FAQ.md` |
| User-facing package behavior | `core_packages/ecsly/README.md`, `CHANGELOG.md` |

**Contributions:** safe when they target packages already in this repo. Do not
add references to packages, plugins, or tools that are not present here.

## Package chooser

| Need | Package | Public source | Hosted status |
| --- | --- | --- | --- |
| Pure ECS runtime, systems, queries, commands | `ecsly` | `core_packages/ecsly` | Published prerelease |
| App actions, drafts, invalidation, cold lookup | `ecsly_app` | `core_packages/ecsly_app` | Unpublished prerelease |
| Typed-column factory generation | `ecsly_codegen` | `core_packages/ecsly_codegen` | Unpublished prerelease |
| Flutter scope, controller, selectors, loops | `ecsly_flutter` | `core_packages/ecsly_flutter` | Unpublished prerelease |

Publication to pub.dev is tracked separately from moving source into this repo.

## License

Dual-licensed under [MIT](LICENSE-MIT) and [Apache-2.0](LICENSE-APACHE).
