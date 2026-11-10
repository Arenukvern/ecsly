import 'package:ecs_camera_plugin/ecs_camera_plugin.dart';
import 'package:ecsly/ecsly.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('projection mode switches only on latch system frame boundary', () {
    final world = World()..addPlugin(CameraPlugin());
    final mode = world.getResource<CameraProjectionModeResource>();

    expect(mode.effectiveMode, CameraProjectionMode.orthographic2d);
    mode.requestedMode = CameraProjectionMode.perspective3d;

    expect(mode.effectiveMode, CameraProjectionMode.orthographic2d);
    cameraProjectionModeLatchSystem(world);
    expect(mode.effectiveMode, CameraProjectionMode.perspective3d);
    expect(mode.latchFrameId, mode.frameId);
  });
}
