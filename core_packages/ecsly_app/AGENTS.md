# ecsly_app: Agent Working Agreement

## Goal

Pure Dart app-layer contracts for ecsly: actions, drafts, invalidation hints,
cold lookup, and optional id projections. No Flutter dependency.

## Package boundary

- **Owns:** `EcsAction`, `EcsActionRunner`, `EcsDraft`, `EcsInvalidationBatch`,
  `EcsComponentLookupX`, `EntityIndexResource`, `EcsHostSchedule`.
- **Re-exports:** `package:ecsly/ecsly.dart` for app-host one-import DX.
- **Does not own:** Widgets, tickers, `BuildContext` helpers (`ecsly_flutter`);
  hot simulation (`ecsly` systems/queries).

## Consumer workflow

1. Add `ecsly` + `ecsly_app` to `dependencies`.
2. Register components/resources on `World`.
3. Define `EcsAction` subclasses; run via `EcsActionRunner`.
4. Use mutation helpers for narrow invalidation hints.
5. Flutter hosts: prefer `ecsly_flutter` for scope/controller/widgets.

See [DX_FAQ.md](DX_FAQ.md) for drafts, indexes, schedules, troubleshooting.

## Compatibility

- `ecsly_app` `0.1.0-dev.x` requires `ecsly` `>=0.0.1-dev.9`.
- Publication status: published prerelease on pub.dev.
- Public API: `package:ecsly_app/ecsly_app.dart` (includes ecsly re-export).

## Testing

```bash
cd core_packages/ecsly_app && dart test
dart run example/main.dart
dart pub publish --dry-run
```

## Docs to update

- API / usage → [DX_FAQ.md](DX_FAQ.md) + [README.md](README.md)
- Boundary / design → [DESIGN_FAQ.md](DESIGN_FAQ.md)
- Release → [CHANGELOG.md](CHANGELOG.md)

## Reference consumers in repo

- [ecsly_flutter](../ecsly_flutter) — Flutter host re-export and widget tests
