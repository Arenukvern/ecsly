// Parameters carry no `final`: this package compiles under language 3.13
// (where that modifier is an error) as well as 3.12.
// ignore_for_file: prefer_final_parameters

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

  /// Geometry identity per key: shape + size. When an update keeps both,
  /// only position/color changed and the node is mutated IN PLACE — no
  /// geometry rebuild, no scene remove/add churn. This is the hot path
  /// for moving actors (people dots at 30 Hz): a sphere that moves keeps
  /// its mesh and material.
  final Map<String, (SceneShape, double)> _geometryIdentity = {};

  @override
  int get count => _nodes.length;

  @override
  void add(String key, VisualState visual) {
    if (_nodes.containsKey(key)) return;
    final node = _build(visual);
    if (node == null) return;
    _nodes[key] = node;
    _geometryIdentity[key] = (visual.shape, visual.size);
    scene.add(node);
  }

  @override
  void update(String key, VisualState visual) {
    final existing = _nodes[key];
    final identity = _geometryIdentity[key];
    if (existing != null &&
        identity != null &&
        identity.$1 == visual.shape &&
        identity.$2 == visual.size &&
        existing.mesh != null) {
      // Same geometry: mutate position and color in place.
      existing.position = vm.Vector3(
        visual.position[0],
        visual.position.length > 1 ? visual.position[1] : 0,
        visual.position.length > 2 ? visual.position[2] : 0,
      );
      final material = existing.mesh!.primitives.first.material;
      if (material is PhysicallyBasedMaterial) {
        material.baseColorFactor = _colorOf(visual);
      } else if (material is UnlitMaterial) {
        material.baseColorFactor = _colorOf(visual);
      }
      return;
    }
    if (existing != null) {
      scene.remove(existing);
      _nodes.remove(key);
      _geometryIdentity.remove(key);
    }
    add(key, visual);
  }

  @override
  void remove(String key) {
    final existing = _nodes.remove(key);
    _geometryIdentity.remove(key);
    if (existing != null) scene.remove(existing);
  }

  /// ARGB int → the sink flavor of an RGBA vector.
  static vm.Vector4 _colorOf(VisualState visual) => vm.Vector4(
    ((visual.argb >> 16) & 0xFF) / 255,
    ((visual.argb >> 8) & 0xFF) / 255,
    (visual.argb & 0xFF) / 255,
    ((visual.argb >> 24) & 0xFF) / 255,
  );

  /// Builds the node for one visual. Geometry per [SceneShape]; color
  /// via the PBR base-color factor (an RGBA Vector4). `billboard` maps
  /// to a small UNLIT quad — always visible regardless of lighting;
  /// text labels are the inspector's 2D overlay concern, not geometry.
  Node? _build(VisualState visual) {
    final position = vm.Vector3(
      visual.position[0],
      visual.position.length > 1 ? visual.position[1] : 0,
      visual.position.length > 2 ? visual.position[2] : 0,
    );
    final color = _colorOf(visual);
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
  ///
  /// Grab-the-world convention under flutter_scene's LEFT-HANDED render
  /// (screen right = worldUp × forward; with the default view looking
  /// toward −Z, world +X renders on the LEFT): drag right → yaw += dx →
  /// the eye swings toward +X → content follows the finger right. Drag
  /// down → pitch lowers. Signs verified against getViewMatrix in the
  /// convention test; a right-handed assumption inverts the yaw.
  void orbit(double dx, double dy) {
    yaw += dx * 0.01;
    pitch = math.max(_minPitch, math.min(_maxPitch, pitch - dy * 0.01));
  }

  /// The camera eye as a camera Vector3.
  void zoom(double factor) {
    distance = math.max(
      _minDistance,
      math.min(_maxDistance, distance * factor),
    );
  }

  /// Point the rig at one world position (the inspector's focus action).
  void focus(List<double> position) => target = [
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

  /// The orbit target as a camera Vector3.
  vm.Vector3 cameraTarget() => vm.Vector3(target[0], target[1], target[2]);

  /// Pan: slide the orbit target across the ground plane, camera-relative
  /// (grab-the-world: drag right → content follows right; drag down →
  /// content follows down). Signs derived from flutter_scene's
  /// left-handed screen axes (right_g = (−cosYaw, +sinYaw),
  /// up_g = −(sinYaw, cosYaw) in world XZ); a right-handed assumption
  /// mirrors the X term. Scale rides distance so panning feels constant
  /// at any zoom.
  void pan(double dx, double dy) {
    final scale = distance * 0.0016;
    final sinYaw = math.sin(yaw);
    final cosYaw = math.cos(yaw);
    target = [
      target[0] + (dx * cosYaw - dy * sinYaw) * scale,
      target[1],
      target[2] + (-dx * sinYaw - dy * cosYaw) * scale,
    ];
  }
}
