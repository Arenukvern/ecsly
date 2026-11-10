import 'package:ecsly/ecsly.dart';

import 'components/camera_components.dart';
import 'components/inspect_camera_state_component.dart';
import 'resources/active_cameras_resource.dart';
import 'resources/camera_projection_mode_resource.dart';
import 'resources/inspect_camera_state_resource.dart';
import 'resources/viewport_size_resource.dart';

/// ECS Plugin for camera functionality.
///
/// Provides component-based camera system for 2D games.
/// Registers camera components and spawns a default active camera entity.
///
/// **Composable Architecture:**
/// - **Target Layer**: `FollowTarget`, `FollowGroupTarget`, `FixedTarget`, `FreeTarget` (mutually exclusive)
/// - **Control Layer**: `CameraController`, `CameraZoom`, `CameraSmoothing` (composable)
/// - **Effects Layer**: `CameraShake`, `CameraBlend`, `CameraConstraints` (composable)
/// - **Core Components**: `CameraPosition`, `CameraVelocity` (always present)
class CameraPlugin extends Plugin {
  /// Unique name for this plugin
  @override
  String get name => 'Camera';

  /// Install the camera plugin into the world.
  ///
  /// Registers camera components and spawns a default camera entity.
  @override
  void install(final World world) {
    // Register CameraComponent (regular component, uses ObjectColumn)
    world.components.registerObjectComponent<CameraComponent>();

    // Register extension components (TypedData for zero-GC)
    world.components.registerExtension<CameraPositionComponent, CameraPosition>(
      columnFactory: CameraPositionColumnFactory(),
      facadeFactory: CameraPositionFacadeFactory(),
    );

    world.components.registerExtension<CameraVelocityComponent, CameraVelocity>(
      columnFactory: CameraVelocityColumnFactory(),
      facadeFactory: CameraVelocityFacadeFactory(),
    );

    world.components.registerExtension<CameraPose3Component, CameraPose3>(
      columnFactory: CameraPose3ColumnFactory(),
      facadeFactory: CameraPose3FacadeFactory(),
    );

    world.components.registerExtension<CameraShakeComponent, CameraShake>(
      columnFactory: CameraShakeColumnFactory(),
      facadeFactory: CameraShakeFacadeFactory(),
    );

    // Register target components (mutually exclusive)
    world.components.registerObjectComponent<FollowTarget>();
    world.components.registerObjectComponent<FollowGroupTarget>();
    world.components.registerObjectComponent<FixedTarget>();
    world.components.registerObjectComponent<FreeTarget>();

    // Register control components (composable)
    world.components.registerObjectComponent<CameraController>();
    world.components.registerObjectComponent<CameraZoom>();
    world.components.registerObjectComponent<CameraSmoothing>();

    // Register effects components (composable)
    world.components.registerObjectComponent<CameraBlend>();
    world.components.registerObjectComponent<CameraConstraints>();
    world.components.registerObjectComponent<CameraRail2p5DConstraints>();
    world.components
        .registerExtension<InspectCameraStateComponent, InspectCameraState>(
          columnFactory: InspectCameraStateColumnFactory(),
          facadeFactory: InspectCameraStateFacadeFactory(),
        );

    // Register CameraZoomToFit component (camera behavior, not input control)
    world.components.registerObjectComponent<CameraZoomToFit>();

    world.components.registerObjectComponent<CameraViewportRectComponent>();

    // Register ViewportSizeResource (used by camera systems and UnifiedInputWidget)
    world.upsertResource(ViewportSizeResource());
    world.upsertResource(ActiveCamerasResource());
    world.upsertResource(CameraProjectionModeResource());
    world.upsertResource(InspectCameraStateResource());

    // Note: Action components (CameraPanAction, CameraZoomAction, etc.) are registered
    // by CameraControlPlugin, not here. This keeps camera plugin independent of input.

    // Spawn default camera with FreeTarget + Controller + Zoom + Smoothing
    final cameraEntity = world.entities.create();
    world.spawnBundle(
      cameraEntity,
      ComponentBundle.fromLists(
        [
          CameraComponent(),
          CameraViewportRectComponent(),
          FreeTarget(),
          CameraController(),
          CameraZoom(),
          CameraSmoothing(),
        ],
        [
          (CameraPositionComponent, CameraPosition),
          (CameraPose3Component, CameraPose3),
          (CameraVelocityComponent, CameraVelocity),
        ],
      ),
    );

    // Initialize camera position
    final (ext, _) = world.getEntity(cameraEntity);
    final pos = ext
        .toExtension()
        .getOrCreate<CameraPositionComponent, CameraPosition>();
    pos
      ..x = 0
      ..y = 0
      ..targetX = 0
      ..targetY = 0
      ..zoom = 1.0
      ..targetZoom = 1.0;

    final pose = ext
        .toExtension()
        .getOrCreate<CameraPose3Component, CameraPose3>();
    pose
      ..posZ = 0.0
      ..rotX = 0.0
      ..rotY = 0.0
      ..rotZ = 0.0
      ..rotW = 1.0
      ..zoomOrFovOverride = double.nan
      ..near = 0.1
      ..far = 1000.0;
  }
}
