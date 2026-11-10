# ECS Camera Control Plugin DX_FAQ - Memory Palace

_Spatial organization for AI agent memory retention. Input-based camera control for ECS games._

## 🎮 Setup Station

```dart
import 'package:ecs_camera_control_plugin/ecs_camera_control_plugin.dart';

// Install dependencies first (required)
world.addPlugin(InputPlugin());
world.addPlugin(CameraPlugin());

// Then install camera control
world.addPlugin(CameraControlPlugin(
  enablePan: true,
  enableZoom: true,
  enableScrollZoom: true,
  enablePinchZoom: true,
  enableEntityDragging: false, // Enable if needed
));

// Action components registered automatically:
// - CameraPanAction, CameraZoomAction, CameraSelectAction, CameraDragAction
```

## 🎬 Preset Application

```dart
// Apply RTS camera preset (edge pan, scroll zoom, box select)
CameraPreset.rts.applyTo(world);

// Apply platformer camera preset (follow player)
CameraPreset.platformer.applyTo(world, followEntity: playerEntity);

// Apply top-down camera preset (free movement)
CameraPreset.topDown.applyTo(world);

// Apply isometric camera preset (45° angle, constrained)
CameraPreset.isometric.applyTo(world);

// Validate preset configuration
final validator = CameraPresetValidator(world);
final issues = validator.validatePreset(CameraPreset.rts);
if (issues.isNotEmpty) {
  print('Preset validation issues: $issues');
}
```

## ⚙️ Manual Configuration

```dart
// Get camera entity
final cameraQuery = world.queryExt<CameraComponent, CameraComponent>();
final cameraEntity = cameraQuery.first.$1;

// Configure keyboard pan (WASD)
world.getEntity(cameraEntity).insert(CameraPanAction(
  deltaX: 0.0,  // Set by input systems
  deltaY: 0.0,
  speedMultiplier: 1.0,
));

// Configure zoom actions
world.getEntity(cameraEntity).insert(CameraZoomAction(
  zoomDelta: 0.0,  // Positive = zoom in, negative = zoom out
  speedMultiplier: 1.0,
));

// Configure interaction mode
final modeResource = world.getResource<CameraInteractionModeResource>();
modeResource.mode = CameraInteractionMode.gameplay; // or editor, cinematic
```

## 🎯 Action Processing

```dart
// Handle camera pan actions
void processCameraPan(World world) {
  world.queryExt<CameraPanAction, CameraPanAction>().forEach((ext, action) {
    final camera = ext.getExtension<CameraPositionComponent, CameraPosition>();
    camera.targetX += action.deltaX * action.speedMultiplier;
    camera.targetY += action.deltaY * action.speedMultiplier;
  });
}

// Handle camera zoom actions
void processCameraZoom(World world) {
  world.queryExt<CameraZoomAction, CameraZoomAction>().forEach((ext, action) {
    final camera = ext.getExtension<CameraPositionComponent, CameraPosition>();
    final newZoom = camera.targetZoom * (1.0 + action.zoomDelta);
    camera.targetZoom = newZoom.clamp(0.1, 10.0);
  });
}

// Add to input schedule
world.schedule('Input').add(processCameraPan).then(processCameraZoom);
```

## 🎭 Interaction Mode Switching

```dart
// Switch to editor mode (free camera control)
final modeResource = world.getResource<CameraInteractionModeResource>();
modeResource.mode = CameraInteractionMode.editor;

// In editor mode, camera systems may behave differently
// (e.g., ignore follow targets, enable free movement)

// Switch to cinematic mode (disable input)
modeResource.mode = CameraInteractionMode.cinematic;

// Switch back to gameplay
modeResource.mode = CameraInteractionMode.gameplay;

// Query current mode
if (modeResource.mode == CameraInteractionMode.gameplay) {
  // Enable player controls
}
```

## 🖱️ Entity Dragging

```dart
// Enable entity dragging in plugin
world.addPlugin(CameraControlPlugin(
  enableEntityDragging: true,
  // ... other options
));

// Make entity draggable
world.getEntity(entity).insert(DraggableComponent(
  dragPlane: DragPlane.xy,  // or xz, yz
));

// Systems automatically handle:
// - Converting screen drag to world coordinates
// - Scaling movement by camera zoom
// - Updating entity position during drag
// - Drag start/end events

// Listen to drag events
void handleEntityDrag(World world) {
  final reader = world.events.reader<EntityDragEvent>();
  for (final event in reader.iter()) {
    final draggedEntity = event.entity;
    final dragDelta = event.worldDelta;
    // Custom drag logic if needed
  }
}
```

## 🎛️ Custom Control Systems

```dart
// Custom pan system (keyboard WASD)
void keyboardPanSystem(World world) {
  final tracker = world.getResource<InputStateTracker>();
  final cameraQuery = world.queryExt<CameraComponent, CameraComponent>();

  if (cameraQuery.isNotEmpty) {
    final (ext, _) = cameraQuery.first;
    final camera = ext.getExtension<CameraPositionComponent, CameraPosition>();

    double panX = 0.0;
    double panY = 0.0;

    if (tracker.isHeld(InputAction.moveLeft)) panX -= 100.0;
    if (tracker.isHeld(InputAction.moveRight)) panX += 100.0;
    if (tracker.isHeld(InputAction.moveUp)) panY -= 100.0;
    if (tracker.isHeld(InputAction.moveDown)) panY += 100.0;

    camera.targetX += panX * world.deltaTime;
    camera.targetY += panY * world.deltaTime;
  }
}

// Add to update schedule
world.schedule('Update').add(keyboardPanSystem);
```

## 🚨 Safety Zone

- ✅ Install InputPlugin and CameraPlugin before CameraControlPlugin
- ✅ Use presets for quick setup, manual config for customization
- ✅ Action components enable preprocessing before camera application
- ✅ Interaction modes control when camera accepts input
- ✅ Entity dragging requires DraggableComponent on entities
- ✅ Camera control systems run in Input schedule by default
- ✅ Validate presets before applying in production

**Memory Hook:** "Setup → Preset → Manual → Action → Mode → Drag → Custom"