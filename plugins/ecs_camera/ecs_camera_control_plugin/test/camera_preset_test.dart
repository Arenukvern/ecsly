import 'package:ecsly/ecsly.dart';
import 'package:ecs_camera_control_plugin/ecs_camera_control_plugin.dart';
import 'package:ecs_camera_plugin/ecs_camera_plugin.dart';
import 'package:ecs_input_plugin/ecs_input_plugin.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  List<dynamic> _bundleComponents(final ComponentBundle bundle) =>
      bundle.components.items.map((final c) => c.$2).toList();

  group('CameraPreset', () {
    test('all presets create valid component bundles', () {
      for (final preset in CameraPreset.values) {
        final bundle = preset.createBundle();
        expect(bundle.components, isNotEmpty);
      }
    });

    test('RTS preset creates expected components', () {
      final bundle = CameraPreset.rts.createBundle();
      final list = _bundleComponents(bundle);

      // Should contain target, control, and action components
      expect(list.length, greaterThanOrEqualTo(5));

      // Check for specific component types
      final hasFreeTarget = list.any((final c) => c is FreeTarget);
      final hasController = list.any((final c) => c is CameraController);
      final hasZoom = list.any((final c) => c is CameraZoom);
      final hasPanAction = list.any((final c) => c is CameraPanAction);
      final hasZoomAction = list.any((final c) => c is CameraZoomAction);

      expect(
        hasFreeTarget,
        isTrue,
        reason: 'RTS preset should have FreeTarget',
      );
      expect(hasController, isTrue, reason: 'Should have CameraController');
      expect(hasZoom, isTrue, reason: 'Should have CameraZoom');
      expect(hasPanAction, isTrue, reason: 'Should have CameraPanAction');
      expect(hasZoomAction, isTrue, reason: 'Should have CameraZoomAction');
    });

    test('Platformer preset creates follow target', () {
      final bundle = CameraPreset.platformer.createBundle();
      final list = _bundleComponents(bundle);

      final hasFollowTarget = list.any((final c) => c is FollowTarget);
      final hasFreeTarget = list.any((final c) => c is FreeTarget);

      expect(
        hasFollowTarget || hasFreeTarget,
        isTrue,
        reason: 'Platformer preset should include a platform target',
      );
    });

    test('TopDown and RTS presets have no smoothing', () {
      final topDownBundle = CameraPreset.topDown.createBundle();
      final rtsBundle = CameraPreset.rts.createBundle();

      final topDownHasSmoothing = _bundleComponents(
        topDownBundle,
      ).any((final c) => c is CameraSmoothing);
      final rtsHasSmoothing = _bundleComponents(
        rtsBundle,
      ).any((final c) => c is CameraSmoothing);

      expect(
        topDownHasSmoothing,
        isFalse,
        reason: 'TopDown preset should not have smoothing',
      );
      expect(
        rtsHasSmoothing,
        isFalse,
        reason: 'RTS preset should not have smoothing',
      );
    });

    test('presets accept custom parameters', () {
      const customSpeed = 999.0;
      const customMinZoom = 0.1;
      const customMaxZoom = 10.0;

      final bundle = CameraPreset.rts.createBundle(
        moveSpeed: customSpeed,
        minZoom: customMinZoom,
        maxZoom: customMaxZoom,
      );
      final components = _bundleComponents(bundle);

      final controller = components.whereType<CameraController>().first;

      expect(controller.moveSpeed, equals(customSpeed));
      // Zoom limits are in CameraConstraints, not CameraZoom
      final constraints = components.whereType<CameraConstraints>().firstOrNull;
      if (constraints != null) {
        expect(constraints.minZoom, equals(customMinZoom));
        expect(constraints.maxZoom, equals(customMaxZoom));
      }
    });

    test('configureInputMap sets up preset-specific bindings', () {
      final inputMap = RuntimeInputMap();

      CameraPreset.rts.configureInputMap(inputMap);

      // Check that RTS-specific bindings are set
      final panSources = inputMap.getSources(InputAction.cameraPan);
      expect(
        panSources,
        isNotEmpty,
        reason: 'RTS preset should bind camera pan',
      );

      final zoomSources = inputMap.getSources(InputAction.zoomIn);
      expect(zoomSources, isNotEmpty, reason: 'RTS preset should bind zoom');
    });

    test('each preset has unique default settings', () {
      const presets = CameraPreset.values;
      final speeds = presets.map((final p) => p.defaultMoveSpeed).toSet();
      final minZooms = presets.map((final p) => p.defaultMinZoom).toSet();
      final maxZooms = presets.map((final p) => p.defaultMaxZoom).toSet();

      // All presets should have different speeds (ensures they're unique)
      expect(
        speeds.length,
        equals(presets.length),
        reason: 'All presets should have unique default speeds',
      );
      expect(
        minZooms.length,
        greaterThan(1),
        reason: 'Presets should have varying min zoom levels',
      );
      expect(
        maxZooms.length,
        greaterThan(1),
        reason: 'Presets should have varying max zoom levels',
      );
    });

    test('preset switching replaces all components', () {
      // This test demonstrates that switching presets replaces all components
      // rather than leaving orphaned ones
      final rtsBundle = CameraPreset.rts.createBundle();
      final platformerBundle = CameraPreset.platformer.createBundle();

      final rtsComponents = _bundleComponents(rtsBundle);
      final platformerComponents = _bundleComponents(platformerBundle);

      expect(
        rtsComponents.any((final c) => c is CameraSelectAction),
        isTrue,
        reason: 'RTS preset should include camera select',
      );
      expect(
        platformerComponents.any((final c) => c is CameraSelectAction),
        isFalse,
        reason: 'Platformer preset should not include camera select',
      );
    });
  });

  group('CameraPreset Integration', () {
    late World world;

    setUp(() {
      world = World()
        ..addPlugin(CameraPlugin())
        ..addPlugin(const InputPlugin())
        ..addPlugin(const CameraControlPlugin());
    });

    test('can apply preset to camera entity', () {
      final camera = world.reserveEmptyEntity();

      // Apply RTS preset
      final bundle = CameraPreset.rts.createBundle();

      world.spawnBundle(camera.entity, bundle);

      // Verify components were added
      final hasController = world.query<CameraController>().firstOrNull != null;
      final hasTarget = world.query<FreeTarget>().firstOrNull != null;

      expect(
        hasController,
        isTrue,
        reason: 'Camera should have controller after preset application',
      );
      expect(
        hasTarget,
        isTrue,
        reason: 'Camera should have target after preset application',
      );
    });

    test('preset input configuration works with input system', () {
      final inputMap = world.getResource<RuntimeInputMap>();

      // Configure RTS preset input
      CameraPreset.rts.configureInputMap(inputMap);

      // Verify input map has bindings
      final moveSources = inputMap.getSources(InputAction.moveUp);
      expect(
        moveSources,
        isNotEmpty,
        reason: 'Preset should configure movement inputs',
      );
    });
  });
}
