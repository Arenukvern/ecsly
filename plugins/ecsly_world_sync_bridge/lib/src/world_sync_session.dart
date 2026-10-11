import 'dart:async';
import 'dart:typed_data';

// cancel_subscriptions: the inbound subscription's cancel is deliberately
// owned by stop() (not the creating function), so a restart can wait out
// the radio's release; the diagnostic cannot see across methods.
// ignore_for_file: cancel_subscriptions

import 'package:ecsly_world_sync/ecsly_world_sync.dart';
import 'package:universal_storage_convergence_session/universal_storage_convergence_session.dart';
import 'package:universal_storage_mesh_transport/universal_storage_mesh_transport.dart';

/// Anti-entropy session for one [WorldSync] replica over the foundation's
/// mesh radio (ecsly ADR 0004; owns the schedule role ADR 0002 gave the
/// old bespoke driver).
///
/// Everything below the schedule is the foundation's, never re-implemented
/// here: the wire is the session core's [MeshSyncProtocol] (hello → vv →
/// delta, byte-identical with the mesh exchange), the what-to-send decision
/// is the session core's [DeltaPlanner] run against the replica's own
/// [DeltaReplica] seam, compaction is the session core's [shouldCompact]
/// policy, and the radio is `universal_storage_mesh_transport`'s
/// [MeshTransport] (framing, LAN sockets, relays, and fakes live there).
/// Ordering, dedupe, folding, and staleness stay in the kernel and the
/// session core; this class decides only *when* peers are dialed and
/// applies what each round returns.
///
/// Each round runs the session protocol's symmetric script with one peer:
/// both sides announce `hello` + `vv`, both compute a plan from the peer's
/// vectors, both ship one `delta`. A session the PEER dialed is handled by
/// the same code — the script is symmetric, so initiator and responder are
/// one implementation and simultaneous mutual dials are safe (each
/// direction runs over its own session; both rounds converge or both are
/// no-ops). A round where nothing changed ships empty deltas and touches
/// nothing: zero-ops exchange rounds are idempotent.
///
/// No pairing, discovery, or presence is claimed here (ADR 0004 §3): the
/// peer records come from the owner's pairing layer, and sync stays
/// opportunistic — an unreachable peer is "try again next tick", never an
/// error condition for the replica.
final class WorldSyncSession {
  /// Creates a session driver for [sync] talking over [transport].
  ///
  /// [peerId] is this replica's radio identity (independent of the kernel
  /// actor id, which [WorldSync] owns); [displayName] rides the hello
  /// frame. [peers] are the paired records to dial on every [tick].
  /// [maxLogOps] / [minInterval] feed the session core's compaction policy
  /// (defaults: the shared 512 ops / 5 minutes); pass `null` to disable a
  /// trigger. [clock] defaults to [DateTime.now] so tests can drive
  /// deterministic compaction intervals.
  WorldSyncSession({
    required this.sync,
    required this.transport,
    required this.peerId,
    required this.peers,
    final String? displayName,
    this.maxLogOps = defaultMaxLogOps,
    this.minInterval = defaultMinInterval,
    final DateTime Function()? clock,
  }) : _displayName = displayName ?? peerId,
       _now = clock ?? DateTime.now,
       _lastCompactionAt = (clock ?? DateTime.now)();

  /// The replica this driver serves.
  final WorldSync sync;

  /// The radio linking this replica to [peers].
  final MeshTransport transport;

  /// This side's radio identity (hello frame, diagnostics).
  final String peerId;

  /// Paired peers this replica exchanges with, one round each per [tick].
  final Set<MeshPeerRecord> peers;

  /// Log-length trigger handed to the session core's compaction policy.
  final int? maxLogOps;

  /// Interval trigger handed to the session core's compaction policy.
  final Duration? minInterval;

  final String _displayName;
  final DateTime Function() _now;
  DateTime _lastCompactionAt;
  Timer? _timer;
  StreamSubscription<MeshSession>? _incomingSubscription;

  /// The pending cancel of a released subscription, if one is still
  /// settling — a re-listen must wait for the radio to let go first.
  Future<void>? _incomingCancel;

  /// Bumps on every [listen]/[stop], so a deferred re-listen scheduled by
  /// an earlier call does not fire after the owner changed its mind.
  int _listenEpoch = 0;
  bool _running = false;
  bool _tickInFlight = false;

  /// Whether [start] is active (inbound subscription + periodic timer live).
  bool get isRunning => _running;

  /// How many exchange rounds completed (diagnostics).
  int get exchanges => _exchanges;
  int _exchanges = 0;

  /// How many exchange rounds failed — unreachable peers, closed sessions
  /// (diagnostics; failures are counted, never fatal).
  int get failedExchanges => _failedExchanges;
  int _failedExchanges = 0;

  /// How many compactions this driver has executed (diagnostics).
  int get compactions => _compactions;
  int _compactions = 0;

  /// Subscribes to the radio: every session a peer dials in runs the same
  /// exchange script (responder == initiator). Idempotent while live; if a
  /// previous [stop]'s cancel is still settling, the re-subscribe waits
  /// for the radio to release the old subscription. The radio's `incoming`
  /// stream must tolerate a fresh listen after a cancel completes — the
  /// foundation's LAN transport backs it with a broadcast controller.
  void listen() {
    if (_incomingSubscription != null) return;
    final epoch = ++_listenEpoch;
    final settling = _incomingCancel;
    if (settling != null) {
      unawaited(
        settling.then((final _) {
          if (epoch == _listenEpoch) {
            _incomingCancel = null;
            _subscribe();
          }
        }),
      );
      return;
    }
    _subscribe();
  }

