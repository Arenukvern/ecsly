import 'context_event.dart';

/// Append-only event storage: the single source of truth of a context.
///
/// State is never persisted as truth — it is always the fold of
/// [load]'s events. Implementations must make [append] durable before
/// returning, so an event is either fully acknowledged or absent.
abstract interface class ContextStore {
  /// Loads every event in order, repairing an unacknowledged corrupt tail.
  List<ContextEvent> load();

  /// Durably appends one event (fsync before returning).
  void append(final ContextEvent event);

  /// Durably appends a batch under ONE flush: a crash mid-batch leaves a
  /// prefix whose partial final line is tail-repaired, so the contract
  /// (an event is either fully acknowledged or absent) holds at batch
  /// granularity. Imports and migrations must use this — per-event
  /// flushing makes bulk loads fsync-bound.
  void appendAll(final List<ContextEvent> events);

  /// Releases the store: handles and lock files. Idempotent.
  void close();
}
