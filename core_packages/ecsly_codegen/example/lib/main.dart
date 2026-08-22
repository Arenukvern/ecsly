import 'package:ecsly/ecsly.dart';
import 'package:ecsly_codegen/ecsly_codegen.dart';

part 'main.ecs.g.dart';

@EcsComponent(
  column: EcsColumnType.float32,
  stride: 2,
  facade: 'ExamplePosition',
)
abstract final class ExamplePositionComponent extends Component {}

extension type const ExamplePosition((int, FloatColumn) data) {
  double get x => data.$2.getValue(data.$1, 0);
  set x(final double value) => data.$2.setValue(data.$1, 0, value);

  double get y => data.$2.getValue(data.$1, 1);
  set y(final double value) => data.$2.setValue(data.$1, 1, value);
}

void main() {
  final world = World();
  world.components.registerExtension<ExamplePositionComponent, ExamplePosition>(
    columnFactory: ExamplePositionColumnFactory(),
    facadeFactory: ExamplePositionFacadeFactory(),
  );

  final entity = world.entities.create();
  world.spawnBundle(
    entity,
    ComponentBundle.fromLists(const [], const [
      (ExamplePositionComponent, ExamplePosition),
    ]),
  );
  world.flush();

  final (ext, isValid) = world.getEntityExtension(entity);
  if (!isValid) {
    throw StateError('Entity should be valid after spawn.');
  }

  final position = ext
      .getExtension<ExamplePositionComponent, ExamplePosition>()!;
  position
    ..x = 4
    ..y = 8;

  assert(position.x == 4, 'x should round-trip through the generated facade.');
  assert(position.y == 8, 'y should round-trip through the generated facade.');
}
