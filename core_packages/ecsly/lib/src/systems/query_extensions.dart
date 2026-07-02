import '../components/component.dart';
import '../components/component_query.dart';
import '../entities/entities.dart';
import '../world/world.dart';

/// {@template world_query_extensions}
/// Type-safe query extensions for World that return Dart records.
///
/// These extensions provide ergonomic access to components using
/// the underlying [ComponentQuery] system.
///
/// **Query Patterns:**
///
/// 1. **Immutable Queries** (`query`, `query2`, etc.):
///    - Return zero-cost extension type facades (not copies) for read-only access
///    - Facades wrap TypedData indices, providing zero-allocation iteration
///    - Use with commands for structural changes (spawn/despawn/insert/remove)
///    - Suitable for extension type components (Position, Velocity, etc.)
///    - Includes [WorldEntity] wrappers, which are convenience/cold-path APIs
///      compared to the raw chunk query family (`queryRaw2/3/4`)
///
/// 2. **Mutable Queries** (`queryMut`, `queryMut2`, etc.):
///    - Return (WorldEntityMut, Component) tuples for direct in-place mutation
///    - Similar to Bevy's `&mut Component` pattern
///    - Direct mutation of stored class components (heap objects)
///    - Suitable for frequent data updates (every frame) with class components
///    - **Safety:** Only one system mutates a component type at a time (scheduler ensures this)
///
/// **Key Distinction:**
/// - **query()**: Extension type facades (zero-allocation) - use for Position, Velocity, etc.
/// - **queryMut()**: Class components (heap objects) - use for MutablePosition, MutableHP, etc.
/// - **Commands**: For structural changes (spawn/despawn/insert/remove components) - changes archetype
/// {@endtemplate}
extension WorldQueryX on World {
  /// Prepare a reusable component query from component ids.
  ///
  /// This is a warm/hot-path convenience around [ComponentQuery]. It caches the
  /// required/excluded masks and lets the existing query engine reuse matching
  /// archetype plans across iterations.
  ComponentQuery prepareQuery({
    final Iterable<ComponentId>? required,
    final Iterable<ComponentId>? excluded,
  }) => ComponentQuery(world: this, required: required, excluded: excluded);

  ComponentQuery prepareQuery1<T extends Component>() =>
      prepareQuery(required: [components.getComponentId<T>()]);

  ComponentQuery prepareQuery2<T1 extends Component, T2 extends Component>() =>
      prepareQuery(
        required: [
          components.getComponentId<T1>(),
          components.getComponentId<T2>(),
        ],
      );

  ComponentQuery prepareQuery3<
    T1 extends Component,
    T2 extends Component,
    T3 extends Component
  >() => prepareQuery(
    required: [
      components.getComponentId<T1>(),
      components.getComponentId<T2>(),
      components.getComponentId<T3>(),
    ],
  );

  ComponentQuery prepareQuery4<
    T1 extends Component,
    T2 extends Component,
    T3 extends Component,
    T4 extends Component
  >() => prepareQuery(
    required: [
      components.getComponentId<T1>(),
      components.getComponentId<T2>(),
      components.getComponentId<T3>(),
      components.getComponentId<T4>(),
    ],
  );

  /// Query entities with a single component type.
  ///
  /// Returns an iterable of (WorldEntity, Component) tuples with zero-cost extension type facades (not copies).
  /// Facades wrap TypedData indices, providing zero-allocation iteration.
  ///
  /// **Important:** Use Component class types (e.g., `PositionComponent`) for the
  /// type parameter, but the query returns extension type facades (e.g., `Position`).
  /// For ObjectColumn components, returns Component class instances.
  ///
  /// **Use for:** Extension type components (Position, Velocity, etc.)
  ///
  /// Automatically flushes pending changes before querying to ensure
  /// up-to-date results.
  ///
  /// Example:
  /// ```dart
  /// for (final (entity, posComp) in world.query<PositionComponent>()) {
  ///   final position = posComp as Position; // Cast to extension type
  ///   position.x += 1.0; // Direct mutation of TypedData via facade
  ///   entity.despawn(); // Direct entity operations available
  /// }
  /// ```
  Iterable<(WorldEntity, T)> query<T extends Component>() {
    final query = ComponentQuery(
      world: this,
      required: [components.getComponentId<T>()],
    );
    return query.iter1<T>();
  }

