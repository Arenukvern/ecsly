import 'package:ecsly/ecsly.dart';

import 'entity_refs.dart';
import 'resource_snapshot.dart';

/// Strategy that mints stable [PersistentEntity] identities for a world.
///
/// Allocation is a **world-level policy** (ADR 0007): a world installs one
/// allocator and every identity comes from it. Mixing policies within a
/// world is what would break deterministic replay — sequence allocation is a
/// pure function of seed and spawn order, so two runs of the same seed
/// mint identical identities and `ecsly_replay`'s cold-vs-hot comparison
/// (keyed by identity) holds.
abstract interface class PersistentEntityAllocator {
  /// Policy discriminator stored in snapshots (`'sequence'`, `'random'`).
  String get mode;

  /// Mints the next identity. Uniqueness within the world is the
  /// allocator's contract; [spawnPersistent] additionally cross-checks the
  /// index and fails loudly on collision.
  PersistentEntity next();

  /// Grows the allocation state past every identity found in a restored
  /// snapshot, so newly minted identities never collide with restored ones.
  /// No-op for stateless policies ([RandomPersistentEntityAllocator]).
  void adoptMax(Iterable<PersistentEntity> identities);

  /// The snapshotable state of this allocator (`mode` included).
  Map<String, Object?> snapshotState();

  /// Restores the allocator state from [snapshotState] output.
  void restoreState(Map<String, Object?> state);
}

/// Deterministic allocator: hands out [PersistentEntity.sequence] values
/// from a monotonic counter starting at [start] (1 by default — identity
/// `zero` is reserved as the null identity).
///
/// Freed identities are never reused; the counter only grows. [adoptMax]
/// re-derives the counter from restored identities, making restore robust
/// even when the allocator's own snapshot payload is lost.
class SequencePersistentEntityAllocator implements PersistentEntityAllocator {
  /// Creates the allocator starting at [start].
  SequencePersistentEntityAllocator({this.start = 1}) : nextValue = start;

  /// First identity the allocator hands out.
  final int start;

  /// Next sequence value to hand out.
  int nextValue;

  @override
  String get mode => 'sequence';

  @override
  PersistentEntity next() => PersistentEntity.sequence(nextValue++);

  @override
  void adoptMax(Iterable<PersistentEntity> identities) {
    for (final identity in identities) {
      final sequence = identity.sequenceValue;
      if (sequence != null && sequence >= nextValue) {
        nextValue = sequence + 1;
      }
    }
  }

  @override
  Map<String, Object?> snapshotState() => {'mode': mode, 'next': nextValue};

  @override
  void restoreState(Map<String, Object?> state) {
    nextValue = (state['next'] as num?)?.toInt() ?? start;
  }
}

/// Random allocator: every [next] mints a fresh 128-bit secure-random
/// identity ([PersistentEntity.create]). Globally unique by collision
/// resistance — the merge-safe choice for MMO-style topologies.
///
/// Stateless: nothing to snapshot or adopt.
class RandomPersistentEntityAllocator implements PersistentEntityAllocator {
  /// Creates the allocator.
  const RandomPersistentEntityAllocator();

  @override
  String get mode => 'random';

  @override
  PersistentEntity next() => PersistentEntity.create();

  @override
  void adoptMax(Iterable<PersistentEntity> identities) {}

  @override
  Map<String, Object?> snapshotState() => {'mode': mode};

  @override
  void restoreState(Map<String, Object?> state) {}
}

/// World-held [PersistentEntityAllocator] — the DI seam spawn sites and
/// restore use. Snapshotable so the allocation state travels with saves.
class PersistentEntityAllocatorResource extends Resource
    with SnapshotableResource {
  /// Creates the resource wrapping [allocator].
  PersistentEntityAllocatorResource(this.allocator);

  /// The active allocation policy for this world.
  final PersistentEntityAllocator allocator;

  @override
  Map<String, Object?> toJson(EntityRefEncoder refs) =>
      allocator.snapshotState();

  /// Rebuilds the right allocator implementation from a snapshot payload.
  static PersistentEntityAllocatorResource fromJson(
    Map<String, Object?> json, [
    EntityRefResolver? refs,
  ]) => switch (json['mode']) {
    'random' => PersistentEntityAllocatorResource(
      const RandomPersistentEntityAllocator(),
    ),
    _ => PersistentEntityAllocatorResource(
      SequencePersistentEntityAllocator(),
    )..allocator.restoreState(json),
  };
}
