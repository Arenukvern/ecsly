import '../../systems/schedule_job_types.dart';
import '../../world/world.dart';
import '../resource.dart';

/// Delta time resource for frame-rate independent movement
class DeltaTimeResource extends Resource {
  DeltaTimeResource(this.deltaTime);

  double deltaTime;
}

/// Resource for tracking level state and transitions.
///
/// Q: Why is this a Resource instead of a Component?
/// A: Level state is global game state, not entity-specific data.
///    Resources provide O(1) access without entity lookups.
class LevelStateResource extends Resource {
  LevelStateResource({
    required this.currentLevel,
    this.isTransitioning = false,
    this.nextLevel,
  });

  final String currentLevel; // e.g., "menu", "level1", "level2"
  final bool isTransitioning;
  final String? nextLevel;

  LevelStateResource completeTransition() =>
      LevelStateResource(currentLevel: nextLevel!);

  LevelStateResource transitionTo(final String levelId) => LevelStateResource(
    currentLevel: currentLevel,
    isTransitioning: true,
    nextLevel: levelId,
  );
}

/// Deterministic simulation time source for schedule triggers.
///
/// Systems or loop drivers should update this once per simulation step.
/// Triggers read this resource instead of wall clock time.
class ScheduleTimeResource extends Resource {
  ScheduleTimeResource({required this.deltaSeconds, this.elapsedSeconds = 0});

  /// Step delta used for this simulation frame.
  double deltaSeconds;

  /// Total elapsed simulation time.
  double elapsedSeconds;
}

/// Controls simulation execution for debuggers/inspectors.
///
/// Typical usage:
/// - `paused=true` stops schedule execution in the game loop
/// - increment `stepFrames` to run N frames while paused
class SimulationControlResource extends Resource {
  SimulationControlResource({this.paused = false, this.stepFrames = 0});

  bool paused;
  int stepFrames;
}

/// Quality preset used by [PerformanceBudgetResource].
enum QualityPreset { ultra, high, medium, low }

/// Runtime performance budget and quality controls.
///
/// This is data-only and can be consumed by loop drivers, extract systems and
/// render hosts to enforce CPU/GPU limits.
class PerformanceBudgetResource extends Resource {
  PerformanceBudgetResource({
    this.preset = QualityPreset.high,
    this.adaptiveQuality = false,
    this.frameBudgetMs = 16.67,
    this.cpuBudgetMs = 10.0,
    this.gpuBudgetMs = 6.0,
    this.renderScale = 1.0,
    this.maxDrawCalls = 0,
    this.maxParticles = 0,
    this.maxEntityUpdates = 0,
  });

  QualityPreset preset;

  /// When true, hosts/systems may auto-adjust quality.
  bool adaptiveQuality;

  /// Target total frame budget.
  double frameBudgetMs;

  /// Target CPU budget (simulation + extraction + game-side work).
  double cpuBudgetMs;

  /// Target GPU submit budget.
  double gpuBudgetMs;

  /// 1.0 = native resolution, lower values reduce internal render resolution.
  double renderScale;

  /// Optional cap. `<= 0` means unlimited.
  int maxDrawCalls;

  /// Optional cap. `<= 0` means unlimited.
  int maxParticles;

  /// Optional cap. `<= 0` means unlimited.
  int maxEntityUpdates;
}

/// Render submit telemetry captured by render hosts.
///
/// Used by budget controllers to react to GPU/transport pressure.
class RenderSubmitMetricsResource extends Resource {
  RenderSubmitMetricsResource({
    this.submitMicros = 0,
    this.drawCount = 0,
    this.transformCount = 0,
    final List<int>? submitMicrosSamples,
  }) : submitMicrosSamples = submitMicrosSamples ?? <int>[];

  static const int maxSamples = 120;

  int submitMicros;
  int drawCount;
  int transformCount;

  final List<int> submitMicrosSamples;

  void update({
    required final int submitMicros,
    required final int drawCount,
    required final int transformCount,
  }) {
    this.submitMicros = submitMicros;
    this.drawCount = drawCount;
    this.transformCount = transformCount;

    submitMicrosSamples.add(submitMicros);
    if (submitMicrosSamples.length > maxSamples) {
      submitMicrosSamples.removeAt(0);
    }
  }
}

/// Per-frame profiling stats from the native wgpu renderer.
/// Populated by the render bridge when profiling is enabled.
class RenderProfileStatsResource extends Resource {
  bool profilingEnabled = false;
  String? lastAiDump;

  // CPU timings (microseconds)
  int cpuPrepareFrameUs = 0;
  int cpuMeshCollectSortUs = 0;
  int cpuRenderEncodeUs = 0;
  int cpuTotalUs = 0;

  // GPU timings (microseconds, -1 = unavailable)
  int gpuMeshUs = -1;
  int gpuSplatCullUs = -1;
  int gpuSplatSortUs = -1;
  int gpuSplatRenderUs = -1;
  int gpuBloomUs = -1;
  int gpuToneMapUs = -1;
  int gpuTotalUs = -1;

  bool gpuTimestampsAvailable = false;
  int meshBatchCount = 0;
  int splatCount = 0;

  /// Callback to toggle profiling in the native renderer.
  // ignore: avoid_positional_boolean_parameters
  void Function(bool enabled)? onSetProfilingEnabled;

  /// Callback to read latest profile stats from native.
  void Function()? onReadProfileStats;
}

