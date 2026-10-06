import 'package:ecsly_context/ecsly_context.dart';

/// In-memory [ContextStore] for graph and projection tests.
final class MemoryStore implements ContextStore {
  /// Every appended event, in order.
  final List<ContextEvent> events = <ContextEvent>[];

  var _closed = false;

  @override
  List<ContextEvent> load() => List.of(events);

  @override
  void append(final ContextEvent event) {
    if (_closed) {
      throw StateError('MemoryStore is closed');
    }
    events.add(event);
  }

  @override
  void appendAll(final List<ContextEvent> events) {
    if (_closed) {
      throw StateError('MemoryStore is closed');
    }
    this.events.addAll(events);
  }

  @override
  void close() {
    _closed = true;
  }
}
