import 'dart:ui' show Size;

import 'package:ecsly_flutter_scene/ecsly_flutter_scene.dart';
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

/// Consumer sink: moving spheres retain geometry, nodes and materials.
/// Changing polylines rebuild only their own mesh; no generic engine fork.
class RetainedSceneSink implements SceneSink {
  RetainedSceneSink(this.scene);
  final Scene scene;
  final _nodes = <String, Node>{};
  final _visuals = <String, VisualState>{};
  final _materials = <String, UnlitMaterial>{};
  final _lines = <String, PolylineGeometry>{};
  int creations = 0, transformUpdates = 0, removals = 0;
  @override
  int get count => _nodes.length;

  @override
  void add(String key, VisualState visual) {
    final material = UnlitMaterial()..baseColorFactor = _color(visual.argb);
    final mesh = switch (visual.shape) {
      SceneShape.sphere => Mesh(SphereGeometry(radius: 1), material),
      SceneShape.polyline => Mesh(
        PolylineGeometry(
          [for (final p in visual.points) _position(p)],
          width: visual.size,
          widthMode: PolylineWidthMode.worldUnits,
        ),
        material,
      ),
      _ => throw UnsupportedError(
        'Preview sink supports spheres and polylines',
      ),
    };
    final geometry = mesh.primitives.first.geometry;
    if (geometry is PolylineGeometry) _lines[key] = geometry;
    final node = Node(mesh: mesh)..position = _position(visual.position);
    if (visual.shape == SceneShape.sphere) {
      node.scale = vm.Vector3.all(visual.size);
    }
    _nodes[key] = node;
    _visuals[key] = visual;
    scene.add(node);
    _materials[key] = material;
    creations++;
  }

  @override
  void update(String key, VisualState visual) {
    final previous = _visuals[key]!;
    if (previous.shape != visual.shape || visual.shape == SceneShape.polyline) {
      remove(key);
      add(key, visual);
      return;
    }
    final node = _nodes[key]!;
    node.position = _position(visual.position);
    node.scale = vm.Vector3.all(visual.size);
    _materials[key]!.baseColorFactor = _color(visual.argb);
    _visuals[key] = visual;
    transformUpdates++;
  }

  @override
  void remove(String key) {
    final node = _nodes.remove(key);
    _visuals.remove(key);
    _materials.remove(key);
    _lines.remove(key);
    if (node != null) {
      scene.remove(node);
      removals++;
    }
  }

  void updateForCamera(Camera camera, Size viewportSize) {
    for (final geometry in _lines.values) {
      geometry.updateForCamera(camera, viewportSize);
    }
  }

  vm.Vector3 _position(List<double> p) => vm.Vector3(p[0], p[1], p[2]);
  vm.Vector4 _color(int argb) => vm.Vector4(
    ((argb >> 16) & 255) / 255,
    ((argb >> 8) & 255) / 255,
    (argb & 255) / 255,
    ((argb >> 24) & 255) / 255,
  );
}
