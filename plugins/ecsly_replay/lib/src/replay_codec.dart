// ignore_for_file: prefer_final_parameters

import 'dart:convert';

import 'checkpoint_store.dart';
import 'replay_log.dart';

/// JSON codec for bundled replay session state.
class ReplaySessionCodec {
  /// Encodes [log] and [checkpoints] to a JSON string.
  static String encode({
    required final ReplayLog log,
    required final CheckpointStore checkpoints,
  }) =>
      jsonEncode(<String, Object?>{
        'log': log.toJson(),
        'checkpoints': checkpoints.toJson(),
      });

  /// Decodes a session from JSON.
  static (ReplayLog log, CheckpointStore checkpoints) decode(final String json) {
    final root = jsonDecode(json) as Map<String, Object?>;
    final log = ReplayLog.fromJson(
      (root['log'] as Map<String, Object?>?) ?? const {},
    );
    final checkpoints = CheckpointStore.fromJson(
      (root['checkpoints'] as Map<String, Object?>?) ?? const {},
    );
    return (log, checkpoints);
  }
}
