import 'package:ecsly/ecsly.dart';

import 'components.dart';

class FrameClockResource extends Resource {
  FrameClockResource({required this.deltaSeconds});

  final double deltaSeconds;
  int frame = 0;
}

void installFrameClock(
  final World world, {
  required final double deltaSeconds,
}) {
  world.upsertResource(FrameClockResource(deltaSeconds: deltaSeconds));
}

void tickFrameClockSystem(final World world) {
  final clock = world.getResource<FrameClockResource>();
  clock.frame += 1;
}

void queueCounterChangesSystem(final World world) {
  for (final (entity, counter) in world.query<CounterComponent>()) {
    if (counter.value >= 2) {
      // Structural changes are queued so iteration can finish safely.
      entity.remove<CounterComponent>();
    } else {
      entity.insert(CounterComponent(counter.value + 1));
    }
  }
}

void addUpdateSystems(final World world) {
  world.createSchedule('Update')
    ..add(tickFrameClockSystem)
    ..add(queueCounterChangesSystem);
}

void main() {
  final world = World();
  registerCounterComponents(world);

  // Resources hold world-level data. Systems read or mutate that data.
  installFrameClock(world, deltaSeconds: 1 / 60);

  final entity = world.reserveEmptyEntity().entity;
  world.spawnBundle(entity, ComponentBundle.fromLists([CounterComponent(1)]));
  world.flush();

  // Schedules wire behavior. Resources do not own commands or systems.
  addUpdateSystems(world);

  for (var i = 0; i < 3; i++) {
    world.runSchedule('Update');
    world.flush();

    final frame = world.getResource<FrameClockResource>().frame;
    final remaining = world.queryCount<CounterComponent>();
    print('frame=$frame counters=$remaining');
  }
}
