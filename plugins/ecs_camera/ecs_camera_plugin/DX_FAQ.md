# ECS Camera Plugin DX_FAQ - Memory Palace

_Spatial organization for AI agent memory retention. Component-based camera system for 2D games._

## 🎬 Setup Station

```dart
import 'package:ecs_camera_plugin/ecs_camera_plugin.dart';

// Install camera plugin (creates default camera)
world.addPlugin(CameraPlugin());

// Components registered automatically:
// - CameraComponent, CameraPositionComponent, CameraVelocityComponent
// - Target: FollowTarget, FollowGroupTarget, FixedTarget, FreeTarget
// - Control: CameraController, CameraZoom, CameraSmoothing
// - Effects: CameraShake, CameraBlend, CameraConstraints
```

```dart
// Projection mode switching (latched at frame boundary)
final projection = world.getResource<CameraProjectionModeResource>();
projection.requestedMode = CameraProjectionMode.perspective3d;
cameraProjectionModeLatchSystem(world);
```

## 🎯 Target Configuration

```dart
// Get default camera entity
final cameraQuery = world.queryExt<CameraComponent, CameraComponent>();
final cameraEntity = cameraQuery.first.$1;

// Follow single entity
world.getEntity(cameraEntity).insert(FollowTarget(
  entity: playerEntity,
  offset: const Offset(50, -20), // Leading camera
  deadZone: 10.0, // Don't follow small movements
));

// Follow multiple entities (fit all in view)
world.getEntity(cameraEntity).insert(FollowGroupTarget(
  entities: [player1, player2],
  mode: FollowGroupMode.fitBounds,
  padding: 50.0,
));

// Fixed position camera
world.getEntity(cameraEntity).insert(FixedTarget(
  position: const Offset(100, 100),
));

// Free camera (programmatic control)
world.getEntity(cameraEntity).insert(FreeTarget());
```

## 🎮 Control Configuration

```dart
// Configure camera movement speed and limits
world.getEntity(cameraEntity).insert(CameraController(
  panSpeed: 200.0,    // Units per second
  zoomSpeed: 2.0,     // Zoom factor per second
  minZoom: 0.5,
  maxZoom: 3.0,
));

// Configure smoothing (lerp-based interpolation)
world.getEntity(cameraEntity).insert(CameraSmoothing(
  positionSmoothing: 5.0,  // How fast position lerps
  zoomSmoothing: 8.0,      // How fast zoom lerps
));

// Configure zoom behavior
world.getEntity(cameraEntity).insert(CameraZoom(
  zoomSpeed: 2.0,
  minZoom: 0.1,
  maxZoom: 10.0,
));
```

## 🌊 Effect Application

```dart
// Add screen shake effect
world.getEntity(cameraEntity).insert(CameraShake(
  intensity: 5.0,
  duration: 0.5,
  frequency: 20.0,
));

// Add camera blending (smooth transitions)
world.getEntity(cameraEntity).insert(CameraBlend(
  blendTime: 1.0,
  easeType: CameraBlendEase.smooth,
));

// Add movement constraints
world.getEntity(cameraEntity).insert(CameraConstraints(
  minX: -1000,
  maxX: 1000,
  minY: -1000,
  maxY: 1000,
  constrainZoom: true,
  minZoom: 0.5,
  maxZoom: 2.0,
));
```

## 📐 Coordinate Conversion

```dart
// Convert screen to world coordinates
final converter = CameraCoordinateConverter(world: world);
final worldPos = converter.screenToWorld(screenOffset);

// Convert world to screen coordinates
final screenPos = converter.worldToScreen(worldOffset);

// Get camera position and zoom
final (ext, _) = world.getEntity(cameraEntity);
final pos = ext.getExtension<CameraPositionComponent, CameraPosition>();
final currentX = pos.x;
final currentY = pos.y;
final currentZoom = pos.zoom;
```

## 🎨 Rendering Integration

```dart
// Use camera in custom painter
class GamePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final converter = CameraCoordinateConverter(world: world);

    // Transform canvas to camera view
    final cameraTransform = converter.getCameraTransform(size);
    canvas.transform(cameraTransform.storage);

    // Draw world content (coordinates are now in world space)
    canvas.drawCircle(Offset(100, 100), 10, paint);
  }
}
```

## 🎭 Programmatic Control

```dart
// Set camera target position (smooth lerp)
final (ext, _) = world.getEntity(cameraEntity);
final pos = ext.getExtension<CameraPositionComponent, CameraPosition>();
pos.targetX = 500.0;
pos.targetY = 300.0;
pos.targetZoom = 2.0;

// Set camera velocity (physics-based movement)
final vel = ext.getExtension<CameraVelocityComponent, CameraVelocity>();
vel.x = 100.0;  // Units per second
vel.y = 50.0;
```

## 🚨 Safety Zone

- ✅ Install CameraPlugin for component registration
- ✅ Only one target component per camera entity
- ✅ Use targetX/targetY for smooth movement, x/y for immediate
- ✅ Add smoothing for natural camera feel
- ✅ Use coordinate converter for screen/world transformations
- ✅ Camera systems run automatically after plugin installation
- ✅ Default camera created with FreeTarget + basic controls

**Memory Hook:** "Setup → Target → Control → Effects → Coordinates → Rendering → Control"
