import 'dart:typed_data';

import '../components/components.dart';
import '../errors/ecs_errors.dart';
import 'events.dart';

final Map<int, Float32List> _floatWriteScratch = {};
final Map<int, Float64List> _intLoadScratch = {};
final Map<int, Int32List> _intWriteScratch = {};

/// Load an event from FloatColumn storage.
///
/// Extracts numeric fields from the FloatColumn's TypedData backing store
/// and uses the provided factory function to reconstruct the event instance.
T _loadFromFloatColumn<T extends EcsEvent>(
  final FloatColumn column,
  final int index,
  final T Function(List<double>) factory,
) {
  final stride = column.stride;
  final offset = index * stride;
  final fields = Float32List.view(
    column.data.buffer,
    offset * Float32List.bytesPerElement,
    stride,
  );
  return factory(fields);
}

/// Load an event from IntColumn storage.
///
/// Extracts numeric fields from the IntColumn's TypedData backing store
/// and uses the provided factory function to reconstruct the event instance.
/// Supports multi-field events with stride.
T _loadFromIntColumn<T extends EcsEvent>(
  final IntColumn column,
  final int index,
  final T Function(List<double>) factory,
) {
  final stride = column.stride;
  final offset = index * stride;
  final scratch = _intLoadScratch.putIfAbsent(
    stride,
    () => Float64List(stride),
  );
  for (var i = 0; i < stride; i++) {
    scratch[i] = column.data[offset + i].toDouble();
  }
  return factory(scratch);
}

/// Store an event to FloatColumn storage.
///
/// Extracts numeric fields using TypedDataEventMixin and packs them into
/// the FloatColumn's TypedData backing store. Validates stride compatibility
/// before storage.
///
/// Throws [EventStrideMismatchError] if the event's numericFields length
/// doesn't match the column's stride.
void _storeToFloatColumn<T extends EcsEvent>(
  final FloatColumn column,
  final int index,
  final T event,
) {
  final typedEvent = event as TypedDataEventMixin;
  final stride = column.stride;
  final fieldsLength = typedEvent.numericFieldCount;
  _validateEventStride<T>(stride, fieldsLength);

  final scratch = _floatWriteScratch.putIfAbsent(
    stride,
    () => Float32List(stride),
  );
  typedEvent.writeNumericFieldsTo(scratch);

  final offset = index * stride;
  for (var i = 0; i < stride; i++) {
    column.data[offset + i] = scratch[i];
  }
}

/// Store an event to IntColumn storage.
///
/// Extracts numeric fields using TypedDataEventMixin and stores them in
/// the IntColumn's TypedData backing store. Validates stride compatibility
/// before storage. Supports multi-field events with stride.
///
/// Throws [EventStrideMismatchError] if the event's numericFields length
/// doesn't match the column's stride.
void _storeToIntColumn<T extends EcsEvent>(
  final IntColumn column,
  final int index,
  final T event,
) {
  final typedEvent = event as TypedDataEventMixin;
  final stride = column.stride;
  final fieldsLength = typedEvent.numericFieldCount;
  _validateEventStride<T>(stride, fieldsLength);

  final scratch = _intWriteScratch.putIfAbsent(stride, () => Int32List(stride));
  typedEvent.writeNumericIntFieldsTo(scratch);

  final offset = index * stride;
  for (var i = 0; i < stride; i++) {
    column.data[offset + i] = scratch[i];
  }
}

/// Validate that event stride matches column stride.
///
/// Throws [EventStrideMismatchError] if the event's numericFields length
/// doesn't match the column's stride.
void _validateEventStride<T extends EcsEvent>(
  final int columnStride,
  final int eventFieldCount,
) {
  if (eventFieldCount != columnStride) {
    throw EventStrideMismatchError(
      eventType: T,
      expectedStride: columnStride,
      actualFieldCount: eventFieldCount,
    );
  }
}

/// Supported column types for event storage.
enum ColumnType {
  /// FloatColumn for primitive numeric events.
  float,

  /// IntColumn for integer-based events.
  int,

  /// ObjectColumn for complex events with objects/strings.
  object,
}

