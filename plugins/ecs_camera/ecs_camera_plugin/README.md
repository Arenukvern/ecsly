# ecs_camera_plugin

Low-level camera system plugin for ECS (position, velocity, targets, smoothing, constraints, shake) - **NO input dependency**.

## Overview

Pure camera layer that provides:
- Camera state: Position, Velocity, Zoom
- Camera behavior: FollowTarget, FixedTarget, FreeTarget
- Camera effects: Smoothing, Shake, Constraints, Blend
- Camera systems: Target following, smoothing, physics, constraints
- **NO input dependencies** - camera can be controlled programmatically

## Usage

```dart
import 'package:ecs_camera_plugin/ecs_camera_plugin.dart';

world.addPlugin(CameraPlugin());
```

## Features

- Component-based camera system
- Multiple target modes (follow, fixed, free)
- Smoothing and physics-based movement
- Camera shake effects
- Constraints and bounds
- **Can be controlled programmatically** - no input required

## Dependencies

- `ecs` - Core ECS package
- `flutter` - Flutter SDK
- `vector_math` - Vector math utilities

## Optional Dependencies

- `ecs_input_plugin` - For ViewportSizeResource (used by zoom-to-fit system)
- `game2d` - For PositionComponent (used by zoom-to-fit system)