  void _subscribe() {
    _incomingSubscription = transport.incoming.listen(_accept);
  }

  /// Starts the periodic mode: [listen]s to the radio and repeats [tick]
  /// every [interval]. Calling [start] while running re-times the period
  /// without dropping the live inbound subscription.
  void start({final Duration interval = const Duration(seconds: 5)}) {
    listen();
    _timer?.cancel();
    _timer = Timer.periodic(interval, (final _) {
      unawaited(_tickGuarded());
    });
    _running = true;
  }

  /// Stops the periodic mode: no more ticks, and the inbound subscription
  /// is released. Safe to call repeatedly; [tick] remains usable manually.
  /// An in-flight round finishes on its own.
  void stop() {
    _timer?.cancel();
    _timer = null;
    _listenEpoch++;
    final subscription = _incomingSubscription;
    if (subscription != null) {
      _incomingCancel = subscription.cancel();
      _incomingSubscription = null;
    }
    _running = false;
  }

  /// One anti-entropy round: exchange with every peer (parallel, failures
  /// isolated per peer), then apply the session core's compaction policy to
  /// the replica's pending log.
  Future<void> tick() async {
    await Future.wait([for (final peer in peers) _dial(peer)]);
    _maybeCompact();
  }

  Future<void> _dial(final MeshPeerRecord peer) async {
    try {
      final session = await transport.connect(peer);
      await _exchangeWith(session);
    }
    // Sync is opportunistic (mesh ADR 0010 §4): ANY radio failure is
    // counted and retried on a later tick — it must never take the
    // replica or the timer down.
    // ignore: avoid_catches_without_on_clauses
    catch (_) {
      _failedExchanges++;
    }
  }

  Future<void> _accept(final MeshSession session) async {
    try {
      await _exchangeWith(session);
    }
    // Same contract as _dial: a failed inbound round is counted, never
    // fatal.
    // ignore: avoid_catches_without_on_clauses
    catch (_) {
      _failedExchanges++;
    }
  }

  /// Guards the periodic timer against stacking: a hung round skips ticks
  /// instead of piling up parallel exchanges to the same peer.
  Future<void> _tickGuarded() async {
    if (_tickInFlight) return;
    _tickInFlight = true;
    try {
      await tick();
    } finally {
      _tickInFlight = false;
    }
  }

  /// One symmetric script over [session] — the session-core protocol
  /// (hello, vv, delta), planned by [DeltaPlanner] against the replica's
  /// own [DeltaReplica] seam. The session closes when the round ends.
  Future<void> _exchangeWith(final MeshSession session) async {
    final inbound = StreamIterator<Uint8List>(session.inbound);
    try {
      await _send(
        session,
        MeshSyncProtocol.hello(peerId: peerId, displayName: _displayName),
      );
      await _send(
        session,
        MeshSyncProtocol.vv({sync.docId: sync.vv}),
      );

      // The peer's announcement: skip its hello/sub frames, take the vv.
      // Worlds are wildcard-delivered — no interest frame is sent, and a
      // peer's `sub` (if any) does not gate a single-doc world.
      Map<String, Object?>? announced;
      while (announced == null && await inbound.moveNext()) {
        final message = MeshSyncProtocol.decode(inbound.current);
        if (message['type'] == MeshSyncProtocol.vvType) announced = message;
      }
      if (announced == null) {
        throw StateError(
          'world sync: session closed before the peer announced its vectors',
        );
      }
      final plan = const DeltaPlanner().plan(
        docs: [sync],
        remoteVectors: MeshSyncProtocol.parseVv(announced),
      );
      await _send(
        session,
        MeshSyncProtocol.delta(ops: plan.ops, states: plan.states),
      );

      final incoming = MeshSyncProtocol.parseDelta(
        await _recvOfType(inbound, MeshSyncProtocol.deltaType),
      );
      sync.applyRemote(incoming.ops);
      // The kernel rejects stale snapshots on adoption, so over-sending
      // stays safe.
      incoming.states.forEach(sync.adoptSnapshot);
      _exchanges++;
    } finally {
      await inbound.cancel();
      await session.close();
    }
  }

  void _maybeCompact() {
    final now = _now();
    if (!shouldCompact(
      logLength: sync.pendingOps.length,
      now: now,
      lastCompactionAt: _lastCompactionAt,
      maxLogOps: maxLogOps,
      minInterval: minInterval,
    )) {
      return;
    }
    sync.compact();
    _lastCompactionAt = now;
    _compactions++;
  }

  Future<void> _send(final MeshSession session, final Map<String, Object?> message) =>
      session.send(MeshSyncProtocol.encode(message));

  Future<Map<String, Object?>> _recvOfType(
    final StreamIterator<Uint8List> inbound,
    final String type,
  ) async {
    while (await inbound.moveNext()) {
      final message = MeshSyncProtocol.decode(inbound.current);
      if (message['type'] == type) return message;
    }
    throw StateError(
      'world sync: session closed while waiting for "$type"',
    );
  }
}
