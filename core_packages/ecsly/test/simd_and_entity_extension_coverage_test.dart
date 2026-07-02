import 'dart:typed_data';

import 'package:ecsly/ecsly.dart';
import 'package:test/test.dart';

import '_test_components.dart';

void main() {
  group('SIMD patterns/utilities', () {
    test('simd pattern helpers mutate columns correctly', () {
      final positions = _column2([(3, 4), (0, 0), (1, 2)]);
      final output = FloatColumn(stride: 1, initialCapacity: 3)
        ..addBlank()
        ..addBlank()
        ..addBlank();

      calculateDistancesSimd(positions, Float32x4(0, 0, 0, 0), output);
      expect(output.getValue(0, 0), closeTo(5.0, 0.0001));

      normalizeVectorsSimd(positions);
      expect(positions.getValue(1, 0), 0); // zero vector stays zero

      scalePositionsSimd(positions, 2);
      updatePositionSimd(positions, _column2([(1, 1), (1, 1), (1, 1)]), 0.5);
      expect(positions.getValue(2, 0), isNonZero);
    });

    test('SimdUtils add/dot/multiply branches', () {
      final a = _column2([(1, 2), (3, 4)]);
      final b = _column2([(10, 20), (30, 40)]);
      final r = _column2([(0, 0), (0, 0)]);

      SimdUtils.addColumnsSimd(a, b, r);
      expect(r.getValue(0, 0), 11);
      expect(r.getValue(1, 1), 44);

      SimdUtils.multiplyColumnSimd(r, 2);
      expect(r.getValue(0, 0), 22);

      final d2 = SimdUtils.dotProductSimd(a, b); // non-4-stride fallback path
      expect(d2.getValue(0, 0), 50);
      expect(d2.getValue(1, 0), 250);

      final a4 = FloatColumn(stride: 4, initialCapacity: 2)
        ..addBlank()
        ..addBlank();
      final b4 = FloatColumn(stride: 4, initialCapacity: 2)
        ..addBlank()
        ..addBlank();
      for (var i = 0; i < 2; i++) {
        for (var j = 0; j < 4; j++) {
          a4.setValue(i, j, 1);
          b4.setValue(i, j, 2);
        }
      }
      final d4 = SimdUtils.dotProductSimd(a4, b4); // stride-4 path
      expect(d4.length, 2);
    });

    test('simd_patterns stride guards enforce current API contracts', () {
      final stride4 = FloatColumn(stride: 4, initialCapacity: 1)..addBlank();
      final out1 = FloatColumn(stride: 1, initialCapacity: 1)..addBlank();

      // Current contracts require stride==2 for these APIs, which makes their
      // SIMD branch unreachable with current FloatColumn.simdView semantics.
      expect(
        () => calculateDistancesSimd(stride4, Float32x4.zero(), out1),
        throwsA(isA<AssertionError>()),
      );
      expect(
        () => normalizeVectorsSimd(stride4),
        throwsA(isA<AssertionError>()),
      );
      expect(
        () => updatePositionSimd(stride4, stride4, 0.5),
        throwsA(isA<AssertionError>()),
      );

      final stride2 = _column2([(2, 0)]);
      final badOut = FloatColumn(stride: 2, initialCapacity: 1)..addBlank();
      expect(
        () => calculateDistancesSimd(stride2, Float32x4.zero(), badOut),
        throwsA(isA<AssertionError>()),
      );
    });
  });

  group('WorldEntityExtension edge paths', () {
    test('toEntity/toMut and extension error/null paths', () {
      final world = buildTestWorld();
      final e = world.reserveEmptyEntity().entity;

      final (base, isValid) = world.getEntity(e);
      expect(isValid, isTrue);

      final ext = base.toExtension();
      expect(ext.toEntity().entity, e);
      expect(ext.toMut().base.entity, e);

      // Component not present -> null path
      expect(ext.getExtension<PositionComponent, Position>(), isNull);

      // No extension registration for this component ID -> throws
      world.upsertComponent(e, const NameComponent('n'));
      world.flush();
      expect(
        () => ext.getExtension<NameComponent, NameComponent>(),
        throwsA(isA<ExtensionTypeNotRegisteredError>()),
      );

      // Existing component path
      ext.create<PositionComponent, Position>();
      expect(ext.getExtension<PositionComponent, Position>(), isNotNull);

      // Unregistered extension component create path should fail on flush
      expect(
        () => ext.create<_UnregisteredExtComponent, Position>(),
        throwsA(isA<EcsStateError>()),
      );
    });
  });
}

FloatColumn _column2(final List<(double, double)> rows) {
  final c = FloatColumn(stride: 2, initialCapacity: rows.length);
  for (final (x, y) in rows) {
    c.addBlank();
    final i = c.length - 1;
    c
      ..setValue(i, 0, x)
      ..setValue(i, 1, y);
  }
  return c;
}

class _UnregisteredExtComponent extends Component {
  const _UnregisteredExtComponent();
}
