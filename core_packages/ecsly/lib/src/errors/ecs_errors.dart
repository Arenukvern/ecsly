/// ECS-specific error handling following Dart's Exception vs Error best practices.
///
/// **Errors** (programming mistakes, should not be caught):
/// - [EntityNotFoundError]: Entity doesn't exist or is not alive
/// - [ComponentNotFoundError]: Component not found for entity
/// - [ComponentNotRegisteredError]: Component type not registered
/// - [ExtensionTypeNotRegisteredError]: Component has no registered extension type
/// - [ExtensionTypeMismatchError]: Extension type doesn't match registered type
/// - [ArchetypeNotFoundError]: Archetype not found
/// - [EventNotRegisteredException]: Event channel not registered
/// - [EventFactoryValidationError]: Event factory validation failure
/// - [EventStrideCalculationError]: Event stride calculation failure
/// - [EventStrideMismatchError]: Event stride validation failure
/// - [EventTypeMismatchError]: Wrong event type for column storage
/// - [EventColumnUnsupportedError]: Column type doesn't support event operations
/// - [EventTriggerValidationError]: EventTrigger used with unregistered channel
/// - [EcsStateError]: General ECS state errors
///
/// **Exceptions** (recoverable conditions, can be caught):
/// - [ComponentRegistrationException]: Failed to register component (recoverable)
/// - [EventCapacityOverflow]: Event channel capacity exceeded (recoverable)
/// - [EventRegistrationException]: Failed to register event (recoverable)
library;

import '../archetypes/archetypes.dart';
import '../components/component.dart';
import '../entities/entity.dart';

/// Thrown when accessing an archetype that doesn't exist.
///
/// This is a programming error - archetype IDs should be validated before use.
class ArchetypeNotFoundError extends EcsStateError {
  ArchetypeNotFoundError(this.archetypeId)
    : super('ArchetypeId $archetypeId not found');

  /// The archetype ID that was not found.
  final ArchetypeId archetypeId;
}

/// Thrown when a system schedule has circular dependencies.
///
/// This is a programming error - system dependencies should form a DAG.
class CircularDependencyError extends EcsStateError {
  CircularDependencyError(this.cycle)
    : super('Circular dependency detected in system schedule: $cycle');

  /// The cycle path that was detected.
  final List<String> cycle;
}

/// Thrown when accessing a component that doesn't exist on an entity.
///
/// This is a programming error - components should be checked before access.
/// Use [WorldEntity.hasFast] or [ComponentQuery] to check component existence.
class ComponentNotFoundError extends EcsStateError {
  ComponentNotFoundError(this.componentType, this.entity)
    : super('Component $componentType not found for entity $entity');

  /// The component type that was not found.
  final Type componentType;

  /// The entity that was accessed.
  final Entity entity;
}

/// Thrown when using a component type that hasn't been registered.
///
/// This is a programming error - components must be registered before use.
/// Use explicit registration APIs on [ComponentRegistry] to register components.
class ComponentNotRegisteredError extends EcsStateError {
  ComponentNotRegisteredError(this.componentType)
    : super('Component type $componentType is not registered');

  /// The component type that was not registered.
  final Type componentType;
}

/// Thrown when component registration fails (recoverable).
///
/// This can occur during plugin loading or dynamic component registration.
/// Can be caught and handled gracefully.
class ComponentRegistrationException extends EcsException {
  ComponentRegistrationException(this.componentType, [final String? reason])
    : super(
        reason != null
            ? 'Failed to register component type $componentType: $reason'
            : 'Failed to register component type $componentType',
      );

  /// The component type that failed to register.
  final Type componentType;
}

/// Base class for ECS-specific exceptions (recoverable conditions).
///
/// These represent conditions that can be handled gracefully.
/// Use [EcsStateError] for programming mistakes.
class EcsException implements Exception {
  EcsException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Base class for ECS-specific state errors.
///
/// These represent programming mistakes and should not typically be caught.
/// Use [EcsException] for recoverable conditions.
class EcsStateError extends StateError {
  EcsStateError(super.message);
}

/// Thrown when accessing an entity that doesn't exist or is not alive.
///
/// This is a programming error - entities should be validated before use.
/// Use [World.entities.isAlive] to check entity validity.
class EntityNotFoundError extends EcsStateError {
  EntityNotFoundError(this.entity)
    : super('Entity $entity not found or not alive');

