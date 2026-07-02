/// Example event types for testing and documentation.
///
/// These demonstrate different event storage strategies:
/// - TypedData events: Use FloatColumn/IntColumn storage (zero-GC)
/// - Complex events: Use ObjectColumn storage

/// Marker interface for events that can use TypedData storage.
///
/// Events implementing this interface will automatically use
/// FloatColumn or IntColumn instead of ObjectColumn for zero-GC storage.
///
/// To use TypedData storage, events must:
/// 1. Implement this interface
/// 2. Mix in [TypedDataEventMixin] to provide field extraction
/// 3. Register with a factory function and sample event
///
/// Example:
/// ```dart
/// class DamageEvent with TypedDataEventMixin implements TypedDataEvent {
///   const DamageEvent({
///     required this.targetEntity,
///     required this.sourceEntity,
///     required this.amount,
///   });
///
///   final int targetEntity;
///   final int sourceEntity;
///   final double amount;
///
///   @override
///   List<num> get numericFields => [targetEntity, sourceEntity, amount];
/// }
///
/// // Register the event:
/// world.events.register<DamageEvent>(
///   fromNumericFieldsFactory: (fields) => DamageEvent(
///     targetEntity: fields[0].toInt(),
///     sourceEntity: fields[1].toInt(),
///     amount: fields[2],
///   ),
///   sampleEvent: DamageEvent(targetEntity: 0, sourceEntity: 0, amount: 0.0),
/// );
/// ```
library;

import 'dart:typed_data';

export 'event_channel.dart';
export 'event_channel_factory.dart';
export 'event_registry.dart';

/// Base marker interface for all events.
///
/// All events must implement this interface to be used with EventChannel.
/// This enables type-safe event channels that can use either TypedData storage
/// (for TypedDataEvent) or Object storage (for complex events).
abstract class EcsEvent {
  const EcsEvent();
}

/// Marker interface for events that can use TypedData storage.
///
/// Events implementing this interface will automatically use
/// FloatColumn or IntColumn instead of ObjectColumn for zero-GC storage.
///
/// To use TypedData storage, events must:
/// 1. Implement this interface
/// 2. Mix in [TypedDataEventMixin] to provide field extraction
/// 3. Register with a factory function and sample event
///
/// Example:
/// ```dart
/// class DamageEvent with TypedDataEventMixin implements TypedDataEvent {
///   const DamageEvent({
///     required this.targetEntity,
///     required this.sourceEntity,
///     required this.amount,
///   });
///
///   final int targetEntity;
///   final int sourceEntity;
///   final double amount;
///
///   @override
///   List<double> get numericFields => [targetEntity, sourceEntity, amount];
/// }
/// ```
abstract class TypedDataEvent implements EcsEvent {}

/// Mixin that provides field extraction for TypedDataEvent.
///
/// Events using TypedData storage must implement this mixin
/// to provide field extraction for serialization.
///
/// Deserialization is handled by a factory function provided
/// at event registration.
mixin TypedDataEventMixin on EcsEvent {
  /// Number of numeric fields in storage order.
  ///
  /// Override for allocation-free metadata reads in hot event paths.
  int get numericFieldCount => numericFields.length;

  /// Returns all numeric fields in storage order.
  ///
  /// Fields should be returned in constructor parameter order.
  /// All numeric types (int, double) are supported.
  List<double> get numericFields;

  /// Writes numeric fields into a preallocated float buffer.
  ///
  /// Override this in hot events to avoid allocating [numericFields] on send.
  void writeNumericFieldsTo(final Float32List target) {
    final fields = numericFields;
    for (var i = 0; i < fields.length; i++) {
      target[i] = fields[i];
    }
  }

  /// Writes numeric fields into a preallocated int buffer.
  ///
  /// Override this in int-only events to avoid allocation and conversion.
  void writeNumericIntFieldsTo(final Int32List target) {
    final fields = numericFields;
    for (var i = 0; i < fields.length; i++) {
      target[i] = fields[i].toInt();
    }
  }
}
