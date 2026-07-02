# Changelog

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
