import 'package:ecs_input_plugin/ecs_input_plugin.dart';
import 'package:ecsly/ecsly.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ordering regression: the ecsly scheduler resolves systems WITHOUT
/// dependency edges alphabetically (topological tie-break over a
/// lexicographic comparator), not by insertion order. An earlier version of
/// configureInputSchedule relied on insertion order — under the real
/// scheduler `eventInputClearSystem` (temp name `__then_N`, sorting before
/// every letter-named system) ran SECOND and dropped the raw events before
/// classification, killing the whole pipeline. These tests pin the explicit
/// runAfter chain end-to-end.
void main() {
  const down = RawPointerDownEvent(
    position: Offset(10, 10),
    worldPosition: Offset(10, 10),
    timestamp: 1000,
    pointer: 1,
  );
  const up = RawPointerUpEvent(
    position: Offset(10, 10),
    worldPosition: Offset(10, 10),
    timestamp: 1002,
    pointer: 1,
  );

  test('classified taps reach additionalSystems; clear runs last', () {
    final world = World();
    world.systems.plugins.add(
      const InputPlugin(configureSchedule: false),
      world,
    );

    final seen = <String>[];
    configureInputSchedule(
      world,
      additionalSystems: [
        (final w) {
          seen.add('consumer');
          if (w.events.reader<TapEvent>().isNotEmpty) seen.add('tapVisible');
        },
      ],
    );
    // A late host system (the orbit-camera shape): explicit edges pin it
    // after classification and before the clear.
    world
        .schedule(const ScheduleId('Input'))
        .add(
          (final w) {
            seen.add('lateHost');
            if (w.events.reader<TapEvent>().isNotEmpty)
              seen.add('tapVisibleLate');
          },
          name: 'lateHostSystem',
          runAfter: ['scaleClassificationSystem'],
          runBefore: ['eventInputClearSystem'],
        );
    world.flush();

    world.events
      ..writer<RawPointerDownEvent>().send(down)
      ..writer<RawPointerUpEvent>().send(up);
    world.runSchedule(const ScheduleId('Input'));

    // Both consumers ran AFTER classification produced the tap (their
    // relative order is topologically free — both are pinned only between
    // classification and the clear).
    expect(seen, containsAll(<String>['consumer', 'lateHost']));
    expect(seen, contains('tapVisible'));
    expect(seen, contains('tapVisibleLate'));
    // Each consumer immediately saw the tap when it ran.
    expect(seen.indexOf('tapVisible'), seen.indexOf('consumer') + 1);
    expect(seen.indexOf('tapVisibleLate'), seen.indexOf('lateHost') + 1);
    // ...and the clear ran LAST (nothing survives the run).
    expect(world.events.reader<TapEvent>().isNotEmpty, isFalse);
    expect(world.events.reader<RawPointerUpEvent>().isNotEmpty, isFalse);
  });

  test('raw down/up through the schedule produces and consumes a tap', () {
    final world = World();
    world.systems.plugins.add(const InputPlugin(), world);
    var tapsSeen = 0;
    world
        .schedule(const ScheduleId('Input'))
        .add(
          (final w) => tapsSeen += w.events.reader<TapEvent>().iter().length,
          name: 'tapCounter',
          runAfter: ['gestureClassificationSystem'],
          runBefore: ['eventInputClearSystem'],
        );
    world.flush();

    world.events
      ..writer<RawPointerDownEvent>().send(down)
      ..writer<RawPointerUpEvent>().send(up);
    world.runSchedule(const ScheduleId('Input'));

    expect(tapsSeen, 1);
    // Second run with no new events: the trigger stays off, nothing repeats.
    world.runSchedule(const ScheduleId('Input'));
    expect(tapsSeen, 1);
  });
}
