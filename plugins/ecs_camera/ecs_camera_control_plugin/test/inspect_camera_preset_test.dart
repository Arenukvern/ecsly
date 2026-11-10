import 'package:ecs_camera_control_plugin/ecs_camera_control_plugin.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('resolves inspect preset mapping and clamping deterministically', () {
    final front = resolveInspectCameraPresetPose(
      preset: InspectCameraPreset.front,
      targetX: 10.0,
      targetY: -2.0,
      targetZ: 4.0,
      distance: 24.0,
    );
    expect(front.targetX, 10.0);
    expect(front.targetY, -2.0);
    expect(front.targetZ, 4.0);
    expect(front.yawDeg, 0.0);
    expect(front.pitchDeg, 0.0);
    expect(front.distance, 24.0);

    final back = resolveInspectCameraPresetPose(
      preset: InspectCameraPreset.back,
      targetX: 10.0,
      targetY: -2.0,
      targetZ: 4.0,
      distance: 24.0,
    );
    expect(back.yawDeg, 180.0);
    expect(back.pitchDeg, 0.0);

    final left = resolveInspectCameraPresetPose(
      preset: InspectCameraPreset.left,
      targetX: 10.0,
      targetY: -2.0,
      targetZ: 4.0,
      distance: 24.0,
    );
    expect(left.yawDeg, -90.0);

    final right = resolveInspectCameraPresetPose(
      preset: InspectCameraPreset.right,
      targetX: 10.0,
      targetY: -2.0,
      targetZ: 4.0,
      distance: 24.0,
    );
    expect(right.yawDeg, 90.0);

    final top = resolveInspectCameraPresetPose(
      preset: InspectCameraPreset.top,
      targetX: 10.0,
      targetY: -2.0,
      targetZ: 4.0,
      distance: 5000.0,
      minPitchDeg: -10.0,
      maxPitchDeg: 60.0,
      minDistance: 1.0,
      maxDistance: 120.0,
    );
    expect(top.yawDeg, 0.0);
    expect(top.pitchDeg, 60.0);
    expect(top.distance, 120.0);

    final iso = resolveInspectCameraPresetPose(
      preset: InspectCameraPreset.iso,
      targetX: 10.0,
      targetY: -2.0,
      targetZ: 4.0,
      distance: 0.01,
      minDistance: 1.0,
      maxDistance: 120.0,
    );
    expect(iso.yawDeg, 45.0);
    expect(iso.pitchDeg, closeTo(35.264389682754654, 1e-12));
    expect(iso.distance, 1.0);

    final reset = resolveInspectCameraPresetPose(
      preset: InspectCameraPreset.reset,
      targetX: 10.0,
      targetY: -2.0,
      targetZ: 4.0,
      distance: 18.0,
    );
    expect(reset.yawDeg, 0.0);
    expect(reset.pitchDeg, 0.0);
    expect(reset.distance, 18.0);
  });
}
