// Parameters carry no `final`: this package compiles under language 3.13
// (where that modifier is an error) as well as 3.12.
// ignore_for_file: prefer_final_parameters

import 'package:ecsly_flutter_scene/ecsly_flutter_scene.dart';
import 'package:flutter_test/flutter_test.dart';

/// The gesture-feel law, stated declaratively: pan/orbit are
/// grab-the-world UNDER FLUTTER_SCENE'S LEFT-HANDED RENDER (screen right
/// = worldUp × forward). A handedness slip mirrors the X axis — exactly
/// the regression these tests pin.
void main() {
  group('SceneCameraRig.pan', () {
    test('yaw 0: drag right moves target +X, drag down moves -Z', () {
      // yaw 0 puts the eye on +Z looking toward -Z; flutter_scene renders
      // world +X on the LEFT, so grab-the-world drags the target toward
      // +X (content follows the finger left-to-right on screen).
      final rig = SceneCameraRig(target: [0, 0, 0], distance: 100, yaw: 0);
      rig.pan(10, 0);
      expect(rig.target[0], greaterThan(0));
      expect(rig.target[2], closeTo(0, 1e-9));
      final afterX = rig.target;
      rig.pan(0, 10);
      expect(rig.target[2], lessThan(afterX[2]));
      expect(rig.target[1], 0, reason: 'pan stays on the ground plane');
    });

    test('pan scale rides distance (constant screen feel)', () {
      final near = SceneCameraRig(distance: 10, yaw: 0);
      final far = SceneCameraRig(distance: 100, yaw: 0);
      near.pan(10, 0);
      far.pan(10, 0);
      expect(far.target[0].abs(), greaterThan(near.target[0].abs() * 5));
    });

    test('yaw pi/2: drag right moves target toward -Z', () {
      // At yaw pi/2 the eye sits on +X looking toward -X; screen right is
      // then world +Z, so a grab-the-world drag right slides the target
      // toward -Z (content follows the finger).
      final rig = SceneCameraRig(distance: 100, yaw: 1.5707963267948966);
      rig.pan(10, 0);
      expect(rig.target[2], lessThan(0));
      expect(rig.target[0], closeTo(0, 1e-6));
    });

    test('orbit still clamps pitch; zoom still clamps distance', () {
      final rig = SceneCameraRig(distance: 10);
      rig.orbit(0, 10000);
      expect(rig.pitch, lessThanOrEqualTo(1.45));
      rig.zoom(0.0001);
      expect(rig.distance, greaterThanOrEqualTo(0.5));
    });
  });

  group('SceneCameraRig.orbit signs', () {
    test('drag right swings the eye toward world +X (yaw grows)', () {
      // With the eye on +Z (yaw ~ 0) flutter_scene renders +X LEFT, so a
      // rightward drag must move the eye toward +X for the content to
      // follow the finger. This is the sign a right-handed assumption
      // gets backwards.
      final rig = SceneCameraRig(distance: 10, yaw: 0);
      rig.orbit(10, 0);
      expect(rig.yaw, greaterThan(0));
      expect(rig.cameraPosition().x, greaterThan(0));
    });

    test('drag down lowers the pitch (grab-the-world tilt)', () {
      final rig = SceneCameraRig(distance: 10, yaw: 0);
      rig.orbit(0, 10);
      expect(rig.pitch, lessThan(0.5));
    });
  });
}
