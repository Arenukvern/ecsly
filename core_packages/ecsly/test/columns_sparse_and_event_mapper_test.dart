import 'dart:typed_data';

import 'package:ecsly/ecsly.dart';
import 'package:ecsly/src/events/event_column_mapper.dart';
import 'package:test/test.dart';

class EmptyTypedEvent extends EcsEvent
    with TypedDataEventMixin
    implements TypedDataEvent {
  @override
  List<double> get numericFields => const [];
}

class PairTypedEvent extends EcsEvent
    with TypedDataEventMixin
    implements TypedDataEvent {
  PairTypedEvent(this.a, this.b);
  final double a;
  final double b;

  @override
  List<double> get numericFields => [a, b];
}

class PlainEvent extends EcsEvent {
  const PlainEvent();
}

void main() {
  group('SparseColumnList', () {
    test('add/get/contains/remove including swap-with-last paths', () {
      final list = SparseColumnList();
      final c1 = FloatColumn(stride: 1);
      final c2 = Uint8Column();
      final c3 = IntColumn();

      expect(() => list.add(const ComponentId(999), c1), throwsArgumentError);

      list.add(const ComponentId(1), c1);
      list.add(const ComponentId(2), c2);
      list.add(const ComponentId(3), c3);
      list.add(const ComponentId(2), c2); // duplicate ignored

      expect(list.length, 3);
      expect(list.contains(const ComponentId(1)), isTrue);
      expect(list.contains(const ComponentId(-1)), isFalse);
      expect(list.getColumn(const ComponentId(2)), same(c2));
      expect(list.getColumn(const ComponentId(-1)), isNull);

      final entries = list.entries.toList();
      expect(entries.length, 3);
      expect(list.values.length, 3);

      list.remove(const ComponentId(2)); // middle remove -> swap path
      expect(list.length, 2);
      expect(list.contains(const ComponentId(2)), isFalse);

      list.remove(const ComponentId(-1));
      list.remove(const ComponentId(999));
      expect(list.length, 2);
    });
  });

  group('Float/Object column branch coverage', () {
    test('FloatColumn edge/error/simd helpers', () {
      final f = FloatColumn(stride: 2, initialCapacity: 1);
      f.addBlank();
      f.set(0, Float32List.fromList([1, 2]));

      expect(f.getValue(99, 0), 0);
      expect(f.getValueUnsafe(0, 1), 2);
      expect(f.view(0), Float32List.fromList([1, 2]));
      expect(f.simdView, isNull);

      final otherType = Uint8Column()..addBlank();
      expect(() => f.copyTo(0, otherType, 0), throwsArgumentError);

      final wrongStride = FloatColumn(stride: 3)..addBlank();
      expect(() => f.copyTo(0, wrongStride, 0), throwsArgumentError);

      final dst = FloatColumn(stride: 2)
        ..addBlank()
        ..addBlank();
      f.copyTo(0, dst, 1);
      expect(dst.getValue(1, 0), 1);

      f.moveTo(0, dst, 0);
      expect(dst.getValue(0, 1), 2);
      expect(f.getValue(0, 0), 0);

      f.swap(0, 0); // no-op equal index
      f.swapRemove(0);
      expect(f.length, 0);

      final f4 = FloatColumn(stride: 4)
        ..addBlank()
        ..set(0, Float32List.fromList([1, 2, 3, 4]));

      expect(f4.getSimdViewForRows(-1, 1), isNull);
      expect(f4.getSimdViewForRows(0, 2), isNull);
      expect(f4.getSimdViewForRows(0, 1), isNotNull);

      f4.simdAdd(0, Float32x4.splat(1));
      f4.simdMultiply(0, Float32x4.splat(2));
      expect(f4.getValue(0, 0), closeTo(4, 0.001));

      f4.batchSimdUpdate((final _) => Float32x4(9, 9, 9, 9));
      expect(f4.getValue(0, 2), 9);

      f4.simdProcess((final v) => v + Float32x4.splat(1));
      expect(f4.getValue(0, 3), 10);

      // scalar fallback path
      final f2 = FloatColumn(stride: 2)
        ..addBlank()
        ..set(0, Float32List.fromList([2, 3]));
      f2.simdProcess((final v) => v + Float32x4.splat(2));
      expect(f2.getValue(0, 0), 4);
    });

    test('ObjectColumn copy/move/fill/resize/swap paths', () {
      final obj = ObjectColumn<String>(initialCapacity: 1);
      obj.addBlank();
      obj.setValue(0, 'a');

      expect(
        () => obj.copyTo(0, Uint8Column()..addBlank(), 0),
        throwsArgumentError,
      );

      obj.fillRange(0, 1, 'b');
      expect(obj.getValue(0), 'b');

      final dst = ObjectColumn<String>()
        ..addBlank()
        ..addBlank();
      obj.copyTo(0, dst, 1);
      expect(dst.getValue(1), 'b');

      obj.moveTo(0, dst, 0);
      expect(dst.getValue(0), 'b');
      expect(obj.getValue(0), isNull);

      obj.resize(1); // no-op branch
      obj.addBlank();
      obj.setValue(1, 'x');
      obj.swap(0, 1);
      obj.swapRemove(0);
      expect(obj.length, 1);
      obj.clear();
      expect(obj.length, 0);
    });
  });

  group('EventColumnMapper', () {
    test('mapEventType falls back to object for non-typed events', () {
      final cfg = EventColumnMapper.mapEventType<PlainEvent>(capacity: 4);
      expect(cfg.columnType, ColumnType.object);
      expect(cfg.createColumn(), isA<ObjectColumn<PlainEvent>>());
    });

    test(
      'typed event registration validates factory/stride/sample requirements',
      () {
        expect(
          () => EventColumnMapper.mapEventType<PairTypedEvent>(
            capacity: 4,
            sampleEvent: PairTypedEvent(1, 2),
          ),
          throwsA(isA<EventRegistrationException>()),
        );

        expect(
          () => EventColumnMapper.mapEventType<PairTypedEvent>(
            capacity: 4,
            fromDoubleFieldsFactory: (final fields) =>
                PairTypedEvent(fields[0], fields[1]),
            stride: 0,
          ),
          throwsA(isA<EventRegistrationException>()),
        );

        expect(
          () => EventColumnMapper.mapEventType<PairTypedEvent>(
            capacity: 4,
            fromDoubleFieldsFactory: (final fields) =>
                PairTypedEvent(fields[0], fields[1]),
          ),
          throwsA(isA<EventRegistrationException>()),
        );

        expect(
          () => EventColumnMapper.mapEventType<EmptyTypedEvent>(
            capacity: 4,
            fromDoubleFieldsFactory: (final _) => EmptyTypedEvent(),
            sampleEvent: EmptyTypedEvent(),
          ),
          throwsA(isA<EventRegistrationException>()),
        );
      },
    );

    test('typed event config creates float/int/object columns correctly', () {
      final typed = EventColumnMapper.mapEventType<PairTypedEvent>(
        capacity: 8,
        fromDoubleFieldsFactory: (final f) => PairTypedEvent(f[0], f[1]),
        sampleEvent: PairTypedEvent(1, 2),
      );
      expect(typed.columnType, ColumnType.float);
      expect(typed.stride, 2);
      expect(typed.createColumn(), isA<FloatColumn>());

      const intCfg = EventColumnConfig<PairTypedEvent>(
        columnType: ColumnType.int,
        capacity: 8,
        stride: 3,
      );
      final intColumn = intCfg.createColumn();
      expect(intColumn, isA<IntColumn>());
      expect((intColumn as IntColumn).stride, 3);

      const objCfg = EventColumnConfig<PlainEvent>(
        columnType: ColumnType.object,
        capacity: 2,
      );
      expect(objCfg.createColumn(), isA<ObjectColumn<PlainEvent>>());
    });

    test('TypedDataEventRegistry tracks registration state', () {
      final registry = TypedDataEventRegistry();
      expect(registry.isRegistered<PairTypedEvent>(), isFalse);
      registry.register<PairTypedEvent>(2);
      expect(registry.isRegistered<PairTypedEvent>(), isTrue);
      expect(registry.isRegistered<PlainEvent>(), isFalse);
    });

    test(
      'DataColumn event storage extension covers object/float/int and errors',
      () {
        final object = ObjectColumn<PlainEvent>(initialCapacity: 1)..addBlank();
        object.storeEvent<PlainEvent>(0, const PlainEvent());
        expect(object.loadEvent<PlainEvent>(0), isA<PlainEvent>());
        object.clearEvent(0);
        expect(
          () => object.loadEvent<PlainEvent>(0),
          throwsA(isA<EventTypeMismatchError>()),
        );

        final float = FloatColumn(stride: 2, initialCapacity: 1)..addBlank();
        float.storeEvent<PairTypedEvent>(0, PairTypedEvent(1.5, 2.5));
        final loadedFloat = float.loadEvent<PairTypedEvent>(
          0,
          fromDoubleFieldsFactory: (final f) => PairTypedEvent(f[0], f[1]),
        );
        expect(loadedFloat.a, closeTo(1.5, 0.001));
        expect(loadedFloat.b, closeTo(2.5, 0.001));

        expect(
          () => float.loadEvent<PairTypedEvent>(0),
          throwsA(isA<EventTypeMismatchError>()),
        );
        expect(
          () => float.storeEvent<PlainEvent>(0, const PlainEvent()),
          throwsA(isA<EventTypeMismatchError>()),
        );
        expect(
          () => float.storeEvent<PairTypedEvent>(0, PairTypedEvent(1, 2)),
          returnsNormally,
        );

        final intCol = IntColumn(stride: 2, initialCapacity: 1)..addBlank();
        intCol.storeEvent<PairTypedEvent>(0, PairTypedEvent(7, 9));
        final loadedInt = intCol.loadEvent<PairTypedEvent>(
          0,
          fromDoubleFieldsFactory: (final f) => PairTypedEvent(f[0], f[1]),
        );
        expect(loadedInt.a, 7);
        expect(loadedInt.b, 9);

        expect(
          () => intCol.loadEvent<PairTypedEvent>(0),
          throwsA(isA<EventTypeMismatchError>()),
        );
        expect(
          () => intCol.storeEvent<PlainEvent>(0, const PlainEvent()),
          throwsA(isA<EventTypeMismatchError>()),
        );

        final badStride = IntColumn(initialCapacity: 1)..addBlank();
        expect(
          () => badStride.storeEvent<PairTypedEvent>(0, PairTypedEvent(1, 2)),
          throwsA(isA<EventStrideMismatchError>()),
        );
      },
    );
  });
}
