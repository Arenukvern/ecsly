import '../archetypes/archetypes.dart';
import '../components/components.dart';
import '../errors/ecs_errors.dart';
import '../world/world.dart';
import 'entities.dart';

/// Provides mutable access to entity components for direct in-place mutation.
///
/// Similar to Bevy's `&mut Component` pattern, this wrapper allows direct
/// mutation of component data without creating new component instances.
///
/// **Key Distinction:**
/// - **WorldEntityMut**: For data mutation (doesn't change archetype) - direct in-place updates
/// - **WorldEntity**: For structural changes (spawn/despawn/insert/remove components) - changes archetype
///
/// **Safety:**
/// Only one system mutates a component type at a time (scheduler ensures this).
/// This is safe because components are stored in `List<Component?>` arrays in archetypes,
/// allowing in-place updates without changing the archetype signature.
///
/// **Usage:**
/// ```dart
/// // Get mutable entity wrapper
/// final entityMut = world.getEntityMut(entity);
///
/// // Mutate component directly (no allocation)
/// final position = entityMut.getMut<MutablePosition>();
/// position.x += velocity.dx * dt;
/// position.y += velocity.dy * dt;
/// ```
///
/// Should be validated before wrapping!
/// Use [World.getEntityMut] to validate and wrap an entity.
extension type WorldEntityMut(WorldEntity base) {
  /// Archetype containing this entity
  Archetype get archetype => base.archetype;

  /// Entity ID
  Entity get entity => base.entity;

  /// Check if entity is still valid (not despawned)
  ///
  /// Uses generation-based validation (like Bevy's Entities::is_valid).
  /// Checks both index and generation to detect stale entity references.
  /// O(1) lookup, doesn't trigger flushes.
  bool get isAlive => world.entities.isAlive(entity);

  /// Entity location
  EntityLocation get location => base.location;

  /// World reference
  World get world => base.world;

  /// Get mutable reference to component of type T for this entity.
  ///
  /// Returns the actual stored component object (not a copy), allowing
  /// direct in-place mutation.
  ///
  /// **Performance:** No object allocation - direct mutation of stored component.
  ///
  /// **Safety:** Only one system mutates a component type at a time (scheduler ensures this).
  ///
  /// Throws [ComponentNotFoundError] if component is not found.
  T getMut<T extends Component>() {
    final component = archetype.getComponentByEntity<T>(
      entity,
      world.components,
      world.entities,
    );
    if (component == null) {
      throw ComponentNotFoundError(T, entity);
    }
    return component;
  }

  /// Get mutable references to two components for this entity.
  ///
  /// Returns the actual stored component objects (not copies), allowing
  /// direct in-place mutation.
  ///
  /// **Performance:** No object allocation - direct mutation of stored components.
  ///
  /// Throws [ComponentNotFoundError] if either component is not found.
  (T1, T2) getMut2<T1 extends Component, T2 extends Component>() {
    final components = archetype.getComponentByEntity2<T1, T2>(
      entity,
      world.components,
      world.entities,
    );
    if (components == null) {
      throw ComponentNotFoundError(T1, entity);
    }
    return components;
  }

  /// Get mutable references to three components for this entity.
  ///
  /// Returns the actual stored component objects (not copies), allowing
  /// direct in-place mutation.
  ///
  /// **Performance:** No object allocation - direct mutation of stored components.
  ///
  /// Throws [ComponentNotFoundError] if any component is not found.
  (T1, T2, T3)
  getMut3<T1 extends Component, T2 extends Component, T3 extends Component>() {
    final components = archetype.getComponentByEntity3<T1, T2, T3>(
      entity,
      world.components,
      world.entities,
    );
    if (components == null) {
      throw ComponentNotFoundError(T1, entity);
    }
    return components;
  }

  /// Check if entity has component of type T.
  ///
  /// Uses non-throwing archetype signature check for efficient component
  /// existence verification.
  bool has<T extends Component>() =>
      world.components.getComponentIdByType(T) != null;

  /// Check if entity has component of type T without throwing.
  ///
  /// Uses archetype signature checking for efficient non-throwing component
  /// existence verification. Returns `false` if entity doesn't exist or
  /// component is not present.
  bool hasFast<T extends Component>() {
    final componentId = world.components.getComponentIdByType(T);
    if (componentId == null) return false;
    return archetype.signature.has(componentId);
  }

  /// Convert back to base entity wrapper
  WorldEntity toEntity() => base;

  /// Convert to extension type wrapper
  WorldEntityExtension toExtension() => WorldEntityExtension(base);
}
