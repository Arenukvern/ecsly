import 'dart:async';

import 'package:ecsly/ecsly.dart';
import 'package:meta/meta.dart';

import '../ecsly_app.dart';

class EcsLoop {
  final worlds = <WorldId, World>{};

  void attachWorld(final World world) => worlds[world.id] = world;

  void dispose() {
    for (final world in worlds.values) {
      world.clear();
    }
    worlds.clear();
  }
}

@immutable
class EcsFixedStepMetrics {
  const EcsFixedStepMetrics({
    required this.fixedDt,
    required this.elapsedMicros,
    required this.stepsRunThisTickerFrame,
    required this.catchUpClamped,
  });

  final double fixedDt;
  final int elapsedMicros;
  final int stepsRunThisTickerFrame;
  final bool catchUpClamped;
}

class EcsFixedLoopConfig {
  const EcsFixedLoopConfig({
    this.fixedDt = 1 / 60,
    this.schedules = const [],
    this.flushAfterStep = true,
    this.maxCatchUpStepsPerTick,
    this.onFixedStepMetrics,
  });
  final bool flushAfterStep;
  final Iterable<({String name, bool isAsync})> schedules;
  final double fixedDt;
  Duration get fixedDtDuration =>
      Duration(milliseconds: (fixedDt * 1000).toInt());
  final int? maxCatchUpStepsPerTick;
  final void Function(EcsFixedStepMetrics)? onFixedStepMetrics;
}

/// Allows to tick every attached world.
class EcsFixedLoop extends EcsLoop {
  EcsFixedLoop({this.config = const EcsFixedLoopConfig()});
  EcsFixedLoopConfig config;
  Duration _lastElapsed = Duration.zero;
  double _accumulator = 0;
  Timer? timer;
  bool get isLoopActive => timer != null && timer?.isActive == true;

  void start(final EcsFixedLoopConfig? config) {
    if (config != null) this.config = config;
    timer = Timer(this.config.fixedDtDuration, _handleTick);
  }

  void _handleTick() {
    for (final world in worlds.values) {
      tickWorld(world, _lastElapsed);
    }
    timer = Timer(config.fixedDtDuration, _handleTick);
  }

  void stop() {
    timer?.cancel();
    timer = null;
  }

  void tickWorld(final World world, final Duration elapsed) {
    final frameTime = _lastElapsed == Duration.zero
        ? 0.0
        : (elapsed - _lastElapsed).inMicroseconds / 1000000.0;
    _lastElapsed = elapsed;

    final stopwatch = Stopwatch()..start();
    var stepsRun = 0;
    var catchUpClamped = false;
    final maxSteps = config.maxCatchUpStepsPerTick;
    _accumulator += frameTime.clamp(0.0, 0.1);
    while (_accumulator >= config.fixedDt &&
        (maxSteps == null || stepsRun < maxSteps)) {
      _runFixedStep(world);
      _accumulator -= config.fixedDt;
      stepsRun += 1;
    }
    if (maxSteps != null && _accumulator >= config.fixedDt) {
      _accumulator = 0;
      catchUpClamped = true;
    }
    stopwatch.stop();
    config.onFixedStepMetrics?.call(
      EcsFixedStepMetrics(
        fixedDt: config.fixedDt,
        elapsedMicros: stopwatch.elapsedMicroseconds,
        stepsRunThisTickerFrame: stepsRun,
        catchUpClamped: catchUpClamped,
      ),
    );
    if (stepsRun > 0) {
      world.flush();
    }
  }

  void _runFixedStep(final World world) {
    _updateTimeResources(world, config.fixedDt);
    // Advance the schedule execution frame so that best-effort job systems
    // (ScheduleJobResultQueueResource) can pipeline across frames.
    syncScheduleExecutionFrame(world);
    for (final schedule in config.schedules) {
      // Use runSchedule (sync path) for all schedules. The sync executor's
      // _executeGroup already does fire-and-forget for asyncParallel systems
      // — the returned Future is discarded. Using runScheduleAsync would
      // incorrectly await via Future.wait, blocking the loop.
      world.runSchedule(ScheduleId(schedule.name));
    }
  }
}

void _updateTimeResources(final World world, final double dt) {
  if (!world.resources.has<DeltaTimeResource>()) {
    world.upsertResource(DeltaTimeResource(dt));
  } else {
    world.getResource<DeltaTimeResource>().deltaTime = dt;
  }

  if (!world.resources.has<ScheduleTimeResource>()) {
    world.upsertResource(
      ScheduleTimeResource(deltaSeconds: dt, elapsedSeconds: dt),
    );
    world.flush();
    return;
  }

  final scheduleTime = world.getResource<ScheduleTimeResource>();
  scheduleTime
    ..deltaSeconds = dt
    ..elapsedSeconds += dt;
}
