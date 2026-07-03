# Changelog

## [0.1.0-dev.2](https://github.com/Arenukvern/ecsly/compare/ecsly_flutter-v0.1.0-dev.1...ecsly_flutter-v0.1.0-dev.2) (2026-07-02)


### Documentation

* clarify ecsly resource boundaries and release automation ([371dfec](https://github.com/Arenukvern/ecsly/commit/371dfec85e3dc8ff59fca0ca2b6edde4de2b1d8f))
* mark companion packages published ([ff4192a](https://github.com/Arenukvern/ecsly/commit/ff4192a6c6f69e247b5053dd4bdba5c039228b6e))

## 0.1.0-dev.1

- Initial public prerelease aligned with `ecsly` `0.0.1-dev.x` and
  `ecsly_app` `0.1.0-dev.x`.
- **Compatibility:** requires `ecsly >=0.0.1-dev.9`, `ecsly_app ^0.1.0-dev.1`,
  Flutter `>=3.35.0`.
- Reexported pure Dart app helpers from `package:ecsly_app`; Flutter now owns
  host glue while actions, drafts, cold lookup, and id projections live in the
  app package.
- Delegated action execution/status bookkeeping to `EcsActionRunner`.
- Added tracked-change filtering for resource/component selectors and optional
  `EcsWorldSelectorDependencies` hints. Unknown in-place mutations still
  refresh conservatively.
- Added the first official Flutter bridge package for ecsly.
- Added `EcsScope`, `EcsController`, resource/component builders and selectors,
  context helpers, `EcsAction`, `EcsActionBuilder`, `EcsDraft`, and optional loop
  widgets for app and game hosts.
- Added `EcsActionOnMount` and `EcsActionStatusSelector` for startup hydration
  and status-only UI.
- Added `EcsWorldSelector` for derived UI values that combine multiple ECS
  resources/components.
- Added optional-entity component lookup helpers for screens/actions that resolve
  ECS state from stable app data such as selected ids or route ids.
- Added action-context bundle spawning helpers and a loop-free, component-first
  example app that hydrates after `runApp`.
- Renamed public frame schedule terminology from `vsync` to `flutterFrame` and
  clarified that the bridge proves Flutter engine frame pacing, not renderer
  presentation.
- Added host-declared frame schedule invalidation for `EcsLoop`,
  `EcsFixedStepLoop`, and `EcsFrameSchedule`.
- Release packaging: SPDX MIT license, pub.dev metadata, README install/API lanes,
  `example/pubspec.yaml`, `AGENTS.md`, CI publish dry-run gate.
