import 'package:ecs_camera_control_plugin/ecs_camera_control_plugin.dart';
import 'package:ecs_input_plugin/ecs_input_plugin.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RuntimeInputMap JSON Serialization', () {
    late RuntimeInputMap inputMap;

    setUp(() {
      inputMap = RuntimeInputMap();
    });

    test('roundtrip serialization preserves all bindings', () {
      // Add various types of bindings
      inputMap
        ..bindSingle(
          const KeyboardSource(LogicalKeyboardKey.keyW),
          InputAction.moveUp,
        )
        ..bindSingle(
          const KeyboardSource(LogicalKeyboardKey.keyA),
          InputAction.moveLeft,
        )
        ..bindSingle(
          const KeyboardSource(LogicalKeyboardKey.keyS),
          InputAction.moveDown,
        )
        ..bindSingle(
          const KeyboardSource(LogicalKeyboardKey.keyD),
          InputAction.moveRight,
        )
        ..bindSingle(const MouseButtonSource(0), InputAction.attack)
        ..bindSingle(
          const GestureSource(GestureType.drag),
          InputAction.cameraPan,
        )
        ..bindSingle(
          const GestureSource(GestureType.scroll),
          InputAction.zoomIn,
        );

      // Add a binding with modifiers
      inputMap.bind(
        const KeyboardSource(
          LogicalKeyboardKey.keyW,
          modifiers: KeyModifiers(ctrl: true),
        ),
        {InputAction.moveUp},
      );

      // Serialize and deserialize
      final json = inputMap.toJson();
      final result = RuntimeInputMap.fromJsonWithErrors(json);
      final deserializedMap = result.map;

      // Verify all bindings are preserved
      expect(
        deserializedMap.getSources(InputAction.moveUp).length,
        equals(2), // W and Ctrl+W
        reason: 'Should preserve both regular and modified key bindings',
      );
      expect(
        deserializedMap.getSources(InputAction.moveLeft).length,
        equals(1),
        reason: 'Should preserve single key binding',
      );
      expect(
        deserializedMap.getSources(InputAction.moveDown).length,
        equals(1),
        reason: 'Should preserve single key binding',
      );
      expect(
        deserializedMap.getSources(InputAction.moveRight).length,
        equals(1),
        reason: 'Should preserve single key binding',
      );
      expect(
        deserializedMap.getSources(InputAction.attack).length,
        equals(1),
        reason: 'Should preserve mouse binding',
      );
      expect(
        deserializedMap.getSources(InputAction.cameraPan).length,
        equals(1),
        reason: 'Should preserve gesture binding',
      );
      expect(
        deserializedMap.getSources(InputAction.zoomIn).length,
        equals(1),
        reason: 'Should preserve scroll gesture binding',
      );
    });

    test('keyboard source serialization roundtrip', () {
      const original = KeyboardSource(LogicalKeyboardKey.keyW);
      final json = original.toJson();
      final deserialized = InputSource.fromUniqueId(
        json['type'] == 'keyboard'
            ? 'kb:${(json['data'] as Map)['keyId']}'
            : '',
      );

      expect(deserialized, isA<KeyboardSource>());
      final kbSource = deserialized! as KeyboardSource;
      expect(kbSource.key, equals(original.key));
      expect(kbSource.modifiers, equals(original.modifiers));
    });

    test('keyboard source with modifiers serialization', () {
      const original = KeyboardSource(
        LogicalKeyboardKey.keyW,
        modifiers: KeyModifiers(ctrl: true, shift: true),
      );
      final json = original.toJson();
      final uniqueId = 'kb:${(json['data'] as Map)['keyId']}+ctrl+shift';
      final deserialized = InputSource.fromUniqueId(uniqueId);

      expect(deserialized, isA<KeyboardSource>());
      final kbSource = deserialized! as KeyboardSource;
      expect(kbSource.key, equals(original.key));
      expect(kbSource.modifiers?.ctrl, isTrue);
      expect(kbSource.modifiers?.shift, isTrue);
      expect(kbSource.modifiers?.alt, isFalse);
      expect(kbSource.modifiers?.meta, isFalse);
    });

    test('mouse button source serialization roundtrip', () {
      const original = MouseButtonSource(
        1,
        modifiers: KeyModifiers(shift: true),
      );
      final json = original.toJson();
      final uniqueId = 'mouse:${(json['data'] as Map)['button']}+shift';
      final deserialized = InputSource.fromUniqueId(uniqueId);

      expect(deserialized, isA<MouseButtonSource>());
      final mouseSource = deserialized! as MouseButtonSource;
      expect(mouseSource.button, equals(original.button));
      expect(mouseSource.modifiers?.shift, isTrue);
    });

    test('gesture source serialization roundtrip', () {
      const original = GestureSource(GestureType.drag);
      final json = original.toJson();
      final uniqueId = 'gesture:${(json['data'] as Map)['type']}';
      final deserialized = InputSource.fromUniqueId(uniqueId);

      expect(deserialized, isA<GestureSource>());
      final gestureSource = deserialized! as GestureSource;
      expect(gestureSource.type, equals(original.type));
    });

    test('handles invalid unique IDs gracefully', () {
      final invalidIds = [
        'invalid',
        'kb:999999', // Invalid key ID
        'mouse:abc', // Invalid button
        'gesture:nonexistent', // Invalid gesture type
        '', // Empty
        'kb:', // Missing key ID
      ];

      for (final id in invalidIds) {
        final result = InputSource.fromUniqueId(id);
        expect(
          result,
          isNull,
          reason: 'Should return null for invalid ID: $id',
        );
      }
    });

    test('multiple actions per source serialization', () {
      // Bind one source to multiple actions
      inputMap.bind(const KeyboardSource(LogicalKeyboardKey.space), {
        InputAction.jump,
        InputAction.interact,
      });

      final json = inputMap.toJson();
      final result = RuntimeInputMap.fromJsonWithErrors(json);
      final deserializedMap = result.map;

      final sources = deserializedMap.getSources(InputAction.jump);
      expect(sources.length, equals(1));
      expect(
        deserializedMap.getActions(sources.first),
        containsAll({InputAction.jump, InputAction.interact}),
      );
    });

    test('empty input map serialization', () {
      final json = inputMap.toJson();
      final result = RuntimeInputMap.fromJsonWithErrors(json);
      final deserializedMap = result.map;

      // Empty map should have no bindings
      for (final action in InputAction.values) {
        expect(deserializedMap.getSources(action), isEmpty);
      }
    });

    test('handles malformed JSON gracefully', () {
      // Test various malformed JSON cases
      final malformedJsons = [
        {'bindings': 'not-a-list'}, // Wrong type for bindings
        {
          'bindings': [
            {'source': 'kb:87'},
          ],
        }, // Missing actions
        {
          'bindings': [
            {
              'actions': ['moveUp'],
            },
          ],
        }, // Missing source
        {
          'bindings': [
            {'source': 'kb:87', 'actions': 'not-a-list'},
          ],
        }, // Wrong actions type
        {
          'bindings': [
            {
              'source': 'kb:87',
              'actions': ['invalid-action'],
            },
          ],
        }, // Invalid action
      ];

      for (final json in malformedJsons) {
        // Should not crash, but may skip invalid bindings and report errors
        final result = RuntimeInputMap.fromJsonWithErrors(json);
        expect(
          result.map,
          isNotNull,
          reason: 'Should return a map even with errors',
        );
        expect(
          result.hasErrors,
          isTrue,
          reason: 'Should report errors for malformed JSON',
        );
      }
    });

    test('preset configuration can be serialized', () {
      // Configure RTS preset
      CameraPreset.rts.configureInputMap(inputMap);

      // Serialize
      final json = inputMap.toJson();
      expect(
        json['bindings'],
        isNotEmpty,
        reason: 'Preset should add bindings that can be serialized',
      );

      // Deserialize
      final result = RuntimeInputMap.fromJsonWithErrors(json);
      final deserializedMap = result.map;

      // Verify preset bindings are preserved
      expect(
        deserializedMap.getSources(InputAction.moveUp),
        isNotEmpty,
        reason: 'Preset movement bindings should be preserved',
      );
      expect(
        deserializedMap.getSources(InputAction.cameraPan),
        isNotEmpty,
        reason: 'Preset camera bindings should be preserved',
      );
    });

    test('JSON format is version-compatible', () {
      // Create a known JSON format
      // Use a valid key ID - we'll get it from a real keyboard source
      const wKey = LogicalKeyboardKey.keyW;
      final knownJson = {
        'bindings': [
          {
            'source': 'kb:${wKey.keyId}',
            'actions': ['moveUp'],
          },
          {
            'source': 'gesture:drag',
            'actions': ['cameraPan'],
          },
        ],
      };

      final result = RuntimeInputMap.fromJsonWithErrors(knownJson);
      final map = result.map;

      expect(map.getSources(InputAction.moveUp), isNotEmpty);
      expect(map.getSources(InputAction.cameraPan), isNotEmpty);

      // Serialized version should be equivalent
      final reserialized = map.toJson();
      expect(
        (reserialized['bindings'] as List).length,
        equals(2),
        reason: 'Should preserve binding count through reserialization',
      );
    });

    group('fromJsonWithErrors error reporting', () {
      test('reports missing source field', () {
        final json = {
          'bindings': [
            {
              'actions': ['moveUp'],
            }, // Missing source
          ],
        };

        final result = RuntimeInputMap.fromJsonWithErrors(json);

        expect(result.hasErrors, isTrue);
        expect(result.errors, hasLength(1));
        expect(result.errors.first, contains('missing "source" field'));
        expect(result.map.getSources(InputAction.moveUp), isEmpty);
      });

      test('reports unknown source types', () {
        final json = {
          'bindings': [
            {
              'source': 'unknown:123',
              'actions': ['moveUp'],
            },
          ],
        };

        final result = RuntimeInputMap.fromJsonWithErrors(json);

        expect(result.hasErrors, isTrue);
        expect(result.errors, hasLength(1));
        expect(result.errors.first, contains('unknown source type'));
        expect(result.map.getSources(InputAction.moveUp), isEmpty);
      });

      test('reports invalid action names', () {
        final json = {
          'bindings': [
            {
              'source': 'kb:87',
              'actions': ['invalid-action', 'moveUp'],
            },
          ],
        };

        final result = RuntimeInputMap.fromJsonWithErrors(json);

        expect(result.hasErrors, isTrue);
        expect(result.errors, hasLength(1));
        expect(
          result.errors.first,
          contains('unknown action "invalid-action"'),
        );
        // Should still load the valid action
        expect(result.map.getSources(InputAction.moveUp), hasLength(1));
      });

      test('reports wrong action type', () {
        final json = {
          'bindings': [
            {'source': 'kb:87', 'actions': 'not-a-list'},
          ],
        };

        final result = RuntimeInputMap.fromJsonWithErrors(json);

        expect(result.hasErrors, isTrue);
        expect(result.errors, hasLength(1));
        expect(result.errors.first, contains('expected string, got'));
        expect(result.map.getSources(InputAction.moveUp), isEmpty);
      });

      test('reports invalid binding format', () {
        final json = {
          'bindings': [
            'not-an-object', // Wrong format
          ],
        };

        final result = RuntimeInputMap.fromJsonWithErrors(json);

        expect(result.hasErrors, isTrue);
        expect(result.errors, hasLength(1));
        expect(result.errors.first, contains('invalid binding format'));
      });

      test('reports invalid JSON structure', () {
        final json = {'bindings': 'not-a-list'};

        final result = RuntimeInputMap.fromJsonWithErrors(json);

        expect(result.hasErrors, isTrue);
        expect(result.errors, hasLength(1));
        expect(result.errors.first, contains('Invalid JSON structure'));
      });

      test('succeeds with valid JSON', () {
        final json = {
          'bindings': [
            {
              'source': 'kb:87',
              'actions': ['moveUp'],
            },
            {
              'source': 'gesture:drag',
              'actions': ['cameraPan'],
            },
          ],
        };

        final result = RuntimeInputMap.fromJsonWithErrors(json);

        expect(result.hasErrors, isFalse);
        expect(result.errors, isEmpty);
        expect(result.map.getSources(InputAction.moveUp), hasLength(1));
        expect(result.map.getSources(InputAction.cameraPan), hasLength(1));
      });

      test('partially loads valid bindings when some are invalid', () {
        final json = {
          'bindings': [
            {
              'source': 'kb:87',
              'actions': ['moveUp'],
            }, // Valid
            {
              'source': 'unknown:123',
              'actions': ['moveLeft'],
            }, // Invalid source
            {
              'source': 'gesture:drag',
              'actions': ['cameraPan'],
            }, // Valid
            {
              'source': 'kb:65',
              'actions': ['invalid-action'],
            }, // Invalid action
          ],
        };

        final result = RuntimeInputMap.fromJsonWithErrors(json);

        expect(result.hasErrors, isTrue);
        expect(result.errors, hasLength(2)); // Two errors
        expect(result.map.getSources(InputAction.moveUp), hasLength(1));
        expect(result.map.getSources(InputAction.cameraPan), hasLength(1));
        expect(result.map.getSources(InputAction.moveLeft), isEmpty);
      });
    });
  });
}
