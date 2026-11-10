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
    'Listener skips pan-zoom callbacks so trackpad gestures are not doubled',
    (final tester) async {
      // Regression pin: macOS routes trackpad pan/zoom to BOTH
      // Listener.onPointerPanZoom* AND the scale recognizer (Flutter feeds
      // PointerPanZoom events to ScaleGestureRecognizer too). Wiring both
      // paths double-emits every trackpad gesture — double pan/zoom speed,
      // the exact bug paid for once in the flutter_scene adapter. The scale
      // recognizer is the single source of scale/pan-zoom; the Listener
      // must NOT also listen for pan-zoom.
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

      final listener = tester.widget<Listener>(
        find.byWidgetPredicate(
          (final widget) =>
              widget is Listener && widget.onPointerSignal != null,
        ),
      );
      expect(listener.onPointerPanZoomStart, isNull);
      expect(listener.onPointerPanZoomUpdate, isNull);
      expect(listener.onPointerPanZoomEnd, isNull);

      // The scale path (single source for touch + trackpad) stays wired.
      final gestureDetector = tester.widget<GestureDetector>(
        find.byWidgetPredicate(
          (final widget) =>
              widget is GestureDetector && widget.onScaleUpdate != null,
        ),
      );
      expect(gestureDetector.onScaleStart, isNotNull);
      expect(gestureDetector.onScaleUpdate, isNotNull);
      expect(gestureDetector.onScaleEnd, isNotNull);
    },
  );

  testWidgets(
    'UnifiedInputWidget forwards pointer hover as a raw hover event',
    (final tester) async {
      // Hover (mouse move with NO buttons) never reaches onPointerMove —
      // hosts that track the cursor without a press (placement ghosts,
      // hover picking) rely on this dedicated event.
      final world = World()..addPlugin(InputPlugin());

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: SizedBox.expand(
            child: UnifiedInputWidget(
              world: world,
              toWorldCoords: (final p, final size) =>
                  ui.Offset(p.dx * 2, p.dy * 2),
              child: const SizedBox.expand(),
            ),
          ),
        ),
      );

      final listener = tester.widget<Listener>(
        find.byWidgetPredicate(
          (final widget) => widget is Listener && widget.onPointerHover != null,
        ),
      );
      listener.onPointerHover!(
        const PointerHoverEvent(
          timeStamp: Duration(milliseconds: 5),
          position: ui.Offset(30, 40),
        ),
      );

      final hovers = world.events
          .reader<RawPointerHoverEvent>()
          .iter()
          .toList();
      expect(hovers, hasLength(1));
      expect(hovers.single.position, const ui.Offset(30, 40));
      // The host converter ran on the hover position.
      expect(hovers.single.worldPosition, const ui.Offset(60, 80));
      expect(hovers.single.buttons, 0);
    },
  );

  testWidgets(
    'Scale updates carry the host world focal point into PinchEvent',
    (final tester) async {
      final world = World()..addPlugin(InputPlugin());

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: SizedBox.expand(
            child: UnifiedInputWidget(
              world: world,
              toWorldCoords: (final p, final size) =>
                  ui.Offset(p.dx * 2, p.dy * 2),
              child: const SizedBox.expand(),
            ),
          ),
        ),
      );

      final gestureFinder = find.byWidgetPredicate(
        (final widget) =>
            widget is GestureDetector && widget.onScaleUpdate != null,
      );
      final gestureDetector = tester.widget<GestureDetector>(gestureFinder);
      gestureDetector.onScaleUpdate!(
        ScaleUpdateDetails(
          focalPoint: ui.Offset(120, 240),
          localFocalPoint: ui.Offset(12, 24),
          focalPointDelta: ui.Offset(-5, 7),
          scale: 1.25,
          rotation: 0.4,
          pointerCount: 2,
        ),
      );

      final raw = world.events.reader<RawScaleUpdateEvent>().iter().single;
      expect(raw.worldFocalPoint, const ui.Offset(24, 48));

      // Classification passes the world focal through to PinchEvent, so
      // camera systems can zoom-at-cursor without knowing the projection.
      scaleClassificationSystem(world);
      final pinch = world.events.reader<PinchEvent>().iter().single;
      expect(pinch.worldPosition, const ui.Offset(24, 48));
      expect(pinch.focalPoint, const ui.Offset(12, 24));
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
