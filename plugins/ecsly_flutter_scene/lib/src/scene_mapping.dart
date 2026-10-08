// Parameters carry no `final`: this package compiles under language 3.13
// (where that modifier is an error) as well as 3.12.
// ignore_for_file: prefer_final_parameters

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

  /// Space-making decorations (floor rails, a horizon) derived from the
  /// world each collect — never entity data, always drawn (the scene must
  /// read as SPACE at every altitude). Keys are `static|g<index>`; the
  /// closure runs per collect, so it may read the world's layout.
  List<VisualState> Function(World world)? ground;

  /// Registers (or replaces — one spec per component type) the visual
  /// for component type [T]. Type-safe: the query/read closures close
  /// over the concrete [T] here; nothing dynamic runs per frame.
  void add<T extends Component>(
    VisualState? Function(Entity entity, T component, World world) visualOf, {
    bool Function(Entity entity, World world)? skip,
  }) {
    _specs.removeWhere((existing) => existing.type == T);
    _specs.add(
      _TypedSpec(
        T,
        (world) => world.prepareQuery1<T>().entities.toList(),
        (world, entity) => world.getEntity(entity).$1.get<T>(),
        (entity, component, world) =>
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
  /// stable per (spec type, entity): `'T|e<entity>'`; decorations are
  /// `'static|g<index>'`.
  Map<String, VisualState> collect(World world) {
    final out = <String, VisualState>{};
    final ground = this.ground;
    if (ground != null) {
      final decorations = ground(world);
      for (var i = 0; i < decorations.length; i++) {
        out['static|g$i'] = decorations[i];
      }
    }
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
