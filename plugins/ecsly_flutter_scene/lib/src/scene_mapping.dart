/// The declarative mapping DSL: component type → visual. Pure — consumes
/// an ecsly World through type-safe query closures (captured at
/// registration) and produces [VisualState]s. The consumer owns layout
/// (positions come from component data or a supplied layout function);
/// the adapter never arranges a graph itself.
library;

import 'package:ecsly/ecsly.dart';

import 'visual_state.dart';

/// The stored spec: a type-erased view over one [VisualSpec<T>] plus the
/// registration type (the stable half of an entity's visual key).
class _TypedSpec {
  _TypedSpec(this.type, this.query, this.read, this.visualOf, this.skip);
  final Type type;
  final List<Entity> Function(World world) query;
  final Component? Function(World world, Entity entity) read;
  final VisualState? Function(Entity entity, Component component, World world)
  visualOf;
  final bool Function(Entity entity, World world)? skip;
}

/// The declarative mapping: component type → visual.
class SceneMapping {
  final List<_TypedSpec> _specs = [];

  /// Registers (or replaces — one spec per component type) the visual
  /// for component type [T]. Type-safe: the query/read closures close
  /// over the concrete [T] here; nothing dynamic runs per frame.
  void add<T extends Component>(
    final VisualState? Function(Entity entity, T component, World world) visualOf, {
    final bool Function(Entity entity, World world)? skip,
  }) {
    _specs.removeWhere((final existing) => existing.type == T);
    _specs.add(
      _TypedSpec(
        T,
        (final world) => world.prepareQuery1<T>().entities.toList(),
        (final world, final entity) => world.getEntity(entity).$1.get<T>(),
        (final entity, final component, final world) =>
            visualOf(entity, component as T, world),
        skip,
      ),
    );
  }

  /// True while no component type is mapped.
  bool get isEmpty => _specs.isEmpty;
  /// How many component types are mapped.
  int get specCount => _specs.length;

  /// Collects the desired {key → VisualState} for [world]. Keys are
  /// stable per (spec type, entity): `'T|e<entity>'`.
  Map<String, VisualState> collect(final World world) {
    final out = <String, VisualState>{};
    for (final spec in _specs) {
      for (final entity in spec.query(world)) {
        if (spec.skip != null && spec.skip!(entity, world)) continue;
        final component = spec.read(world, entity);
        if (component == null) continue;
        final visual = spec.visualOf(entity, component, world);
        if (visual == null) continue;
        out['${spec.type}|e${entity.toJson()}'] = visual;
      }
    }
    return out;
  }
}