  /// Query entities with two component types.
  ///
  /// Returns an iterable of (WorldEntity, Component1, Component2) tuples.
  /// For extension type components, returns extension type facades.
  /// For ObjectColumn components, returns Component class instances.
  ///
  /// **Important:** Use Component class types (e.g., `PositionComponent`) for type
  /// parameters, but cast results to extension types (e.g., `Position`) when needed.
  ///
  /// Automatically flushes pending changes before querying to ensure
  /// up-to-date results.
  ///
  /// Example:
  /// ```dart
  /// for (final (entity, posComp, velComp) in world.query2<PositionComponent, VelocityComponent>()) {
  ///   final position = posComp as Position;
  ///   final velocity = velComp as Velocity;
  ///   position.x += velocity.dx;
  ///   entity.insert(Acceleration()); // Direct entity operations available
  /// }
  /// ```
  Iterable<(WorldEntity, T1, T2)>
  query2<T1 extends Component, T2 extends Component>() {
    final query = ComponentQuery(
      world: this,
      required: [
        components.getComponentId<T1>(),
        components.getComponentId<T2>(),
      ],
    );
    return query.iter2<T1, T2>();
  }

  /// Query entities with three component types.
  ///
  /// Returns an iterable of (WorldEntity, Component1, Component2, Component3) tuples.
  ///
  /// Automatically flushes pending changes before querying to ensure
  /// up-to-date results.
  Iterable<(WorldEntity, T1, T2, T3)>
  query3<T1 extends Component, T2 extends Component, T3 extends Component>() {
    final query = ComponentQuery(
      world: this,
      required: [
        components.getComponentId<T1>(),
        components.getComponentId<T2>(),
        components.getComponentId<T3>(),
      ],
    );
    return query.iter3<T1, T2, T3>();
  }

  /// Query entities with four component types.
  ///
  /// Returns an iterable of (WorldEntity, Component1, Component2, Component3, Component4) tuples.
  ///
  /// Automatically flushes pending changes before querying to ensure
  /// up-to-date results.
  Iterable<(WorldEntity, T1, T2, T3, T4)> query4<
    T1 extends Component,
    T2 extends Component,
    T3 extends Component,
    T4 extends Component
  >() {
    final query = ComponentQuery(
      world: this,
      required: [
        components.getComponentId<T1>(),
        components.getComponentId<T2>(),
        components.getComponentId<T3>(),
        components.getComponentId<T4>(),
      ],
    );
    return query.iter4<T1, T2, T3, T4>();
  }

  /// Query entities with five component types.
  ///
  /// Returns an iterable of (WorldEntity, Component1, Component2, Component3, Component4, Component5) tuples.
  ///
  /// Automatically flushes pending changes before querying to ensure
  /// up-to-date results.
  Iterable<(WorldEntity, T1, T2, T3, T4, T5)> query5<
    T1 extends Component,
    T2 extends Component,
    T3 extends Component,
    T4 extends Component,
    T5 extends Component
  >() {
    final query = ComponentQuery(
      world: this,
      required: [
        components.getComponentId<T1>(),
        components.getComponentId<T2>(),
        components.getComponentId<T3>(),
        components.getComponentId<T4>(),
        components.getComponentId<T5>(),
      ],
    );
    return query.iter5<T1, T2, T3, T4, T5>();
  }

  /// Query entities with six component types.
  ///
  /// Returns an iterable of (WorldEntity, Component1, Component2, Component3, Component4, Component5, Component6) tuples.
  ///
  /// Automatically flushes pending changes before querying to ensure
  /// up-to-date results.
  Iterable<(WorldEntity, T1, T2, T3, T4, T5, T6)> query6<
    T1 extends Component,
    T2 extends Component,
    T3 extends Component,
    T4 extends Component,
    T5 extends Component,
    T6 extends Component
  >() {
    final query = ComponentQuery(
      world: this,
      required: [
        components.getComponentId<T1>(),
        components.getComponentId<T2>(),
        components.getComponentId<T3>(),
        components.getComponentId<T4>(),
        components.getComponentId<T5>(),
        components.getComponentId<T6>(),
      ],
    );
    return query.iter6<T1, T2, T3, T4, T5, T6>();
  }

  /// Advanced query builder.
  ComponentQueryBuilder toQueryBuilder() => ComponentQueryBuilder(this);

