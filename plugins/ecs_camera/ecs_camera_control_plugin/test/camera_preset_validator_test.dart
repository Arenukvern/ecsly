import 'package:ecs_camera_control_plugin/ecs_camera_control_plugin.dart';
import 'package:ecs_input_plugin/ecs_input_plugin.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CameraPresetValidator', () {
    late CameraPresetValidator validator;
    late RuntimeInputMap inputMap;

    setUp(() {
      validator = CameraPresetValidator();
      inputMap = RuntimeInputMap();
    });

    group('RTS Preset Validation', () {
      test('validates complete RTS preset configuration', () {
        // Configure all required RTS bindings
        inputMap.bindSingle(
          const KeyboardSource(LogicalKeyboardKey.keyW),
          InputAction.moveUp,
        );
        inputMap.bindSingle(
          const GestureSource(GestureType.drag),
          InputAction.cameraPan,
        );
        inputMap.bindSingle(
          const GestureSource(GestureType.scroll),
          InputAction.zoomIn,
        );
        inputMap.bindSingle(
          const KeyboardSource(LogicalKeyboardKey.minus),
          InputAction.zoomOut,
        );
        inputMap.bindSingle(
          const KeyboardSource(LogicalKeyboardKey.keyR),
          InputAction.cameraReset,
        );
        inputMap.bindSingle(const MouseButtonSource(0), InputAction.attack);

        final result = validator.validatePreset(CameraPreset.rts, inputMap);
        expect(result.isValid, isTrue);
        expect(result.missingBindings, isEmpty);
      });

      test('detects missing bindings in RTS preset', () {
        // Only configure some bindings, missing cameraPan and attack
        inputMap.bindSingle(
          const KeyboardSource(LogicalKeyboardKey.keyW),
          InputAction.moveUp,
        );
        inputMap.bindSingle(
          const GestureSource(GestureType.scroll),
          InputAction.zoomIn,
        );
        inputMap.bindSingle(
          const KeyboardSource(LogicalKeyboardKey.minus),
          InputAction.zoomOut,
        );

        final result = validator.validatePreset(CameraPreset.rts, inputMap);
        expect(result.isValid, isFalse);
        expect(result.missingBindings, contains(InputAction.cameraPan));
        expect(result.missingBindings, contains(InputAction.attack));
        expect(result.missingBindings, hasLength(2));
      });
    });

    group('Platformer Preset Validation', () {
      test('validates complete platformer preset configuration', () {
        // Configure all required platformer bindings
        inputMap.bindSingle(
          const KeyboardSource(LogicalKeyboardKey.keyW),
          InputAction.moveUp,
        );
        inputMap.bindSingle(
          const KeyboardSource(LogicalKeyboardKey.keyA),
          InputAction.moveLeft,
        );
        inputMap.bindSingle(
          const KeyboardSource(LogicalKeyboardKey.keyS),
          InputAction.moveDown,
        );
        inputMap.bindSingle(
          const KeyboardSource(LogicalKeyboardKey.keyD),
          InputAction.moveRight,
        );
        inputMap.bindSingle(
          const GestureSource(GestureType.scroll),
          InputAction.zoomIn,
        );
        inputMap.bindSingle(
          const KeyboardSource(LogicalKeyboardKey.minus),
          InputAction.zoomOut,
        );
        inputMap.bindSingle(
          const KeyboardSource(LogicalKeyboardKey.space),
          InputAction.jump,
        );
        inputMap.bindSingle(
          const KeyboardSource(LogicalKeyboardKey.keyX),
          InputAction.attack,
        );

        final result = validator.validatePreset(
          CameraPreset.platformer,
          inputMap,
        );
        expect(result.isValid, isTrue);
        expect(result.missingBindings, isEmpty);
      });

      test('detects missing movement bindings in platformer preset', () {
        // Missing moveLeft and moveRight
        inputMap.bindSingle(
          const KeyboardSource(LogicalKeyboardKey.keyW),
          InputAction.moveUp,
        );
        inputMap.bindSingle(
          const KeyboardSource(LogicalKeyboardKey.keyS),
          InputAction.moveDown,
        );

        final result = validator.validatePreset(
          CameraPreset.platformer,
          inputMap,
        );
        expect(result.isValid, isFalse);
        expect(result.missingBindings, contains(InputAction.moveLeft));
        expect(result.missingBindings, contains(InputAction.moveRight));
        expect(result.missingBindings, contains(InputAction.zoomOut));
        expect(result.missingBindings, contains(InputAction.attack));
      });
    });

    group('TopDown Preset Validation', () {
      test('validates complete topDown preset configuration', () {
        // Configure all required topDown bindings
        inputMap.bindSingle(
          const KeyboardSource(LogicalKeyboardKey.keyW),
          InputAction.moveUp,
        );
        inputMap.bindSingle(
          const KeyboardSource(LogicalKeyboardKey.keyA),
          InputAction.moveLeft,
        );
        inputMap.bindSingle(
          const KeyboardSource(LogicalKeyboardKey.keyS),
          InputAction.moveDown,
        );
        inputMap.bindSingle(
          const KeyboardSource(LogicalKeyboardKey.keyD),
          InputAction.moveRight,
        );
        inputMap.bindSingle(
          const GestureSource(GestureType.scroll),
          InputAction.zoomIn,
        );
        inputMap.bindSingle(
          const KeyboardSource(LogicalKeyboardKey.minus),
          InputAction.zoomOut,
        );
        inputMap.bindSingle(
          const KeyboardSource(LogicalKeyboardKey.space),
          InputAction.jump,
        );

        final result = validator.validatePreset(CameraPreset.topDown, inputMap);
        expect(result.isValid, isTrue);
        expect(result.missingBindings, isEmpty);
      });
    });

    group('Empty Input Map', () {
      test('detects all missing bindings when input map is empty', () {
        final result = validator.validatePreset(CameraPreset.rts, inputMap);
        expect(result.isValid, isFalse);
        expect(result.missingBindings, isNotEmpty);
        // RTS requires at least cameraPan, zoomIn, zoomOut, attack
        expect(result.missingBindings.length, greaterThanOrEqualTo(4));
      });
    });

    group('Validation Result Properties', () {
      test('ValidationResult has correct properties for valid config', () {
        inputMap.bindSingle(
          const KeyboardSource(LogicalKeyboardKey.keyW),
          InputAction.moveUp,
        );

        const result = CameraPresetValidationResult(isValid: true);

        expect(result.isValid, isTrue);
        expect(result.missingBindings, isEmpty);
        expect(result.errors, isEmpty);
      });

      test('ValidationResult has correct properties for invalid config', () {
        const result = CameraPresetValidationResult(
          isValid: false,
          missingBindings: [InputAction.moveUp, InputAction.moveLeft],
          errors: ['Test error'],
        );

        expect(result.isValid, isFalse);
        expect(result.missingBindings, hasLength(2));
        expect(result.errors, hasLength(1));
      });
    });
  });
}
