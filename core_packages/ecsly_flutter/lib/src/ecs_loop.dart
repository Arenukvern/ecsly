import 'dart:async' show unawaited;

import 'package:ecsly_app/ecsly_app.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'ecs_controller.dart';
import 'ecs_schedule_observer.dart';

typedef ScheduleOrderingPolicy =
    Iterable<String> Function(Iterable<String> scheduleNames);
typedef EcsScheduleInvalidation =
    EcsInvalidationBatch? Function(String scheduleName);

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

/// Ticker-driven Flutter frame loop.
class EcsLoop extends StatefulWidget {
  const EcsLoop({
    required this.world,
    required this.schedules,
    required this.child,
    this.controller,
    this.paused,
    this.flushAfterTick = true,
    this.scheduleOrderingPolicy,
    this.scheduleReason = EcsFlutterScheduleReason.frame,
    this.scheduleInvalidation,
    this.onScheduleRun,
    super.key,
  });

  final World world;
  final EcsController? controller;
  final Iterable<String> schedules;
  final Widget child;
  final ValueListenable<bool>? paused;
  final bool flushAfterTick;
  final ScheduleOrderingPolicy? scheduleOrderingPolicy;
  final EcsFlutterScheduleReason scheduleReason;
  final EcsScheduleInvalidation? scheduleInvalidation;
  final EcsScheduleRunObserver? onScheduleRun;

  @override
  State<EcsLoop> createState() => _EcsLoopState();
}

/// Drives named ECS schedules with fixed-step accumulation.
class EcsFixedStepLoop extends StatefulWidget {
  const EcsFixedStepLoop({
    required this.world,
    required this.schedules,
    required this.child,
    this.controller,
    this.fixedDt = 1 / 60,
    this.maxCatchUpStepsPerTick,
    this.paused,
    this.flushAfterStep = true,
    this.onFixedStepMetrics,
    this.scheduleReason = EcsFlutterScheduleReason.frame,
    this.scheduleInvalidation,
    this.onScheduleRun,
    super.key,
  });

  final World world;
  final EcsController? controller;
  final Iterable<String> schedules;
  final Widget child;
  final double fixedDt;
  final int? maxCatchUpStepsPerTick;
  final ValueListenable<bool>? paused;
  final bool flushAfterStep;
  final ValueChanged<EcsFixedStepMetrics>? onFixedStepMetrics;
  final EcsFlutterScheduleReason scheduleReason;
  final EcsScheduleInvalidation? scheduleInvalidation;
  final EcsScheduleRunObserver? onScheduleRun;

  @override
  State<EcsFixedStepLoop> createState() => _EcsFixedStepLoopState();
}

class _EcsLoopState extends State<EcsLoop> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  Duration _lastElapsed = Duration.zero;

  @override
  Widget build(final BuildContext context) => widget.child;

  @override
  void dispose() {
    widget.paused?.removeListener(_applyPaused);
    _ticker.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
    widget.paused?.addListener(_applyPaused);
    _applyPaused();
  }

  @override
  void didUpdateWidget(covariant final EcsLoop oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.paused, widget.paused)) {
      oldWidget.paused?.removeListener(_applyPaused);
      widget.paused?.addListener(_applyPaused);
      _applyPaused();
    }
  }

  void _applyPaused() {
    if (widget.paused?.value ?? false) {
      _ticker.stop();
      _lastElapsed = Duration.zero;
      return;
    }
    if (!_ticker.isActive) {
      unawaited(_ticker.start());
    }
  }

  void _onTick(final Duration elapsed) {
    final frameTime = _lastElapsed == Duration.zero
        ? 0.0
        : (elapsed - _lastElapsed).inMicroseconds / 1000000.0;
    _lastElapsed = elapsed;
    _runSchedules(frameTime.clamp(0.0, 0.1));
  }

  void _runSchedules(final double dt) {
    _updateTimeResources(widget.world, dt);
    var invalidation = _timeResourceInvalidation();
    final ordered =
        widget.scheduleOrderingPolicy?.call(widget.schedules) ??
        widget.schedules;
    for (final scheduleName in ordered) {
      _runSchedule(
        widget.world,
        scheduleName,
        reason: widget.scheduleReason,
        onScheduleRun: widget.onScheduleRun,
      );
      invalidation = invalidation.merge(
        _scheduleInvalidationFor(scheduleName, widget.scheduleInvalidation),
      );
    }
    _flushAndNotify(
      widget.world,
      widget.controller,
      flush: widget.flushAfterTick,
      invalidation: invalidation,
    );
  }
}