  /// Query entities with a single component type, returning explicit extension type.
  ///
  /// Returns an iterable of (WorldEntityExtension, ExtensionType) tuples directly, eliminating the need for casting.
  /// Use Component class type for TComp and extension type for TExt.
  ///
  /// **Type Safety:** Validates extension type matches registered type at runtime.
  /// **Performance:** Zero-allocation extension type facades.
  ///
  /// Automatically flushes pending changes before querying to ensure up-to-date results.
  ///
  /// Example:
  /// ```dart
  /// for (final (entity, pos) in world.queryExt<PositionComponent, Position>()) {
  ///   pos.x += 1.0; // Direct access, no cast needed
  ///   pos.y += 2.0;
  ///   entity.create<HealthComponent, Health>(); // Direct entity operations available
  /// }
  /// ```
  Iterable<(WorldEntityExtension, TExt)>
  queryExt<TComp extends Component, TExt>() {
    final query = ComponentQuery(
      world: this,
      required: [components.getComponentId<TComp>()],
    );
    return query.iterExt1<TComp, TExt>();
  }

  /// Query entities with two component types, returning explicit extension types.
  ///
  /// Returns an iterable of (WorldEntityExtension, ExtensionType1, ExtensionType2) tuples directly,
  /// eliminating the need for casting. Use Component class types for TComp/T2Comp
  /// and extension types for TExt/Text.
  ///
  /// **Type Safety:** Validates extension types match registered types at runtime.
  /// **Performance:** Zero-allocation extension type facades.
  ///
  /// Automatically flushes pending changes before querying to ensure up-to-date results.
  ///
  /// Example:
  /// ```dart
  /// for (final (entity, pos, vel) in world.queryExt2<PositionComponent, Position, VelocityComponent, Velocity>()) {
  ///   pos.x += vel.dx; // Direct access, no cast needed
  ///   pos.y += vel.dy;
  ///   entity.insert<AccelerationComponent>(Acceleration()); // Direct entity operations available
  /// }
  /// ```
  Iterable<(WorldEntityExtension, TExt, Text)>
  queryExt2<TComp extends Component, TExt, T2Comp extends Component, Text>() {
    final query = ComponentQuery(
      world: this,
      required: [
        components.getComponentId<TComp>(),
        components.getComponentId<T2Comp>(),
      ],
    );
    return query.iterExt2<TComp, TExt, T2Comp, Text>();
  }

  /// Query entities with two component types, returning explicit extension types with conditional filtering.
  ///
  /// Returns an iterable of (WorldEntityExtension, ExtensionType1, ExtensionType2) tuples directly,
  /// eliminating the need for casting. Predicate is applied to the first extension type.
  ///
  /// **Type Safety:** Validates extension types match registered types at runtime.
  /// **Performance:** Zero-allocation extension type facades with early filtering.
  ///
  /// Automatically flushes pending changes before querying to ensure up-to-date results.
  ///
  /// Example:
  /// ```dart
  /// for (final (entity, pos, vel) in world.queryExt2Where<PositionComponent, Position, VelocityComponent, Velocity>(
  ///   (pos) => pos.x > 100
  /// )) {
  ///   // Only processes entities with position.x > 100
  ///   entity.getExtension<ArmorComponent, Armor>()?.durability -= 10; // Direct entity operations available
  /// }
  /// ```
  Iterable<(WorldEntityExtension, TExt, T2Ext)> queryExt2Where<
    TComp extends Component,
    TExt,
    T2Comp extends Component,
    T2Ext
  >(final ExtensionPredicate<TExt> predicate) {
    final query = ComponentQuery(
      world: this,
      required: [
        components.getComponentId<TComp>(),
        components.getComponentId<T2Comp>(),
      ],
    );
    return query.iterExt2Where<TComp, TExt, T2Comp, T2Ext>(predicate);
  }

