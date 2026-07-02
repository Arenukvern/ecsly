# ecsly_app DX_FAQ - Memory Palace

Developer notes for app-layer workflows on ecsly worlds.

**Requires `ecsly` `>=0.0.1-dev.9`.** `ecsly_app` is a published prerelease;
see [README.md](README.md) for hosted and workspace setup.

## Quick setup

```yaml
dependencies:
  ecsly: ^0.0.1-dev.9
  ecsly_app: ^0.1.0-dev.1
```

```dart
import 'package:ecsly_app/ecsly_app.dart';
```

Flutter apps usually import `package:ecsly_flutter/ecsly_flutter.dart`, which
re-exports `ecsly_app`.

## Package chooser

| Need | Package | Status |
|------|---------|--------|
| Systems, queries, hot loops | `ecsly` | Public package |
| Actions, drafts, invalidation, cold lookup | `ecsly_app` | Published prerelease |
| Typed-column builders | `ecsly_codegen` | Published prerelease |
| Widgets, scope, controller | `ecsly_flutter` | Published prerelease |

## First action

```dart
class SeedAction extends EcsAction<void> {
  const SeedAction();

  @override
  void run(final EcsActionContext context) {
    context.upsertResource(CounterResource(0));
  }
}

final runner = EcsActionRunner(world: world);
await runner.run(
  const SeedAction(),
  onChanged: ({final flush = true, final invalidation}) {
    if (flush) world.flush();
  },
);
```

Prefer `context.mutateResource` and `context.upsertComponent` so hosts get
narrow `EcsInvalidationBatch` hints.

## Drafts

```dart
world.upsertResource(EcsDraftsResource());
final draft = world.getResource<EcsDraftsResource>().draft<String>(
  'profile.name',
  original: 'Ada',
);
draft.current = 'Grace';
draft.touch('name');
```

Drafts are headless. Flutter widgets bind to them; actions commit on submit.

## Entity index projection

```dart
world.upsertResource(EntityIndexResource<TodoIds, String>());
// In spawn action:
index.upsert(todoId, entity);
context.invalidateResource<EntityIndexResource<TodoIds, String>>();
// On despawn: index.remove(todoId) — manual maintenance required
```

Stable ids live on components. The index is a cold lookup cache only.

## Host schedules

```dart
const afterAction = EcsHostSchedule(
  'app.after_action',
  runWhen: (final invalidation) =>
      invalidation.matchesResourceType(TodoUiResource),
);
```

`EcsHostSchedule` is metadata. Hosts (`ecsly_flutter`) decide when to run named
schedules after actions complete.

## Cold lookup

```dart
final entity = world.maybeFindEcsEntityWithComponent<TodoId>(
  where: (final _, final id) => id.value == routeId,
);
```

Scans archetypes — use for UI/routes, not per-frame simulation.

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| Host rebuilds everything after action | Action used raw `context.world` without `invalidate*`; default is broad |
| UI stale after action | Pass `onChanged` and flush the world when `flush: true` |
| `ComponentNotRegisteredError` | Register components before actions spawn or query them |
| Index points at despawned entity | Remove or update index entries in despawn actions |
| Slow route lookups in hot loop | Move to query cache or system iteration; index/lookup are cold path |
| Unsure which import to use | Simulation plugin → `ecsly`; app host → `ecsly_app` or `ecsly_flutter` |
