# ecsly_flutter_scene

A 3D scene adapter for [ecsly](https://github.com/arenukvern/ecsly) worlds
on [flutter_scene](https://pub.dev/packages/flutter_scene): declarative
per-component visual mappings, an incremental binder that keeps a
flutter_scene `Scene` in sync with world queries, and an orbit camera rig.

Built for inspectors and debug views — the first consumer visualizes
agent worlds (actors as shapes, steps/claims as lifecycle-colored
markers, meaning-tree neighborhoods as a graph).

## Design

- **Pure core, thin renderer shell.** `SceneMapping`, `VisualState`, and
  `EcsSceneBinder` import no flutter_scene — they diff pure
  `VisualState`s against a `SceneSink` interface, so the whole core is
  unit-testable without a GPU. flutter_scene types appear only in
  `FlutterSceneSink`, `SceneCameraRig`, and `EcsSceneView`.
- **The consumer owns layout.** The mapping only consumes position +
  appearance (from component data or a layout function you supply); it
  never arranges a graph itself.
- **Diffed sync.** Each `binder.sync()` collects the desired visuals and
  lands only ADD/UPDATE/REMOVE mutations — a static world costs one
  collection and zero sink calls. Updates are signature-diffed.
- **Labels are billboards** (flutter_scene-native): no per-label texture
  round-trip, legible at any camera distance.
- **The view only READS the world.** Your app's own loop ticks it; the
  view runs a 30 Hz sync pass and never contends with the world schedule.

## Usage

```dart
final mapping = SceneMapping()
  ..add<Actor>(
    (entity, actor, world) => VisualState(
      shape: SceneShape.sphere,
      argb: 0xFF4A9EFF,
      size: 0.6,
      position: layoutOf(entity),
      label: 'actor',
    ),
  )
  ..add<Step>(
    (entity, step, world) => switch (step.status) {
      StepLifecycle.verified => _green(entity),
      StepLifecycle.failed => _red(entity),
      _ => _amber(entity), // open/blocked — in flight
    },
    skip: (entity, world) => world.getEntity(entity).$1.get<Step>()!.status ==
        StepLifecycle.superseded,
    // superseded steps render nothing
  );

// In a widget tree (Flutter 3.47+, Flutter GPU enabled):
EcsSceneView(world: world, mapping: mapping);
```

## Requirements

- Flutter 3.47+ with **Flutter GPU enabled** per platform
  (`--enable-flutter-gpu` for debug, `FLTEnableFlutterGPU` in iOS/macOS
  Info.plist, etc. — see the flutter_scene README).
- `await Scene.initializeStaticResources()` before first geometry —
  `EcsSceneView` handles this itself (guarded, idempotent).
- flutter_scene is pre-1.0 and its API moves; ALL renderer calls in this
  package concentrate in `lib/src/flutter_scene_sink.dart` +
  `lib/src/ecs_scene_view.dart` — API drift costs those files only.

## What was borrowed

Patterns (not code) from the private ecsly plugins: the mapping-DSL idea
(`ecs_scene_description`), panel/toolbar ergonomics
(`ecs_visual_workbench_flutter`), and replay-loop structure
(`ecs_replay_tools_flutter`). Dependencies: flutter_scene + ecsly +
ecsy_flutter only.
