import 'package:ecsly/ecsly.dart';

import '../resources/camera_projection_mode_resource.dart';

/// Applies pending camera projection mode changes at frame boundaries only.
void cameraProjectionModeLatchSystem(final World world) {
  final mode = world.getResource<CameraProjectionModeResource>();
  mode.frameId += 1;

  if (mode.requestedMode == mode.effectiveMode) {
    return;
  }

  mode.effectiveMode = mode.requestedMode;
  mode.latchFrameId = mode.frameId;
}
