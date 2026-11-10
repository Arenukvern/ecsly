import 'package:flutter/services.dart';

import '../utils/gesture_types.dart';

/// Gesture type source (drag, pinch, scroll, etc.).
class GestureSource extends InputSource {
  const GestureSource(this.type);

  /// Deserialize from JSON.
  factory GestureSource.fromJson(final Map<String, dynamic> json) {
    final typeName = json['type'] as String;
    final type = GestureType.values.firstWhere(
      (final t) => t.name == typeName,
      orElse: () => throw ArgumentError('Unknown gesture type: $typeName'),
    );
    return GestureSource(type);
  }

  final GestureType type;

  @override
  String get uniqueId => 'gesture:${type.name}';

  /// Serialize to JSON.
  @override
  Map<String, dynamic> toJson() => {
    'type': 'gesture',
    'data': {'type': type.name},
  };
}

/// Sealed class hierarchy representing different input sources.
sealed class InputSource {
  const InputSource();

  /// Deserialize from JSON.
  factory InputSource.fromJson(final Map<String, dynamic> json) {
    final type = json['type'] as String;
    final data = json['data'] as Map<String, dynamic>;

    return switch (type) {
      'keyboard' => KeyboardSource.fromJson(data),
      'mouse' => MouseButtonSource.fromJson(data),
      'gesture' => GestureSource.fromJson(data),
      _ => throw ArgumentError('Unknown input source type: $type'),
    };
  }

  /// Unique identifier for serialization/deserialization.
  String get uniqueId;

  /// Serialize to JSON.
  Map<String, dynamic> toJson();

  /// Reconstruct InputSource from its unique ID string.
  ///
  /// This is used for deserialization when only the uniqueId is stored.
  static InputSource? fromUniqueId(final String uniqueId) {
    // Parse keyboard sources: kb:123 or kb:123+ctrl+shift
    if (uniqueId.startsWith('kb:')) {
      final parts = uniqueId.substring(3).split('+');
      final keyId = int.tryParse(parts[0]);
      if (keyId == null) return null;

      final key = LogicalKeyboardKey.findKeyByKeyId(keyId);
      if (key == null) return null;

      KeyModifiers? modifiers;
      if (parts.length > 1) {
        final mods = <String>[];
        for (var i = 1; i < parts.length; i++) {
          mods.add(parts[i]);
        }
        modifiers = KeyModifiers(
          ctrl: mods.contains('ctrl'),
          shift: mods.contains('shift'),
          alt: mods.contains('alt'),
          meta: mods.contains('meta'),
        );
      }

      return KeyboardSource(key, modifiers: modifiers);
    }

    // Parse mouse sources: mouse:0, mouse:1+ctrl, etc.
    if (uniqueId.startsWith('mouse:')) {
      final parts = uniqueId.substring(6).split('+');
      final button = int.tryParse(parts[0]);
      if (button == null) return null;

      KeyModifiers? modifiers;
      if (parts.length > 1) {
        final mods = <String>[];
        for (var i = 1; i < parts.length; i++) {
          mods.add(parts[i]);
        }
        modifiers = KeyModifiers(
          ctrl: mods.contains('ctrl'),
          shift: mods.contains('shift'),
          alt: mods.contains('alt'),
          meta: mods.contains('meta'),
        );
      }

      return MouseButtonSource(button, modifiers: modifiers);
    }

    // Parse gesture sources: gesture:drag, gesture:scroll, etc.
    if (uniqueId.startsWith('gesture:')) {
      final typeName = uniqueId.substring(8);
      try {
        final type = GestureType.values.firstWhere(
          (final t) => t.name == typeName,
        );
        return GestureSource(type);
      } catch (e) {
        return null; // Invalid gesture type
      }
    }

    return null; // Unknown source type
  }
}

/// Keyboard key source with optional modifiers.
class KeyboardSource extends InputSource {
  const KeyboardSource(this.key, {this.modifiers});