/// Configuration for mapping an event type to column storage.
class EventColumnConfig<T extends EcsEvent> {
  const EventColumnConfig({
    required this.columnType,
    required this.capacity,
    this.stride = 1,
    this.isPrimitiveEvent = false,
    this.fromDoubleFieldsFactory,
  });

  /// The type of column to use for storage.
  final ColumnType columnType;

  /// Capacity for the column (should match EventChannel capacity).
  final int capacity;

  /// Stride for FloatColumn (number of floats per event).
  final int stride;

  /// Whether this event type contains only primitive fields.
  final bool isPrimitiveEvent;

  /// Factory function to create event from numeric fields.
  ///
  /// Required for TypedDataEvent types to enable deserialization.
  final T Function(List<double> fields)? fromDoubleFieldsFactory;

  /// Create the appropriate column instance.
  DataColumn createColumn() {
    switch (columnType) {
      case ColumnType.float:
        return ColumnFactoryRegistry.createFloatColumn(
          stride: stride,
          initialCapacity: capacity,
        );
      case ColumnType.int:
        // ColumnFactoryRegistry does not support stride in IntColumn, so mimic direct construction
        return ColumnFactoryRegistry.createIntColumn(
          initialCapacity: capacity,
          stride: stride,
        );
      case ColumnType.object:
        return ColumnFactoryRegistry.createObjectColumn<T>(
          initialCapacity: capacity,
        );
    }
  }
}

/// Maps event types to appropriate column configurations.
///
/// This class analyzes event type structures and determines the optimal
/// column storage strategy based on ECS pillars (SoA, TypedData).
class EventColumnMapper {
  EventColumnMapper._();

  /// Create a column configuration for the given event type.
  ///
  /// Automatically detects TypedDataEvent types and uses FloatColumn/IntColumn
  /// for zero-GC storage. Falls back to ObjectColumn for complex events.
  ///
  /// For TypedDataEvent types, requires either [sampleEvent] or explicit [stride]
  /// to prevent unsafe defaults that could cause data corruption.
  ///
  /// Throws [EventRegistrationException] if TypedDataEvent registration
  /// is missing required parameters.
  static EventColumnConfig<T> mapEventType<T extends EcsEvent>({
    required final int capacity,
    final T Function(List<double>)? fromDoubleFieldsFactory,
    final T? sampleEvent,
    final int? stride,
    final TypedDataEventRegistry? registry,
  }) {
    // Check if factory is provided (explicit TypedDataEvent) or sampleEvent indicates TypedDataEvent
    if (fromDoubleFieldsFactory != null ||
        (sampleEvent != null && sampleEvent is TypedDataEventMixin)) {
      return _createTypedDataConfig<T>(
        capacity: capacity,
        fromDoubleFieldsFactory: fromDoubleFieldsFactory,
        sampleEvent: sampleEvent,
        stride: stride,
        registry: registry,
      );
    }

    // Fallback to ObjectColumn for complex events
    return EventColumnConfig<T>(
      columnType: ColumnType.object,
      capacity: capacity,
    );
  }

  /// Calculate stride for a TypedDataEvent from sample event or provided stride.
  ///
  /// Requires either explicit stride or sampleEvent for TypedDataEvent registration.
  /// No unsafe fallbacks to prevent data corruption.
  ///
  /// Validates that stride is positive when provided explicitly.
  static int _calculateStrideForTypedDataEvent<T>(
    final T? sampleEvent,
    final int? stride,
  ) {
    if (stride != null) {
      if (stride <= 0) {
        throw EventRegistrationException(
          T,
          'TypedDataEvent stride must be positive, got $stride',
        );
      }
      return stride;
    }
    if (sampleEvent != null && sampleEvent is TypedDataEventMixin) {
      final calculatedStride = sampleEvent.numericFields.length;
      if (calculatedStride <= 0) {
        throw EventRegistrationException(
          T,
          'TypedDataEvent sampleEvent must have at least one numeric field, '
          'but numericFields returned $calculatedStride fields',
        );
      }
      return calculatedStride;
    }
    // No fallback - require explicit stride or sampleEvent for TypedDataEvent
    throw EventRegistrationException(
      T,
      'TypedDataEvent registration requires either explicit stride parameter '
      'or sampleEvent with numericFields. Neither was provided.',
    );
  }

