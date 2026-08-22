import 'dart:convert';

import 'world_snapshot.dart';

/// Marker keys for non-finite doubles, which JSON cannot represent.
const String _infinityKey = '__ecsly_inf__';
const String _negInfinityKey = '__ecsly_neg_inf__';
const String _nanKey = '__ecsly_nan__';

Object? _encodeValue(final Object? value) {
  if (value is double) {
    if (value.isNaN) return _nanKey;
    if (value == double.infinity) return _infinityKey;
    if (value == -double.infinity) return _negInfinityKey;
    return value;
  }
  if (value is Map<String, Object?>) {
    return value.map((final k, final v) => MapEntry(k, _encodeValue(v)));
  }
  if (value is Map) {
    return value.map(
      (final k, final v) => MapEntry(k.toString(), _encodeValue(v)),
    );
  }
  if (value is List) {
    return value.map(_encodeValue).toList();
  }
  return value;
}

Object? _decodeValue(final Object? value) {
  if (value == _nanKey) return double.nan;
  if (value == _infinityKey) return double.infinity;
  if (value == _negInfinityKey) {
    return -double.infinity;
  }
  if (value is Map<String, Object?>) {
    return value.map((final k, final v) => MapEntry(k, _decodeValue(v)));
  }
  if (value is Map) {
    return value.map(
      (final k, final v) => MapEntry(k.toString(), _decodeValue(v)),
    );
  }
  if (value is List) {
    return value.map(_decodeValue).toList();
  }
  return value;
}

/// Encode a [WorldSnapshot] to a compact JSON string.
///
/// Non-finite doubles (`Infinity`, `-Infinity`, `NaN`) are encoded as marker
/// strings and restored on decode.
String encodeWorldSnapshot(final WorldSnapshot snapshot) =>
    jsonEncode(_encodeValue(snapshot.toJson()));

/// Decode a [WorldSnapshot] from a JSON string produced by
/// [encodeWorldSnapshot].
WorldSnapshot decodeWorldSnapshot(final String json) {
  final decoded = jsonDecode(json);
  if (decoded is! Map<String, Object?>) {
    throw FormatException('Expected a JSON object, got ${decoded.runtimeType}');
  }
  return WorldSnapshot.fromJson(
    // ignore: cast_nullable_to_non_nullable
    _decodeValue(decoded) as Map<String, Object?>,
  );
}
