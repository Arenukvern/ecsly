import 'dart:typed_data';

import 'package:meta/meta.dart';

import '../components/columns/data_column.dart';
import '../errors/ecs_errors.dart';
import '../resources/resource.dart';
import 'event_column_mapper.dart';
import 'events.dart';

/// Capacity policy for event ring buffers when full.
///
/// When capacity is exceeded:
/// - [dropOld]: Removes oldest event, stores new event
/// - [dropNew]: Ignores new event (default)
/// - [throwOnOverflow]: Throws [EventCapacityOverflow] (recoverable exception)
enum EventCapacityPolicy {
  /// Drop the oldest event when buffer is full.
  dropOld,

  /// Drop the new event when buffer is full (default).
  dropNew,

  /// Throw [EventCapacityOverflow] exception when buffer is full.
  ///
  /// This exception can be caught and handled gracefully (e.g., logging,
  /// retrying, or degrading functionality).
  throwOnOverflow,
}

/// {@template event_channel}
/// A type-safe event channel that stores events in ECS DataColumns.
///
/// Event channels use ring buffers on dense column arrays for optimal performance.
/// Storage automatically selects between FloatColumn, IntColumn, and ObjectColumn
/// based on event structure for SoA layout and SIMD compatibility.
///
/// Events have a frame-bound lifecycle:
/// 1. Send events during frame execution
/// 2. Read events during frame execution
/// 3. Clear events at end of frame/schedule
///
/// Example:
/// ```dart
/// // Register channel in plugin
/// class MyPlugin extends Plugin {
///   @override
///   void install(World world) {
///     world.events.register<DamageEvent>();
///   }
/// }
///
/// // Use in systems
/// void damageSystem(World world) {
///   final writer = world.events.writer<DamageEvent>();
///   final reader = world.events.reader<DamageEvent>();
///
///   // Send events
///   writer.send(DamageEvent(entity: target, amount: 10));
///
///   // Read events
///   for (final event in reader.iter()) {
///     // Handle event
///   }
/// }
/// ```
/// {@endtemplate}
class EventChannel<T extends EcsEvent> implements Resource {
  /// {@macro event_channel}
  EventChannel.withColumn({
    required final DataColumn column,
    required final EventColumnConfig<T> config,
    required this.capacity,
    this.capacityPolicy = EventCapacityPolicy.dropNew,
    this.metricsHook,
  }) : _column = column,
       _config = config;

  /// Maximum number of events this channel can hold.
  final int capacity;

  /// Policy for handling buffer overflow.
  final EventCapacityPolicy capacityPolicy;

  /// Optional hook for capacity overflow metrics.
  final void Function(EventCapacityOverflow)? metricsHook;

  // Column-based storage for events
  final DataColumn _column;

  // Configuration for event-to-column mapping
  final EventColumnConfig<T> _config;

  // Ring buffer indices
  int _head = 0; // Next read position

  int _tail = 0; // Next write position

  int _length = 0;

  // Incremented when head position changes (dropOld/clear).
  // Readers/cursors use this to detect invalidated snapshots.
  int _headEpoch = 0;

  /// Whether the channel is empty.
  bool get isEmpty => _length == 0;

  /// Whether the channel is full.
  bool get isFull => _length == capacity;

  /// Current number of events in the channel.
  int get length => _length;

  /// Clear all events from this channel.
  ///
  /// Called automatically at the end of each frame/schedule to maintain
  /// the frame-bound lifecycle of events.
  ///
  /// Performance characteristics:
  /// - O(1) for TypedData columns (FloatColumn, IntColumn): just resets indices
  /// - O(length) for ObjectColumn: must null out references to prevent memory leaks
  ///
  /// For ObjectColumn, properly handles wrapped ring buffers by clearing
  /// both the head-to-capacity and start-to-tail ranges.
  void clear() {
    if (_length > 0) {
      _headEpoch++;
    }

    // For TypedData columns, we can just reset indices (O(1))
    // Values will be overwritten on next write
    if (_config.columnType != ColumnType.object) {
      _head = 0;
      _tail = 0;
      _length = 0;
      return;
    }

    // For ObjectColumn, must clear references to prevent memory leaks
    // Use fillRange for better performance when possible
    if (_head < _tail) {
      // Contiguous range from head to tail
      (_column as ObjectColumn).fillRange(_head, _tail, null);
    } else if (_length > 0) {
      // Wrapped range: head to end, then start to tail
      (_column as ObjectColumn)
        ..fillRange(_head, capacity, null)
        ..fillRange(0, _tail, null);
    }
    _head = 0;
    _tail = 0;
    _length = 0;
  }

