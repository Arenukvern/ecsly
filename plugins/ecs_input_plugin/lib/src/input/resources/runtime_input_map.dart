import 'package:ecsly/ecsly.dart';
import 'package:flutter/services.dart';

import '../input_action.dart';
import '../utils/gesture_types.dart';
import 'input_source.dart';

/// Result of loading RuntimeInputMap from JSON.
class LoadResult {
  const LoadResult(this.map, this.errors);

  /// The loaded input map (may be partially loaded on errors).
  final RuntimeInputMap map;

  /// List of errors encountered during loading.
  final List<String> errors;

  /// Whether any errors occurred during loading.
  bool get hasErrors => errors.isNotEmpty;
}

/// Runtime-rebindable input mapping resource.
class RuntimeInputMap extends Resource {
  /// Bindings: InputSource -> Set<InputAction>
  final Map<String, MapEntry<InputSource, Set<InputAction>>> _bindings = {};

  /// Reverse index: InputAction -> Set<InputSource>
  final Map<InputAction, Set<InputSource>> _actionToSources = {};

  /// Backward-compatible wrapper.
  static LoadResult fromJsonWithErrors(Map<String, dynamic> json) =>
      runtimeInputMapFromJsonWithErrors(json);
}

extension RuntimeInputMapOps on RuntimeInputMap {
  void bind(InputSource source, Set<InputAction> actions) =>
      runtimeInputMapBind(this, source, actions);

  void bindSingle(InputSource source, InputAction action) =>
      runtimeInputMapBindSingle(this, source, action);

  void clearAction(InputAction action) =>
      runtimeInputMapClearAction(this, action);

  List<InputSource> findConflicts() => runtimeInputMapFindConflicts(this);

  Set<InputAction> getActions(InputSource source) =>
      runtimeInputMapGetActions(this, source);

  Iterable<KeyboardSource> getMatchingKeyboardSources(
    LogicalKeyboardKey key,
    Set<LogicalKeyboardKey> pressed,
  ) => runtimeInputMapGetMatchingKeyboardSources(this, key, pressed);

  Set<InputSource> getSources(InputAction action) =>
      runtimeInputMapGetSources(this, action);

  bool hasConflict(InputSource source) =>
      runtimeInputMapHasConflict(this, source);

  void initializeDefaults() => runtimeInputMapInitializeDefaults(this);

  Map<String, dynamic> toJson() => runtimeInputMapToJson(this);

  void unbind(InputSource source) => runtimeInputMapUnbind(this, source);
}

void runtimeInputMapBind(
  RuntimeInputMap map,
  InputSource source,
  Set<InputAction> actions,
) {
  runtimeInputMapUnbind(map, source);

  map._bindings[source.uniqueId] = MapEntry(source, actions);
  for (final action in actions) {
    map._actionToSources.putIfAbsent(action, () => {}).add(source);
  }
}

void runtimeInputMapBindSingle(
  RuntimeInputMap map,
  InputSource source,
  InputAction action,
) {
  runtimeInputMapBind(map, source, {action});
}

void runtimeInputMapClearAction(
  RuntimeInputMap map,
  InputAction action,
) {
  final sources = map._actionToSources.remove(action);
  if (sources == null) return;

  for (final source in sources) {
    final entry = map._bindings[source.uniqueId];
    if (entry == null) continue;

    entry.value.remove(action);
    if (entry.value.isEmpty) {
      map._bindings.remove(source.uniqueId);
    }
  }
}

List<InputSource> runtimeInputMapFindConflicts(RuntimeInputMap map) {
  final conflicts = <InputSource>[];
  for (final entry in map._bindings.values) {
    if (entry.value.length > 1) {
      conflicts.add(entry.key);
    }
  }
  return conflicts;
}

Set<InputAction> runtimeInputMapGetActions(
  RuntimeInputMap map,
  InputSource source,
) => map._bindings[source.uniqueId]?.value ?? {};

Iterable<KeyboardSource> runtimeInputMapGetMatchingKeyboardSources(
  RuntimeInputMap map,
  LogicalKeyboardKey key,
  Set<LogicalKeyboardKey> pressed,
) => map._bindings.values
    .where((entry) => entry.key is KeyboardSource)
    .map((entry) => entry.key as KeyboardSource)
    .where((source) => source.matches(key, pressed));

