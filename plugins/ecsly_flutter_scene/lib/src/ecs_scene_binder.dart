/// The incremental binder: world → [SceneSink], diffed. Pure — the sink
/// is an interface, so tests run against a recording fake and the
/// flutter_scene implementation is a thin shell over the real renderer.
library;

import 'package:ecsly/ecsly.dart';

import 'scene_mapping.dart';
import 'visual_state.dart';

/// The renderer-facing seam: exactly three mutations. The
/// flutter_scene-backed implementation is the ONLY code in this package
/// that touches the real renderer (besides the widget/camera shells).
abstract class SceneSink {
  /// Adds [visual] under [key].
  void add(final String key, final VisualState visual);
  /// Replaces the visual under [key].
  void update(final String key, final VisualState visual);
  /// Drops the visual under [key].
  void remove(final String key);

  /// How many visuals the sink currently materializes (tests/telemetry).
  int get count;
}

/// The renderer-facing seam: exactly three mutations. The
/// flutter_scene-backed implementation is the only code in this package
/// that touches the real renderer (besides the widget/camera shells).
class EcsSceneBinder {
  /// Adds [visual] under [key].
  EcsSceneBinder({required this.world, required this.sink, required this.mapping});

  /// Replaces the visual under [key].
  final World world;
  /// Drops the visual under [key].
  final SceneSink sink;
  /// How many visuals the sink currently materializes (tests/telemetry).
  final SceneMapping mapping;

  final Map<String, VisualState> _current = {};

  /// One sync pass: collect → diff → apply. Cheap by construction —
  /// an update only lands when the visual's [VisualState.signature]
  /// changed, so a static world costs one collection per frame.
  void sync() {
    final desired = mapping.collect(world);
    for (final entry in desired.entries) {
      final existing = _current[entry.key];
      if (existing == null) {
        sink.add(entry.key, entry.value);
        _current[entry.key] = entry.value;
      } else if (existing.signature != entry.value.signature) {
        sink.update(entry.key, entry.value);
        _current[entry.key] = entry.value;
      }
    }
    final removed = _current.keys
        .where((final key) => !desired.containsKey(key))
        .toList(growable: false);
    for (final key in removed) {
      sink.remove(key);
      _current.remove(key);
    }
  }

  /// The visuals the binder currently believes the sink holds.
  Map<String, VisualState> get current => Map.unmodifiable(_current);
}