  /// Query entities with three component types, returning extension type facades.
  ///
  /// Returns an iterable of (WorldEntityExtension, ExtensionType1, ExtensionType2, ExtensionType3) tuples.
  /// Use Component class types for TComp/T2Comp/T3Comp and extension types for TExt/T2Ext/T3Ext.
  ///
  /// **Type Safety:** Validates extension types match registered types at runtime.
  /// **Performance:** Direct access to stored components with zero allocation.
  ///
  /// Automatically flushes pending changes before querying to ensure up-to-date results.
  ///
  /// Example:
  /// ```dart
  /// for (final (entity, pos, vel, health) in world.queryExt3<PositionComponent, Position, VelocityComponent, Velocity, HealthComponent, Health>()) {
  ///   pos.x += vel.dx; // Direct access, no cast needed
  ///   pos.y += vel.dy;
  ///   health.value -= 1;
  ///   entity.toEntity().remove<ArmorComponent>(); // Direct entity operations available
  /// }
  /// ```
  Iterable<(WorldEntityExtension, TExt, T2Ext, T3Ext)> queryExt3<
    TComp extends Component,
    TExt,
    T2Comp extends Component,
    T2Ext,
    T3Comp extends Component,
    T3Ext
  >() {
    final query = ComponentQuery(
      world: this,
      required: [
        components.getComponentId<TComp>(),
        components.getComponentId<T2Comp>(),
        components.getComponentId<T3Comp>(),
      ],
    );
    return query.iterExt3<TComp, TExt, T2Comp, T2Ext, T3Comp, T3Ext>();
  }

  /// Query entities with four component types, returning extension type facades.
  ///
  /// Returns an iterable of (WorldEntityExtension, ExtensionType1, ExtensionType2, ExtensionType3, ExtensionType4) tuples.
  /// Use Component class types for TComp/T2Comp/T3Comp/T4Comp and extension types for TExt/T2Ext/T3Ext/T4Ext.
  ///
  /// **Type Safety:** Validates extension types match registered types at runtime.
  /// **Performance:** Direct access to stored components with zero allocation.
  ///
  /// Automatically flushes pending changes before querying to ensure up-to-date results.
  ///
  /// Example:
  /// ```dart
  /// for (final (entity, pos, vel, health, armor) in world.queryExt4<PositionComponent, Position, VelocityComponent, Velocity, HealthComponent, Health, ArmorComponent, Armor>()) {
  ///   pos.x += vel.dx; // Direct access, no cast needed
  ///   pos.y += vel.dy;
  ///   health.value -= armor.damageReduction;
  ///   entity.getExtension<InventoryComponent, Inventory>()?.addItem(item); // Direct entity operations available
  /// }
  /// ```
  Iterable<(WorldEntityExtension, TExt, T2Ext, T3Ext, T4Ext)> queryExt4<
    TComp extends Component,
    TExt,
    T2Comp extends Component,
    T2Ext,
    T3Comp extends Component,
    T3Ext,
    T4Comp extends Component,
    T4Ext
  >() {
    final query = ComponentQuery(
      world: this,
      required: [
        components.getComponentId<TComp>(),
        components.getComponentId<T2Comp>(),
        components.getComponentId<T3Comp>(),
        components.getComponentId<T4Comp>(),
      ],
    );
    return query
        .iterExt4<TComp, TExt, T2Comp, T2Ext, T3Comp, T3Ext, T4Comp, T4Ext>();
  }

  /// Query entities with a single component type, returning explicit extension type with conditional filtering.
  ///
  /// Returns an iterable of (WorldEntityExtension, ExtensionType) tuples directly, eliminating the need for casting.
  /// Predicate is applied during iteration for zero-allocation filtering.
  ///
  /// **Type Safety:** Validates extension type matches registered type at runtime.
  /// **Performance:** Zero-allocation extension type facades with early filtering.
  ///
  /// Automatically flushes pending changes before querying to ensure up-to-date results.
  ///
  /// Example:
  /// ```dart
  /// for (final (entity, hp) in world.queryExtWhere<HealthComponent, Health>(
  ///   (hp) => hp.isDead
  /// )) {
  ///   // Only processes dead entities, no manual filtering needed
  ///   entity.toEntity().despawn(); // Direct entity operations available
  /// }
  /// ```
  Iterable<(WorldEntityExtension, TExt)> queryExtWhere<
    TComp extends Component,
    TExt
  >(final ExtensionPredicate<TExt> predicate) {
    final query = ComponentQuery(
      world: this,
      required: [components.getComponentId<TComp>()],
    );
    return query.iterExt1Where<TComp, TExt>(predicate);
  }

