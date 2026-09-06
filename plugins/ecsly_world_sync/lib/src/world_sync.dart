import 'dart:convert';

import 'package:universal_storage_convergence/universal_storage_convergence.dart';

import 'component_delta.dart';
import 'world_projection.dart';
import 'world_sync_event.dart';

export 'component_delta.dart';
export 'world_projection.dart';
export 'world_sync_event.dart';

/// World-sync adapter over the convergence kernel (ecsly ADR 0001; kernel
/// ADR 0011).
///
/// Converts world event-channel events and component deltas into kernel
/// [OpRecord]s (LWW map strategy by default; one op per keyed piece of
/// state), and folds remote ops back into a [WorldProjection].
///
/// Boundary (kernel ADR 0011): this adapter chooses the merge strategy and
/// compaction policy; it never hand-rolls ordering, version vectors, or
/// fold rules — everything below the op payload is the kernel's job, and
/// the kernel never learns about worlds.
///
/// Values are stored JSON-encoded so any JSON-encodable payload rides the
/// kernel's LWW map readers unchanged.
final class WorldSync {
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
       );

  /// Restores a replica from [json] previously written by [toJson]
  /// (durable local persistence, including HLC monotonicity state).
  factory WorldSync.fromJson(final Map<String, dynamic> json) {
    final doc = ConvergenceDoc.fromJson(json);
    final sync = WorldSync._(doc);
    return sync;
  }

  WorldSync._(this._doc)
    : actorId = _doc.actorId,
      docId = _doc.docId {
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
  final String docId;

  /// Local actor id; also the HLC actor tiebreak.
  final String actorId;

  final ConvergenceDoc _doc;

  /// High-water marks of applied ops per actor (kernel [VersionVector]).
  VersionVector get vv => _doc.vv;

  /// Ops retained for delta shipping (not yet compacted).
  List<OpRecord> get pendingOps => _doc.pendingOps;

  /// Ops this replica holds that [remoteVv] has not observed (anti-entropy
  /// delta, kernel ADR 0011 §3).
  List<OpRecord> opsFor(final VersionVector remoteVv) =>
      _doc.opsSince(remoteVv);

  /// True when [remoteVv] is fully covered but the log was compacted and
  /// the peer still needs a snapshot.
  bool needsSnapshotFor(final VersionVector remoteVv) =>
      _doc.needsSnapshotFor(remoteVv);

  /// Current state as a kernel [Snapshot] at our own watermark.
  Snapshot snapshotFor() => _doc.snapshotFor();

  /// Adopts a remote [snapshot] when it carries unseen events.
  bool adoptSnapshot(final Snapshot snapshot) => _doc.adoptSnapshot(snapshot);

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
  int applyRemote(final Iterable<OpRecord> ops) => _doc.applyRemote(ops);

  /// Read-only projection of the current world state.
  WorldProjection get projection =>
      WorldProjection.fromState(_doc.state);

  /// Full serialization for durable local persistence.
  Map<String, dynamic> toJson() => _doc.toJson();

  OpRecord _apply(final String key, final Object? value, final DateTime now) =>
      _doc.applyLocal({'k': key, 'v': jsonEncode(value)}, now);

  OpRecord _remove(final String key, final DateTime now) =>
      _doc.applyLocal({'k': key, 'del': true}, now);
}
