import 'package:ecsly/ecsly.dart';

import '../components/camera_components.dart';

/// Camera constraints system - applies bounds to camera position and zoom.
///
/// **IMPORTANT**: This system must run LAST in the camera schedule.
/// All other systems write unconstrained values, then this system clamps them.
void cameraConstraintsSystem(final World world) {
  for (final (_, pos, constraints)
      in world
          .queryExt2<
            CameraPositionComponent,
            CameraPosition,
            CameraConstraints,
            CameraConstraints
          >()) {
    constraints.constrainPosition(pos);
  }
}
