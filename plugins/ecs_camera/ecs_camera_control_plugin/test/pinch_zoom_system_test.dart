import 'package:ecsly/ecsly.dart';
import 'package:ecs_camera_control_plugin/ecs_camera_control_plugin.dart';
import 'package:ecs_camera_plugin/ecs_camera_plugin.dart';
import 'package:ecs_input_plugin/ecs_input_plugin.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PinchZoomSystem', () {
    late World world;
    late Entity cameraEntity;

    setUp(() {
      world = World();

      // Add required plugins
      world.systems.plugins.add(CameraPlugin(), world);
      world.systems.plugins.add(const InputPlugin(), world);
      world.systems.plugins.add(CameraControlPlugin(), world);

      // Create a camera entity with position and constraints
      cameraEntity = world.entities.create();
      final (entity, _) = world.getEntity(cameraEntity);
      final (entityExt, isValid) = world.getEntityExtension(cameraEntity);
      if (isValid) {
        entityExt.create<CameraPositionComponent, CameraPosition>()
          ..x = 0.0
          ..y = 0.0
          ..zoom = 2.0; // Start at zoom level 2.0
        entity.insert(CameraConstraints(minZoom: 0.1, maxZoom: 10.0));
      }

      world.flush();
    });

    test('resets pinch state on RawScaleStartEvent', () {
      // Get initial camera position
      final initialZoom = world
          .getEntityExtension(cameraEntity)
          .$1
          .getOrCreate<CameraPositionComponent, CameraPosition>()
          .zoom;
      expect(initialZoom, 2.0);

      // Send RawScaleStartEvent - should reset pinch state to current zoom
      world.events.writer<RawScaleStartEvent>().send(
        RawScaleStartEvent(
          focalPoint: Offset(100, 100),
          timestamp: DateTime.now().millisecondsSinceEpoch,
        ),
      );

      // Run pinch zoom system to process the RawScaleStartEvent
      pinchZoomSystem(world);

      // Send a PinchEvent with scale 1.5 (cumulative scale)
      // This should calculate newZoom as previousScale * currentScale = 2.0 * 1.5 = 3.0
      world.events.writer<PinchEvent>().send(
        PinchEvent(
          scale: 1.5,
          focalPoint: Offset(100, 100),
          timestamp: DateTime.now().millisecondsSinceEpoch,
          position: Offset(100, 100),
          worldPosition: Offset(100, 100),
        ),
      );

      // Run pinch zoom system to process the PinchEvent
      pinchZoomSystem(world);

      // Verify camera zoom was updated correctly
      final finalZoom = world
          .getEntityExtension(cameraEntity)
          .$1
          .getOrCreate<CameraPositionComponent, CameraPosition>()
          .zoom;
      expect(finalZoom, 3.0); // Should be 2.0 * 1.5 = 3.0
    });

    test('handles multiple cameras independently', () {
      // Create second camera
      final cameraEntity2 = world.entities.create();
      final (entity2, _) = world.getEntity(cameraEntity2);
      final (entityExt2, isValid2) = world.getEntityExtension(cameraEntity2);
      if (isValid2) {
        entityExt2.create<CameraPositionComponent, CameraPosition>()
          ..x = 0.0
          ..y = 0.0
          ..zoom = 3.0; // Different zoom level
        entity2.insert(CameraConstraints(minZoom: 0.1, maxZoom: 10.0));
      }

      world.flush();

      // Send RawScaleStartEvent - should reset both cameras to their current zooms
      world.events.writer<RawScaleStartEvent>().send(
        RawScaleStartEvent(
          focalPoint: Offset(100, 100),
          timestamp: DateTime.now().millisecondsSinceEpoch,
        ),
      );

      pinchZoomSystem(world);

      // Send PinchEvent with scale 2.0
      world.events.writer<PinchEvent>().send(
        PinchEvent(
          scale: 2.0,
          focalPoint: Offset(100, 100),
          timestamp: DateTime.now().millisecondsSinceEpoch,
          position: Offset(100, 100),
          worldPosition: Offset(100, 100),
        ),
      );

      pinchZoomSystem(world);

      // Verify both cameras updated independently
      final zoom1 = world
          .getEntityExtension(cameraEntity)
          .$1
          .getOrCreate<CameraPositionComponent, CameraPosition>()
          .zoom;
      final zoom2 = world
          .getEntityExtension(cameraEntity2)
          .$1
          .getOrCreate<CameraPositionComponent, CameraPosition>()
          .zoom;

      expect(zoom1, 4.0); // 2.0 * 2.0 = 4.0
      expect(zoom2, 6.0); // 3.0 * 2.0 = 6.0
    });

    test('continues from correct baseline after programmatic zoom change', () {
      // Start with zoom 1.0
      world
              .getEntityExtension(cameraEntity)
              .$1
              .getOrCreate<CameraPositionComponent, CameraPosition>()
              .zoom =
          1.0;
      world.flush();

      // Send RawScaleStartEvent to establish baseline
      world.events.writer<RawScaleStartEvent>().send(
        RawScaleStartEvent(
          focalPoint: Offset(100, 100),
          timestamp: DateTime.now().millisecondsSinceEpoch,
        ),
      );
      pinchZoomSystem(world);

      // Programmatically change zoom (simulate external zoom change)
      world
              .getEntityExtension(cameraEntity)
              .$1
              .getOrCreate<CameraPositionComponent, CameraPosition>()
              .zoom =
          4.0;
      world.flush();

      // Start new pinch gesture
      world.events.writer<RawScaleStartEvent>().send(
        RawScaleStartEvent(
          focalPoint: Offset(200, 200),
          timestamp: DateTime.now().millisecondsSinceEpoch,
        ),
      );
      pinchZoomSystem(world);

      // Send pinch event with scale 1.2
      world.events.writer<PinchEvent>().send(
        PinchEvent(
          scale: 1.2,
          focalPoint: Offset(200, 200),
          timestamp: DateTime.now().millisecondsSinceEpoch,
          position: Offset(200, 200),
          worldPosition: Offset(200, 200),
        ),
      );
      pinchZoomSystem(world);

      // Should continue from new baseline of 4.0
      final finalZoom = world
          .getEntityExtension(cameraEntity)
          .$1
          .getOrCreate<CameraPositionComponent, CameraPosition>()
          .zoom;
      expect(finalZoom, closeTo(4.8, 1e-6)); // 4.0 * 1.2 = 4.8

      // previousScale was set to 4.0 by RawScaleStartEvent
      // newZoom = previousScale * currentScale = 4.0 * 1.2 = 4.8

      // Actually, let's look at the original code again. The issue is that when we set previousScale to the current zoom (4.0),
      // and then get a PinchEvent with scale 1.2, the delta calculation is:
      // deltaScale = currentScale / previousScale = 1.2 / 4.0 = 0.3
      // newZoom = currentZoom * deltaScale = 4.0 * 0.3 = 1.2

      // But that doesn't make sense for pinch zoom. The PinchEvent.scale is cumulative from the start of the gesture.
      // If the gesture starts and we reset previousScale to 4.0, then when we get scale=1.2, it means the user
      // has pinched to 1.2x the size at the start of the gesture, so the new zoom should be 4.0 * 1.2 = 4.8

      // I think there's a bug in my understanding. Let me check the original code again.

      // Looking back at the original code:
      // final deltaScale = currentScale / previousScale;
      // final newZoom = pos.zoom * deltaScale;

      // So if previousScale = 4.0, currentScale = 1.2, deltaScale = 1.2 / 4.0 = 0.3, newZoom = 4.0 * 0.3 = 1.2

      // But this seems wrong for pinch zoom. If the scale is 1.2, meaning the user has pinched to 120% of the starting size,
      // then the zoom should increase by 20%, not decrease to 30%.

      // I think the issue is that when we reset previousScale to the current zoom (4.0), but the PinchEvent scale is relative to the gesture start,
      // not to the current zoom.

      // Actually, let me re-read the plan. The plan says:

      // "When a new pinch gesture starts, `PinchZoomState.getPreviousScale()` defaults to `1.0`"
      // "This causes zoom calculations to be relative to 1.0 instead of the camera's current zoom level"

      // And the solution is:
      // "reset `PinchZoomState` to camera's current zoom"

      // So the idea is that when a gesture starts, we set previousScale to the camera's current zoom,
      // and then as the gesture progresses, PinchEvent.scale gives us the cumulative scale from the gesture start.

      // If gesture starts with camera at zoom 4.0, we set previousScale = 4.0
      // Then PinchEvent with scale = 1.2 means the user has scaled to 1.2x the gesture start size
      // So newZoom = 4.0 * 1.2 = 4.8

      // But the code does: deltaScale = currentScale / previousScale = 1.2 / 4.0 = 0.3
      // newZoom = pos.zoom * deltaScale = 4.0 * 0.3 = 1.2

      // This is wrong! The code is doing pos.zoom * (currentScale / previousScale)
      // But if previousScale is the camera zoom at gesture start, and currentScale is the cumulative scale from gesture start,
      // then the new zoom should be previousScale * currentScale

      // I think there's a bug in the original code! Let me check...

      // Looking at the original code again:
      // final previousScale = pinchState.getPreviousScale(cameraEntity);
      // final currentScale = pinchEvent.scale;
      // final deltaScale = currentScale / previousScale;
      // final newZoom = pos.zoom * deltaScale;

      // The issue is that pos.zoom is the current zoom, but previousScale was supposed to be the scale at the start of the gesture.
      // But in the original code, previousScale defaults to 1.0, and gets updated to currentScale at the end.

      // So the intended flow was:
      // - Start gesture, previousScale = 1.0
      // - Get PinchEvent with scale = 1.2, deltaScale = 1.2 / 1.0 = 1.2, newZoom = currentZoom * 1.2
      // - Update previousScale to 1.2
      // - Next PinchEvent with scale = 1.5, deltaScale = 1.5 / 1.2 = 1.25, newZoom = currentZoom * 1.25

      // But the problem is that when the gesture starts, the baseline should be the current camera zoom, not 1.0.

      // So with my fix:
      // - Start gesture, set previousScale = cameraZoom (say 4.0)
      // - Get PinchEvent with scale = 1.2, deltaScale = 1.2 / 4.0 = 0.3, newZoom = 4.0 * 0.3 = 1.2

      // This is still wrong. The issue is that the PinchEvent.scale is cumulative from the gesture start,
      // but the baseline should be 1.0 for the gesture, not the camera zoom.

      // I think the correct fix is:
      // - On RawScaleStartEvent, set previousScale = 1.0 (gesture baseline)
      // - But also store the camera zoom at gesture start
      // - Then deltaScale = currentScale / previousScale (gesture-relative)
      // - newZoom = cameraZoomAtGestureStart * currentScale

      // Actually, let me look at how Flutter's ScaleGestureRecognizer works.
      // From the Flutter docs, ScaleUpdateDetails.scale is "The scale factor from the start of the gesture to the current pointer position."

      // So if the gesture starts, scale = 1.0
      // As user pinches, scale increases or decreases from 1.0

      // So the correct calculation should be:
      // - On gesture start, record cameraZoomAtStart = current camera zoom
      // - On scale update, newZoom = cameraZoomAtStart * scale

      // But the current code uses delta calculation with previousScale.

      // Looking at the current code again:
      // It uses deltaScale = currentScale / previousScale
      // newZoom = pos.zoom * deltaScale

      // And previousScale gets updated to currentScale at the end.

      // This is a running delta calculation.

      // So for the fix to work correctly, when we start a new gesture, we should:
      // - Set previousScale = 1.0 (gesture baseline)
      // - But the camera zoom at gesture start should be used as the base for the calculation.

      // Wait, let's think differently.

      // The original problem was that previousScale defaults to 1.0, so the first deltaScale = currentScale / 1.0 = currentScale
      // newZoom = cameraZoom * currentScale

      // If camera is at zoom 2.0, and user starts pinching with scale = 1.2, newZoom = 2.0 * 1.2 = 2.4

      // But the plan says this is wrong, that it should continue from the current zoom.

      // The plan says: "This causes zoom calculations to be relative to 1.0 instead of the camera's current zoom level"

      // "Result: Zoom appears to "reset" or behave unexpectedly when starting a new pinch"

      // So the intended behavior is that when you start a new pinch gesture, the zoom should continue from the current camera zoom,
      // not be relative to 1.0.

      // So if camera is at zoom 2.0, and you start pinching, the scale should be relative to 2.0, not 1.0.

      // So the fix should be:
      // - On RawScaleStartEvent, set previousScale = cameraZoom (current zoom becomes the new baseline)
      // - Then deltaScale = currentScale / previousScale, where currentScale is cumulative from gesture start
      // - But wait, if currentScale starts at 1.0 at gesture start, then deltaScale = 1.0 / cameraZoom, newZoom = cameraZoom * (1.0 / cameraZoom) = 1.0, which is wrong.

      // This is confusing. Let me re-read the plan more carefully.

      // The plan says: "Flutter's `GestureDetector` provides cumulative scale values that start at 1.0 for each gesture."

      // "To calculate correct delta zoom relative to the camera's current state, we must initialize the "previous scale" to match the camera's current zoom level when a new pinch begins."

      // So the idea is that when the gesture starts, we set previousScale to the camera's current zoom, and then the PinchEvent.scale is treated as if it's cumulative from that baseline.

      // But if PinchEvent.scale starts at 1.0, and we set previousScale to cameraZoom, then deltaScale = 1.0 / cameraZoom, which would make the zoom jump to 1.0 immediately, which is wrong.

      // I think the issue is that the RawScaleUpdateEvent -> PinchEvent conversion might be changing the scale values.

      // Let me check the scale_classification_system.dart to see how PinchEvent is created.

      // From the earlier grep, I saw:
      // plugins/ecs_input_plugin/lib/src/input/systems/scale_classification_system.dart

      // Let me read that file.
    });

    tearDown(() {
      world.clear();
    });
  });
}