Set<InputSource> runtimeInputMapGetSources(
  RuntimeInputMap map,
  InputAction action,
) => map._actionToSources[action] ?? {};

bool runtimeInputMapHasConflict(
  RuntimeInputMap map,
  InputSource source,
) {
  final entry = map._bindings[source.uniqueId];
  return entry != null && entry.value.length > 1;
}

void runtimeInputMapInitializeDefaults(RuntimeInputMap map) {
  runtimeInputMapBindSingle(
    map,
    const KeyboardSource(LogicalKeyboardKey.keyW),
    InputAction.moveUp,
  );
  runtimeInputMapBindSingle(
    map,
    const KeyboardSource(LogicalKeyboardKey.keyA),
    InputAction.moveLeft,
  );
  runtimeInputMapBindSingle(
    map,
    const KeyboardSource(LogicalKeyboardKey.keyS),
    InputAction.moveDown,
  );
  runtimeInputMapBindSingle(
    map,
    const KeyboardSource(LogicalKeyboardKey.keyD),
    InputAction.moveRight,
  );
  runtimeInputMapBindSingle(
    map,
    const KeyboardSource(LogicalKeyboardKey.arrowUp),
    InputAction.moveUp,
  );
  runtimeInputMapBindSingle(
    map,
    const KeyboardSource(LogicalKeyboardKey.arrowLeft),
    InputAction.moveLeft,
  );
  runtimeInputMapBindSingle(
    map,
    const KeyboardSource(LogicalKeyboardKey.arrowDown),
    InputAction.moveDown,
  );
  runtimeInputMapBindSingle(
    map,
    const KeyboardSource(LogicalKeyboardKey.arrowRight),
    InputAction.moveRight,
  );

  runtimeInputMapBindSingle(
    map,
    const KeyboardSource(LogicalKeyboardKey.equal),
    InputAction.zoomIn,
  );
  runtimeInputMapBindSingle(
    map,
    const KeyboardSource(LogicalKeyboardKey.minus),
    InputAction.zoomOut,
  );
  runtimeInputMapBindSingle(
    map,
    const KeyboardSource(LogicalKeyboardKey.keyR),
    InputAction.cameraReset,
  );

  runtimeInputMapBindSingle(
    map,
    const GestureSource(GestureType.drag),
    InputAction.cameraPan,
  );
  runtimeInputMapBindSingle(
    map,
    const GestureSource(GestureType.scroll),
    InputAction.zoomIn,
  );

  runtimeInputMapBindSingle(
    map,
    const KeyboardSource(LogicalKeyboardKey.space),
    InputAction.jump,
  );
  runtimeInputMapBindSingle(
    map,
    const KeyboardSource(LogicalKeyboardKey.keyE),
    InputAction.interact,
  );
  runtimeInputMapBindSingle(
    map,
    const KeyboardSource(LogicalKeyboardKey.keyX),
    InputAction.attack,
  );
  runtimeInputMapBindSingle(
    map,
    const KeyboardSource(LogicalKeyboardKey.keyQ),
    InputAction.special,
  );
  runtimeInputMapBindSingle(
    map,
    const KeyboardSource(LogicalKeyboardKey.escape),
    InputAction.pause,
  );
}

Map<String, dynamic> runtimeInputMapToJson(RuntimeInputMap map) => {
  'bindings': map._bindings.entries
      .map(
        (e) => {
          'source': e.value.key.uniqueId,
          'actions': e.value.value.map((a) => a.name).toList(),
        },
      )
      .toList(),
};

void runtimeInputMapUnbind(
  RuntimeInputMap map,
  InputSource source,
) {
  final entry = map._bindings.remove(source.uniqueId);
  if (entry == null) return;

  for (final action in entry.value) {
    map._actionToSources[action]?.remove(source);
  }
}