  /// Read multiple events in batch.
  ///
  /// Returns up to [count] events from the channel.
  /// Events are read in FIFO order (oldest first).
  ///
  /// This provides snapshot semantics - events remain available for other readers.
  /// For consumption semantics, use [EventReader.drain()] or iterate and clear manually.
  ///
  /// Performance: O(count) - creates a new List and calls readEvent for each element.
  /// Consider using [EventReader.iter()] for better performance in tight loops.
  ///
  /// Useful for processing multiple events efficiently when you need a List.
  List<T> readBatch(final int count) {
    final snapshotHead = _head;
    final snapshotLength = _length;
    final maxCount = count < snapshotLength ? count : snapshotLength;
    final result = <T>[];
    for (var i = 0; i < maxCount; i++) {
      result.add(readEventAt(i, head: snapshotHead));
    }
    return result;
  }

  /// Create an iterator for reading events.
  ///
  /// The iterator provides snapshot semantics - events sent after
  /// iterator creation won't be visible.
  EventReader<T> toReader() => EventReader<T>._(this);

  // Internal storage access for readers
  @internal
  T readEvent(final int index) => readEventAt(index, head: _head);

  @internal
  T readEventAt(final int index, {required final int head}) =>
      _loadEvent((head + index) % capacity);

  /// Send an event to this channel.
  ///
  /// Returns true if the event was successfully sent, false if dropped
  /// due to capacity policy.
  ///
  /// Overflow behavior:
  /// - [EventCapacityPolicy.dropNew]: Returns false, event ignored
  /// - [EventCapacityPolicy.dropOld]: Removes oldest event, sends new one
  /// - [EventCapacityPolicy.throwOnOverflow]: Throws [EventCapacityOverflow]
  bool send(final T event) {
    if (_length >= capacity) {
      // Handle capacity overflow
      switch (capacityPolicy) {
        case EventCapacityPolicy.dropNew:
          _reportOverflow(event, dropped: true);
          return false;
        case EventCapacityPolicy.dropOld:
          // Clear old event reference before advancing
          _clearEventAt(_head);
          _advanceHead();
          _length--;
        case EventCapacityPolicy.throwOnOverflow:
          throw EventCapacityOverflow(
            channelType: T,
            capacity: capacity,
            attemptedEvent: event,
          );
      }
    }

    // Store event
    _storeEvent(_tail, event);
    _advanceTail();
    _length++;

    return true;
  }

  /// Send multiple events in batch.
  ///
  /// Attempts to send all events, stopping on first failure.
  /// Returns the number of events successfully sent.
  ///
  /// Useful for high-throughput scenarios where you want to send
  /// multiple related events together.
  int sendBatch(final List<T> events) {
    var sent = 0;
    for (final event in events) {
      if (send(event)) {
        sent++;
      } else {
        break; // Stop on first failure
      }
    }
    return sent;
  }

  /// Create a writer for sending events.
  EventWriter<T> toWriter() => EventWriter<T>._(this);

  void _advanceHead() {
    if (_isPowerOfTwo(capacity)) {
      _head = (_head + 1) & (capacity - 1);
    } else {
      _head = (_head + 1) % capacity;
    }
    _headEpoch++;
  }

  void _advanceTail() {
    if (_isPowerOfTwo(capacity)) {
      _tail = (_tail + 1) & (capacity - 1);
    } else {
      _tail = (_tail + 1) % capacity;
    }
  }

  void _clearEventAt(final int index) {
    // Use column's clear method to prevent memory leaks
    _column.clearEvent(index);
  }

  T _loadEvent(final int index) => _column.loadEvent<T>(
    index,
    fromDoubleFieldsFactory: _config.fromDoubleFieldsFactory,
  );

  void _reportOverflow(final T event, {required final bool dropped}) {
    metricsHook?.call(
      EventCapacityOverflow(
        channelType: T,
        capacity: capacity,
        attemptedEvent: event,
        dropped: dropped,
      ),
    );
  }

  void _storeEvent(final int index, final T event) {
    // Use column-based storage
    _column.storeEvent(index, event);
  }

  static bool _isPowerOfTwo(final int n) => n > 0 && (n & (n - 1)) == 0;
}

/// {@template event_reader}
/// Reader interface for iterating over events in a channel.
///
/// Provides snapshot semantics - events sent after reader creation
/// are not visible. This ensures consistent iteration during a frame.
///
/// Example:
/// ```dart
/// final reader = world.events.reader<DamageEvent>();
///
/// // Iterate over all events
/// for (final event in reader.iter()) {
///   handleDamage(event);
/// }
///
/// // Check if any events exist
/// if (reader.isNotEmpty) {
///   // Handle events
/// }
/// ```
/// {@endtemplate}
class EventReader<T extends EcsEvent> {
  const EventReader._(this._channel);