/// Convenience helper for updating [RenderSubmitMetricsResource].
void reportRenderSubmitMetrics(
  final World world, {
  required final int submitMicros,
  required final int drawCount,
  required final int transformCount,
}) {
  if (!world.resources.has<RenderSubmitMetricsResource>()) {
    world.upsertResource(RenderSubmitMetricsResource());
  }

  world.getResource<RenderSubmitMetricsResource>().update(
    submitMicros: submitMicros,
    drawCount: drawCount,
    transformCount: transformCount,
  );
}

/// Applies a quality preset to [PerformanceBudgetResource] runtime controls.
void applyQualityPreset(
  final PerformanceBudgetResource budget,
  final QualityPreset preset,
) {
  budget.preset = preset;
  budget.frameBudgetMs = 16.67;
  switch (preset) {
    case QualityPreset.ultra:
      budget.cpuBudgetMs = 11.0;
      budget.gpuBudgetMs = 7.0;
      budget.renderScale = 1.0;
      budget.maxDrawCalls = 0;
      budget.maxParticles = 0;
      budget.maxEntityUpdates = 0;
    case QualityPreset.high:
      budget.cpuBudgetMs = 10.0;
      budget.gpuBudgetMs = 6.0;
      budget.renderScale = 0.9;
      budget.maxDrawCalls = 10000;
      budget.maxParticles = 25000;
      budget.maxEntityUpdates = 0;
    case QualityPreset.medium:
      budget.cpuBudgetMs = 9.0;
      budget.gpuBudgetMs = 5.5;
      budget.renderScale = 0.75;
      budget.maxDrawCalls = 6000;
      budget.maxParticles = 12000;
      budget.maxEntityUpdates = 50000;
    case QualityPreset.low:
      budget.cpuBudgetMs = 8.0;
      budget.gpuBudgetMs = 5.0;
      budget.renderScale = 0.6;
      budget.maxDrawCalls = 3000;
      budget.maxParticles = 5000;
      budget.maxEntityUpdates = 25000;
  }
}

QualityPreset nextHigherQualityPreset(final QualityPreset preset) =>
    switch (preset) {
      QualityPreset.low => QualityPreset.medium,
      QualityPreset.medium => QualityPreset.high,
      QualityPreset.high => QualityPreset.ultra,
      QualityPreset.ultra => QualityPreset.ultra,
    };

QualityPreset nextLowerQualityPreset(final QualityPreset preset) =>
    switch (preset) {
      QualityPreset.ultra => QualityPreset.high,
      QualityPreset.high => QualityPreset.medium,
      QualityPreset.medium => QualityPreset.low,
      QualityPreset.low => QualityPreset.low,
    };

/// Optional non-deterministic adapter used only when explicitly installed.
///
/// This resource is intentionally opt-in and should not be used in deterministic
/// simulation tests.
class WallClockScheduleTimeResource extends Resource {
  WallClockScheduleTimeResource({
    required this.nowSeconds,
    required this.lastTickSeconds,
  });

  double nowSeconds;
  double lastTickSeconds;
}

/// Optional diagnostics for deterministic simulation/extraction verification.
///
/// This resource is data-only and can be updated by systems each frame to track
/// order diagnostics and section hashes.
class WorldDeterminismResource extends Resource {
  WorldDeterminismResource({
    this.frameId = 0,
    this.worldHash64 = 0,
    this.packetHash64 = 0,
    this.orderViolationCount = 0,
    final List<int>? sectionHashes64,
  }) : sectionHashes64 = sectionHashes64 ?? <int>[];

  int frameId;
  int worldHash64;
  int packetHash64;
  int orderViolationCount;
  List<int> sectionHashes64;
}

enum ScheduleExecutionPolicy { serial, deterministic, bestEffort }

class ScheduleExecutionPolicyResource extends Resource {
  ScheduleExecutionPolicyResource({
    this.mode = ScheduleExecutionPolicy.deterministic,
    this.workerCount = 1,
    this.frameId = 0,
  });

  int frameId;
  ScheduleExecutionPolicy mode;
  int workerCount;

  void advanceFrame() {
    frameId += 1;
  }

  // ignore: use_setters_to_change_properties
  void markFrame(final int frameId) {
    this.frameId = frameId;
  }
}

class ScheduleJobResultQueueResource extends Resource {
  final List<ScheduleJobResultEnvelope<Object>> _completed =
      <ScheduleJobResultEnvelope<Object>>[];
  final Set<String> _inFlight = <String>{};

  bool beginInFlight({
    required final String jobKey,
    required final int frameId,
  }) => _inFlight.add(_composeInFlightKey(jobKey, frameId));

  void cancelInFlight({
    required final String jobKey,
    required final int frameId,
  }) {
    _inFlight.remove(_composeInFlightKey(jobKey, frameId));
  }

  void completeInFlight<T extends Object>(
    final ScheduleJobResultEnvelope<T> envelope,
  ) {
    _inFlight.remove(_composeInFlightKey(envelope.jobKey, envelope.frameId));
    _completed.add(_eraseEnvelope(envelope));
  }

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

  bool hasInFlightJob(final String jobKey) =>
      _inFlight.any((final key) => key.startsWith('$jobKey#'));

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

void syncScheduleExecutionFrame(
  final World world, {
  final int? explicitFrameId,
}) {
  if (!world.resources.has<ScheduleExecutionPolicyResource>()) {
    return;
  }
  final policy = world.getResource<ScheduleExecutionPolicyResource>();
  if (explicitFrameId != null) {
    policy.markFrame(explicitFrameId);
    return;
  }
  policy.advanceFrame();
}
