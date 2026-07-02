// ignore_for_file: avoid_multiple_declarations_per_line, cascade_invocations, avoid_returning_this, unsafe_variance

import 'dart:collection';

import '../archetypes/archetypes.dart';
import '../entities/entities.dart';
import '../errors/ecs_errors.dart';
import '../world/world.dart';
import 'columns/data_column.dart';
import 'component.dart';
import 'component_facade_factory.dart';
import 'component_mask/component_mask.dart';
import 'query_cache.dart';

/// Type for component predicates used in conditional queries.
/// Returns true if the component matches the condition.
typedef ComponentPredicate<T> = bool Function(T component);

/// Type for extension type predicates used in conditional queries.
/// Returns true if the extension type matches the condition.
typedef ExtensionPredicate<T> = bool Function(T extensionType);

/// Query builder for iterating entities with specific components and conditions.
/// Provides cache-friendly iteration over matching archetypes with predicate filtering.
class ComponentQuery {
  /// Create a query with required and/or excluded components.
  ComponentQuery({
    required this.world,
    final Iterable<ComponentId>? required,
    final Iterable<ComponentId>? excluded,
  }) : requiredMask = required != null
           ? createComponentMask(required)
           : emptyComponentMask,
       excludedMask = excluded != null
           ? createComponentMask(excluded)
           : emptyComponentMask;

  /// Create a new query builder for the given world.
  factory ComponentQuery.fromWorld(final World world) =>
      ComponentQuery._(world, emptyComponentMask, emptyComponentMask);

  ComponentQuery._(this.world, this.requiredMask, this.excludedMask);

  final World world;
  final ComponentMask requiredMask;
  final ComponentMask excludedMask;
  late final List<ComponentId> _requiredComponentIds = requiredMask.componentIds
      .toList(growable: false);
  final Map<int, _CompiledQueryPlan> _compiledPlans =
      <int, _CompiledQueryPlan>{};
  final List<Archetype> _excludedScratch = <Archetype>[];
  int _matchingCacheStructuralVersion = -1;
  List<Archetype>? _matchingCache;

  /// Lazily iterate over entities only.
  /// This avoids allocating a new list for the results.
  ///
  /// Automatically flushes pending changes before building the entity list
  /// to ensure queries return up-to-date results.
  Iterable<Entity> get entities sync* {
    world.ensureFlushed();
    final queryKey = QueryCacheKey(
      requiredMask,
      excludedMask == emptyComponentMask ? null : excludedMask,
    );
    final cached = world.queryCache.getCachedResult(
      queryKey,
      world.archetypes,
      () {
        final result = <Entity>[];
        final archetypes = matchingArchetypes;
        for (final archetype in archetypes) {
          final entities = archetype.entities;
          for (var row = 0; row < entities.length; row++) {
            final entity = entities[row];
            if (!_isEntityRowCurrent(world, archetype, entity, row)) {
              continue;
            }
            result.add(entity);
          }
        }
        return result;
      },
    );
    final cachedEntities = cached?.entities;
    if (cachedEntities != null) {
      yield* cachedEntities;
      return;
    }

    // Result cache is disabled: stream entities directly.
    final archetypes = matchingArchetypes;
    for (final archetype in archetypes) {
      final entities = archetype.entities;
      for (var row = 0; row < entities.length; row++) {
        final entity = entities[row];
        if (!_isEntityRowCurrent(world, archetype, entity, row)) {
          continue;
        }
        yield entity;
      }
    }
  }

  /// Get matching archetypes for the query.
  ///
  /// Automatically flushes pending changes before finding matching archetypes
  /// to ensure queries return up-to-date results.
  List<Archetype> get matchingArchetypes {
    world.ensureFlushed();
    world.assertHotScheduleCompatible(_requiredComponentIds);
    final structuralVersion = world.archetypes.structuralVersion;
    final cached = _matchingCache;
    if (cached != null &&
        _matchingCacheStructuralVersion == structuralVersion) {
      return cached;
    }

    final cachedResult = world.queryCache.getOrCompute(
      requiredMask,
      world.archetypes,
    );
    List<Archetype> matching = cachedResult.matchingArchetypes;
    if (excludedMask != emptyComponentMask) {
      _excludedScratch.clear();
      for (final archetype in matching) {
        if (!archetype.componentMask.intersects(excludedMask)) {
          _excludedScratch.add(archetype);
        }
      }
      matching = _excludedScratch;
    }

    _matchingCacheStructuralVersion = structuralVersion;
    _matchingCache = matching;
    return matching;
  }

  /// Count matching entities without materializing entity lists.
  int count() {
    world.ensureFlushed();
    var total = 0;
    for (final archetype in matchingArchetypes) {
      total += archetype.entityCount;
    }
    return total;
  }

  /// Returns true if at least one matching entity exists.
  bool any() {
    world.ensureFlushed();
    for (final archetype in matchingArchetypes) {
      if (archetype.entityCount > 0) {
        return true;
      }
    }
    return false;
  }

  List<Archetype> _resolveArchetypesForIds(final List<ComponentId> ids) {
    world.assertHotScheduleCompatible(ids);
    final key = _packPlanKey(ids);
    final plan = _compiledPlans.putIfAbsent(
      key,
      () => _CompiledQueryPlan(createComponentMask(ids)),
    );
    return plan.resolve(world);
  }

  /// Creates a garbage-free iterator for a single component type.
  ///
  /// Example:
  /// ```dart
  /// for (final (entity, position) in query.iter1<PositionComponent>()) {
  ///   position.x += 1.0;
  /// }
  /// ```
  Iterable<(WorldEntity, T1)> iter1<T1 extends Component>() {
    world.ensureFlushed();
    // Build ComponentMask from ComponentId instead of Type list
    final componentId = world.components.getComponentId<T1>();
    final archetypes = _resolveArchetypesForIds([componentId]);
    if (archetypes.isEmpty) {
      return const [];
    }

    return _QueryIterable1<T1>(archetypes, componentId, world);
  }

  /// Creates a conditional query for a single component type with predicate filtering.
  /// Predicate is applied during iteration for zero-allocation filtering.
  ///
  /// Example:
  /// ```dart
  /// for (final (entity, health) in query.iter1Where<HealthComponent>(
  ///   (health) => health.value <= 0
  ///   )) {
  ///     // Only processes dead entities
  ///   }
  /// ```
  Iterable<(WorldEntity, T1)> iter1Where<T1 extends Component>(
    final ComponentPredicate<T1> predicate,
  ) {
    world.ensureFlushed();
    final componentId = world.components.getComponentId<T1>();
    final archetypes = _resolveArchetypesForIds([componentId]);
    if (archetypes.isEmpty) {
      return const [];
    }

    return _QueryIterable1Where<T1>(archetypes, componentId, world, predicate);
  }

  /// Creates a garbage-free iterator for two component types.
  ///
  /// Example:
  /// ```dart
  /// for (final (entity, pos, vel) in query.iter2<Position, Velocity>()) {
  ///   pos.x += vel.dx;
  /// }
  /// ```
  Iterable<(WorldEntity, T1, T2)>
  iter2<T1 extends Component, T2 extends Component>() {
    world.ensureFlushed();
    final id1 = world.components.getComponentId<T1>();
    final id2 = world.components.getComponentId<T2>();
    final archetypes = _resolveArchetypesForIds([id1, id2]);
    if (archetypes.isEmpty) {
      return const [];
    }

    return _QueryIterable2<T1, T2>(archetypes, id1, id2, world);
  }

  /// Creates a garbage-free iterator for three component types.
  ///
  /// Example:
  /// ```dart
  /// for (final (entity, pos, vel, health) in query.iter3<Position, Velocity, Health>()) {
  ///   pos.x += vel.dx;
  ///   health.damage(1);
  /// }
  /// ```
  Iterable<(WorldEntity, T1, T2, T3)>
  iter3<T1 extends Component, T2 extends Component, T3 extends Component>() {
    world.ensureFlushed();
    final id1 = world.components.getComponentId<T1>();
    final id2 = world.components.getComponentId<T2>();
    final id3 = world.components.getComponentId<T3>();
    final archetypes = _resolveArchetypesForIds([id1, id2, id3]);
    if (archetypes.isEmpty) {
      return const [];
    }

    return _QueryIterable3<T1, T2, T3>(archetypes, id1, id2, id3, world);
  }

  /// Creates a garbage-free iterator for four component types.
  ///
  /// Example:
  /// ```dart
  /// for (final (entity, pos, vel, health, armor) in query.iter4<Position, Velocity, Health, Armor>()) {
  ///   pos.x += vel.dx;
  /// }
  /// ```
  Iterable<(WorldEntity, T1, T2, T3, T4)> iter4<
    T1 extends Component,
    T2 extends Component,
    T3 extends Component,
    T4 extends Component
  >() {
    world.ensureFlushed();
    final id1 = world.components.getComponentId<T1>();
    final id2 = world.components.getComponentId<T2>();
    final id3 = world.components.getComponentId<T3>();
    final id4 = world.components.getComponentId<T4>();
    final archetypes = _resolveArchetypesForIds([id1, id2, id3, id4]);
    if (archetypes.isEmpty) {
      return const [];
    }

    return _QueryIterable4<T1, T2, T3, T4>(
      archetypes,
      id1,
      id2,
      id3,
      id4,
      world,
    );
  }

  /// Creates a garbage-free iterator for five component types.
  Iterable<(WorldEntity, T1, T2, T3, T4, T5)> iter5<
    T1 extends Component,
    T2 extends Component,
    T3 extends Component,
    T4 extends Component,
    T5 extends Component
  >() {
    world.ensureFlushed();
    final id1 = world.components.getComponentId<T1>();
    final id2 = world.components.getComponentId<T2>();
    final id3 = world.components.getComponentId<T3>();
    final id4 = world.components.getComponentId<T4>();
    final id5 = world.components.getComponentId<T5>();
    final archetypes = _resolveArchetypesForIds([id1, id2, id3, id4, id5]);
    if (archetypes.isEmpty) {
      return const [];
    }

    return _QueryIterable5<T1, T2, T3, T4, T5>(
      archetypes,
      id1,
      id2,
      id3,
      id4,
      id5,
      world,
    );
  }

  /// Creates a garbage-free iterator for six component types.
  Iterable<(WorldEntity, T1, T2, T3, T4, T5, T6)> iter6<
    T1 extends Component,
    T2 extends Component,
    T3 extends Component,
    T4 extends Component,
    T5 extends Component,
    T6 extends Component
  >() {
    world.ensureFlushed();
    final id1 = world.components.getComponentId<T1>();
    final id2 = world.components.getComponentId<T2>();
    final id3 = world.components.getComponentId<T3>();
    final id4 = world.components.getComponentId<T4>();
    final id5 = world.components.getComponentId<T5>();
    final id6 = world.components.getComponentId<T6>();
    final archetypes = _resolveArchetypesForIds([id1, id2, id3, id4, id5, id6]);
    if (archetypes.isEmpty) {
      return const [];
    }

    return _QueryIterable6<T1, T2, T3, T4, T5, T6>(
      archetypes,
      id1,
      id2,
      id3,
      id4,
      id5,
      id6,
      world,
    );
  }

  /// Creates a garbage-free iterator for a single component type with explicit extension type.
  ///
  /// Returns extension type facades directly, eliminating the need for casting.
  ///
  /// Example:
  /// ```dart
  /// for (final (entity, pos) in query.iterExt1<PositionComponent, Position>()) {
  ///   pos.x += 1.0; // Direct access, no cast needed
  /// }
  /// ```
  Iterable<(WorldEntityExtension, TExt)>
  iterExt1<TComp extends Component, TExt>() {
    if (TComp == TExt) {
      return iter1<TComp>().map((final tuple) {
        final (entity, comp) = tuple;
        return (entity.toExtension(), comp as TExt);
      });
    }
    world.ensureFlushed();
    final id1 = world.components.getComponentId<TComp>();
    final archetypes = _resolveArchetypesForIds([id1]);
    if (archetypes.isEmpty) {
      return const [];
    }

    return _QueryIterableExt1<TComp, TExt>(archetypes, id1, world);
  }

