import 'dart:developer';

import 'package:ecsly/ecsly.dart';
import 'components.dart';

void main() {
  final world = World();

  registerCounterComponents(world);

  // Structural changes are queued. reserveEmptyEntity gives us an entity ID now,
  // then spawnBundle attaches its initial component set on the next flush.
  final entity = world.reserveEmptyEntity().entity;
  world.spawnBundle(entity, ComponentBundle.fromLists([CounterComponent(1)]));

  // After flush, queries and entity wrappers can see the spawned component.
  world.flush();

  final (worldEntity, isValid) = world.getEntity(entity);
  if (!isValid) {
    return;
  }

  // Object components are normal Dart objects. getMut returns the stored object,
  // so this mutates the component in place.
  worldEntity.toMut().getMut<CounterComponent>().value += 1;

  for (final (_, counter) in world.query<CounterComponent>()) {
    log('Counter value: ${counter.value}');
  }
}
