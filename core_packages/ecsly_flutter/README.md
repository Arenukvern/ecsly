# ecsly_flutter

Thin Flutter bindings for [`ecsly`](https://pub.dev/packages/ecsly) and
[`ecsly_app`](../ecsly_app/README.md).

This package is the official Flutter bridge for apps and games. It keeps the
setup path shared: every host gets an `EcsScope`, an `EcsController`, selectors,
and optional action helpers. Apps can run user actions without a loop. Games can
add `EcsLoop` or `EcsFixedStepLoop` around the same scope.

**Status:** published prerelease. Pin the `dev` version deliberately.

**Compatibility:** `ecsly_flutter` `0.1.0-dev.x` requires `ecsly` `>=0.0.1-dev.9`,
`ecsly_app` `^0.1.0-dev.1`, and Flutter `>=3.35.0`.

Further docs: [DX_FAQ.md](DX_FAQ.md) (how) · [DESIGN_FAQ.md](DESIGN_FAQ.md) (why)

## Install

```yaml
dependencies:
  ecsly: ^0.0.1-dev.9
  ecsly_app: ^0.1.0-dev.1
  ecsly_flutter: ^0.1.0-dev.1
  flutter:
    sdk: flutter
```

```dart
import 'package:ecsly_flutter/ecsly_flutter.dart';
```

This package re-exports `package:ecsly_app/ecsly_app.dart` (which re-exports
`ecsly`). Flutter widgets and loop hosts live here; headless app workflows are
defined in [`ecsly_app`](../ecsly_app/README.md).

Monorepo/workspace packages may use key-only entries (`ecsly_flutter:`) or
local path overrides while developing multiple packages together.

Run the sample app from this package:

```sh
cd core_packages/ecsly_flutter/example && flutter run
```

## Package chooser

| Need | Package | Public status |
|------|---------|---------------|
| Hot simulation | `ecsly` | Public package |
| Cold app path | `ecsly_app` | Published prerelease |
| Typed-column builders | `ecsly_codegen` | Published prerelease |
| Flutter host | `ecsly_flutter` | Published prerelease |

Pure Dart app contracts such as `EcsAction`, `EcsDraft`, cold component lookup,
and `EntityIndexResource` are owned by
[`ecsly_app`](../ecsly_app/README.md) and reexported here for Flutter convenience.
See the [ecsly_app README](../ecsly_app/README.md) for headless action workflows
and invalidation patterns.

## App-style usage

Prefer components for user-visible records and domain slices. Keep resources
small: filters, clocks, status tables, caches, selected ids, and other
world-scoped coordination state.

```dart
class TodoTitle extends Component {
  const TodoTitle(this.value);
  final String value;
}

class TodoUiResource extends Resource {
  final List<Entity> order = <Entity>[];
  bool showDone = true;
}

final world = World()
  ..components.registerObjectComponent<TodoTitle>()
  ..upsertResource(TodoUiResource());
final controller = EcsController(world: world);

EcsAppScope(
  world: world,
  controller: controller,
  schedules: const EcsFlutterSchedules(
    onMount: 'app.boot',
    afterAction: 'app.after_action',
    onResume: 'app.resume',
  ),
  child: EcsActionOnMount(
    action: const HydrateTodosAction(),
    child: EcsComponentSelector<TodoTitle, String>(
      entity: todoEntity,
      select: (title) => title.value,
      builder: (context, value) => Text(value),
    ),
  ),
);
```

`EcsActionOnMount` runs after the first frame. It keeps app hydration in normal
ECS action logic without filling the world with domain records before `runApp`.

For most Flutter apps, keep systems synchronous and use them as lifecycle or
post-action derivation passes. Async work belongs in `EcsAction`; schedules
normalize or derive state after the action completes:

```dart
world
    .getOrCreateSchedule('app.after_action')
    .add(recomputeVisibleTodosSystem, name: 'todos.visible')
    .then(validateSelectionSystem, name: 'todos.selection');

EcsAppScope(
  world: world,
  controller: controller,
  schedules: const EcsFlutterSchedules(
    onMount: 'app.boot',
    afterAction: 'app.after_action',
    onResume: 'app.resume',
    frame: null,
  ),
  onScheduleRun: (event) => debugPrint(
    '${event.reason.name}: ${event.scheduleName} ${event.elapsed}',
  ),
  child: const App(),
);
```

This gives plain apps predictable transactions: action, flush, app systems,
flush, and tracked Flutter refreshes. It also leaves the same world free to
install normal ecsly plugins and schedules.

Context helpers use ECS-scoped names so Flutter autocomplete stays honest:

```dart
final ui = context.getEcsResource<TodoUiResource>();

final title = context.selectEcsComponent<TodoTitle, String>(
  (title) => title.value,
  entity: todoEntity,
);

final showDone = context.selectEcsResource<TodoUiResource, bool>(
  (ui) => ui.showDone,
);
```

When a screen starts from app data rather than an `Entity`, use `where` for a
cold app/UI lookup. Context helpers delegate to the same `World` extension API,
so reusable app code can use `world.findEcsEntityWithComponent(...)` directly:

```dart
final entity = context.findEcsEntityWithComponent<TodoRecord>(
  where: (entity, todo) => todo.id == selectedTodoId,
);

final sameEntity = world.findEcsEntityWithComponent<TodoRecord>(
  where: (entity, todo) => todo.id == selectedTodoId,
);

final title = context.selectEcsComponent<TodoRecord, String>(
  (todo) => todo.title,
  entity: entity,
);
```

Stable app ids should still be normal components. If a screen repeatedly needs
to resolve a route id or selected id to the current runtime entity, use a typed
app/plugin projection such as `EntityIndexResource<TodoIds, String>`. Treat it
as optional infrastructure, not the source of identity. Feature plugins and
actions must update or remove index entries manually when they spawn, despawn,
or change ids.

When a widget derives one value from multiple resources/components, use
`EcsWorldSelector`. Add dependency hints when the selector can safely skip
unrelated tracked ECS changes:

```dart
EcsWorldSelector<List<Entity>>(
  dependencies: const EcsWorldSelectorDependencies(
    resourceTypes: [TodoUiResource],
    componentTypes: [TodoRecord],
    structural: true,
  ),
  select: (world) => visibleTodos(world),
  builder: (context, entities) => TodoListView(entities),
);
```

Resource and component selectors use Flutter aspect invalidation supplied by the
controller. Core ECS does not remember which resource or component type changed.
Pass an `EcsInvalidationBatch` when a transaction/action knows what changed;
omitted invalidation refreshes conservatively.

Selector invalidation is measured separately from core ECS benchmarks. From the
repo root, run:

```sh
just profile-flutter-selectors
```

The test writes `build/reports/selector_invalidation_profile.v1.json` inside
`core_packages/ecsly_flutter` with selector-call, selector-builder-call,
controller notification, invalidation-batch, and artifact provenance counters.
Use Flutter DevTools/profile mode only after those counters show an unexpected
selector path; debug-mode rebuild timings are not a stable benchmark.

When a button, stream, repository, or form handler changes ECS state, run a
transaction or reusable action through the controller:

```dart
class ToggleTodoAction extends EcsAction<void> {
  const ToggleTodoAction(this.entity);
  final Entity entity;

  @override
  void run(EcsActionContext context) {
    final done = context.getComponent<TodoDone>(entity: entity);
    context.upsertComponent(entity, TodoDone(value: !done.value));
  }
}

await context.runEcsAction(ToggleTodoAction(todoEntity));
```

When creating one app record from multiple components, use a component bundle
through the action context instead of piecemeal upserts:

```dart
final entity = context.spawnComponents([
  TodoId(id),
  TodoTitle(title),
  const TodoDone(value: false),
]);
context
    .getResource<EntityIndexResource<TodoIds, String>>()
    .upsert(id, entity);
context.invalidateResource<EntityIndexResource<TodoIds, String>>();
```

`EcsActionBuilder` exposes action status without choosing a Material or
Cupertino button for you.

## Editing and Forms

Use normal Flutter text fields and form widgets. Use `EcsDraft<T>` when the app
needs a headless draft with original/current values, dirty state, field errors,
and explicit reset/commit behavior.

Drafts are useful for text editing, nested sheets, validation, optimistic saves,
and “local committed, remote failed” states. They do not put `BuildContext`,
controllers, navigation, or callbacks into ECS resources.

## Game Usage

Games use the same scope and selectors, then add a loop host:

```dart
EcsAppScope(
  world: world,
  controller: controller,
  schedules: const EcsFlutterSchedules(
    frame: EcsFrameSchedule.fixed(
      'SwarmUpdate',
      fixedDt: 1 / 60,
      maxCatchUpStepsPerTick: 4,
      invalidation: EcsInvalidationBatch.broad(),
    ),
  ),
  child: MyRenderer(),
);
```

For lower-level control, keep using `EcsLoop` or `EcsFixedStepLoop` directly.
The app host simply packages the common lifecycle/action/frame policy in one
place.

Frame schedules broad-invalidate by default because schedule systems are opaque
to Flutter. If a host owns a schedule and knows the exact UI-facing slice it
mutates, pass an `EcsInvalidationBatch` to `EcsFrameSchedule` or an
`EcsScheduleInvalidation` callback to the lower-level loop. The loop also marks
`DeltaTimeResource` and `ScheduleTimeResource` as changed on every narrow frame
notification.

Renderers, camera/input bindings, debug overlays, MCP tooling, and game-specific
plugins are intentionally outside this package.