  /// Creates a conditional iterator for extension type components with predicate filtering.
  /// Predicate is applied to the extension type during iteration.
  ///
  /// Example:
  /// ```dart
  /// for (final (entity, hp) in query.iterExt1Where<HealthComponent, Health>(
  ///   (hp) => hp.isDead
  /// )) {
  ///   // Only processes dead entities
  /// }
  /// ```
  Iterable<(WorldEntityExtension, TExt)> iterExt1Where<
    TComp extends Component,
    TExt
  >(final ExtensionPredicate<TExt> predicate) {
    if (TComp == TExt) {
      return iter1Where((final component) => predicate(component as TExt)).map((
        final tuple,
      ) {
        final (entity, comp) = tuple;
        return (entity.toExtension(), comp as TExt);
      });
    }
    world.ensureFlushed();
    final id1 = world.components.getComponentId<TComp>();
    final archetypes = _resolveArchetypesForIds([id1]);
    if (archetypes.isEmpty) {
      return const [];
    }

    return _QueryIterableExt1Where<TComp, TExt>(
      archetypes,
      id1,
      world,
      predicate,
    );
  }

  /// Creates a garbage-free iterator for two component types with explicit extension types.
  ///
  /// Returns extension type facades directly, eliminating the need for casting.
  ///
  /// Example:
  /// ```dart
  /// for (final (entity, pos, vel) in query.iterExt2<PositionComponent, Position, VelocityComponent, Velocity>()) {
  ///   pos.x += vel.dx; // Direct access, no cast needed
  /// }
  /// ```
  Iterable<(WorldEntityExtension, TExt, T2Ext)>
  iterExt2<TComp extends Component, TExt, T2Comp extends Component, T2Ext>() {
    world.ensureFlushed();
    final id1 = world.components.getComponentId<TComp>();
    final id2 = world.components.getComponentId<T2Comp>();
    final archetypes = _resolveArchetypesForIds([id1, id2]);
    if (archetypes.isEmpty) {
      return const [];
    }

    return _QueryIterableExt2<TComp, TExt, T2Comp, T2Ext>(
      archetypes,
      id1,
      id2,
      world,
    );
  }

  /// Creates a conditional iterator for two extension type components with predicate filtering.
  /// Predicate is applied to the first extension type during iteration.
  Iterable<(WorldEntityExtension, TExt, T2Ext)> iterExt2Where<
    TComp extends Component,
    TExt,
    T2Comp extends Component,
    T2Ext
  >(final ExtensionPredicate<TExt> predicate) {
    world.ensureFlushed();
    final id1 = world.components.getComponentId<TComp>();
    final id2 = world.components.getComponentId<T2Comp>();
    final archetypes = _resolveArchetypesForIds([id1, id2]);
    if (archetypes.isEmpty) {
      return const [];
    }

    return _QueryIterableExt2Where<TComp, TExt, T2Comp, T2Ext>(
      archetypes,
      id1,
      id2,
      world,
      predicate,
    );
  }

  /// Creates a garbage-free iterator for three component types with explicit extension types.
  ///
  /// Returns extension type facades directly, eliminating the need for casting.
  ///
  /// Example:
  /// ```dart
  /// for (final (entity, pos, vel, health) in query.iterExt3<PositionComponent, Position, VelocityComponent, Velocity, HealthComponent, Health>()) {
  ///   pos.x += vel.dx; // Direct access, no cast needed
  ///   health.value -= 1;
  /// }
  /// ```
  Iterable<(WorldEntityExtension, TExt, T2Ext, T3Ext)> iterExt3<
    TComp extends Component,
    TExt,
    T2Comp extends Component,
    T2Ext,
    T3Comp extends Component,
    T3Ext
  >() {
    world.ensureFlushed();
    final id1 = world.components.getComponentId<TComp>();
    final id2 = world.components.getComponentId<T2Comp>();
    final id3 = world.components.getComponentId<T3Comp>();
    final archetypes = _resolveArchetypesForIds([id1, id2, id3]);
    if (archetypes.isEmpty) {
      return const [];
    }

    return _QueryIterableExt3<TComp, TExt, T2Comp, T2Ext, T3Comp, T3Ext>(
      archetypes,
      id1,
      id2,
      id3,
      world,
    );
  }

  /// Creates a garbage-free iterator for four component types with explicit extension types.
  ///
  /// Returns extension type facades directly, eliminating the need for casting.
  ///
  /// Example:
  /// ```dart
  /// for (final (entity, pos, vel, health, armor) in query.iterExt4<PositionComponent, Position, VelocityComponent, Velocity, HealthComponent, Health, ArmorComponent, Armor>()) {
  ///   pos.x += vel.dx; // Direct access, no cast needed
  ///   health.value -= armor.damageReduction;
  /// }
  /// ```
  Iterable<(WorldEntityExtension, TExt, T2Ext, T3Ext, T4Ext)> iterExt4<
    TComp extends Component,
    TExt,
    T2Comp extends Component,
    T2Ext,
    T3Comp extends Component,
    T3Ext,
    T4Comp extends Component,
    T4Ext
  >() {
    world.ensureFlushed();
    final id1 = world.components.getComponentId<TComp>();
    final id2 = world.components.getComponentId<T2Comp>();
    final id3 = world.components.getComponentId<T3Comp>();
    final id4 = world.components.getComponentId<T4Comp>();
    final archetypes = _resolveArchetypesForIds([id1, id2, id3, id4]);
    if (archetypes.isEmpty) {
      return const [];
    }

    return _QueryIterableExt4<
      TComp,
      TExt,
      T2Comp,
      T2Ext,
      T3Comp,
      T3Ext,
      T4Comp,
      T4Ext
    >(archetypes, id1, id2, id3, id4, world);
  }

  /// Creates an iterator for mutable queries with a single component type.
  ///
  /// Returns (WorldEntityMut, Component) tuples for direct in-place mutation.
  ///
  /// Example:
  /// ```dart
  /// for (final (entityMut, position) in query.iterMut1<MutablePosition>()) {
  ///   position.x += 1.0; // Direct mutation
  /// }
  /// ```
  Iterable<(WorldEntityMut, T1)> iterMut1<T1 extends Component>() {
    world.ensureFlushed();
    final componentId = world.components.getComponentId<T1>();
    final archetypes = _resolveArchetypesForIds([componentId]);
    if (archetypes.isEmpty) {
      return const [];
    }

    return _QueryIterableMut1<T1>(archetypes, componentId, world);
  }

  /// Creates an iterator for mutable queries with two component types.
  ///
  /// Returns (WorldEntityMut, Component1, Component2) tuples for direct mutation.
  Iterable<(WorldEntityMut, T1, T2)>
  iterMut2<T1 extends Component, T2 extends Component>() {
    world.ensureFlushed();
    final id1 = world.components.getComponentId<T1>();
    final id2 = world.components.getComponentId<T2>();
    final archetypes = _resolveArchetypesForIds([id1, id2]);
    if (archetypes.isEmpty) {
      return const [];
    }

    return _QueryIterableMut2<T1, T2>(archetypes, id1, id2, world);
  }

  /// Creates an iterator for mutable queries with three component types.
  ///
  /// Returns (WorldEntityMut, Component1, Component2, Component3) tuples.
  Iterable<(WorldEntityMut, T1, T2, T3)>
  iterMut3<T1 extends Component, T2 extends Component, T3 extends Component>() {
    world.ensureFlushed();
    final id1 = world.components.getComponentId<T1>();
    final id2 = world.components.getComponentId<T2>();
    final id3 = world.components.getComponentId<T3>();
    final archetypes = _resolveArchetypesForIds([id1, id2, id3]);
    if (archetypes.isEmpty) {
      return const [];
    }

    return _QueryIterableMut3<T1, T2, T3>(archetypes, id1, id2, id3, world);
  }

  /// Creates an iterator for mutable queries with four component types.
  ///
  /// Returns (WorldEntityMut, Component1, Component2, Component3, Component4) tuples.
  Iterable<(WorldEntityMut, T1, T2, T3, T4)> iterMut4<
    T1 extends Component,
    T2 extends Component,
    T3 extends Component,
    T4 extends Component
  >() {
    world.ensureFlushed();
    final id1 = world.components.getComponentId<T1>();
    final id2 = world.components.getComponentId<T2>();
    final id3 = world.components.getComponentId<T3>();
    final id4 = world.components.getComponentId<T4>();
    final archetypes = _resolveArchetypesForIds([id1, id2, id3, id4]);
    if (archetypes.isEmpty) {
      return const [];
    }

    return _QueryIterableMut4<T1, T2, T3, T4>(
      archetypes,
      id1,
      id2,
      id3,
      id4,
      world,
    );
  }

  /// Creates a garbage-free iterator for two extension components without entity wrappers.
  ///
  /// Returns (Entity, ExtensionType1, ExtensionType2) tuples.
  /// This avoids WorldEntity/WorldEntityExtension wrapper allocations and is intended
  /// for performance-critical systems that only need entity IDs + direct component access.
  Iterable<(Entity, TExt, T2Ext)> iterRawExt2<
    TComp extends Component,
    TExt,
    T2Comp extends Component,
    T2Ext
  >() {
    world.ensureFlushed();
    final id1 = world.components.getComponentId<TComp>();
    final id2 = world.components.getComponentId<T2Comp>();
    final archetypes = _resolveArchetypesForIds([id1, id2]);
    if (archetypes.isEmpty) {
      return const [];
    }

    return _QueryIterableRawExt2<TComp, TExt, T2Comp, T2Ext>(
      archetypes,
      id1,
      id2,
      world,
    );
  }

  /// Returns raw chunk views for two components without per-row wrapper records.
  ///
  /// Use [RawQueryChunk2.forEachRow] with index-based loops for hot paths.
  Iterable<RawQueryChunk2<TExt, T2Ext>> iterRaw2<
    TComp extends Component,
    TExt,
    T2Comp extends Component,
    T2Ext
  >() sync* {
    world.ensureFlushed();
    final id1 = world.components.getComponentId<TComp>();
    final id2 = world.components.getComponentId<T2Comp>();
    final archetypes = _resolveArchetypesForIds([id1, id2]);
    if (archetypes.isEmpty) {
      return;
    }

    final facadeRegistry = world.components.componentFacadeRegistry;
    for (final archetype in archetypes) {
      final column1 = archetype.getColumn(id1);
      final column2 = archetype.getColumn(id2);
      if (column1 == null || column2 == null) {
        continue;
      }
      final rowCount = _minRowCount3(
        column1.length,
        column2.length,
        archetype.entities.length,
      );
      if (rowCount == 0) {
        continue;
      }
      final factory1 = facadeRegistry.initializeColumn(id1, column1);
      final factory2 = facadeRegistry.initializeColumn(id2, column2);
      yield RawQueryChunk2<TExt, T2Ext>._(
        world: world,
        archetypeId: archetype.archetypeId,
        entities: archetype.entities,
        rowCount: rowCount,
        column1: RawComponentColumn<TExt>._(factory1, column1, rowCount),
        column2: RawComponentColumn<T2Ext>._(factory2, column2, rowCount),
      );
    }
  }

  /// Returns raw chunk views for three components without per-row wrapper records.
  Iterable<RawQueryChunk3<TExt, T2Ext, T3Ext>> iterRaw3<
    TComp extends Component,
    TExt,
    T2Comp extends Component,
    T2Ext,
    T3Comp extends Component,
    T3Ext
  >() sync* {
    world.ensureFlushed();
    final id1 = world.components.getComponentId<TComp>();
    final id2 = world.components.getComponentId<T2Comp>();
    final id3 = world.components.getComponentId<T3Comp>();
    final archetypes = _resolveArchetypesForIds([id1, id2, id3]);
    if (archetypes.isEmpty) {
      return;
    }

    final facadeRegistry = world.components.componentFacadeRegistry;
    for (final archetype in archetypes) {
      final column1 = archetype.getColumn(id1);
      final column2 = archetype.getColumn(id2);
      final column3 = archetype.getColumn(id3);
      if (column1 == null || column2 == null || column3 == null) {
        continue;
      }
      final rowCount = _minRowCount4(
        column1.length,
        column2.length,
        column3.length,
        archetype.entities.length,
      );
      if (rowCount == 0) {
        continue;
      }
      final factory1 = facadeRegistry.initializeColumn(id1, column1);
      final factory2 = facadeRegistry.initializeColumn(id2, column2);
      final factory3 = facadeRegistry.initializeColumn(id3, column3);
      yield RawQueryChunk3<TExt, T2Ext, T3Ext>._(
        world: world,
        archetypeId: archetype.archetypeId,
        entities: archetype.entities,
        rowCount: rowCount,
        column1: RawComponentColumn<TExt>._(factory1, column1, rowCount),
        column2: RawComponentColumn<T2Ext>._(factory2, column2, rowCount),
        column3: RawComponentColumn<T3Ext>._(factory3, column3, rowCount),
      );
    }
  }

