# ecsly (Entity Component System) for Dart apps

⚠️ This package is published as **super-experimental prerelease** (`0.0.1-dev.9`).
APIs are actively changing and may break across releases.

![ecsly logo](assets/brand/ecsly-logo.png)

`ecsly` is a performance-oriented Dart ECS runtime focused on deterministic simulation and low-GC hot loops.
It owns entities, archetypes, resources, events, commands, and schedules.

Use it when you want a small pure-Dart ECS core under games, simulations,
tools, tests, Flutter hosts, Jaspr sites, or plugin packages. Start with normal
Dart object components, then move hot numeric state to typed extension
components when GC pressure or iteration speed matters.

## Use

Add to `pubspec.yaml`:

```yaml
dependencies:
  ecsly: ^0.0.1-dev.9
```

Import path:

```dart
import 'package:ecsly/ecsly.dart';
```

Supported platforms: Android, iOS, Linux, macOS, web, and Windows.

Because the core package has no Flutter dependency, it can also be used from
Jaspr and other Dart-first hosts. Keep simulation in `ecsly` systems, then let
the host layer decide how to render, hydrate, or expose the resulting state.

## API lanes

- Hot path: schedules, queries, extension components, typed columns, and
  direct in-place component/resource writes. This is where low-GC simulation
  belongs.
- Warm path: command queues, flush boundaries, resources, prepared queries, and
  topology/query revisions.
- Cold app path: actions, drafts, domain-id projections, route lookups, and UI
  selection helpers live in `package:ecsly_app` or host packages such as
  `package:ecsly_flutter`.

Host invalidation summaries are intentionally outside core. Flutter/app hosts
can use `package:ecsly_app` invalidation batches while hot worlds keep the core
mutation path summary-free and change-tracking-free.

## Tiny story

Define a component as ordinary Dart data:

```dart
class CounterComponent extends Component {
  CounterComponent(this.value);
  int value;
}
```

Create a world and register the component storage:

```dart
final world = World();
world.components.registerObjectComponent<CounterComponent>();
```

Spawn an entity with a component bundle:

```dart
final entity = world.reserveEmptyEntity().entity;
world.spawnBundle(entity, ComponentBundle.fromLists([CounterComponent(1)]));

// Structural changes are queued; flush makes them visible to queries.
world.flush();
```

For cold-path app/tooling code, `world.spawnComponents([...])` returns the new
entity while still queuing one bundled structural spawn.

Read or mutate it:

```dart
for (final (_, counter) in world.queryMut<CounterComponent>()) {
  counter.value += 1;
}
```

Put logic into a schedule when you want named update stages:

```dart
world.createSchedule('Update').add((world) {
  for (final (_, counter) in world.queryMut<CounterComponent>()) {
    counter.value += 1;
  }
});

world.runSchedule('Update');
world.flush();
```

For hot numeric data, use extension components backed by typed columns. See
`example/scheduled_run.dart` for a compact `EnergyComponent` example.

## A few more patterns

Extension components split identity from storage. The marker type lets ecsly
register/query a component; the facade gives typed access to packed column data:

```dart
world.components.registerExtension<EnergyComponent, Energy>(
  columnFactory: MyEnergyColumnFactory(),
  facadeFactory: MyEnergyFacadeFactory(),
);

for (final (_, energy) in world.queryExt<EnergyComponent, Energy>()) {
  energy.current += energy.regenPerTick;
}
```

The runnable `example/extension_component.dart` uses the concrete factories
defined in `example/components.dart`.

Commands let you request structural changes while iteration is still running:

```dart
for (final (entity, counter) in world.query<CounterComponent>()) {
  if (counter.value >= 2) {
    entity.remove<CounterComponent>(); // queued until flush
  }
}

world.flush();
```

Resources are global singleton state for systems:

```dart
class FrameClockResource extends Resource {
  FrameClockResource(this.deltaSeconds);
  final double deltaSeconds;
  int frame = 0;
}

world.upsertResource(FrameClockResource(1 / 60));

void tickFrameClockSystem(World world) {
  world.getResource<FrameClockResource>().frame += 1;
}
```

