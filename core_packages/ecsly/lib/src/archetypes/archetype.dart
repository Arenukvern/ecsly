import '../components/columns/data_column.dart';
import '../components/component.dart';
import '../components/component_mask/component_mask.dart';
import '../components/component_registry.dart';
import '../entities/entities.dart';
import '../errors/ecs_errors.dart';
import 'archetype_signature.dart';
import 'sparse_column_list.dart';

/// Archetype groups entities with identical component signatures.
/// Uses columnar storage (`Column` abstraction) for cache-friendly iteration.
///
/// Note: Entity-to-row mapping is handled globally by Entities class to avoid
/// per-archetype HashMap overhead and maintain consistency.
class Archetype {
  /// Creates an archetype for entities that share [signature].
  ///
  /// The [archetypeId] is assigned by the world-local archetype registry and is
  /// used as a stable handle for migrations, queries, and debug views.
  Archetype({required this.archetypeId, required this.signature})
    : _entities = [],
      _columns = SparseColumnList(),
      _columnOrder = [];

  /// World-local identifier for this archetype.
  ///
  /// IDs are stable for the lifetime of the world and let other systems refer
  /// to this storage bucket without depending on object identity.
  final ArchetypeId archetypeId;

  /// Component signature shared by every entity stored in this archetype.
  ///
  /// The signature determines which component columns exist and which queries
  /// can match this archetype.
  final ArchetypeSignature signature;

  // Dense list of entities for fast iteration
  final List<Entity> _entities;

  // Column storage: sparse list with O(1) lookup
  final SparseColumnList _columns;

  // Column order (determines iteration order)
  final List<ComponentId> _columnOrder;

  /// Get all component IDs in this archetype
  List<ComponentId> get componentIds => List.unmodifiable(_columnOrder);

  /// Get component mask for this archetype
  ComponentMask get componentMask => signature.mask;

  /// Dense entity rows stored by this archetype.
  ///
  /// The index in this list is the row used by each component column. Keep the
  /// list dense so hot queries can iterate contiguous rows.
  List<Entity> get entities => _entities;

  /// Number of live entity rows currently stored in this archetype.
  int get entityCount => _entities.length;

  /// Check if archetype is empty
  bool get isEmpty => _entities.isEmpty;

  /// Add a column to this archetype
  void addColumn(final ComponentId componentId, final DataColumn column) {
    if (_columns.contains(componentId)) {
      return; // Column already exists
    }

    _columns.add(componentId, column);
    _columnOrder.add(componentId);

    // Ensure column has capacity for existing entities
    while (column.length < _entities.length) {
      column.addBlank();
    }
  }

  /// Adds a new entity to the archetype and allocates space for its components.
  /// The actual component data must be set separately.
  /// Returns the row index for the new entity.
  int addEntity(final Entity entity) {
    _assertColumnSynchronization();

    final rowIndex = _entities.length;
    _entities.add(entity);

    // Allocate space in each component column for the new entity.
    for (final column in _columns.values) {
      column.addBlank();
    }

    _assertColumnSynchronization();
    return rowIndex;
  }

  /// Adds multiple entities contiguously and allocates blank component rows.
  ///
  /// This is an internal bulk primitive for command flush/migration paths. It
  /// preserves the same dense-row invariant as [addEntity] while avoiding
  /// repeated synchronization checks and row-index list allocation.
  int addEntities(final List<Entity> entities) {
    if (entities.isEmpty) return _entities.length;
    _assertColumnSynchronization();

    final startRow = _entities.length;
    _entities.addAll(entities);
    for (var i = 0; i < entities.length; i++) {
      for (final column in _columns.values) {
        column.addBlank();
      }
    }

    _assertColumnSynchronization();
    return startRow;
  }

  /// Check if entity is in this archetype
  ///
  /// Uses global Entities location tracking for O(1) lookup.
  bool contains(final Entity entity, final Entities entities) {
    if (!entities.isAlive(entity)) return false;
    final location = entities.getLocation(entity);
    return location.archetypeId == archetypeId;
  }

  /// Get column for a component ID
  DataColumn? getColumn(final ComponentId componentId) =>
      _columns.getColumn(componentId);

  /// Get component of type T for the given entity.
  /// Requires ComponentRegistry to resolve ComponentId from Type.
  T? getComponentByEntity<T extends Component>(
    final Entity entity,
    final ComponentRegistry registry,
    final Entities entities,
  ) {
    final rowIndex = getRowIndex(entity, entities);
    if (rowIndex == null) return null;
    return getComponentByIndex<T>(rowIndex, registry);
  }

  /// Get two components at the given entity.
  /// Requires ComponentRegistry to resolve ComponentId from Type.
  (T1, T2)? getComponentByEntity2<T1 extends Component, T2 extends Component>(
    final Entity entity,
    final ComponentRegistry registry,
    final Entities entities,
  ) {
    final rowIndex = getRowIndex(entity, entities);
    if (rowIndex == null) return null;
    return getComponentByIndex2<T1, T2>(rowIndex, registry);
  }

