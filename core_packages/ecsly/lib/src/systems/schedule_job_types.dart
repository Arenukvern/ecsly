class ScheduleJobChunk<T extends Object> {
  const ScheduleJobChunk({required this.chunkKey, required this.payload});

  final int chunkKey;
  final T payload;
}

class ScheduleJobChunkResult<T extends Object> {
  const ScheduleJobChunkResult({required this.chunkKey, required this.value});

  final int chunkKey;
  final T value;
}

class ScheduleJobResultEnvelope<T extends Object> {
  const ScheduleJobResultEnvelope({
    required this.jobKey,
    required this.frameId,
    required this.results,
  });

  final String jobKey;
  final int frameId;
  final List<ScheduleJobChunkResult<T>> results;
}
