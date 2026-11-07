# Changelog

## Unreleased

- Add `WorldSnapshotRestoreMode.reconcile` and `reconcileWorldSnapshot` for
  in-place restore by `PersistentId` (component set reconciliation, despawn
  absent persisted entities, leave non-persistent entities untouched).

## [0.1.0-dev.4](https://github.com/Arenukvern/ecsly/compare/ecsly_serialization-v0.1.0-dev.3...ecsly_serialization-v0.1.0-dev.4) (2026-11-07)


### Documentation

* ecsly_serialization and ecsly_replay are on pub.dev ([57df2a8](https://github.com/Arenukvern/ecsly/commit/57df2a8de68f36a64c7d58586ed561ff2b49920c))

## [0.1.0-dev.3](https://github.com/Arenukvern/ecsly/compare/ecsly_serialization-v0.1.0-dev.2...ecsly_serialization-v0.1.0-dev.3) (2026-11-07)


### Bug Fixes

* align workspace ecsly constraints with 0.1.0-dev.13; guard unpublished plugins ([b6bfef6](https://github.com/Arenukvern/ecsly/commit/b6bfef612134ef4d29f4006953fbb90648e4524e))


### Documentation

* align package READMEs and FAQs with the repositioned voice ([936f0b7](https://github.com/Arenukvern/ecsly/commit/936f0b75c58a354bb77b5d287fa59b693a1b375a))
* **plugins:** align plugin READMEs with reality; add missing world_zones README ([57055c7](https://github.com/Arenukvern/ecsly/commit/57055c7fcba28676f8f658c054c329a342167a5c))

## [0.1.0-dev.2](https://github.com/Arenukvern/ecsly/compare/ecsly_serialization-v0.1.0-dev.1...ecsly_serialization-v0.1.0-dev.2) (2026-10-27)


### Features

* **ecsly_replay:** add replay log, checkpoints, and reconcile restore ([57be21e](https://github.com/Arenukvern/ecsly/commit/57be21ece4ae367c22a7f64fd4ef8d21e138eaf6))
* **ecsly_replay:** world replay log, checkpoints, and seek ([5976a5f](https://github.com/Arenukvern/ecsly/commit/5976a5f782fc87de431dd7b24f34e8c9c9badedf))
* north star +example ([86b4d2c](https://github.com/Arenukvern/ecsly/commit/86b4d2c3dd89042fea06500f68a4118e6795cee9))
* serialization / deserialization plugin ([001b892](https://github.com/Arenukvern/ecsly/commit/001b8922c2d378cf3415afd4f19914450763bc58))


### Bug Fixes

* **ci:** unblock wip-loop validation for Dart 3.13 and publish preflight ([77b3f8d](https://github.com/Arenukvern/ecsly/commit/77b3f8d12f1c32e512ad5e66a849c2dd57deece7))

## 0.1.0-dev.1

- Initial public prerelease of JSON world snapshots for ecsly (resources,
  entities, and SoA component columns).
