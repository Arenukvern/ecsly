# The ecsly_flutter_scene adapter (~/xs/ecsly/plugins/ecsly_flutter_scene)

A pure-core 3D adapter for ecsly worlds on flutter_scene. `SceneMapping` (pure) →
`VisualState` (pure data) → `EcsSceneBinder` (pure diff) → `SceneSink` (interface) →
`FlutterSceneSink`/`EcsSceneView` (the only GPU-touching code). Know this file map:

| File | Role |
| --- | --- |
| `lib/src/visual_state.dart` | `SceneShape` enum (closed) + `VisualState` data class |
| `lib/src/scene_mapping.dart` | `SceneMapping.add<T>(visualOf, {skip})` — component type → visual |
| `lib/src/ecs_scene_binder.dart` | `EcsSceneBinder` + `abstract class SceneSink` (add/update/remove/count) |
| `lib/src/flutter_scene_sink.dart` | `FlutterSceneSink` (materializes visuals) + `SceneCameraRig` (orbit camera) |
| `lib/src/ecs_scene_view.dart` | `EcsSceneView` widget (30 Hz sync, orbit gestures, static-resource init) |

## Mapping an entity type (the normal path)

```dart
final mapping = SceneMapping()
  ..add<Actor>(
    (entity, actor, world) {
      final pos = world.getEntity(entity).$1.get<_Position>();
      return VisualState(
        shape: SceneShape.sphere,
        argb: 0xFF4A9EFF,
        size: 0.5,
        position: [pos!.x, pos.y, pos.z],
        label: actor.label,
      );
    },
    skip: (entity, world) => /* e.g. superseded entities render nothing */,
  );
```

Rules baked into the package (do not fight them):

- **The consumer owns layout.** Positions come from component data or a layout function
  you supply. Never arrange a graph inside a mapping closure.
- One spec per component type; re-`add<T>` replaces the spec.
- `visualOf` returning `null` = render nothing this frame; `skip` = don't even query.
- Keys are `'T|e<entity>'` — stable, so the diff is meaningful across frames.

## VisualState semantics (exact)

| Field | Meaning |
| --- | --- |
| `shape` | `sphere` (point mass) · `cuboid` (box) · `disc` (flat, ground markers) · `billboard` (unlit thin cuboid in the inspected sink; no automatic camera-facing behavior) · `polyline` (uses `points`) |
| `size` | sphere radius · cube edge · disc **diameter** · billboard edge · polyline width |
| `argb` | plain int, `0xAARRGGBB`; alpha honored by the sink |
| `position` | XYZ world units; supply all three coordinates |
| `label` | **currently unused by `FlutterSceneSink`** — the inspector renders labels as a 2D overlay. Don't rely on it appearing in 3D. |
| `points` | polyline vertices only |
| `pickId` | Optional stable domain id; built-in picking only targets spheres |

Lifecycle color convention (from the first consumer): `verified` green, `failed` red,
open/blocked amber. Reuse it for anything stateful so views stay consistent.

### Trap: the signature excludes polyline point *contents*

`VisualState.signature` includes `position`, `size`, `argb`, `label`, and
`points.length` — but not the point values. A polyline whose vertices move without
changing count produces an identical signature, so **the binder never updates it**.
The default also rounds position coordinates to two decimal places, suppressing small
movements. For a dynamic consumer, override the signature with full-content or an
explicit revision contract through a `VisualState` subtype. The verified
[ecsly-visualization template](/Users/antonio/.codex/skills/ecsly-visualization/assets/preview_app/lib/preview_model.dart)
uses full-content JSON for small scenes and tests both failure cases. Do not claim
that this fixes the upstream binder's default policy or scales without measurement.

### Camera and camera-facing lines

The inspected `SceneCameraBasis` uses a horizontal basis opposite to flutter_scene
0.23.0. Labels and picks can disagree with pixels even while its own round-trip test
passes. Consumer viewports should use the renderer camera's `worldToScreen` and
`screenPointToRay`. This was verified with live browser/native captures and an
independent off-center camera/picking test in the visualization preview.

