import 'dart:typed_data';

import 'package:ecsly/ecsly.dart';

// Extension-type (typed-data) components

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

// ObjectColumn (cold-data) component

class NameComponent extends Component {
  const NameComponent(this.value);
  final String value;
}

// Component data types for migration/extractor tests (not stored directly).

class XYData {
  const XYData(this.x, this.y);
  final double x;
  final double y;
}

class ValueData {
  const ValueData(this.value);
  final num value;
}

Float32List f2(final double a, final double b) => Float32List.fromList([a, b]);

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
  world.components.registerObjectComponent<NameComponent>();
  return world;
}