  final EventChannel<T> _channel;

  /// Whether there are no events to read.
  bool get isEmpty => _channel.isEmpty;

  /// Whether there are events to read.
  bool get isNotEmpty => !_channel.isEmpty;

  /// Number of events available to read.
  int get length => _channel.length;

  /// Create a stable cursor over the current event snapshot.
  ///
  /// This is the hot-path read API for index-based loops.
  EventCursor<T> cursor() => EventCursor<T>._(_channel);

  /// Read event at [index] in the current snapshot.
  ///
  /// Throws [RangeError] if index is out of bounds.
  T readAt(final int index) => cursor().readAt(index);

  /// Read event at [index] in the current snapshot.
  ///
  /// Returns null if index is out of bounds.
  T? tryReadAt(final int index) => cursor().tryReadAt(index);

  /// Iterate events with an allocation-free index loop.
  ///
  /// This avoids constructing iterators and should be preferred in hot paths.
  void forEach(final void Function(T event) onEvent) {
    final snapshot = cursor();
    while (snapshot.moveNext()) {
      onEvent(snapshot.current);
    }
  }

  /// Iterate events with index and value, allocation-free.
  ///
  /// Index values are relative to the cursor snapshot and do not account for
  /// concurrent drops in other cursors.
  void forEachIndexed(final void Function(int index, T event) onEvent) {
    final snapshot = cursor();
    while (snapshot.moveNext()) {
      onEvent(snapshot.index, snapshot.current);
    }
  }

  /// Drain all events into a list.
  ///
  /// Returns a list of all current events. The channel will be empty after this call.
  /// Note: Events are not automatically cleared - call clearAll() on the registry when appropriate.
  List<T> drain() {
    final snapshot = cursor();
    final result = List<T>.generate(snapshot.length, snapshot.readAt);
    return result;
  }

  /// Create an iterator over all current events.
  Iterable<T> iter() sync* {
    final snapshot = cursor();
    while (snapshot.moveNext()) {
      yield snapshot.current;
    }
  }

  /// Create a SIMD-aware iterator for FloatColumn events.
  ///
  /// Returns an iterator over raw numeric fields for SIMD processing.
  /// Only available for events stored in FloatColumn with compatible stride.
  /// Use this for bulk math operations on event fields without object allocation.
  ///
  /// Example:
  /// ```dart
  /// final fieldsIter = reader.iterSimd();
  /// if (fieldsIter != null) {
  ///   for (final fields in fieldsIter) {
  ///     // fields is Float32List with event's numeric fields
  ///     // Process with SIMD operations
  ///   }
  /// }
  /// ```
  Iterable<Float32List>? iterSimd() {
    final column = _channel._column;
    if (column is FloatColumn && column.simdView != null) {
      return _FloatColumnEventIterable<T>(_channel);
    }
    return null; // Not a SIMD-compatible FloatColumn
  }

  /// Read the first event without consuming it.
  T? peek() => tryReadAt(0);

  /// Read the first event (oldest).
  T? readFirst() => tryReadAt(0);

  /// Read the last event (newest).
  T? readLast() {
    final snapshot = cursor();
    return snapshot.tryReadAt(snapshot.length - 1);
  }
}

/// Cursor for allocation-free event reads using index-based loops.
class EventCursor<T extends EcsEvent> {
  EventCursor._(this._channel)
    : _headSnapshot = _channel._head,
      _lengthSnapshot = _channel._length,
      _headEpochSnapshot = _channel._headEpoch;

  final EventChannel<T> _channel;
  final int _headSnapshot;
  final int _lengthSnapshot;
  final int _headEpochSnapshot;

  int _index = -1;

  /// Number of events captured by this cursor snapshot.
  int get length => _lengthSnapshot;

  /// Current cursor index. `-1` before first [moveNext].
  int get index => _index;

  /// Remaining unread events in this snapshot.
  int get remaining {
    final unread = _lengthSnapshot - (_index + 1);
    return unread < 0 ? _lengthSnapshot : unread;
  }

  /// Whether the snapshot still has unread events.
  bool get hasNext => _index + 1 < _lengthSnapshot;

  /// Advance to the next event in the snapshot.
  bool moveNext() {
    _assertSnapshotValid();
    if (!hasNext) {
      return false;
    }
    _index++;
    return true;
  }

