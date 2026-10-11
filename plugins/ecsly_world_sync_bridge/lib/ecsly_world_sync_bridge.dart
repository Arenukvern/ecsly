/// Live World-to-delta bridge for [ecsly] worlds (ecsly ADR 0002, re-set on
/// the foundation's session core by ADR 0004).
///
/// Pulls forward the live-bridge deferral of ADR 0001:
///
/// - [WorldSyncBridge] diffs `ecsly_serialization` world captures at flush
///   boundaries into `ecsly_world_sync` [ComponentDelta]s — stable keys from
///   `PersistentId`, never runtime entity handles; spawn/despawn surface as
///   new keys and tombstones.
/// - [WorldSyncSession] runs anti-entropy over a `universal_storage_mesh_transport`
///   [MeshTransport]: the session core's wire (`MeshSyncProtocol`), the
///   session core's `DeltaPlanner` for what-to-send, and the session core's
///   compaction policy. This package owns only the ECS capture diff and the
///   schedule — never the protocol, the decisions, or the radio.
///
/// Merge semantics stay in the convergence kernel
/// (`universal_storage_convergence`). No networking of its own is claimed:
/// pairing, discovery, framing, and radios are
/// `universal_storage_mesh_transport`'s domain (its `FakeMeshPair` stands
/// in for tests); no kernel→World reverse materialization, no presence, no
/// rollback.
library;

export 'package:ecsly_world_sync/ecsly_world_sync.dart'
    show ComponentDelta, WorldProjection, WorldSync, WorldSyncEvent;

// The compaction policy is the session core's type now (ADR 0004); the
// bridge keeps it reachable under its old surface.
export 'package:universal_storage_convergence_session/universal_storage_convergence_session.dart'
    show defaultMaxLogOps, defaultMinInterval, shouldCompact;

export 'src/world_sync_bridge.dart';
export 'src/world_sync_session.dart';
