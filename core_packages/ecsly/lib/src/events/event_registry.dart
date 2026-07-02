import '../errors/ecs_errors.dart';
import '../world/world.dart';
import 'event_column_mapper.dart';
import 'events.dart';

/// {@template event_registry}
/// Registry for managing event channels as world resources.
///
/// Event channels are stored as resources with auto-generated resource IDs.
/// This enables type-safe access while maintaining the existing resource
/// system patterns.
///
/// Example:
/// ```dart
/// // Register channels in plugin
/// world.events.register<DamageEvent>(capacity: 100);
/// world.events.register<InputEvent>();
///
/// // Access in systems
/// final damageWriter = world.events.writer<DamageEvent>();
/// final inputReader = world.events.reader<InputEvent>();
/// ```
/// {@endtemplate}
class EventRegistry {
  /// {@macro event_registry}
  EventRegistry(this.world) {
    _typedDataEventRegistryInstance = TypedDataEventRegistry();
  }

  final World world;

  /// Per-world TypedDataEvent registry instance.
  ///
  /// Moved from singleton to per-world to ensure isolation between worlds.
  /// Each world has its own TypedDataEventRegistry instance, preventing
  /// cross-world contamination. Type objects are compile-time constants
  /// and safe for multi-world isolation when stored in `Set<Type>` or `Map<Type, int>`.
  late final TypedDataEventRegistry _typedDataEventRegistryInstance;

  /// Get the TypedDataEventRegistry instance for this world.
  ///
  /// Used internally for multi-world isolation.
  TypedDataEventRegistry get typedDataEventRegistry =>
      _typedDataEventRegistryInstance;

  /// Get the event channel resource for type T.
  EventChannel<T> channel<T extends EcsEvent>() =>
      world.getResource<EventChannel<T>>();

  /// Clear all event channels.
  ///
  /// Called automatically at the end of each frame/schedule.
  /// Ensures frame-bound lifecycle by resetting all tracked channels.
  ///
  /// Performance: O(n) where n = number of registered event types.
  /// Each channel's clear() is O(1) for TypedData columns or O(length) for ObjectColumn.
  /// Acceptable performance since clearing happens once per frame, not per entity.
  void clearAll() {
    // Clear all EventChannel resources in the world
    // Use resources as single source of truth for event channels
    for (final channel in world.resources.iter<EventChannel>()) {
      channel.clear();
    }
  }

  /// Check if an event channel is registered for type T.
  ///
  /// Returns true if the channel exists, false otherwise.
  /// Does not throw if the channel is not registered.
  bool hasRegistered<T extends EcsEvent>() =>
      world.resources.has<EventChannel<T>>();

  /// Create an event reader for type T.
  ///
  /// The event channel must be explicitly registered first using [register<T>()].
  /// Throws [StateError] if the channel is not registered.
  EventReader<T> reader<T extends EcsEvent>() {
    if (!world.resources.has<EventChannel<T>>()) {
      throw EventNotRegisteredException<T>();
    }
    return channel<T>().toReader();
  }

  /// Register an event channel for type T.
  ///
  /// [capacity] defaults to 64 events.
  /// [capacityPolicy] defaults to dropping new events.
  ///
  /// For TypedDataEvent types, provide [fromDoubleFieldsFactory] and either
  /// [sampleEvent] OR explicit [stride] to enable TypedData storage (FloatColumn/IntColumn).
  /// If [fromDoubleFieldsFactory] is not provided, events will use ObjectColumn storage.
  ///
  /// TypedDataEvent registration validates factory functions at registration time
  /// to prevent runtime errors. The validation includes:
  /// - Verifying sampleEvent implements TypedDataEventMixin
  /// - Testing factory function produces valid events
  /// - Ensuring factory-produced events have matching stride and numericFields
  ///
  /// Example:
  /// ```dart
  /// // TypedDataEvent with factory and sample event (recommended)
  /// world.events.register<DamageEvent>(
  ///   fromDoubleFieldsFactory: (fields) => DamageEvent(
  ///     targetEntity: fields[0].toInt(),
  ///     sourceEntity: fields[1].toInt(),
  ///     amount: fields[2],
  ///   ),
  ///   sampleEvent: DamageEvent(targetEntity: 0, sourceEntity: 0, amount: 0.0),
  /// );
  ///
  /// // TypedDataEvent with explicit stride
  /// world.events.register<SimpleEvent>(
  ///   fromDoubleFieldsFactory: (fields) => SimpleEvent(fields[0]),
  ///   stride: 1,
  /// );
  ///
  /// // Regular event (uses ObjectColumn)
  /// world.events.register<LogEvent>();
  /// ```
  ///
  /// Throws [EventRegistrationException] if:
  /// - TypedDataEvent registration missing required stride/sampleEvent
  /// - Factory function produces invalid events
  /// - Sample event doesn't implement TypedDataEventMixin
  ///
  void register<T extends EcsEvent>({
    final int capacity = 64,
    final EventCapacityPolicy capacityPolicy = EventCapacityPolicy.dropNew,
    final void Function(EventCapacityOverflow)? metricsHook,
    final T Function(List<double>)? fromDoubleFieldsFactory,
    final T? sampleEvent,
    final int? stride, // Required for TypedDataEvent without sampleEvent
  }) {
    // Detect TypedDataEvent and register if factory is provided
    if (fromDoubleFieldsFactory != null) {
      if (sampleEvent != null) {
        _registerTypedDataEvent<T>(fromDoubleFieldsFactory, sampleEvent);
      } else if (stride != null) {
        // Validate stride is positive
        if (stride <= 0) {
          throw EventRegistrationException(
            T,
            'TypedDataEvent stride must be positive, got $stride',
          );
        }
        // Use provided stride directly (no sampleEvent provided)
        typedDataEventRegistry.register<T>(stride);
      } else {
        throw EventRegistrationException(
          T,
          'TypedDataEvent registration requires either sampleEvent or explicit stride. '
          'Provide one of: sampleEvent parameter, or stride parameter.',
        );
      }
    }

    final channel = EventChannelFactory.create<T>(
      capacity: capacity,
      capacityPolicy: capacityPolicy,
      metricsHook: metricsHook,
      fromDoubleFieldsFactory: fromDoubleFieldsFactory,
      sampleEvent: sampleEvent,
      stride: stride,
      registry: typedDataEventRegistry,
    );
    world.resources.push(channel);
  }

