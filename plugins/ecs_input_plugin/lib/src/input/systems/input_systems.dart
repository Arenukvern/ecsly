/// Barrel export for all input systems and schedule configuration.
library;

import 'package:ecsly/ecsly.dart';

import '../gesture_events.dart';
import '../raw_input_events.dart';
import 'drag_start_selection_system.dart';
import 'entity_selection_system.dart';
import 'event_input_clear_system.dart';
import 'gesture_classification_system.dart';
import 'hit_testing_system.dart';
import 'input_binding_system.dart';
import 'input_cleanup_system.dart';
import 'scale_classification_system.dart';
import 'secondary_tap_system.dart';
import 'selection_cleanup_system.dart';

/// Creates and configures the core Input schedule with event-driven systems.
///
/// This schedule only runs when input events exist, providing zero-overhead
/// when no input is active. Applications should add their own entity-specific
/// systems to this schedule to handle gestures for interactive entities.
///
/// The schedule is organized in priority order:
/// 1. Gesture classification (processes raw events into gestures)
/// 2. Hit testing (foundation for all interaction)
/// 3. Selection systems (highest priority)
/// 4. Entity interaction systems
/// 5. Application-specific systems
/// 6. Cleanup systems
///
/// [additionalSystems] Optional list of systems to add before the clear system.
/// Systems are added in order, allowing applications to extend the input pipeline.
/// Note: Camera control systems should be added via CameraControlPlugin, not here.
void configureInputSchedule(
  final World world, {
  final List<void Function(World)>? additionalSystems,
}) {
  world.getOrCreateSchedule(const ScheduleId('KeyboardInput'), trigger: const EveryFrame())
    // Input action mapping (keyboard to actions)
    ..add(inputBindingSystem);
  // InputCleanup (advance tracker, selection/gesture cleanup) must run *after*
  // any schedule that reads InputStateTracker.justPressed (e.g. menu/level input).
  // Hosts should apply [inputCleanupLastScheduleOrdering] when iterating
  // schedules so that InputCleanup runs last in the frame.
  world.getOrCreateSchedule(const ScheduleId('InputCleanup'), trigger: const EveryFrame())
    ..add(inputCleanupSystem);
  final schedule =
      world.getOrCreateSchedule(
          const ScheduleId('Input'),
          trigger: ConditionTrigger(
            (final w) =>
                // Check for raw events (from widget)
                w.events.reader<RawPointerDownEvent>().isNotEmpty ||
                w.events.reader<RawPointerMoveEvent>().isNotEmpty ||
                w.events.reader<RawPointerUpEvent>().isNotEmpty ||
                w.events.reader<RawKeyDownEvent>().isNotEmpty ||
                w.events.reader<RawKeyUpEvent>().isNotEmpty ||
                w.events.reader<RawKeyRepeatEvent>().isNotEmpty ||
                w.events.reader<RawScaleStartEvent>().isNotEmpty ||
                w.events.reader<RawScaleUpdateEvent>().isNotEmpty ||
                w.events.reader<ScrollEvent>().isNotEmpty ||
                // Check for classified gestures (from classification system)
                w.events.reader<TapEvent>().isNotEmpty ||
                w.events.reader<DoubleTapEvent>().isNotEmpty ||
                w.events.reader<LongPressEvent>().isNotEmpty ||
                w.events.reader<DragEvent>().isNotEmpty ||
                w.events.reader<PinchEvent>().isNotEmpty ||
                w.events.reader<RawScaleEndEvent>().isNotEmpty ||
                w.events.reader<SecondaryTapEvent>().isNotEmpty,
          ),
        )
        // Gesture classification (processes raw events into gestures)
        ..add(gestureClassificationSystem, name: 'gestureClassificationSystem')
        // Scale classification (converts raw scale to pinch gestures)
        ..add(scaleClassificationSystem, name: 'scaleClassificationSystem')
        // Unified hit testing (foundation for all interaction)
        ..add(unifiedHitTestingSystem, name: 'unifiedHitTestingSystem')
        // Secondary tap system (right-click context menus)
        ..add(secondaryTapInputSystem, name: 'secondaryTapInputSystem')
        // Selection systems (highest priority)
        ..add(entitySelectionSystem, name: 'entitySelectionSystem')
        // Drag-start selection (select entities when drag starts on them)
        ..add(dragStartSelectionSystem, name: 'dragStartSelectionSystem')
        // Selection cleanup (remove dead entities)
        ..add(selectionCleanupSystem);

  // Add application-specific systems if provided
  additionalSystems?.forEach(schedule.add);

  schedule.then(eventInputClearSystem);
}

/// Default ordering policy that ensures the `InputCleanup` schedule runs last.
///
/// This keeps `InputStateTracker.justPressed` visible to game/level/menu
/// systems in the same frame, while still advancing the tracker and performing
/// cleanup before the next frame.
Iterable<String> inputCleanupLastScheduleOrdering(
  final Iterable<String> scheduleNames,
) {
  const inputCleanupName = 'InputCleanup';
  String? runLast;

  for (final name in scheduleNames) {
    if (name == inputCleanupName) {
      runLast = name;
      break;
    }
  }

  if (runLast == null) {
    return scheduleNames;
  }

  return <String>[
    for (final name in scheduleNames)
      if (name != runLast) name,
    runLast,
  ];
}

/// Ordering policy for schedules in hosts that integrate with the input plugin.
///
/// Implementations take the existing [scheduleNames] and return a new ordered
/// sequence. Hosts are expected to iterate the returned sequence when driving
/// the world each frame.
typedef ScheduleOrderingPolicy =
    Iterable<String> Function(Iterable<String> scheduleNames);