  /// The entity that was not found.
  final Entity entity;
}

/// Thrown when a hot schedule attempts to access an object/cold component.
class HotScheduleObjectComponentError extends EcsStateError {
  HotScheduleObjectComponentError(this.componentId, this.componentType)
    : super(
        'Hot schedule rejected object component $componentType (id: $componentId). '
        'Register as SoA or remove it from the hot-path schedule.',
      );

  final ComponentId componentId;
  final Type componentType;
}

/// Thrown when event channel capacity is exceeded (recoverable).
///
/// This can occur during normal operation when events are sent faster than processed.
/// Can be caught and handled gracefully (e.g., log, retry, degrade gracefully).
class EventCapacityOverflow extends EcsException {
  EventCapacityOverflow({
    required this.channelType,
    required this.capacity,
    required this.attemptedEvent,
    this.dropped = false,
  }) : super(
         'Event channel capacity exceeded for $channelType '
         '(capacity: $capacity, dropped: $dropped): $attemptedEvent',
       );

  /// Type of the event channel.
  final Type channelType;

  /// Maximum capacity of the channel.
  final int capacity;

  /// The event that couldn't be stored.
  final dynamic attemptedEvent;

  /// Whether the event was dropped (vs thrown).
  final bool dropped;
}

/// Thrown when column-based event storage is not supported for a column type.
///
/// This is a programming error - only ObjectColumn, FloatColumn, and IntColumn
/// support event storage. Ensure events are registered with supported column types.
class EventColumnUnsupportedError extends EcsStateError {
  EventColumnUnsupportedError(this.columnType, this.operation)
    : super(
        'Column-based event $operation not supported for $columnType. '
        'Supported types: ObjectColumn, FloatColumn, IntColumn.',
      );

  /// The column type that doesn't support the operation.
  final Type columnType;

  /// The operation that was attempted (e.g., 'loading', 'storage').
  final String operation;
}

/// Thrown when event factory validation fails.
///
/// This is a programming error - event factories must create valid events.
/// Ensure factory functions produce events with correct structure and types.
class EventFactoryValidationError extends EcsStateError {
  EventFactoryValidationError(this.eventType, [this.details])
    : super(
        'Event factory validation failed for $eventType'
        '${details != null ? ': $details' : ''}',
      );

  /// The event type that failed validation.
  final Type eventType;

  /// Additional details about the validation failure.
  final String? details;
}

/// Thrown when accessing an event channel that hasn't been registered.
///
/// This is a programming error - event channels must be registered before use.
/// Use [EventRegistry.register] to register event channels.
class EventNotRegisteredException<T> extends EcsException {
  EventNotRegisteredException()
    : super(
        'Event channel for $T not registered. Call world.events.register<$T>() first.',
      );
}

/// Thrown when event registration fails (recoverable).
///
/// This can occur during plugin loading or dynamic event registration.
/// Can be caught and handled gracefully.
class EventRegistrationException extends EcsException {
  EventRegistrationException(this.eventType, [final String? reason])
    : super(
        reason != null
            ? 'Failed to register event type $eventType: $reason'
            : 'Failed to register event type $eventType',
      );

  /// The event type that failed to register.
  final Type eventType;
}

/// Thrown when event stride calculation fails.
///
/// This is a programming error - event stride must be calculable from sample events.
/// Ensure TypedDataEvent implementations provide consistent numericFields.
class EventStrideCalculationError extends EcsStateError {
  EventStrideCalculationError(this.eventType, [this.details])
    : super(
        'Event stride calculation failed for $eventType'
        '${details != null ? ': $details' : ''}',
      );

  /// The event type that failed stride calculation.
  final Type eventType;

  /// Additional details about the stride calculation failure.
  final String? details;
}

/// Thrown when event stride doesn't match the expected stride.
///
/// This is a programming error - event field counts must match stride.
/// Ensure numericFields returns the correct number of fields.
class EventStrideMismatchError extends EcsStateError {
  EventStrideMismatchError({
    required this.eventType,
    required this.expectedStride,
    required this.actualFieldCount,
  }) : super(
         'Event $eventType stride mismatch: expected $expectedStride fields, '
         'but numericFields returned $actualFieldCount fields. '
         'Check your TypedDataEventMixin implementation.',
       );

