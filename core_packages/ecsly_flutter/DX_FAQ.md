# ecsly_flutter DX_FAQ

`ecsly_flutter` is a published prerelease. Use hosted constraints for consumers
and workspace/local dependency setup for repo development.

## Package chooser

| Need | Package | Status |
|------|---------|--------|
| Systems, queries, hot loops | `ecsly` | Public package |
| Actions, drafts, invalidation, cold lookup | `ecsly_app` | Published prerelease |
| Typed-column builders | `ecsly_codegen` | Published prerelease |
| Widgets, scope, controller | `ecsly_flutter` | Published prerelease |

## Do apps need a game loop?

No. Apps can mutate resources/entities from callbacks, actions, async loads,
streams, or lifecycle hooks, then notify through `EcsController`.

Use `EcsLoop` or `EcsFixedStepLoop` only where a frame driver is needed.

## Should I fill the world before `runApp`?

Register component types, install plugins, and upsert tiny resources before
`runApp` if needed. Do not load or seed domain records there.

Use `EcsActionOnMount` for app hydration so startup work is an idempotent
`EcsAction` with normal status, flushing, and notification behavior.

```dart
EcsScope(
  world: world,
  controller: controller,
  child: const EcsActionOnMount(
    action: HydrateTodosAction(),
    child: TodoScreen(),
  ),
);
```

## Should app state be a resource or a component?

Use components for repeated/domain records and per-entity state: todos, form
sections, content blocks, selected items, dirty flags, load requests, item
status, position, layout, and tags.

Use resources for true world singletons: clocks, config, selected ids, filters,
small indexes, action status, sync status, caches, queues, and host/session
coordination.

If a resource grows a `Map<Entity, DomainState>` plus business rules, split it
into components and small resources.

## How do I create an entity with multiple app components?

Use a component bundle through `EcsActionContext.spawnComponents` or core
`world.spawnComponents`. This queues one bundled structural spawn and returns
the entity id.

```dart
final entity = context.spawnComponents([
  TodoId(id),
  TodoTitle(title),
  const TodoDone(value: false),
]);
```

Use core `world.batchSpawn(bundle, count)` only when many entities share the
same bundle semantics. For distinct object-component data, spawn one bundle per
record and let the controller notify once after the action or transaction.

## Why do context helpers still say `Ecs`?

The bridge keeps ECS semantics visible. Use:

- `context.ecs`
- `context.getEcsResource<T>()`
- `context.readEcsResource<T>()`
- `context.selectEcsResource<T, R>(...)`
- `context.getEcsComponent<T>(entity: entity)`
- `context.readEcsComponent<T>(entity: entity)`
- `context.findEcsEntityWithComponent<T>(where: ...)`
- `context.selectEcsComponent<T, R>(..., entity: entity)`
- `context.runEcsAction(action)`

The package avoids unqualified `context.watch<T>()` and `context.read<T>()`
because ecsly rebuilds are controlled by `EcsController` notifications and
explicit transactions/actions.

## How do I avoid rebuilding too much UI?

Prefer component selectors for entity state:

```dart
EcsComponentSelector<TodoTitle, String>(
  entity: todo,
  select: (title) => title.value,
  builder: (context, value) => Text(value),
);
```

Use `EcsResourceSelector<T, R>` for small global state. Select a small immutable
value and provide `equals` when the selected value needs custom comparison.

Use `EcsWorldSelector<R>` when one UI value is derived from multiple ECS slices,
such as an ordered visible entity list that depends on a resource and per-entity
components. Prefer narrower resource/component selectors when one slice is
enough.

## Do I need an Entity to read a component from Flutter?

No. Pass `entity:` when the widget already has one. Pass `where:` when the UI
starts from app data such as a route id, selected id, slug, document id, or
current editor target.

```dart
final title = context.selectEcsComponent<TodoRecord, String>(
  (todo) => todo.title,
  where: (entity, todo) => todo.id == selectedTodoId,
);
```