  /// Returns raw chunk views for four components without per-row wrapper records.
  Iterable<RawQueryChunk4<TExt, T2Ext, T3Ext, T4Ext>> iterRaw4<
    TComp extends Component,
    TExt,
    T2Comp extends Component,
    T2Ext,
    T3Comp extends Component,
    T3Ext,
    T4Comp extends Component,
    T4Ext
  >() sync* {
    world.ensureFlushed();
    final id1 = world.components.getComponentId<TComp>();
    final id2 = world.components.getComponentId<T2Comp>();
    final id3 = world.components.getComponentId<T3Comp>();
    final id4 = world.components.getComponentId<T4Comp>();
    final archetypes = _resolveArchetypesForIds([id1, id2, id3, id4]);
    if (archetypes.isEmpty) {
      return;
    }

    final facadeRegistry = world.components.componentFacadeRegistry;
    for (final archetype in archetypes) {
      final column1 = archetype.getColumn(id1);
      final column2 = archetype.getColumn(id2);
      final column3 = archetype.getColumn(id3);
      final column4 = archetype.getColumn(id4);
      if (column1 == null ||
          column2 == null ||
          column3 == null ||
          column4 == null) {
        continue;
      }
      final rowCount = _minRowCount5(
        column1.length,
        column2.length,
        column3.length,
        column4.length,
        archetype.entities.length,
      );
      if (rowCount == 0) {
        continue;
      }
      final factory1 = facadeRegistry.initializeColumn(id1, column1);
      final factory2 = facadeRegistry.initializeColumn(id2, column2);
      final factory3 = facadeRegistry.initializeColumn(id3, column3);
      final factory4 = facadeRegistry.initializeColumn(id4, column4);
      yield RawQueryChunk4<TExt, T2Ext, T3Ext, T4Ext>._(
        world: world,
        archetypeId: archetype.archetypeId,
        entities: archetype.entities,
        rowCount: rowCount,
        column1: RawComponentColumn<TExt>._(factory1, column1, rowCount),
        column2: RawComponentColumn<T2Ext>._(factory2, column2, rowCount),
        column3: RawComponentColumn<T3Ext>._(factory3, column3, rowCount),
        column4: RawComponentColumn<T4Ext>._(factory4, column4, rowCount),
      );
    }
  }

  /// Check if an archetype signature matches this query.
  bool matches(final ArchetypeSignature signature) {
    // Must have all required components
    if (!signature.mask.contains(requiredMask)) {
      return false;
    }
    // Must not have any excluded components
    if (signature.mask.intersects(excludedMask)) {
      return false;
    }
    return true;
  }

  /// Add excluded component type to the query.
  ComponentQuery withoutType<T extends Component>() {
    final componentId = world.components.getComponentId<T>();
    if (excludedMask.has(componentId)) {
      return this;
    }
    final newExcludedMask = excludedMask.copy();
    newExcludedMask.set(componentId);
    return ComponentQuery._(world, requiredMask, newExcludedMask);
  }

  /// Add required component type to the query.
  ComponentQuery withType<T extends Component>() {
    final componentId = world.components.getComponentId<T>();
    if (requiredMask.has(componentId)) {
      return this;
    }
    final newRequiredMask = requiredMask.copy();
    newRequiredMask.set(componentId);
    return ComponentQuery._(world, newRequiredMask, excludedMask);
  }
}

final class RawComponentColumn<T> {
  const RawComponentColumn._(this._factory, this._column, this.length);

  final ComponentFacadeFactory _factory;
  final DataColumn _column;
  final int length;

  T operator [](final int row) {
    if (row < 0 || row >= length) {
      throw RangeError.index(row, this, 'row', null, length);
    }
    _factory.initialize(_column);
    return _factory.create(row) as T;
  }

  void forEachIndexed(final void Function(int row, T component) visitor) {
    _factory.initialize(_column);
    for (var row = 0; row < length; row++) {
      visitor(row, _factory.create(row) as T);
    }
  }

  void _initialize() => _factory.initialize(_column);

  T _createAt(final int row) => _factory.create(row) as T;
}

final class RawQueryChunk2<T1, T2> {
  const RawQueryChunk2._({
    required final World world,
    required final ArchetypeId archetypeId,
    required this.entities,
    required this.rowCount,
    required this.column1,
    required this.column2,
  }) : _world = world,
       _archetypeId = archetypeId;

  final World _world;
  final ArchetypeId _archetypeId;
  final List<Entity> entities;
  final int rowCount;
  final RawComponentColumn<T1> column1;
  final RawComponentColumn<T2> column2;

  void forEachRow(
    final void Function(int row, Entity entity, T1 c1, T2 c2) visitor,
  ) {
    column1._initialize();
    column2._initialize();
    for (var row = 0; row < rowCount; row++) {
      final entity = entities[row];
      if (!_isEntityRowCurrentAtLocation(_world, _archetypeId, entity, row)) {
        continue;
      }
      visitor(row, entity, column1._createAt(row), column2._createAt(row));
    }
  }
}

final class RawQueryChunk3<T1, T2, T3> {
  const RawQueryChunk3._({
    required final World world,
    required final ArchetypeId archetypeId,
    required this.entities,
    required this.rowCount,
    required this.column1,
    required this.column2,
    required this.column3,
  }) : _world = world,
       _archetypeId = archetypeId;

  final World _world;
  final ArchetypeId _archetypeId;
  final List<Entity> entities;
  final int rowCount;
  final RawComponentColumn<T1> column1;
  final RawComponentColumn<T2> column2;
  final RawComponentColumn<T3> column3;

  void forEachRow(
    final void Function(int row, Entity entity, T1 c1, T2 c2, T3 c3) visitor,
  ) {
    column1._initialize();
    column2._initialize();
    column3._initialize();
    for (var row = 0; row < rowCount; row++) {
      final entity = entities[row];
      if (!_isEntityRowCurrentAtLocation(_world, _archetypeId, entity, row)) {
        continue;
      }
      visitor(
        row,
        entity,
        column1._createAt(row),
        column2._createAt(row),
        column3._createAt(row),
      );
    }
  }
}

final class RawQueryChunk4<T1, T2, T3, T4> {
  const RawQueryChunk4._({
    required final World world,
    required final ArchetypeId archetypeId,
    required this.entities,
    required this.rowCount,
    required this.column1,
    required this.column2,
    required this.column3,
    required this.column4,
  }) : _world = world,
       _archetypeId = archetypeId;

  final World _world;
  final ArchetypeId _archetypeId;
  final List<Entity> entities;
  final int rowCount;
  final RawComponentColumn<T1> column1;
  final RawComponentColumn<T2> column2;
  final RawComponentColumn<T3> column3;
  final RawComponentColumn<T4> column4;

  void forEachRow(
    final void Function(int row, Entity entity, T1 c1, T2 c2, T3 c3, T4 c4)
    visitor,
  ) {
    column1._initialize();
    column2._initialize();
    column3._initialize();
    column4._initialize();
    for (var row = 0; row < rowCount; row++) {
      final entity = entities[row];
      if (!_isEntityRowCurrentAtLocation(_world, _archetypeId, entity, row)) {
        continue;
      }
      visitor(
        row,
        entity,
        column1._createAt(row),
        column2._createAt(row),
        column3._createAt(row),
        column4._createAt(row),
      );
    }
  }
}

int _minRowCount3(final int a, final int b, final int c) {
  var min = a;
  if (b < min) min = b;
  if (c < min) min = c;
  return min;
}

int _minRowCount4(final int a, final int b, final int c, final int d) {
  var min = a;
  if (b < min) min = b;
  if (c < min) min = c;
  if (d < min) min = d;
  return min;
}

int _minRowCount5(
  final int a,
  final int b,
  final int c,
  final int d,
  final int e,
) {
  var min = a;
  if (b < min) min = b;
  if (c < min) min = c;
  if (d < min) min = d;
  if (e < min) min = e;
  return min;
}

bool _isEntityRowCurrent(
  final World world,
  final Archetype archetype,
  final Entity entity,
  final int row,
) => _isEntityRowCurrentAtLocation(world, archetype.archetypeId, entity, row);

bool _isEntityRowCurrentAtLocation(
  final World world,
  final ArchetypeId archetypeId,
  final Entity entity,
  final int row,
) {
  if (!world.entities.isAlive(entity)) {
    return false;
  }
  final location = world.entities.getLocation(entity);
  return location.archetypeId == archetypeId && location.archetypeRow == row;
}

int _packPlanKey(final List<ComponentId> ids) {
  var key = ids.length & 0xF;
  for (var i = 0; i < ids.length; i++) {
    key |= (ids[i].value & 0xFF) << (4 + (i * 8));
  }
  return key;
}

final class _CompiledQueryPlan {
  _CompiledQueryPlan(this.mask);

  final ComponentMask mask;
  int _cachedArchetypeVersion = -1;
  List<Archetype>? _cachedArchetypes;

  List<Archetype> resolve(final World world) {
    final version = world.archetypes.structuralVersion;
    final cached = _cachedArchetypes;
    if (cached != null && _cachedArchetypeVersion == version) {
      return cached;
    }

    final computed = world.queryCache.getOrCompute(mask, world.archetypes);
    _cachedArchetypes = computed.matchingArchetypes;
    _cachedArchetypeVersion = version;
    return _cachedArchetypes!;
  }
}

/// Builder for constructing queries.
class ComponentQueryBuilder {
  ComponentQueryBuilder(this.world);

  final World world;
  final Set<ComponentId> _required = {};
  final Set<ComponentId> _excluded = {};

  /// Build query.
  ComponentQuery build() => ComponentQuery(
    world: world,
    required: _required.isEmpty ? null : _required,
    excluded: _excluded.isEmpty ? null : _excluded,
  );

  /// Add required component.
  ComponentQueryBuilder withComponent(final ComponentId id) {
    _required.add(id);
    return this;
  }

  /// Add excluded component.
  ComponentQueryBuilder withoutComponent(final ComponentId id) {
    _excluded.add(id);
    return this;
  }
}

/// Query for entities that MUST NOT have any specified components.
class ExcludedQuery {
  ExcludedQuery(final Iterable<ComponentId> excluded)
    : excludedMask = createComponentMask(excluded);

  final ComponentMask excludedMask;

  /// Check if archetype matches this query.
  bool matches(final ArchetypeSignature signature) =>
      !signature.mask.intersects(excludedMask);
}

/// Query for entities that MUST have all specified components.
class RequiredQuery {
  RequiredQuery(final Iterable<ComponentId> required)
    : requiredMask = createComponentMask(required);

  final ComponentMask requiredMask;

  /// Check if archetype matches this query.
  bool matches(final ArchetypeSignature signature) =>
      signature.mask.contains(requiredMask);
}

/// Internal iterable for a single-component query using Column abstraction.
class _QueryIterable1<T extends Component>
    extends IterableBase<(WorldEntity, T)> {
  _QueryIterable1(this.archetypes, this.componentId, this.world);
  final List<Archetype> archetypes;
  final ComponentId componentId;
  final World world;

  @override
  Iterator<(WorldEntity, T)> get iterator =>
      _QueryIterator1<T>(archetypes, componentId, world);
}

/// Iterator implementation for single component with predicate filtering
class _QueryIterable1Where<T1 extends Component>
    extends Iterable<(WorldEntity, T1)> {
  _QueryIterable1Where(
    this.archetypes,
    this.componentId1,
    this.world,
    this.predicate,
  );

  final List<Archetype> archetypes;
  final ComponentId componentId1;
  final World world;
  final ComponentPredicate<T1> predicate;

  @override
  Iterator<(WorldEntity, T1)> get iterator =>
      _QueryIterator1Where<T1>(archetypes, componentId1, world, predicate);
}

/// Internal iterable for a two-component query.
class _QueryIterable2<T1 extends Component, T2 extends Component>
    extends IterableBase<(WorldEntity, T1, T2)> {
  _QueryIterable2(this._archetypes, this._id1, this._id2, this._world);
  final List<Archetype> _archetypes;
  final ComponentId _id1;
  final ComponentId _id2;
  final World _world;

  @override
  Iterator<(WorldEntity, T1, T2)> get iterator =>
      _QueryIterator2<T1, T2>(_archetypes, _id1, _id2, _world);
}

/// Internal iterable for a three-component query.
class _QueryIterable3<
  T1 extends Component,
  T2 extends Component,
  T3 extends Component
>
    extends IterableBase<(WorldEntity, T1, T2, T3)> {
  _QueryIterable3(
    this._archetypes,
    this._id1,
    this._id2,
    this._id3,
    this._world,
  );
  final List<Archetype> _archetypes;
  final ComponentId _id1;
  final ComponentId _id2;
  final ComponentId _id3;
  final World _world;

  @override
  Iterator<(WorldEntity, T1, T2, T3)> get iterator =>
      _QueryIterator3<T1, T2, T3>(_archetypes, _id1, _id2, _id3, _world);
}