  /// Create TypedData configuration for a TypedDataEvent.
  ///
  /// Analyzes event structure to determine FloatColumn vs IntColumn
  /// and calculates stride from sampleEvent if available.
  static EventColumnConfig<T> _createTypedDataConfig<T extends EcsEvent>({
    required final int capacity,
    final T Function(List<double>)? fromDoubleFieldsFactory,
    final T? sampleEvent,
    final int? stride,
    final TypedDataEventRegistry? registry,
  }) {
    if (fromDoubleFieldsFactory == null) {
      throw EventRegistrationException(
        T,
        'TypedDataEvent requires fromDoubleFieldsFactory for deserialization. '
        'Provide it when registering the event type.',
      );
    }

    // Calculate stride from sampleEvent or provided stride
    final calculatedStride = _calculateStrideForTypedDataEvent<T>(
      sampleEvent,
      stride,
    );

    // Determine column type based on field analysis
    // Analyze sampleEvent to choose IntColumn for int-only events
    final columnType = _determineColumnTypeForTypedDataEvent<T>(sampleEvent);

    return EventColumnConfig<T>(
      columnType: columnType,
      capacity: capacity,
      stride: calculatedStride,
      isPrimitiveEvent: true,
      fromDoubleFieldsFactory: fromDoubleFieldsFactory,
    );
  }

  /// Determine column type for a TypedDataEvent.
  ///
  /// Analyzes sampleEvent to choose IntColumn for int-only events,
  /// FloatColumn otherwise.
  static ColumnType _determineColumnTypeForTypedDataEvent<T>(
    final T? sampleEvent,
  ) {
    if (sampleEvent != null && sampleEvent is TypedDataEventMixin) {
      // Analyze field types - use IntColumn if all fields are integers
      final fields = sampleEvent.numericFields;
      final allInts = fields.every((final field) => field is int);
      if (allInts) {
        return ColumnType.int;
      }
    }
    // Default to FloatColumn (can store both int and double)
    return ColumnType.float;
  }
}

/// Public API for registering TypedDataEvent types.
///
/// Used internally by EventRegistry when TypedDataEvent is detected.
/// Now instance-based to support multi-world isolation.
///
/// Each world has its own TypedDataEventRegistry instance to prevent
/// cross-world contamination. Type objects are compile-time constants
/// and safe for multi-world isolation when stored in collections.
class TypedDataEventRegistry {
  /// Per-world registry of event types that use TypedData storage.
  final _TypedDataEventRegistry _typedDataEventRegistry =
      _TypedDataEventRegistry();

  /// Per-world registry for storing stride values for TypedDataEvent types.
  final _TypedDataEventStrideRegistry _typedDataEventStrideRegistry =
      _TypedDataEventStrideRegistry();

  /// Check if an event type is registered as TypedDataEvent.
  bool isRegistered<T>() => _typedDataEventRegistry.isTypedDataEvent<T>();

  /// Register a TypedDataEvent type with its stride.
  ///
  /// [stride] is the number of numeric fields in the event.
  void register<T extends EcsEvent>(final int stride) {
    _typedDataEventRegistry.register<T>();
    _typedDataEventStrideRegistry.register<T>(stride);
  }
}

/// Registry of event types that use TypedData storage.
///
/// Populated automatically when TypedDataEvent types are registered.
/// Uses `Set<Type>` which is safe for multi-world isolation because Type objects
/// are compile-time constants that don't carry instance state.
final class _TypedDataEventRegistry {
  _TypedDataEventRegistry();

  final Set<Type> _typedDataEventTypes = {};

  /// Check if an event type uses TypedData storage.
  bool isTypedDataEvent<T>() => _typedDataEventTypes.contains(T);

  /// Register an event type as using TypedData storage.
  void register<T extends EcsEvent>() {
    _typedDataEventTypes.add(T);
  }
}

/// Registry for storing stride values for TypedDataEvent types.
///
/// Uses `Map<Type, int>` which is safe for multi-world isolation because
/// Type objects are compile-time constants that don't carry instance state.
final class _TypedDataEventStrideRegistry {
  _TypedDataEventStrideRegistry();

  final Map<Type, int> _strides = {};

  /// Get stride for an event type.
  int? getStride<T>() => _strides[T];