  /// Query entities with a single component type, returning mutable references.
  ///
  /// Returns an iterable of (WorldEntityMut, Component) tuples where the component
  /// is a direct reference to the stored component, allowing in-place mutation.
  ///
  /// **Key Distinction:**
  /// - **queryMut**: For data mutation (doesn't change archetype) - direct in-place updates
  /// - **query**: For read-only access or when using commands for structural changes
  ///
  /// **Performance:** No object allocation - direct mutation of stored components.
  ///
  /// **Safety:** Only one system mutates a component type at a time (scheduler ensures this).
  ///
  /// Automatically flushes pending changes before querying to ensure up-to-date results.
  ///
  /// Example:
  /// ```dart
  /// for (final (entity, position) in world.queryMut<MutablePosition>()) {
  ///   position.x += velocity.dx * dt; // Direct mutation, no allocation
  ///   position.y += velocity.dy * dt;
  /// }
  /// ```
  Iterable<(WorldEntityMut, T)> queryMut<T extends Component>() {
    final query = ComponentQuery(
      world: this,
      required: [components.getComponentId<T>()],
    );
    return query.iterMut1<T>();
  }

  /// Query entities with two component types, returning mutable references.
  ///
  /// Returns an iterable of (WorldEntityMut, Component1, Component2) tuples where
  /// components are direct references to stored components, allowing in-place mutation.
  ///
  /// **Performance:** No object allocation - direct mutation of stored components.
  ///
  /// Automatically flushes pending changes before querying to ensure up-to-date results.
  ///
  /// Example:
  /// ```dart
  /// for (final (entity, position, velocity) in world.queryMut2<MutablePosition, MutableVelocity>()) {
  ///   position.x += velocity.dx * dt; // Direct mutation, no allocation
  ///   position.y += velocity.dy * dt;
  /// }
  /// ```
  Iterable<(WorldEntityMut, T1, T2)>
  queryMut2<T1 extends Component, T2 extends Component>() {
    final query = ComponentQuery(
      world: this,
      required: [
        components.getComponentId<T1>(),
        components.getComponentId<T2>(),
      ],
    );
    return query.iterMut2<T1, T2>();
  }

  /// Query entities with three component types, returning mutable references.
  ///
  /// Returns an iterable of (WorldEntityMut, Component1, Component2, Component3) tuples
  /// where components are direct references to stored components, allowing in-place mutation.
  ///
  /// **Performance:** No object allocation - direct mutation of stored components.
  ///
  /// Automatically flushes pending changes before querying to ensure up-to-date results.
  Iterable<(WorldEntityMut, T1, T2, T3)> queryMut3<
    T1 extends Component,
    T2 extends Component,
    T3 extends Component
  >() {
    final query = ComponentQuery(
      world: this,
      required: [
        components.getComponentId<T1>(),
        components.getComponentId<T2>(),
        components.getComponentId<T3>(),
      ],
    );
    return query.iterMut3<T1, T2, T3>();
  }

  /// Query entities with four component types, returning mutable references.
  ///
  /// Returns an iterable of (WorldEntityMut, C1, C2, C3, C4) tuples where components
  /// are direct references to stored components, allowing in-place mutation.
  ///
  /// **Performance:** No object allocation - direct mutation of stored components.
  ///
  /// Automatically flushes pending changes before querying to ensure up-to-date results.
  Iterable<(WorldEntityMut, T1, T2, T3, T4)> queryMut4<
    T1 extends Component,
    T2 extends Component,
    T3 extends Component,
    T4 extends Component
  >() {
    final query = ComponentQuery(
      world: this,
      required: [
        components.getComponentId<T1>(),
        components.getComponentId<T2>(),
        components.getComponentId<T3>(),
        components.getComponentId<T4>(),
      ],
    );
    return query.iterMut4<T1, T2, T3, T4>();
  }

  /// Query entities with two component types, returning raw entity IDs plus extension facades.
  ///
  /// Returns (Entity, ExtensionType1, ExtensionType2) tuples.
  /// This is intended for very hot systems that do not need WorldEntity wrappers.
  Iterable<(Entity, TExt, T2Ext)> queryRawExt2<
    TComp extends Component,
    TExt,
    T2Comp extends Component,
    T2Ext
  >() {
    final query = ComponentQuery(
      world: this,
      required: [
        components.getComponentId<TComp>(),
        components.getComponentId<T2Comp>(),
      ],
    );
    return query.iterRawExt2<TComp, TExt, T2Comp, T2Ext>();
  }

  /// Query chunks for two components in a raw hot-path form.
  ///
  /// Each chunk provides typed column views + row count and supports
  /// index-based loops without per-row wrapper records.
  Iterable<RawQueryChunk2<TExt, T2Ext>>
  queryRaw2<TComp extends Component, TExt, T2Comp extends Component, T2Ext>() {
    final query = ComponentQuery(
      world: this,
      required: [
        components.getComponentId<TComp>(),
        components.getComponentId<T2Comp>(),
      ],
    );
    return query.iterRaw2<TComp, TExt, T2Comp, T2Ext>();
  }

