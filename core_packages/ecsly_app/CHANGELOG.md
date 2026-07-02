# Changelog

## [0.1.0-dev.2](https://github.com/Arenukvern/ecsly/compare/ecsly_app-v0.1.0-dev.1...ecsly_app-v0.1.0-dev.2) (2026-07-02)


### Documentation

* clarify ecsly resource boundaries and release automation ([371dfec](https://github.com/Arenukvern/ecsly/commit/371dfec85e3dc8ff59fca0ca2b6edde4de2b1d8f))
* mark companion packages published ([ff4192a](https://github.com/Arenukvern/ecsly/commit/ff4192a6c6f69e247b5053dd4bdba5c039228b6e))

## 0.1.0-dev.1

- Initial public prerelease aligned with `ecsly` `0.0.1-dev.x` and
  `ecsly_flutter` `0.1.0-dev.x`.
- **Compatibility:** requires `ecsly >=0.0.1-dev.9`.
- Added pure Dart app-layer package for actions, drafts, cold component lookup,
  and typed entity-id projections.
- Added `EcsActionRunner` for non-Flutter hosts with status in
  `EcsActionStatusResource`.
- Added `EcsActionContext.mutateResource` and `upsertComponent` helpers for
  narrow invalidation hints.
- Moved lookup and experimental `EntityIndexResource` out of `ecsly_flutter`.
- Release packaging: SPDX MIT license, pub.dev metadata, README quick-start,
  `example/`, DX/DESIGN FAQs, `AGENTS.md`, and CI publish dry-run gate.