  /// Register stride for an event type.
  void register<T extends EcsEvent>(final int stride) {
    _strides[T] = stride;
  }
}

/// Extension methods for storing/loading events from columns.
extension EventColumnStorage on DataColumn {
  /// Clear an event at the given index (prevent memory leaks).
  ///
  /// Performance: O(1) for all column types.
  /// - TypedData columns (FloatColumn, IntColumn): no-op (value types)
  /// - ObjectColumn: sets reference to null
  void clearEvent(final int index) {
    if (this is ObjectColumn) {
      (this as ObjectColumn).setValue(index, null);
    }
    // FloatColumn and IntColumn don't need explicit clearing (TypedData is value types)
    // The values will be overwritten on next write
  }

  /// Load an event from the column at the given index.
  ///
  /// Supports ObjectColumn, FloatColumn, and IntColumn storage.
  /// For TypedData columns, requires a factory function from EventColumnConfig.
  ///
  /// Throws [EventColumnUnsupportedError] for unsupported column types.
  /// Throws [EventTypeMismatchError] for missing factory or invalid events.
  T loadEvent<T extends EcsEvent>(
    final int index, {
    final T Function(List<double>)? fromDoubleFieldsFactory,
  }) {
    switch (this) {
      case final ObjectColumn<T> objectColumn:
        final value = objectColumn.getValue(index);
        if (value == null) {
          throw EventTypeMismatchError(
            'Failed to load event $T at index $index: event is null. '
            'This may indicate the event was cleared or never stored.',
          );
        }
        return value;
      case final FloatColumn floatColumn:
        if (fromDoubleFieldsFactory == null) {
          throw EventTypeMismatchError(
            'Failed to load event $T from FloatColumn at index $index: '
            'fromDoubleFieldsFactory is required but not provided. '
            'Ensure event type $T is registered with a factory function.',
          );
        }
        return _loadFromFloatColumn<T>(
          floatColumn,
          index,
          fromDoubleFieldsFactory,
        );
      case final IntColumn intColumn:
        if (fromDoubleFieldsFactory == null) {
          throw EventTypeMismatchError(
            'Failed to load event $T from IntColumn at index $index: '
            'fromDoubleFieldsFactory is required but not provided. '
            'Ensure event type $T is registered with a factory function.',
          );
        }
        return _loadFromIntColumn<T>(intColumn, index, fromDoubleFieldsFactory);
      default:
        throw EventColumnUnsupportedError(
          runtimeType,
          'loading event $T at index $index',
        );
    }
  }

  /// Store an event in the column at the given index.
  ///
  /// Supports ObjectColumn, FloatColumn, and IntColumn storage.
  /// For TypedData columns, extracts numeric fields using TypedDataEventMixin.
  ///
  /// Performance: O(1) for single-field events, O(stride) for multi-field events.
  ///
  /// Throws [EventColumnUnsupportedError] for unsupported column types.
  /// Throws [EventTypeMismatchError] for type mismatches.
  /// Throws [EventStrideMismatchError] for stride validation failures.
  void storeEvent<T extends EcsEvent>(final int index, final T event) {
    switch (this) {
      case final ObjectColumn<T> objectColumn:
        objectColumn.setValue(index, event);
      case final FloatColumn floatColumn:
        if (event is! TypedDataEventMixin) {
          throw EventTypeMismatchError(
            'Failed to store event $T in FloatColumn at index $index: '
            'event type ${event.runtimeType} does not implement TypedDataEventMixin. '
            'Ensure $T implements TypedDataEventMixin and provides numericFields.',
          );
        }
        _storeToFloatColumn<T>(floatColumn, index, event);
      case final IntColumn intColumn:
        if (event is! TypedDataEventMixin) {
          throw EventTypeMismatchError(
            'Failed to store event $T in IntColumn at index $index: '
            'event type ${event.runtimeType} does not implement TypedDataEventMixin. '
            'Ensure $T implements TypedDataEventMixin and provides numericFields.',
          );
        }
        _storeToIntColumn<T>(intColumn, index, event);
      default:
        throw EventColumnUnsupportedError(
          runtimeType,
          'storing event $T at index $index',
        );
    }
  }
}