/// Internal iterable for a four-component query.
class _QueryIterable4<
  T1 extends Component,
  T2 extends Component,
  T3 extends Component,
  T4 extends Component
>
    extends IterableBase<(WorldEntity, T1, T2, T3, T4)> {
  _QueryIterable4(
    this._archetypes,
    this._id1,
    this._id2,
    this._id3,
    this._id4,
    this._world,
  );
  final List<Archetype> _archetypes;
  final ComponentId _id1;
  final ComponentId _id2;
  final ComponentId _id3;
  final ComponentId _id4;
  final World _world;

  @override
  Iterator<(WorldEntity, T1, T2, T3, T4)> get iterator =>
      _QueryIterator4<T1, T2, T3, T4>(
        _archetypes,
        _id1,
        _id2,
        _id3,
        _id4,
        _world,
      );
}

/// Internal iterable for a five-component query.
class _QueryIterable5<
  T1 extends Component,
  T2 extends Component,
  T3 extends Component,
  T4 extends Component,
  T5 extends Component
>
    extends IterableBase<(WorldEntity, T1, T2, T3, T4, T5)> {
  _QueryIterable5(
    this._archetypes,
    this._id1,
    this._id2,
    this._id3,
    this._id4,
    this._id5,
    this._world,
  );
  final List<Archetype> _archetypes;
  final ComponentId _id1;
  final ComponentId _id2;
  final ComponentId _id3;
  final ComponentId _id4;
  final ComponentId _id5;
  final World _world;

  @override
  Iterator<(WorldEntity, T1, T2, T3, T4, T5)> get iterator =>
      _QueryIterator5<T1, T2, T3, T4, T5>(
        _archetypes,
        _id1,
        _id2,
        _id3,
        _id4,
        _id5,
        _world,
      );
}

/// Internal iterable for a six-component query.
class _QueryIterable6<
  T1 extends Component,
  T2 extends Component,
  T3 extends Component,
  T4 extends Component,
  T5 extends Component,
  T6 extends Component
>
    extends IterableBase<(WorldEntity, T1, T2, T3, T4, T5, T6)> {
  _QueryIterable6(
    this._archetypes,
    this._id1,
    this._id2,
    this._id3,
    this._id4,
    this._id5,
    this._id6,
    this._world,
  );
  final List<Archetype> _archetypes;
  final ComponentId _id1, _id2, _id3, _id4, _id5, _id6;
  final World _world;

  @override
  Iterator<(WorldEntity, T1, T2, T3, T4, T5, T6)> get iterator =>
      _QueryIterator6<T1, T2, T3, T4, T5, T6>(
        _archetypes,
        _id1,
        _id2,
        _id3,
        _id4,
        _id5,
        _id6,
        _world,
      );
}

/// Internal iterable for extension type queries with a single component type.
///
/// Returns ExtensionType directly, eliminating casting.
class _QueryIterableExt1<TComp extends Component, TExt>
    extends IterableBase<(WorldEntityExtension, TExt)> {
  _QueryIterableExt1(this._archetypes, this._id1, this._world);
  final List<Archetype> _archetypes;
  final ComponentId _id1;
  final World _world;

  @override
  Iterator<(WorldEntityExtension, TExt)> get iterator =>
      _QueryIteratorExt1<TComp, TExt>(_archetypes, _id1, _world);
}

/// Iterator implementation for extension type with predicate filtering
class _QueryIterableExt1Where<TComp extends Component, TExt>
    extends Iterable<(WorldEntityExtension, TExt)> {
  _QueryIterableExt1Where(
    this.archetypes,
    this.componentId,
    this.world,
    this.predicate,
  );

  final List<Archetype> archetypes;
  final ComponentId componentId;
  final World world;
  final ExtensionPredicate<TExt> predicate;

  @override
  Iterator<(WorldEntityExtension, TExt)> get iterator =>
      _QueryIteratorExt1Where<TComp, TExt>(
        archetypes,
        componentId,
        world,
        predicate,
      );
}

/// Internal iterable for extension type queries with two component types.
///
/// Returns (ExtensionType1, ExtensionType2) tuples directly, eliminating casting.
class _QueryIterableExt2<
  TComp extends Component,
  TExt,
  T2Comp extends Component,
  T2Ext
>
    extends IterableBase<(WorldEntityExtension, TExt, T2Ext)> {
  _QueryIterableExt2(this._archetypes, this._id1, this._id2, this._world);
  final List<Archetype> _archetypes;
  final ComponentId _id1;
  final ComponentId _id2;
  final World _world;

  @override
  Iterator<(WorldEntityExtension, TExt, T2Ext)> get iterator =>
      _QueryIteratorExt2<TComp, TExt, T2Comp, T2Ext>(
        _archetypes,
        _id1,
        _id2,
        _world,
      );
}

/// Iterator implementation for two extension types with predicate filtering
class _QueryIterableExt2Where<
  TComp extends Component,
  TExt,
  T2Comp extends Component,
  T2Ext
>
    extends Iterable<(WorldEntityExtension, TExt, T2Ext)> {
  _QueryIterableExt2Where(
    this.archetypes,
    this.componentId1,
    this.componentId2,
    this.world,
    this.predicate,
  );

  final List<Archetype> archetypes;
  final ComponentId componentId1;
  final ComponentId componentId2;
  final World world;
  final ExtensionPredicate<TExt> predicate;

  @override
  Iterator<(WorldEntityExtension, TExt, T2Ext)> get iterator =>
      _QueryIteratorExt2WhereIterator<TComp, TExt, T2Comp, T2Ext>(
        archetypes,
        componentId1,
        componentId2,
        world,
        predicate,
      );
}

/// Internal iterable for extension type queries with three component types.
///
/// Returns (ExtensionType1, ExtensionType2, ExtensionType3) tuples directly, eliminating casting.
class _QueryIterableExt3<
  TComp extends Component,
  TExt,
  T2Comp extends Component,
  T2Ext,
  T3Comp extends Component,
  T3Ext
>
    extends IterableBase<(WorldEntityExtension, TExt, T2Ext, T3Ext)> {
  _QueryIterableExt3(
    this._archetypes,
    this._id1,
    this._id2,
    this._id3,
    this._world,
  ) {
    // keep existing validation logic
    if (TComp != TExt) {
      final registeredExt1 = _world.components.componentFacadeRegistry
          .getExtensionType(_id1);
      if (registeredExt1 == null) {
        throw ExtensionTypeNotRegisteredError<TExt>(_id1);
      }
      if (registeredExt1 != TExt) {
        throw ExtensionTypeMismatchError(_id1, registeredExt1, TExt);
      }
    }
    // ... similar for T2Ext, T3Ext
  }

  final List<Archetype> _archetypes;
  final ComponentId _id1;
  final ComponentId _id2;
  final ComponentId _id3;
  final World _world;

  @override
  Iterator<(WorldEntityExtension, TExt, T2Ext, T3Ext)> get iterator =>
      _QueryIteratorExt3<TComp, TExt, T2Comp, T2Ext, T3Comp, T3Ext>(
        _archetypes,
        _id1,
        _id2,
        _id3,
        _world,
      );
}

/// Internal iterable for extension type queries with four component types.
///
/// Returns (ExtensionType1, ExtensionType2, ExtensionType3, ExtensionType4) tuples directly, eliminating casting.
class _QueryIterableExt4<
  TComp extends Component,
  TExt,
  T2Comp extends Component,
  T2Ext,
  T3Comp extends Component,
  T3Ext,
  T4Comp extends Component,
  T4Ext
>
    extends IterableBase<(WorldEntityExtension, TExt, T2Ext, T3Ext, T4Ext)> {
  _QueryIterableExt4(
    this._archetypes,
    this._id1,
    this._id2,
    this._id3,
    this._id4,
    this._world,
  ) {
    // validate only if its not the same component type
    if (TComp != TExt) {
      // Validate extension types match registered types
      final registeredExt1 = _world.components.componentFacadeRegistry
          .getExtensionType(_id1);
      if (registeredExt1 == null) {
        throw ExtensionTypeNotRegisteredError<TExt>(_id1);
      }
      if (registeredExt1 != TExt) {
        throw ExtensionTypeMismatchError(_id1, registeredExt1, TExt);
      }
    }

    // validate only if its not the same component type
    if (T2Comp != T2Ext) {
      final registeredExt2 = _world.components.componentFacadeRegistry
          .getExtensionType(_id2);
      if (registeredExt2 == null) {
        throw ExtensionTypeNotRegisteredError<T2Ext>(_id2);
      }
      if (registeredExt2 != T2Ext) {
        throw ExtensionTypeMismatchError(_id2, registeredExt2, T2Ext);
      }
    }

    // validate only if its not the same component type
    if (T3Comp != T3Ext) {
      final registeredExt3 = _world.components.componentFacadeRegistry
          .getExtensionType(_id3);
      if (registeredExt3 == null) {
        throw ExtensionTypeNotRegisteredError<T3Ext>(_id3);
      }
      if (registeredExt3 != T3Ext) {
        throw ExtensionTypeMismatchError(_id3, registeredExt3, T3Ext);
      }
    }

    // validate only if its not the same component type
    if (T4Comp != T4Ext) {
      final registeredExt4 = _world.components.componentFacadeRegistry
          .getExtensionType(_id4);
      if (registeredExt4 == null) {
        throw ExtensionTypeNotRegisteredError<T4Ext>(_id4);
      }
      if (registeredExt4 != T4Ext) {
        throw ExtensionTypeMismatchError(_id4, registeredExt4, T4Ext);
      }
    }
  }

  final List<Archetype> _archetypes;
  final ComponentId _id1;
  final ComponentId _id2;
  final ComponentId _id3;
  final ComponentId _id4;
  final World _world;

  @override
  Iterator<(WorldEntityExtension, TExt, T2Ext, T3Ext, T4Ext)> get iterator =>
      _QueryIteratorExt4<
        TComp,
        TExt,
        T2Comp,
        T2Ext,
        T3Comp,
        T3Ext,
        T4Comp,
        T4Ext
      >(_archetypes, _id1, _id2, _id3, _id4, _world);
}

/// Internal iterable for mutable queries with a single component type.
class _QueryIterableMut1<T1 extends Component>
    extends IterableBase<(WorldEntityMut, T1)> {
  _QueryIterableMut1(this._archetypes, this._componentId, this._world);
  final List<Archetype> _archetypes;
  final ComponentId _componentId;
  final World _world;

  @override
  Iterator<(WorldEntityMut, T1)> get iterator =>
      _QueryIteratorMut1<T1>(_archetypes, _componentId, _world);
}

/// Internal iterable for mutable queries with two component types.
class _QueryIterableMut2<T1 extends Component, T2 extends Component>
    extends IterableBase<(WorldEntityMut, T1, T2)> {
  _QueryIterableMut2(this._archetypes, this._id1, this._id2, this._world);
  final List<Archetype> _archetypes;
  final ComponentId _id1;
  final ComponentId _id2;
  final World _world;

  @override
  Iterator<(WorldEntityMut, T1, T2)> get iterator =>
      _QueryIteratorMut2<T1, T2>(_archetypes, _id1, _id2, _world);
}

/// Internal iterable for mutable queries with three component types.
class _QueryIterableMut3<
  T1 extends Component,
  T2 extends Component,
  T3 extends Component
>
    extends IterableBase<(WorldEntityMut, T1, T2, T3)> {
  _QueryIterableMut3(
    this._archetypes,
    this._id1,
    this._id2,
    this._id3,
    this._world,
  );
  final List<Archetype> _archetypes;
  final ComponentId _id1;
  final ComponentId _id2;
  final ComponentId _id3;
  final World _world;

  @override
  Iterator<(WorldEntityMut, T1, T2, T3)> get iterator =>
      _QueryIteratorMut3<T1, T2, T3>(_archetypes, _id1, _id2, _id3, _world);
}

/// Internal iterable for mutable queries with four component types.
class _QueryIterableMut4<
  T1 extends Component,
  T2 extends Component,
  T3 extends Component,
  T4 extends Component
>
    extends IterableBase<(WorldEntityMut, T1, T2, T3, T4)> {
  _QueryIterableMut4(
    this._archetypes,
    this._id1,
    this._id2,
    this._id3,
    this._id4,
    this._world,
  );
  final List<Archetype> _archetypes;
  final ComponentId _id1;
  final ComponentId _id2;
  final ComponentId _id3;
  final ComponentId _id4;
  final World _world;

  @override
  Iterator<(WorldEntityMut, T1, T2, T3, T4)> get iterator =>
      _QueryIteratorMut4<T1, T2, T3, T4>(
        _archetypes,
        _id1,
        _id2,
        _id3,
        _id4,
        _world,
      );
}

