import 'package:ecsly/ecsly.dart';
import 'package:ecs_spatial_core/ecs_spatial_core.dart';
import 'package:test/test.dart';

void main() {
  test(
    'positionFromConfig returns (x, y) when entity has position component',
    () {
      final world = _createTestWorld();
      world.flush();

      final entity = world.entities.create();
      final (ext, valid) = world.getEntityExtension(entity);
      expect(valid, isTrue);
      final pos = ext.create<_TestPosComponent, _TestPos>();
      pos.x = 12.0;
      pos.y = -3.5;
      world.flush();

      final config = PositionConfigResource(
        positionComponentId: world.components
            .getComponentId<_TestPosComponent>(),
        stride: 2,
      );
      world.upsertResource(config);

      expect(positionFromConfig(world, entity, config), equals((12.0, -3.5)));
    },
  );

  test('positionFromConfig returns null when entity has no position', () {
    final world = _createTestWorld();
    world.flush();

    final entity = world.entities.create();
    world.flush();

    final config = PositionConfigResource(
      positionComponentId: world.components.getComponentId<_TestPosComponent>(),
      stride: 2,
    );

    expect(positionFromConfig(world, entity, config), isNull);
  });

  test('applyPositionDelta updates position and returns true', () {
    final world = _createTestWorld();
    world.flush();

    final entity = world.entities.create();
    final (ext, valid) = world.getEntityExtension(entity);
    expect(valid, isTrue);
    final pos = ext.create<_TestPosComponent, _TestPos>();
    pos.x = 5.0;
    pos.y = 7.0;
    world.flush();

    final config = PositionConfigResource(
      positionComponentId: world.components.getComponentId<_TestPosComponent>(),
      stride: 2,
    );
    world.upsertResource(config);

    final ok = applyPositionDelta(world, entity, 2.5, -1.5, config);
    expect(ok, isTrue);

    expect(positionFromConfig(world, entity, config), equals((7.5, 5.5)));
  });

  test('applyPositionDelta returns false when entity has no position', () {
    final world = _createTestWorld();
    world.flush();

    final entity = world.entities.create();
    world.flush();

    final config = PositionConfigResource(
      positionComponentId: world.components.getComponentId<_TestPosComponent>(),
      stride: 2,
    );

    expect(applyPositionDelta(world, entity, 1.0, 1.0, config), isFalse);
  });
}

World _createTestWorld() {
  final world = World();
  world.components.registerExtension<_TestPosComponent, _TestPos>(
    columnFactory: _TestPosColumnFactory(),
    facadeFactory: _TestPosFacadeFactory(),
  );
  return world;
}

final class _TestPosColumnFactory extends ColumnFactory {
  @override
  DataColumn createColumn(
    final ComponentId componentId, {
    final int initialCapacity = 8,
  }) => FloatColumn(stride: 2, initialCapacity: initialCapacity);
}

// Test-only position component to avoid depending on game2d_plugin (breaks cycle).
abstract final class _TestPosComponent extends Component {}

final class _TestPosFacadeFactory extends ComponentFacadeFactory<_TestPos> {
  @override
  _TestPos create(final int index) => _TestPos._(index);

  @override
  void initialize(final DataColumn column) =>
      _TestPos._init(column as FloatColumn);
}

extension type _TestPos._(int index) {
  static late FloatColumn _col;
  double get x => _col.getValueUnsafe(index, 0);
  set x(final double v) => _col.setValue(index, 0, v);
  double get y => _col.getValueUnsafe(index, 1);
  set y(final double v) => _col.setValue(index, 1, v);
  static void _init(final FloatColumn c) => _col = c;
}
