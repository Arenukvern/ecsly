# ecsly_app

Pure Dart app-layer helpers for [`ecsly`](https://pub.dev/packages/ecsly).

`ecsly_app` sits between the headless ECS runtime and host packages such as
[`ecsly_flutter`](../ecsly_flutter/README.md). It owns app workflows
and derived infrastructure that are not core simulation machinery.

**Status:** published prerelease. Pin the `dev` version deliberately.

**Compatibility:** `ecsly_app` `0.1.0-dev.x` requires `ecsly` `>=0.0.1-dev.9`.

Further docs: [DX_FAQ.md](DX_FAQ.md) (how) · [DESIGN_FAQ.md](DESIGN_FAQ.md) (why)

## Install

```yaml
dependencies:
  ecsly: ^0.0.1-dev.9
  ecsly_app: ^0.1.0-dev.1
```

```dart
import 'package:ecsly_app/ecsly_app.dart';
```

This package re-exports `package:ecsly/ecsly.dart` for one-import app hosts.
Simulation-only packages may depend on `ecsly` alone.

Monorepo/workspace packages may use key-only entries (`ecsly:` / `ecsly_app:`)
or local path overrides while developing multiple packages together.

## Package chooser

| Need | Package | Public status |
|------|---------|---------------|
| Hot simulation | `ecsly` | Public package |
| Cold app path | `ecsly_app` | Published prerelease |
| Typed-column builders | `ecsly_codegen` | Published prerelease |
| Flutter host | `ecsly_flutter` | Published prerelease |

Keep hot simulation in `ecsly` systems and queries. Keep widgets and tickers in
host packages. Stable app ids belong on normal components; indexes are optional
projections, not ECS identity.

## Quick start

```dart
class CounterResource extends Resource {
  CounterResource(this.value);
  int value;
}

class IncrementAction extends EcsAction<int> {
  const IncrementAction();

  @override
  int run(final EcsActionContext context) {
    context.mutateResource<CounterResource>((final counter) {
      counter.value += 1;
    });
    return context.getResource<CounterResource>().value;
  }
}

Future<void> main() async {
  final world = World()..upsertResource(CounterResource(0));
  final runner = EcsActionRunner(world: world);

  final result = await runner.run(
    const IncrementAction(),
    onChanged: ({final flush = true, final invalidation}) {
      if (flush) world.flush();
    },
  );

  print('counter=$result');
}
```

See [example/main.dart](example/main.dart) for invalidation hints and status.

## What this package provides

- `EcsAction` and `EcsActionRunner` for reusable app/use-case workflows
- `EcsInvalidationBatch` and mutation helpers for host refresh hints
- `EcsDraft` and `EcsDraftsResource` for headless edit state
- cold component lookup helpers on `World`
- `EntityIndexResource<TScope, K>` for optional typed id-to-entity projections
- `EcsHostSchedule` metadata for host schedule wiring

## Actions and invalidation

Use `EcsAction` for hydration, save, submit, toggle, optimistic sync, and
feature-owned entity creation:

```dart
class ToggleTodoAction extends EcsAction<void> {
  const ToggleTodoAction(this.entity);

  final Entity entity;

  @override
  void run(final EcsActionContext context) {
    final done = context.getComponent<TodoDone>(entity: entity);
    context.upsertComponent(entity, TodoDone(value: !done.value));
  }
}

class ChangeFilterAction extends EcsAction<void> {
  const ChangeFilterAction(this.showDone);

  final bool showDone;

  @override
  void run(final EcsActionContext context) {
    context.mutateResource<TodoUiResource>((final ui) {
      ui.showDone = showDone;
    });
  }
}
```

Raw `context.world` access stays available for advanced or bulk operations. When
you use it, call `context.invalidate(...)`, `invalidateResource<T>()`, or
`invalidateComponent<T>()` yourself. If an action does not provide any explicit
hint, hosts must treat the mutation as broad.

Store edit drafts on the world:

```dart
world.upsertResource(EcsDraftsResource());
final titleDraft = world.getResource<EcsDraftsResource>().draft<String>(
  'todo.title',
  original: 'Buy milk',
);
```

## Entity indexes are projections

`EntityIndexResource<TScope, K>` is experimental, data-only lookup
infrastructure. The stable id itself still belongs on a normal component.
Feature actions must maintain the index when they spawn, despawn, or change ids:

```dart
Entity spawnTodo(final EcsActionContext context, final String id, final String title) {
  final entity = context.spawnComponents([
    TodoId(id),
    TodoTitle(title),
  ]);
  context.getResource<EntityIndexResource<TodoIds, String>>().upsert(
    id,
    entity,
  );
  context.invalidateResource<EntityIndexResource<TodoIds, String>>();
  return entity;
}
```

Do not treat the index as core ECS identity or an auto-maintained registry.

## Cold lookup caveat

`findEcsEntityWithComponent` scans matching archetypes. Use it for screens,
routes, and app actions — not hot simulation loops. Hot systems should use
cached queries.

## Flutter and other hosts

- **Flutter apps:** prefer [`ecsly_flutter`](../ecsly_flutter/README.md),
  which re-exports `ecsly_app` and wires `EcsController` / selectors.
- **Jaspr, CLI, tests:** use `ecsly_app` directly with `EcsActionRunner`.

## Related packages

- [`ecsly`](https://pub.dev/packages/ecsly) — ECS runtime
- [`ecsly_codegen`](../ecsly_codegen/README.md) — typed-column codegen
- [`ecsly_flutter`](../ecsly_flutter/README.md) — Flutter host bridge
