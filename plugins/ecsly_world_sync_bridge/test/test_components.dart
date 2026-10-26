import 'package:ecsly/ecsly.dart';
import 'package:ecsly_serialization/ecsly_serialization.dart';

/// Test components and world builders for the bridge tests.
///
/// Kept local (mirrors `ecsly_serialization`'s test components) so this
/// package's tests do not depend on other packages' test helpers. Writes and
/// reads go through archetype columns directly — the extension-type facades
/// bind columns through statics, which is unsafe with two live worlds in
/// one test.

class PositionComponent extends Component {
  const PositionComponent();
}

extension type Position._(int index) {
  static late FloatColumn _column;

  // ignore: use_setters_to_change_properties - internal column bootstrap
  static void _setTypedColumn(final FloatColumn column) {
    _column = column;
  }

  double get x => _column.getValueUnsafe(index, 0);
  double get y => _column.getValueUnsafe(index, 1);

  set x(final double value) => _column.setValue(index, 0, value);
  set y(final double value) => _column.setValue(index, 1, value);
}

final class _PositionColumnFactory extends ColumnFactory {
  @override
  DataColumn createColumn(
    final ComponentId componentId, {
    final int initialCapacity = 8,
  }) => FloatColumn(stride: 2, initialCapacity: initialCapacity);
}

final class _PositionFacadeFactory extends ComponentFacadeFactory<Position> {
  @override
  Position create(final int index) => Position._(index);

  @override
  void initialize(final DataColumn column) {
    Position._setTypedColumn(column as FloatColumn);
  }
}

class HealthComponent extends Component {
  const HealthComponent();
}

extension type Health._(int index) {
  static late Uint8Column _column;

  // ignore: use_setters_to_change_properties - internal column bootstrap
  static void _setTypedColumn(final Uint8Column column) {
    _column = column;
  }

  int get value => _column.getValue(index);

  set value(final int v) => _column.setValue(index, v);
}

final class _HealthColumnFactory extends ColumnFactory {
  @override
  DataColumn createColumn(
    final ComponentId componentId, {
    final int initialCapacity = 8,
  }) => Uint8Column(initialCapacity: initialCapacity);
}

final class _HealthFacadeFactory extends ComponentFacadeFactory<Health> {
  @override
  Health create(final int index) => Health._(index);

  @override
  void initialize(final DataColumn column) {
    Health._setTypedColumn(column as Uint8Column);
  }
}

class ScoreComponent extends Component {
  const ScoreComponent();
}

extension type Score._(int index) {
  static late IntColumn _column;

  // ignore: use_setters_to_change_properties - internal column bootstrap
  static void _setTypedColumn(final IntColumn column) {
    _column = column;
  }

  int get value => _column.getValueAt(index);

  set value(final int v) => _column.setValueAt(index, v);
}

final class _ScoreColumnFactory extends ColumnFactory {
  @override
  DataColumn createColumn(
    final ComponentId componentId, {
    final int initialCapacity = 8,
  }) => IntColumn(initialCapacity: initialCapacity);
}

final class _ScoreFacadeFactory extends ComponentFacadeFactory<Score> {
  @override
  Score create(final int index) => Score._(index);

  @override
  void initialize(final DataColumn column) {
    Score._setTypedColumn(column as IntColumn);
  }
}

/// Object-tier component (cold data) — captured only through a codec.
class NameComponent extends Component {
  const NameComponent(this.value);

  final String value;
}

/// JSON codec for [NameComponent] used by the object-component test.
class NameCodec extends ObjectComponentCodec<NameComponent> {
  const NameCodec();

  @override
  Object? toJson(final NameComponent component) => component.value;

  @override
  NameComponent fromJson(final Object? value) =>
      NameComponent(value as String? ?? '');
}

/// Builds a world with Position (float x2), Health (uint8), and Score (int)
/// registered, plus [PersistentId]. Does not spawn anything.
World buildTestWorld() {
  final world = World();
  world.components.registerExtension<PositionComponent, Position>(
    columnFactory: _PositionColumnFactory(),
    facadeFactory: _PositionFacadeFactory(),
  );
  world.components.registerExtension<HealthComponent, Health>(
    columnFactory: _HealthColumnFactory(),
    facadeFactory: _HealthFacadeFactory(),
  );
  world.components.registerExtension<ScoreComponent, Score>(
    columnFactory: _ScoreColumnFactory(),
    facadeFactory: _ScoreFacadeFactory(),
  );
  world.components.registerObjectComponent<NameComponent>(
    sample: const NameComponent(''),
  );
  registerPersistentId(world);
  return world;
}

/// Spawns an entity with [PersistentId] [pid] plus the given SoA components
/// and flushes. Returns the entity handle (world-local; never synced).
Entity spawnShip(
  final World world,
  final int pid, {
  final bool position = true,
  final bool health = false,
  final bool score = false,
  final NameComponent? name,
}) {
  final entity = world.spawnComponents([
    PersistentId(pid),
    if (position) const PositionComponent(),
    if (health) const HealthComponent(),
    if (score) const ScoreComponent(),
    ?name,
  ]);
  world.flush();
  return entity;
}

/// Writes one column value without extension-type facades (safe with
/// multiple live worlds).
void writeColumn(
  final World world,
  final Entity entity,
  final Type componentType,
  final int offset,
  final num value,
) {
  final (column, row) = _columnAndRow(world, entity, componentType);
  switch (column) {
    case final FloatColumn c:
      c.setValue(row, offset, value.toDouble());
    case final IntColumn c:
      c.setValue(row, offset, value.toInt());
    case final Uint8Column c:
      c.setValue(row, value.toInt());
    case final ObjectColumn _:
      throw UnsupportedError('writeColumn is for SoA columns only');
  }
}

/// Reads one column value without extension-type facades.
num readColumn(
  final World world,
  final Entity entity,
  final Type componentType,
  final int offset,
) {
  final (column, row) = _columnAndRow(world, entity, componentType);
  return switch (column) {
    final FloatColumn c => c.getValue(row, offset),
    final IntColumn c => c.getValue(row, offset),
    final Uint8Column c => c.getValue(row),
    final ObjectColumn _ => throw UnsupportedError(
      'readColumn is for SoA columns only',
    ),
  };
}

(DataColumn, int) _columnAndRow(
  final World world,
  final Entity entity,
  final Type componentType,
) {
  final componentId = world.components.getComponentIdByType(componentType)!;
  final location = world.entities.getLocation(entity);
  final archetypeIndex = world.archetypes.findArchetypeIndex(
    location.archetypeId,
  );
  final archetype = world.archetypes[archetypeIndex];
  final row = archetype.getRowIndex(entity, world.entities)!;
  return (archetype.getColumn(componentId)!, row);
}

/// Deterministic monotonic clock shared by both replicas so LWW winners are
/// decided by issue order, not actor tie-breaks.
final class TestClock {
  TestClock([final DateTime? start])
    : _next = start ?? DateTime.utc(2026, 9, 26, 12);

  DateTime _next;

  DateTime tick() => _next = _next.add(const Duration(milliseconds: 7));
}
