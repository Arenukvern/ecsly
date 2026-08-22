import 'package:ecsly/ecsly.dart';

/// Marker + identity component marking an entity as persistable.
///
/// Only entities carrying [PersistentId] are captured by
/// `captureWorldSnapshot`; everything else (particles, VFX, transient state)
/// is treated as runtime-only. The [value] is the stable cross-session
/// identity: it travels with the snapshot and is re-attached on restore, so
/// references and app-side lookups survive world-to-world transfers.
///
/// Register it in the world via [registerPersistentId] (done automatically by
/// capture and restore).
class PersistentId extends Component {
  /// Creates a persistent identity with the given stable [value].
  const PersistentId(this.value);

  /// Stable identity value. Must be unique among persisted entities in a
  /// world; duplicates fail capture loudly.
  final int value;

  @override
  String toString() => 'PersistentId($value)';
}

/// Ensures [PersistentId] is registered in [world]. Idempotent.
void registerPersistentId(final World world) {
  if (world.components.getComponentIdByType(PersistentId) == null) {
    world.components.registerObjectComponent<PersistentId>();
  }
}

/// Reads the [PersistentId] of [entity], or null when absent.
PersistentId? persistentIdOf(final World world, final Entity entity) {
  try {
    final location = world.entities.getLocation(entity);
    if (location.archetypeId == ArchetypeId.zero) return null;
    final archetypeIndex = world.archetypes.findArchetypeIndex(
      location.archetypeId,
    );
    return world.archetypes[archetypeIndex].getComponentByEntity<PersistentId>(
      entity,
      world.components,
      world.entities,
    );
    // ignore: avoid_catching_errors
  } on EcsStateError {
    return null;
  }
}
