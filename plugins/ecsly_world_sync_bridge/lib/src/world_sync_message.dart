import 'package:universal_storage_convergence/universal_storage_convergence.dart';

/// Wire format version of [WorldSyncMessage] envelopes.
const int worldSyncMessageVersion = 1;

/// One message on the world-sync wire (ecsly ADR 0002): a version vector,
/// a batch of kernel ops, or a full kernel snapshot.
///
/// Sealed over exactly the three anti-entropy payloads the kernel exposes.
/// [toJson]/[fromJson] are the wire form — JSON-compatible maps with a
/// `type` discriminator and a `v` format version, so any link that moves
/// JSON can move world sync. Copies made via the JSON round-trip never
/// share mutable state with the sender.
sealed class WorldSyncMessage {
  const WorldSyncMessage();

  /// Discriminator for the concrete message type.
  String get type;

  /// JSON-compatible wire form (includes [type] and
  /// [worldSyncMessageVersion]).
  Map<String, Object?> toJson();

  /// Decodes a message produced by [toJson]. Throws [ArgumentError] on an
  /// unknown discriminator or an unsupported format version — receivers
  /// must never guess.
  static WorldSyncMessage fromJson(final Map<String, Object?> json) {
    final version = (json['v'] as num?)?.toInt();
    if (version != worldSyncMessageVersion) {
      throw ArgumentError.value(
        version,
        'v',
        'Unsupported WorldSyncMessage format version',
      );
    }
    switch (json['type']) {
      case 'vv':
        return VvMessage(
          VersionVector.fromJson(
            Map<String, dynamic>.from(json['vv']! as Map<dynamic, dynamic>),
          ),
        );
      case 'ops':
        return OpsMessage(
          (json['ops']! as List<Object?>)
              .whereType<Map<dynamic, dynamic>>()
              .map((final e) => OpRecord.fromJson(Map<String, dynamic>.from(e)))
              .toList(growable: false),
        );
      case 'snapshot':
        return SnapshotMessage(
          Snapshot.fromJson(
            Map<String, dynamic>.from(
              json['snapshot']! as Map<dynamic, dynamic>,
            ),
          ),
        );
      case final other:
        throw ArgumentError.value(other, 'type', 'Unknown message type');
    }
  }

  /// Decodes [json], requiring it to be a message of concrete type [T].
  static T fromJsonAs<T extends WorldSyncMessage>(
    final Map<String, Object?> json,
  ) {
    final message = fromJson(json);
    if (message is! T) {
      throw ArgumentError.value(
        json['type'],
        'type',
        'Expected $T, got ${message.type}',
      );
    }
    return message;
  }
}

/// Anti-entropy hello: the sender's kernel [VersionVector] watermark.
final class VvMessage extends WorldSyncMessage {
  /// Creates a version-vector hello.
  const VvMessage(this.vv);

  /// Sender's high-water marks of applied ops per actor.
  final VersionVector vv;

  /// Message discriminator: `'vv'`.
  @override
  String get type => 'vv';

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'v': worldSyncMessageVersion,
    'type': type,
    'vv': vv.toJson(),
  };

  @override
  String toString() => 'VvMessage(${vv.toJson()})';
}

/// A delta batch: kernel ops the receiver has not observed.
final class OpsMessage extends WorldSyncMessage {
  /// Creates a delta batch from kernel ops.
  const OpsMessage(this.ops);

  /// Ops to fold, in sender order (the kernel re-orders by HLC anyway).
  final List<OpRecord> ops;

  /// Message discriminator: `'ops'`.
  @override
  String get type => 'ops';

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'v': worldSyncMessageVersion,
    'type': type,
    'ops': ops.map((final op) => op.toJson()).toList(growable: false),
  };

  @override
  String toString() => 'OpsMessage(${ops.length} ops)';
}

/// A full-state kernel snapshot for a replica the log can no longer serve.
final class SnapshotMessage extends WorldSyncMessage {
  /// Creates a full-state message from a kernel snapshot.
  const SnapshotMessage(this.snapshot);

  /// The snapshot to adopt (kernel decides staleness on adoption).
  final Snapshot snapshot;

  /// Message discriminator: `'snapshot'`.
  @override
  String get type => 'snapshot';

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'v': worldSyncMessageVersion,
    'type': type,
    'snapshot': snapshot.toJson(),
  };

  @override
  String toString() => 'SnapshotMessage(${snapshot.state.length} keys)';
}
