import 'package:ecs_camera_plugin/ecs_camera_plugin.dart';
import 'package:ecsly/ecsly.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('camera plugin registers inspect camera state primitives', () {
    final world = World()..addPlugin(CameraPlugin());

    expect(
      world.components.getComponentIdByType(InspectCameraStateComponent),
      isNotNull,
    );
    expect(world.resources.has<InspectCameraStateResource>(), isTrue);

    final resource = world.getResource<InspectCameraStateResource>();
    expect(resource.targetX, 0.0);
    expect(resource.targetY, 0.0);
    expect(resource.targetZ, 0.0);
    expect(resource.yawDeg, 0.0);
    expect(resource.pitchDeg, 0.0);
    expect(resource.distance, 12.0);
  });
}
