/// A single chunk of work produced by [partition] and consumed by [executeChunk].
class ScheduleJobChunk<T extends Object> {
  /// Creates a chunk with a stable [chunkKey] and its [payload].
  const ScheduleJobChunk({required this.chunkKey, required this.payload});

  /// Stable ordering key. Results are merged in ascending [chunkKey] order.
  final int chunkKey;

  /// The work unit to execute.
  final T payload;
}

/// The result of executing a single [ScheduleJobChunk].
class ScheduleJobChunkResult<T extends Object> {
  /// Creates a result pairing the originating [chunkKey] with its [value].
  const ScheduleJobChunkResult({required this.chunkKey, required this.value});

  /// Matches the [ScheduleJobChunk.chunkKey] this result came from.
  final int chunkKey;

  /// The computed value for this chunk.
  final T value;
}

/// A completed frame's worth of chunk results, tagged for the result queue.
class ScheduleJobResultEnvelope<T extends Object> {
  /// Creates an envelope associating [results] with a [jobKey] and [frameId].
  const ScheduleJobResultEnvelope({
    required this.jobKey,
    required this.frameId,
    required this.results,
  });

  /// The [ScheduleParallelTaskSystem.jobKey] that produced these results.
  final String jobKey;

  /// The frame id these results belong to.
  final int frameId;

  /// Ordered chunk results for this frame.
  final List<ScheduleJobChunkResult<T>> results;
}
