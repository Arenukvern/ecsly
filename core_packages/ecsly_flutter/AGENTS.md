# ecsly_flutter: Agent Working Agreement

## Goal

Thin Flutter bridge for ecsly worlds: scope, controller, selective rebuilds,
action widgets, and optional frame loops. Not a game framework.

## Package boundary

- **Owns:** `EcsScope`, `EcsController`, selectors/builders, `BuildContext` ECS
  helpers, `EcsActionOnMount`, `EcsLoop` / `EcsFixedStepLoop`,
  `EcsFlutterSchedules`, selector invalidation wiring.
- **Re-exports:** `package:ecsly_app/ecsly_app.dart` (actions, drafts, lookup).
- **Does not own:** Renderers, input/camera/collision plugins, MCP bootstrap,
  storage/network clients, domain simulation systems.

## Consumer workflow

1. Add `ecsly`, `ecsly_app`, `ecsly_flutter` + Flutter SDK to `dependencies`.
2. Build `World`, register components, optional `Plugin`s.
3. Wrap app in `EcsScope` + `EcsController`.
4. Hydrate with `EcsActionOnMount` after `runApp`, not before.
5. Use selectors for UI; run mutations via `context.runEcsAction` or controller
   transactions.
6. Add `EcsLoop` only when a frame driver is needed.

See [DX_FAQ.md](DX_FAQ.md) for forms, plugins, invalidation, and troubleshooting.

## Compatibility

- `ecsly_flutter` `0.1.0-dev.x` requires `ecsly` `>=0.0.1-dev.9`, `ecsly_app`
  `^0.1.0-dev.1`, Flutter `>=3.35.0`.
- Publication status: published prerelease on pub.dev.
- Public API: `package:ecsly_flutter/ecsly_flutter.dart`.

## Testing

```bash
cd core_packages/ecsly_flutter && flutter test
cd example && flutter run   # manual smoke
just profile-flutter-selectors   # selector invalidation artifact (repo root)
flutter pub publish --dry-run
```

Selector regression gate: `build/reports/selector_invalidation_profile.v1.json`.

## Docs to update

- API / usage → [DX_FAQ.md](DX_FAQ.md) + [README.md](README.md)
- Boundary / design → [DESIGN_FAQ.md](DESIGN_FAQ.md)
- Release → [CHANGELOG.md](CHANGELOG.md)

## Reference in repo

- [example/lib/main.dart](example/lib/main.dart) — todo app with hydration + selectors
- [ecsly_app](../ecsly_app) — headless app contracts consumed by this package
