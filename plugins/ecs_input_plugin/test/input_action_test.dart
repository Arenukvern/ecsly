import 'package:ecsly/ecsly.dart';
import 'package:ecs_input_plugin/ecs_input_plugin.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RuntimeInputMap', () {
    late World world;
    late RuntimeInputMap inputMap;

    setUp(() {
      world = World()..addPlugin(const InputPlugin());
      inputMap = world.getResource<RuntimeInputMap>();
    });

    test('default mappings are initialized', () {
      final sources = inputMap.getSources(InputAction.moveUp);
      expect(sources.length, greaterThan(0));
      expect(
        sources.any(
          (final s) => s is KeyboardSource && s.key == LogicalKeyboardKey.keyW,
        ),
        isTrue,
      );
    });

    test('can bind keyboard source to action', () {
      const source = KeyboardSource(LogicalKeyboardKey.keyT);
      inputMap.bindSingle(source, InputAction.jump);

      final actions = inputMap.getActions(source);
      expect(actions, contains(InputAction.jump));
    });

    test('can bind multiple actions to one source', () {
      const source = KeyboardSource(LogicalKeyboardKey.keyT);
      inputMap.bind(source, {InputAction.jump, InputAction.special});

      final actions = inputMap.getActions(source);
      expect(actions, hasLength(2));
      expect(actions, containsAll([InputAction.jump, InputAction.special]));
    });

    test('unbinding removes source', () {
      const source = KeyboardSource(LogicalKeyboardKey.keyT);
      inputMap.bindSingle(source, InputAction.jump);
      inputMap.unbind(source);

      final actions = inputMap.getActions(source);
      expect(actions, isEmpty);
    });

    test('can bind gesture sources', () {
      const source = GestureSource(GestureType.drag);
      inputMap.bindSingle(source, InputAction.cameraPan);

      final actions = inputMap.getActions(source);
      expect(actions, contains(InputAction.cameraPan));
    });
  });

  group('RuntimeInputMap JSON Persistence', () {
    test('toJson serializes bindings correctly', () {
      final inputMap = RuntimeInputMap();
      inputMap.bindSingle(
        const KeyboardSource(LogicalKeyboardKey.keyW),
        InputAction.moveUp,
      );
      inputMap.bindSingle(
        const GestureSource(GestureType.drag),
        InputAction.cameraPan,
      );

      final jsonMap = inputMap.toJson();
      final bindings = jsonMap['bindings'] as List<dynamic>;

      expect(jsonMap, contains('bindings'));
      expect(bindings, isA<List>());
      expect(bindings.length, equals(2));
    });

    test('fromJson deserializes bindings correctly', () {
      final json = {
        'bindings': [
          {
            'source': {
              'type': 'keyboard',
              'data': {'keyId': LogicalKeyboardKey.keyW.keyId},
            },
            'actions': ['moveUp'],
          },
          {
            'source': {
              'type': 'gesture',
              'data': {'type': 'drag'},
            },
            'actions': ['cameraPan'],
          },
        ],
      };

      final result = RuntimeInputMap.fromJsonWithErrors(json);
      final inputMap = result.map;

      final moveUpSources = inputMap.getSources(InputAction.moveUp);
      expect(moveUpSources.length, equals(1));
      expect(moveUpSources.first, isA<KeyboardSource>());

      final panSources = inputMap.getSources(InputAction.cameraPan);
      expect(panSources.length, equals(1));
      expect(panSources.first, isA<GestureSource>());
    });

    test('JSON roundtrip preserves all bindings', () {
      final original = RuntimeInputMap();
      original.initializeDefaults();

      // Add custom binding
      original.bindSingle(
        const KeyboardSource(LogicalKeyboardKey.f1),
        InputAction.pause,
      );

      final json = original.toJson();
      final result = RuntimeInputMap.fromJsonWithErrors(json);
      final loaded = result.map;

      // Check that all actions have the same number of sources
      for (final action in InputAction.values) {
        final originalSources = original.getSources(action);
        final loadedSources = loaded.getSources(action);
        expect(
          loadedSources.length,
          equals(originalSources.length),
          reason: 'Action $action source count mismatch',
        );
      }
    });

    test('fromJson handles invalid bindings gracefully', () {
      final json = {
        'bindings': [
          {
            'source': {'type': 'invalid', 'data': {}},
            'actions': ['moveUp'],
          },
          {
            'source': {
              'type': 'keyboard',
              'data': {'keyId': LogicalKeyboardKey.keyW.keyId},
            },
            'actions': ['moveUp'],
          },
        ],
      };

      // Should not throw and should load valid bindings
      final result = RuntimeInputMap.fromJsonWithErrors(json);
      final inputMap = result.map;
      final sources = inputMap.getSources(InputAction.moveUp);
      expect(sources.length, equals(1)); // Only the valid one
    });

    test('fromJson handles unknown actions gracefully', () {
      final json = {
        'bindings': [
          {
            'source': {
              'type': 'keyboard',
              'data': {'keyId': LogicalKeyboardKey.keyW.keyId},
            },
            'actions': ['moveUp', 'unknownAction'],
          },
        ],
      };

      // Should not throw and should load valid actions
      final result = RuntimeInputMap.fromJsonWithErrors(json);
      final inputMap = result.map;
      final sources = inputMap.getSources(InputAction.moveUp);
      expect(sources.length, equals(1));
    });
  });

  group('InputStateTracker', () {
    test('tracks pressed state', () {
      final tracker = InputStateTracker();
      tracker.updateState(InputAction.jump, InputState.pressed);

      expect(tracker.justPressed(InputAction.jump), isTrue);
      expect(tracker.isHeld(InputAction.jump), isTrue);
    });

    test('transitions pressed to held', () {
      final tracker = InputStateTracker();
      tracker.updateState(InputAction.jump, InputState.pressed);
      tracker.advance();

      expect(tracker.justPressed(InputAction.jump), isFalse);
      expect(tracker.isHeld(InputAction.jump), isTrue);
    });

    test('tracks released state', () {
      final tracker = InputStateTracker();
      tracker.updateState(InputAction.jump, InputState.pressed);
      tracker.advance();
      tracker.updateState(InputAction.jump, InputState.released);

      expect(tracker.justReleased(InputAction.jump), isTrue);
      expect(tracker.isHeld(InputAction.jump), isFalse);
    });
  });
}