  /// Query chunks for three components in a raw hot-path form.
  Iterable<RawQueryChunk3<TExt, T2Ext, T3Ext>> queryRaw3<
    TComp extends Component,
    TExt,
    T2Comp extends Component,
    T2Ext,
    T3Comp extends Component,
    T3Ext
  >() {
    final query = ComponentQuery(
      world: this,
      required: [
        components.getComponentId<TComp>(),
        components.getComponentId<T2Comp>(),
        components.getComponentId<T3Comp>(),
      ],
    );
    return query.iterRaw3<TComp, TExt, T2Comp, T2Ext, T3Comp, T3Ext>();
  }

  /// Query chunks for four components in a raw hot-path form.
  Iterable<RawQueryChunk4<TExt, T2Ext, T3Ext, T4Ext>> queryRaw4<
    TComp extends Component,
    TExt,
    T2Comp extends Component,
    T2Ext,
    T3Comp extends Component,
    T3Ext,
    T4Comp extends Component,
    T4Ext
  >() {
    final query = ComponentQuery(
      world: this,
      required: [
        components.getComponentId<TComp>(),
        components.getComponentId<T2Comp>(),
        components.getComponentId<T3Comp>(),
        components.getComponentId<T4Comp>(),
      ],
    );
    return query
        .iterRaw4<TComp, TExt, T2Comp, T2Ext, T3Comp, T3Ext, T4Comp, T4Ext>();
  }

  /// Count matching entities for one component without materializing entities.
  int queryCount<TComp extends Component>() {
    final query = ComponentQuery(
      world: this,
      required: [components.getComponentId<TComp>()],
    );
    return query.count();
  }

  /// Count matching entities for two components without materializing entities.
  int queryCount2<T1 extends Component, T2 extends Component>() {
    final query = ComponentQuery(
      world: this,
      required: [
        components.getComponentId<T1>(),
        components.getComponentId<T2>(),
      ],
    );
    return query.count();
  }

  /// Count matching entities for three components without materializing entities.
  int queryCount3<
    T1 extends Component,
    T2 extends Component,
    T3 extends Component
  >() {
    final query = ComponentQuery(
      world: this,
      required: [
        components.getComponentId<T1>(),
        components.getComponentId<T2>(),
        components.getComponentId<T3>(),
      ],
    );
    return query.count();
  }

  /// Count matching entities for four components without materializing entities.
  int queryCount4<
    T1 extends Component,
    T2 extends Component,
    T3 extends Component,
    T4 extends Component
  >() {
    final query = ComponentQuery(
      world: this,
      required: [
        components.getComponentId<T1>(),
        components.getComponentId<T2>(),
        components.getComponentId<T3>(),
        components.getComponentId<T4>(),
      ],
    );
    return query.count();
  }

  /// Fast existence check for one component without materializing entities.
  bool queryAny<TComp extends Component>() {
    final query = ComponentQuery(
      world: this,
      required: [components.getComponentId<TComp>()],
    );
    return query.any();
  }

  /// Fast existence check for two components without materializing entities.
  bool queryAny2<T1 extends Component, T2 extends Component>() {
    final query = ComponentQuery(
      world: this,
      required: [
        components.getComponentId<T1>(),
        components.getComponentId<T2>(),
      ],
    );
    return query.any();
  }

  /// Fast existence check for three components without materializing entities.
  bool queryAny3<
    T1 extends Component,
    T2 extends Component,
    T3 extends Component
  >() {
    final query = ComponentQuery(
      world: this,
      required: [
        components.getComponentId<T1>(),
        components.getComponentId<T2>(),
        components.getComponentId<T3>(),
      ],
    );
    return query.any();
  }

  /// Fast existence check for four components without materializing entities.
  bool queryAny4<
    T1 extends Component,
    T2 extends Component,
    T3 extends Component,
    T4 extends Component
  >() {
    final query = ComponentQuery(
      world: this,
      required: [
        components.getComponentId<T1>(),
        components.getComponentId<T2>(),
        components.getComponentId<T3>(),
        components.getComponentId<T4>(),
      ],
    );
    return query.any();
  }
}