Resources can be immutable snapshots, mutable frame state, or a mix of both.
Choose mutability by purpose: fixed inputs stay `final`, counters and caches can
mutate, and behavior still belongs in systems. Keep command-queuing behavior in
system functions, not inside the resource object.

Use `world.maybeGetResource<T>()` for optional resources. Runtime [Entity]
handles are not persistent ids; stable app/domain ids should be normal
components or plugin data. If host UI starts from a selected id, keep any
id-to-entity index in the app/plugin layer instead of core simulation code.
Core tracks only topology/query revision epochs for structural changes at
`flush()`: one successful structural command flush is one epoch even if many
entities moved.
Host/view invalidation belongs in `package:ecsly_app` or
`package:ecsly_flutter` through explicit `EcsInvalidationBatch` hints.

SIMD-style hot paths use typed columns with stride `4`, then operate on the
column's `Float32x4List` view. See `example/simd_columns.dart`.

## SIMD columns

Use an extension component when the game-facing API should look like fields,
but the storage should stay packed for hot loops. A stride-4 `FloatColumn` can
hold `(x, y, z, w)` rows and expose a `Float32x4List` view:

```dart
import 'dart:typed_data';

import 'package:ecsly/ecsly.dart';

class Velocity4Component extends Component {
  const Velocity4Component();
}

extension type Velocity4._(int index) {
  static late FloatColumn column;

  double get x => column.getValueUnsafe(index, 0);
  double get y => column.getValueUnsafe(index, 1);

  set x(double value) => column.setValue(index, 0, value);
  set y(double value) => column.setValue(index, 1, value);
}

final class Velocity4ColumnFactory extends ColumnFactory {
  @override
  DataColumn createColumn(
    ComponentId componentId, {
    int initialCapacity = 8,
  }) {
    return FloatColumn(stride: 4, initialCapacity: initialCapacity);
  }
}

final class Velocity4FacadeFactory
    extends ComponentFacadeFactory<Velocity4> {
  @override
  Velocity4 create(int index) => Velocity4._(index);

  @override
  void initialize(covariant FloatColumn column) {
    Velocity4.column = column;
  }
}
```

Register the extension component, spawn rows, then use the SIMD view when you
want to update the packed column in batches:

```dart
final world = World();
world.components.registerExtension<Velocity4Component, Velocity4>(
  columnFactory: Velocity4ColumnFactory(),
  facadeFactory: Velocity4FacadeFactory(),
);

final entity = world.reserveEmptyEntity().entity;
world.spawnBundle(
  entity,
  ComponentBundle.fromExtensionList(const [
    (Velocity4Component, Velocity4),
  ]),
);
world.flush();

for (final (_, velocity) in world.queryExt<Velocity4Component, Velocity4>()) {
  velocity.x = 3;
  velocity.y = 4;
}

final simd = Velocity4.column.simdView;
if (simd != null) {
  final gravity = Float32x4(0, -9.8, 0, 0);
  for (var i = 0; i < Velocity4.column.length; i++) {
    simd[i] = simd[i] + gravity;
  }
}
```

The facade keeps ordinary systems readable. The column keeps numeric state
dense, reusable, and cheap to scan when a game or simulation starts pushing
more entities through the same operation.

## Why it is useful

- Deterministic structural changes through command queues and explicit flushes.
- Fast iteration through archetypes, query masks, and column storage.
- Flexible object components for simple/cold data.
- Low-GC extension components for compact hot data.
- Schedules, resources, events, and plugins without depending on Flutter.
- Usable from Flutter, Jaspr, CLI tools, tests, and other Dart runtimes.

## Examples

