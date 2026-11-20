import 'package:ecsly/ecsly.dart';
import 'package:ecsly_serialization/ecsly_serialization.dart';

///
/// Kept local so the plugin tests don't depend on core test helpers.

class PositionComponent extends Component {
  const PositionComponent();
}

extension type Position._(int index) {
  static late FloatColumn _column;

  // ignore: use_setters_to_change_properties - internal column bootstrap helper
  static void _setTypedColumn(FloatColumn column) {
    _column = column;
  }

  double get x => _column.getValueUnsafe(index, 0);
  double get y => _column.getValueUnsafe(index, 1);

  set x(double value) => _column.setValue(index, 0, value);
  set y(double value) => _column.setValue(index, 1, value);
}

final class _PositionColumnFactory extends ColumnFactory {
  @override
  DataColumn createColumn(
    ComponentId componentId, {
    int initialCapacity = 8,
  }) => FloatColumn(stride: 2, initialCapacity: initialCapacity);
}

final class _PositionFacadeFactory extends ComponentFacadeFactory<Position> {
  @override
  Position create(int index) => Position._(index);

  @override
  void initialize(DataColumn column) {
    Position._setTypedColumn(column as FloatColumn);
  }
}

class HealthComponent extends Component {
  const HealthComponent();
}

extension type Health._(int index) {
  static late Uint8Column _column;

  // ignore: use_setters_to_change_properties - internal column bootstrap helper
  static void _setTypedColumn(Uint8Column column) {
    _column = column;
  }

  int get value => _column.getValue(index);

  set value(int v) => _column.setValue(index, v);
}

final class _HealthColumnFactory extends ColumnFactory {
  @override
  DataColumn createColumn(
    ComponentId componentId, {
    int initialCapacity = 8,
  }) => Uint8Column(initialCapacity: initialCapacity);
}

final class _HealthFacadeFactory extends ComponentFacadeFactory<Health> {
  @override
  Health create(int index) => Health._(index);

  @override
  void initialize(DataColumn column) {
    Health._setTypedColumn(column as Uint8Column);
  }
}

class ScoreComponent extends Component {
  const ScoreComponent();
}

extension type Score._(int index) {
  static late IntColumn _column;

  // ignore: use_setters_to_change_properties - internal column bootstrap helper
  static void _setTypedColumn(IntColumn column) {
    _column = column;
  }

  int get value => _column.getValueAt(index);

  set value(int v) => _column.setValueAt(index, v);
}

final class _ScoreColumnFactory extends ColumnFactory {
  @override
  DataColumn createColumn(
    ComponentId componentId, {
    int initialCapacity = 8,
  }) => IntColumn(initialCapacity: initialCapacity);
}

final class _ScoreFacadeFactory extends ComponentFacadeFactory<Score> {
  @override
  Score create(int index) => Score._(index);

  @override
  void initialize(DataColumn column) {
    Score._setTypedColumn(column as IntColumn);
  }
}

class NameComponent extends Component {
  const NameComponent(this.value);
  final String value;
}

/// Spawns [count] entities carrying [PersistentEntityComponent]s `1..count` plus the
/// standard component set. Returns the world flushed and ready to capture.
World buildPopulatedWorld(int count) {
  final world = buildSerializationTestWorld();
  registerPersistentEntity(world);
  for (var i = 0; i < count; i++) {
    world.spawnComponents([
      PersistentEntityComponent(PersistentEntity.sequence(i + 1)),
      const PositionComponent(),
      const HealthComponent(),
      const ScoreComponent(),
    ]);
  }
  world.flush();
  return world;
}

World buildSerializationTestWorld() {
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
  return world;
}

/// World with only Position registered (subset of the full set).
World buildPositionOnlyWorld() {
  final world = World();
  world.components.registerExtension<PositionComponent, Position>(
    columnFactory: _PositionColumnFactory(),
    facadeFactory: _PositionFacadeFactory(),
  );
  return world;
}
