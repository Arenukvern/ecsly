import 'dart:ui' as ui;

import 'package:ecsly/ecsly.dart';
import 'package:ecs_camera_plugin/ecs_camera_plugin.dart';
import 'package:ecs_input_plugin/ecs_input_plugin.dart';
import 'package:flutter/services.dart';
import 'package:vector_math/vector_math_64.dart' as vm;

import 'components/camera_action_components.dart';

/// Predefined camera configurations for different game genres.
///
/// Each preset configures:
/// - Target behavior (follow player, free movement, fixed position)
/// - Control parameters (speed, zoom limits, smoothing)
/// - Input mappings (keyboard, mouse, gesture bindings)
/// - Action components (pan, zoom, select behaviors)
enum CameraPreset {
  /// RTS game camera (edge pan, scroll zoom, box select).
  ///
  /// - Free movement with WASD/arrows
  /// - Edge-of-screen panning
  /// - Scroll wheel zoom (handled directly by scrollZoomSystem)
  /// - Box selection with drag
  /// - Reset to center with R key
  rts,

  /// Platformer camera (follow player with smooth tracking).
  ///
  /// - Follows player entity
  /// - Smooth position/zoom transitions
  /// - Constrained movement bounds
  /// - Keyboard pan override
  /// - Limited zoom range
  platformer,

  /// Top-down camera (free movement with WASD).
  ///
  /// - Free camera movement
  /// - WASD + mouse controls
  /// - Scroll wheel zoom (handled directly by scrollZoomSystem)
  /// - Wide zoom range
  /// - No smoothing for direct control
  topDown,

  /// Isometric camera (45° angle with constrained movement).
  ///
  /// - Fixed isometric projection
  /// - Constrained pan bounds
  /// - Scroll wheel zoom (handled directly by scrollZoomSystem)
  /// - Moderate zoom range
  /// - Smooth movement
  isometric,

  /// Strategy game camera (similar to RTS but different bindings).
  ///
  /// - Free movement with arrow keys
  /// - Scroll wheel zoom (handled directly by scrollZoomSystem)
  /// - Right-click pan
  /// - Box selection
  strategy,

  /// RPG camera (follow player with free look).
  ///
  /// - Follows player entity
  /// - Mouse look rotation
  /// - Scroll wheel zoom (handled directly by scrollZoomSystem)
  /// - Keyboard pan override
  /// - Moderate zoom range
  /// - Smooth transitions
  rpg,
}

/// Extension methods for CameraPreset to provide default values.
extension CameraPresetFactory on CameraPreset {
  /// Default maximum zoom level for this preset.
  double get defaultMaxZoom => switch (this) {
    CameraPreset.rts => 3.0,
    CameraPreset.platformer => 2.0,
    CameraPreset.topDown => 5.0,
    CameraPreset.isometric => 2.5,
    CameraPreset.strategy => 4.0,
    CameraPreset.rpg => 3.0,
  };

  /// Default minimum zoom level for this preset.
  double get defaultMinZoom => switch (this) {
    CameraPreset.rts => 0.5,
    CameraPreset.platformer => 0.8,
    CameraPreset.topDown => 0.1,
    CameraPreset.isometric => 0.7,
    CameraPreset.strategy => 0.3,
    CameraPreset.rpg => 0.6,
  };

  /// Default movement speed for this preset.
  double get defaultMoveSpeed => switch (this) {
    CameraPreset.rts => 400.0,
    CameraPreset.platformer => 300.0,
    CameraPreset.topDown => 500.0,
    CameraPreset.isometric => 250.0,
    CameraPreset.strategy => 350.0,
    CameraPreset.rpg => 200.0,
  };

  /// Default smoothing speed for this preset.
  double get defaultSmoothingSpeed => switch (this) {
    CameraPreset.rts => 3.0,
    CameraPreset.platformer => 5.0,
    CameraPreset.topDown => 0.0, // No smoothing for direct control
    CameraPreset.isometric => 4.0,
    CameraPreset.strategy => 3.5,
    CameraPreset.rpg => 6.0,
  };

  /// Default zoom smoothing speed for this preset.
  double get defaultZoomSmoothingSpeed => switch (this) {
    CameraPreset.rts => 8.0,
    CameraPreset.platformer => 10.0,
    CameraPreset.topDown => 0.0,
    CameraPreset.isometric => 6.0,
    CameraPreset.strategy => 7.0,
    CameraPreset.rpg => 12.0,
  };