  /// The event type with the stride mismatch.
  final Type eventType;

  /// The expected stride (from column configuration).
  final int expectedStride;

  /// The actual field count from numericFields.
  final int actualFieldCount;
}

/// Thrown when EventTrigger is used with an unregistered event channel.
///
/// This is a programming error - event channels must be registered before use
/// in triggers. Register the event channel first using [EventRegistry.register].
class EventTriggerValidationError extends EcsStateError {
  EventTriggerValidationError(this.eventType)
    : super(
        'EventTrigger validation failed: Event channel for $eventType not registered. '
        'Register the event channel using world.events.register<$eventType>() before using it in triggers.',
      );

  /// The event type that is not registered.
  final Type eventType;
}

/// Thrown when event type doesn't match column storage type.
///
/// This is a programming error - events must match their registered storage type.
/// Ensure events are registered with the correct configuration.
class EventTypeMismatchError extends EcsStateError {
  EventTypeMismatchError([this.details])
    : super(
        'Event type mismatch: ${details ?? "Event type incompatible with column storage"}',
      );

  /// Additional details about the type mismatch.
  final String? details;
}

/// Thrown when an extension type doesn't match the registered type for a component.
///
/// This is a programming error - extension types must match registered types.
/// Ensure extension types match the types registered with the facade factory.
class ExtensionTypeMismatchError extends EcsStateError {
  ExtensionTypeMismatchError(
    this.componentId,
    this.expectedType,
    this.actualType,
  ) : super(
        'Extension type mismatch for component $componentId: '
        'expected $expectedType, got $actualType. '
        'Ensure extension types match registered types.',
      );

  /// The component ID with the type mismatch.
  final ComponentId componentId;

  /// The expected extension type (registered type).
  final Type expectedType;

  /// The actual extension type provided.
  final Type actualType;
}

/// Thrown when a component has no registered extension type facade.
///
/// This is a programming error - components must have a facade factory registered
/// before using queryExt methods or extension type access.
/// Use [ComponentFacadeRegistry.registerFacadeFactory] to register facades.
class ExtensionTypeNotRegisteredError<TExtension> extends EcsStateError {
  ExtensionTypeNotRegisteredError(this.componentId)
    : super(
        'Component $componentId has no registered extension type $TExtension. '
        'Register a facade factory before using queryExt methods.',
      );

  /// The component ID that has no registered extension type.
  final ComponentId componentId;
}

/// Thrown when an iterator is used incorrectly (not initialized or exhausted).
///
/// This is a programming error - iterators should be used correctly.
class IteratorNotReadyError extends EcsStateError {
  IteratorNotReadyError([final String? context])
    : super(
        context != null
            ? 'Iterator not initialized or exhausted: $context'
            : 'Iterator not initialized or exhausted',
      );
}

/// Thrown when plugin installation fails (recoverable).
///
/// This can occur during plugin loading or initialization.
/// Can be caught and handled gracefully.
class PluginInstallationException extends EcsException {
  PluginInstallationException(this.pluginName, [final String? reason])
    : super(
        reason != null
            ? 'Failed to install plugin "$pluginName": $reason'
            : 'Failed to install plugin "$pluginName"',
      );

  /// The name of the plugin that failed to install.
  final String pluginName;
}

/// Thrown when a deterministic schedule trigger has no configured time source.
///
/// Time-based triggers require [ScheduleTimeResource], [DeltaTimeResource], or
/// an explicit opt-in [WallClockScheduleTimeResource].
class ScheduleTimeSourceMissingError extends EcsStateError {
  ScheduleTimeSourceMissingError()
    : super(
        'No schedule time source is available. Register ScheduleTimeResource '
        '(preferred), DeltaTimeResource (compatibility adapter), or WallClockScheduleTimeResource '
        '(explicit non-deterministic adapter).',
      );
}

/// Thrown when a system configuration is invalid.
///
/// This is a programming error - system configurations should be valid.
class SystemConfigurationError extends EcsStateError {
  SystemConfigurationError(this.systemName, this.details)
    : super('System "$systemName" configuration error: $details');

  /// The name of the system with invalid configuration.
  final String systemName;

  /// Details about the configuration error.
  final String details;
}