- `example/basic_world.dart`: smallest object-component flow.
- `example/scheduled_run.dart`: schedule plus custom `FloatColumn` extension component.
- `example/extension_component.dart`: marker component plus typed facade.
- `example/commands_and_resources.dart`: deferred commands and global resources.
- `example/simd_columns.dart`: stride-4 `FloatColumn` and SIMD view.
- `example/components.dart`: tiny components with dartdoc explaining the storage choices.

Run an example from this package directory:

```sh
dart run example/main.dart
```

Core examples avoid owning gameplay-space components such as `PositionComponent`
and `VelocityComponent`. Use domain packages or application-owned packages for
shared game concepts.

## Benchmarks

Historical local baseline: `benchmark/results/latest.md`

Recorded environment: MacBook Air (M2, 2022), 8 GB RAM, macOS, Dart `3.12.1`,
8 processors. Treat these as machine-specific evidence, not universal
guarantees.

| Metric | Recorded result | Signal |
|---|---:|---|
| Mutable typed-column query | 66.0M ops/sec | low-GC in-place mutation |
| Raw chunk query | 53.8M ops/sec | strongest hot query path |
| Render-packet-like extract | 72.9M ops/sec | prototype-style packet extraction |
| 20k game-frame p95 | 893 us | frame-shaped ECS update + extract |
| Command flush | 4.1M ops/sec | structural/object-component bottleneck signal |
| Spawn/despawn churn | 2.5M ops/sec | frame-style entity lifecycle pressure |

Generate a local report:

```sh
dart run benchmark/run.dart --limits --samples=5 \
  --markdown-out=benchmark/results/latest.md \
  --json-out=benchmark/results/latest.json
```

The README table above is the initial recorded baseline; compare it to the
generated median-of-5 report on the same machine, OS, Dart SDK, and runtime
mode.

The benchmark suite reports hot-path strengths and bottleneck signals: query
iteration, raw chunk iteration, game-frame p50/p95/p99,
render-packet-like extract, command flush, migration, spawn/despawn churn,
cache hit/miss, events, memory delta, and optional entity-count scaling. Results
depend on machine, OS, Dart SDK, and runtime mode, so compare median-of-5
reports from the same environment.

When a metric moves, profile the benchmark under the Dart VM service instead of
guessing from the scorecard:

```sh
dart --observe=0 --pause-isolates-on-start run benchmark/run.dart --json
```

Open the printed DevTools URL, resume the isolate, and capture CPU, allocation,
GC, and timeline evidence around the changed metric. Start with
`CommandQueue.execute`, `QueryCache.getOrCompute`, query cache invalidation,
query iterator loops, archetype migration, and accidental
`List`/`Map`/closure/record allocations in hot paths. Keep those captures as
`benchmark/results/profiles/` sidecars; the scorecard says what moved, while
the profile sidecar is the causal evidence.

## What this package is and is not

- ✅ Core runtime package: entities, archetypes, resources, events, plugins, and system schedules.
- ✅ Runtime-first with minimal external dependencies and early-prerelease status.
- ❌ Not a code-generator package: typed-column factory codegen belongs in the companion `ecsly_codegen` package when available.
- ❌ Not a full application stack: graphics/input/collision/camera plugins remain outside this public repo until explicitly migrated.

## Documentation

- **[DX_FAQ.md](DX_FAQ.md)** — how to start, examples, terminology, and practical usage.
- **[DESIGN_FAQ.md](DESIGN_FAQ.md)** — architecture, trade-offs, and why the API works this way.
- Companion package docs, when available in your workspace or on pub.dev:
  `ecsly_app` for app-layer actions/drafts/invalidation, `ecsly_flutter` for
  Flutter host bridges, and `ecsly_codegen` for typed-column factory codegen.
- **[Autogenerated API docs](https://pub.dev/documentation/ecsly/latest/)**
- **[CHANGELOG.md](CHANGELOG.md)**

## Acknowledgements

`ecsly` stands on prior ECS and simulation work. We appreciate ideas and lessons from
[Bevy](https://bevyengine.org/), [EnTT](https://github.com/skypjack/entt), and many other open-source contributors.
