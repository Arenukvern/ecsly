import 'dart:typed_data';

import 'package:ecsly/ecsly.dart';
import 'package:ecsly/src/archetypes/entity_migration_tools/extractors/field_extractors.dart';
import 'package:ecsly/src/archetypes/entity_migration_tools/extractors/list_extractors.dart';
import 'package:ecsly/src/archetypes/entity_migration_tools/extractors/primitive_extractors.dart';
import 'package:test/test.dart';

import '_test_components.dart';

void main() {
  group('Low-coverage utility paths', () {
    test('IntColumn supports stride operations and migration helpers', () {
      final col = IntColumn(initialCapacity: 1, stride: 2);
      col.addBlank();
      col.addBlank();
      col.setValue(0, 0, 1);
      col.setValue(0, 1, 2);
      col.setValue(1, 0, 3);
      col.setValue(1, 1, 4);

      final dst = IntColumn(initialCapacity: 2, stride: 2)
        ..addBlank()
        ..addBlank();
      col.copyTo(1, dst, 0);
      expect(dst.getValue(0, 0), 3);
      expect(dst.getValue(0, 1), 4);

      col.moveTo(0, dst, 1);
      expect(dst.getValue(1, 0), 1);
      expect(col.getValue(0, 0), 0);

      col.swap(0, 1);
      col.swapRemove(1);
      expect(col.length, 1);

      final scalar = IntColumn()..addBlank();
      scalar.setValueAt(0, 55);
      expect(scalar.getValueAt(0), 55);

      final wrongStride = IntColumn()..addBlank();
      expect(() => col.copyTo(0, wrongStride, 0), throwsArgumentError);
    });

    test('SIMD utility and pattern functions execute scalar/simd paths', () {
      final a = FloatColumn(stride: 4, initialCapacity: 2)
        ..addBlank()
        ..set(0, Float32List.fromList([1, 2, 3, 4]));
      final b = FloatColumn(stride: 4, initialCapacity: 2)
        ..addBlank()
        ..set(0, Float32List.fromList([5, 6, 7, 8]));
      final out = FloatColumn(stride: 4, initialCapacity: 2)..addBlank();

      SimdUtils.addColumnsSimd(a, b, out);
      expect(out.getValue(0, 0), 6);
      expect(out.getValue(0, 3), 12);

      final dot = SimdUtils.dotProductSimd(a, b);
      expect(dot.getValue(0, 0), closeTo(70, 0.001));

      SimdUtils.multiplyColumnSimd(a, 2);
      expect(a.getValue(0, 0), 2);

      final pos = FloatColumn(stride: 2, initialCapacity: 2)
        ..addBlank()
        ..set(0, Float32List.fromList([3, 4]));
      final vel = FloatColumn(stride: 2, initialCapacity: 2)
        ..addBlank()
        ..set(0, Float32List.fromList([1, -1]));
      final distOut = FloatColumn(stride: 1, initialCapacity: 2)..addBlank();

      calculateDistancesSimd(pos, Float32x4(0, 0, 0, 0), distOut);
      expect(distOut.getValue(0, 0), closeTo(5, 0.001));

      normalizeVectorsSimd(pos);
      expect(pos.getValue(0, 0), closeTo(0.6, 0.01));
      expect(pos.getValue(0, 1), closeTo(0.8, 0.01));

      scalePositionsSimd(pos, 10);
      expect(pos.getValue(0, 0), closeTo(6, 0.1));

      updatePositionSimd(pos, vel, 0.5);
      expect(pos.getValue(0, 0), closeTo(6.5, 0.1));
    });

    test(
      'extractors and migration system perform expected transformations',
      () {
        final primitive = PrimitiveExtractor();
        expect(primitive.extractFloats(7), [7.0]);
        expect(primitive.extractInt(8.9), 8);
        expect(primitive.extractObject('x'), 'x');

        final listExtractor = ListExtractor();
        expect(listExtractor.extractFloats([1, 2.5]), [1.0, 2.5]);
        expect(listExtractor.extractObject([1, 2]), [1, 2]);

        final xy = XYFieldExtractor<XYData>(
          getX: (final d) => d.x,
          getY: (final d) => d.y,
        );
        expect(xy.extractFloats(const XYData(1.5, 2.5)), [1.5, 2.5]);

        final value = ValueFieldExtractor<ValueData>(
          getValue: (final d) => d.value,
        );
        expect(value.extractFloats(const ValueData(3)), [3.0]);
        expect(value.extractInt(const ValueData(3.9)), 3);

        final world = buildTestWorld();
        world.components.registerObjectComponent<MutableMetric>();
        final e = world.reserveEmptyEntity().entity;
        world.spawnBundle(
          e,
          ComponentBundle.fromLists(const [NameComponent('m')]),
        );
        world.flush();

        final migration = EntityMigrationSystem(
          world.archetypes,
          world.entities,
        );
        final metricId = world.components.getComponentId<MutableMetric>();
        migration.migrateAddComponent(e, metricId, MutableMetric(42));
        expect(world.getComponent<MutableMetric>(e).value, 42);

        migration.migrateRemoveComponent(e, metricId);
        expect(world.query<MutableMetric>(), isEmpty);
      },
    );

    test(
      'executor, descriptors, config, commands, plugins, and debug plugin paths',
      () async {
        final world = buildTestWorld();
        final calls = <String>[];

        final config = IsolateConfig(
          transferData: (final w) => w.entities.count,
          isolateFunction: (final data) => data,
          applyResults: (final w, final _) {},
        );

        final d = SystemDescriptor(
          system: (final _) => calls.add('sync'),
          name: 's',
        );
        final d2 = d.copyWith(name: 's2', mode: ExecutionMode.rustParallel);
        expect(d2.name, 's2');
        expect(d2.mode, ExecutionMode.rustParallel);

        const executor = SystemExecutor();
        executor.executeSchedule(
          world,
          'test',
          [
            [0],
          ],
          [d],
        );

        Future<void> asyncFn(final World _) async {
          calls.add('async');
        }

        Future<void> parFn(final World _) async {
          calls.add('parallel');
        }

        final isolateDesc = SystemDescriptor(
          system: (final _) => calls.add('isolate'),
          mode: ExecutionMode.isolate,
          isolateConfig: config,
        );

        await executor.executeScheduleAsync(
          world,
          'test_async',
          [
            [0, 1, 2, 3],
          ],
          [
            SystemDescriptor(system: (final _) => calls.add('sync2')),
            SystemDescriptor(system: asyncFn, mode: ExecutionMode.async),
            SystemDescriptor(
              system: parFn,
              mode: ExecutionMode.asyncParallel,
              canRunInParallel: true,
            ),
            isolateDesc,
          ],
        );

        expect(
          calls,
          containsAll(['sync', 'sync2', 'async', 'parallel', 'isolate']),
        );

        await expectLater(
          () => executor.executeScheduleAsync(
            world,
            'test_isolate_error',
            [
              [0],
            ],
            [
              const SystemDescriptor(
                system: _noopSystem,
                mode: ExecutionMode.isolate,
              ),
            ],
          ),
          throwsA(isA<SystemConfigurationError>()),
        );

        final cmd = ComponentCommands(
          queue: world.commandQueue,
          component: const NameComponent('x'),
        );
        expect(cmd.component, isA<NameComponent>());

        final p1 = PersistentEntity.create();
        final p2 = PersistentEntity.create();
        expect(p1, isNot(p2));

        world.addPlugin(BarePlugin());
        expect(world.removePlugin('bare'), isTrue);

        world.upsertResource(DeltaTimeResource(0.016));
        world.addPlugin(DebugPlugin());
        world.runSchedule('HighFrequency');
        expect(
          world.getResource<PerformanceResource>().frameTime,
          greaterThan(0),
        );
        expect(
          world.getResource<SpawnPerformanceResource>().flushTimeMs,
          greaterThanOrEqualTo(0),
        );
        expect(world.removePlugin('debug'), isTrue);

        // Also exercise explicit phase systems.
        flushEntitiesSystem(world);
        flushComponentsSystem(world);
        flushResourcesSystem(world);
        flushCommandsSystem(world);
        flushAllSystem(world);

        final state = LevelStateResource(currentLevel: 'menu');
        final transitioning = state.transitionTo('level1');
        expect(transitioning.isTransitioning, isTrue);
        expect(transitioning.completeTransition().currentLevel, 'level1');
      },
    );
  });
}

void _noopSystem(final World _) {}

class BarePlugin extends Plugin {
  @override
  String get name => 'bare';

  @override
  void install(final World world) {}
}

class MutableMetric extends Component {
  MutableMetric(this.value);
  int value;
}
