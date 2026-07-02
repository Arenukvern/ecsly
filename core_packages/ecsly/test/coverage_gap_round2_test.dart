import 'dart:typed_data';

import 'package:ecsly/ecsly.dart';
import 'package:ecsly/src/archetypes/entity_migration_tools/component_data_integrator.dart';
import 'package:ecsly/src/archetypes/entity_migration_tools/component_data_writer.dart';
import 'package:ecsly/src/archetypes/entity_migration_tools/extractor_registry.dart';
import 'package:ecsly/src/archetypes/entity_migration_tools/extractors/field_extractors.dart';
import 'package:ecsly/src/archetypes/entity_migration_tools/extractors/list_extractors.dart';
import 'package:ecsly/src/archetypes/entity_migration_tools/signature_computer.dart';
import 'package:ecsly/src/events/event_column_mapper.dart';
import 'package:test/test.dart';

class _ObjEvent extends EcsEvent {
  const _ObjEvent(this.value);
  final int value;
}

class _Vec4Event extends EcsEvent
    with TypedDataEventMixin
    implements TypedDataEvent {
  const _Vec4Event(this.a, this.b, this.c, this.d);

  final double a;
  final double b;
  final double c;
  final double d;

  @override
  List<double> get numericFields => [a, b, c, d];
}

class _XY {
  const _XY(this.x, this.y);
  final double x;
  final double y;
}

class _Val {
  const _Val(this.value);
  final int value;
}

