// ignore_for_file: prefer_final_parameters, prefer_const_constructors
import 'dart:math' as math;

import 'package:ecsly_flutter_scene/ecsly_flutter_scene.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'recording_sink.dart';

/// The camera-math law: picking and projection are TWO reads of ONE
/// basis — a world position projected through the basis lands on the
/// same pixel a ray through that pixel picks the sphere at.
void main() {
  // A rig-shaped camera: eye orbiting the origin at distance 10, the
  // inspector's default (yaw 0.6, pitch 0.5).
  final eye = vm.Vector3(
    10 * math.cos(0.5) * math.sin(0.6),
    10 * math.sin(0.5),
    10 * math.cos(0.5) * math.cos(0.6),
  );
  final basis = SceneCameraBasis(
    eye: eye.storage.toList(),
    target: [0, 0, 0],
    aspect: 4 / 3,
  );

  test('a sphere at the target is hit by the ray through the viewport center',
      () {
    final ray = basis.rayThrough(0, 0);
    final t = raySphere(ray, vm.Vector3.zero(), 0.25);
    expect(t, isNotNull);
    expect(t, closeTo(10 - 0.25, 0.5));
  });

  test('a sphere off the frustum is missed', () {
    final ray = basis.rayThrough(0, 0);
    // Far outside the horizontal frustum at depth 10 (half-width ~4.1).
    expect(raySphere(ray, vm.Vector3(30, 0, 0), 0.25), isNull);
    // Behind the camera.
    expect(raySphere(ray, eye * 2, 0.25), isNull);
  });

  test('pickVisuals reports the NEAREST named sphere and skips unnamed',
      () {
    final near = VisualState(
      shape: SceneShape.sphere,
      argb: 0xFF000001,
      size: 0.25,
      position: [0, 0, 0],
      pickId: 'near',
    );
    final far = VisualState(
      shape: SceneShape.sphere,
      argb: 0xFF000002,
      size: 0.25,
      position: [0, 0, -3],
      pickId: 'far',
    );
    final step = VisualState(
      shape: SceneShape.cuboid,
      argb: 0xFF000003,
      size: 0.5,
      position: [0, 0, 1],
      pickId: 'never-a-cuboid',
    );
    final unnamed = VisualState(
      shape: SceneShape.sphere,
      argb: 0xFF000004,
      size: 5,
      position: [0, 0, 5],
    );
    final hit = pickVisuals(
      visuals: {
        'far|e1': far,
        'near|e2': near,
        'step|e3': step,
        'unnamed|e4': unnamed,
      },
      ray: basis.rayThrough(0, 0),
    );
    expect(hit, isNotNull);
    expect(hit!.pickId, 'near');
    // A cuboid on the ray never intercepts; an unnamed sphere never
    // intercepts (the pick grammar names its targets).
    expect(
      pickVisuals(visuals: {'step|e3': step}, ray: basis.rayThrough(0, 0)),
      isNull,
    );
  });

  test('projection and picking agree: the projected pixel picks the sphere',
      () {
    final world = vm.Vector3(1.5, 0.4, -0.5);
    final (ndcX, ndcY) = basis.ndcOfWorld(world)!;
    final ray = basis.rayThrough(ndcX, ndcY);
    final t = raySphere(ray, world, 0.25);
    expect(t, isNotNull);
    // The ray reaches the sphere roughly at the projected depth.
    expect(t, closeTo((world - eye).length, 0.3));
    // NDC bounds sanity: inside the frustum.
    expect(ndcX, inInclusiveRange(-1, 1));
    expect(ndcY, inInclusiveRange(-1, 1));
  });

  test('pointer pixels round-trip through NDC', () {
    final (ndcX, ndcY) = basis.ndcOfPointer(200, 150, 800, 600);
    expect(ndcX, closeTo(-0.5, 1e-9));
    expect(ndcY, closeTo(0.5, 1e-9));
  });

  test('ground decorations collect under stable static keys', () {
    final world = buildWorld();
    final mapping = SceneMapping()
      ..ground = (w) => [
            VisualState(
              shape: SceneShape.polyline,
              argb: 0xFF6B6B6B,
              size: 0.03,
              position: [0, -1, 0],
              points: [
                [0, -1, 0],
                [1, -1, 0],
              ],
            ),
          ];
    final collected = mapping.collect(world);
    expect(collected, hasLength(1));
    expect(collected.keys.first, 'static|g0');
  });
}
