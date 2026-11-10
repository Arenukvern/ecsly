/// Performance optimization guide for event-driven input system.
///
/// ## Event Capacity Tuning
///
/// Adjust event capacities based on your application's input patterns:
///
/// - **High-frequency input** (games, interactive apps): Increase capacities to 500-1000
/// - **Low-frequency input** (business apps): Default capacities (200) are sufficient
/// - **Monitor overflow**: Check event channel metrics for dropped events
///
/// Example:
/// ```dart
/// world.addPlugin(InputPlugin(
///   tapCapacity: 500,      // More taps for frequent clicking
///   dragCapacity: 1000,    // Many drag events during gestures
///   entityEventCapacity: 200, // Enough for interactive entities
/// ));
/// ```
///
/// ## Spatial Indexing for Large Entity Sets
///
/// When you have 100+ interactive entities, consider spatial indexing:
///
/// ```dart
/// class SpatialInputIndex extends Resource {
///   final Map<int, List<Entity>> spatialGrid = {};
///
///   void updateIndex(List<Entity> interactiveEntities, World world) {
///     spatialGrid.clear();
///     for (final entity in interactiveEntities) {
///       final position = getEntityWorldPosition(entity, world);
///       if (position != null) {
///         final gridKey = _positionToGridKey(position);
///         spatialGrid.putIfAbsent(gridKey, () => []).add(entity);
///       }
///     }
///   }
///
///   List<Entity> getNearbyEntities(Offset position) {
///     final gridKey = _positionToGridKey(position);
///     return spatialGrid[gridKey] ?? [];
///   }
///
///   int _positionToGridKey(Offset position) {
///     // Convert world position to grid coordinates
///     const gridSize = 100.0; // Adjust based on entity density
///     final gridX = (position.dx / gridSize).floor();
///     final gridY = (position.dy / gridSize).floor();
///     return gridX + (gridY << 16); // Pack into single int
///   }
/// }
/// ```
///
/// Integrate spatial indexing into hit testing:
/// ```dart
/// void optimizedHitTestSystem(SystemContext context) {
///   final spatialIndex = context.world.getResource<SpatialInputIndex>();
///
///   // For each gesture event, only check nearby entities
///   final tapReader = context.world.events.reader<TapEvent>();
///   for (final event in tapReader.iter()) {
///     final nearbyEntities = spatialIndex.getNearbyEntities(event.worldPosition);
///     // Hit test only nearby entities instead of all interactive entities
///   }
/// }
/// ```
///
/// ## Conditional Querying Verification
///
/// The Input schedule only runs when events exist, providing zero overhead when idle.
/// Verify this with performance profiling:
///
/// - **Idle state**: No input events → schedule doesn't run → 0 CPU cost
/// - **Active state**: Input events exist → schedule runs → processes events efficiently
///
/// The ConditionTrigger ensures optimal performance by avoiding unnecessary work.
///
/// ## Memory Layout Optimization
///
/// Events use TypedData storage (FloatColumn/IntColumn) for zero-GC performance:
/// - Position fields: Float64 values in TypedData
/// - Entity IDs: Int32 values
/// - Timestamps: Int64 values
///
/// This provides cache-friendly memory access and eliminates GC pressure during input processing.
///
/// ## Benchmarking Recommendations
///
/// 1. **Idle Performance**: Measure CPU usage when no input events exist
/// 2. **Peak Performance**: Test with maximum expected interactive entities
/// 3. **Memory Usage**: Monitor event channel sizes and GC frequency
/// 4. **Event Throughput**: Test maximum events per second your systems can handle
///
/// ## Scaling Strategies
///
/// - **10-100 entities**: Default system works well
/// - **100-1000 entities**: Consider spatial indexing
/// - **1000+ entities**: Implement hierarchical hit testing or viewport culling
library;

export 'draggable_components/draggable_component.dart';
export 'events/input_action_event.dart';
export 'gesture_events.dart';
export 'input_action.dart';
export 'input_plugin.dart';
export 'raw_input_events.dart';
export 'resources/cursor_position_resource.dart';
export 'resources/gesture_classification_state.dart';
export 'resources/gesture_consumption_tracker.dart';
export 'resources/input_source.dart';
export 'resources/input_state_tracker.dart';
export 'resources/input_world_space_resource.dart';
export 'resources/interactive_entities_cache.dart';
export 'resources/position_mutator_resource.dart';
export 'resources/runtime_input_map.dart';
export 'resources/selection_manager.dart';
export 'systems/gesture_classification_system.dart';
export 'systems/input_binding_system.dart';
export 'systems/systems.dart';
export 'utils/constants.dart';
export 'utils/entity_world_position.dart';
export 'utils/gesture_types.dart';
export 'utils/hit_testing.dart';
export 'validation/input_config_validator.dart';
export 'widgets/unified_input_widget.dart';