  /// Configures input mappings for this preset in the given map.
  void configureInputMap(final RuntimeInputMap map) {
    // Clear existing bindings first
    InputAction.values.forEach(map.clearAction);

    // Add preset-specific bindings
    _configureInputBindings(map);
  }

  /// Creates a component bundle for this preset.
  ///
  /// [followTarget] - Entity to follow (required for platformer/rpg presets)
  /// [constraints] - Movement bounds rectangle
  /// [moveSpeed] - Camera movement speed
  /// [minZoom] - Minimum zoom level
  /// [maxZoom] - Maximum zoom level
  ComponentBundle createBundle({
    final Entity? followTarget,
    final vm.Vector2? position,
    final ui.Rect? constraints,
    final double? moveSpeed,
    final double? minZoom,
    final double? maxZoom,
  }) {
    final components = <Component>[];

    // Add target component
    components.add(_createTargetComponent(followTarget, position, constraints));

    // Add control components
    components.addAll(_createControlComponents(moveSpeed, minZoom, maxZoom));

    // Add action components
    components.addAll(_createActionComponents());

    return ComponentBundle.fromLists(components, []);
  }

  void _configureInputBindings(final RuntimeInputMap map) {
    // Movement keys (shared across most presets)
    map.bindSingle(
      const KeyboardSource(LogicalKeyboardKey.keyW),
      InputAction.moveUp,
    );
    map.bindSingle(
      const KeyboardSource(LogicalKeyboardKey.keyA),
      InputAction.moveLeft,
    );
    map.bindSingle(
      const KeyboardSource(LogicalKeyboardKey.keyS),
      InputAction.moveDown,
    );
    map.bindSingle(
      const KeyboardSource(LogicalKeyboardKey.keyD),
      InputAction.moveRight,
    );

    // Arrow key alternatives
    map.bindSingle(
      const KeyboardSource(LogicalKeyboardKey.arrowUp),
      InputAction.moveUp,
    );
    map.bindSingle(
      const KeyboardSource(LogicalKeyboardKey.arrowLeft),
      InputAction.moveLeft,
    );
    map.bindSingle(
      const KeyboardSource(LogicalKeyboardKey.arrowDown),
      InputAction.moveDown,
    );
    map.bindSingle(
      const KeyboardSource(LogicalKeyboardKey.arrowRight),
      InputAction.moveRight,
    );

    // Keyboard zoom keys (always available)
    // Note: Scroll zoom is handled directly by scrollZoomSystem, not through action bindings
    // Bind = key for zoom in (works with or without Shift depending on keyboard layout)
    map.bindSingle(
      const KeyboardSource(LogicalKeyboardKey.equal),
      InputAction.zoomIn,
    );
    map.bindSingle(
      const KeyboardSource(LogicalKeyboardKey.minus),
      InputAction.zoomOut,
    );

    // Preset-specific bindings
    switch (this) {
      case CameraPreset.rts:
        // RTS uses middle mouse for pan, scroll for zoom
        map.bindSingle(
          const GestureSource(GestureType.drag),
          InputAction.cameraPan,
        );
        map.bindSingle(
          const GestureSource(GestureType.scroll),
          InputAction.zoomIn,
        );
        map.bindSingle(
          const KeyboardSource(LogicalKeyboardKey.keyR),
          InputAction.cameraReset,
        );
        map.bindSingle(
          const MouseButtonSource(0),
          InputAction.attack,
        ); // Left click

      case CameraPreset.platformer:
        // Platformer uses gestures for camera control
        map.bindSingle(
          const GestureSource(GestureType.drag),
          InputAction.cameraPan,
        );
        map.bindSingle(
          const GestureSource(GestureType.scroll),
          InputAction.zoomIn,
        );
        map.bindSingle(
          const KeyboardSource(LogicalKeyboardKey.space),
          InputAction.jump,
        );
        map.bindSingle(
          const KeyboardSource(LogicalKeyboardKey.keyX),
          InputAction.attack,
        );

      case CameraPreset.topDown:
        // Top-down is pure keyboard/mouse control
        map.bindSingle(
          const MouseButtonSource(2),
          InputAction.cameraPan,
        ); // Right click
        map.bindSingle(
          const GestureSource(GestureType.scroll),
          InputAction.zoomIn,
        );
        map.bindSingle(
          const KeyboardSource(LogicalKeyboardKey.space),
          InputAction.jump,
        );

      case CameraPreset.isometric:
        // Isometric uses drag gesture for panning
        map.bindSingle(
          const GestureSource(GestureType.drag),
          InputAction.cameraPan,
        );
        map.bindSingle(
          const GestureSource(GestureType.scroll),
          InputAction.zoomIn,
        );
        map.bindSingle(
          const KeyboardSource(LogicalKeyboardKey.keyR),
          InputAction.cameraReset,
        );

      case CameraPreset.strategy:
        // Strategy uses arrow keys for movement
        map.bindSingle(
          const MouseButtonSource(2),
          InputAction.cameraPan,
        ); // Right click
        map.bindSingle(
          const GestureSource(GestureType.scroll),
          InputAction.zoomIn,
        );
        map.bindSingle(
          const MouseButtonSource(0),
          InputAction.attack,
        ); // Left click

      case CameraPreset.rpg:
        // RPG uses mouse look
        map.bindSingle(
          const GestureSource(GestureType.drag),
          InputAction.cameraPan,
        );
        map.bindSingle(
          const GestureSource(GestureType.scroll),
          InputAction.zoomIn,
        );
        map.bindSingle(
          const KeyboardSource(LogicalKeyboardKey.space),
          InputAction.jump,
        );
        map.bindSingle(
          const KeyboardSource(LogicalKeyboardKey.keyE),
          InputAction.interact,
        );
    }
  }