/// Internal iterable for raw extension-type queries with two component types.
///
/// Returns (Entity, ExtensionType1, ExtensionType2) tuples.
class _QueryIterableRawExt2<
  TComp extends Component,
  TExt,
  T2Comp extends Component,
  T2Ext
>
    extends IterableBase<(Entity, TExt, T2Ext)> {
  _QueryIterableRawExt2(this._archetypes, this._id1, this._id2, this._world);
  final List<Archetype> _archetypes;
  final ComponentId _id1;
  final ComponentId _id2;
  final World _world;

  @override
  Iterator<(Entity, TExt, T2Ext)> get iterator =>
      _QueryIteratorRawExt2<TComp, TExt, T2Comp, T2Ext>(
        _archetypes,
        _id1,
        _id2,
        _world,
      );
}

/// Internal iterator for single component queries.
class _QueryIterator1<T1 extends Component>
    implements Iterator<(WorldEntity, T1)> {
  _QueryIterator1(this._archetypes, this._id1, this._world);

  final List<Archetype> _archetypes;
  final ComponentId _id1;
  final World _world;

  // Cached factory for performance optimization
  ComponentFacadeFactory? _cachedFactory;

  int _archetypeIndex = 0;
  int _entityIndex = 0;
  int _lastInitializedArchetypeIndex = -1;
  (WorldEntity, T1)? _current;

  @override
  (WorldEntity, T1) get current {
    if (_current == null) {
      throw IteratorNotReadyError('Query iterator (1 component)');
    }
    return _current!;
  }

  @override
  bool moveNext() {
    while (_archetypeIndex < _archetypes.length) {
      final archetype = _archetypes[_archetypeIndex];
      final column1 = archetype.getColumn(_id1);

      if (column1 != null && _entityIndex < column1.length) {
        // Cache factory when entering new archetype
        if (_archetypeIndex != _lastInitializedArchetypeIndex) {
          _cachedFactory = _world.components.componentFacadeRegistry.getFactory(
            _id1,
          );
          // Re-fetch factory after initializeColumn in case it was auto-generated for ObjectColumn
          _cachedFactory = _world.components.componentFacadeRegistry
              .initializeColumn(_id1, column1);

          _lastInitializedArchetypeIndex = _archetypeIndex;
        }

        final entity = archetype.entities[_entityIndex];
        final (entityWrapper, isValid) = _world.getEntityFast(entity);
        if (!isValid) {
          _entityIndex++;
          continue;
        }

        // Get component: Use cached factory (no HashMap lookup)
        final component1 = _cachedFactory!.create(_entityIndex) as T1;

        _current = (entityWrapper, component1);
        _entityIndex++;
        return true;
      }

      _archetypeIndex++;
      _entityIndex = 0;
    }

    _current = null;
    return false;
  }
}

/// Internal iterator for single component queries with predicate filtering.
class _QueryIterator1Where<T1 extends Component>
    implements Iterator<(WorldEntity, T1)> {
  _QueryIterator1Where(
    this.archetypes,
    this.componentId,
    this.world,
    this.predicate,
  );

  final List<Archetype> archetypes;
  final ComponentId componentId;
  final World world;
  final ComponentPredicate<T1> predicate;

  int archetypeIndex = 0;
  int entityIndex = -1;
  (WorldEntity, T1)? _current;

  @override
  (WorldEntity, T1) get current => _current!;

  @override
  bool moveNext() {
    while (archetypeIndex < archetypes.length) {
      final archetype = archetypes[archetypeIndex];
      final column = archetype.getColumn(componentId);

      if (column == null) {
        archetypeIndex++;
        entityIndex = -1;
        continue;
      }

      while (entityIndex < archetype.entityCount - 1) {
        entityIndex++;
        final entity = archetype.entities[entityIndex];
        final (entityWrapper, isValid) = world.getEntityFast(entity);
        if (!isValid) {
          continue;
        }

        final component = world.components.componentFacadeRegistry
            .createFacade<T1>(componentId, entityIndex, column);

        if (predicate(component)) {
          _current = (entityWrapper, component);
          return true;
        }
      }

      // Move to next archetype
      archetypeIndex++;
      entityIndex = -1;
    }

    _current = null;
    return false;
  }
}

/// Internal iterator for two component queries.
class _QueryIterator2<T1 extends Component, T2 extends Component>
    implements Iterator<(WorldEntity, T1, T2)> {
  _QueryIterator2(this._archetypes, this._id1, this._id2, this._world);

  final List<Archetype> _archetypes;
  final ComponentId _id1;
  final ComponentId _id2;
  final World _world;

  // Cached factories for performance optimization
  ComponentFacadeFactory? _cachedFactory1, _cachedFactory2;

  int _archetypeIndex = 0;
  int _entityIndex = 0;
  int _lastInitializedArchetypeIndex = -1;
  (WorldEntity, T1, T2)? _current;

  @override
  (WorldEntity, T1, T2) get current {
    if (_current == null) {
      throw IteratorNotReadyError('Query iterator (2 components)');
    }
    return _current!;
  }

  @override
  bool moveNext() {
    while (_archetypeIndex < _archetypes.length) {
      final archetype = _archetypes[_archetypeIndex];
      final column1 = archetype.getColumn(_id1);
      final column2 = archetype.getColumn(_id2);

      if (column1 != null &&
          column2 != null &&
          _entityIndex < column1.length &&
          _entityIndex < column2.length) {
        // Cache factories when entering new archetype
        if (_archetypeIndex != _lastInitializedArchetypeIndex) {
          _cachedFactory1 = _world.components.componentFacadeRegistry
              .getFactory(_id1);
          _cachedFactory2 = _world.components.componentFacadeRegistry
              .getFactory(_id2);
          // Re-fetch factories after initializeColumn in case they were auto-generated for ObjectColumn
          _cachedFactory1 = _world.components.componentFacadeRegistry
              .initializeColumn(_id1, column1);
          _cachedFactory2 = _world.components.componentFacadeRegistry
              .initializeColumn(_id2, column2);

          _lastInitializedArchetypeIndex = _archetypeIndex;
        }

        final entity = archetype.entities[_entityIndex];
        final (entityWrapper, isValid) = _world.getEntityFast(entity);
        if (!isValid) {
          _entityIndex++;
          continue;
        }

        // Get components: Use cached factories (no HashMap lookup)
        final component1 = _cachedFactory1!.create(_entityIndex) as T1;
        final component2 = _cachedFactory2!.create(_entityIndex) as T2;

        _current = (entityWrapper, component1, component2);
        _entityIndex++;
        return true;
      }

      _archetypeIndex++;
      _entityIndex = 0;
    }

    _current = null;
    return false;
  }
}

/// Internal iterator for three component queries.
class _QueryIterator3<
  T1 extends Component,
  T2 extends Component,
  T3 extends Component
>
    implements Iterator<(WorldEntity, T1, T2, T3)> {
  _QueryIterator3(
    this._archetypes,
    this._id1,
    this._id2,
    this._id3,
    this._world,
  );

  final List<Archetype> _archetypes;
  final ComponentId _id1;
  final ComponentId _id2;
  final ComponentId _id3;
  final World _world;

  // Cached factories for performance optimization
  ComponentFacadeFactory? _cachedFactory1, _cachedFactory2, _cachedFactory3;

  int _archetypeIndex = 0;
  int _entityIndex = 0;
  int _lastInitializedArchetypeIndex = -1;
  (WorldEntity, T1, T2, T3)? _current;

  @override
  (WorldEntity, T1, T2, T3) get current {
    if (_current == null) {
      throw IteratorNotReadyError('Query iterator (3 components)');
    }
    return _current!;
  }

  @override
  bool moveNext() {
    while (_archetypeIndex < _archetypes.length) {
      final archetype = _archetypes[_archetypeIndex];
      final column1 = archetype.getColumn(_id1);
      final column2 = archetype.getColumn(_id2);
      final column3 = archetype.getColumn(_id3);

      if (column1 != null &&
          column2 != null &&
          column3 != null &&
          _entityIndex < column1.length &&
          _entityIndex < column2.length &&
          _entityIndex < column3.length) {
        // Cache factories when entering new archetype
        if (_archetypeIndex != _lastInitializedArchetypeIndex) {
          _cachedFactory1 = _world.components.componentFacadeRegistry
              .getFactory(_id1);
          _cachedFactory2 = _world.components.componentFacadeRegistry
              .getFactory(_id2);
          _cachedFactory3 = _world.components.componentFacadeRegistry
              .getFactory(_id3);
          // Re-fetch factories after initializeColumn in case they were auto-generated for ObjectColumn
          _cachedFactory1 = _world.components.componentFacadeRegistry
              .initializeColumn(_id1, column1);
          _cachedFactory2 = _world.components.componentFacadeRegistry
              .initializeColumn(_id2, column2);
          _cachedFactory3 = _world.components.componentFacadeRegistry
              .initializeColumn(_id3, column3);
          _lastInitializedArchetypeIndex = _archetypeIndex;
        }

        final entity = archetype.entities[_entityIndex];
        final (entityWrapper, isValid) = _world.getEntityFast(entity);
        if (!isValid) {
          _entityIndex++;
          continue;
        }

        // Get components: Use cached factories (no HashMap lookup)
        final component1 = _cachedFactory1!.create(_entityIndex) as T1;
        final component2 = _cachedFactory2!.create(_entityIndex) as T2;
        final component3 = _cachedFactory3!.create(_entityIndex) as T3;

        _current = (entityWrapper, component1, component2, component3);
        _entityIndex++;
        return true;
      }

      _archetypeIndex++;
      _entityIndex = 0;
    }

    _current = null;
    return false;
  }
}

/// Internal iterator for four component queries.
class _QueryIterator4<
  T1 extends Component,
  T2 extends Component,
  T3 extends Component,
  T4 extends Component
>
    implements Iterator<(WorldEntity, T1, T2, T3, T4)> {
  _QueryIterator4(
    this._archetypes,
    this._id1,
    this._id2,
    this._id3,
    this._id4,
    this._world,
  );

  final List<Archetype> _archetypes;
  final ComponentId _id1;
  final ComponentId _id2;
  final ComponentId _id3;
  final ComponentId _id4;
  final World _world;

  // Cached factories for performance optimization
  ComponentFacadeFactory? _cachedFactory1,
      _cachedFactory2,
      _cachedFactory3,
      _cachedFactory4;

  int _archetypeIndex = 0;
  int _entityIndex = 0;
  int _lastInitializedArchetypeIndex = -1;
  (WorldEntity, T1, T2, T3, T4)? _current;

  @override
  (WorldEntity, T1, T2, T3, T4) get current {
    if (_current == null) {
      throw IteratorNotReadyError('Query iterator (4 components)');
    }
    return _current!;
  }

  @override
  bool moveNext() {
    while (_archetypeIndex < _archetypes.length) {
      final archetype = _archetypes[_archetypeIndex];
      final column1 = archetype.getColumn(_id1);
      final column2 = archetype.getColumn(_id2);
      final column3 = archetype.getColumn(_id3);
      final column4 = archetype.getColumn(_id4);

      if (column1 != null &&
          column2 != null &&
          column3 != null &&
          column4 != null &&
          _entityIndex < column1.length &&
          _entityIndex < column2.length &&
          _entityIndex < column3.length &&
          _entityIndex < column4.length) {
        // Cache factories when entering new archetype
        if (_archetypeIndex != _lastInitializedArchetypeIndex) {
          _cachedFactory1 = _world.components.componentFacadeRegistry
              .getFactory(_id1);
          _cachedFactory2 = _world.components.componentFacadeRegistry
              .getFactory(_id2);
          _cachedFactory3 = _world.components.componentFacadeRegistry
              .getFactory(_id3);
          _cachedFactory4 = _world.components.componentFacadeRegistry
              .getFactory(_id4);
          // Re-fetch factories after initializeColumn in case they were auto-generated for ObjectColumn
          _cachedFactory1 = _world.components.componentFacadeRegistry
              .initializeColumn(_id1, column1);
          _cachedFactory2 = _world.components.componentFacadeRegistry
              .initializeColumn(_id2, column2);
          _cachedFactory3 = _world.components.componentFacadeRegistry
              .initializeColumn(_id3, column3);
          _cachedFactory4 = _world.components.componentFacadeRegistry
              .initializeColumn(_id4, column4);

          _lastInitializedArchetypeIndex = _archetypeIndex;
        }

        final entity = archetype.entities[_entityIndex];
        final (entityWrapper, isValid) = _world.getEntityFast(entity);
        if (!isValid) {
          _entityIndex++;
          continue;
        }

        // Get components: Use cached factories (no HashMap lookup)
        final component1 = _cachedFactory1!.create(_entityIndex) as T1;
        final component2 = _cachedFactory2!.create(_entityIndex) as T2;
        final component3 = _cachedFactory3!.create(_entityIndex) as T3;
        final component4 = _cachedFactory4!.create(_entityIndex) as T4;

        _current = (
          entityWrapper,
          component1,
          component2,
          component3,
          component4,
        );
        _entityIndex++;
        return true;
      }

      _archetypeIndex++;
      _entityIndex = 0;
    }

    _current = null;
    return false;
  }
}