void main() {
  group('Migration extractor/writer paths', () {
    tearDown(() {
      ExtractorRegistry.instance.clear();
    });

    test('ExtractorRegistry register/get/fallback and ListExtractor', () {
      final reg = ExtractorRegistry.instance;
      expect(reg.getExtractor(num), isNotNull);
      expect(reg.getExtractor(int), isNotNull);
      expect(reg.getExtractor(double), isNotNull);

      final xyExtractor = XYFieldExtractor<_XY>(
        getX: (final v) => v.x,
        getY: (final v) => v.y,
      );
      reg.register<_XY>(xyExtractor);
      final resolved = reg.getExtractorFor(const _XY(1, 2));
      expect(resolved.extractFloats(const _XY(1, 2)), [1.0, 2.0]);

      final listExtractor = ListExtractor();
      expect(listExtractor.extractFloats([1, 2.5]), [1.0, 2.5]);
      expect(listExtractor.extractFloats(const _Val(1)), isEmpty);
      expect(listExtractor.extractObject([1, 2]), isA<List>());
      expect(listExtractor.extractObject(const _Val(1)), isNull);
    });

    test('ComponentDataWriter writes Float/Int/Uint8/Object columns', () {
      final reg = ExtractorRegistry.instance;
      reg.register<_XY>(
        XYFieldExtractor<_XY>(getX: (final v) => v.x, getY: (final v) => v.y),
      );
      reg.register<_Val>(
        ValueFieldExtractor<_Val>(getValue: (final v) => v.value),
      );

      final floatCol = FloatColumn(stride: 2, initialCapacity: 1)..addBlank();
      ComponentDataWriter.writeToColumn(floatCol, 0, const _XY(3, 4));
      expect(floatCol.getValue(0, 0), 3.0);
      expect(floatCol.getValue(0, 1), 4.0);

      final intCol = IntColumn(initialCapacity: 1)..addBlank();
      ComponentDataWriter.writeToColumn(intCol, 0, const _Val(9));
      expect(intCol.getValueAt(0), 9);

      final u8Col = Uint8Column(initialCapacity: 1)..addBlank();
      ComponentDataWriter.writeToColumn(u8Col, 0, const _Val(300));
      expect(u8Col.getValue(0), 255);

      final objCol = ObjectColumn<Object>(initialCapacity: 1)..addBlank();
      ComponentDataWriter.writeToColumn(objCol, 0, 12);
      expect(objCol.getValue(0), 12);

      expect(ComponentDataWriter.extractFloats(11), [11.0]);
      ComponentDataIntegrator.writeComponentData(floatCol, 0, null);
      ComponentDataIntegrator.writeComponentData(floatCol, 0, const _XY(7, 8));
      expect(floatCol.getValue(0, 0), 7.0);
    });
  });

  group('ComponentMask base behavior', () {
    test('set/clear/contains/intersection/union/componentIds/toString', () {
      final a = ComponentMaskImpl(maxComponents: 64);
      final b = ComponentMaskImpl(maxComponents: 128);

      a
        ..set(const ComponentId(1))
        ..set(const ComponentId(3));
      b
        ..set(const ComponentId(3))
        ..set(const ComponentId(65));

      expect(a.has(const ComponentId(1)), isTrue);
      expect(a.has(const ComponentId(-1)), isFalse);
      expect(a.contains(b), isFalse);

      final inter = a.intersection(b);
      expect(inter.has(const ComponentId(3)), isTrue);
      expect(inter.has(const ComponentId(1)), isFalse);

      final uni = a.union(b);
      expect(uni.has(const ComponentId(1)), isTrue);
      expect(uni.has(const ComponentId(65)), isTrue);
      expect(
        uni.componentIds.map((final id) => id.value),
        containsAll([1, 3, 65]),
      );

      final copy = a.copy();
      expect(copy, a);
      expect(a.toString(), contains('1'));

      a.clear(const ComponentId(1));
      expect(a.has(const ComponentId(1)), isFalse);
      a.clear(const ComponentId(120)); // out-of-bounds clear path
      expect(a.has(const ComponentId(120)), isFalse);

      expect(
        () => a.set(const ComponentId(200)),
        throwsA(isA<EcsStateError>()),
      );

      final empty = ComponentMaskImpl();
      expect(empty.toString(), 'ComponentMask(empty)');
      expect(empty == b, isFalse);
    });
  });

  group('EventChannel and factory behavior', () {
    test('factory validation and typed channel reader/writer APIs', () {
      expect(
        () => EventChannelFactory.create<_ObjEvent>(capacity: 0),
        throwsA(isA<EventRegistrationException>()),
      );

      final overflows = <EventCapacityOverflow>[];
      final channel = EventChannelFactory.create<_Vec4Event>(
        capacity: 2,
        metricsHook: overflows.add,
        fromDoubleFieldsFactory: (final fields) =>
            _Vec4Event(fields[0], fields[1], fields[2], fields[3]),
        sampleEvent: const _Vec4Event(0, 0, 0, 0),
      );
      final writer = channel.toWriter();
      final reader = channel.toReader();

      expect(writer.trySend(const _Vec4Event(1, 0, 0, 0)), isTrue);
      writer.send(const _Vec4Event(2, 0, 0, 0));
      expect(reader.length, 2);
      expect(reader.peek()?.a, 1);
      expect(reader.readFirst()?.a, 1);
      expect(reader.readLast()?.a, 2);
      expect(writer.trySend(const _Vec4Event(3, 0, 0, 0)), isFalse); // dropNew
      expect(overflows, hasLength(1));
      expect(overflows.single.dropped, isTrue);

      final batch = reader.drain();
      expect(batch.map((final e) => e.a), [1, 2]);
      final iterValues = <double>[];
      reader.forEach((final e) => iterValues.add(e.a));
      expect(iterValues, [1, 2]);

      channel.clear();
      expect(reader.isEmpty, isTrue);

      expect(
        writer.sendBatch(const [
          _Vec4Event(1, 0, 0, 0),
          _Vec4Event(2, 0, 0, 0),
          _Vec4Event(3, 0, 0, 0),
        ]),
        2,
      );
      expect(channel.readBatch(10).map((final e) => e.a), [1, 2]);
      channel.clear();
      expect(reader.isNotEmpty, isFalse);
    });

    test('dropOld/throwOnOverflow, typed iterSimd and object clear path', () {
      final dropOld = EventChannelFactory.create<_Vec4Event>(
        capacity: 2,
        capacityPolicy: EventCapacityPolicy.dropOld,
        fromDoubleFieldsFactory: (final fields) =>
            _Vec4Event(fields[0], fields[1], fields[2], fields[3]),
        sampleEvent: const _Vec4Event(0, 0, 0, 0),
      );
      dropOld
        ..send(const _Vec4Event(1, 0, 0, 0))
        ..send(const _Vec4Event(2, 0, 0, 0))
        ..send(const _Vec4Event(3, 0, 0, 0));
      expect(dropOld.readBatch(2).map((final e) => e.a), [2, 3]);

      final throws = EventChannelFactory.create<_Vec4Event>(
        capacity: 1,
        capacityPolicy: EventCapacityPolicy.throwOnOverflow,
        fromDoubleFieldsFactory: (final fields) =>
            _Vec4Event(fields[0], fields[1], fields[2], fields[3]),
        sampleEvent: const _Vec4Event(0, 0, 0, 0),
      );
      throws.send(const _Vec4Event(1, 0, 0, 0));
      expect(
        () => throws.send(const _Vec4Event(2, 0, 0, 0)),
        throwsA(isA<EventCapacityOverflow>()),
      );

      final typed = EventChannelFactory.create<_Vec4Event>(
        capacity: 4,
        fromDoubleFieldsFactory: (final fields) =>
            _Vec4Event(fields[0], fields[1], fields[2], fields[3]),
        sampleEvent: const _Vec4Event(0, 0, 0, 0),
      );
      typed.send(const _Vec4Event(1, 2, 3, 4));
      final simdIter = typed.toReader().iterSimd();
      if (simdIter != null) {
        expect(simdIter.first, isA<Float32List>());
      }

      final objectConfig = EventColumnMapper.mapEventType<_ObjEvent>(
        capacity: 2,
      );
      final objectColumn = ObjectColumn<_ObjEvent>(initialCapacity: 2)
        ..addBlank()
        ..addBlank();
      final objectChannel = EventChannel<_ObjEvent>.withColumn(
        column: objectColumn,
        config: objectConfig,
        capacity: 2,
      );
      objectChannel
        ..send(const _ObjEvent(1))
        ..send(const _ObjEvent(2));
      objectChannel.clear();
      expect(objectChannel.isEmpty, isTrue);
    });

    test('cursor/index APIs expose stable snapshots and bounds checks', () {
      final channel = EventChannelFactory.create<_Vec4Event>(
        capacity: 4,
        fromDoubleFieldsFactory: (final fields) =>
            _Vec4Event(fields[0], fields[1], fields[2], fields[3]),
        sampleEvent: const _Vec4Event(0, 0, 0, 0),
      );
      channel
        ..send(const _Vec4Event(1, 0, 0, 0))
        ..send(const _Vec4Event(2, 0, 0, 0));

      final reader = channel.toReader();
      expect(reader.readAt(0).a, 1);
      expect(reader.tryReadAt(2), isNull);
      expect(() => reader.readAt(2), throwsRangeError);

      final cursor = reader.cursor();
      channel.send(const _Vec4Event(3, 0, 0, 0));
      expect(cursor.length, 2);
      expect(cursor.readAt(0).a, 1);
      expect(cursor.readAt(1).a, 2);

      final seen = <double>[];
      while (cursor.moveNext()) {
        seen.add(cursor.current.a);
      }
      expect(seen, [1, 2]);
    });

    test(
      'cursor snapshots invalidate on dropOld and clear structural changes',
      () {
        final channel = EventChannelFactory.create<_Vec4Event>(
          capacity: 2,
          capacityPolicy: EventCapacityPolicy.dropOld,
          fromDoubleFieldsFactory: (final fields) =>
              _Vec4Event(fields[0], fields[1], fields[2], fields[3]),
          sampleEvent: const _Vec4Event(0, 0, 0, 0),
        );
        channel
          ..send(const _Vec4Event(1, 0, 0, 0))
          ..send(const _Vec4Event(2, 0, 0, 0));
        final cursor = channel.toReader().cursor();
        channel.send(const _Vec4Event(3, 0, 0, 0)); // dropOld shifts head
        expect(
          () => cursor.readAt(0),
          throwsA(isA<ConcurrentModificationError>()),
        );

        final clearCursor = channel.toReader().cursor();
        channel.clear();
        expect(
          clearCursor.moveNext,
          throwsA(isA<ConcurrentModificationError>()),
        );
      },
    );
  });

  group('SignatureComputer pooled mask behavior', () {
    test('multi-add and multi-remove compute expected signatures', () {
      const c1 = ComponentId(1);
      const c2 = ComponentId(2);
      const c3 = ComponentId(3);
      final archetype = Archetype(
        archetypeId: const ArchetypeId(42),
        signature: ArchetypeSignature.fromIds(const [c1]),
      );

      final added = SignatureComputer.computeAddSignatureMultiple(archetype, [
        c2,
        c3,
      ]);
      expect(added.has(c1), isTrue);
      expect(added.has(c2), isTrue);
      expect(added.has(c3), isTrue);

      final removed = SignatureComputer.computeRemoveSignatureMultiple(
        Archetype(archetypeId: const ArchetypeId(43), signature: added),
        [c1, c3],
      );
      expect(removed.has(c1), isFalse);
      expect(removed.has(c2), isTrue);
      expect(removed.has(c3), isFalse);
    });

    test('pooled buffers are cleared between calls', () {
      const c1 = ComponentId(1);
      const c2 = ComponentId(2);
      const c3 = ComponentId(3);
      final archetype = Archetype(
        archetypeId: const ArchetypeId(44),
        signature: ArchetypeSignature.fromIds(const [c1]),
      );

      final first = SignatureComputer.computeAddSignatureMultiple(archetype, [
        c2,
      ]);
      final second = SignatureComputer.computeAddSignatureMultiple(archetype, [
        c3,
      ]);

      expect(first.has(c2), isTrue);
      expect(second.has(c2), isFalse);
      expect(second.has(c3), isTrue);
    });
  });

  group('Schedule additional code paths', () {
    test(
      'addSystems/removeSystem/clear/getExecutionRate and throttled tracking',
      () {
        final world = World();
        final ran = <String>[];
        final schedule = Schedule('r', maxExecutionRate: 0.0001)
          ..addSystems([(final w) => ran.add('a'), (final w) => ran.add('b')])
          ..add((final w) => ran.add('c'), name: 'c');

        expect(schedule.removeSystem('missing'), isFalse);
        expect(schedule.removeSystem('c'), isTrue);

        for (var i = 0; i < 12; i++) {
          schedule.run(world);
        }

        expect(ran.isNotEmpty, isTrue);
        expect(schedule.getExecutionRate(), isNotNull);

        schedule.clear();
        expect(schedule.systems, isEmpty);
        schedule.then((final w) => ran.add('after-clear'));
        schedule.run(world);
        expect(ran, contains('after-clear'));
      },
    );
  });
}
