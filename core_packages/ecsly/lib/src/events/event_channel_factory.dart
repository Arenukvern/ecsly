import '../errors/ecs_errors.dart';
import 'event_column_mapper.dart';
import 'events.dart';

/// Factory for creating appropriately typed event channels.
///
/// Analyzes the event type to determine the best storage strategy.
class EventChannelFactory {
  EventChannelFactory._();

  /// Create an event channel for the given type.
  ///
  /// Uses EventColumnMapper to analyze the event type and create
  /// appropriate column-based storage for optimal performance.
  ///
  /// For TypedDataEvent types, provide [fromDoubleFieldsFactory] and
  /// [sampleEvent] to enable TypedData storage (FloatColumn/IntColumn).
  ///
  /// Throws [EventRegistrationException] if capacity is not positive.
  static EventChannel<T> create<T extends EcsEvent>({
    required final int capacity,
    final EventCapacityPolicy capacityPolicy = EventCapacityPolicy.dropNew,
    final void Function(EventCapacityOverflow)? metricsHook,
    final T Function(List<double>)? fromDoubleFieldsFactory,
    final T? sampleEvent,
    final int? stride,
    final TypedDataEventRegistry? registry,
  }) {
    // Validate capacity
    if (capacity <= 0) {
      throw EventRegistrationException(
        T,
        'Event channel capacity must be positive, got $capacity',
      );
    }

    // Map event type to column configuration
    final config = EventColumnMapper.mapEventType<T>(
      capacity: capacity,
      fromDoubleFieldsFactory: fromDoubleFieldsFactory,
      sampleEvent: sampleEvent,
      stride: stride,
      registry: registry,
    );

    // Create the appropriate column
    final column = config.createColumn();

    // Create channel with column-based storage
    return EventChannel<T>.withColumn(
      column: column,
      config: config,
      capacity: capacity,
      capacityPolicy: capacityPolicy,
      metricsHook: metricsHook,
    );
  }
}
