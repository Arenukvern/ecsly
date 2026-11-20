import 'package:ecsly/ecsly.dart';

/// A second, independently-registered component set with the same shapes as
/// `serialization_test_components.dart` but different type names, used to
/// build worlds whose registration order differs from the primary set.
///
/// Distinct type names are required because component identity in snapshots
/// is by type name — a "reordered" world must still use the same names to be
/// remappable. For true reorder tests we register the SAME types in a
/// different order in a fresh World (each World has its own registry), which
/// is what stability_test.dart does via [buildReorderedWorld].

class AltPositionComponent extends Component {
  const AltPositionComponent();
}

extension type AltPosition._(int index) {
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

final class _AltPositionColumnFactory extends ColumnFactory {
  @override
  DataColumn createColumn(
    ComponentId componentId, {
    int initialCapacity = 8,
  }) => FloatColumn(stride: 2, initialCapacity: initialCapacity);
}

final class _AltPositionFacadeFactory
    extends ComponentFacadeFactory<AltPosition> {
  @override
  AltPosition create(int index) => AltPosition._(index);

  @override
  void initialize(DataColumn column) {
    AltPosition._setTypedColumn(column as FloatColumn);
  }
}

class AltHealthComponent extends Component {
  const AltHealthComponent();
}

extension type AltHealth._(int index) {
  static late Uint8Column _column;

  // ignore: use_setters_to_change_properties - internal column bootstrap helper
  static void _setTypedColumn(Uint8Column column) {
    _column = column;
  }

  int get value => _column.getValue(index);

  set value(int v) => _column.setValue(index, v);
}

final class _AltHealthColumnFactory extends ColumnFactory {
  @override
  DataColumn createColumn(
    ComponentId componentId, {
    int initialCapacity = 8,
  }) => Uint8Column(initialCapacity: initialCapacity);
}

final class _AltHealthFacadeFactory extends ComponentFacadeFactory<AltHealth> {
  @override
  AltHealth create(int index) => AltHealth._(index);

  @override
  void initialize(DataColumn column) {
    AltHealth._setTypedColumn(column as Uint8Column);
  }
}

class AltScoreComponent extends Component {
  const AltScoreComponent();
}

extension type AltScore._(int index) {
  static late IntColumn _column;

  // ignore: use_setters_to_change_properties - internal column bootstrap helper
  static void _setTypedColumn(IntColumn column) {
    _column = column;
  }

  int get value => _column.getValueAt(index);

  set value(int v) => _column.setValueAt(index, v);
}

final class _AltScoreColumnFactory extends ColumnFactory {
  @override
  DataColumn createColumn(
    ComponentId componentId, {
    int initialCapacity = 8,
  }) => IntColumn(initialCapacity: initialCapacity);
}

final class _AltScoreFacadeFactory extends ComponentFacadeFactory<AltScore> {
  @override
  AltScore create(int index) => AltScore._(index);

  @override
  void initialize(DataColumn column) {
    AltScore._setTypedColumn(column as IntColumn);
  }
}

/// World with the same component shapes registered in REVERSE order:
/// Score, Health, Position (primary set registers Position, Health, Score).
World buildReorderedWorld() {
  final world = World();
  world.components.registerExtension<AltScoreComponent, AltScore>(
    columnFactory: _AltScoreColumnFactory(),
    facadeFactory: _AltScoreFacadeFactory(),
  );
  world.components.registerExtension<AltHealthComponent, AltHealth>(
    columnFactory: _AltHealthColumnFactory(),
    facadeFactory: _AltHealthFacadeFactory(),
  );
  world.components.registerExtension<AltPositionComponent, AltPosition>(
    columnFactory: _AltPositionColumnFactory(),
    facadeFactory: _AltPositionFacadeFactory(),
  );
  return world;
}
