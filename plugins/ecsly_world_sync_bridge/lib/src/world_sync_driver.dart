import 'dart:async';

import 'package:ecsly_world_sync/ecsly_world_sync.dart';

import 'snapshot_policy.dart';
import 'world_sync_message.dart';
import 'world_sync_transport.dart';

export 'snapshot_policy.dart';
export 'world_sync_message.dart';
export 'world_sync_transport.dart';

/// Anti-entropy driver over one [WorldSync] replica and one
/// [WorldSyncTransport] (ecsly ADR 0002).
///
/// Protocol per exchange round:
///
/// 1. [tick] sends every peer a [VvMessage] carrying this replica's
///    [WorldSync.vv];
/// 2. on a peer's [VvMessage], answer with [OpsMessage]
///    ([WorldSync.opsFor]) — or, when the log can no longer serve that peer
///    (compacted), a [SnapshotMessage] ([WorldSync.needsSnapshotFor] /
///    [WorldSync.snapshotFor]);
/// 3. [OpsMessage]s fold via [WorldSync.applyRemote]; [SnapshotMessage]s go
///    through [WorldSync.adoptSnapshot], which the kernel makes safe against
///    stale/unneeded snapshots (it only adopts genuinely newer state).
///
/// Ordering, dedupe, and merge semantics stay in the kernel; the driver only
/// decides *when* to send what. Every [tick] also applies the
/// [SnapshotPolicy] and compacts ([WorldSync.compact]) when it fires.
///
/// [start] additionally subscribes to the transport and repeats the round on
/// a [Timer]; tests usually drive [tick] and
/// [handleIncoming] directly for determinism.
final class WorldSyncDriver {
  /// Creates a driver for [sync] talking to [peers] over [transport].
  ///
  /// [policy] defaults to [SnapshotPolicy] defaults (512 ops / 5 minutes);
  /// pass [SnapshotPolicy(maxLogOps: 0x7fffffffffffffff)]-style values to
  /// effectively disable size-triggered compaction. [clock] defaults to
  /// [DateTime.now].
  WorldSyncDriver({
    required this.sync,
    required this.transport,
    required this.peers,
    this.policy = const SnapshotPolicy(),
    final DateTime Function()? clock,
  }) : _now = clock ?? DateTime.now,
       _lastCompactionAt = (clock ?? DateTime.now)();

  /// The replica this driver serves.
  final WorldSync sync;

  /// The outbound/inbound link to all [peers].
  final WorldSyncTransport transport;

  /// Peer ids this replica exchanges with.
  final Set<String> peers;

  /// Compaction policy applied on every [tick].
  final SnapshotPolicy policy;

  final DateTime Function() _now;
  DateTime _lastCompactionAt;
  StreamSubscription<WorldSyncIncoming>? _subscription;
  Timer? _timer;
  bool _running = false;

  /// Whether [start] is active (subscription + periodic timer live).
  bool get isRunning => _running;

  /// How many compactions this driver has executed (diagnostics).
  int get compactions => _compactions;
  int _compactions = 0;

  /// Anti-entropy round: send our [VvMessage] to every peer, then apply the
  /// [SnapshotPolicy] (compacting when it fires).
  void tick() {
    final vv = sync.vv;
    for (final peer in peers) {
      transport.send(peer, VvMessage(vv));
    }
    if (policy.shouldCompact(sync, _now(), lastCompactionAt: _lastCompactionAt)) {
      sync.compact();
      _lastCompactionAt = _now();
      _compactions++;
    }
  }

  /// Handles one inbound message. Public so tests (and custom pumps) can
  /// drive delivery deterministically without the transport stream.
  void handleIncoming(final WorldSyncIncoming incoming) =>
      _handle(incoming.fromPeerId, incoming.message);

  void _handle(final String fromPeerId, final WorldSyncMessage message) {
    switch (message) {
      case VvMessage(:final vv):
        final ops = sync.opsFor(vv);
        if (ops.isNotEmpty) {
          transport.send(fromPeerId, OpsMessage(ops));
        } else if (sync.needsSnapshotFor(vv)) {
          // Log compacted past what this peer has seen: only a full
          // snapshot can serve it. The kernel rejects stale snapshots on
          // adoption, so over-sending stays safe.
          transport.send(fromPeerId, SnapshotMessage(sync.snapshotFor()));
        }
      case OpsMessage(:final ops):
        sync.applyRemote(ops);
      case SnapshotMessage(:final snapshot):
        sync.adoptSnapshot(snapshot);
    }
  }

  /// Starts the periodic mode: subscribes to
  /// [WorldSyncTransport.messages] (routing each envelope through
  /// [handleIncoming]) and repeats [tick] every [interval]. Calling [start]
  /// while running re-times the period.
  void start({final Duration interval = const Duration(seconds: 5)}) {
    stop();
    _subscription = transport.messages.listen(handleIncoming);
    _timer = Timer.periodic(interval, (final _) => tick());
    _running = true;
  }

  /// Stops the periodic mode. Safe to call repeatedly; [tick] and
  /// [handleIncoming] remain usable manually.
  void stop() {
    _timer?.cancel();
    _timer = null;
    unawaited(_subscription?.cancel());
    _subscription = null;
    _running = false;
  }
}
