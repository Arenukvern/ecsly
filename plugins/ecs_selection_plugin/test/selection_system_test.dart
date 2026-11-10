import 'package:ecs_picking_plugin/ecs_picking_plugin.dart';
import 'package:ecs_selection_plugin/ecs_selection_plugin.dart';
import 'package:ecsly/ecsly.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('selectionSystem', () {
    test('does nothing when no new picking hit', () {
      final world = World();
      world.addPlugin(const PickingPlugin());
      world.addPlugin(const SelectionPlugin());

      selectionSystem(world);

      final state = world.getResource<SelectionStateResource>();
      expect(state.selectedKey, isNull);
    });

    test('updates selection state from picking result', () {
      final world = World();
      world.addPlugin(const PickingPlugin());
      world.addPlugin(const SelectionPlugin());

      final result = world.getResource<PickingResultResource>();
      result
        ..hasNewHit = true
        ..hitKey = 'test-body'
        ..hitX = 1.0
        ..hitY = 2.0
        ..hitZ = 3.0
        ..normalX = 0.0
        ..normalY = 1.0
        ..normalZ = 0.0;

      selectionSystem(world);

      final state = world.getResource<SelectionStateResource>();
      expect(state.selectedKey, 'test-body');
      expect(state.hitX, 1.0);
      expect(state.hitY, 2.0);
      expect(state.hitZ, 3.0);
      expect(state.normalX, 0.0);
      expect(state.normalY, 1.0);
      expect(state.normalZ, 0.0);
    });

    test('clears hasNewHit after processing', () {
      final world = World();
      world.addPlugin(const PickingPlugin());
      world.addPlugin(const SelectionPlugin());

      final result = world.getResource<PickingResultResource>();
      result
        ..hasNewHit = true
        ..hitKey = 'test-body';

      selectionSystem(world);

      expect(result.hasNewHit, isFalse);
    });

    test('does not re-process on next frame without new hit', () {
      final world = World();
      world.addPlugin(const PickingPlugin());
      world.addPlugin(const SelectionPlugin());

      final result = world.getResource<PickingResultResource>();
      result
        ..hasNewHit = true
        ..hitKey = 'first';

      selectionSystem(world);
      expect(world.getResource<SelectionStateResource>().selectedKey, 'first');

      // Second frame: no new hit, selection unchanged.
      selectionSystem(world);
      expect(world.getResource<SelectionStateResource>().selectedKey, 'first');
    });
  });
}