  /// Unregister an event channel for type T.
  ///
  /// Removes the channel from resources and clears it from tracking.
  /// Does nothing if the channel is not registered.
  void unregister<T extends EcsEvent>() {
    if (world.resources.has<EventChannel<T>>()) {
      world.getResource<EventChannel<T>>().clear(); // Clear before removing
      world.resources.remove<EventChannel<T>>();
    }
  }

  /// Create an event writer for type T.
  ///
  /// The event channel must be explicitly registered first using [register<T>()].
  /// Throws [EventNotRegisteredException] if the channel is not registered.
  EventWriter<T> writer<T extends EcsEvent>() {
    if (!world.resources.has<EventChannel<T>>()) {
      throw EventNotRegisteredException<T>();
    }
    return channel<T>().toWriter();
  }

  /// Register a TypedDataEvent type in the registry.
  ///
  /// Calculates stride from a sample event and registers the type.
  /// Requires sampleEvent to be provided (validation happens at registration time).
  void _registerTypedDataEvent<T extends EcsEvent>(
    final T Function(List<double>) factory,
    final T sampleEvent,
  ) {
    // Validate that sampleEvent implements the mixin
    if (sampleEvent is! TypedDataEventMixin) {
      throw EventRegistrationException(
        T,
        'sampleEvent does not implement TypedDataEventMixin. '
        'TypedDataEvent types must implement this mixin to provide numericFields. '
        'Example: class MyEvent with TypedDataEventMixin implements TypedDataEvent { ... }',
      );
    }

    // Factory function is already validated to be non-null by caller

    // Calculate stride from sample event's numericFields
    final typedSampleEvent = sampleEvent as TypedDataEventMixin;
    final expectedStride = typedSampleEvent.numericFields.length;

    // Validate factory function by creating a test event
    // Use the same numericFields from sampleEvent to test the factory
    final testFields = typedSampleEvent.numericFields;
    late final T testEvent;
    try {
      testEvent = factory(testFields);
    } catch (e) {
      throw EventFactoryValidationError(
        T,
        'Factory function failed when creating test event with numericFields: $e. '
        'Ensure factory function handles the expected field structure correctly.',
      );
    }

    // Validate that factory-produced event has matching numericFields
    if (testEvent is! TypedDataEventMixin) {
      throw EventRegistrationException(
        T,
        'Factory function produced event that does not implement TypedDataEventMixin. '
        'Factory must produce events that implement TypedDataEventMixin.',
      );
    }

    final typedTestEvent = testEvent as TypedDataEventMixin;
    final actualStride = typedTestEvent.numericFields.length;

    if (actualStride != expectedStride) {
      throw EventFactoryValidationError(
        T,
        'Factory function produced event with mismatched stride. '
        'Sample event has $expectedStride fields, but factory produced event has $actualStride fields. '
        'Check that factory function creates events with the correct numericFields structure.',
      );
    }

    // Validate that numericFields values match (for debugging factory issues)
    final sampleFields = typedSampleEvent.numericFields;
    final factoryFields = typedTestEvent.numericFields;
    for (var i = 0; i < expectedStride; i++) {
      if (sampleFields[i] != factoryFields[i]) {
        throw EventFactoryValidationError(
          T,
          'Factory function produced event with mismatched numericFields at index $i. '
          'Expected ${sampleFields[i]}, got ${factoryFields[i]}. '
          'Ensure factory function reconstructs events correctly from numericFields.',
        );
      }
    }

    typedDataEventRegistry.register<T>(expectedStride);
  }
}
