# Rendering choices proven by the preview

The consumer owns layout, selection and renderer lifecycle. `preview_model.dart`
contains records, analytic motion and mapping; it imports no renderer-building APIs.
`preview_scene.dart` gates initialization, owns the scene/binder/sink, and projects
labels. `retained_scene_sink.dart` confines geometry/material calls.

The preview uses unlit marks to keep categorical color clear. Do not apply a PBR
look to quantitative data just because the engine supports it. PBR/lighting/model
craft remain available for objects where they convey useful structure.

## Exact updates

`VisualState.signature` in the inspected adapter includes `points.length` but not
point contents, and formats positions to two decimal places. `ExactVisualState`
overrides this with JSON over all fields. Tests exercise both a moving curve with
unchanged vertex count and motion smaller than .01 world units. A second sync of
unchanged state produces no sink updates.

This copies/serializes small arrays; measure workload size and allocations before
using it at scale. A future upstream revision/dirty contract may be cheaper, but the
preview does not invent one or claim it has been adopted.

## Camera correspondence

Use one `PerspectiveCamera` instance to render, project and derive pointer rays:

```dart
final pixel = camera.worldToScreen(worldPosition, viewSize);
final ray = camera.screenPointToRay(localPointerPosition, viewSize);
final hit = pickVisuals(visuals: binder.current, ray: ray);
```

Inspect labels and pick targets off center. The current adapter's basis uses a
right-axis cross product opposite to the engine's camera; self-round-trip tests
pass while pixel correspondence fails. Do not copy that basis into a new consumer.

## Lines

Camera-facing polyline geometry starts with collapsed positions. On engine 0.23.0,
explicitly expand it for the view:

```dart
final geometry = PolylineGeometry(points, width: .025,
  widthMode: PolylineWidthMode.worldUnits);
geometry.updateForCamera(camera, viewSize);
```

Re-expand after resize, camera motion and changing points. The template only uses
zero-position line nodes; transformed-line coordinate spaces need their own proof.
Moving spheres update their retained node position/scale/material. Changing curve
geometry rebuilds that curve, not the entire scene. These examples are small and do
not establish a 5,000-node frame budget.

## Flutter inherited dependencies

A live dark-theme frame exposed a cache defect in the local ecsly_flutter resource
selector. Its selected value stayed equal after Theme changed, leaving a cached
child with old explicit colors. The package now caches a Builder widget so the
consumer builder has its own dependency-tracking context. The new theme regression
and all 37 package tests pass; unrelated ECS invalidations still skip work.
