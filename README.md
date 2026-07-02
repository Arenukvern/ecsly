<div align="center">

<img src="core_packages/ecsly/assets/brand/ecsly-logo.png" alt="ecsly logo" width="180">

# ecsly

_Experimental ECS packages for Dart and Flutter._

[![pub: ecsly](https://img.shields.io/pub/v/ecsly.svg?include_prereleases)](https://pub.dev/packages/ecsly)
[![Release validation](https://github.com/Arenukvern/ecsly/actions/workflows/release-validation.yml/badge.svg?branch=main)](https://github.com/Arenukvern/ecsly/actions/workflows/release-validation.yml)
[![Release Please](https://github.com/Arenukvern/ecsly/actions/workflows/release-please.yml/badge.svg?branch=main)](https://github.com/Arenukvern/ecsly/actions/workflows/release-please.yml)
[![Publish pub.dev package](https://github.com/Arenukvern/ecsly/actions/workflows/pub-publish.yml/badge.svg?branch=main)](https://github.com/Arenukvern/ecsly/actions/workflows/pub-publish.yml)
[![Docs](https://img.shields.io/badge/docs-docs.page-blue)](https://docs.page/arenukvern/ecsly)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE-MIT)
[![License: Apache-2.0](https://img.shields.io/badge/License-Apache--2.0-blue.svg)](LICENSE-APACHE)
[![All Contributors](https://img.shields.io/github/all-contributors/Arenukvern/ecsly?color=ee8449&style=flat-square)](#contributors)
[![maintained with Skill Steward](https://raw.githubusercontent.com/Arenukvern/skill_steward/main/docs/brand/assets/svg/badge-light.svg)](https://github.com/Arenukvern/skill_steward)

</div>

`ecsly` is a public prerelease package family for building data-oriented Dart
and Flutter applications. It currently provides a pure Dart ECS runtime, an app
workflow layer, typed-column code generation, and a Flutter bridge.

The honest status: `ecsly` is early R&D, not a finished game engine. The North
Star is a practical Dart game-engine stack over time, but only the packages in
this public repository are canonical here.

Repo charter: [docs/NORTH_STAR.mdx](docs/NORTH_STAR.mdx). Repo-wide why/how:
[docs/DESIGN_FAQ.mdx](docs/DESIGN_FAQ.mdx) and
[docs/DX_FAQ.mdx](docs/DX_FAQ.mdx).

## Choose Your Path

| I want to... | Start here | Use |
| --- | --- | --- |
| Try the core ECS runtime | [Quick start](#quick-start) | `ecsly` |
| Build game/simulation logic | [For game dev](#for-game-dev) | `ecsly`, optional `ecsly_codegen` |
| Build app workflows and Flutter UI | [For app dev](#for-app-dev) | `ecsly_app`, `ecsly_flutter` |
| Contribute or maintain releases | [For maintainers](#for-maintainers) | `AGENTS.md`, Steward, Release Please |
| Browse hosted docs | [docs.page/arenukvern/ecsly](https://docs.page/arenukvern/ecsly) | Docs map and package routes |

## Quick Start

Requirements: Dart SDK `>=3.12.0`.

```sh
dart pub get
cd core_packages/ecsly
dart run example/main.dart
```

Add the core runtime:

```yaml
dependencies:
  ecsly: ^0.0.1-dev.10
```

The core package is pure Dart. It does not depend on Flutter.

## For Game Dev

Use `ecsly` when you want explicit entity/component storage, systems, schedules,
resources, events, deferred commands, and hot-path data layouts.

Good first examples:

| Example | Shows |
| --- | --- |
| [`basic_world.dart`](core_packages/ecsly/example/basic_world.dart) | Smallest object-component flow |
| [`scheduled_run.dart`](core_packages/ecsly/example/scheduled_run.dart) | Systems and schedules |
| [`extension_component.dart`](core_packages/ecsly/example/extension_component.dart) | Typed facade over hot data |
| [`commands_and_resources.dart`](core_packages/ecsly/example/commands_and_resources.dart) | Deferred commands and resources |
| [`simd_columns.dart`](core_packages/ecsly/example/simd_columns.dart) | Stride-4 `FloatColumn` and SIMD views |

Start with object components. Move hot numeric state into typed columns only
when allocation pressure or iteration speed matters.

## For App Dev

Use the companion packages when ECS state needs to connect to app workflows,
identity, invalidation, and Flutter widgets.

| Need | Package |
| --- | --- |
| Actions, drafts, invalidation, cold lookup, entity-id projections | [`ecsly_app`](core_packages/ecsly_app/) |
| Flutter scope, controller, selectors, actions, frame loops | [`ecsly_flutter`](core_packages/ecsly_flutter/) |
| Typed-column factory generation | [`ecsly_codegen`](core_packages/ecsly_codegen/) |

The companion packages are published prereleases. Treat the `dev` channel as
early integration surface and pin versions deliberately.

## Packages

| Package | Version | Pub.dev | Role |
| --- | --- | --- | --- |
| `ecsly` | `0.0.1-dev.10` | [![pub package](https://img.shields.io/pub/v/ecsly.svg?include_prereleases)](https://pub.dev/packages/ecsly) | Pure ECS runtime, systems, queries, commands, resources, events, benchmarks |
| `ecsly_app` | `0.1.0-dev.1` | [![pub package](https://img.shields.io/pub/v/ecsly_app.svg?include_prereleases)](https://pub.dev/packages/ecsly_app) | Pure Dart app workflow layer |
| `ecsly_codegen` | `0.1.0-dev.1` | [![pub package](https://img.shields.io/pub/v/ecsly_codegen.svg?include_prereleases)](https://pub.dev/packages/ecsly_codegen) | Typed-column factory annotations and builder |
| `ecsly_flutter` | `0.1.0-dev.1` | [![pub package](https://img.shields.io/pub/v/ecsly_flutter.svg?include_prereleases)](https://pub.dev/packages/ecsly_flutter) | Flutter bindings for ECS worlds and app workflows |

Package docs:

- [`ecsly` README](core_packages/ecsly/README.md)
- [`ecsly_app` README](core_packages/ecsly_app/README.md)
- [`ecsly_codegen` README](core_packages/ecsly_codegen/README.md)
- [`ecsly_flutter` README](core_packages/ecsly_flutter/README.md)
- [API docs on pub.dev](https://pub.dev/documentation/ecsly/latest/)

## What Exists Now

- Generational entity IDs and world/entity wrappers.
- Archetype-based component storage and migration.
- Object components for straightforward modeling.
- Extension/facade components backed by typed columns for hot data paths.
- Resources, deferred command queues, and explicit `flush()` semantics.
- Schedules, systems, plugins, and event channels.
- Query helpers, query caching, and topology revisions.
- Benchmark scripts and local scorecard artifacts.
- Flutter selectors, actions, and loop widgets through companion packages.

Non-claims:

- This is not yet a complete game engine.
- The public repo is intentionally smaller than private/internal workspaces.
- Packages or tools absent from this repo are not public contracts.
- A green Steward check is routing/contract proof, not runtime product proof.

## For Maintainers

Read [AGENTS.md](AGENTS.md) before changing code.

Main validation loop:

```sh
dart pub get
cd core_packages/ecsly
dart analyze
dart test
dart pub publish --dry-run
```

Companion checks:

```sh
cd core_packages/ecsly_app && dart test
cd core_packages/ecsly_codegen && dart test
cd core_packages/ecsly_flutter && flutter test
```

Release and Steward commands:

```sh
just
just check
just release-check
steward doctor --json
steward probe --profile quick --json
```

Release automation uses Release Please and tags shaped like
`<package>-v<version>`, for example `ecsly-v0.0.1-dev.11`.

## Contributing

Contributions are welcome when they target packages and docs already present in
this public repo.

- Contributor guide: [CONTRIBUTING.md](CONTRIBUTING.md)
- Pull request checklist: [.github/pull_request_template.md](.github/pull_request_template.md)
- Contributor credit: [docs/contributing/contributors.mdx](docs/contributing/contributors.mdx)
- Security reports: [GitHub security advisories](https://github.com/Arenukvern/ecsly/security/advisories/new)

## Contributors

Thanks to everyone who helps improve `ecsly`.

This roster is maintained with [all-contributors](https://allcontributors.org/).
Use the all-contributors bot or CLI from a pull request:

```sh
npx all-contributors-cli add <github-login> code,doc
npx all-contributors-cli generate
```

<!-- ALL-CONTRIBUTORS-LIST:START - Do not remove or modify this section -->
<!-- prettier-ignore-start -->
<!-- markdownlint-disable -->
<!-- markdownlint-restore -->
<!-- prettier-ignore-end -->

<!-- ALL-CONTRIBUTORS-LIST:END -->

## License

Dual-licensed under [MIT](LICENSE-MIT) and [Apache-2.0](LICENSE-APACHE).
