/// InputPlugin for registering gesture events and input resources.
///
/// This plugin sets up the event-driven input system by registering all
/// gesture event types and ensuring required resources are available.
library;

import 'dart:ui' as ui;

import 'package:ecsly/ecsly.dart';
import 'package:flutter/services.dart' as services;

import 'draggable_components/draggable_component.dart';
import 'events/input_action_event.dart';
import 'gesture_events.dart';
import 'input_action.dart';
import 'raw_input_events.dart';
import 'resources/cursor_position_resource.dart';
import 'resources/gesture_classification_state.dart';
import 'resources/gesture_consumption_tracker.dart';
import 'resources/input_state_tracker.dart';
import 'resources/interactive_entities_cache.dart';
import 'resources/runtime_input_map.dart';
import 'resources/selection_manager.dart';
import 'systems/input_systems.dart';

/// Plugin that configures the event-driven input system.
///
/// Installs this plugin to automatically register all gesture events
/// with appropriate capacities and ensure GestureClassificationState is available.
class InputPlugin extends Plugin {
  /// Capacity for tap, double-tap, long-press, and secondary tap events
  final int tapCapacity;

  /// Capacity for drag events
  final int dragCapacity;

  /// Capacity for pinch events
  final int pinchCapacity;

  /// Capacity for scroll events
  final int scrollCapacity;

  /// Whether to configure the input schedule automatically
  final bool configureSchedule;

  /// Capacity for entity-specific events
  final int entityEventCapacity;

  /// Creates an InputPlugin.
  ///
  /// [tapCapacity] - Capacity for tap events (default: 200)
  /// [dragCapacity] - Capacity for drag events (default: 200)
  /// [pinchCapacity] - Capacity for pinch events (default: 50)
  /// [scrollCapacity] - Capacity for scroll events (default: 50)
  /// [entityEventCapacity] - Capacity for entity-specific events (default: 100)
  /// [configureSchedule] - Whether to configure the input schedule automatically
  const InputPlugin({
    this.tapCapacity = 200,
    this.dragCapacity = 200,
    this.pinchCapacity = 50,
    this.scrollCapacity = 50,
    this.entityEventCapacity = 100,
    this.configureSchedule = true,
  });

  @override
  String get name => 'Input';

