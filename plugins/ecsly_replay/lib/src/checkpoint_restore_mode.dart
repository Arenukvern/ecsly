// ignore_for_file: prefer_final_parameters

/// How [ReplayPlayer] applies checkpoint [WorldSnapshot]s to the live world.
enum CheckpointRestoreMode {
  /// Reconcile by [PersistentEntityComponent]: overwrite values, fix component sets, despawn
  /// persisted entities missing from the checkpoint; leave entities without
  /// [PersistentEntityComponent] untouched. Default for inspector seek.
  reconcile,

  /// Spawn fresh persisted entities (save/load oracle). May replace runtime
  /// [Entity] handles for persisted rows.
  spawn,
}
