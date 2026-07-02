import 'dart:typed_data';

import 'package:ecsly/ecsly.dart';
import 'package:test/test.dart';

void main() {
  group('FloatColumnSimd Extension', () {
    test('getSimdViewForRows returns null if stride is not multiple of 4', () {
      final column = FloatColumn(stride: 2);
      column.addBlank();
      column.addBlank();
      expect(column.getSimdViewForRows(0, 1), isNull);
    });

    test('getSimdViewForRows returns null for invalid range', () {
      final column = FloatColumn(stride: 4);
      column.addBlank();
      expect(column.getSimdViewForRows(-1, 1), isNull);
      expect(column.getSimdViewForRows(0, -1), isNull);
      expect(column.getSimdViewForRows(0, 10), isNull); // Out of bounds
    });

    test('getSimdViewForRows returns valid view for stride 4', () {
      final column = FloatColumn(stride: 4);
      for (int i = 0; i < 4; i++) {
        column.addBlank();
      }

      final view = column.getSimdViewForRows(0, 2);
      expect(view, isNotNull);
      expect(view!.length, equals(2)); // 2 rows * 4 stride / 4 = 2 SIMD vectors
    });

    test('simdProcess works with SIMD when stride is multiple of 4', () {
      final column = FloatColumn(stride: 4);
      column.addBlank();
      column.addBlank();
      column.setValue(0, 0, 1);
      column.setValue(0, 1, 2);
      column.setValue(0, 2, 3);
      column.setValue(0, 3, 4);

      // Scale by 2
      column.simdProcess((final vec) => vec * Float32x4.splat(2));

      expect(column.getValue(0, 0), closeTo(2.0, 0.001));
      expect(column.getValue(0, 1), closeTo(4.0, 0.001));
      expect(column.getValue(0, 2), closeTo(6.0, 0.001));
      expect(column.getValue(0, 3), closeTo(8.0, 0.001));
    });

    test('simdProcess falls back to scalar for stride 2', () {
      final column = FloatColumn(stride: 2);
      column.addBlank();
      column.setValue(0, 0, 1);
      column.setValue(0, 1, 2);

      // Scale by 2
      column.simdProcess((final vec) => vec * Float32x4.splat(2));

      expect(column.getValue(0, 0), closeTo(2.0, 0.001));
      expect(column.getValue(0, 1), closeTo(4.0, 0.001));
    });
  });

  group('SimdUtils', () {
    test('addColumnsSimd works with SIMD', () {
      final a = FloatColumn(stride: 4);
      final b = FloatColumn(stride: 4);
      final result = FloatColumn(stride: 4);

      for (int i = 0; i < 2; i++) {
        a.addBlank();
        b.addBlank();
        result.addBlank();
      }

      a.setValue(0, 0, 1);
      a.setValue(0, 1, 2);
      a.setValue(0, 2, 3);
      a.setValue(0, 3, 4);

      b.setValue(0, 0, 5);
      b.setValue(0, 1, 6);
      b.setValue(0, 2, 7);
      b.setValue(0, 3, 8);

      SimdUtils.addColumnsSimd(a, b, result);

      expect(result.getValue(0, 0), closeTo(6.0, 0.001));
      expect(result.getValue(0, 1), closeTo(8.0, 0.001));
      expect(result.getValue(0, 2), closeTo(10.0, 0.001));
      expect(result.getValue(0, 3), closeTo(12.0, 0.001));
    });

    test('addColumnsSimd falls back to scalar for stride 2', () {
      final a = FloatColumn(stride: 2);
      final b = FloatColumn(stride: 2);
      final result = FloatColumn(stride: 2);

      a.addBlank();
      b.addBlank();
      result.addBlank();

      a.setValue(0, 0, 1);
      a.setValue(0, 1, 2);
      b.setValue(0, 0, 3);
      b.setValue(0, 1, 4);

      SimdUtils.addColumnsSimd(a, b, result);

      expect(result.getValue(0, 0), closeTo(4.0, 0.001));
      expect(result.getValue(0, 1), closeTo(6.0, 0.001));
    });

    test('multiplyColumnSimd works with SIMD', () {
      final column = FloatColumn(stride: 4);
      column.addBlank();
      column.setValue(0, 0, 1);
      column.setValue(0, 1, 2);
      column.setValue(0, 2, 3);
      column.setValue(0, 3, 4);

      SimdUtils.multiplyColumnSimd(column, 2);

      expect(column.getValue(0, 0), closeTo(2.0, 0.001));
      expect(column.getValue(0, 1), closeTo(4.0, 0.001));
      expect(column.getValue(0, 2), closeTo(6.0, 0.001));
      expect(column.getValue(0, 3), closeTo(8.0, 0.001));
    });

    test('multiplyColumnSimd falls back to scalar for stride 2', () {
      final column = FloatColumn(stride: 2);
      column.addBlank();
      column.setValue(0, 0, 1);
      column.setValue(0, 1, 2);

      SimdUtils.multiplyColumnSimd(column, 2);

      expect(column.getValue(0, 0), closeTo(2.0, 0.001));
      expect(column.getValue(0, 1), closeTo(4.0, 0.001));
    });

    test('dotProductSimd works with SIMD for stride 4', () {
      final a = FloatColumn(stride: 4);
      final b = FloatColumn(stride: 4);

      a.addBlank();
      b.addBlank();

      a.setValue(0, 0, 1);
      a.setValue(0, 1, 2);
      a.setValue(0, 2, 3);
      a.setValue(0, 3, 4);

      b.setValue(0, 0, 2);
      b.setValue(0, 1, 3);
      b.setValue(0, 2, 4);
      b.setValue(0, 3, 5);

      final result = SimdUtils.dotProductSimd(a, b);

      // Dot product: 1*2 + 2*3 + 3*4 + 4*5 = 2 + 6 + 12 + 20 = 40
      expect(result.getValue(0, 0), closeTo(40.0, 0.001));
    });

    test('dotProductSimd falls back to scalar for stride 2', () {
      final a = FloatColumn(stride: 2);
      final b = FloatColumn(stride: 2);

      a.addBlank();
      b.addBlank();

      a.setValue(0, 0, 1);
      a.setValue(0, 1, 2);
      b.setValue(0, 0, 3);
      b.setValue(0, 1, 4);

      final result = SimdUtils.dotProductSimd(a, b);

      // Dot product: 1*3 + 2*4 = 3 + 8 = 11
      expect(result.getValue(0, 0), closeTo(11.0, 0.001));
    });
  });

  group('SIMD Pattern Functions', () {
    test('updatePositionSimd works with SIMD', () {
      final positionColumn = FloatColumn(stride: 2);
      final velocityColumn = FloatColumn(stride: 2);

      for (int i = 0; i < 2; i++) {
        positionColumn.addBlank();
        velocityColumn.addBlank();
      }

      positionColumn.setValue(0, 0, 0); // x
      positionColumn.setValue(0, 1, 0); // y
      velocityColumn.setValue(0, 0, 1); // dx
      velocityColumn.setValue(0, 1, 2); // dy

      const dt = 0.5;
      updatePositionSimd(positionColumn, velocityColumn, dt);

      expect(positionColumn.getValue(0, 0), closeTo(0.5, 0.001)); // x + dx*dt
      expect(positionColumn.getValue(0, 1), closeTo(1.0, 0.001)); // y + dy*dt
    });

    test('updatePositionSimd falls back to scalar correctly', () {
      final positionColumn = FloatColumn(stride: 2);
      final velocityColumn = FloatColumn(stride: 2);

      positionColumn.addBlank();
      velocityColumn.addBlank();

      positionColumn.setValue(0, 0, 10);
      positionColumn.setValue(0, 1, 20);
      velocityColumn.setValue(0, 0, 5);
      velocityColumn.setValue(0, 1, 10);

      const dt = 2.0;
      updatePositionSimd(positionColumn, velocityColumn, dt);

      expect(positionColumn.getValue(0, 0), closeTo(20.0, 0.001)); // 10 + 5*2
      expect(positionColumn.getValue(0, 1), closeTo(40.0, 0.001)); // 20 + 10*2
    });

    test('scalePositionsSimd works with SIMD', () {
      final positionColumn = FloatColumn(stride: 4);
      positionColumn.addBlank();
      positionColumn.setValue(0, 0, 1);
      positionColumn.setValue(0, 1, 2);
      positionColumn.setValue(0, 2, 3);
      positionColumn.setValue(0, 3, 4);

      scalePositionsSimd(positionColumn, 2);

      expect(positionColumn.getValue(0, 0), closeTo(2.0, 0.001));
      expect(positionColumn.getValue(0, 1), closeTo(4.0, 0.001));
      expect(positionColumn.getValue(0, 2), closeTo(6.0, 0.001));
      expect(positionColumn.getValue(0, 3), closeTo(8.0, 0.001));
    });

    test('scalePositionsSimd falls back to scalar for stride 2', () {
      final positionColumn = FloatColumn(stride: 2);
      positionColumn.addBlank();
      positionColumn.setValue(0, 0, 1);
      positionColumn.setValue(0, 1, 2);

      scalePositionsSimd(positionColumn, 3);

      expect(positionColumn.getValue(0, 0), closeTo(3.0, 0.001));
      expect(positionColumn.getValue(0, 1), closeTo(6.0, 0.001));
    });

    test('calculateDistancesSimd works correctly', () {
      final positionColumn = FloatColumn(stride: 2);
      final outputColumn = FloatColumn(stride: 1);

      for (int i = 0; i < 2; i++) {
        positionColumn.addBlank();
        outputColumn.addBlank();
      }

      positionColumn.setValue(0, 0, 0); // x
      positionColumn.setValue(0, 1, 0); // y
      positionColumn.setValue(1, 0, 3); // x
      positionColumn.setValue(1, 1, 4); // y

      final target = Float32x4(0, 0, 0, 0); // Target at origin
      calculateDistancesSimd(positionColumn, target, outputColumn);

      // Distance from (0,0) to (0,0) = 0
      expect(outputColumn.getValue(0, 0), closeTo(0.0, 0.001));
      // Distance from (3,4) to (0,0) = 5
      expect(outputColumn.getValue(1, 0), closeTo(5.0, 0.001));
    });

    test('normalizeVectorsSimd works correctly', () {
      final vectorColumn = FloatColumn(stride: 2);
      vectorColumn.addBlank();
      vectorColumn.setValue(0, 0, 3); // x
      vectorColumn.setValue(0, 1, 4); // y

      normalizeVectorsSimd(vectorColumn);

      // Normalized (3,4) should be (0.6, 0.8)
      expect(vectorColumn.getValue(0, 0), closeTo(0.6, 0.001));
      expect(vectorColumn.getValue(0, 1), closeTo(0.8, 0.001));
    });

    test('normalizeVectorsSimd handles zero vectors', () {
      final vectorColumn = FloatColumn(stride: 2);
      vectorColumn.addBlank();
      vectorColumn.setValue(0, 0, 0);
      vectorColumn.setValue(0, 1, 0);

      normalizeVectorsSimd(vectorColumn);

      // Zero vector should remain zero
      expect(vectorColumn.getValue(0, 0), closeTo(0.0, 0.001));
      expect(vectorColumn.getValue(0, 1), closeTo(0.0, 0.001));
    });
  });

  group('SIMD Correctness Tests', () {
    test('SIMD and scalar produce same results for updatePositionSimd', () {
      final posSimd = FloatColumn(stride: 2);
      final velSimd = FloatColumn(stride: 2);
      final posScalar = FloatColumn(stride: 2);
      final velScalar = FloatColumn(stride: 2);

      for (int i = 0; i < 4; i++) {
        posSimd.addBlank();
        velSimd.addBlank();
        posScalar.addBlank();
        velScalar.addBlank();
      }

      // Initialize with same values
      for (int i = 0; i < 4; i++) {
        posSimd.setValue(i, 0, i * 1.0);
        posSimd.setValue(i, 1, i * 2.0);
        velSimd.setValue(i, 0, i * 0.5);
        velSimd.setValue(i, 1, i * 1.0);

        posScalar.setValue(i, 0, i * 1.0);
        posScalar.setValue(i, 1, i * 2.0);
        velScalar.setValue(i, 0, i * 0.5);
        velScalar.setValue(i, 1, i * 1.0);
      }

      const dt = 0.5;
      updatePositionSimd(posSimd, velSimd, dt);
      updatePositionSimd(posScalar, velScalar, dt);

      // Results should match (within floating point precision)
      for (int i = 0; i < 4; i++) {
        expect(
          posSimd.getValue(i, 0),
          closeTo(posScalar.getValue(i, 0), 0.001),
        );
        expect(
          posSimd.getValue(i, 1),
          closeTo(posScalar.getValue(i, 1), 0.001),
        );
      }
    });
  });
}
