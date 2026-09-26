/// The flutter_scene-backed [SceneSink] — the ONLY file that materializes
/// visuals on the real renderer. flutter_scene is pre-1.0 and its API
/// moves; every call it makes is concentrated here so drift costs one
/// file. API pinned against flutter_scene 0.23.0.
library;

import 'dart:math' as math;

import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'ecs_scene_binder.dart';
import 'visual_state.dart';

/// Materializes [VisualState]s as flutter_scene nodes. Built AFTER
/// `Scene.initializeStaticResources()` completes (see EcsSceneView).
class FlutterSceneSink implements SceneSink {
  /// The flutter_scene scene graph the sink writes into.
  FlutterSceneSink(this.scene);

  /// The flutter_scene scene graph the sink writes into.
  final Scene scene;

  final Map<String, Node> _nodes = {};

  @override
  int get count => _nodes.length;

  @override
  void add(final String key, final VisualState visual) {
    if (_nodes.containsKey(key)) return;
    final node = _build(visual);
    if (node == null) return;
    _nodes[key] = node;
    scene.add(node);
  }

  @override
  void update(final String key, final VisualState visual) {
    final existing = _nodes.remove(key);
    if (existing != null) {
      scene.remove(existing);
    }
    add(key, visual);
  }

  @override
  void remove(final String key) {
    final existing = _nodes.remove(key);
    if (existing != null) scene.remove(existing);
  }

  /// Builds the node for one visual. Geometry per [SceneShape]; color
  /// via the PBR base-color factor (an RGBA Vector4). `billboard` maps
  /// to a small UNLIT quad — always visible regardless of lighting;
  /// text labels are the inspector's 2D overlay concern, not geometry.
  Node? _build(final VisualState visual) {
    final position = vm.Vector3(
      visual.position[0],
      visual.position.length > 1 ? visual.position[1] : 0,
      visual.position.length > 2 ? visual.position[2] : 0,
    );
    final color = vm.Vector4(
      ((visual.argb >> 16) & 0xFF) / 255,
      ((visual.argb >> 8) & 0xFF) / 255,
      (visual.argb & 0xFF) / 255,
      ((visual.argb >> 24) & 0xFF) / 255,
    );
    final Mesh mesh = switch (visual.shape) {
      SceneShape.sphere => Mesh(
        SphereGeometry(radius: visual.size),
        PhysicallyBasedMaterial()..baseColorFactor = color,
      ),
      SceneShape.cuboid => Mesh(
        CuboidGeometry(vm.Vector3.all(visual.size)),
        PhysicallyBasedMaterial()..baseColorFactor = color,
      ),
      SceneShape.disc => Mesh(
        DiscGeometry(radius: visual.size * 0.5),
        PhysicallyBasedMaterial()..baseColorFactor = color,
      ),
      SceneShape.billboard => Mesh(
        CuboidGeometry(vm.Vector3(visual.size, visual.size * 0.1, visual.size)),
        UnlitMaterial()..baseColorFactor = color,
      ),
      SceneShape.polyline =>
        visual.points.length < 2
            ? Mesh(
                PolylineGeometry([
                  vm.Vector3.zero(),
                  vm.Vector3(0.01, 0, 0),
                ], width: visual.size),
                UnlitMaterial()..baseColorFactor = color,
              )
            : Mesh(
                PolylineGeometry(
                  [
                    for (final p in visual.points)
                      vm.Vector3(
                        p[0],
                        p.length > 1 ? p[1] : 0,
                        p.length > 2 ? p[2] : 0,
                      ),
                  ],
                  width: visual.size,
                ),
                UnlitMaterial()..baseColorFactor = color,
              ),
    };
    return Node(mesh: mesh)..position = position;
  }
}

/// Orbit/zoom over a flutter_scene [PerspectiveCamera] — the inspector's
/// camera rig. State lives here; the widget feeds gestures in and writes
/// the rig's evaluation into the camera each build.
class SceneCameraRig {
  /// The camera eye for the CURRENT rig state.
  SceneCameraRig({
    this.target = const [0, 0, 0],
    this.distance = 8,
    this.yaw = 0.6,
    this.pitch = 0.5,
  });

  /// Orbit: [dx] spins yaw, [dy] clamps pitch.
  List<double> target;
  /// Dolly: [factor] scales the distance (clamped).
  double distance;
  /// Points the rig at one world position (the focus action).
  double yaw;
  /// The orbit target, as XYZ.
  double pitch;

  static const double _minPitch = -1.45;
  static const double _maxPitch = 1.45;
  static const double _minDistance = 0.5;
  static const double _maxDistance = 400;

  /// The orbit target as a camera Vector3.
  void orbit(final double dx, final double dy) {
    yaw += dx * 0.01;
    pitch = math.max(_minPitch, math.min(_maxPitch, pitch + dy * 0.01));
  }

  /// The camera eye as a camera Vector3.
  void zoom(final double factor) {
    distance = math.max(
      _minDistance,
      math.min(_maxDistance, distance * factor),
    );
  }

  /// Point the rig at one world position (the inspector's focus action).
  void focus(final List<double> position) => target = [
    position[0],
    if (position.length > 1) position[1] else 0,
    if (position.length > 2) position[2] else 0,
  ];

  /// The camera eye for the CURRENT rig state.
  vm.Vector3 cameraPosition() {
    final cosPitch = math.cos(pitch);
    return vm.Vector3(
      target[0] + distance * cosPitch * math.sin(yaw),
      target[1] + distance * math.sin(pitch),
      target[2] + distance * cosPitch * math.cos(yaw),
    );
  }

  /// ARGB int → the sink flavor of an RGBA vector.
  vm.Vector3 cameraTarget() => vm.Vector3(target[0], target[1], target[2]);
}