class _EcsFixedStepLoopState extends State<EcsFixedStepLoop>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  Duration _lastElapsed = Duration.zero;
  double _accumulator = 0;

  @override
  Widget build(final BuildContext context) => widget.child;

  @override
  void dispose() {
    widget.paused?.removeListener(_applyPaused);
    _ticker.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
    widget.paused?.addListener(_applyPaused);
    _applyPaused();
  }

  @override
  void didUpdateWidget(covariant final EcsFixedStepLoop oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.paused, widget.paused)) {
      oldWidget.paused?.removeListener(_applyPaused);
      widget.paused?.addListener(_applyPaused);
      _applyPaused();
    }
  }

  void _applyPaused() {
    if (widget.paused?.value ?? false) {
      _ticker.stop();
      _lastElapsed = Duration.zero;
      _accumulator = 0;
      return;
    }
    if (!_ticker.isActive) {
      unawaited(_ticker.start());
    }
  }

  void _onTick(final Duration elapsed) {
    final frameTime = _lastElapsed == Duration.zero
        ? 0.0
        : (elapsed - _lastElapsed).inMicroseconds / 1000000.0;
    _lastElapsed = elapsed;

    final stopwatch = Stopwatch()..start();
    var stepsRun = 0;
    var catchUpClamped = false;
    var invalidation = const EcsInvalidationBatch.empty();
    final maxSteps = widget.maxCatchUpStepsPerTick;
    _accumulator += frameTime.clamp(0.0, 0.1);
    while (_accumulator >= widget.fixedDt &&
        (maxSteps == null || stepsRun < maxSteps)) {
      invalidation = invalidation.merge(_runFixedStep());
      _accumulator -= widget.fixedDt;
      stepsRun += 1;
    }
    if (maxSteps != null && _accumulator >= widget.fixedDt) {
      _accumulator = 0;
      catchUpClamped = true;
    }
    stopwatch.stop();
    widget.onFixedStepMetrics?.call(
      EcsFixedStepMetrics(
        fixedDt: widget.fixedDt,
        elapsedMicros: stopwatch.elapsedMicroseconds,
        stepsRunThisTickerFrame: stepsRun,
        catchUpClamped: catchUpClamped,
      ),
    );
    if (stepsRun > 0) {
      _flushAndNotify(
        widget.world,
        widget.controller,
        flush: widget.flushAfterStep,
        invalidation: invalidation,
      );
    }
  }

  EcsInvalidationBatch _runFixedStep() {
    _updateTimeResources(widget.world, widget.fixedDt);
    var invalidation = _timeResourceInvalidation();
    for (final scheduleName in widget.schedules) {
      _runSchedule(
        widget.world,
        scheduleName,
        reason: widget.scheduleReason,
        onScheduleRun: widget.onScheduleRun,
      );
      invalidation = invalidation.merge(
        _scheduleInvalidationFor(scheduleName, widget.scheduleInvalidation),
      );
    }
    return invalidation;
  }
}

void _runSchedule(
  final World world,
  final String scheduleName, {
  required final EcsFlutterScheduleReason reason,
  required final EcsScheduleRunObserver? onScheduleRun,
}) {
  final stopwatch = Stopwatch()..start();
  try {
    world.runSchedule(scheduleName);
    stopwatch.stop();
    onScheduleRun?.call(
      EcsScheduleRunEvent(
        scheduleName: scheduleName,
        reason: reason,
        elapsed: stopwatch.elapsed,
      ),
    );
  } on Object catch (error, stackTrace) {
    stopwatch.stop();
    onScheduleRun?.call(
      EcsScheduleRunEvent(
        scheduleName: scheduleName,
        reason: reason,
        elapsed: stopwatch.elapsed,
        error: error,
        stackTrace: stackTrace,
      ),
    );
    rethrow;
  }
}

void _flushAndNotify(
  final World world,
  final EcsController? controller, {
  required final bool flush,
  required final EcsInvalidationBatch invalidation,
}) {
  if (controller != null) {
    controller.notifyWorldChanged(flush: flush, invalidation: invalidation);
    return;
  }
  if (flush) {
    world.flush();
  }
}

EcsInvalidationBatch _scheduleInvalidationFor(
  final String scheduleName,
  final EcsScheduleInvalidation? scheduleInvalidation,
) =>
    scheduleInvalidation?.call(scheduleName) ??
    const EcsInvalidationBatch.broad();

EcsInvalidationBatch _timeResourceInvalidation() =>
    EcsInvalidationBatch.resources(const <Type>[
      DeltaTimeResource,
      ScheduleTimeResource,
    ]);

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
