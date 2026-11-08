// Parameters carry no `final`: this package compiles under language 3.13
// (where that modifier is an error) as well as 3.12.
// ignore_for_file: prefer_final_parameters

import 'package:ecsly_flutter_scene/ecsly_flutter_scene.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SceneCameraRig.pan', () {
    test('yaw 0: drag right moves target left (-X), drag down moves -Z', () {
      final rig = SceneCameraRig(target: [0, 0, 0], distance: 100, yaw: 0);
      rig.pan(10, 0);
      expect(rig.target[0], lessThan(0));
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

    test('yaw pi/2: drag right moves target toward +Z', () {
      final rig = SceneCameraRig(distance: 100, yaw: 1.5707963267948966);
      rig.pan(10, 0);
      expect(rig.target[2], greaterThan(0));
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
}