  /// Deserialize from JSON.
  factory KeyboardSource.fromJson(final Map<String, dynamic> json) {
    final keyId = json['keyId'] as int;
    final key =
        LogicalKeyboardKey.findKeyByKeyId(keyId) ??
        (throw ArgumentError('Unknown key ID: $keyId'));

    KeyModifiers? modifiers;
    if (json.containsKey('modifiers')) {
      final mods = json['modifiers'] as Map<String, dynamic>;
      modifiers = KeyModifiers(
        ctrl: mods['ctrl'] as bool? ?? false,
        shift: mods['shift'] as bool? ?? false,
        alt: mods['alt'] as bool? ?? false,
        meta: mods['meta'] as bool? ?? false,
      );
    }

    return KeyboardSource(key, modifiers: modifiers);
  }

  final LogicalKeyboardKey key;
  final KeyModifiers? modifiers;

  @override
  String get uniqueId => 'kb:${key.keyId}${modifiers?.suffix ?? ''}';

  bool matches(
    final LogicalKeyboardKey pressedKey,
    final Set<LogicalKeyboardKey> pressed,
  ) {
    if (pressedKey != key) return false;
    return modifiers?.matches(pressed) ?? true;
  }

  /// Serialize to JSON.
  @override
  Map<String, dynamic> toJson() => {
    'type': 'keyboard',
    'data': {
      'keyId': key.keyId,
      if (modifiers != null)
        'modifiers': {
          'ctrl': modifiers!.ctrl,
          'shift': modifiers!.shift,
          'alt': modifiers!.alt,
          'meta': modifiers!.meta,
        },
    },
  };
}

/// Key modifier state (Ctrl, Shift, Alt, Meta).
class KeyModifiers {
  const KeyModifiers({
    this.ctrl = false,
    this.shift = false,
    this.alt = false,
    this.meta = false,
  });

  final bool ctrl;
  final bool shift;
  final bool alt;
  final bool meta;

  String get suffix =>
      '${ctrl ? '+ctrl' : ''}${shift ? '+shift' : ''}${alt ? '+alt' : ''}${meta ? '+meta' : ''}';

  bool matches(final Set<LogicalKeyboardKey> pressed) {
    // Check if required modifiers match actual pressed state
    final ctrlPressed =
        pressed.contains(LogicalKeyboardKey.controlLeft) ||
        pressed.contains(LogicalKeyboardKey.controlRight);
    final shiftPressed =
        pressed.contains(LogicalKeyboardKey.shiftLeft) ||
        pressed.contains(LogicalKeyboardKey.shiftRight);
    final altPressed =
        pressed.contains(LogicalKeyboardKey.altLeft) ||
        pressed.contains(LogicalKeyboardKey.altRight);
    final metaPressed =
        pressed.contains(LogicalKeyboardKey.metaLeft) ||
        pressed.contains(LogicalKeyboardKey.metaRight);

    // For each modifier: if required, must be pressed; if not required, must not be pressed
    return (ctrl == ctrlPressed) &&
        (shift == shiftPressed) &&
        (alt == altPressed) &&
        (meta == metaPressed);
  }
}

/// Mouse button source with optional modifiers.
class MouseButtonSource extends InputSource {
  const MouseButtonSource(this.button, {this.modifiers});

  /// Deserialize from JSON.
  factory MouseButtonSource.fromJson(final Map<String, dynamic> json) {
    final button = json['button'] as int;

    KeyModifiers? modifiers;
    if (json.containsKey('modifiers')) {
      final mods = json['modifiers'] as Map<String, dynamic>;
      modifiers = KeyModifiers(
        ctrl: mods['ctrl'] as bool? ?? false,
        shift: mods['shift'] as bool? ?? false,
        alt: mods['alt'] as bool? ?? false,
        meta: mods['meta'] as bool? ?? false,
      );
    }

    return MouseButtonSource(button, modifiers: modifiers);
  }

  final int button; // 0=left, 1=right, 2=middle
  final KeyModifiers? modifiers;

  @override
  String get uniqueId => 'mouse:$button${modifiers?.suffix ?? ''}';

  /// Serialize to JSON.
  @override
  Map<String, dynamic> toJson() => {
    'type': 'mouse',
    'data': {
      'button': button,
      if (modifiers != null)
        'modifiers': {
          'ctrl': modifiers!.ctrl,
          'shift': modifiers!.shift,
          'alt': modifiers!.alt,
          'meta': modifiers!.meta,
        },
    },
  };
}