  /// Get three components at the given entity.
  /// Requires ComponentRegistry to resolve ComponentId from Type.
  (T1, T2, T3)? getComponentByEntity3<
    T1 extends Component,
    T2 extends Component,
    T3 extends Component
  >(
    final Entity entity,
    final ComponentRegistry registry,
    final Entities entities,
  ) {
    final rowIndex = getRowIndex(entity, entities);
    if (rowIndex == null) return null;
    return getComponentByIndex3<T1, T2, T3>(rowIndex, registry);
  }

  /// Get component of type T at the given row index.
  /// Requires ComponentRegistry to resolve ComponentId from Type.
  T? getComponentByIndex<T extends Component>(
    final int rowIndex,
    final ComponentRegistry registry,
  ) {
    final componentId = registry.getComponentId<T>();
    final column = getColumn(componentId);
    if (column == null) return null;

    return _getComponentFromColumn<T>(componentId, rowIndex, column, registry);
  }

  /// Get two components at the given row index.
  /// Requires ComponentRegistry to resolve ComponentId from Type.
  (T1, T2)? getComponentByIndex2<T1 extends Component, T2 extends Component>(
    final int rowIndex,
    final ComponentRegistry registry,
  ) {
    final componentId1 = registry.getComponentId<T1>();
    final componentId2 = registry.getComponentId<T2>();

    final column1 = getColumn(componentId1);
    final column2 = getColumn(componentId2);

    if (column1 == null || column2 == null) return null;

    final component1 = _getComponentFromColumn<T1>(
      componentId1,
      rowIndex,
      column1,
      registry,
    );
    final component2 = _getComponentFromColumn<T2>(
      componentId2,
      rowIndex,
      column2,
      registry,
    );

    return (component1, component2);
  }

  /// Get three components at the given row index.
  /// Requires ComponentRegistry to resolve ComponentId from Type.
  (T1, T2, T3)? getComponentByIndex3<
    T1 extends Component,
    T2 extends Component,
    T3 extends Component
  >(final int rowIndex, final ComponentRegistry registry) {
    final componentId1 = registry.getComponentId<T1>();
    final componentId2 = registry.getComponentId<T2>();
    final componentId3 = registry.getComponentId<T3>();

    final column1 = getColumn(componentId1);
    final column2 = getColumn(componentId2);
    final column3 = getColumn(componentId3);

    if (column1 == null || column2 == null || column3 == null) return null;

    final component1 = _getComponentFromColumn<T1>(
      componentId1,
      rowIndex,
      column1,
      registry,
    );
    final component2 = _getComponentFromColumn<T2>(
      componentId2,
      rowIndex,
      column2,
      registry,
    );
    final component3 = _getComponentFromColumn<T3>(
      componentId3,
      rowIndex,
      column3,
      registry,
    );

    return (component1, component2, component3);
  }

  /// Get row index for entity
  ///
  /// Uses global Entities location tracking for O(1) lookup.
  int? getRowIndex(final Entity entity, final Entities entities) {
    if (!entities.isAlive(entity)) return null;
    final location = entities.getLocation(entity);
    return location.archetypeId == archetypeId ? location.archetypeRow : null;
  }

  /// Check if this archetype matches a bitmask query
  bool matches(final ComponentMask queryMask) => signature.matches(queryMask);

  /// Moves an entity from this archetype to a destination archetype.
  ///
  /// This is a low-level operation that copies raw component data between buffers.
  /// **Note:** This method does NOT update entity location in the Entities manager.
  /// For most use cases, prefer using [EntityMigrator.migrateEntity] which handles
  /// location updates, component data writing, and other migration concerns.
  ///
  /// This method is kept for advanced use cases where fine-grained control is needed.
  void moveEntity(
    final Entity entity,
    final Archetype destination,
    final Entities entities,
  ) {
    final sourceRowIndex = getRowIndex(entity, entities);
    if (sourceRowIndex == null) return;

    // 1. Add entity to destination and get its new row index.
    final destinationRowIndex = destination.addEntity(entity);

    // 2. Copy component data from this archetype to the destination.
    for (final componentId in _columnOrder) {
      final sourceColumn = _columns.getColumn(componentId);
      if (sourceColumn == null) continue;

      final destColumn = destination.getColumn(componentId);
      if (destColumn != null) {
        // Copy component data using Column abstraction
        sourceColumn.copyTo(sourceRowIndex, destColumn, destinationRowIndex);
      }
    }

    // 3. Remove the entity from this archetype.
    removeEntity(entity, entities);
  }

