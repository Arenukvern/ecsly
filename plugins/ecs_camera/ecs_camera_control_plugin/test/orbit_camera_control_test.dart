import 'package:ecs_camera_control_plugin/ecs_camera_control_plugin.dart';
import 'package:ecs_input_plugin/ecs_input_plugin.dart';
import 'package:ecsly/ecsly.dart';
import 'package:flutter_test/flutter_test.dart';

/// Headless proof of the renderer-agnostic orbit control: ECS input events
/// (the same DragEvent/ScrollEvent that UnifiedInputWidget emits from raw
/// Flutter pointers) drive an [OrbitCameraResource] with NO renderer present.
/// This is the "controls don't depend on flutter_scene" half — a flutter_scene
/// bridge only has to read OrbitCameraResource.cameraPosition() each frame.
void main() {
  late World world;
  late OrbitCameraResource cam;

  DragEvent drag(double dx, double dy, {int buttons = kOrbitPrimaryButton}) =>
      DragEvent(
        position: Offset.zero,
        worldPosition: Offset.zero,
        startPosition: Offset.zero,
        startWorldPosition: Offset.zero,
        delta: Offset(dx, dy),
        timestamp: 0,
        buttons: buttons,
      );

  ScrollEvent scroll(double dy) => ScrollEvent(
    position: Offset.zero,
    worldPosition: Offset.zero,
    delta: Offset(0, dy),
    timestamp: 0,
  );

  setUp(() {
    world = World();
    world.systems.plugins.add(const InputPlugin(), world);
    cam = OrbitCameraResource(
      yaw: 0,
      pitch: 0.5,
      distance: 20,
      targetX: 0,
      targetY: 0,
      targetZ: 0,
    );
    world.upsertResource(cam);
    world.flush();
  });

  group('orbitCameraControlSystem — drag', () {
    test('left-drag pans the target (grab-the-world)', () {
      // yaw 0: screen-right is world -X under flutter_scene's left-handed
      // render, so a grab-the-world drag right moves the target toward +X.
      world.events.writer<DragEvent>().send(drag(10, 0));
      orbitCameraControlSystem(world);
      expect(cam.targetX, greaterThan(0));
      expect(cam.targetZ, closeTo(0, 1e-9));
      expect(cam.yaw, 0, reason: 'a plain drag pans, it does not orbit');
    });

    test('middle-button drag orbits yaw instead of panning', () {
      world.events.writer<DragEvent>().send(
        drag(10, 0, buttons: kOrbitMiddleButton),
      );
      orbitCameraControlSystem(world);
      expect(cam.yaw, greaterThan(0), reason: 'drag right spins yaw +');
      expect(cam.targetX, 0, reason: 'orbit does not translate the target');
    });

    test('middle-button vertical drag tilts pitch (clamped)', () {
      world.events.writer<DragEvent>().send(
        drag(0, 10, buttons: kOrbitMiddleButton),
      );
      orbitCameraControlSystem(world);
      expect(cam.pitch, lessThan(0.5), reason: 'drag down lowers pitch');
      // Clamp holds at the straight-down singularity guard.
      for (var i = 0; i < 400; i++) {
        world.events.writer<DragEvent>().send(
          drag(0, 100, buttons: kOrbitMiddleButton),
        );
        orbitCameraControlSystem(world);
      }
      expect(cam.pitch, greaterThanOrEqualTo(cam.minPitch));
    });
  });

  group('orbitCameraControlSystem — scroll', () {
    // Each test uses the fresh world from setUp and a single system run, so
    // the event buffer holds exactly one scroll (in-game the Input schedule's
    // cleanup drains events every frame; calling the system twice without a
    // frame boundary would otherwise re-process the same event).
    test('scroll up dollies in', () {
      world.events.writer<ScrollEvent>().send(scroll(-100));
      orbitCameraControlSystem(world);
      expect(cam.distance, lessThan(20));
    });

    test('scroll down dollies out', () {
      world.events.writer<ScrollEvent>().send(scroll(100));
      orbitCameraControlSystem(world);
      expect(cam.distance, greaterThan(20));
    });

    test('distance stays within clamps', () {
      for (var i = 0; i < 200; i++) {
        world.events.writer<ScrollEvent>().send(scroll(-100));
      }
      orbitCameraControlSystem(world);
      expect(cam.distance, greaterThanOrEqualTo(cam.minDistance));
    });
  });

  group('orbitCameraControlSystem — mode gating', () {
    test('cinematic mode ignores manual camera input', () {
      world.upsertResource(
        CameraInteractionModeResource(mode: CameraInteractionMode.cinematic),
      );
      world.flush();
      world.events.writer<DragEvent>().send(
        drag(10, 10, buttons: kOrbitMiddleButton),
      );
      world.events.writer<ScrollEvent>().send(scroll(-100));
      orbitCameraControlSystem(world);
      expect(cam.yaw, 0);
      expect(cam.distance, 20);
    });

    test('editor mode allows navigation', () {
      world.upsertResource(
        CameraInteractionModeResource(mode: CameraInteractionMode.editor),
      );
      world.flush();
      world.events.writer<DragEvent>().send(
        drag(10, 0, buttons: kOrbitMiddleButton),
      );
      orbitCameraControlSystem(world);
      expect(cam.yaw, greaterThan(0));
    });
  });

  group('OrbitCameraResource math (renderer bridge surface)', () {
    test('cameraPosition is spherical around the target', () {
      cam
        ..yaw = 0
        ..pitch = 0
        ..distance = 10
        ..targetX = 0
        ..targetY = 0
        ..targetZ = 0;
      final eye = cam.cameraPosition();
      // yaw 0, pitch 0 → eye straight out along +Z at the distance.
      expect(eye.x, closeTo(0, 1e-9));
      expect(eye.y, closeTo(0, 1e-9));
      expect(eye.z, closeTo(10, 1e-9));
    });

    test('zoomAt slides the target toward the cursor world point', () {
      cam
        ..distance = 20
        ..targetX = 0
        ..targetY = 0
        ..targetZ = 0;
      cam.zoomAt(0.5, 10, 0, 10); // zoom in, cursor over world (10,0,10)
      expect(cam.distance, closeTo(10, 1e-9));
      // keep = 1 - 10/20 = 0.5 → target moves halfway to the cursor point.
      expect(cam.targetX, closeTo(5, 1e-9));
      expect(cam.targetZ, closeTo(5, 1e-9));
    });

    test('resetToHome returns to the construction pose', () {
      cam
        ..yaw = 2
        ..pitch = -1
        ..distance = 300
        ..targetX = 40
        ..targetY = 1
        ..targetZ = -40;
      cam.resetToHome();
      expect(cam.yaw, 0, reason: 'home yaw = constructor yaw (0 in setUp)');
      expect(cam.pitch, 0.5);
      expect(cam.distance, 20);
      expect(cam.targetX, 0);
      expect(cam.targetZ, 0);
    });

    test('no OrbitCameraResource → system is a safe no-op', () {
      final bare = World();
      bare.systems.plugins.add(const InputPlugin(), bare);
      bare.flush();
      bare.events.writer<DragEvent>().send(drag(10, 0));
      expect(() => orbitCameraControlSystem(bare), returnsNormally);
    });
  });

  group('orbitCameraControlSystem — modifiers + consumption', () {
    test('shift-drag orbits (trackpad/mouse without a middle button)', () {
      world.events.writer<DragEvent>().send(
        DragEvent(
          position: Offset.zero,
          worldPosition: Offset.zero,
          startPosition: Offset.zero,
          startWorldPosition: Offset.zero,
          delta: const Offset(10, 0),
          timestamp: 0,
          buttons: kOrbitPrimaryButton,
          modifierMask: inputModifierShiftMask,
        ),
      );
      orbitCameraControlSystem(world);
      expect(cam.yaw, greaterThan(0));
      expect(cam.targetX, 0);
    });

    test('consumed drags are skipped (editor paint claims the gesture)', () {
      final event = drag(10, 0);
      world.events.writer<DragEvent>().send(event);
      world.getResource<GestureConsumptionTracker>().markDragConsumed(event);
      orbitCameraControlSystem(world);
      expect(cam.targetX, 0);
      expect(cam.targetZ, 0);
    });
  });

  group('orbitCameraControlSystem — pinch / twist / zoom-at-cursor', () {
    PinchEvent pinch({
      double scale = 1,
      double rotation = 0,
      int pointerCount = 2,
      Offset focalPointDelta = Offset.zero,
      Offset worldPosition = Offset.zero,
    }) => PinchEvent(
      position: Offset.zero,
      worldPosition: worldPosition,
      scale: scale,
      focalPoint: Offset.zero,
      focalPointDelta: focalPointDelta,
      rotation: rotation,
      pointerCount: pointerCount,
      timestamp: 0,
    );

    test('cumulative pinch scale converts to per-update dolly', () {
      // No RawScaleStartEvent here: direct system calls replay the persisted
      // buffer each run, and the delta tracking makes replays idempotent
      // (ratio 1) — a replayed start event would wrongly reset mid-gesture.
      // The reset boundary is covered by its own single-run test below.
      world.events.writer<PinchEvent>().send(
        pinch(scale: 1.2, focalPointDelta: Offset.zero),
      );
      orbitCameraControlSystem(world);
      // ratio 1.2 → zoom(1/1.2): 20 → 16.67
      expect(cam.distance, closeTo(20 / 1.2, 1e-5)); // Float32 event storage

      world.events.writer<PinchEvent>().send(
        pinch(scale: 1.5, focalPointDelta: Offset.zero),
      );
      orbitCameraControlSystem(world);
      // ratio 1.5/1.2 = 1.25 → 16.67 → 13.33
      expect(cam.distance, closeTo(20 / 1.5, 1e-5));
    });

    test('RawScaleStart resets the cumulative pinch baseline', () {
      final fresh = World();
      fresh.systems.plugins.add(const InputPlugin(), fresh);
      final cam2 = OrbitCameraResource(yaw: 0, pitch: 0.5, distance: 20)
        ..lastPinchScale = 3; // mid-gesture state from a previous frame
      fresh.upsertResource(cam2);
      fresh.flush();
      fresh.events.writer<RawScaleStartEvent>().send(
        const RawScaleStartEvent(focalPoint: Offset.zero, timestamp: 0),
      );
      fresh.events.writer<PinchEvent>().send(
        PinchEvent(
          position: Offset.zero,
          worldPosition: Offset.zero,
          scale: 1.5,
          focalPoint: Offset.zero,
          timestamp: 0,
          pointerCount: 2,
        ),
      );
      orbitCameraControlSystem(fresh);
      // Baseline reset to 1 → ratio 1.5 → 20 / 1.5 (NOT 20 * 3 / 1.5).
      expect(cam2.distance, closeTo(20 / 1.5, 1e-9));
    });

    test('cumulative rotation converts to yaw twist', () {
      world.events.writer<PinchEvent>().send(pinch(rotation: 0.3));
      orbitCameraControlSystem(world);
      expect(cam.yaw, closeTo(0.3, 1e-6)); // Float32 event storage
      world.events.writer<PinchEvent>().send(pinch(rotation: 0.5));
      orbitCameraControlSystem(world);
      // Delta only: 0.5 cumulative → +0.2 this update (the replayed 0.3
      // event contributes a zero delta).
      expect(cam.yaw, closeTo(0.5, 1e-6));
    });

    test('two-finger focal drag pans once (DragEvent suppressed)', () {
      // The same physical gesture also emits per-pointer DragEvents; the
      // transform-active frame must ignore them so panning is not doubled.
      world.events.writer<DragEvent>().send(drag(10, 0));
      world.events.writer<PinchEvent>().send(
        pinch(focalPointDelta: const Offset(10, 0)),
      );
      orbitCameraControlSystem(world);
      final s = cam.distance * cam.panScale;
      expect(cam.targetX, closeTo(10 * s, 1e-9), reason: 'single pan, not 2x');
    });

    test('plain mouse drag alongside an identity PinchEvent pans once', () {
      // Single pointer, scale 1, rotation 0 = the scale recognizer's shadow
      // of an ordinary drag — the DragEvent owns it.
      world.events.writer<DragEvent>().send(drag(10, 0));
      world.events.writer<PinchEvent>().send(
        pinch(pointerCount: 1, focalPointDelta: const Offset(10, 0)),
      );
      orbitCameraControlSystem(world);
      final s = cam.distance * cam.panScale;
      expect(cam.targetX, closeTo(10 * s, 1e-9));
    });

    test('scroll zooms at the cursor when the bridge projects it', () {
      cam.zoomAtCursor = true;
      world.events.writer<ScrollEvent>().send(
        ScrollEvent(
          position: Offset.zero,
          // Bridge convention: worldPosition = Offset(worldX, worldZ) of the
          // ground point under the cursor (plane at targetY).
          worldPosition: const Offset(10, 10),
          delta: const Offset(0, -100),
          timestamp: 0,
        ),
      );
      orbitCameraControlSystem(world);
      expect(cam.distance, closeTo(18, 1e-9)); // 20 * 0.9
      // keep = 1 - 18/20 = 0.1 → target slides 10% toward (10, 10).
      expect(cam.targetX, closeTo(1, 1e-9));
      expect(cam.targetZ, closeTo(1, 1e-9));
    });

    test('double-tap zooms in (at the cursor when projected)', () {
      cam.zoomAtCursor = true;
      world.events.writer<DoubleTapEvent>().send(
        const DoubleTapEvent(
          position: Offset.zero,
          worldPosition: Offset(0, 0),
          timestamp: 0,
        ),
      );
      orbitCameraControlSystem(world);
      expect(cam.distance, closeTo(16, 1e-9)); // 20 * 0.8
      expect(cam.targetX, 0);
    });
  });

  group('orbitCameraKeyboardSystem — RuntimeInputMap actions', () {
    late InputStateTracker tracker;

    setUp(() {
      tracker = world.getResource<InputStateTracker>();
      world.upsertResource(DeltaTimeResource(1 / 60));
      world.flush();
    });

    test('moveRight pans the view right (inverse of a grab-drag)', () {
      tracker.updateState(InputAction.moveRight, InputState.pressed);
      orbitCameraKeyboardSystem(world);
      expect(cam.targetX, lessThan(0));
      expect(cam.targetZ, closeTo(0, 1e-12));
    });

    test('moveUp pans the view up-screen (target toward -Z at yaw 0)', () {
      tracker.updateState(InputAction.moveUp, InputState.pressed);
      orbitCameraKeyboardSystem(world);
      expect(cam.targetZ, lessThan(0));
      expect(cam.targetX, closeTo(0, 1e-12));
    });

    test('zoomIn held dollies in exponentially', () {
      tracker.updateState(InputAction.zoomIn, InputState.pressed);
      orbitCameraKeyboardSystem(world);
      expect(cam.distance, lessThan(20));
      expect(cam.distance, greaterThan(19), reason: 'one 60th of a halving');
    });

    test('cameraReset (justPressed) returns to the home pose', () {
      cam
        ..yaw = 2
        ..targetX = 50;
      tracker.updateState(InputAction.cameraReset, InputState.pressed);
      orbitCameraKeyboardSystem(world);
      expect(cam.yaw, 0);
      expect(cam.targetX, 0);
    });

    test('cinematic mode blocks keyboard navigation', () {
      world.upsertResource(
        CameraInteractionModeResource(mode: CameraInteractionMode.cinematic),
      );
      world.flush();
      tracker.updateState(InputAction.moveRight, InputState.pressed);
      tracker.updateState(InputAction.cameraReset, InputState.pressed);
      cam.yaw = 2;
      orbitCameraKeyboardSystem(world);
      expect(cam.targetX, 0);
      expect(cam.yaw, 2, reason: 'reset is blocked too');
    });
  });

  group('schedule wiring (explicit dependency edges)', () {
    test('raw pointer drag through the Input schedule pans the orbit', () {
      // The full pipeline: UnifiedInputWidget-shaped RAW events → gesture
      // classification → orbitCameraControlSystem → cleared. Proves
      // configureOrbitCameraControlSchedule's runAfter/runBefore edges land
      // the system between classification and the clear under the real
      // (alphabetical tie-break) scheduler.
      configureOrbitCameraControlSchedule(world);
      configureOrbitCameraKeyboardSchedule(world);
      world.flush();

      world.events.writer<RawPointerDownEvent>().send(
        const RawPointerDownEvent(
          position: Offset(0, 0),
          worldPosition: Offset(0, 0),
          timestamp: 1000,
          pointer: 1,
          buttons: 1,
        ),
      );
      world.events.writer<RawPointerMoveEvent>().send(
        const RawPointerMoveEvent(
          position: Offset(20, 0),
          worldPosition: Offset(20, 0),
          delta: Offset(20, 0),
          timestamp: 1016,
          pointer: 1,
          buttons: 1,
        ),
      );
      world.events.writer<RawPointerUpEvent>().send(
        const RawPointerUpEvent(
          position: Offset(20, 0),
          worldPosition: Offset(20, 0),
          timestamp: 1032,
          pointer: 1,
          buttons: 1,
        ),
      );

      world.runSchedule(const ScheduleId('Input'));

      expect(cam.targetX, greaterThan(0), reason: 'drag right pans +X');
      expect(cam.yaw, 0);
      // Events were cleared at the end of the run.
      expect(world.events.reader<DragEvent>().isNotEmpty, isFalse);
    });
  });
}
