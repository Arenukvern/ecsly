import 'package:ecsly/ecsly.dart';

import 'schedule_job_types.dart';

/// Holds completed job results and tracks in-flight work for best-effort jobs.
///
/// The [ScheduleExecutionPolicy] enum and [ScheduleExecutionPolicyResource]
/// are owned by the `ecsly` core package and re-exported through it; this file
/// only adds the result queue used by job systems.
class ScheduleJobResultQueueResource extends Resource {
  /// {@macro schedule_job_result_queue_resource}
  ScheduleJobResultQueueResource();

  final List<ScheduleJobResultEnvelope<Object>> _completed =
      <ScheduleJobResultEnvelope<Object>>[];
  final Set<String> _inFlight = <String>{};

  /// Marks a job's work for a frame as in-flight.
  bool beginInFlight({
    required final String jobKey,
    required final int frameId,
  }) => _inFlight.add(_composeInFlightKey(jobKey, frameId));

  /// Cancels the in-flight marker for a frame (e.g. on error).
  void cancelInFlight({
    required final String jobKey,
    required final int frameId,
  }) {
    _inFlight.remove(_composeInFlightKey(jobKey, frameId));
  }

  /// Records a completed frame's results and clears its in-flight marker.
  void completeInFlight<T extends Object>(
    final ScheduleJobResultEnvelope<T> envelope,
  ) {
    _inFlight.remove(_composeInFlightKey(envelope.jobKey, envelope.frameId));
    _completed.add(_eraseEnvelope(envelope));
  }

  /// Drops results and in-flight markers older than [minFrameId].
  ///
  /// If [jobKey] is provided, only that job's entries are dropped.
  int dropStaleResults({required final int minFrameId, final String? jobKey}) {
    final before = _completed.length;
    _completed.removeWhere(
      (final envelope) =>
          envelope.frameId < minFrameId &&
          (jobKey == null || envelope.jobKey == jobKey),
    );
    if (jobKey == null) {
      _inFlight.removeWhere((final key) => _decodeFrameId(key) < minFrameId);
    } else {
      _inFlight.removeWhere(
        (final key) =>
            key.startsWith('$jobKey#') && _decodeFrameId(key) < minFrameId,
      );
    }
    return before - _completed.length;
  }

  /// Whether any work for [jobKey] is currently in flight.
  bool hasInFlightJob(final String jobKey) =>
      _inFlight.any((final key) => key.startsWith('$jobKey#'));

  /// Returns and removes the completed results for a frame.
  List<ScheduleJobChunkResult<T>> takeForFrame<T extends Object>({
    required final String jobKey,
    required final int frameId,
  }) {
    final matches = <ScheduleJobChunkResult<T>>[];
    _completed.removeWhere((final envelope) {
      if (envelope.jobKey != jobKey || envelope.frameId != frameId) {
        return false;
      }
      for (final result in envelope.results) {
        matches.add(
          ScheduleJobChunkResult<T>(
            chunkKey: result.chunkKey,
            value: result.value as T,
          ),
        );
      }
      return true;
    });
    matches.sort((final a, final b) => a.chunkKey.compareTo(b.chunkKey));
    return matches;
  }

  String _composeInFlightKey(final String jobKey, final int frameId) =>
      '$jobKey#$frameId';

  int _decodeFrameId(final String key) {
    final separator = key.lastIndexOf('#');
    if (separator < 0 || separator + 1 >= key.length) return 0;
    return int.tryParse(key.substring(separator + 1)) ?? 0;
  }

  ScheduleJobResultEnvelope<Object> _eraseEnvelope<T extends Object>(
    final ScheduleJobResultEnvelope<T> envelope,
  ) => ScheduleJobResultEnvelope<Object>(
    jobKey: envelope.jobKey,
    frameId: envelope.frameId,
    results: envelope.results
        .map(
          (final result) => ScheduleJobChunkResult<Object>(
            chunkKey: result.chunkKey,
            value: result.value,
          ),
        )
        .toList(growable: false),
  );
}
