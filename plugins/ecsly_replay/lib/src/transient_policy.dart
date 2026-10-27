// ignore_for_file: prefer_final_parameters

/// How [ReplayPlayer] treats entities without [PersistentId] after a seek.
enum TransientPolicy {
  /// Leave non-persistent entities in the world (inspector selection, gizmos).
  ///
  /// No determinism guarantee if systems read transient entities during replay.
  keep,

  /// Despawn all entities without [PersistentId] so the world matches recorded
  /// persisted state only. Required for [ReplayPlayer.verifyDeterminism].
  despawn,
}
