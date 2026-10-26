import 'dart:convert';

import 'package:universal_storage_convergence/universal_storage_convergence.dart';
import 'package:universal_storage_convergence_session/universal_storage_convergence_session.dart';

import 'component_delta.dart';
import 'world_projection.dart';
import 'world_sync_event.dart';

export 'component_delta.dart';
export 'world_projection.dart';
export 'world_sync_event.dart';

/// World-sync adapter over the convergence kernel (ecsly ADR 0001; kernel
/// ADR 0011), on the shared anti-entropy session core (ecsly ADR 0004).
///
/// Converts world event-channel events and component deltas into kernel
/// [OpRecord]s (LWW map strategy by default; one op per keyed piece of
/// state), and folds remote ops back into a [WorldProjection].
///
/// Boundary (kernel ADR 0011): this adapter chooses the merge strategy and
/// compaction policy; it never hand-rolls ordering, version vectors, or
/// fold rules — everything below the op payload is the kernel's job, and
/// the kernel never learns about worlds. The session core contributes the
/// receive watermark and the [DeltaReplica] seam: [WorldSync] is a
/// first-class replica for the session package's [DeltaPlanner], so any
/// session-driven exchange plans against it directly.
///
/// Values are stored JSON-encoded so any JSON-encodable payload rides the
/// kernel's LWW map readers unchanged.
final class WorldSync implements DeltaReplica {
  /// Creates a replica for [docId] owned by [actorId].
  ///
  /// [strategy] is fixed per replica instance (protocol-breaking to change
  /// across replicas, per the kernel contract); the default is the kernel's
  /// LWW map strategy.
  WorldSync({
    required this.actorId,
    this.docId = defaultDocId,
    final MergeStrategy strategy = defaultStrategy,
  }) : _doc = ConvergenceDoc(
         docId: docId,
         actorId: actorId,
         strategy: strategy,
       ),
       _watermark = ReceiveWatermark(actorId: actorId);

  /// Restores a replica from [json] previously written by [toJson]
  /// (durable local persistence, including HLC monotonicity state).
  ///
  /// The receive watermark (key `receive_watermark`) is restored with the
  /// doc when present; older files without the key restore with a fresh
  /// watermark — they predate the ahead-clock fix, so there is nothing to
  /// restore (ecsly ADR 0004).
  factory WorldSync.fromJson(final Map<String, dynamic> json) {
    final doc = ConvergenceDoc.fromJson(json);
    final watermarkJson = json['receive_watermark'];
    final watermark = watermarkJson == null
        ? ReceiveWatermark(actorId: doc.actorId)
        : ReceiveWatermark.fromJson(
            Map<String, dynamic>.from(watermarkJson as Map<dynamic, dynamic>),
          );
    return WorldSync._(doc, watermark);
  }

  WorldSync._(this._doc, [final ReceiveWatermark? watermark])
    : actorId = _doc.actorId,
      docId = _doc.docId,
      _watermark = watermark ?? ReceiveWatermark(actorId: _doc.actorId) {
    if (_doc.strategy.name != defaultStrategy.name) {
      throw ArgumentError.value(
        _doc.strategy.name,
        'strategy',
        'WorldSync projection assumes the LWW map strategy',
      );
    }
  }

  /// Default kernel document id for a synced world.
  static const String defaultDocId = 'world';

  /// Default merge strategy: the kernel's LWW map.
  static const MergeStrategy defaultStrategy = LwwMapStrategy();

  /// Kernel document id all this replica's ops carry.
  @override
  final String docId;

  /// Local actor id; also the HLC actor tiebreak.
  final String actorId;

  final ConvergenceDoc _doc;

  /// High-water HLC of everything RECEIVED (remote ops, adopted snapshot
  /// `createdAt`) — the causality floor for local writes (ecsly ADR 0004).
  ///
  /// WHY: the kernel folds remote ops without ticking the local clock, so
  /// LWW orders a post-fold local write by raw wall clock — a peer with an
  /// ahead wall clock would outrank it forever. The watermark closes that
  /// at this layer, exactly as the session core's ReceiveWatermark
  /// documents: [ReceiveWatermark.floorNow] bounds the wall component of
  /// the next local write and the watermark's value rides the kernel's
  /// `lastIssued` seam for the counter component. Both together make a
  /// local write issued after folding a remote op strictly outrank it.
  final ReceiveWatermark _watermark;

