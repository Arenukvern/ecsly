import 'dart:math' as math;
import 'dart:typed_data';

import 'package:ecsly/ecsly.dart';
import 'package:test/test.dart';

/// Row counts that cross the short-column fast path and leave a scalar tail.
const _counts = [1, 2, 3, 7, 8, 9, 15, 16, 17, 64, 100];

void main() {
  group('simd windows', () {
    test('stride 4 view and window cover live rows only', () {
      final column = FloatColumn(stride: 4, initialCapacity: 2)
        ..addBlank()
        ..set(0, Float32List.fromList([1, 2, 3, 4]));
      column.data[4] = 9; // spare capacity

      expect(column.simdView, isNotNull);
      expect(column.simdView!.length, 1);
      expect(column.simdWindow.vectors.length, 1);
      expect(column.simdWindow.tailFloats, 0);
      expect(column.simdWindow.vectors[0].x, 1);
      expect(column.simdWindow.vectors[0].w, 4);

      column.simdProcess((v) => v + Float32x4.splat(1));
      expect(column.getValue(0, 0), 2);
      expect(column.data[4], 9);
    });

    test('stride 2 window packs two entities and keeps a one-entity tail', () {
      final paired = FloatColumn(stride: 2)
        ..addBlank()
        ..addBlank();
      paired.setValue(0, 0, 1);
      paired.setValue(0, 1, 2);
      paired.setValue(1, 0, 3);
      paired.setValue(1, 1, 4);

      expect(paired.simdView, isNull);
      expect(paired.simdWindow.tailFloats, 0);
      expect(paired.simdWindow.vectors.length, 1);
      final vector = paired.simdWindow.vectors[0];
      expect(vector.x, 1);
      expect(vector.y, 2);
      expect(vector.z, 3);
      expect(vector.w, 4);

      final single = FloatColumn(stride: 2)
        ..addBlank()
        ..set(0, Float32List.fromList([2, 3]));
      expect(single.simdWindow.vectors.length, 0);
      expect(single.simdWindow.tailFloats, 2);
      single.simdProcess((v) => v + Float32x4.splat(2));
      expect(single.getValue(0, 0), 4);
      expect(single.getValue(0, 1), 5);
    });

    test('window is reused until length or the buffer changes', () {
      final column = _column(2, 8, (row, lane) => row + lane * 0.5);
      final first = column.simdWindow;
      expect(identical(column.simdWindow, first), isTrue);

      column.addBlank();
      final second = column.simdWindow;
      expect(identical(second, first), isFalse);
      expect(first.vectors.length, 4);
      expect(first.tailFloats, 0);
      expect(second.vectors.length, 4);
      expect(second.tailFloats, 2);

      column.resize(64);
      expect(identical(column.simdWindow, second), isFalse);

      column.clear();
      expect(column.simdWindow.vectors.length, 0);
      expect(column.simdWindow.tailFloats, 0);
    });

    test('getSimdViewForRows uses a 16-byte offset', () {
      final column = FloatColumn(stride: 4)
        ..addBlank()
        ..addBlank();
      column.set(0, Float32List.fromList([1, 0, 0, 0]));
      column.set(1, Float32List.fromList([9, 8, 7, 6]));

      final second = column.getSimdViewForRows(1, 1);
      expect(second, isNotNull);
      expect(second!.length, 1);
      expect(second[0].x, 9);
      expect(second[0].w, 6);
      expect(column.getSimdViewForRows(0, 1), isNotNull);

      final stride2 = FloatColumn(stride: 2)
        ..addBlank()
        ..addBlank();
      expect(stride2.getSimdViewForRows(0, 1), isNull);
      expect(stride2.getSimdViewForRows(1, 1), isNull);
      expect(stride2.getSimdViewForRows(0, 2), isNotNull);
    });

    test('int window groups live ints and is reused', () {
      final column = IntColumn();
      for (var i = 0; i < 5; i++) {
        column.addBlank();
        column.setValue(i, 0, i + 1);
      }
      expect(column.simdWindow.vectors.length, 1);
      expect(column.simdWindow.tailInts, 1);
      expect(column.simdWindow.vectors[0].x, 1);
      expect(column.simdWindow.vectors[0].w, 4);
      expect(identical(column.simdWindow, column.simdWindow), isTrue);

      column.addBlank();
      expect(column.simdWindow.vectors.length, 1);
      expect(column.simdWindow.tailInts, 2);
    });

    test('simdView is the vector list of the window', () {
      final wide = _column(4, 2, (row, lane) => row * 4.0 + lane);
      expect(identical(wide.simdView, wide.simdWindow.vectors), isTrue);
      expect(wide.simdView![1].w, 7);
      expect(_column(2, 4, (_, _) => 0).simdView, isNull);
    });

    test('the VM has hardware SIMD', () {
      expect(kEcslySimdHardware, isTrue);
    });
  });

  group('kernel parity', () {
    test('update and distance match the scalar twins across sizes', () {
      for (final count in _counts) {
        final position = _column(
          2,
          count,
          (row, lane) => (row + 1) * 0.1 + lane * 0.25,
        );
        final velocity = _column(
          2,
          count,
          (row, lane) => (row % 7) * 0.05 - lane * 0.5,
        );
        final expected = _snapshot(position);
        for (var row = 0; row < count; row++) {
          expected[row * 2] += velocity.getValue(row, 0) * 0.016;
          expected[row * 2 + 1] += velocity.getValue(row, 1) * 0.016;
        }

        updatePositionSimd(position, velocity, 0.016);

        _expectClose(_snapshot(position), expected, 'update rows $count');

        final distances = _column(1, count, (_, _) => 0);
        calculateDistancesSimd(
          position,
          Float32x4(0.5, -0.25, 80, 90),
          distances,
        );
        for (var row = 0; row < count; row++) {
          final dx = position.getValue(row, 0) - 0.5;
          final dy = position.getValue(row, 1) + 0.25;
          expect(
            distances.getValue(row, 0),
            closeTo(math.sqrt(dx * dx + dy * dy), 1e-5),
            reason: 'distance row $row of $count',
          );
        }
      }
    });

    test('the shorter column bounds update and distance', () {
      final position = _column(2, 4, (row, _) => row + 1.0);
      final velocity = _column(2, 2, (_, _) => 10.0);

      updatePositionSimd(position, velocity, 1);

      expect(position.getValue(0, 0), 11);
      expect(position.getValue(1, 0), 12);
      expect(position.getValue(2, 0), 3);
      expect(position.getValue(3, 0), 4);

      final distances = _column(1, 2, (_, _) => 0);
      calculateDistancesSimd(position, Float32x4.zero(), distances);
      expect(distances.length, 2);
      expect(
        distances.getValue(0, 0),
        closeTo(math.sqrt(11 * 11 + 11 * 11), 1e-4),
      );
    });

    test('normalize is bit-identical to the scalar twin', () {
      for (final count in _counts) {
        final column = _column(
          2,
          count,
          (row, lane) => (row % 13) * 0.375 - 2 + lane * 0.1,
        );
        final expected = _snapshot(column);
        for (var row = 0; row < count; row++) {
          final x = expected[row * 2];
          final y = expected[row * 2 + 1];
          final magnitude = math.sqrt(x * x + y * y);
          if (magnitude > 0) {
            expected[row * 2] = x / magnitude;
            expected[row * 2 + 1] = y / magnitude;
          }
        }

        normalizeVectorsSimd(column);

        expect(_snapshot(column), orderedEquals(expected));
      }
    });

    test('normalize keeps a NaN component and a zero vector', () {
      final column = FloatColumn(stride: 2);
      for (final (x, y) in [
        (double.nan, 1.0),
        (3.0, 4.0),
        (0.0, 0.0),
        (0.0, 5.0),
      ]) {
        column
          ..addBlank()
          ..set(column.length - 1, Float32List.fromList([x, y]));
      }

      normalizeVectorsSimd(column);

      expect(column.getValue(0, 0).isNaN, isTrue);
      expect(column.getValue(0, 1), 1);
      expect(column.getValue(1, 0), closeTo(0.6, 1e-6));
      expect(column.getValue(1, 1), closeTo(0.8, 1e-6));
      expect(column.getValue(2, 0), 0);
      expect(column.getValue(2, 1), 0);
      expect(column.getValue(3, 0), 0);
      expect(column.getValue(3, 1), 1);
    });

    test(
      'scale, multiply, and add match the scalar twins for every stride',
      () {
        for (final stride in [1, 2, 3, 4, 5, 8]) {
          for (final count in [1, 3, 4, 7, 16, 17, 40]) {
            final label = 'stride $stride rows $count';
            final column = _column(
              stride,
              count,
              (row, lane) => (row + 1) * 0.125 + lane * 0.1,
            );
            final scaled = _snapshot(column);
            for (var i = 0; i < scaled.length; i++) {
              scaled[i] *= 1.1;
            }

            scalePositionsSimd(column, 1.1);
            _expectClose(_snapshot(column), scaled, 'scale $label');

            SimdUtils.multiplyColumnSimd(column, 1 / 1.1);
            _expectClose(
              _snapshot(column),
              _snapshot(
                _column(
                  stride,
                  count,
                  (row, lane) => (row + 1) * 0.125 + lane * 0.1,
                ),
              ),
              'multiply $label',
            );

            final other = _column(
              stride,
              count,
              (row, lane) => lane - row * 0.5,
            );
            final sum = _column(stride, count, (_, _) => 0);
            final expectedSum = _snapshot(other);
            final base = _snapshot(column);
            for (var i = 0; i < expectedSum.length; i++) {
              expectedSum[i] += base[i];
            }
            SimdUtils.addColumnsSimd(column, other, sum);
            _expectClose(_snapshot(sum), expectedSum, 'add $label');
          }
        }
      },
    );

    test('dot product matches the scalar twin for every stride', () {
      for (final stride in [1, 2, 3, 4, 5]) {
        final a = _column(stride, 9, (row, lane) => (row + 1) * 0.5 + lane);
        final b = _column(
          stride,
          9,
          (row, lane) => (row % 3) * 0.25 - lane * 0.5,
        );

        final dots = SimdUtils.dotProductSimd(a, b);

        expect(dots.stride, 1);
        expect(dots.length, 9);
        for (var row = 0; row < 9; row++) {
          var sum = 0.0;
          for (var lane = 0; lane < stride; lane++) {
            sum += a.getValue(row, lane) * b.getValue(row, lane);
          }
          // Stride 2 and 4 rows are float32 vector products on the VM.
          final tolerance = stride == 2 || stride == 4 ? sum.abs() * 4e-7 : 0;
          expect(
            dots.getValue(row, 0),
            closeTo(sum, tolerance),
            reason: 'stride $stride row $row',
          );
        }
      }
    });

    test('kernels leave spare capacity untouched', () {
      final column = _column(2, 8, (row, lane) => row * 0.5 + lane + 1);
      final live = column.length * 2;
      final spare = Float32List(column.data.length - live)
        ..fillRange(0, column.data.length - live, 7.5);
      column.data.setAll(live, spare);

      scalePositionsSimd(column, 2);
      SimdUtils.multiplyColumnSimd(column, 3);
      normalizeVectorsSimd(column);
      final velocity = _column(2, 8, (_, _) => 0.5);
      updatePositionSimd(column, velocity, 0.5);

      expect(column.data.sublist(live), spare);
    });
  });

  group('row operations', () {
    test('simdAdd and simdMultiply touch one row', () {
      final column = _column(2, 3, (row, lane) => row * 10 + lane + 1.0);

      column.simdAdd(1, Float32x4(100, 200, 300, 400));

      expect(column.getValue(1, 0), 111);
      expect(column.getValue(1, 1), 212);
      expect(column.getValue(0, 0), 1);
      expect(column.getValue(2, 0), 21);

      column.simdMultiply(1, Float32x4(2, 3, 0, 0));
      expect(column.getValue(1, 0), 222);
      expect(column.getValue(1, 1), 636);

      column.simdAdd(3, Float32x4.splat(1));
      column.simdAdd(-1, Float32x4.splat(1));
      column.simdMultiply(99, Float32x4.splat(0));
      expect(column.getValue(1, 0), 222);
      expect(column.getValue(2, 0), 21);
    });

    test('simdAdd repeats the four lanes across a wide row', () {
      final five = _column(5, 1, (_, _) => 0);
      five.simdAdd(0, Float32x4(1, 2, 3, 4));
      expect(_snapshot(five), [1, 2, 3, 4, 1]);

      final eight = _column(8, 1, (_, _) => 1);
      eight.simdAdd(1, Float32x4(1, 2, 3, 4)); // out of range
      eight.simdAdd(0, Float32x4(1, 2, 3, 4));
      eight.simdMultiply(0, Float32x4(2, 2, 2, 2));
      expect(_snapshot(eight), [4, 6, 8, 10, 4, 6, 8, 10]);
    });

    test('batchSimdUpdate needs a stride that is a multiple of 4', () {
      for (final stride in [2, 5]) {
        final column = _column(stride, 3, (_, _) => 1);
        column.batchSimdUpdate((_) => Float32x4.splat(9));
        expect(_snapshot(column).every((value) => value == 1), isTrue);
      }

      final wide = _column(4, 2, (_, _) => 1);
      wide.batchSimdUpdate((index) => Float32x4.splat(index + 1));
      expect(_snapshot(wide), [1, 1, 1, 1, 2, 2, 2, 2]);
    });
  });
}

FloatColumn _column(
  int stride,
  int rows,
  double Function(int row, int lane) at,
) {
  final column = FloatColumn(stride: stride, initialCapacity: rows);
  for (var row = 0; row < rows; row++) {
    column.addBlank();
    for (var lane = 0; lane < stride; lane++) {
      column.setValue(row, lane, at(row, lane));
    }
  }
  return column;
}

Float32List _snapshot(FloatColumn column) =>
    Float32List.fromList(column.data.sublist(0, column.length * column.stride));

/// Three float32 ulps. Vector rows round after every operation.
void _expectClose(Float32List actual, Float32List expected, String label) {
  expect(actual.length, expected.length, reason: label);
  for (var i = 0; i < actual.length; i++) {
    final tolerance = expected[i].abs() * 4e-7 + 1e-9;
    expect(
      actual[i],
      closeTo(expected[i], tolerance),
      reason: '$label float $i',
    );
  }
}