LoadResult runtimeInputMapFromJsonWithErrors(Map<String, dynamic> json) {
  final map = RuntimeInputMap();
  final errors = <String>[];

  try {
    final bindingsRaw = json['bindings'];
    if (bindingsRaw == null) {
      return LoadResult(map, errors);
    }
    if (bindingsRaw is! List<dynamic>) {
      throw ArgumentError('"bindings" must be a list');
    }

    final bindings = bindingsRaw;
    for (var i = 0; i < bindings.length; i++) {
      try {
        final bindingJson = bindings[i];
        if (bindingJson is! Map) {
          throw ArgumentError('binding must be an object');
        }
        final binding = Map<String, dynamic>.from(bindingJson);
        final sourceRaw = binding['source'];
        final actionNamesRaw = binding['actions'];

        if (sourceRaw == null) {
          errors.add('Binding $i: missing "source" field');
          continue;
        }

        final source = _runtimeInputMapParseSource(sourceRaw);
        if (source == null) {
          errors.add('Binding $i: unknown source type "$sourceRaw"');
          continue;
        }

        final actions = <InputAction>[];
        var hasActionErrors = false;
        final actionNames = actionNamesRaw is List<dynamic>
            ? actionNamesRaw
            : actionNamesRaw == null
            ? <dynamic>[]
            : (() {
                hasActionErrors = true;
                errors.add(
                  'Binding $i, action 0: expected string, got ${actionNamesRaw.runtimeType}',
                );
                return <dynamic>[];
              })();
        for (var j = 0; j < actionNames.length; j++) {
          final name = actionNames[j];
          if (name is! String) {
            hasActionErrors = true;
            errors.add(
              'Binding $i, action $j: expected string, got ${name.runtimeType}',
            );
            continue;
          }

          try {
            final action = InputAction.values.firstWhere(
              (action) => action.name == name,
              orElse: () => throw ArgumentError('Unknown action: $name'),
            );
            actions.add(action);
          } catch (_) {
            hasActionErrors = true;
            errors.add('Binding $i, action $j: unknown action "$name"');
          }
        }

        if (actions.isNotEmpty) {
          runtimeInputMapBind(map, source, actions.toSet());
        } else if (!hasActionErrors) {
          errors.add('Binding $i: no valid actions found');
        }
      } catch (e) {
        errors.add('Binding $i: invalid binding format - $e');
      }
    }
  } catch (e) {
    errors.add('Invalid JSON structure: $e');
  }

  return LoadResult(map, errors);
}

InputSource? _runtimeInputMapParseSource(Object sourceRaw) {
  if (sourceRaw is String) {
    return _runtimeInputMapParseSourceId(sourceRaw);
  }
  if (sourceRaw is Map) {
    try {
      final sourceJson = Map<String, dynamic>.from(sourceRaw);
      return InputSource.fromJson(sourceJson);
    } catch (_) {
      return null;
    }
  }
  return null;
}

InputSource? _runtimeInputMapParseSourceId(String sourceId) {
  final parsed = InputSource.fromUniqueId(sourceId);
  if (parsed != null) return parsed;

  // Backward compatibility for legacy ASCII-like key IDs (e.g. kb:87 for W).
  if (!sourceId.startsWith('kb:')) return null;

  final parts = sourceId.substring(3).split('+');
  final keyCode = int.tryParse(parts.first);
  if (keyCode == null) return null;

  final key = _runtimeInputMapFindLegacyKeyboardKey(keyCode);
  if (key == null) return null;

  final modifiers = _runtimeInputMapParseModifiers(parts.skip(1));
  return KeyboardSource(key, modifiers: modifiers);
}

LogicalKeyboardKey? _runtimeInputMapFindLegacyKeyboardKey(int keyCode) {
  if (keyCode < 0 || keyCode > 0xFFFF) return null;

  if (keyCode <= 255) {
    final upperLabel = String.fromCharCode(keyCode).toUpperCase();
    for (final key in LogicalKeyboardKey.knownLogicalKeys) {
      if (key.keyLabel.toUpperCase() == upperLabel) {
        return key;
      }
    }

    if (keyCode == 32) return LogicalKeyboardKey.space;
  }

  // Keep unknown but bounded key IDs round-trippable for custom bindings.
  return LogicalKeyboardKey(keyCode);
}

KeyModifiers? _runtimeInputMapParseModifiers(
  Iterable<String> modifierNames,
) {
  final names = modifierNames.toSet();
  if (names.isEmpty) return null;

  return KeyModifiers(
    ctrl: names.contains('ctrl'),
    shift: names.contains('shift'),
    alt: names.contains('alt'),
    meta: names.contains('meta'),
  );
}