  /// Moves an entity from this archetype to a destination archetype,
  /// excluding the specified component from being copied.
  ///
  /// This is a low-level operation that copies raw component data between buffers.
  /// **Note:** This method does NOT update entity location in the Entities manager.
  /// For most use cases, prefer using [EntityMigrator.migrateEntity] which handles
  /// location updates, component data writing, and other migration concerns.
  ///
  /// This method is kept for advanced use cases where fine-grained control is needed.
  void moveEntityExcluding(
    final Entity entity,
    final Archetype destination,
    final ComponentId excludeComponentId,
    final Entities entities,
  ) {
    final sourceRowIndex = getRowIndex(entity, entities);
    if (sourceRowIndex == null) return;

    // 1. Add entity to destination and get its new row index.
    final destinationRowIndex = destination.addEntity(entity);

    // 2. Copy component data from this archetype to the destination,
    //    excluding the specified component.
    for (final componentId in _columnOrder) {
      // Skip the excluded component
      if (componentId == excludeComponentId) continue;

      final sourceColumn = _columns.getColumn(componentId);
      if (sourceColumn == null) continue;

      final destColumn = destination.getColumn(componentId);
      if (destColumn != null) {
        // Copy component data using Column abstraction
        sourceColumn.copyTo(sourceRowIndex, destColumn, destinationRowIndex);
      }
    }

    // 3. Remove the entity from this archetype.
    removeEntity(entity, entities);
  }

  /// Remove entity from this archetype using swap-with-last for O(1) removal.
  ///
  /// **Swap-and-pop invariants:**
  /// - After swapping, the element to remove is always at `lastIndex`
  /// - `swapRemove` must be called BEFORE `removeLast()` to maintain valid length
  /// - Columns and entities must stay synchronized (same length)
  /// - Global Entities location tracking is updated to maintain consistency
  void removeEntity(final Entity entity, final Entities entities) {
    _assertColumnSynchronization();

    final rowIndex = getRowIndex(entity, entities);
    if (rowIndex == null) return;

    // Guard: If archetype is empty, nothing to remove
    if (_entities.isEmpty) return;

    final lastIndex = _entities.length - 1;
    final lastEntity = _entities[lastIndex];

    if (rowIndex != lastIndex) {
      // Swap the entity
      _entities[rowIndex] = lastEntity;

      // Update global location tracking: lastEntity now has new row index
      entities.setLocation(lastEntity, EntityLocation(archetypeId, rowIndex));

      // Swap components in each column
      for (final column in _columns.values) {
        column.swap(rowIndex, lastIndex);
      }
    }

    // Remove last element from all columns BEFORE removing from entities
    // This ensures column.length is still valid when swapRemove is called
    for (final column in _columns.values) {
      column.swapRemove(lastIndex);
    }

    // Remove the last element from entities
    _entities.removeLast();

    _assertColumnSynchronization();
  }

  /// Assert that columns are synchronized with entities.
  /// Validates:
  /// - All columns have same length as entities
  /// - Column count matches column order
  /// - Entity row indices are valid
  void _assertColumnSynchronization() {
    assert(() {
      final entityCount = _entities.length;

      // Check all columns have same length as entities
      for (final column in _columns.values) {
        if (column.length != entityCount) {
          throw EcsStateError(
            'Column length mismatch: expected $entityCount, got ${column.length}',
          );
        }
      }

      // Check column count matches column order
      if (_columns.length != _columnOrder.length) {
        throw EcsStateError(
          'Column count mismatch: _columns has ${_columns.length}, '
          '_columnOrder has ${_columnOrder.length}',
        );
      }

      // Check entity row indices are valid (verified via global Entities tracking)

      return true;
    }(), 'Column synchronization check failed');
  }

  /// Helper method to get component from column.
  /// All columns now use the unified facade system (ObjectColumn facades are auto-generated).
  T _getComponentFromColumn<T extends Component>(
    final ComponentId componentId,
    final int rowIndex,
    final DataColumn column,
    final ComponentRegistry registry,
    // All columns use facade system - no special cases!
    // ObjectColumn facades are auto-generated if not registered
  ) => registry.componentFacadeRegistry.createFacade<T>(
    componentId,
    rowIndex,
    column,
  );
}

/// Can be integer, since this value is emphemeral and should never be
/// saved to disk - it would be recreated specifically for the world.
extension type const ArchetypeId(int value) {
  static const zero = ArchetypeId(0);
}

/// Location of archetype in List similar to [EntityIndex].
extension type const ArchetypeIndex(int value) {
  static const zero = ArchetypeIndex(0);
}

/// Bulk operations extension for Archetype
extension ArchetypeBulkOps on Archetype {
  /// Add multiple entities at once (more efficient)
  ///
  /// **Note:** This method does NOT update entity locations in Entities manager.
  /// Callers must update entity locations separately after calling this method.
  void addEntities(final List<Entity> entities) {
    _entities.addAll(entities);

    // Add blanks to all columns
    for (final column in _columns.values) {
      for (int i = 0; i < entities.length; i++) {
        column.addBlank();
      }
    }
  }

  /// Batch remove entities
  void removeEntities(
    final List<Entity> entities,
    final Entities entitiesManager,
  ) {
    for (final entity in entities) {
      removeEntity(entity, entitiesManager);
    }
  }
}