`PolylineGeometry` defaults to `screenPixels`: a width of .025 is almost invisible.
For world-unit lines set `widthMode: PolylineWidthMode.worldUnits`; expand the line
with `updateForCamera(camera, viewportSize)` after camera/viewport/points changes.
The installed engine does not call that method automatically for the adapter sink.
The preview's retained sink owns this work; its changing spheres retain nodes and
materials instead of rebuilding on every transform update.

`EcsSceneView` currently exposes `onEntityTap`, `onEntityHold`,
`onCameraChanged`, `onDistanceChange`, and manipulation callbacks. These hooks are
source-observed; the preview verified its custom consumer viewport, not every
built-in view callback. Use the public camera APIs for new viewport work.

## Adding visuals richer than the five shapes

`SceneShape` is intentionally closed; `EcsSceneView` hardwires `FlutterSceneSink`. Both
are upstream design decisions — don't edit the plugin to widen them from an app. The
public seam is `SceneSink` + `EcsSceneBinder` + `SceneMapping`, all pure. Three patterns,
in order of preference:

### Pattern 1 — custom sink that delegates (rich visuals per entity)

Implement `SceneSink` in your app. Delegate standard shapes to a wrapped
`FlutterSceneSink`; intercept keys you want to enrich (match on the spec-type prefix of
the key, e.g. `'Agent|e3'`) and materialize a full flutter_scene node — a
`loadScene(...)`-loaded hero model, a procedurally built subtree, anything.

```dart
class RichSink implements SceneSink {
  RichSink(this.scene) : _fallback = FlutterSceneSink(scene);
  final Scene scene;
  final FlutterSceneSink _fallback;
  final Map<String, Node> _custom = {};

  @override
  void add(String key, VisualState visual) {
    if (!key.startsWith('Agent|')) return _fallback.add(key, visual);
    final node = buildAgentModel(AgentParams(size: visual.size, seed: key.hashCode));
    node.position = _vec(visual.position);
    scene.add(node);
    _custom[key] = node;
  }
  // update: remove + re-add (matches FlutterSceneSink semantics: it also
  // rebuilds rather than mutating in place). remove: drop from both maps.
}
```

### Pattern 2 — your own view widget (when you need camera/loop control)

`EcsSceneView` is ~100 lines: init static resources → `Scene()` → binder with
`FlutterSceneSink` → 30 Hz `Timer` calling `binder.sync()` → `SceneView` with the rig.
Copy that shape in your app with `RichSink` instead. State you own: the `Scene`, the
binder, a `SceneCameraRig`. The world stays **read-only** — your app's own loop ticks it.

### Pattern 3 — skip VisualState for hero assets

If a visual doesn't fit state-diffing at all (a persistent environment, a cutscene rig),
build the flutter_scene scene yourself and use ecsly only for logic. The adapter is for
*state-driven* visuals; forcing everything through `VisualState` is a smell.

## Package hygiene (working inside the plugin itself)

- Renderer calls stay confined to `flutter_scene_sink.dart` + `ecs_scene_view.dart` —
  flutter_scene is pre-1.0 and drifts; isolation is the point of the architecture.
- The inspected pubspec requires Dart >=3.13; parameters carry no `final` modifier (see the
  `ignore_for_file: prefer_final_parameters` headers). Preserve this.
- Tests run GPU-free: `test/recording_sink.dart` records add/update/remove calls; binder
  and mapping tests assert against it. New pure logic (layout functions, visual
  derivation) gets the same treatment. Geometry construction is also GPU-free — see the
  procedural reference.
- Validation loop for the plugin: `cd plugins/ecsly_flutter_scene && flutter analyze &&
  flutter test` (workspace: `dart pub get` at repo root first). `just check` before PRs per
  repo `AGENTS.md`.

## Enabling the view in an app

Flutter 3.47+ with Flutter GPU: `flutter run --enable-flutter-gpu` in dev, plus the
platform plist/manifest keys for permanent/release (`FLTEnableFlutterGPU` on iOS/macOS,
`EnableFlutterGPU` meta-data on Android — see the flutter_scene README). `EcsSceneView`
handles `Scene.initializeStaticResources()` itself (guarded, idempotent);
`initialDistance` sets the orbit camera start.
