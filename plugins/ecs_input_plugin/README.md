# ecs_input_plugin

## Publish status

- Package: `ecs_input_plugin`
- Canonical import: `package:ecs_input_plugin/ecs_input_plugin.dart`
- Private package (`publish_to: none`). Not published on pub.dev.
- Workspace dependency example:
  ```yaml
  dependencies:
    ecs_input_plugin:
      path: ../ecs_input_plugin
  ```

Low-level input handling plugin for ECS (events, gestures, actions, resources) - **NO camera dependency**.

## Overview

Pure input layer that provides:
- Events: RawPointerDownEvent, TapEvent, DragEvent, ScrollEvent, etc.
- Gesture classification and hit testing
- Entity selection and dragging
- Input resources: InputStateTracker, SelectionManager, etc.
- **NO camera action components or camera control systems**

## Usage

```dart
import 'package:ecs_input_plugin/ecs_input_plugin.dart';

world.addPlugin(const InputPlugin());
```

## Features

- Event-driven input system
- Gesture classification (tap, drag, pinch, scroll)
- Entity interaction (selection, dragging)
- Input action mapping
- Runtime key rebinding

## Dependencies

- `ecs` - Core ECS package
- `flutter` - Flutter SDK

## Optional Dependencies

- `game2d` - For PositionComponent (used by entity dragging/selection systems)
- `ecs_camera_plugin` - For zoom-aware hit testing (optional, systems work without it)
