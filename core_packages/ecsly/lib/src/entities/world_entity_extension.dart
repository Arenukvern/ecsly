import '../ecsly.dart';

/// Zero-cost wrapper for extension type component access.
///
/// Provides type-safe access to extension type facades (e.g., Position, Velocity)
/// with runtime validation to ensure type safety.
///
/// **Usage:**
/// ```dart
/// final (entity, isValid) = world.getEntity(someEntity);
/// if (isValid) {
///   final ext = entity.toExtension();
///   final pos = ext.getExtension<PositionComponent, Position>();
///   final vel = ext.getExtension<VelocityComponent, Velocity>();
/// }
/// ```
extension type WorldEntityExtension(WorldEntity base) {
  /// Archetype containing this entity
  Archetype get archetype => base.archetype;

  /// Entity ID
  Entity get entity => base.entity;

  /// Check if entity is still valid (not despawned)
  bool get isValid => base.isValid;

  /// Entity location
  EntityLocation get location => base.location;

  /// World reference
  World get world => base.world;

  /// Create component if it doesn't exist, return extension type facade.
  ///
  /// If component already exists, returns existing facade (like getExtension).
  /// If component doesn't exist, creates it (zero-initialized) and returns facade.
  ///
  /// **Zero-Cost:** Returns extension type facade, no wrapper class allocation.
  ///
  /// **Usage:**
  /// ```dart
  /// final pos = entity.create<PositionComponent, Position>();
  /// pos.x = 10; pos.y = 20;  // Direct mutation, zero-cost
  /// ```
  ///
  /// **Type Safety:**
  /// - TComponent: The Component class (e.g., PositionComponent)
  /// - TExtension: The extension type facade (e.g., Position)
  ///
  /// Throws [ArgumentError] if TExtension doesn't match the registered type.
  TExtension create<TComponent extends Component, TExtension>() {
    // Ensure commands are flushed first (if needed) to get accurate state
    if (base.world.commandQueue.needsFlush ||
        base.world.resources.doesNeedFlush) {
      base.world.flush();
    }

    // Use batch addition for consistency and performance benefits
    base.world.commands.batchAddExtensionComponents(
      [base.entity],
      [(TComponent, TExtension)],
    );

    // Flush immediately for single-entity convenience (backward compatibility)
    if (base.world.commandQueue.needsFlush) {
      base.world.flush();
    }

    // Return facade using getExtension (handles all the post-flush logic)
    final result = getExtension<TComponent, TExtension>();
    if (result == null) {
      throw EcsStateError(
        'Failed to create component $TComponent: component not found after flush',
      );
    }
    return result;
  }

  /// Get extension type facade for Component class T.
  ///
  /// Uses ComponentFacadeFactory to determine correct extension type.
  /// Validates that TExtension matches the registered extension type at runtime.
  ///
  /// **Type Safety:**
  /// - TComponent: The Component class (e.g., PositionComponent)
  /// - TExtension: The extension type facade (e.g., Position)
  ///
  /// Throws [ArgumentError] if TExtension doesn't match the registered type.
  /// Returns null if component doesn't exist for this entity.
  TExtension? getExtension<TComponent extends Component, TExtension>() {
    final componentId = base.world.components.getComponentId<TComponent>();
    final rowIndex = base.archetype.getRowIndex(
      base.entity,
      base.world.entities,
    );
    if (rowIndex == null) return null;

    final column = base.archetype.getColumn(componentId);
    if (column == null) return null;

    // Validate extension type matches registered type
    final expectedType = base.world.components.componentFacadeRegistry
        .getExtensionType(componentId);
    if (expectedType == null) {
      throw ExtensionTypeNotRegisteredError(componentId);
    }

    if (expectedType != TExtension) {
      throw ExtensionTypeMismatchError(componentId, expectedType, TExtension);
    }

    // Initialize column if needed, then create facade
    base.world.components.componentFacadeRegistry.initializeColumn(
      componentId,
      column,
    );
    return base.world.components.componentFacadeRegistry
        .createFacadeWithoutInit<TExtension>(componentId, rowIndex);
  }

  /// Get extension type facade for Component class T, or create it if it doesn't exist.
  ///
  /// If component already exists, returns existing facade.
  /// If component doesn't exist, creates it (zero-initialized) and returns facade.
  ///
  /// This is a convenience method that combines getExtension and create.
  ///
  /// **Zero-Cost:** Returns extension type facade, no wrapper class allocation.
  ///
  /// **Usage:**
  /// ```dart
  /// final pos = entity.getOrCreate<PositionComponent, Position>();
  /// pos.x = 10; pos.y = 20;  // Direct mutation, zero-cost
  /// ```
  ///
  /// **Type Safety:**
  /// - TComponent: The Component class (e.g., PositionComponent)
  /// - TExtension: The extension type facade (e.g., Position)
  ///
  /// Throws [ArgumentError] if TExtension doesn't match the registered type.
  TExtension getOrCreate<TComponent extends Component, TExtension>() {
    // First try to get the extension
    final existing = getExtension<TComponent, TExtension>();
    if (existing != null) {
      return existing;
    }

    // If it doesn't exist, create it
    return create<TComponent, TExtension>();
  }

  /// Convert back to base entity wrapper
  WorldEntity toEntity() => base;

  /// Convert to mutable wrapper
  WorldEntityMut toMut() => WorldEntityMut(base);
}
