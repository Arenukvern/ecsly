import 'dart:ui' as ui;

import 'package:ecs_input_plugin/ecs_input_plugin.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('GestureClassificationState Double-Tap Detection', () {
    late GestureClassificationState state;

    setUp(() {
      state = GestureClassificationState();
    });

    group('Single tap', () {
      test('should classify as tap but not double-tap', () {
        final now = DateTime.now();

        // Down event
        state.onPointerDown(
          RawPointerDownEvent(
            pointer: 1,
            position: ui.Offset(100, 100),
            worldPosition: ui.Offset(100, 100),
            timestamp: now.millisecondsSinceEpoch,
          ),
          now,
        );

        // Up event (tap)
        final upEvent = RawPointerUpEvent(
          pointer: 1,
          position: ui.Offset(100, 100),
          worldPosition: ui.Offset(100, 100),
          timestamp: now
              .add(const Duration(milliseconds: 100))
              .millisecondsSinceEpoch,
        );
        state.checkForDoubleTap(
          upEvent,
          now.add(const Duration(milliseconds: 100)),
        );

        // Check classification - should be tap (not double-tap)
        final gesture = state.classifyGesture(
          1,
          now.add(const Duration(milliseconds: 100)),
        );
        expect(gesture, GestureType.tap);

        state.onPointerUp(upEvent, now.add(const Duration(milliseconds: 100)));
      });
    });

    group('Current gesture display tracking', () {
      test('should display recent gesture within display window', () {
        final state = GestureClassificationState();
        final now = DateTime.now();

        // Record a completed tap gesture
        state.recordCompletedGesture(GestureType.tap, now);

        // Should show tap immediately
        expect(state.getCurrentGestureDisplay(now), 'tap');

        // Should still show tap within display window (299ms later)
        final laterTime = now.add(const Duration(milliseconds: 299));
        expect(state.getCurrentGestureDisplay(laterTime), 'tap');

        // Should show none after display window expires (301ms later)
        final expiredTime = now.add(const Duration(milliseconds: 301));
        expect(state.getCurrentGestureDisplay(expiredTime), 'none');
      });

      test('should prioritize active gestures over recent completed ones', () {
        final state = GestureClassificationState();
        final now = DateTime.now();

        // Record a completed tap gesture
        state.recordCompletedGesture(GestureType.tap, now);

        // Simulate an active drag gesture
        state.onPointerDown(
          RawPointerDownEvent(
            pointer: 1,
            position: ui.Offset(100, 100),
            worldPosition: ui.Offset(100, 100),
            timestamp: now.millisecondsSinceEpoch,
          ),
          now,
        );

        state.onPointerMove(
          RawPointerMoveEvent(
            pointer: 1,
            position: ui.Offset(110, 110),
            worldPosition: ui.Offset(110, 110),
            delta: ui.Offset(10, 10),
            timestamp: now
                .add(const Duration(milliseconds: 10))
                .millisecondsSinceEpoch,
          ),
          now.add(const Duration(milliseconds: 10)),
        );

        // Should show active drag, not the recent tap
        expect(
          state.getCurrentGestureDisplay(
            now.add(const Duration(milliseconds: 10)),
          ),
          'drag',
        );
      });
    });

    group('Double tap within timeout and distance', () {
      test('should detect double-tap with same pointer ID', () {
        final now = DateTime.now();

        // First tap - down
        state.onPointerDown(
          RawPointerDownEvent(
            pointer: 1,
            position: ui.Offset(100, 100),
            worldPosition: ui.Offset(100, 100),
            timestamp: now.millisecondsSinceEpoch,
          ),
          now,
        );

        // First tap - up
        final upEvent1 = RawPointerUpEvent(
          pointer: 1,
          position: ui.Offset(100, 100),
          worldPosition: ui.Offset(100, 100),
          timestamp: now
              .add(const Duration(milliseconds: 100))
              .millisecondsSinceEpoch,
        );
        state.checkForDoubleTap(
          upEvent1,
          now.add(const Duration(milliseconds: 100)),
        );
        final gesture1 = state.classifyGesture(
          1,
          now.add(const Duration(milliseconds: 100)),
        );
        expect(gesture1, GestureType.tap); // First tap should be single tap
        state.onPointerUp(upEvent1, now.add(const Duration(milliseconds: 100)));

        // Second tap - down (same pointer)
        state.onPointerDown(
          RawPointerDownEvent(
            pointer: 1,
            position: ui.Offset(100, 100),
            worldPosition: ui.Offset(100, 100),
            timestamp: now
                .add(const Duration(milliseconds: 200))
                .millisecondsSinceEpoch,
          ),
          now.add(const Duration(milliseconds: 200)),
        );

        // Second tap - up
        final upEvent2 = RawPointerUpEvent(
          pointer: 1,
          position: ui.Offset(100, 100),
          worldPosition: ui.Offset(100, 100),
          timestamp: now
              .add(const Duration(milliseconds: 250))
              .millisecondsSinceEpoch,
        );
        state.checkForDoubleTap(
          upEvent2,
          now.add(const Duration(milliseconds: 250)),
        );

        // Check second tap is classified as double-tap
        final gesture2 = state.classifyGesture(
          1,
          now.add(const Duration(milliseconds: 250)),
        );
        expect(gesture2, GestureType.doubleTap);

        state.onPointerUp(upEvent2, now.add(const Duration(milliseconds: 250)));
      });

      test('should detect double-tap with different pointer IDs', () {
        final now = DateTime.now();

        // First tap - down (pointer 1)
        state.onPointerDown(
          RawPointerDownEvent(
            pointer: 1,
            position: ui.Offset(100, 100),
            worldPosition: ui.Offset(100, 100),
            timestamp: now.millisecondsSinceEpoch,
          ),
          now,
        );

        // First tap - up (pointer 1)
        final upEvent1 = RawPointerUpEvent(
          pointer: 1,
          position: ui.Offset(100, 100),
          worldPosition: ui.Offset(100, 100),
          timestamp: now
              .add(const Duration(milliseconds: 100))
              .millisecondsSinceEpoch,
        );
        state.checkForDoubleTap(
          upEvent1,
          now.add(const Duration(milliseconds: 100)),
        );
        final gesture1 = state.classifyGesture(
          1,
          now.add(const Duration(milliseconds: 100)),
        );
        expect(gesture1, GestureType.tap); // First tap should be single tap
        state.onPointerUp(upEvent1, now.add(const Duration(milliseconds: 100)));

        // Second tap - down (pointer 2)
        state.onPointerDown(
          RawPointerDownEvent(
            pointer: 2,
            position: ui.Offset(100, 100),
            worldPosition: ui.Offset(100, 100),
            timestamp: now
                .add(const Duration(milliseconds: 200))
                .millisecondsSinceEpoch,
          ),
          now.add(const Duration(milliseconds: 200)),
        );

        // Second tap - up (pointer 2)
        final upEvent2 = RawPointerUpEvent(
          pointer: 2,
          position: ui.Offset(100, 100),
          worldPosition: ui.Offset(100, 100),
          timestamp: now
              .add(const Duration(milliseconds: 250))
              .millisecondsSinceEpoch,
        );
        state.checkForDoubleTap(
          upEvent2,
          now.add(const Duration(milliseconds: 250)),
        );

        // Check second tap is classified as double-tap
        final gesture2 = state.classifyGesture(
          2,
          now.add(const Duration(milliseconds: 250)),
        );
        expect(gesture2, GestureType.doubleTap);

        state.onPointerUp(upEvent2, now.add(const Duration(milliseconds: 250)));
      });
    });

    group('Double tap outside timeout', () {
      test(
        'should not detect double-tap when taps are too far apart in time',
        () {
          final now = DateTime.now();

          // First tap - down
          state.onPointerDown(
            RawPointerDownEvent(
              pointer: 1,
              position: ui.Offset(100, 100),
              worldPosition: ui.Offset(100, 100),
              timestamp: now.millisecondsSinceEpoch,
            ),
            now,
          );

          // First tap - up
          state.onPointerUp(
            RawPointerUpEvent(
              pointer: 1,
              position: ui.Offset(100, 100),
              worldPosition: ui.Offset(100, 100),
              timestamp: now
                  .add(const Duration(milliseconds: 100))
                  .millisecondsSinceEpoch,
            ),
            now.add(const Duration(milliseconds: 100)),
          );

          // Second tap - down (after timeout)
          state.onPointerDown(
            RawPointerDownEvent(
              pointer: 2,
              position: ui.Offset(100, 100),
              worldPosition: ui.Offset(100, 100),
              timestamp: now
                  .add(const Duration(milliseconds: 400))
                  .millisecondsSinceEpoch,
            ),
            now.add(const Duration(milliseconds: 400)),
          ); // > 300ms timeout

          // Second tap - up
          final upEvent2 = RawPointerUpEvent(
            pointer: 2,
            position: ui.Offset(100, 100),
            worldPosition: ui.Offset(100, 100),
            timestamp: now
                .add(const Duration(milliseconds: 450))
                .millisecondsSinceEpoch,
          );
          state.checkForDoubleTap(
            upEvent2,
            now.add(const Duration(milliseconds: 450)),
          );

          // Check second tap is classified as single tap, not double-tap
          final gesture = state.classifyGesture(
            2,
            now.add(const Duration(milliseconds: 450)),
          );
          expect(gesture, GestureType.tap);

          state.onPointerUp(
            upEvent2,
            now.add(const Duration(milliseconds: 450)),
          );
        },
      );
    });

    group('Double tap outside distance threshold', () {
      test(
        'should not detect double-tap when taps are too far apart spatially',
        () {
          final now = DateTime.now();

          // First tap - down
          state.onPointerDown(
            RawPointerDownEvent(
              pointer: 1,
              position: ui.Offset(100, 100),
              worldPosition: ui.Offset(100, 100),
              timestamp: now.millisecondsSinceEpoch,
            ),
            now,
          );

          // First tap - up
          state.onPointerUp(
            RawPointerUpEvent(
              pointer: 1,
              position: ui.Offset(100, 100),
              worldPosition: ui.Offset(100, 100),
              timestamp: now
                  .add(const Duration(milliseconds: 100))
                  .millisecondsSinceEpoch,
            ),
            now.add(const Duration(milliseconds: 100)),
          );

          // Second tap - down (far away)
          state.onPointerDown(
            RawPointerDownEvent(
              pointer: 2,
              position: ui.Offset(200, 200), // > 50px away
              worldPosition: ui.Offset(200, 200),
              timestamp: now
                  .add(const Duration(milliseconds: 200))
                  .millisecondsSinceEpoch,
            ),
            now.add(const Duration(milliseconds: 200)),
          );

          // Second tap - up
          final upEvent2 = RawPointerUpEvent(
            pointer: 2,
            position: ui.Offset(200, 200),
            worldPosition: ui.Offset(200, 200),
            timestamp: now
                .add(const Duration(milliseconds: 250))
                .millisecondsSinceEpoch,
          );
          state.checkForDoubleTap(
            upEvent2,
            now.add(const Duration(milliseconds: 250)),
          );

          // Check second tap is classified as single tap, not double-tap
          final gesture = state.classifyGesture(
            2,
            now.add(const Duration(milliseconds: 250)),
          );
          expect(gesture, GestureType.tap);

          state.onPointerUp(
            upEvent2,
            now.add(const Duration(milliseconds: 250)),
          );
        },
      );
    });

    group('Stale tap cleanup behavior', () {
      test('should not detect double-tap when first tap is too old', () {
        final now = DateTime.now();

        // First tap (will become stale)
        state.onPointerDown(
          RawPointerDownEvent(
            pointer: 1,
            position: ui.Offset(100, 100),
            worldPosition: ui.Offset(100, 100),
            timestamp: now.millisecondsSinceEpoch,
          ),
          now,
        );

        state.onPointerUp(
          RawPointerUpEvent(
            pointer: 1,
            position: ui.Offset(100, 100),
            worldPosition: ui.Offset(100, 100),
            timestamp: now
                .add(const Duration(milliseconds: 100))
                .millisecondsSinceEpoch,
          ),
          now.add(const Duration(milliseconds: 100)),
        );

        // Wait beyond timeout for second tap
        final futureTime = now.add(const Duration(milliseconds: 400));

        // Second tap (should not be double-tap because first is stale)
        state.onPointerDown(
          RawPointerDownEvent(
            pointer: 2,
            position: ui.Offset(100, 100),
            worldPosition: ui.Offset(100, 100),
            timestamp: futureTime.millisecondsSinceEpoch,
          ),
          futureTime,
        );

        final upEvent2 = RawPointerUpEvent(
          pointer: 2,
          position: ui.Offset(100, 100),
          worldPosition: ui.Offset(100, 100),
          timestamp: futureTime
              .add(const Duration(milliseconds: 50))
              .millisecondsSinceEpoch,
        );
        state.checkForDoubleTap(
          upEvent2,
          futureTime.add(const Duration(milliseconds: 50)),
        );

        // Should be single tap, not double-tap (stale tap was cleaned up)
        final gesture = state.classifyGesture(
          2,
          futureTime.add(const Duration(milliseconds: 50)),
        );
        expect(gesture, GestureType.tap);

        state.onPointerUp(
          upEvent2,
          futureTime.add(const Duration(milliseconds: 50)),
        );
      });
    });
  });
}
