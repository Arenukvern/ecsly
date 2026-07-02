// ignore_for_file: cascade_invocations

import 'dart:typed_data';

import 'package:ecsly/ecsly.dart';
import 'package:test/test.dart';

void main() {
  group('Column Interface', () {
    test('Column has required interface methods', () {
      final column = FloatColumn(stride: 2);
      expect(column.length, isA<int>());
      expect(column.capacity, isA<int>());
      column.addBlank();
      column.addBlank();
      expect(() => column.swap(0, 0), returnsNormally);
      expect(() => column.resize(10), returnsNormally);
      expect(column.addBlank, returnsNormally);
      expect(() => column.swapRemove(0), returnsNormally);
      expect(() => column.copyTo(0, column, 0), returnsNormally);
      expect(() => column.moveTo(0, column, 0), returnsNormally);
      expect(column.clear, returnsNormally);
    });
  });

  group('FloatColumn', () {
    test('creates with initial capacity and stride', () {
      final column = FloatColumn(initialCapacity: 10, stride: 2);
      expect(column.length, equals(0));
      expect(column.capacity, greaterThanOrEqualTo(10));
      expect(column.stride, equals(2));
    });

    test('addBlank adds zero-initialized elements', () {
      final column = FloatColumn(stride: 2);
      column.addBlank();
      expect(column.length, equals(1));
      expect(column.getValue(0, 0), equals(0.0));
      expect(column.getValue(0, 1), equals(0.0));
    });

    test('getValue and setValue work correctly', () {
      final column = FloatColumn(stride: 2);
      column.addBlank();
      column.setValue(0, 0, 10.5);
      column.setValue(0, 1, 20.7);
      expect(column.getValue(0, 0), closeTo(10.5, 0.001));
      expect(column.getValue(0, 1), closeTo(20.7, 0.001));
    });

    test('view returns correct sublist', () {
      final column = FloatColumn(stride: 2);
      column.addBlank();
      column.setValue(0, 0, 10);
      column.setValue(0, 1, 20);
      final view = column.view(0);
      expect(view.length, equals(2));
      expect(view[0], equals(10.0));
      expect(view[1], equals(20.0));
    });

    test('set updates element from Float32List', () {
      final column = FloatColumn(stride: 2);
      column.addBlank();
      column.set(0, Float32List.fromList([5.0, 15.0]));
      expect(column.getValue(0, 0), equals(5.0));
      expect(column.getValue(0, 1), equals(15.0));
    });

    test('swap exchanges elements correctly', () {
      final column = FloatColumn(stride: 2);
      column.addBlank();
      column.addBlank();
      column.setValue(0, 0, 10);
      column.setValue(0, 1, 20);
      column.setValue(1, 0, 30);
      column.setValue(1, 1, 40);

      column.swap(0, 1);

      expect(column.getValue(0, 0), equals(30.0));
      expect(column.getValue(0, 1), equals(40.0));
      expect(column.getValue(1, 0), equals(10.0));
      expect(column.getValue(1, 1), equals(20.0));
    });

    test('swapRemove removes element by swapping with last', () {
      final column = FloatColumn(stride: 2);
      column.addBlank();
      column.addBlank();
      column.addBlank();
      column.setValue(0, 0, 10);
      column.setValue(1, 0, 20);
      column.setValue(2, 0, 30);

      column.swapRemove(0);

      expect(column.length, equals(2));
      // Last element should now be at index 0
      expect(column.getValue(0, 0), equals(30.0));
      expect(column.getValue(1, 0), equals(20.0));
    });

    test('resize increases capacity', () {
      final column = FloatColumn(initialCapacity: 2, stride: 2);
      final initialCapacity = column.capacity;
      column.resize(10);
      expect(column.capacity, greaterThanOrEqualTo(10));
      expect(column.capacity, greaterThan(initialCapacity));
    });

    test('resize does nothing if new capacity is smaller', () {
      final column = FloatColumn(initialCapacity: 10, stride: 2);
      final initialCapacity = column.capacity;
      column.resize(5);
      expect(column.capacity, equals(initialCapacity));
    });

    test('copyTo copies element to another column', () {
      final source = FloatColumn(stride: 2);
      final dest = FloatColumn(stride: 2);
      source.addBlank();
      dest.addBlank();
      source.setValue(0, 0, 10);
      source.setValue(0, 1, 20);

      source.copyTo(0, dest, 0);

      expect(dest.getValue(0, 0), equals(10.0));
      expect(dest.getValue(0, 1), equals(20.0));
    });

    test('moveTo copies and clears source', () {
      final source = FloatColumn(stride: 2);
      final dest = FloatColumn(stride: 2);
      source.addBlank();
      dest.addBlank();
      source.setValue(0, 0, 10);
      source.setValue(0, 1, 20);

      source.moveTo(0, dest, 0);

      expect(dest.getValue(0, 0), equals(10.0));
      expect(dest.getValue(0, 1), equals(20.0));
      expect(source.getValue(0, 0), equals(0.0));
      expect(source.getValue(0, 1), equals(0.0));
    });

    test('clear sets length to zero', () {
      final column = FloatColumn(stride: 2);
      column.addBlank();
      column.addBlank();
      expect(column.length, equals(2));
      column.clear();
      expect(column.length, equals(0));
    });

    test('simdView returns null if stride is not multiple of 4', () {
      final column = FloatColumn(stride: 2);
      expect(column.simdView, isNull);
    });

    test('simdView returns Float32x4List if stride is multiple of 4', () {
      final column = FloatColumn(stride: 4);
      final simdView = column.simdView;
      expect(simdView, isNotNull);
      expect(simdView, isA<Float32x4List>());
    });

    test('auto-resizes when capacity exceeded', () {
      final column = FloatColumn(initialCapacity: 2, stride: 2);
      final initialCapacity = column.capacity;
      // Add more than initial capacity
      for (int i = 0; i < initialCapacity + 1; i++) {
        column.addBlank();
      }
      expect(column.capacity, greaterThan(initialCapacity));
      expect(column.length, equals(initialCapacity + 1));
    });
  });

  group('IntColumn', () {
    test('creates with initial capacity', () {
      final column = IntColumn(initialCapacity: 10);
      expect(column.length, equals(0));
      expect(column.capacity, greaterThanOrEqualTo(10));
    });

    test('addBlank adds zero-initialized elements', () {
      final column = IntColumn();
      column.addBlank();
      expect(column.length, equals(1));
      expect(column.getValue(0, 0), equals(0));
    });

    test('getValue and setValue work correctly', () {
      final column = IntColumn();
      column.addBlank();
      column.setValue(0, 0, 42);
      expect(column.getValue(0, 0), equals(42));
    });

    test('swap exchanges elements correctly', () {
      final column = IntColumn();
      column.addBlank();
      column.addBlank();
      column.setValue(0, 0, 10);
      column.setValue(1, 0, 20);

      column.swap(0, 1);

      expect(column.getValue(0, 0), equals(20));
      expect(column.getValue(1, 0), equals(10));
    });

    test('swapRemove removes element by swapping with last', () {
      final column = IntColumn();
      column.addBlank();
      column.addBlank();
      column.addBlank();
      column.setValue(0, 0, 10);
      column.setValue(1, 0, 20);
      column.setValue(2, 0, 30);

      column.swapRemove(0);

      expect(column.length, equals(2));
      expect(column.getValue(0, 0), equals(30));
      expect(column.getValue(1, 0), equals(20));
    });

    test('copyTo copies element to another column', () {
      final source = IntColumn();
      final dest = IntColumn();
      source.addBlank();
      dest.addBlank();
      source.setValue(0, 0, 42);

      source.copyTo(0, dest, 0);

      expect(dest.getValue(0, 0), equals(42));
    });

    test('moveTo copies and clears source', () {
      final source = IntColumn();
      final dest = IntColumn();
      source.addBlank();
      dest.addBlank();
      source.setValue(0, 0, 42);

      source.moveTo(0, dest, 0);

      expect(dest.getValue(0, 0), equals(42));
      expect(source.getValue(0, 0), equals(0));
    });

    test('clear sets length to zero', () {
      final column = IntColumn();
      column.addBlank();
      column.addBlank();
      expect(column.length, equals(2));
      column.clear();
      expect(column.length, equals(0));
    });
  });

  group('Uint8Column', () {
    test('creates with initial capacity', () {
      final column = Uint8Column(initialCapacity: 10);
      expect(column.length, equals(0));
      expect(column.capacity, greaterThanOrEqualTo(10));
    });

    test('addBlank adds zero-initialized elements', () {
      final column = Uint8Column();
      column.addBlank();
      expect(column.length, equals(1));
      expect(column.getValue(0), equals(0));
    });

    test('getValue and setValue work correctly', () {
      final column = Uint8Column();
      column.addBlank();
      column.setValue(0, 42);
      expect(column.getValue(0), equals(42));
    });

    test('setValue clamps values greater than 255', () {
      final column = Uint8Column();
      column.addBlank();
      column.setValue(0, 300);
      expect(column.getValue(0), equals(255));
    });

    test('setValue clamps values less than 0', () {
      final column = Uint8Column();
      column.addBlank();
      column.setValue(0, -10);
      expect(column.getValue(0), equals(0));
    });

    test('setValue accepts values in valid range', () {
      final column = Uint8Column();
      column.addBlank();
      column.setValue(0, 0);
      expect(column.getValue(0), equals(0));
      column.setValue(0, 255);
      expect(column.getValue(0), equals(255));
      column.setValue(0, 128);
      expect(column.getValue(0), equals(128));
    });

    test('swap exchanges elements correctly', () {
      final column = Uint8Column();
      column.addBlank();
      column.addBlank();
      column.setValue(0, 10);
      column.setValue(1, 20);

      column.swap(0, 1);

      expect(column.getValue(0), equals(20));
      expect(column.getValue(1), equals(10));
    });

    test('swapRemove removes element by swapping with last', () {
      final column = Uint8Column();
      column.addBlank();
      column.addBlank();
      column.addBlank();
      column.setValue(0, 10);
      column.setValue(1, 20);
      column.setValue(2, 30);

      column.swapRemove(0);

      expect(column.length, equals(2));
      expect(column.getValue(0), equals(30));
      expect(column.getValue(1), equals(20));
    });

    test('copyTo copies element to another column', () {
      final source = Uint8Column();
      final dest = Uint8Column();
      source.addBlank();
      dest.addBlank();
      source.setValue(0, 42);

      source.copyTo(0, dest, 0);

      expect(dest.getValue(0), equals(42));
    });

    test('moveTo copies and clears source', () {
      final source = Uint8Column();
      final dest = Uint8Column();
      source.addBlank();
      dest.addBlank();
      source.setValue(0, 42);

      source.moveTo(0, dest, 0);

      expect(dest.getValue(0), equals(42));
      expect(source.getValue(0), equals(0));
    });

    test('clear sets length to zero', () {
      final column = Uint8Column();
      column.addBlank();
      column.addBlank();
      expect(column.length, equals(2));
      column.clear();
      expect(column.length, equals(0));
    });

    test('copyTo throws if destination is not Uint8Column', () {
      final source = Uint8Column();
      final dest = IntColumn();
      source.addBlank();
      dest.addBlank();
      source.setValue(0, 42);

      expect(() => source.copyTo(0, dest, 0), throwsArgumentError);
    });
  });

  group('ObjectColumn', () {
    test('creates with initial capacity', () {
      final column = ObjectColumn<String>(initialCapacity: 10);
      expect(column.length, equals(0));
      expect(column.capacity, greaterThanOrEqualTo(10));
    });

    test('addBlank adds null elements', () {
      final column = ObjectColumn<String>();
      column.addBlank();
      expect(column.length, equals(1));
      expect(column.getValue(0), isNull);
    });

    test('getValue and setValue work correctly', () {
      final column = ObjectColumn<String>();
      column.addBlank();
      column.setValue(0, 'test');
      expect(column.getValue(0), equals('test'));
    });

    test('handles null values correctly', () {
      final column = ObjectColumn<String>();
      column.addBlank();
      column.setValue(0, 'test');
      column.setValue(0, null);
      expect(column.getValue(0), isNull);
    });

    test('swap exchanges elements correctly', () {
      final column = ObjectColumn<String>();
      column.addBlank();
      column.addBlank();
      column.setValue(0, 'first');
      column.setValue(1, 'second');

      column.swap(0, 1);

      expect(column.getValue(0), equals('second'));
      expect(column.getValue(1), equals('first'));
    });

    test('swapRemove removes element by swapping with last', () {
      final column = ObjectColumn<String>();
      column.addBlank();
      column.addBlank();
      column.addBlank();
      column.setValue(0, 'first');
      column.setValue(1, 'second');
      column.setValue(2, 'third');

      column.swapRemove(0);

      expect(column.length, equals(2));
      expect(column.getValue(0), equals('third'));
      expect(column.getValue(1), equals('second'));
    });

    test('copyTo copies element to another column', () {
      final source = ObjectColumn<String>();
      final dest = ObjectColumn<String>();
      source.addBlank();
      dest.addBlank();
      source.setValue(0, 'test');

      source.copyTo(0, dest, 0);

      expect(dest.getValue(0), equals('test'));
    });

    test('moveTo copies and clears source', () {
      final source = ObjectColumn<String>();
      final dest = ObjectColumn<String>();
      source.addBlank();
      dest.addBlank();
      source.setValue(0, 'test');

      source.moveTo(0, dest, 0);

      expect(dest.getValue(0), equals('test'));
      expect(source.getValue(0), isNull);
    });

    test('clear sets length to zero and nullifies elements', () {
      final column = ObjectColumn<String>();
      column.addBlank();
      column.addBlank();
      column.setValue(0, 'test');
      expect(column.length, equals(2));
      column.clear();
      expect(column.length, equals(0));
      // Elements should be nullified
      column.addBlank();
      expect(column.getValue(0), isNull);
    });
  });

  group('Edge Cases', () {
    test('FloatColumn: empty column operations', () {
      final column = FloatColumn(stride: 2);
      expect(column.length, equals(0));
      expect(column.capacity, greaterThan(0));
      column.clear();
      expect(column.length, equals(0));
    });

    test('FloatColumn: single element swap', () {
      final column = FloatColumn(stride: 2);
      column.addBlank();
      column.setValue(0, 0, 10);
      column.swap(0, 0); // Should be no-op
      expect(column.getValue(0, 0), equals(10.0));
    });

    test('IntColumn: empty column operations', () {
      final column = IntColumn();
      expect(column.length, equals(0));
      expect(column.capacity, greaterThan(0));
      column.clear();
      expect(column.length, equals(0));
    });

    test('ObjectColumn: empty column operations', () {
      final column = ObjectColumn<String>();
      expect(column.length, equals(0));
      expect(column.capacity, greaterThan(0));
      column.clear();
      expect(column.length, equals(0));
    });

    test('FloatColumn: swap with same index is no-op', () {
      final column = FloatColumn(stride: 2);
      column.addBlank();
      column.setValue(0, 0, 5);
      column.swap(0, 0);
      expect(column.getValue(0, 0), equals(5.0));
    });

    test('IntColumn: swap with same index is no-op', () {
      final column = IntColumn();
      column.addBlank();
      column.setValue(0, 0, 5);
      column.swap(0, 0);
      expect(column.getValue(0, 0), equals(5));
    });

    test('Uint8Column: empty column operations', () {
      final column = Uint8Column();
      expect(column.length, equals(0));
      expect(column.capacity, greaterThan(0));
      column.clear();
      expect(column.length, equals(0));
    });

    test('Uint8Column: swap with same index is no-op', () {
      final column = Uint8Column();
      column.addBlank();
      column.setValue(0, 5);
      column.swap(0, 0);
      expect(column.getValue(0), equals(5));
    });
  });
}