  /// High-water marks of applied ops per actor (kernel [VersionVector]).
  @override
  VersionVector get vv => _doc.vv;

  /// Ops retained for delta shipping (not yet compacted).
  @override
  List<OpRecord> get pendingOps => _doc.pendingOps;

  /// Ops this replica holds that [remoteVv] has not observed (anti-entropy
  /// delta, kernel ADR 0011 §3).
  List<OpRecord> opsFor(final VersionVector remoteVv) =>
      _doc.opsSince(remoteVv);

  /// Session-core spelling of [opsFor] ([DeltaReplica.opsSince]): same
  /// kernel diff seam, named the way the shared [DeltaPlanner] reads it.
  @override
  List<OpRecord> opsSince(final VersionVector remoteVv) =>
      opsFor(remoteVv);

  /// True when [remoteVv] is fully covered but the log was compacted and
  /// the peer still needs a snapshot.
  @override
  bool needsSnapshotFor(final VersionVector remoteVv) =>
      _doc.needsSnapshotFor(remoteVv);

  /// Current state as a kernel [Snapshot] at our own watermark.
  @override
  Snapshot snapshotFor() => _doc.snapshotFor();

  /// Adopts a remote [snapshot] when it carries unseen events. An adopted
  /// snapshot's `createdAt` raises the receive watermark, so local writes
  /// after wholesale adoption order after the adopted content.
  bool adoptSnapshot(final Snapshot snapshot) {
    final adopted = _doc.adoptSnapshot(snapshot);
    if (adopted) _watermark.observeSnapshot(snapshot);
    return adopted;
  }

  /// Compacts the pending op log into the current state (parent-chosen
  /// compaction policy, executed by the kernel). Returns retired op count.
  int compact() => _doc.compact();

  /// Converts a [ComponentDelta] into one kernel op, folds it locally, and
  /// returns it for transport by the caller.
  OpRecord applyDelta(final ComponentDelta delta, final DateTime now) =>
      _apply(delta.syncKey, delta.value, now);

  /// Converts a [WorldSyncEvent] into one kernel op, folds it locally, and
  /// returns it for transport by the caller.
  OpRecord applyEvent(final WorldSyncEvent event, final DateTime now) =>
      _apply(event.syncKey, event.value, now);

  /// Emits a tombstone for [key] so the removal propagates to replicas that
  /// never saw the value. Returns the kernel op.
  OpRecord removeDelta(final ComponentDelta delta, final DateTime now) =>
      _remove(delta.syncKey, now);

  /// Emits a tombstone for an event key. Returns the kernel op.
  OpRecord removeEvent(final WorldSyncEvent event, final DateTime now) =>
      _remove(event.syncKey, now);

  /// Folds remote [ops] into this replica's projection. Dedupe and ordering
  /// are the kernel's; returns how many ops were newly applied.
  ///
  /// Every op's HLC is observed into the receive watermark — redelivered or
  /// already-folded ops included (raise-only, so re-observation is a
  /// no-op): having SEEN a timestamp is what makes it a causality floor,
  /// regardless of what the fold did with it.
  int applyRemote(final Iterable<OpRecord> ops) {
    final applied = _doc.applyRemote(ops);
    for (final op in ops) {
      _watermark.observe(op.hlc);
    }
    return applied;
  }

  /// Read-only projection of the current world state.
  WorldProjection get projection =>
      WorldProjection.fromState(_doc.state);

  /// Full serialization for durable local persistence (includes the
  /// receive watermark; older readers that ignore the key stay compatible).
  Map<String, dynamic> toJson() => {
    ..._doc.toJson(),
    'receive_watermark': _watermark.toJson(),
  };

  OpRecord _apply(final String key, final Object? value, final DateTime now) =>
      _doc.applyLocal(
        {'k': key, 'v': jsonEncode(value)},
        _watermark.floorNow(now),
        lastIssued: _watermark.value,
      );

  OpRecord _remove(final String key, final DateTime now) =>
      _doc.applyLocal(
        {'k': key, 'del': true},
        _watermark.floorNow(now),
        lastIssued: _watermark.value,
      );
}