/// Internal iterator for five component queries.
class _QueryIterator5<
  T1 extends Component,
  T2 extends Component,
  T3 extends Component,
  T4 extends Component,
  T5 extends Component
>
    implements Iterator<(WorldEntity, T1, T2, T3, T4, T5)> {
  _QueryIterator5(
    this._archetypes,
    this._id1,
    this._id2,
    this._id3,
    this._id4,
    this._id5,
    this._world,
  );

  final List<Archetype> _archetypes;
  final ComponentId _id1;
  final ComponentId _id2;
  final ComponentId _id3;
  final ComponentId _id4;
  final ComponentId _id5;
  final World _world;

  // Cached factories for performance optimization
  ComponentFacadeFactory? _cachedFactory1,
      _cachedFactory2,
      _cachedFactory3,
      _cachedFactory4,
      _cachedFactory5;

  int _archetypeIndex = 0;
  int _entityIndex = 0;
  int _lastInitializedArchetypeIndex = -1;
  (WorldEntity, T1, T2, T3, T4, T5)? _current;

  @override
  (WorldEntity, T1, T2, T3, T4, T5) get current {
    if (_current == null) {
      throw IteratorNotReadyError('Query iterator (5 components)');
    }
    return _current!;
  }

  @override
  bool moveNext() {
    while (_archetypeIndex < _archetypes.length) {
      final archetype = _archetypes[_archetypeIndex];
      final column1 = archetype.getColumn(_id1);
      final column2 = archetype.getColumn(_id2);
      final column3 = archetype.getColumn(_id3);
      final column4 = archetype.getColumn(_id4);
      final column5 = archetype.getColumn(_id5);

      if (column1 != null &&
          column2 != null &&
          column3 != null &&
          column4 != null &&
          column5 != null &&
          _entityIndex < column1.length &&
          _entityIndex < column2.length &&
          _entityIndex < column3.length &&
          _entityIndex < column4.length &&
          _entityIndex < column5.length) {
        // Cache factories when entering new archetype
        if (_archetypeIndex != _lastInitializedArchetypeIndex) {
          _cachedFactory1 = _world.components.componentFacadeRegistry
              .getFactory(_id1);
          _cachedFactory2 = _world.components.componentFacadeRegistry
              .getFactory(_id2);
          _cachedFactory3 = _world.components.componentFacadeRegistry
              .getFactory(_id3);
          _cachedFactory4 = _world.components.componentFacadeRegistry
              .getFactory(_id4);
          _cachedFactory5 = _world.components.componentFacadeRegistry
              .getFactory(_id5);
          // Re-fetch factories after initializeColumn in case they were auto-generated for ObjectColumn
          _cachedFactory1 = _world.components.componentFacadeRegistry
              .initializeColumn(_id1, column1);
          _cachedFactory2 = _world.components.componentFacadeRegistry
              .initializeColumn(_id2, column2);
          _cachedFactory3 = _world.components.componentFacadeRegistry
              .initializeColumn(_id3, column3);
          _cachedFactory4 = _world.components.componentFacadeRegistry
              .initializeColumn(_id4, column4);
          _cachedFactory5 = _world.components.componentFacadeRegistry
              .initializeColumn(_id5, column5);

          _lastInitializedArchetypeIndex = _archetypeIndex;
        }

        final entity = archetype.entities[_entityIndex];
        final (entityWrapper, isValid) = _world.getEntityFast(entity);
        if (!isValid) {
          _entityIndex++;
          continue;
        }

        // Get components: Use cached factories (no HashMap lookup)
        final component1 = _cachedFactory1!.create(_entityIndex) as T1;
        final component2 = _cachedFactory2!.create(_entityIndex) as T2;
        final component3 = _cachedFactory3!.create(_entityIndex) as T3;
        final component4 = _cachedFactory4!.create(_entityIndex) as T4;
        final component5 = _cachedFactory5!.create(_entityIndex) as T5;

        _current = (
          entityWrapper,
          component1,
          component2,
          component3,
          component4,
          component5,
        );
        _entityIndex++;
        return true;
      }

      _archetypeIndex++;
      _entityIndex = 0;
    }

    _current = null;
    return false;
  }
}

class _QueryIterator6<
  T1 extends Component,
  T2 extends Component,
  T3 extends Component,
  T4 extends Component,
  T5 extends Component,
  T6 extends Component
>
    implements Iterator<(WorldEntity, T1, T2, T3, T4, T5, T6)> {
  _QueryIterator6(
    this._archetypes,
    this._id1,
    this._id2,
    this._id3,
    this._id4,
    this._id5,
    this._id6,
    this._world,
  );

  final List<Archetype> _archetypes;
  final ComponentId _id1;
  final ComponentId _id2;
  final ComponentId _id3;
  final ComponentId _id4;
  final ComponentId _id5;
  final ComponentId _id6;
  final World _world;

  // Cached factories for performance optimization
  ComponentFacadeFactory? _cachedFactory1,
      _cachedFactory2,
      _cachedFactory3,
      _cachedFactory4,
      _cachedFactory5,
      _cachedFactory6;

  int _archetypeIndex = 0;
  int _entityIndex = 0;
  int _lastInitializedArchetypeIndex = -1;
  (WorldEntity, T1, T2, T3, T4, T5, T6)? _current;

  @override
  (WorldEntity, T1, T2, T3, T4, T5, T6) get current {
    if (_current == null) {
      throw IteratorNotReadyError('Query iterator (6 components)');
    }
    return _current!;
  }

  @override
  bool moveNext() {
    while (_archetypeIndex < _archetypes.length) {
      final archetype = _archetypes[_archetypeIndex];
      final column1 = archetype.getColumn(_id1);
      final column2 = archetype.getColumn(_id2);
      final column3 = archetype.getColumn(_id3);
      final column4 = archetype.getColumn(_id4);
      final column5 = archetype.getColumn(_id5);
      final column6 = archetype.getColumn(_id6);

      if (column1 != null &&
          column2 != null &&
          column3 != null &&
          column4 != null &&
          column5 != null &&
          column6 != null &&
          _entityIndex < column1.length &&
          _entityIndex < column2.length &&
          _entityIndex < column3.length &&
          _entityIndex < column4.length &&
          _entityIndex < column5.length &&
          _entityIndex < column6.length) {
        // Cache factories when entering new archetype
        if (_archetypeIndex != _lastInitializedArchetypeIndex) {
          _cachedFactory1 = _world.components.componentFacadeRegistry
              .getFactory(_id1);
          _cachedFactory2 = _world.components.componentFacadeRegistry
              .getFactory(_id2);
          _cachedFactory3 = _world.components.componentFacadeRegistry
              .getFactory(_id3);
          _cachedFactory4 = _world.components.componentFacadeRegistry
              .getFactory(_id4);
          _cachedFactory5 = _world.components.componentFacadeRegistry
              .getFactory(_id5);
          _cachedFactory6 = _world.components.componentFacadeRegistry
              .getFactory(_id6);

          // Re-fetch factories after initializeColumn in case they were auto-generated for ObjectColumn
          _cachedFactory1 = _world.components.componentFacadeRegistry
              .initializeColumn(_id1, column1);
          _cachedFactory2 = _world.components.componentFacadeRegistry
              .initializeColumn(_id2, column2);
          _cachedFactory3 = _world.components.componentFacadeRegistry
              .initializeColumn(_id3, column3);
          _cachedFactory4 = _world.components.componentFacadeRegistry
              .initializeColumn(_id4, column4);
          _cachedFactory5 = _world.components.componentFacadeRegistry
              .initializeColumn(_id5, column5);
          _cachedFactory6 = _world.components.componentFacadeRegistry
              .initializeColumn(_id6, column6);

          _lastInitializedArchetypeIndex = _archetypeIndex;
        }

        final entity = archetype.entities[_entityIndex];
        final (entityWrapper, isValid) = _world.getEntityFast(entity);
        if (!isValid) {
          _entityIndex++;
          continue;
        }

        // Get components: Use cached factories (no HashMap lookup)
        final component1 = _cachedFactory1!.create(_entityIndex) as T1;
        final component2 = _cachedFactory2!.create(_entityIndex) as T2;
        final component3 = _cachedFactory3!.create(_entityIndex) as T3;
        final component4 = _cachedFactory4!.create(_entityIndex) as T4;
        final component5 = _cachedFactory5!.create(_entityIndex) as T5;
        final component6 = _cachedFactory6!.create(_entityIndex) as T6;

        _current = (
          entityWrapper,
          component1,
          component2,
          component3,
          component4,
          component5,
          component6,
        );
        _entityIndex++;
        return true;
      }

      _archetypeIndex++;
      _entityIndex = 0;
    }

    _current = null;
    return false;
  }
}

/// Iterator for extension type queries with a single component type.
/// Returns (WorldEntityExtension, ExtensionType) tuples.
class _QueryIteratorExt1<TComp extends Component, TExt>
    implements Iterator<(WorldEntityExtension, TExt)> {
  _QueryIteratorExt1(this._archetypes, this._id1, this._world);

  final List<Archetype> _archetypes;
  final ComponentId _id1;
  final World _world;

  // Cached factory for performance optimization
  ComponentFacadeFactory? _cachedFactory;

  int _archetypeIndex = 0;
  int _entityIndex = 0;
  int _lastInitializedArchetypeIndex = -1;
  (WorldEntityExtension, TExt)? _current;

  @override
  (WorldEntityExtension, TExt) get current {
    if (_current == null) {
      throw IteratorNotReadyError(
        'Extension type query iterator (1 component)',
      );
    }
    return _current!;
  }

  @override
  bool moveNext() {
    while (_archetypeIndex < _archetypes.length) {
      final archetype = _archetypes[_archetypeIndex];
      final column1 = archetype.getColumn(_id1);

      if (column1 != null && _entityIndex < column1.length) {
        // Cache factory when entering new archetype
        if (_archetypeIndex != _lastInitializedArchetypeIndex) {
          _cachedFactory = _world.components.componentFacadeRegistry.getFactory(
            _id1,
          );
          _cachedFactory = _world.components.componentFacadeRegistry
              .initializeColumn(_id1, column1);
          _lastInitializedArchetypeIndex = _archetypeIndex;
        }

        final entity = archetype.entities[_entityIndex];
        final (entityExtension, isValid) = _world.getEntityExtensionFast(
          entity,
        );
        if (!isValid) {
          _entityIndex++;
          continue;
        }

        // Get component: Use cached factory (no HashMap lookup)
        final component1 = _cachedFactory!.create(_entityIndex) as TExt;

        _current = (entityExtension, component1);
        _entityIndex++;
        return true;
      }

      _archetypeIndex++;
      _entityIndex = 0;
    }

    _current = null;
    return false;
  }
}

/// Iterator for extension type queries with predicate filtering.
/// Returns (WorldEntityExtension, ExtensionType) tuples.
class _QueryIteratorExt1Where<TComp extends Component, TExt>
    implements Iterator<(WorldEntityExtension, TExt)> {
  _QueryIteratorExt1Where(
    this.archetypes,
    this.componentId,
    this.world,
    this.predicate,
  );

  final List<Archetype> archetypes;
  final ComponentId componentId;
  final World world;
  final ExtensionPredicate<TExt> predicate;

  int archetypeIndex = 0;
  int entityIndex = -1;
  (WorldEntityExtension, TExt)? _current;

  @override
  (WorldEntityExtension, TExt) get current => _current!;

  @override
  bool moveNext() {
    while (archetypeIndex < archetypes.length) {
      final archetype = archetypes[archetypeIndex];
      final column = archetype.getColumn(componentId);

      if (column == null) {
        archetypeIndex++;
        entityIndex = -1;
        continue;
      }

      while (entityIndex < archetype.entityCount - 1) {
        entityIndex++;
        final entity = archetype.entities[entityIndex];
        final (entityExtension, isValid) = world.getEntityExtensionFast(entity);
        if (!isValid) {
          continue;
        }

        final extensionType = world.components.componentFacadeRegistry
            .createFacade<TExt>(componentId, entityIndex, column);

        if (predicate(extensionType)) {
          _current = (entityExtension, extensionType);
          return true;
        }
      }

      // Move to next archetype
      archetypeIndex++;
      entityIndex = -1;
    }

    _current = null;
    return false;
  }
}

