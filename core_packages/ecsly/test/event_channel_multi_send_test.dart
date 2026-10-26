// ignore_for_file: lines_longer_than_80_chars

/// Minimal failing tests for EventChannel ring-buffer + ObjectColumn
/// interaction under multi-send-per-tick workloads (agent harness pattern:
/// one handler sends N responses in a single tick, systems drain per tick).
///
/// Reproduces data loss seen in xsoulspace_inference_core coding-suite runs:
/// events sent by a handler during a tick were read back as null/garbage by
/// the next drain.
library;

import 'package:ecsly/ecsly.dart';
import 'package:test/test.dart';

/// Plain object event (ObjectColumn path — same as ActorGenerateResponse).
class MsgEvent extends EcsEvent {
  MsgEvent(this.payload);
  final String payload;
}

void main() {
  group('EventChannel multi-send per tick (ObjectColumn)', () {
    late World world;

    setUp(() {
      world = World();
      world.events.register<MsgEvent>(capacity: 256);
    });

    tearDown(() => world.clear());

    test('send 3, drain once, read all 3 intact', () {
      final writer = world.events.writer<MsgEvent>();
      writer.send(MsgEvent('one'));
      writer.send(MsgEvent('two'));
      writer.send(MsgEvent('three'));

      final drained = world.events.reader<MsgEvent>().drain();
      expect(drained, hasLength(3));
      expect(drained[0].payload, 'one');
      expect(drained[1].payload, 'two');
      expect(drained[2].payload, 'three');
    });

    test('drain then send again in same tick (drain→clear→send cycle)', () {
      final writer = world.events.writer<MsgEvent>();
      writer.send(MsgEvent('first'));
      expect(world.events.reader<MsgEvent>().drain(), hasLength(1));

      // Same-tick re-send after drain+clear — the harness does this when a
      // system processes events and emits follow-ups.
      writer.send(MsgEvent('second'));
      final drained = world.events.reader<MsgEvent>().drain();
      expect(drained, hasLength(1));
      expect(drained.single.payload, 'second');
    });

    test('send during drain iteration is not lost (snapshot semantics)', () {
      final writer = world.events.writer<MsgEvent>();
      writer.send(MsgEvent('a'));
      writer.send(MsgEvent('b'));

      final seen = <String>[];
      for (final e in world.events.reader<MsgEvent>().iter()) {
        seen.add(e.payload);
        // Simulate a system emitting a follow-up event mid-iteration.
        writer.send(MsgEvent('during-${e.payload}'));
      }
      expect(seen, ['a', 'b']);

      // Follow-ups must be visible to the next drain.
      final next = world.events.reader<MsgEvent>().drain();
      expect(next.map((e) => e.payload), containsAll(['during-a', 'during-b']));
    });

    test(
      'wraparound: send capacity+10 events, oldest dropped, rest intact',
      () {
        final writer = world.events.writer<MsgEvent>();
        for (var i = 0; i < 266; i++) {
          writer.send(MsgEvent('m$i'));
        }
        final drained = world.events.reader<MsgEvent>().drain();
        expect(drained, hasLength(256));
        // dropOld policy is the default for agent channels; with default
        // dropNew this asserts the first 256 survive intact instead.
        for (var i = 0; i < drained.length; i++) {
          expect(drained[i].payload, 'm$i', reason: 'index $i corrupted');
        }
      },
    );

    test('interleaved drain cycles across many ticks keep all events', () {
      final writer = world.events.writer<MsgEvent>();
      for (var tick = 0; tick < 50; tick++) {
        writer.send(MsgEvent('t${tick}a'));
        writer.send(MsgEvent('t${tick}b'));
        final drained = world.events.reader<MsgEvent>().drain();
        expect(drained, hasLength(2), reason: 'tick $tick lost events');
        expect(drained[0].payload, 't${tick}a');
        expect(drained[1].payload, 't${tick}b');
      }
    });
  });
}
