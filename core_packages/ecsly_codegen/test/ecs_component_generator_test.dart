import 'package:ecsly_codegen/src/annotations.dart';
import 'package:ecsly_codegen/src/ecs_component_generator.dart';
import 'package:test/test.dart';

void main() {
  group('generateEcsComponentFactories', () {
    test('generates float32 column and facade factories', () {
      final output = generateEcsComponentFactories(
        className: 'PositionComponent',
        facade: 'Position',
        columnType: EcsColumnType.float32,
        stride: 2,
      );

      expect(
        output,
        contains('class PositionColumnFactory extends ColumnFactory'),
      );
      expect(
        output,
        contains('FloatColumn(initialCapacity: initialCapacity, stride: 2)'),
      );
      expect(
        output,
        contains(
          'class PositionFacadeFactory '
          'extends ComponentFacadeFactory<Position>',
        ),
      );
      expect(output, contains('late FloatColumn _column;'));
      expect(output, contains('Position create(final int index)'));
    });

    test('generates int32 column and facade factories', () {
      final output = generateEcsComponentFactories(
        className: 'TileComponent',
        facade: 'Tile',
        columnType: EcsColumnType.int32,
        stride: 3,
      );

      expect(output, contains('class TileColumnFactory extends ColumnFactory'));
      expect(
        output,
        contains('IntColumn(initialCapacity: initialCapacity, stride: 3)'),
      );
      expect(
        output,
        contains(
          'class TileFacadeFactory extends ComponentFacadeFactory<Tile>',
        ),
      );
      expect(output, contains('late IntColumn _column;'));
    });

    test('generates uint8 columns without stride', () {
      final output = generateEcsComponentFactories(
        className: 'HealthComponent',
        facade: 'Health',
        columnType: EcsColumnType.uint8,
        stride: 7,
      );

      expect(
        output,
        contains('class HealthColumnFactory extends ColumnFactory'),
      );
      expect(output, contains('Uint8Column(initialCapacity: initialCapacity)'));
      expect(output, isNot(contains('stride: 7')));
      expect(
        output,
        contains(
          'class HealthFacadeFactory '
          'extends ComponentFacadeFactory<Health>',
        ),
      );
      expect(output, contains('late Uint8Column _column;'));
    });

    test('trims Component suffix only when present', () {
      final trimmed = generateEcsComponentFactories(
        className: 'VelocityComponent',
        facade: 'Velocity',
        columnType: EcsColumnType.float32,
        stride: 4,
      );
      final unchanged = generateEcsComponentFactories(
        className: 'Marker',
        facade: 'Marker',
        columnType: EcsColumnType.uint8,
        stride: 1,
      );

      expect(trimmed, contains('class VelocityColumnFactory'));
      expect(unchanged, contains('class MarkerColumnFactory'));
    });

    test('matches golden float32 output', () {
      final output = generateEcsComponentFactories(
        className: 'ExamplePositionComponent',
        facade: 'ExamplePosition',
        columnType: EcsColumnType.float32,
        stride: 2,
      );

      expect(output, equals(_goldenExamplePositionFactories));
    });
  });

  group('validateEcsComponentAnnotation', () {
    test('rejects invalid facade identifiers', () {
      expect(
        () => validateEcsComponentAnnotation(
          facade: 'not-valid',
          columnType: EcsColumnType.float32,
          stride: 2,
        ),
        throwsArgumentError,
      );
    });

    test('rejects non-positive stride for float32', () {
      expect(
        () => validateEcsComponentAnnotation(
          facade: 'Position',
          columnType: EcsColumnType.float32,
          stride: 0,
        ),
        throwsArgumentError,
      );
    });

    test('rejects non-positive stride for int32', () {
      expect(
        () => validateEcsComponentAnnotation(
          facade: 'Tile',
          columnType: EcsColumnType.int32,
          stride: -1,
        ),
        throwsArgumentError,
      );
    });

    test('allows any stride for uint8', () {
      expect(
        () => validateEcsComponentAnnotation(
          facade: 'Health',
          columnType: EcsColumnType.uint8,
          stride: 0,
        ),
        returnsNormally,
      );
    });
  });
}

const _goldenExamplePositionFactories = '''
class ExamplePositionColumnFactory extends ColumnFactory {
  @override
  DataColumn createColumn(
    final ComponentId componentId, {
    final int initialCapacity = 8,
  }) => FloatColumn(initialCapacity: initialCapacity, stride: 2);
}

class ExamplePositionFacadeFactory extends ComponentFacadeFactory<ExamplePosition> {
  late FloatColumn _column;

  @override
  ExamplePosition create(final int index) => ExamplePosition((index, _column));

  @override
  void initialize(final DataColumn column) {
    if (column case final FloatColumn column) {
      _column = column;
      return;
    }
    throw ArgumentError('ExamplePosition requires FloatColumn, got \${column.runtimeType}.');
  }
}
''';
