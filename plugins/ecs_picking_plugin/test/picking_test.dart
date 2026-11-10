import 'package:ecsly/ecsly.dart';
import 'package:ecs_picking_plugin/ecs_picking_plugin.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PickingPlugin', () {
    test('registers intent and result resources', () {
      final world = World();
      world.addPlugin(const PickingPlugin());

      expect(world.resources.has<PickingIntentResource>(), isTrue);
      expect(world.resources.has<PickingResultResource>(), isTrue);
    });

    test('intent defaults to not pending', () {
      final world = World();
      world.addPlugin(const PickingPlugin());

      final intent = world.getResource<PickingIntentResource>();
      expect(intent.pending, isFalse);
    });

    test('result defaults to no hit', () {
      final world = World();
      world.addPlugin(const PickingPlugin());

      final result = world.getResource<PickingResultResource>();
      expect(result.hasNewHit, isFalse);
      expect(result.hitKey, isNull);
    });
  });
}
