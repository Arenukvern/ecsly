import 'package:ecsly/ecsly.dart';

/// Test components mirroring `core_packages/ecsly/test/_test_components.dart`.
///
/// Kept local so the plugin tests don't depend on core test helpers.

class PositionComponent extends Component {
  const PositionComponent();
}

extension type Position._(int index) {
  static late FloatColumn _column;

  // ignore: use_setters_to_change_properties - internal column bootstrap helper
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

  // ignore: use_setters_to_change_properties - internal column bootstrap helper
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

  // ignore: use_setters_to_change_properties - internal column bootstrap helper
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

class NameComponent extends Component {
  const NameComponent(this.value);
  final String value;
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
  world.components.registerObjectComponent<NameComponent>();
  return world;
}