/// Iterator for extension type queries with two component types.
/// Returns (WorldEntityExtension, ExtensionType1, ExtensionType2) tuples.
class _QueryIteratorExt2<
  TComp extends Component,
  TExt,
  T2Comp extends Component,
  T2Ext
>
    implements Iterator<(WorldEntityExtension, TExt, T2Ext)> {
  _QueryIteratorExt2(this._archetypes, this._id1, this._id2, this._world);

  final List<Archetype> _archetypes;
  final ComponentId _id1;
  final ComponentId _id2;
  final World _world;

  // Cached factories for performance optimization
  ComponentFacadeFactory? _cachedFactory1;
  ComponentFacadeFactory? _cachedFactory2;

  int _archetypeIndex = 0;
  int _entityIndex = 0;
  int _lastInitializedArchetypeIndex = -1;
  (WorldEntityExtension, TExt, T2Ext)? _current;

  @override
  (WorldEntityExtension, TExt, T2Ext) get current {
    if (_current == null) {
      throw IteratorNotReadyError(
        'Extension type query iterator (2 components)',
      );
    }
    return _current!;
  }

  @override
  bool moveNext() {
    while (_archetypeIndex < _archetypes.length) {
      final archetype = _archetypes[_archetypeIndex];
      final column1 = archetype.getColumn(_id1);
      final column2 = archetype.getColumn(_id2);

      if (column1 != null &&
          column2 != null &&
          _entityIndex < column1.length &&
          _entityIndex < column2.length) {
        // Cache factories when entering new archetype
        if (_archetypeIndex != _lastInitializedArchetypeIndex) {
          _cachedFactory1 = _world.components.componentFacadeRegistry
              .getFactory(_id1);
          _cachedFactory2 = _world.components.componentFacadeRegistry
              .getFactory(_id2);
          // Re-fetch factories after initializeColumn in case they were auto-generated for ObjectColumn
          _cachedFactory1 = _world.components.componentFacadeRegistry
              .initializeColumn(_id1, column1);
          _cachedFactory2 = _world.components.componentFacadeRegistry
              .initializeColumn(_id2, column2);
          _lastInitializedArchetypeIndex = _archetypeIndex;
        }

        final entity = archetype.entities[_entityIndex];
        final (entityExtension, isValid) = _world.getEntityExtensionFast(
          entity,
        );
        if (!isValid) {
          _entityIndex++;
          continue;
        }

        // Get components: Use cached factories (no HashMap lookup)
        final component1 = _cachedFactory1!.create(_entityIndex) as TExt;
        final component2 = _cachedFactory2!.create(_entityIndex) as T2Ext;

        _current = (entityExtension, component1, component2);
        _entityIndex++;
        return true;
      }

      _archetypeIndex++;
      _entityIndex = 0;
    }

    _current = null;
    return false;
  }
}

/// Iterator for extension type queries with two components and predicate filtering.
/// Returns (WorldEntityExtension, ExtensionType1, ExtensionType2) tuples.
class _QueryIteratorExt2WhereIterator<
  TComp extends Component,
  TExt,
  T2Comp extends Component,
  T2Ext
>
    implements Iterator<(WorldEntityExtension, TExt, T2Ext)> {
  _QueryIteratorExt2WhereIterator(
    this.archetypes,
    this.componentId1,
    this.componentId2,
    this.world,
    this.predicate,
  );

  final List<Archetype> archetypes;
  final ComponentId componentId1;
  final ComponentId componentId2;
  final World world;
  final ExtensionPredicate<TExt> predicate;

  int archetypeIndex = 0;
  int entityIndex = -1;
  (WorldEntityExtension, TExt, T2Ext)? _current;

  @override
  (WorldEntityExtension, TExt, T2Ext) get current => _current!;

  @override
  bool moveNext() {
    while (archetypeIndex < archetypes.length) {
      final archetype = archetypes[archetypeIndex];
      final column1 = archetype.getColumn(componentId1);
      final column2 = archetype.getColumn(componentId2);

      if (column1 == null || column2 == null) {
        archetypeIndex++;
        entityIndex = -1;
        continue;
      }

      while (entityIndex < archetype.entityCount - 1) {
        entityIndex++;
        final entity = archetype.entities[entityIndex];
        final (entityExtension, isValid) = world.getEntityExtensionFast(entity);
        if (!isValid) {
          continue;
        }

        final extensionType1 = world.components.componentFacadeRegistry
            .createFacade<TExt>(componentId1, entityIndex, column1);

        if (predicate(extensionType1)) {
          final extensionType2 = world.components.componentFacadeRegistry
              .createFacade<T2Ext>(componentId2, entityIndex, column2);
          _current = (entityExtension, extensionType1, extensionType2);
          return true;
        }
      }

      // Move to next archetype
      archetypeIndex++;
      entityIndex = -1;
    }

    _current = null;
    return false;
  }
}

/// Iterator for extension type queries with three component types.
/// Returns (WorldEntityExtension, ExtensionType1, ExtensionType2, ExtensionType3) tuples.
class _QueryIteratorExt3<
  TComp extends Component,
  TExt,
  T2Comp extends Component,
  T2Ext,
  T3Comp extends Component,
  T3Ext
>
    implements Iterator<(WorldEntityExtension, TExt, T2Ext, T3Ext)> {
  _QueryIteratorExt3(
    this._archetypes,
    this._id1,
    this._id2,
    this._id3,
    this._world,
  );

  final List<Archetype> _archetypes;
  final ComponentId _id1;
  final ComponentId _id2;
  final ComponentId _id3;
  final World _world;

  // Cached factories for performance optimization
  ComponentFacadeFactory? _cachedFactory1, _cachedFactory2, _cachedFactory3;

  int _archetypeIndex = 0;
  int _entityIndex = 0;
  int _lastInitializedArchetypeIndex = -1;
  (WorldEntityExtension, TExt, T2Ext, T3Ext)? _current;

  @override
  (WorldEntityExtension, TExt, T2Ext, T3Ext) get current {
    if (_current == null) {
      throw IteratorNotReadyError(
        'Extension type query iterator (3 components)',
      );
    }
    return _current!;
  }

  @override
  bool moveNext() {
    while (_archetypeIndex < _archetypes.length) {
      final archetype = _archetypes[_archetypeIndex];
      final column1 = archetype.getColumn(_id1);
      final column2 = archetype.getColumn(_id2);
      final column3 = archetype.getColumn(_id3);

      if (column1 != null &&
          column2 != null &&
          column3 != null &&
          _entityIndex < column1.length &&
          _entityIndex < column2.length &&
          _entityIndex < column3.length) {
        final entity = archetype.entities[_entityIndex];
        final (entityExtension, isValid) = _world.getEntityExtensionFast(
          entity,
        );
        if (!isValid) {
          _entityIndex++;
          continue;
        }

        // Initialize columns only when switching to a new archetype
        if (_archetypeIndex != _lastInitializedArchetypeIndex) {
          _cachedFactory1 = _world.components.componentFacadeRegistry
              .getFactory(_id1);
          _cachedFactory2 = _world.components.componentFacadeRegistry
              .getFactory(_id2);
          _cachedFactory3 = _world.components.componentFacadeRegistry
              .getFactory(_id3);
          // Re-fetch factories after initializeColumn in case they were auto-generated for ObjectColumn
          _cachedFactory1 = _world.components.componentFacadeRegistry
              .initializeColumn(_id1, column1);
          _cachedFactory2 = _world.components.componentFacadeRegistry
              .initializeColumn(_id2, column2);
          _cachedFactory3 = _world.components.componentFacadeRegistry
              .initializeColumn(_id3, column3);

          _lastInitializedArchetypeIndex = _archetypeIndex;
        }

        // Get components: Factory pattern handles both extension types and ObjectColumns
        final component1 = _cachedFactory1!.create(_entityIndex) as TExt;
        final component2 = _cachedFactory2!.create(_entityIndex) as T2Ext;
        final component3 = _cachedFactory3!.create(_entityIndex) as T3Ext;

        _current = (entityExtension, component1, component2, component3);
        _entityIndex++;
        return true;
      }

      _archetypeIndex++;
      _entityIndex = 0;
    }

    _current = null;
    return false;
  }
}

/// Iterator for extension type queries with four component types.
/// Returns (WorldEntityExtension, ExtensionType1, ExtensionType2, ExtensionType3, ExtensionType4) tuples.
class _QueryIteratorExt4<
  TComp extends Component,
  TExt,
  T2Comp extends Component,
  T2Ext,
  T3Comp extends Component,
  T3Ext,
  T4Comp extends Component,
  T4Ext
>
    implements Iterator<(WorldEntityExtension, TExt, T2Ext, T3Ext, T4Ext)> {
  _QueryIteratorExt4(
    this._archetypes,
    this._id1,
    this._id2,
    this._id3,
    this._id4,
    this._world,
  );

  final List<Archetype> _archetypes;
  final ComponentId _id1;
  final ComponentId _id2;
  final ComponentId _id3;
  final ComponentId _id4;
  final World _world;

  int _archetypeIndex = 0;
  int _entityIndex = 0;
  int _lastInitializedArchetypeIndex = -1;
  ComponentFacadeFactory? _cachedFactory1,
      _cachedFactory2,
      _cachedFactory3,
      _cachedFactory4;
  (WorldEntityExtension, TExt, T2Ext, T3Ext, T4Ext)? _current;

  @override
  (WorldEntityExtension, TExt, T2Ext, T3Ext, T4Ext) get current {
    if (_current == null) {
      throw IteratorNotReadyError(
        'Extension type query iterator (4 components)',
      );
    }
    return _current!;
  }

  @override
  bool moveNext() {
    while (_archetypeIndex < _archetypes.length) {
      final archetype = _archetypes[_archetypeIndex];
      final column1 = archetype.getColumn(_id1);
      final column2 = archetype.getColumn(_id2);
      final column3 = archetype.getColumn(_id3);
      final column4 = archetype.getColumn(_id4);

      if (column1 != null &&
          column2 != null &&
          column3 != null &&
          column4 != null &&
          _entityIndex < column1.length &&
          _entityIndex < column2.length &&
          _entityIndex < column3.length &&
          _entityIndex < column4.length) {
        final entity = archetype.entities[_entityIndex];
        final (entityExtension, isValid) = _world.getEntityExtensionFast(
          entity,
        );
        if (!isValid) {
          _entityIndex++;
          continue;
        }

        // Initialize columns only when switching to a new archetype
        if (_archetypeIndex != _lastInitializedArchetypeIndex) {
          _cachedFactory1 = _world.components.componentFacadeRegistry
              .getFactory(_id1);
          _cachedFactory2 = _world.components.componentFacadeRegistry
              .getFactory(_id2);
          _cachedFactory3 = _world.components.componentFacadeRegistry
              .getFactory(_id3);
          _cachedFactory4 = _world.components.componentFacadeRegistry
              .getFactory(_id4);
          // Re-fetch factories after initializeColumn in case they were auto-generated for ObjectColumn
          _cachedFactory1 = _world.components.componentFacadeRegistry
              .initializeColumn(_id1, column1);
          _cachedFactory2 = _world.components.componentFacadeRegistry
              .initializeColumn(_id2, column2);
          _cachedFactory3 = _world.components.componentFacadeRegistry
              .initializeColumn(_id3, column3);
          _cachedFactory4 = _world.components.componentFacadeRegistry
              .initializeColumn(_id4, column4);

          _lastInitializedArchetypeIndex = _archetypeIndex;
        }

        // Get components: Factory pattern handles both extension types and ObjectColumns
        final component1 = _cachedFactory1!.create(_entityIndex) as TExt;
        final component2 = _cachedFactory2!.create(_entityIndex) as T2Ext;
        final component3 = _cachedFactory3!.create(_entityIndex) as T3Ext;
        final component4 = _cachedFactory4!.create(_entityIndex) as T4Ext;

        _current = (
          entityExtension,
          component1,
          component2,
          component3,
          component4,
        );
        _entityIndex++;
        return true;
      }

      _archetypeIndex++;
      _entityIndex = 0;
    }

    _current = null;
    return false;
  }
}

