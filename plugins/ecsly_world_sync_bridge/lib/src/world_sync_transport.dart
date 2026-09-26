// close_sinks: hub controllers live for the process (or until the hub is
// dropped); this local test transport has no close point.
// ignore_for_file: close_sinks

import 'dart:async';

import 'world_sync_message.dart';

/// One incoming message plus the peer it came from.
final class WorldSyncIncoming {
  /// Creates an envelope from [fromPeerId] carrying [message].
  const WorldSyncIncoming({required this.fromPeerId, required this.message});

  /// Sender's peer id.
  final String fromPeerId;

  /// The decoded message.
  final WorldSyncMessage message;

  @override
  String toString() =>
      'WorldSyncIncoming(from: $fromPeerId, message: $message)';
}

/// Outbound link for world-sync messages (ecsly ADR 0002).
///
/// The transport moves opaque [WorldSyncMessage]s between peer ids; it never
/// interprets them. Implementations must not share mutable state between
/// sender and receiver — deep-copy messages on send (the JSON round-trip in
/// [WorldSyncMessage.toJson]/[WorldSyncMessage.fromJson] is sufficient).
///
/// No real networking ships here (ADR 0001 non-claim carries over): the only
/// bundled implementation is [LocalSyncTransport], an in-memory hub for
/// tests and local examples. Sockets, relays, and discovery are later
/// phases.
abstract interface class WorldSyncTransport {
  /// Sends [message] to [toPeerId]. Fire-and-forget; delivery guarantees
  /// (ordering, at-most-once) are the transport's own contract.
  void send(final String toPeerId, final WorldSyncMessage message);

  /// Messages arriving from any peer.
  Stream<WorldSyncIncoming> get messages;
}

/// Shared in-memory wire behind the [LocalSyncTransport] links of one
/// [LocalSyncHub].
final class _Wire {
  final Map<String, List<WorldSyncIncoming>> _inboxes = {};
  final Map<String, StreamController<WorldSyncIncoming>> _controllers = {};

  void _register(final String peerId) {
    _inboxes.putIfAbsent(peerId, () => []);
    _controllers.putIfAbsent(
      peerId,
      // Sync delivery: `flush`/`deliver` run listener callbacks inline, so
      // tests drive exchanges deterministically (no event-loop awaits).
      () => StreamController<WorldSyncIncoming>.broadcast(sync: true),
    );
  }

  void _route(
    final String from,
    final String to,
    final WorldSyncMessage message,
  ) {
    final inbox = _inboxes[to];
    if (inbox == null) {
      throw ArgumentError.value(to, 'to', 'Unregistered peer');
    }
    if (from == to) {
      throw ArgumentError.value(to, 'to', 'A peer cannot send to itself');
    }
    // Deep-copy through the wire form so receiver and sender share nothing.
    inbox.add(
      WorldSyncIncoming(
        fromPeerId: from,
        message: WorldSyncMessage.fromJson(message.toJson()),
      ),
    );
  }
}

/// In-memory N-peer hub for world-sync tests and local examples.
///
/// Register one [LocalSyncTransport] per peer; sends are routed through the
/// hub and queued per recipient. Delivery is explicit and synchronous, so
/// tests fully control order:
///
/// - [LocalSyncTransport.flush] delivers every queued message in FIFO order;
/// - [LocalSyncTransport.takeQueued] hands the queue over for deliberate
///   reordering (shuffled-delivery tests) before
///   [LocalSyncTransport.deliver] replays it.
final class LocalSyncHub {
  final _Wire _wire = _Wire();

  /// Registers [peerId] and returns its transport link. Idempotent per id;
  /// repeated calls return links to the same queue.
  LocalSyncTransport register(final String peerId) {
    _wire._register(peerId);
    return LocalSyncTransport._(peerId, _wire);
  }
}

/// One peer's view of a [LocalSyncHub].
final class LocalSyncTransport implements WorldSyncTransport {
  LocalSyncTransport._(this.peerId, this._wire);

  /// This link's own peer id (stamped onto everything it sends).
  final String peerId;

  final _Wire _wire;

  @override
  void send(final String toPeerId, final WorldSyncMessage message) =>
      _wire._route(peerId, toPeerId, message);

  @override
  Stream<WorldSyncIncoming> get messages => _wire._controllers[peerId]!.stream;

  /// Whether undelivered messages are queued for this peer.
  bool get hasQueued => _wire._inboxes[peerId]!.isNotEmpty;

  /// Delivers every queued message in FIFO order. Listeners registered on
  /// [messages] run synchronously before this returns.
  void flush() {
    final inbox = _wire._inboxes[peerId]!;
    final controller = _wire._controllers[peerId]!;
    while (inbox.isNotEmpty) {
      controller.add(inbox.removeAt(0));
    }
  }

  /// Removes and returns the queued messages without delivering them —
  /// for tests that reorder delivery on purpose.
  List<WorldSyncIncoming> takeQueued() {
    final inbox = _wire._inboxes[peerId]!;
    final out = List<WorldSyncIncoming>.of(inbox);
    inbox.clear();
    return out;
  }

  /// Delivers one specific envelope out of order (pair with [takeQueued]).
  void deliver(final WorldSyncIncoming incoming) =>
      _wire._controllers[peerId]!.add(incoming);
}

/// Convenience: a connected pair sharing one [LocalSyncHub].
(LocalSyncTransport, LocalSyncTransport) localSyncPair(
  final String peerA,
  final String peerB,
) {
  final hub = LocalSyncHub();
  return (hub.register(peerA), hub.register(peerB));
}
