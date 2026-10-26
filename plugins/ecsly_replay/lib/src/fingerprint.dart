// ignore_for_file: prefer_final_parameters

import 'dart:convert';

/// Fingerprints bundled into [ReplayLogHeader] for drift detection.
class ReplayFingerprints {
  /// Creates fingerprints.
  const ReplayFingerprints({
    required this.buildFingerprint,
    required this.schemaFingerprint,
  });

  /// Toolchain / package build identity (caller-defined, e.g. git + sdk).
  final String buildFingerprint;

  /// App schema identity (pairs with [WorldSnapshot.schemaVersion]).
  final String schemaFingerprint;

  Map<String, Object?> toJson() => <String, Object?>{
    'buildFingerprint': buildFingerprint,
    'schemaFingerprint': schemaFingerprint,
  };

  // ignore: prefer_constructors_over_static_methods
  static ReplayFingerprints fromJson(final Map<String, Object?> json) =>
      ReplayFingerprints(
        buildFingerprint: json['buildFingerprint'] as String? ?? '',
        schemaFingerprint: json['schemaFingerprint'] as String? ?? '',
      );
}

/// Canonical JSON string for stable equality checks.
String canonicalJson(final Object? value) => jsonEncode(value);