  /// Current event at [index].
  ///
  /// Throws [StateError] before first [moveNext] or after completion.
  T get current {
    if (_index < 0 || _index >= _lengthSnapshot) {
      throw StateError(
        'EventCursor<$T>.current is unavailable. '
        'Call moveNext() before reading current.',
      );
    }
    return readAt(_index);
  }

  /// Read an event by index from this snapshot.
  ///
  /// Throws [RangeError] if index is out of bounds.
  T readAt(final int index) {
    _assertSnapshotValid();
    _validateIndex(index);
    return _channel.readEventAt(index, head: _headSnapshot);
  }

  /// Read an event by index from this snapshot.
  ///
  /// Returns null if [index] is out of bounds.
  T? tryReadAt(final int index) {
    _assertSnapshotValid();
    if (index < 0 || index >= _lengthSnapshot) {
      return null;
    }
    return _channel.readEventAt(index, head: _headSnapshot);
  }

  void _validateIndex(final int index) {
    if (index < 0 || index >= _lengthSnapshot) {
      throw RangeError(
        'index $index out of bounds for length $_lengthSnapshot',
      );
    }
  }

  void _assertSnapshotValid() {
    if (_channel._headEpoch != _headEpochSnapshot) {
      throw ConcurrentModificationError(
        'EventChannel<$T> was structurally modified while reading snapshot.',
      );
    }
  }
}

/// {@template event_writer}
/// Writer interface for sending events to a channel.
///
/// Provides ergonomic methods for sending events with optional
/// success confirmation.
///
/// Example:
/// ```dart
/// final writer = context.events.writer<DamageEvent>();
///
/// // Send with confirmation
/// if (writer.trySend(DamageEvent(entity: target, amount: 10))) {
///   print('Damage event sent');
/// }
///
/// // Send without confirmation (fire-and-forget)
/// writer.send(DamageEvent(entity: target, amount: 5));
/// ```
/// {@endtemplate}
class EventWriter<T extends EcsEvent> {
  const EventWriter._(this._channel);

  final EventChannel<T> _channel;

  /// Send an event (fire-and-forget).
  ///
  /// Equivalent to [trySend] but ignores the result.
  void send(final T event) => _channel.send(event);

  /// Send multiple events in batch.
  ///
  /// Attempts to send all events, stopping on first failure.
  /// Returns the number of events successfully sent.
  int sendBatch(final List<T> events) => _channel.sendBatch(events);

  /// Send an event only if the condition is true.
  ///
  /// Convenient for conditional event sending without if statements.
  void sendIf(final T event, {required final bool condition}) {
    if (condition) send(event);
  }

  /// Send an event, returning true if successful.
  ///
  /// Returns false if the event was dropped due to capacity policy.
  bool trySend(final T event) => _channel.send(event);
}

/// Iterable for FloatColumn events.
///
/// Provides direct access to numeric fields as Float32List for SIMD processing.
/// Avoids object allocation during iteration for performance-critical math operations.
class _FloatColumnEventIterable<T extends EcsEvent>
    extends Iterable<Float32List> {
  _FloatColumnEventIterable(this._channel);
  final EventChannel<T> _channel;
  @override
  Iterator<Float32List> get iterator => _FloatColumnEventIterator<T>(_channel);
}

/// SIMD-aware iterator for FloatColumn events.
///
/// Provides direct access to numeric fields as Float32List for SIMD processing.
/// Avoids object allocation during iteration for performance-critical math operations.
class _FloatColumnEventIterator<T extends EcsEvent>
    implements Iterator<Float32List> {
  _FloatColumnEventIterator(this._channel)
    : _column = _channel._column as FloatColumn,
      _headSnapshot = _channel._head,
      _lengthSnapshot = _channel._length,
      _headEpochSnapshot = _channel._headEpoch;

  final EventChannel<T> _channel;
  final FloatColumn _column;
  final int _headSnapshot;
  final int _lengthSnapshot;
  final int _headEpochSnapshot;
  int _index = 0;

  @override
  Float32List get current {
    final eventIndex = (_headSnapshot + _index - 1) % _channel.capacity;
    final stride = _column.stride;
    final offset = eventIndex * stride;
    return Float32List.view(
      _column.data.buffer,
      offset * Float32List.bytesPerElement,
      stride,
    );
  }

  @override
  bool moveNext() {
    if (_channel._headEpoch != _headEpochSnapshot) {
      throw ConcurrentModificationError(
        'EventChannel<$T> was structurally modified while reading SIMD snapshot.',
      );
    }
    if (_index < _lengthSnapshot) {
      _index++;
      return true;
    }
    return false;
  }
}
