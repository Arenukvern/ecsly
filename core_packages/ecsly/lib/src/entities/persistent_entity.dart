import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

/// Separator between a namespace and its sequence value in namespaced
/// identities. Chosen because no other identity form (`base64Url` random,
/// decimal sequence) can contain it.
const String persistentEntityNamespaceSeparator = ':';

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
/// The durable counterpart of [Entity]: a stable identifier that survives
/// across runtime runs and worlds.
///
/// Do not confuse with [Entity] — that one is a temporary runtime pointer,
/// regenerated at every game start and unsafe to save. A [PersistentEntity]
/// is safe to save, log, and reference across sessions; it travels inside
/// serialization snapshots and is re-attached to freshly spawned entities on
/// restore.
///
/// Two allocation policies exist, chosen per world, never mixed within one
/// world (mixing would break deterministic replay):
///
/// - [PersistentEntity.sequence] — deterministic, a pure function of a
///   counter (and optional namespace). Replay-safe and compact.
/// - [PersistentEntity.create] — 128 bits of secure randomness plus a
///   counter suffix. Globally unique by collision resistance; the
///   merge-safe choice for MMO-style topologies.
///
/// See ADR 0007 (`docs/decisions/0007_persistent_entity_identity.md`) for
/// the identity model and the allocation-policy contract.
/// {@endtemplate}
extension type const PersistentEntity._(String value) {
  /// {@macro persistent_entity}
  factory PersistentEntity.sequence(
    int value, {
    String? namespace,
  }) {
    if (value < 0) {
      throw ArgumentError.value(value, 'value', 'must be non-negative');
    }
    if (namespace != null) {
      if (namespace.isEmpty) {
        throw ArgumentError.value(namespace, 'namespace', 'must not be empty');
      }
      if (namespace.contains(persistentEntityNamespaceSeparator)) {
        throw ArgumentError.value(
          namespace,
          'namespace',
          "must not contain '$persistentEntityNamespaceSeparator'",
        );
      }
      return PersistentEntity._(
        '$namespace$persistentEntityNamespaceSeparator$value',
      );
    }
    return PersistentEntity._('$value');
  }

  /// {@macro persistent_entity}
  factory PersistentEntity.create() =>
      PersistentEntity._(_PersistentEntityIdGenerator.next());

  /// The identity with no entity behind it (counterpart of
  /// `Entity.nullEntity`).
  static const PersistentEntity zero = PersistentEntity._('');

  /// Whether this is the null identity.
  bool get isZero => value.isEmpty;

  /// The sequence number when this is an un-namespaced sequence identity,
  /// null otherwise (random and namespaced identities do not parse).
  int? get sequenceValue => int.tryParse(value);

  /// The namespace when this is a namespaced sequence identity, null
  /// otherwise.
  String? get namespace {
    final separator = value.indexOf(persistentEntityNamespaceSeparator);
    if (separator <= 0) return null;
    return value.substring(0, separator);
  }

  /// Serializes to a JSON-compatible value (the raw String).
  String toJson() => value;

  /// Deserializes from a JSON-compatible value.
  ///
  /// Accepts ints for pre-v4 payload compatibility (decimal normalization).
  static PersistentEntity fromJson(Object? json) => switch (json) {
    final String value => PersistentEntity._(value),
    final int value => PersistentEntity._('$value'),
    _ => throw ArgumentError.value(json, 'json', 'not a persistent identity'),
  };
}
