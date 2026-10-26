import 'package:universal_storage_convergence/universal_storage_convergence.dart';

/// In-memory fake transport for convergence tests and examples.
///
/// Test-only: no sockets, no relays, no real networking (ecsly ADR 0001
/// non-claim). Ops are copied through JSON on the wire so no replica can
/// accidentally share mutable state with a sender.
final class FakeTransport {
  final Map<String, List<OpRecord>> _inboxes = {};

  /// Registers an inbox for [actorId]. Idempotent.
  void register(final String actorId) =>
      _inboxes.putIfAbsent(actorId, () => []);

  /// Sends a JSON-encoded copy of [ops] from [from] to [to]'s inbox.
  void send(
    final String from,
    final String to,
    final Iterable<OpRecord> ops,
  ) {
    final inbox = _inboxes[to];
    if (inbox == null) {
      throw ArgumentError.value(to, 'to', 'Unregistered replica');
    }
    if (from == to) {
      throw ArgumentError.value(to, 'to', 'A replica cannot send to itself');
    }
    for (final op in ops) {
      inbox.add(OpRecord.fromJson(op.toJson()));
    }
  }

  /// Removes and returns everything queued for [actorId].
  List<OpRecord> drain(final String actorId) {
    final inbox = _inboxes[actorId];
    if (inbox == null) {
      throw ArgumentError.value(actorId, 'actorId', 'Unregistered replica');
    }
    final out = List<OpRecord>.of(inbox);
    inbox.clear();
    return out;
  }
}