  List<Component> _createActionComponents() => switch (this) {
    CameraPreset.rts => [
      const CameraPanAction(
        trigger: InputAction.cameraPan,
        mode: PanMode.velocity, // Direct velocity for precise drag control
      ),
      const CameraZoomAction(trigger: InputAction.zoomIn),
      const CameraZoomAction(trigger: InputAction.zoomOut),
      const CameraSelectAction(
        singleSelect: InputAction.attack,
        boxSelect: InputAction.cameraPan,
      ),
    ],
    CameraPreset.platformer => [
      const CameraPanAction(), // No trigger = always active, uses getAxis2D
      const CameraZoomAction(trigger: InputAction.zoomIn),
      const CameraZoomAction(trigger: InputAction.zoomOut),
    ],
    CameraPreset.topDown => [
      const CameraPanAction(), // No trigger = always active, uses getAxis2D
      const CameraZoomAction(trigger: InputAction.zoomIn),
      const CameraZoomAction(trigger: InputAction.zoomOut),
    ],
    CameraPreset.isometric => [
      const CameraPanAction(trigger: InputAction.cameraPan),
      const CameraZoomAction(trigger: InputAction.zoomIn),
      const CameraZoomAction(trigger: InputAction.zoomOut),
    ],
    CameraPreset.strategy => [
      const CameraPanAction(), // No trigger = always active, uses getAxis2D
      const CameraZoomAction(trigger: InputAction.zoomIn),
      const CameraZoomAction(trigger: InputAction.zoomOut),
      const CameraSelectAction(
        singleSelect: InputAction.attack,
        boxSelect: InputAction.cameraPan,
      ),
    ],
    CameraPreset.rpg => [
      const CameraPanAction(trigger: InputAction.cameraPan),
      const CameraZoomAction(trigger: InputAction.zoomIn),
      const CameraZoomAction(trigger: InputAction.zoomOut),
    ],
  };

  List<Component> _createControlComponents(
    final double? moveSpeed,
    final double? minZoom,
    final double? maxZoom,
  ) {
    final components = <Component>[];

    // Camera controller (movement)
    final speed = moveSpeed ?? defaultMoveSpeed;
    components.add(CameraController(moveSpeed: speed));

    // Camera zoom (only zoomSpeed, limits come from CameraConstraints)
    components.add(CameraZoom());

    // Camera constraints (zoom limits)
    final minZ = minZoom ?? defaultMinZoom;
    final maxZ = maxZoom ?? defaultMaxZoom;
    components.add(CameraConstraints(minZoom: minZ, maxZoom: maxZ));

    // Smoothing (except for direct-control presets)
    if (this != CameraPreset.topDown && this != CameraPreset.rts) {
      components.add(
        CameraSmoothing(
          positionSpeed: defaultSmoothingSpeed,
          zoomSpeed: defaultZoomSmoothingSpeed,
        ),
      );
    }

    return components;
  }

  Component _createTargetComponent(
    final Entity? followTarget,
    final vm.Vector2? position,
    final ui.Rect? constraints,
  ) => switch (this) {
    CameraPreset.platformer || CameraPreset.rpg =>
      followTarget != null
          ? FollowTarget(followTarget, deadZone: 50)
          : FreeTarget(),
    CameraPreset.rts ||
    CameraPreset.topDown ||
    CameraPreset.strategy => FreeTarget(),
    CameraPreset.isometric => FixedTarget(
      position?.x ?? 0.0,
      position?.y ?? 0.0,
    ),
  };
}
