import 'dart:ui' as ui;

import 'package:ecsly/ecsly.dart';
import 'package:ecs_input_plugin/ecs_input_plugin.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ScaleClassificationSystem', () {
    late World world;

    setUp(() {
      world = World()..addPlugin(InputPlugin());

      // Clear any existing events
      world.events.clearAll();
    });

    test('converts RawScaleUpdateEvent to PinchEvent', () {
      // Send a RawScaleUpdateEvent
      const focalPoint = ui.Offset(100, 200);
      const focalPointDelta = ui.Offset(3, -4);
      const rotation = 0.25;
      const pointerCount = 2;
      const scale = 1.5;
      const timestamp = 1234567890;

      world.events.writer<RawScaleUpdateEvent>().send(
        RawScaleUpdateEvent(
          focalPoint: focalPoint,
          focalPointDelta: focalPointDelta,
          rotation: rotation,
          pointerCount: pointerCount,
          scale: scale,
          timestamp: timestamp,
        ),
      );

      // Run the scale classification system
      scaleClassificationSystem(world);

      // Verify PinchEvent was created
      final pinchEvents = world.events.reader<PinchEvent>().iter().toList();
      expect(pinchEvents, hasLength(1));

      final pinchEvent = pinchEvents.first;
      expect(pinchEvent.position, equals(focalPoint));
      expect(
        pinchEvent.worldPosition,
        equals(focalPoint),
      ); // screen = world for now
      expect(pinchEvent.scale, equals(scale));
      expect(pinchEvent.focalPoint, equals(focalPoint));
      expect(pinchEvent.focalPointDelta, equals(focalPointDelta));
      expect(pinchEvent.rotation, equals(rotation));
      expect(pinchEvent.pointerCount, equals(pointerCount));
      expect(pinchEvent.timestamp, closeTo(timestamp, 100));
    });

    test('handles multiple RawScaleUpdateEvent events', () {
      // Send multiple RawScaleUpdateEvent events
      world.events.writer<RawScaleUpdateEvent>().send(
        RawScaleUpdateEvent(
          focalPoint: ui.Offset(100, 200),
          focalPointDelta: ui.Offset(1, 2),
          rotation: 0.1,
          pointerCount: 2,
          scale: 1.2,
          timestamp: 1000,
        ),
      );

      world.events.writer<RawScaleUpdateEvent>().send(
        RawScaleUpdateEvent(
          focalPoint: ui.Offset(150, 250),
          focalPointDelta: ui.Offset(-2, 5),
          rotation: -0.2,
          pointerCount: 3,
          scale: 0.8,
          timestamp: 2000,
        ),
      );

      // Run the scale classification system
      scaleClassificationSystem(world);

      // Verify PinchEvents were created
      final pinchEvents = world.events.reader<PinchEvent>().iter().toList();
      expect(pinchEvents, hasLength(2));

      expect(pinchEvents[0].scale, closeTo(1.2, 0.001));
      expect(pinchEvents[0].focalPointDelta, const ui.Offset(1, 2));
      expect(pinchEvents[0].rotation, closeTo(0.1, 1e-6));
      expect(pinchEvents[0].pointerCount, 2);
      expect(pinchEvents[1].scale, closeTo(0.8, 0.001));
      expect(pinchEvents[1].focalPointDelta, const ui.Offset(-2, 5));
      expect(pinchEvents[1].rotation, closeTo(-0.2, 1e-6));
      expect(pinchEvents[1].pointerCount, 3);
    });

    test('consumes RawScaleStartEvent and RawScaleEndEvent without error', () {
      // Send start and end events (should be consumed without creating PinchEvent)
      world.events.writer<RawScaleStartEvent>().send(
        const RawScaleStartEvent(
          focalPoint: ui.Offset(100, 200),
          timestamp: 1000,
        ),
      );

      world.events.writer<RawScaleEndEvent>().send(
        const RawScaleEndEvent(timestamp: 2000),
      );

      // Run the scale classification system
      scaleClassificationSystem(world);

      // Verify no PinchEvent was created (only update events create PinchEvent)
      final pinchEvents = world.events.reader<PinchEvent>().iter().toList();
      expect(pinchEvents, isEmpty);
    });

    test('preserves event order and data integrity', () {
      // Test with different scale values to ensure no data corruption
      const testCases = [
        (
          focalPoint: ui.Offset(10, 20),
          focalPointDelta: ui.Offset(1, 1),
          rotation: 0.15,
          pointerCount: 2,
          scale: 2.0,
          timestamp: 1111,
        ),
        (
          focalPoint: ui.Offset(30, 40),
          focalPointDelta: ui.Offset(-3, 4),
          rotation: -0.5,
          pointerCount: 3,
          scale: 0.5,
          timestamp: 2222,
        ),
        (
          focalPoint: ui.Offset(50, 60),
          focalPointDelta: ui.Offset.zero,
          rotation: 0.0,
          pointerCount: 4,
          scale: 1.0,
          timestamp: 3333,
        ),
      ];

      for (final testCase in testCases) {
        world.events.writer<RawScaleUpdateEvent>().send(
          RawScaleUpdateEvent(
            focalPoint: testCase.focalPoint,
            focalPointDelta: testCase.focalPointDelta,
            rotation: testCase.rotation,
            pointerCount: testCase.pointerCount,
            scale: testCase.scale,
            timestamp: testCase.timestamp,
          ),
        );
      }

      scaleClassificationSystem(world);

      final pinchEvents = world.events.reader<PinchEvent>().iter().toList();
      expect(pinchEvents, hasLength(3));

      for (var i = 0; i < testCases.length; i++) {
        final testCase = testCases[i];
        final pinchEvent = pinchEvents[i];
        expect(pinchEvent.focalPoint, equals(testCase.focalPoint));
        expect(pinchEvent.focalPointDelta, equals(testCase.focalPointDelta));
        expect(pinchEvent.rotation, closeTo(testCase.rotation, 1e-6));
        expect(pinchEvent.pointerCount, equals(testCase.pointerCount));
        expect(pinchEvent.scale, closeTo(testCase.scale, 0.001));
        expect(pinchEvent.timestamp, equals(testCase.timestamp));
      }
    });

    test('RawScaleUpdateEvent parses additive fields from numeric payload', () {
      final event = RawScaleUpdateEvent.fromDoubleFields([
        10.0,
        20.0,
        1.5,
        1234.0,
        -7.0,
        8.0,
        0.33,
        4.0,
      ]);

      expect(event.focalPoint, const ui.Offset(10, 20));
      expect(event.scale, 1.5);
      expect(event.timestamp, 1234);
      expect(event.focalPointDelta, const ui.Offset(-7, 8));
      expect(event.rotation, closeTo(0.33, 1e-9));
      expect(event.pointerCount, 4);
    });

    test(
      'RawScaleUpdateEvent preserves backward-compatible parsing defaults',
      () {
        final event = RawScaleUpdateEvent.fromDoubleFields([
          10.0,
          20.0,
          1.5,
          1234.0,
        ]);

        expect(event.focalPoint, const ui.Offset(10, 20));
        expect(event.scale, 1.5);
        expect(event.timestamp, 1234);
        expect(event.focalPointDelta, ui.Offset.zero);
        expect(event.rotation, 0.0);
        expect(event.pointerCount, 0);
      },
    );

    test('PinchEvent preserves backward-compatible parsing defaults', () {
      final event = PinchEvent.fromDoubleFields([
        1.0,
        2.0,
        3.0,
        4.0,
        5678.0,
        0.75,
        9.0,
        10.0,
      ]);

      expect(event.position, const ui.Offset(1, 2));
      expect(event.worldPosition, const ui.Offset(3, 4));
      expect(event.timestamp, 5678);
      expect(event.scale, 0.75);
      expect(event.focalPoint, const ui.Offset(9, 10));
      expect(event.focalPointDelta, ui.Offset.zero);
      expect(event.rotation, 0.0);
      expect(event.pointerCount, 0);
    });
  });
}
