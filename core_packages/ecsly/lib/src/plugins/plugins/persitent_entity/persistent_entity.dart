import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

export 'persistent_entity_registry.dart';

// ignore: avoid_classes_with_only_static_members
abstract final class _PersistentEntityIdGenerator {
  static final math.Random _rng = math.Random.secure();
  static int _counter = 0;

  static String next() {
    // 16 bytes of randomness + 4 bytes of counter => 20 bytes total.
    // Base64Url without padding: compact and filesystem-safe.
    final bytes = Uint8List(20);

    for (var i = 0; i < 16; i++) {
      bytes[i] = _rng.nextInt(256);
    }

    final c = _counter++;
    bytes[16] = (c >> 24) & 0xFF;
    bytes[17] = (c >> 16) & 0xFF;
    bytes[18] = (c >> 8) & 0xFF;
    bytes[19] = c & 0xFF;

    return base64Url.encode(bytes).replaceAll('=', '');
  }
}

/// {@template persistent_entity}
/// Represents an savable entity in the game world.
/// Safe to save locally.
///
/// Should be paired with [Entity]
/// {@endtemplate}
extension type const PersistentEntity._(String value) {
  factory PersistentEntity.create() =>
      PersistentEntity._(_PersistentEntityIdGenerator.next());
}
