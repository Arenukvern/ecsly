import 'package:ecsly/ecsly.dart';

import 'entity_refs.dart';

/// Codec for object-tier components stored in [ObjectColumn].
///
/// SoA columns (floats, ints, uint8) serialize generically; heap-object
/// components need a per-type codec registered in
/// [ObjectComponentCodecRegistry].
///
/// Entity references inside payloads are **first-class** (ADR 0007 §4):
/// capture receives an [EntityRefEncoder] to rewrite runtime `Entity`
/// handles into stable identities; restore receives an
/// [EntityRefResolver] to resolve them back — the restore mapping never
/// escapes `restoreWorldSnapshot`, and there is no second rehydration pass.
abstract class ObjectComponentCodec<T extends Component> {
  /// Creates a codec for component type [T].
  const ObjectComponentCodec();

  /// Serialize [component] to a JSON-compatible value, rewriting entity
  /// references through [refs].
  Object? toJson(T component, EntityRefEncoder refs);

  /// Deserialize a component from a JSON-compatible [value], resolving
  /// entity references through [refs].
  T fromJson(Object? value, EntityRefResolver refs);
}

/// Registry of codecs for object-tier components.
///
/// Keys are component identities: the stable name registered for the
/// component when present, falling back to the component type name — the
/// same key snapshots use for components.
class ObjectComponentCodecRegistry {
  final Map<String, ObjectComponentCodec<Component>> _codecs = {};

  /// Register a codec for component type [T]. [name] pins the snapshot
  /// identity; when omitted the type name is used.
  void register<T extends Component>(
    ObjectComponentCodec<T> codec, {
    String? name,
  }) {
    _codecs[name ?? T.toString()] = codec as ObjectComponentCodec<Component>;
  }

  /// Look up a codec by component identity.
  ObjectComponentCodec? lookup(String name) => _codecs[name];

  /// Whether any codec is registered for [name].
  bool contains(String name) => _codecs.containsKey(name);

  /// Remove all codecs.
  void clear() => _codecs.clear();
}
