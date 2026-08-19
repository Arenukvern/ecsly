import 'package:test/test.dart';

void main() {
  group('', () {
    // TODO: restore minimal relevant test
    // test(
    //   'executor, descriptors, config, commands, plugins, and debug plugin paths',
    //   () async {
    //     final world = buildTestWorld();
    //     final calls = <String>[];

    //     final config = IsolateConfig(
    //       transferData: (final w) => w.entities.count,
    //       isolateFunction: (final data) => data,
    //       applyResults: (final w, final _) {},
    //     );

    //     final d = SystemDescriptor(
    //       system: (final _) => calls.add('sync'),
    //       name: 's',
    //     );
    //     final d2 = d.copyWith(name: 's2', mode: ExecutionMode.rustParallel);
    //     expect(d2.name, 's2');
    //     expect(d2.mode, ExecutionMode.rustParallel);

    //     const executor = SystemExecutor();
    //     executor.executeSchedule(
    //       world,
    //       'test',
    //       [
    //         [0],
    //       ],
    //       [d],
    //     );

    //     Future<void> asyncFn(final World _) async {
    //       calls.add('async');
    //     }

    //     Future<void> parFn(final World _) async {
    //       calls.add('parallel');
    //     }

    //     final isolateDesc = SystemDescriptor(
    //       system: (final _) => calls.add('isolate'),
    //       mode: ExecutionMode.isolate,
    //       isolateConfig: config,
    //     );

    //     await executor.executeScheduleAsync(
    //       world,
    //       'test_async',
    //       [
    //         [0, 1, 2, 3],
    //       ],
    //       [
    //         SystemDescriptor(system: (final _) => calls.add('sync2')),
    //         SystemDescriptor(system: asyncFn, mode: ExecutionMode.async),
    //         SystemDescriptor(
    //           system: parFn,
    //           mode: ExecutionMode.asyncParallel,
    //           canRunInParallel: true,
    //         ),
    //         isolateDesc,
    //       ],
    //     );

    //     expect(
    //       calls,
    //       containsAll(['sync', 'sync2', 'async', 'parallel', 'isolate']),
    //     );

    //     await expectLater(
    //       () => executor.executeScheduleAsync(
    //         world,
    //         'test_isolate_error',
    //         [
    //           [0],
    //         ],
    //         [
    //           const SystemDescriptor(
    //             system: _noopSystem,
    //             mode: ExecutionMode.isolate,
    //           ),
    //         ],
    //       ),
    //       throwsA(isA<SystemConfigurationError>()),
    //     );

    //     final cmd = ComponentCommands(
    //       queue: world.commandQueue,
    //       component: const NameComponent('x'),
    //     );
    //     expect(cmd.component, isA<NameComponent>());

    //     final p1 = PersistentEntity.create();
    //     final p2 = PersistentEntity.create();
    //     expect(p1, isNot(p2));

    //     world.addPlugin(BarePlugin());
    //     expect(world.removePlugin('bare'), isTrue);

    //     world.upsertResource(DeltaTimeResource(0.016));
    //     world.addPlugin(DebugPlugin());
    //     world.runSchedule('HighFrequency');
    //     expect(
    //       world.getResource<PerformanceResource>().frameTime,
    //       greaterThan(0),
    //     );
    //     expect(
    //       world.getResource<SpawnPerformanceResource>().flushTimeMs,
    //       greaterThanOrEqualTo(0),
    //     );
    //     expect(world.removePlugin('debug'), isTrue);

    //     // Also exercise explicit phase systems.
    //     flushEntitiesSystem(world);
    //     flushComponentsSystem(world);
    //     flushResourcesSystem(world);
    //     flushCommandsSystem(world);
    //     flushAllSystem(world);

    //     final state = LevelStateResource(currentLevel: 'menu');
    //     final transitioning = state.transitionTo('level1');
    //     expect(transitioning.isTransitioning, isTrue);
    //     expect(transitioning.completeTransition().currentLevel, 'level1');
    //   },
    // );
  });
}