/// Internal iterator for mutable queries with a single component.
class _QueryIteratorMut1<T extends Component>
    implements Iterator<(WorldEntityMut, T)> {
  _QueryIteratorMut1(this._archetypes, this._componentId, this._world);
  final List<Archetype> _archetypes;
  final ComponentId _componentId;
  final World _world;
  late ComponentFacadeFactory? _cachedFactory;

  int _archetypeIndex = 0;
  int _entityIndex = 0;
  int _lastInitializedArchetypeIndex = -1;
  (WorldEntityMut, T)? _current;

  @override
  (WorldEntityMut, T) get current {
    if (_current == null) {
      throw IteratorNotReadyError('Mutable query iterator (1 component)');
    }
    return _current!;
  }

  @override
  bool moveNext() {
    while (_archetypeIndex < _archetypes.length) {
      final archetype = _archetypes[_archetypeIndex];
      final column = archetype.getColumn(_componentId);
      if (column == null || _entityIndex >= column.length) {
        _archetypeIndex++;
        _entityIndex = 0;
        continue;
      }

      if (_archetypeIndex != _lastInitializedArchetypeIndex) {
        _cachedFactory = _world.components.componentFacadeRegistry
            .initializeColumn(_componentId, column);
        _lastInitializedArchetypeIndex = _archetypeIndex;
      }

      final entity = archetype.entities[_entityIndex];
      if (!_world.entities.isAlive(entity)) {
        _entityIndex++;
        continue;
      }

      final location = _world.entities.getLocation(entity);
      if (location.archetypeId != archetype.archetypeId ||
          location.archetypeRow != _entityIndex) {
        _entityIndex++;
        continue;
      }

      final worldEntity = WorldEntity(
        world: _world,
        entity: entity,
        location: location,
      );
      final entityMut = WorldEntityMut(worldEntity);
      final component = _cachedFactory!.create(_entityIndex) as T;

      _current = (entityMut, component);
      _entityIndex++;
      return true;
    }

    _current = null;
    return false;
  }
}

/// Internal iterator for mutable queries with two components.
class _QueryIteratorMut2<T1 extends Component, T2 extends Component>
    implements Iterator<(WorldEntityMut, T1, T2)> {
  _QueryIteratorMut2(this._archetypes, this._id1, this._id2, this._world);
  final List<Archetype> _archetypes;
  final ComponentId _id1;
  final ComponentId _id2;
  final World _world;
  late ComponentFacadeFactory? _cachedFactory1;
  late ComponentFacadeFactory? _cachedFactory2;

  int _archetypeIndex = 0;
  int _entityIndex = 0;
  int _lastInitializedArchetypeIndex = -1;
  (WorldEntityMut, T1, T2)? _current;

  @override
  (WorldEntityMut, T1, T2) get current {
    if (_current == null) {
      throw IteratorNotReadyError('Mutable query iterator (2 components)');
    }
    return _current!;
  }

  @override
  bool moveNext() {
    while (_archetypeIndex < _archetypes.length) {
      final archetype = _archetypes[_archetypeIndex];
      final column1 = archetype.getColumn(_id1);
      final column2 = archetype.getColumn(_id2);
      if (column1 == null ||
          column2 == null ||
          _entityIndex >= column1.length ||
          _entityIndex >= column2.length) {
        _archetypeIndex++;
        _entityIndex = 0;
        continue;
      }

      if (_archetypeIndex != _lastInitializedArchetypeIndex) {
        _cachedFactory1 = _world.components.componentFacadeRegistry
            .initializeColumn(_id1, column1);
        _cachedFactory2 = _world.components.componentFacadeRegistry
            .initializeColumn(_id2, column2);
        _lastInitializedArchetypeIndex = _archetypeIndex;
      }

      final entity = archetype.entities[_entityIndex];
      if (!_world.entities.isAlive(entity)) {
        _entityIndex++;
        continue;
      }

      final location = _world.entities.getLocation(entity);
      if (location.archetypeId != archetype.archetypeId ||
          location.archetypeRow != _entityIndex) {
        _entityIndex++;
        continue;
      }

      final entityMut = WorldEntityMut(
        WorldEntity(world: _world, entity: entity, location: location),
      );
      final component1 = _cachedFactory1!.create(_entityIndex) as T1;
      final component2 = _cachedFactory2!.create(_entityIndex) as T2;
      _current = (entityMut, component1, component2);
      _entityIndex++;
      return true;
    }

    _current = null;
    return false;
  }
}

/// Internal iterator for mutable queries with three components.
class _QueryIteratorMut3<
  T1 extends Component,
  T2 extends Component,
  T3 extends Component
>
    implements Iterator<(WorldEntityMut, T1, T2, T3)> {
  _QueryIteratorMut3(
    this._archetypes,
    this._id1,
    this._id2,
    this._id3,
    this._world,
  );
  final List<Archetype> _archetypes;
  final ComponentId _id1, _id2, _id3;
  final World _world;
  late ComponentFacadeFactory? _cachedFactory1;
  late ComponentFacadeFactory? _cachedFactory2;
  late ComponentFacadeFactory? _cachedFactory3;

  int _archetypeIndex = 0;
  int _entityIndex = 0;
  int _lastInitializedArchetypeIndex = -1;
  (WorldEntityMut, T1, T2, T3)? _current;

  @override
  (WorldEntityMut, T1, T2, T3) get current {
    if (_current == null) {
      throw IteratorNotReadyError('Mutable query iterator (3 components)');
    }
    return _current!;
  }

  @override
  bool moveNext() {
    while (_archetypeIndex < _archetypes.length) {
      final archetype = _archetypes[_archetypeIndex];
      final column1 = archetype.getColumn(_id1);
      final column2 = archetype.getColumn(_id2);
      final column3 = archetype.getColumn(_id3);
      if (column1 == null ||
          column2 == null ||
          column3 == null ||
          _entityIndex >= column1.length ||
          _entityIndex >= column2.length ||
          _entityIndex >= column3.length) {
        _archetypeIndex++;
        _entityIndex = 0;
        continue;
      }

      if (_archetypeIndex != _lastInitializedArchetypeIndex) {
        _cachedFactory1 = _world.components.componentFacadeRegistry
            .initializeColumn(_id1, column1);
        _cachedFactory2 = _world.components.componentFacadeRegistry
            .initializeColumn(_id2, column2);
        _cachedFactory3 = _world.components.componentFacadeRegistry
            .initializeColumn(_id3, column3);
        _lastInitializedArchetypeIndex = _archetypeIndex;
      }

      final entity = archetype.entities[_entityIndex];
      if (!_world.entities.isAlive(entity)) {
        _entityIndex++;
        continue;
      }

      final location = _world.entities.getLocation(entity);
      if (location.archetypeId != archetype.archetypeId ||
          location.archetypeRow != _entityIndex) {
        _entityIndex++;
        continue;
      }

      final entityMut = WorldEntityMut(
        WorldEntity(world: _world, entity: entity, location: location),
      );
      final component1 = _cachedFactory1!.create(_entityIndex) as T1;
      final component2 = _cachedFactory2!.create(_entityIndex) as T2;
      final component3 = _cachedFactory3!.create(_entityIndex) as T3;
      _current = (entityMut, component1, component2, component3);
      _entityIndex++;
      return true;
    }

    _current = null;
    return false;
  }
}

/// Internal iterator for mutable queries with four components.
class _QueryIteratorMut4<
  T1 extends Component,
  T2 extends Component,
  T3 extends Component,
  T4 extends Component
>
    implements Iterator<(WorldEntityMut, T1, T2, T3, T4)> {
  _QueryIteratorMut4(
    this._archetypes,
    this._id1,
    this._id2,
    this._id3,
    this._id4,
    this._world,
  );
  final List<Archetype> _archetypes;
  final ComponentId _id1, _id2, _id3, _id4;
  final World _world;
  late ComponentFacadeFactory? _cachedFactory1;
  late ComponentFacadeFactory? _cachedFactory2;
  late ComponentFacadeFactory? _cachedFactory3;
  late ComponentFacadeFactory? _cachedFactory4;

  int _archetypeIndex = 0;
  int _entityIndex = 0;
  int _lastInitializedArchetypeIndex = -1;
  (WorldEntityMut, T1, T2, T3, T4)? _current;

  @override
  (WorldEntityMut, T1, T2, T3, T4) get current {
    if (_current == null) {
      throw IteratorNotReadyError('Mutable query iterator (4 components)');
    }
    return _current!;
  }

  @override
  bool moveNext() {
    while (_archetypeIndex < _archetypes.length) {
      final archetype = _archetypes[_archetypeIndex];
      final column1 = archetype.getColumn(_id1);
      final column2 = archetype.getColumn(_id2);
      final column3 = archetype.getColumn(_id3);
      final column4 = archetype.getColumn(_id4);
      if (column1 == null ||
          column2 == null ||
          column3 == null ||
          column4 == null ||
          _entityIndex >= column1.length ||
          _entityIndex >= column2.length ||
          _entityIndex >= column3.length ||
          _entityIndex >= column4.length) {
        _archetypeIndex++;
        _entityIndex = 0;
        continue;
      }

      if (_archetypeIndex != _lastInitializedArchetypeIndex) {
        _cachedFactory1 = _world.components.componentFacadeRegistry
            .initializeColumn(_id1, column1);
        _cachedFactory2 = _world.components.componentFacadeRegistry
            .initializeColumn(_id2, column2);
        _cachedFactory3 = _world.components.componentFacadeRegistry
            .initializeColumn(_id3, column3);
        _cachedFactory4 = _world.components.componentFacadeRegistry
            .initializeColumn(_id4, column4);
        _lastInitializedArchetypeIndex = _archetypeIndex;
      }

      final entity = archetype.entities[_entityIndex];
      if (!_world.entities.isAlive(entity)) {
        _entityIndex++;
        continue;
      }

      final location = _world.entities.getLocation(entity);
      if (location.archetypeId != archetype.archetypeId ||
          location.archetypeRow != _entityIndex) {
        _entityIndex++;
        continue;
      }

      final entityMut = WorldEntityMut(
        WorldEntity(world: _world, entity: entity, location: location),
      );
      final component1 = _cachedFactory1!.create(_entityIndex) as T1;
      final component2 = _cachedFactory2!.create(_entityIndex) as T2;
      final component3 = _cachedFactory3!.create(_entityIndex) as T3;
      final component4 = _cachedFactory4!.create(_entityIndex) as T4;
      _current = (entityMut, component1, component2, component3, component4);
      _entityIndex++;
      return true;
    }

    _current = null;
    return false;
  }
}

/// Iterator for raw extension type queries with two component types.
///
/// Returns (Entity, ExtensionType1, ExtensionType2) tuples without wrappers.
class _QueryIteratorRawExt2<
  TComp extends Component,
  TExt,
  T2Comp extends Component,
  T2Ext
>
    implements Iterator<(Entity, TExt, T2Ext)> {
  _QueryIteratorRawExt2(this._archetypes, this._id1, this._id2, this._world);

  final List<Archetype> _archetypes;
  final ComponentId _id1;
  final ComponentId _id2;
  final World _world;

  late ComponentFacadeFactory? _cachedFactory1;
  late ComponentFacadeFactory? _cachedFactory2;

  int _archetypeIndex = 0;
  int _entityIndex = 0;
  int _lastInitializedArchetypeIndex = -1;
  (Entity, TExt, T2Ext)? _current;

  @override
  (Entity, TExt, T2Ext) get current {
    if (_current == null) {
      throw IteratorNotReadyError(
        'Raw extension type query iterator (2 components)',
      );
    }
    return _current!;
  }

  @override
  bool moveNext() {
    while (_archetypeIndex < _archetypes.length) {
      final archetype = _archetypes[_archetypeIndex];
      final column1 = archetype.getColumn(_id1);
      final column2 = archetype.getColumn(_id2);

      if (column1 != null &&
          column2 != null &&
          _entityIndex < column1.length &&
          _entityIndex < column2.length) {
        if (_archetypeIndex != _lastInitializedArchetypeIndex) {
          _cachedFactory1 = _world.components.componentFacadeRegistry
              .initializeColumn(_id1, column1);
          _cachedFactory2 = _world.components.componentFacadeRegistry
              .initializeColumn(_id2, column2);
          _lastInitializedArchetypeIndex = _archetypeIndex;
        }

        final entity = archetype.entities[_entityIndex];
        final component1 = _cachedFactory1!.create(_entityIndex) as TExt;
        final component2 = _cachedFactory2!.create(_entityIndex) as T2Ext;

        _current = (entity, component1, component2);
        _entityIndex++;
        return true;
      }

      _archetypeIndex++;
      _entityIndex = 0;
    }

    _current = null;
    return false;
  }
}
