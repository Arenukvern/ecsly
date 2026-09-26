/// Live World-to-delta bridge for [ecsly] worlds (ecsly ADR 0002).
///
/// Pulls forward the live-bridge deferral of ADR 0001:
///
/// - [WorldSyncBridge] diffs `ecsly_serialization` world captures at flush
///   boundaries into `ecsly_world_sync` [ComponentDelta]s — stable keys from
///   `PersistentId`, never runtime entity handles; spawn/despawn surface as
///   new keys and tombstones.
/// - [WorldSyncDriver] runs anti-entropy over a [WorldSyncTransport]:
///   version-vector exchange, op batches, and kernel snapshots for peers the
///   compacted log can no longer serve, on a [SnapshotPolicy].
/// - [WorldSyncMessage] is the wire envelope (vv / ops / snapshot) with a
///   JSON codec; [LocalSyncHub] is the in-memory test transport.
///
/// Merge semantics stay in the convergence kernel
/// (`universal_storage_convergence`). No real networking, no
/// kernel-to-World reverse materialization, no presence, no rollback.
library;

export 'package:ecsly_world_sync/ecsly_world_sync.dart'
    show ComponentDelta, WorldProjection, WorldSync, WorldSyncEvent;

export 'src/snapshot_policy.dart';
export 'src/world_sync_bridge.dart';
export 'src/world_sync_driver.dart' hide SnapshotPolicy;
export 'src/world_sync_message.dart';
export 'src/world_sync_transport.dart';