Use `context.findEcsEntityWithComponent<T>()` or
`world.findEcsEntityWithComponent<T>()` for cold app/UI lookups when the
resolved entity matters for follow-up actions. The implementation lives in
`package:ecsly_app` and is reexported by `ecsly_flutter`; it is not core ecsly
identity. Stable ids should be normal components. If route ids, selected ids,
draft ids, feed item ids, or map item ids need repeated lookup, add a small
typed app/plugin projection instead of treating the index as identity.

```dart
final class TodoIds {
  const TodoIds._();
}

final entity = context
    .getEcsResource<EntityIndexResource<TodoIds, String>>()
    .entityOf(selectedTodoId);
final title = context.getEcsComponent<TodoTitle>(entity: entity);
```

Predicate lookup is a UI/app convenience, not the hot ECS path. Game systems and
frame-rate simulation should stay on ecsly query/raw chunk APIs.

## How do selectors know what changed?

`EcsScope` uses Flutter `InheritedModel` aspects and app-layer
`EcsInvalidationBatch` hints. Core ECS stays summary-free; Flutter selectors
refresh broadly for unknown transactions and selectively when callers provide
resource/component/structural invalidation batches.

`EcsWorldSelector` can also take `EcsWorldSelectorDependencies` when its derived
value depends on known resources/components:

```dart
EcsWorldSelector<List<Entity>>(
  dependencies: const EcsWorldSelectorDependencies(
    resourceTypes: [TodoUiResource],
    componentTypes: [TodoTitle, TodoDone],
    structural: true,
  ),
  select: visibleTodos,
  builder: (context, entities) => TodoList(entities),
);
```

If a transaction omits an invalidation batch, Flutter refreshes conservatively
instead of skipping. Pass `EcsInvalidationBatch.resource<T>()` or
`EcsInvalidationBatch.component<T>(entity: entity)` for narrow rebuilds.

Frame loops follow the same rule. `EcsLoop`, `EcsFixedStepLoop`, and
`EcsFrameSchedule` broad-invalidate when no schedule invalidation hint is
provided. If the host owns the schedule and knows the UI-facing mutation slice,
pass a component/resource/structural `EcsInvalidationBatch`. The loop always
merges in `DeltaTimeResource` and `ScheduleTimeResource` because it updates
those resources every tick.

## What does `EcsFrameSchedule.flutterFrame` mean?

It means the schedule runs from Flutter's ticker/frame machinery. The bridge
creates a Flutter `Ticker`; Flutter `Ticker` is driven by
`SchedulerBinding.scheduleFrameCallback`, whose transient callbacks run from
`SchedulerBinding.handleBeginFrame`. `SchedulerBinding.scheduleFrame` normally
asks the engine for a frame serviced by the operating system's conceptual frame
signal. Flutter warm-up and forced frames can bypass normal frame pacing.

Flutter engine platform evidence: iOS uses `CADisplayLink`, Android uses
`Choreographer`, and web uses `requestAnimationFrame`.

This is engine frame pacing, not renderer surface-present proof. If a game
renderer needs a frame proof claim, keep that proof at the backend boundary that
can show acquire, submit, and present evidence.

## How do I measure selector invalidation?

Use the counter profile before opening DevTools:

```sh
just profile-flutter-selectors
```

This runs `test/selector_invalidation_profile_test.dart`, writes
`build/reports/selector_invalidation_profile.v1.json`, and validates that
unrelated aspects do not call selector functions or selector builders while
matching or broad invalidations call each exactly once. The artifact separates:

- controller notification count;
- selector function calls;
- selector builder calls;
- scoped aspect dependencies versus explicit-controller fallback;
- command, git, Flutter, and Dart provenance;
- broad/resource/component/structural invalidation shape.

Use Flutter DevTools in profile mode only when these counters move in an
unexpected direction. DevTools rebuild tracing is useful for diagnosis, but the
selector counter artifact is the stable AX gate.

## How can app plugins help Flutter apps?

Use normal ecsly `Plugin`s as feature setup bundles. An app plugin can register
components, small resources, optional id projections, schedules, and optional
headless systems:

```dart
final class TodoIds {
  const TodoIds._();
}

class TodoAppPlugin extends Plugin {
  const TodoAppPlugin();

  @override
  String get name => 'todo_app';

  @override
  void install(World world) {
    world.components.registerObjectComponent<TodoId>();
    world.components.registerObjectComponent<TodoTitle>();
    world.upsertResource(TodoUiResource());
    world.upsertResource(EntityIndexResource<TodoIds, String>());
  }
}
```

Good app plugin contents: feature setup, optional projections,
validation/status resources, sync queues, route/session state, and host adapter
resources for lifecycle, connectivity, or deep links.

`EntityIndexResource` is manually maintained by the feature/plugin action that
owns the id space. When you spawn an entity, add its id to the index and
invalidate that resource; when you despawn or change the id, remove or update
the entry in the same action/helper. The id component remains the source of
truth.

Avoid putting `BuildContext`, `TextEditingController`, callbacks, service
closures, or an entire domain store inside a resource. Repeated app data should
usually be entities with components; resources should stay small and necessary.

## What patterns fit forms, text editing, and sync?

- Forms: create one entity per draft and slice field value, touched, validation,
  dirty, and submit status into components.
- Text editing: the widget owns `TextEditingController`; ECS stores committed or
  debounced draft text plus validation/sync state.
- Sync/offline: model pending mutations as entities with `PendingMutation`,
  `SyncState`, and `ConflictState`; resources hold only service config, queues,
  and status summaries.
- Lists, feeds, and maps: store each item as an entity, keep persistent ids as
  components, add a typed id projection only when repeated lookup needs it, and
  let resources hold order/filter state instead of the full item payload.

## How do actions differ from ECS commands?

`EcsCommand` is core structural ECS machinery: spawn, despawn, add, remove, and
resource upsert work that flushes at a safe boundary.

`EcsAction` is app-level reusable logic: submit form, save draft, sign in,
hydrate local data, toggle UI state, or start optimistic sync. Actions can be
async and expose status through `EcsActionStatusResource`.

Use `EcsActionStatusSelector` when UI only needs the status for an action key,
and `EcsActionBuilder` when UI also needs a guarded run callback.

Inside an action, prefer `context.upsertComponent(...)` and
`context.mutateResource<T>(...)` for ordinary app mutations. They perform the
write and record narrow invalidation hints for Flutter. If you call
`context.world` directly, add the matching `context.invalidate...` call yourself
or accept broad fallback.

## How should forms work?

Keep normal Flutter fields and validators. Add `EcsDraft<T>` when you need
headless original/current values, dirty fields, field errors, reset, rebase, or
commit.

Do not put `TextEditingController`, `BuildContext`, `Navigator`, or snack
callbacks into ECS resources.

## Can games use this package?

Yes. Games should use the same `EcsScope`, selectors, and actions. Add `EcsLoop`
or `EcsFixedStepLoop` only where a frame driver is needed. Prefer fixed-step
simulation for gameplay state, and use a Flutter-frame schedule only when the
schedule intentionally follows host frame cadence.

## What should stay outside this package?

Renderers, HUD systems, input/camera/collision plugins, debug overlays, MCP
bootstrap, storage backends, network clients, and feature-specific schedule
ordering stay in owning packages.

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| Whole app rebuilds after small change | Pass narrow `EcsInvalidationBatch` from actions/transactions; use selector dependencies |
| UI stale after action | Ensure `runEcsAction` / controller path flushes and notifies `EcsController` |
| `EcsScope not found` | Wrap widget tree with `EcsScope` above selectors |
| Hydration runs too early | Use `EcsActionOnMount`, not pre-`runApp` domain seeding |
| Selector runs on unrelated changes | Add `EcsWorldSelectorDependencies` or use narrower selectors |
| Game stutters with loop | Check broad frame invalidation; pass schedule-specific invalidation hints |
| Unsure app vs Flutter API | Actions/drafts → `ecsly_app`; widgets/loops → `ecsly_flutter` |
