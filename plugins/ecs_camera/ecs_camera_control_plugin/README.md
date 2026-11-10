# ecs_camera_control_plugin

Camera control via input - wires InputPlugin and CameraPlugin together.

## Overview

Integration layer that provides:

- Camera action components: CameraPanAction, CameraZoomAction, CameraSelectAction, CameraDragAction
- Control systems: genericCameraPanSystem, genericCameraZoomSystem, scrollZoomSystem, pinchZoomSystem, scrollToZoomActionSystem, entityDraggingSystem
- Utility functions: getCameraZoomConstraints(), getCameraZoom()
- Camera interaction resource: CameraInteractionModeResource
- Entity dragging with zoom-aware movement scaling
- Camera presets with input bindings
- **Requires both InputPlugin and CameraPlugin** - validates dependencies on install

## Usage

### Plugin Installation

```dart
import 'package:ecs_input_plugin/ecs_input_plugin.dart';
import 'package:ecs_camera_plugin/ecs_camera_plugin.dart';
import 'package:ecs_camera_control_plugin/ecs_camera_control_plugin.dart';

// Install dependencies first
world.addPlugin(const InputPlugin());
world.addPlugin(CameraPlugin());

// Then install control plugin
world.addPlugin(const CameraControlPlugin());
```

### Widget Setup

**CRITICAL:** For gesture-based camera control (pinch zoom, drag pan, scroll zoom) to work, you must wrap your widget tree with `UnifiedInputWidget`:

```dart
import 'package:ecs_flutter_plugins/ecs_flutter_plugins.dart';
import 'package:ecs_input_plugin/ecs_input_plugin.dart';

Widget build(BuildContext context) {
  return UnifiedInputWidget(
    world: world,
    child: GameLoopWidget(
      world: world,
      child: YourGameContent(),
    ),
  );
}
```

## Features

- Input-based camera panning (keyboard, drag)
- Input-based camera zooming (keyboard, scroll, pinch)
- Camera interaction modes (game/editor/cinematic)
- Camera presets with pre-configured input bindings
- Runtime input rebinding support
- Multiple zoom systems (direct scroll, action-based, pinch)

## Dependencies

- `ecs_input_plugin` - Required
- `ecs_camera_plugin` - Required
- `ecs` - Core ECS package
- `flutter` - Flutter SDK

## Migration

**Old Code:**

```dart
world.addPlugin(const InputPlugin());
world.addPlugin(CameraPlugin());
```

**New Code:**

```dart
world.addPlugin(const InputPlugin());
world.addPlugin(CameraPlugin());
world.addPlugin(const CameraControlPlugin()); // Optional - for input-based control
```