  @override
  void install(final World world) {
    // 1. Register all components
    world.components.registerObjectComponent<InteractiveElement>();
    world.components.registerObjectComponent<SelectableComponent>();
    world.components.registerObjectComponent<SelectionHighlightComponent>();
    world.components.registerObjectComponent<DraggableComponent>();

    // 2. Register all resources
    world.upsertResource(GestureClassificationState());
    world.upsertResource(InteractiveEntitiesCache());
    world.upsertResource(GestureConsumptionTracker());
    world.upsertResource(InputStateTracker());
    world.upsertResource(SelectionManager());
    world.upsertResource(CursorPositionResource());
    // Note: ViewportSizeResource is now provided by camera plugin
    // UnifiedInputWidget will update it if it exists

    // 3. Register all events (below)
    // 4. Initialize runtime input map (below)

    // Register raw input events (sent from UnifiedInputWidget)
    world.events.register<RawPointerDownEvent>(
      capacity: dragCapacity,
      fromDoubleFieldsFactory: RawPointerDownEvent.fromDoubleFields,
      sampleEvent: const RawPointerDownEvent(
        position: ui.Offset.zero,
        worldPosition: ui.Offset.zero,
        timestamp: 0,
        pointer: 0,
      ),
    );

    world.events.register<RawPointerMoveEvent>(
      capacity: dragCapacity,
      fromDoubleFieldsFactory: RawPointerMoveEvent.fromDoubleFields,
      sampleEvent: const RawPointerMoveEvent(
        position: ui.Offset.zero,
        worldPosition: ui.Offset.zero,
        delta: ui.Offset.zero,
        timestamp: 0,
        pointer: 0,
      ),
    );

    world.events.register<RawPointerUpEvent>(
      capacity: dragCapacity,
      fromDoubleFieldsFactory: RawPointerUpEvent.fromDoubleFields,
      sampleEvent: const RawPointerUpEvent(
        position: ui.Offset.zero,
        worldPosition: ui.Offset.zero,
        timestamp: 0,
        pointer: 0,
      ),
    );

    world.events.register<RawPointerCancelEvent>(
      capacity: 50,
      fromDoubleFieldsFactory: RawPointerCancelEvent.fromDoubleFields,
      sampleEvent: const RawPointerCancelEvent(timestamp: 0, pointer: 0),
    );

    // Register raw keyboard events (sent from UnifiedInputWidget)
    world.events.register<RawKeyDownEvent>(
      capacity: 50,
      fromDoubleFieldsFactory: RawKeyDownEvent.fromDoubleFields,
      sampleEvent: RawKeyDownEvent(
        key: services.LogicalKeyboardKey.space,
        timestamp: 0,
      ),
    );

    world.events.register<RawKeyUpEvent>(
      capacity: 50,
      fromDoubleFieldsFactory: RawKeyUpEvent.fromDoubleFields,
      sampleEvent: RawKeyUpEvent(
        key: services.LogicalKeyboardKey.space,
        timestamp: 0,
      ),
    );

    world.events.register<RawKeyRepeatEvent>(
      capacity: 100,
      fromDoubleFieldsFactory: RawKeyRepeatEvent.fromDoubleFields,
      sampleEvent: RawKeyRepeatEvent(
        key: services.LogicalKeyboardKey.space,
        timestamp: 0,
      ),
    );

    world.events.register<RawScaleStartEvent>(
      capacity: pinchCapacity,
      fromDoubleFieldsFactory: RawScaleStartEvent.fromDoubleFields,
      sampleEvent: const RawScaleStartEvent(
        focalPoint: ui.Offset.zero,
        timestamp: 0,
      ),
    );

    world.events.register<RawScaleUpdateEvent>(
      capacity: pinchCapacity,
      fromDoubleFieldsFactory: RawScaleUpdateEvent.fromDoubleFields,
      sampleEvent: const RawScaleUpdateEvent(
        focalPoint: ui.Offset.zero,
        focalPointDelta: ui.Offset.zero,
        rotation: 0.0,
        pointerCount: 0,
        scale: 1,
        timestamp: 0,
      ),
    );

    world.events.register<RawScaleEndEvent>(
      capacity: pinchCapacity,
      fromDoubleFieldsFactory: RawScaleEndEvent.fromDoubleFields,
      sampleEvent: const RawScaleEndEvent(timestamp: 0),
    );

    // Register global gesture events with appropriate capacities
    world.events.register<TapEvent>(
      capacity: tapCapacity,
      fromDoubleFieldsFactory: TapEvent.fromDoubleFields,
      sampleEvent: const TapEvent(
        position: ui.Offset.zero,
        worldPosition: ui.Offset.zero,
        timestamp: 0,
      ),
    );

    world.events.register<DoubleTapEvent>(
      capacity: tapCapacity,
      fromDoubleFieldsFactory: DoubleTapEvent.fromDoubleFields,
      sampleEvent: const DoubleTapEvent(
        position: ui.Offset.zero,
        worldPosition: ui.Offset.zero,
        timestamp: 0,
      ),
    );

    world.events.register<LongPressEvent>(
      capacity: tapCapacity,
      fromDoubleFieldsFactory: LongPressEvent.fromDoubleFields,
      sampleEvent: const LongPressEvent(
        position: ui.Offset.zero,
        worldPosition: ui.Offset.zero,
        timestamp: 0,
      ),
    );

    world.events.register<DragEvent>(
      capacity: dragCapacity,
      fromDoubleFieldsFactory: DragEvent.fromDoubleFields,
      sampleEvent: const DragEvent(
        position: ui.Offset.zero,
        worldPosition: ui.Offset.zero,
        startPosition: ui.Offset.zero,
        startWorldPosition: ui.Offset.zero,
        delta: ui.Offset.zero,
        timestamp: 0,
      ),
    );

    world.events.register<PinchEvent>(
      capacity: pinchCapacity,
      fromDoubleFieldsFactory: PinchEvent.fromDoubleFields,
      sampleEvent: const PinchEvent(
        position: ui.Offset.zero,
        worldPosition: ui.Offset.zero,
        scale: 1,
        focalPoint: ui.Offset.zero,
        focalPointDelta: ui.Offset.zero,
        rotation: 0.0,
        pointerCount: 0,
        timestamp: 0,
      ),
    );

    world.events.register<ScrollEvent>(
      capacity: scrollCapacity,
      fromDoubleFieldsFactory: ScrollEvent.fromDoubleFields,
      sampleEvent: const ScrollEvent(
        position: ui.Offset.zero,
        worldPosition: ui.Offset.zero,
        delta: ui.Offset.zero,
        timestamp: 0,
        kind: ui.PointerDeviceKind.mouse,
      ),
    );

    world.events.register<SecondaryTapEvent>(
      capacity: tapCapacity,
      fromDoubleFieldsFactory: SecondaryTapEvent.fromDoubleFields,
      sampleEvent: const SecondaryTapEvent(
        position: ui.Offset.zero,
        worldPosition: ui.Offset.zero,
        timestamp: 0,
      ),
    );

    // Register new input action events
    world.events.register<InputActionEvent>(
      capacity: tapCapacity,
      fromDoubleFieldsFactory: InputActionEvent.fromDoubleFields,
      sampleEvent: InputActionEvent(
        action: InputAction.moveUp,
        state: InputState.pressed,
        timestamp: 0,
      ),
    );

    // Register entity-specific events
    world.events.register<EntityTapEvent>(
      capacity: entityEventCapacity,
      fromDoubleFieldsFactory: EntityTapEvent.fromDoubleFields,
      sampleEvent: EntityTapEvent(
        entity: Entity.create(),
        position: ui.Offset.zero,
        worldPosition: ui.Offset.zero,
        timestamp: 0,
      ),
    );

    world.events.register<EntityDragEvent>(
      capacity: entityEventCapacity,
      fromDoubleFieldsFactory: EntityDragEvent.fromDoubleFields,
      sampleEvent: EntityDragEvent(
        entity: Entity.create(),
        position: ui.Offset.zero,
        worldPosition: ui.Offset.zero,
        delta: ui.Offset.zero,
        timestamp: 0,
      ),
    );

    world.events.register<EntityLongPressEvent>(
      capacity: entityEventCapacity,
      fromDoubleFieldsFactory: EntityLongPressEvent.fromDoubleFields,
      sampleEvent: EntityLongPressEvent(
        entity: Entity.create(),
        position: ui.Offset.zero,
        worldPosition: ui.Offset.zero,
        timestamp: 0,
      ),
    );

    world.events.register<EntitySecondaryTapEvent>(
      capacity: entityEventCapacity,
      fromDoubleFieldsFactory: EntitySecondaryTapEvent.fromDoubleFields,
      sampleEvent: EntitySecondaryTapEvent(
        entity: Entity.create(),
        position: ui.Offset.zero,
        worldPosition: ui.Offset.zero,
        timestamp: 0,
      ),
    );

    world.events.register<EntitySelectedEvent>(
      capacity: entityEventCapacity,
      fromDoubleFieldsFactory: EntitySelectedEvent.fromDoubleFields,
      sampleEvent: EntitySelectedEvent(
        entity: Entity.create(),
        timestamp: DateTime.fromMillisecondsSinceEpoch(0),
      ),
    );

    world.events.register<EntityDeselectedEvent>(
      capacity: entityEventCapacity,
      fromDoubleFieldsFactory: EntityDeselectedEvent.fromDoubleFields,
      sampleEvent: EntityDeselectedEvent(
        entity: Entity.create(),
        timestamp: DateTime.fromMillisecondsSinceEpoch(0),
      ),
    );

    // 4. Initialize runtime input map
    final runtimeMap = RuntimeInputMap()..initializeDefaults();
    world.upsertResource(runtimeMap);

    // Configure input schedule if requested
    if (configureSchedule) {
      configureInputSchedule(world);
    }
  }

  // Note: configureInputSchedule is implemented in input_systems.dart
}
