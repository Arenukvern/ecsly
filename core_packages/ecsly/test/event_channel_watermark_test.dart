// ignore_for_file: lines_longer_than_80_chars

/// Tests for the channel watermark API (`EventChannel.stats`).
///
/// The invariant `sent == consumed + dropped + cleared + length` is the
/// one-line assert that turns "data loss" questions into named failures.
library;

import 'package:ecsly/ecsly.dart';
import 'package:test/test.dart';

class WmEvent extends EcsEvent {
  WmEvent(this.payload);
  final String payload;
}

void main() {
  group('channel watermark', () {
    late World world;

    setUp(() {
      world = World();
      world.events.register<WmEvent>(
        capacity: 4,
        capacityPolicy: EventCapacityPolicy.dropOld,
      );
    });

    tearDown(() => world.clear());

    test('invariant holds across send/drain cycles', () {
      final writer = world.events.writer<WmEvent>();
      writer.send(WmEvent('a'));
      writer.send(WmEvent('b'));
      expect(world.events.stats<WmEvent>().isConsistent, isTrue);

      world.events.reader<WmEvent>().drain();
      final s = world.events.stats<WmEvent>();
      expect(s.sent, 2);
      expect(s.consumed, 2);
      expect(s.length, 0);
      expect(s.isConsistent, isTrue);
    });

    test('dropOld overflow counts as dropped', () {
      final writer = world.events.writer<WmEvent>();
      for (var i = 0; i < 6; i++) {
        writer.send(WmEvent('m$i'));
      }
      final s = world.events.stats<WmEvent>();
      expect(s.sent, 6);
      expect(s.dropped, 2); // capacity 4, dropOld policy
      expect(s.length, 4);
      expect(s.isConsistent, isTrue);
    });

    test('clear without drain counts as cleared', () {
      world.events.writer<WmEvent>().send(WmEvent('x'));
      world.events.channel<WmEvent>().clear();
      final s = world.events.stats<WmEvent>();
      expect(s.cleared, 1);
      expect(s.consumed, 0);
      expect(s.isConsistent, isTrue);
    });

    test('resetStats zeroes counters but keeps buffered events', () {
      final writer = world.events.writer<WmEvent>();
      writer.send(WmEvent('keep'));
      world.events.channel<WmEvent>().resetStats();
      final s = world.events.stats<WmEvent>();
      expect(s.sent, 0);
      expect(s.length, 1); // buffered event untouched
      // Invariant is relative to the reset point: sent(0) vs length(1) means
      // one pre-reset send — document, don't assert consistency here.
    });
  });
}
