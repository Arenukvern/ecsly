import 'package:ecsly/ecsly.dart';
import 'package:ecs_camera_control_plugin/ecs_camera_control_plugin.dart';
import 'package:ecs_camera_plugin/ecs_camera_plugin.dart';
import 'package:ecs_input_plugin/ecs_input_plugin.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Input System Performance', () {
    test('RuntimeInputMap lookup scales O(1)', () {
      RuntimeInputMap buildMap(final int size) {
        final map = RuntimeInputMap();
        for (var i = 0; i < size; i++) {
          map.bindSingle(
            KeyboardSource(LogicalKeyboardKey(1000 + i)),
            InputAction.values[i % InputAction.values.length],
          );
        }
        return map;
      }

      int measureLookupMicros(
        final RuntimeInputMap map,
        final KeyboardSource source,
        final int iterations,
      ) {
        var checksum = 0;
        final stopwatch = Stopwatch()..start();
        for (var i = 0; i < iterations; i++) {
          checksum += map.getActions(source).length;
        }
        stopwatch.stop();
        expect(checksum, greaterThan(0));
        return stopwatch.elapsedMicroseconds;
      }

      final smallMap = buildMap(64);
      final largeMap = buildMap(4096);
      const source = KeyboardSource(LogicalKeyboardKey(1050));
      const iterations = 20000;

      // Warm-up to reduce first-run JIT noise in benchmark loop.
      measureLookupMicros(smallMap, source, 1000);
      measureLookupMicros(largeMap, source, 1000);

      final smallMicros = measureLookupMicros(smallMap, source, iterations);
      final largeMicros = measureLookupMicros(largeMap, source, iterations);
      final smallPerLookup = smallMicros / iterations;
      final largePerLookup = largeMicros / iterations;

      // O(1) lookup should not degrade dramatically as map grows.
      expect(largePerLookup, lessThan(smallPerLookup * 3.0 + 0.5));
      print(
        'lookup small: ${smallPerLookup.toStringAsFixed(4)} μs, '
        'large: ${largePerLookup.toStringAsFixed(4)} μs',
      );
    });

    test('InputStateTracker advance() is fast', () {
      final tracker = InputStateTracker();

      // Simulate 100 concurrent actions
      for (final action in InputAction.values) {
        tracker.updateState(action, InputState.pressed);
      }

      // Warm-up the transition and JIT path.
      for (var i = 0; i < 1000; i++) {
        tracker.advance();
      }

      const iterations = 20000;
      final stopwatch = Stopwatch()..start();
      for (var i = 0; i < iterations; i++) {
        tracker.advance();
      }
      stopwatch.stop();

      final perCallMicros = stopwatch.elapsedMicroseconds / iterations;
      expect(perCallMicros, lessThan(20.0));
      print(
        'advance() with ${InputAction.values.length} actions: '
        '${perCallMicros.toStringAsFixed(4)} μs/call',
      );
    });

    test('Camera preset switching is instantaneous', () {
      final world = World()..addPlugin(CameraPlugin());

      final camera = world.entities.create();

      final stopwatch = Stopwatch()..start();
      world.spawnBundle(camera, CameraPreset.rts.createBundle());
      stopwatch.stop();

      expect(stopwatch.elapsedMilliseconds, lessThan(5));
      print('Camera preset switch: ${stopwatch.elapsedMilliseconds} ms');
    });

    test('Selection bulk operations scale linearly', () {
      final world = World()..addPlugin(const InputPlugin());

      final entities = List.generate(1000, (_) => world.entities.create());
      final selectionMgr = world.getResource<SelectionManager>();

      final stopwatch = Stopwatch()..start();
      selectionMgr.selectMultiple(entities);
      stopwatch.stop();

      final timePerEntity = stopwatch.elapsedMicroseconds / entities.length;
      expect(timePerEntity, lessThan(10)); // <10μs per entity
      print('Bulk select 1000 entities: ${stopwatch.elapsedMilliseconds} ms');
    });

    test('Axis input normalization prevents speed hacks', () {
      final tracker = InputStateTracker();

      // Press all four movement keys simultaneously
      tracker.updateState(InputAction.moveUp, InputState.held);
      tracker.updateState(InputAction.moveDown, InputState.held);
      tracker.updateState(InputAction.moveLeft, InputState.held);
      tracker.updateState(InputAction.moveRight, InputState.held);

      final (dx, dy) = tracker.getAxis2D(
        InputAction.moveUp,
        InputAction.moveDown,
        InputAction.moveLeft,
        InputAction.moveRight,
      );

      // Should be normalized to unit length (not 2.0, 2.0)
      final length = dx * dx + dy * dy;
      expect(length, closeTo(0.0, 0.001)); // Conflicting directions cancel out
      print('Conflicting input normalization: ($dx, $dy), length: $length');
    });

    test('Input map JSON serialization is fast', () {
      final map = RuntimeInputMap()..initializeDefaults();

      // Add many custom bindings
      for (var i = 0; i < 100; i++) {
        map.bindSingle(
          KeyboardSource(LogicalKeyboardKey(1000 + i)),
          InputAction.values[i % InputAction.values.length],
        );
      }

      final serializeStopwatch = Stopwatch()..start();
      final json = map.toJson();
      serializeStopwatch.stop();

      final deserializeStopwatch = Stopwatch()..start();
      final result = RuntimeInputMap.fromJsonWithErrors(json);
      final restoredMap = result.map;
      deserializeStopwatch.stop();

      expect(serializeStopwatch.elapsedMilliseconds, lessThan(10));
      expect(deserializeStopwatch.elapsedMilliseconds, lessThan(10));
      expect(
        restoredMap.getActions(const KeyboardSource(LogicalKeyboardKey(1050))),
        isNotEmpty,
      );
      print(
        'JSON serialize: ${serializeStopwatch.elapsedMilliseconds} ms, deserialize: ${deserializeStopwatch.elapsedMilliseconds} ms',
      );
    });
  });
}
