import 'package:ecsly/ecsly.dart';
import 'package:ecsly_world_sync_bridge/ecsly_world_sync_bridge.dart';
import 'package:test/test.dart';

import 'test_components.dart';

void main() {
  test('plugin emits deltas on every flush boundary', () {
    final world = buildTestWorld();
    final sync = WorldSync(actorId: 'a');
    world.addPlugin(WorldSyncBridgePlugin(sync: sync, clock: TestClock().tick));

    final state = world.getResource<WorldSyncBridgeResource>();
    expect(state.session, isNull);
    expect(state.bridge.isAttached, isTrue);

    final ship = spawnShip(world, 1, health: true);
    writeColumn(world, ship, PositionComponent, 0, 1.5);
    world.flush();

    expect(
      sync.projection.componentValue(
        entityKey: '1',
        component: 'PositionComponent',
        field: '0',
      ),
      1.5,
    );
  });

  test('inert install leaves the cadence to the host', () {
    final world = buildTestWorld();
    final sync = WorldSync(actorId: 'a');
    world.addPlugin(
      WorldSyncBridgePlugin(sync: sync, attachFlushObserver: false),
    );

    final ship = spawnShip(world, 2);
    writeColumn(world, ship, PositionComponent, 0, 3);
    world.flush();
    expect(sync.projection.values, isEmpty);

    final ops = world
        .getResource<WorldSyncBridgeResource>()
        .bridge
        .emitDeltas();
    expect(ops, greaterThan(0));
    expect(
      sync.projection.componentValue(
        entityKey: '2',
        component: 'PositionComponent',
        field: '0',
      ),
      3.0,
    );
  });

  test('uninstall detaches the observer and removes the resource', () {
    final world = buildTestWorld();
    final sync = WorldSync(actorId: 'a');
    world.addPlugin(WorldSyncBridgePlugin(sync: sync));

    expect(world.removePlugin('ecsly_world_sync_bridge'), isTrue);
    expect(world.maybeGetResource<WorldSyncBridgeResource>(), isNull);

    final ship = spawnShip(world, 3);
    writeColumn(world, ship, PositionComponent, 0, 7);
    world.flush();
    expect(sync.projection.values, isEmpty);
  });

  test('duplicate install is rejected', () {
    final world = buildTestWorld();
    world.addPlugin(WorldSyncBridgePlugin(sync: WorldSync(actorId: 'a')));
    expect(
      () => world.addPlugin(WorldSyncBridgePlugin(sync: WorldSync(actorId: 'b'))),
      throwsA(isA<PluginInstallationException>()),
    );
  });
}
