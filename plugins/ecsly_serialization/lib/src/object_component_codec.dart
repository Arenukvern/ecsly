import 'package:ecsly/ecsly.dart';

/// Codec for object-tier components stored in [ObjectColumn].
///
/// SoA columns (floats, ints, uint8) serialize generically; heap-object
/// components need a per-type codec registered in
/// [ObjectComponentCodecRegistry].
abstract class ObjectComponentCodec<T extends Component> {
  /// Creates a codec for component type [T].
  const ObjectComponentCodec();

  /// Serialize [component] to a JSON-compatible value.
  Object? toJson(final T component);

  /// Deserialize a component from a JSON-compatible [value].
  T fromJson(final Object? value);
}

/// Registry of codecs for object-tier components.
///
/// Keys are component type names (`runtimeType.toString()` of the component
/// class), matching how snapshots identify components.
class ObjectComponentCodecRegistry {
  final Map<String, ObjectComponentCodec> _codecs = {};

  /// Register a codec for component type [T].
  void register<T extends Component>(final ObjectComponentCodec<T> codec) {
    _codecs[T.toString()] = codec;
  }

  /// Look up a codec by component type name.
  ObjectComponentCodec? lookup(final String typeName) => _codecs[typeName];

  /// Whether any codec is registered for [typeName].
  bool contains(final String typeName) => _codecs.containsKey(typeName);

  /// Remove all codecs.
  void clear() => _codecs.clear();
}
