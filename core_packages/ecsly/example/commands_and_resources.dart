import 'package:ecsly/ecsly.dart';

import 'components.dart';

class FrameClockResource extends Resource {
  FrameClockResource({required this.deltaSeconds});

  final double deltaSeconds;
  int frame = 0;
}

void countAndQueueChanges(final World world) {
  final clock = world.getResource<FrameClockResource>();
  clock.frame += 1;

  for (final (entity, counter) in world.query<CounterComponent>()) {
    if (counter.value >= 2) {
      // Structural changes are queued so iteration can finish safely.
      entity.remove<CounterComponent>();
    } else {
      entity.insert(CounterComponent(counter.value + 1));
    }
  }
}

void main() {
  final world = World();
  registerCounterComponents(world);

  world.upsertResource(FrameClockResource(deltaSeconds: 1 / 60));

  final entity = world.reserveEmptyEntity().entity;
  world.spawnBundle(entity, ComponentBundle.fromLists([CounterComponent(1)]));
  world.flush();

  world.createSchedule('Update').add(countAndQueueChanges);

  for (var i = 0; i < 3; i++) {
    world.runSchedule('Update');
    world.flush();

    final frame = world.getResource<FrameClockResource>().frame;
    final remaining = world.queryCount<CounterComponent>();
    print('frame=$frame counters=$remaining');
  }
}
