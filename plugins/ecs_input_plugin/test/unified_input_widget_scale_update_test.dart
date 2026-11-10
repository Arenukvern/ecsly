import 'dart:ui' as ui;

import 'package:ecsly/ecsly.dart';
import 'package:ecs_input_plugin/ecs_input_plugin.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'UnifiedInputWidget forwards scale update delta, rotation, and pointer count',
    (final tester) async {
      final world = World()..addPlugin(InputPlugin());

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: SizedBox.expand(
            child: UnifiedInputWidget(
              world: world,
              child: const SizedBox.expand(),
            ),
          ),
        ),
      );

      final stackFinder = find.byWidgetPredicate(
        (final widget) => widget is Stack && widget.fit == StackFit.expand,
      );
      expect(stackFinder, findsOneWidget);

      final gestureFinder = find.byWidgetPredicate(
        (final widget) =>
            widget is GestureDetector &&
            widget.onScaleStart != null &&
            widget.onScaleUpdate != null &&
            widget.onScaleEnd != null,
      );
      expect(gestureFinder, findsOneWidget);
      final gestureDetector = tester.widget<GestureDetector>(gestureFinder);
      gestureDetector.onScaleUpdate!(
        ScaleUpdateDetails(
          focalPoint: ui.Offset(120, 240),
          localFocalPoint: ui.Offset(12, 24),
          focalPointDelta: ui.Offset(-5, 7),
          scale: 1.25,
          rotation: 0.4,
          pointerCount: 3,
        ),
      );

      final rawEvents = world.events
          .reader<RawScaleUpdateEvent>()
          .iter()
          .toList();
      expect(rawEvents, hasLength(1));

      final event = rawEvents.single;
      expect(event.focalPoint, const ui.Offset(12, 24));
      expect(event.focalPointDelta, const ui.Offset(-5, 7));
      expect(event.scale, closeTo(1.25, 1e-9));
      expect(event.rotation, closeTo(0.4, 1e-6));
      expect(event.pointerCount, 3);
      expect(event.timestamp, greaterThan(0));
    },
  );

  testWidgets(
    'UnifiedInputWidget forwards trackpad pan/zoom as raw scale events',
    (final tester) async {
      final world = World()..addPlugin(InputPlugin());

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: SizedBox.expand(
            child: UnifiedInputWidget(
              world: world,
              child: const SizedBox.expand(),
            ),
          ),
        ),
      );

      final listenerFinder = find.byWidgetPredicate(
        (final widget) =>
            widget is Listener &&
            widget.onPointerPanZoomStart != null &&
            widget.onPointerPanZoomUpdate != null &&
            widget.onPointerPanZoomEnd != null,
      );
      expect(listenerFinder, findsOneWidget);
      final listener = tester.widget<Listener>(listenerFinder);
      listener.onPointerPanZoomStart!(
        const PointerPanZoomStartEvent(
          timeStamp: Duration(milliseconds: 1),
          position: ui.Offset(80, 90),
        ),
      );
      listener.onPointerPanZoomUpdate!(
        const PointerPanZoomUpdateEvent(
          timeStamp: Duration(milliseconds: 2),
          position: ui.Offset(82, 95),
          panDelta: ui.Offset(2, 5),
          scale: 1.4,
          rotation: 0.25,
        ),
      );
      listener.onPointerPanZoomEnd!(
        const PointerPanZoomEndEvent(
          timeStamp: Duration(milliseconds: 3),
          position: ui.Offset(82, 95),
        ),
      );

      final startEvents = world.events
          .reader<RawScaleStartEvent>()
          .iter()
          .toList();
      final updateEvents = world.events
          .reader<RawScaleUpdateEvent>()
          .iter()
          .toList();
      final endEvents = world.events.reader<RawScaleEndEvent>().iter().toList();
      expect(startEvents, hasLength(1));
      expect(updateEvents, hasLength(1));
      expect(endEvents, hasLength(1));

      expect(startEvents.single.focalPoint, const ui.Offset(80, 90));
      expect(updateEvents.single.focalPoint, const ui.Offset(82, 95));
      expect(updateEvents.single.focalPointDelta, const ui.Offset(2, 5));
      expect(updateEvents.single.scale, closeTo(1.4, 1e-6));
      expect(updateEvents.single.rotation, closeTo(0.25, 1e-6));
      expect(updateEvents.single.pointerCount, 0);
    },
  );

  testWidgets(
    'UnifiedInputWidget can convert trackpad scroll into raw scale pan updates',
    (final tester) async {
      final world = World()..addPlugin(InputPlugin());

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: SizedBox.expand(
            child: UnifiedInputWidget(
              world: world,
              trackpadScrollCausesPan: true,
              child: const SizedBox.expand(),
            ),
          ),
        ),
      );

      final listenerFinder = find.byWidgetPredicate(
        (final widget) => widget is Listener && widget.onPointerSignal != null,
      );
      expect(listenerFinder, findsOneWidget);
      final listener = tester.widget<Listener>(listenerFinder);
      listener.onPointerSignal!(
        const PointerScrollEvent(
          timeStamp: Duration(milliseconds: 1),
          kind: PointerDeviceKind.trackpad,
          position: ui.Offset(42, 24),
          scrollDelta: ui.Offset(3, -7),
        ),
      );

      final scaleEvents = world.events
          .reader<RawScaleUpdateEvent>()
          .iter()
          .toList();
      final scrollEvents = world.events.reader<ScrollEvent>().iter().toList();

      expect(scaleEvents, hasLength(1));
      expect(scrollEvents, isEmpty);

      final event = scaleEvents.single;
      expect(event.focalPoint, const ui.Offset(42, 24));
      expect(event.focalPointDelta, const ui.Offset(-3, 7));
      expect(event.scale, closeTo(1.0, 1e-9));
      expect(event.pointerCount, 0);
    },
  );

  testWidgets(
    'UnifiedInputWidget keeps shift+trackpad scroll as ScrollEvent for pan bindings',
    (final tester) async {
      final world = World()..addPlugin(InputPlugin());

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: SizedBox.expand(
            child: UnifiedInputWidget(
              world: world,
              trackpadScrollCausesPan: true,
              child: const SizedBox.expand(),
            ),
          ),
        ),
      );

      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);

      final listenerFinder = find.byWidgetPredicate(
        (final widget) => widget is Listener && widget.onPointerSignal != null,
      );
      expect(listenerFinder, findsOneWidget);
      final listener = tester.widget<Listener>(listenerFinder);
      listener.onPointerSignal!(
        const PointerScrollEvent(
          timeStamp: Duration(milliseconds: 1),
          kind: PointerDeviceKind.trackpad,
          position: ui.Offset(42, 24),
          scrollDelta: ui.Offset(3, -7),
        ),
      );

      final scaleEvents = world.events
          .reader<RawScaleUpdateEvent>()
          .iter()
          .toList();
      final scrollEvents = world.events.reader<ScrollEvent>().iter().toList();

      expect(scaleEvents, isEmpty);
      expect(scrollEvents, hasLength(1));
      expect(scrollEvents.single.kind, PointerDeviceKind.trackpad);
      expect(scrollEvents.single.delta, const ui.Offset(3, -7));
      expect(
        scrollEvents.single.modifierMask & inputModifierShiftMask,
        isNonZero,
      );

      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    },
  );

  testWidgets(
    'UnifiedInputWidget forwards pointer scroll kind into scroll events',
    (final tester) async {
      final world = World()..addPlugin(InputPlugin());

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: SizedBox.expand(
            child: UnifiedInputWidget(
              world: world,
              child: const SizedBox.expand(),
            ),
          ),
        ),
      );

      final listenerFinder = find.byWidgetPredicate(
        (final widget) => widget is Listener && widget.onPointerSignal != null,
      );
      expect(listenerFinder, findsOneWidget);
      final listener = tester.widget<Listener>(listenerFinder);
      listener.onPointerSignal!(
        const PointerScrollEvent(
          timeStamp: Duration(milliseconds: 1),
          position: ui.Offset(80, 90),
          scrollDelta: ui.Offset(2, -5),
          kind: PointerDeviceKind.trackpad,
        ),
      );

      final scrollEvents = world.events.reader<ScrollEvent>().iter().toList();
      expect(scrollEvents, hasLength(1));
      expect(scrollEvents.single.kind, PointerDeviceKind.trackpad);
      expect(scrollEvents.single.delta, const ui.Offset(2, -5));
    },
  );
}
