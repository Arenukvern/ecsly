import 'package:ecsly_app/ecsly_app.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'ecs_controller.dart';
import 'ecs_loop.dart';
import 'ecs_schedule_observer.dart';
import 'ecs_scope.dart';

enum EcsFrameScheduleMode { vsync, fixedStep }

@immutable
class EcsFrameSchedule {
  const EcsFrameSchedule.vsync(
    this.schedule, {
    this.paused,
    this.flushAfterTick = true,
    this.scheduleOrderingPolicy,
    this.invalidation,
  }) : mode = EcsFrameScheduleMode.vsync,
       fixedDt = null,
       maxCatchUpStepsPerTick = null;

  const EcsFrameSchedule.fixed(
    this.schedule, {
    this.fixedDt = 1 / 60,
    this.maxCatchUpStepsPerTick,
    this.paused,
    this.flushAfterTick = true,
    this.invalidation,
  }) : mode = EcsFrameScheduleMode.fixedStep,
       scheduleOrderingPolicy = null;

  final String schedule;
  final EcsFrameScheduleMode mode;
  final ValueListenable<bool>? paused;
  final bool flushAfterTick;
  final ScheduleOrderingPolicy? scheduleOrderingPolicy;
  final EcsInvalidationBatch? invalidation;
  final double? fixedDt;
  final int? maxCatchUpStepsPerTick;
}

@immutable
class EcsFlutterSchedules {
  const EcsFlutterSchedules({
    this.onMount,
    this.onMountSpec,
    this.afterAction,
    this.afterActionSpec,
    this.onResume,
    this.onResumeSpec,
    this.onPause,
    this.onPauseSpec,
    this.frame,
  });

  final String? onMount;
  final EcsHostSchedule? onMountSpec;
  final String? afterAction;
  final EcsHostSchedule? afterActionSpec;
  final String? onResume;
  final EcsHostSchedule? onResumeSpec;
  final String? onPause;
  final EcsHostSchedule? onPauseSpec;
  final EcsFrameSchedule? frame;

  Iterable<String> scheduleNamesFor(final EcsFlutterScheduleReason reason) {
    final scheduleName = scheduleFor(reason)?.name;
    return scheduleName == null ? const <String>[] : <String>[scheduleName];
  }

  EcsHostSchedule? scheduleFor(final EcsFlutterScheduleReason reason) =>
      switch (reason) {
        EcsFlutterScheduleReason.onMount =>
          onMountSpec ?? _hostScheduleFrom(onMount),
        EcsFlutterScheduleReason.afterAction =>
          afterActionSpec ?? _hostScheduleFrom(afterAction),
        EcsFlutterScheduleReason.onResume =>
          onResumeSpec ?? _hostScheduleFrom(onResume),
        EcsFlutterScheduleReason.onPause =>
          onPauseSpec ?? _hostScheduleFrom(onPause),
        EcsFlutterScheduleReason.frame => frame == null
            ? null
            : EcsHostSchedule(frame!.schedule, invalidation: frame!.invalidation),
      };
}

class EcsAppScope extends StatefulWidget {
  const EcsAppScope({
    required this.world,
    required this.child,
    this.controller,
    this.schedules = const EcsFlutterSchedules(),
    this.services,
    this.runOnMount = true,
    this.observeLifecycle = true,
    this.disposeController = false,
    this.onScheduleRun,
    super.key,
  });

  final World world;
  final Widget child;
  final EcsController? controller;
  final EcsActionServices? services;
  final EcsFlutterSchedules schedules;
  final bool runOnMount;
  final bool observeLifecycle;
  final bool disposeController;
  final EcsScheduleRunObserver? onScheduleRun;

  @override
  State<EcsAppScope> createState() => _EcsAppScopeState();
}

class _EcsAppScopeState extends State<EcsAppScope> with WidgetsBindingObserver {
  late EcsController _controller;
  bool _ownsController = false;
  bool _mountScheduled = false;

  @override
  Widget build(final BuildContext context) {
    final scoped = EcsScope(
      world: widget.world,
      controller: _controller,
      child: _buildFrameHost(widget.child),
    );
    return scoped;
  }

  @override
  void initState() {
    super.initState();
    _configureController();
    if (widget.observeLifecycle) {
      WidgetsBinding.instance.addObserver(this);
    }
    _scheduleMount();
  }

  @override
  void didUpdateWidget(covariant final EcsAppScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    final controllerChanged =
        oldWidget.controller != widget.controller ||
        oldWidget.world != widget.world ||
        oldWidget.services != widget.services;
    if (controllerChanged) {
      _disposeOwnedController();
      _configureController();
      _mountScheduled = false;
    } else {
      _controller
        ..afterActionSchedule = widget.schedules.afterAction
        ..afterActionScheduleSpec = widget.schedules.afterActionSpec
        ..onScheduleRun = widget.onScheduleRun;
    }

    if (oldWidget.observeLifecycle != widget.observeLifecycle) {
      if (widget.observeLifecycle) {
        WidgetsBinding.instance.addObserver(this);
      } else {
        WidgetsBinding.instance.removeObserver(this);
      }
    }
    _scheduleMount();
  }

  @override
  void didChangeAppLifecycleState(final AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _runLifecycleSchedule(EcsFlutterScheduleReason.onResume);
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        _runLifecycleSchedule(EcsFlutterScheduleReason.onPause);
      case AppLifecycleState.detached:
        break;
    }
  }

  @override
  void dispose() {
    if (widget.observeLifecycle) {
      WidgetsBinding.instance.removeObserver(this);
    }
    _disposeOwnedController();
    super.dispose();
  }

  Widget _buildFrameHost(final Widget child) {
    final frame = widget.schedules.frame;
    if (frame == null) return child;
    return switch (frame.mode) {
      EcsFrameScheduleMode.vsync => EcsLoop(
        world: widget.world,
        controller: _controller,
        schedules: [frame.schedule],
        paused: frame.paused,
        flushAfterTick: frame.flushAfterTick,
        scheduleOrderingPolicy: frame.scheduleOrderingPolicy,
        scheduleInvalidation: frame.invalidation == null
            ? null
            : (_) => frame.invalidation,
        onScheduleRun: widget.onScheduleRun,
        child: child,
      ),
      EcsFrameScheduleMode.fixedStep => EcsFixedStepLoop(
        world: widget.world,
        controller: _controller,
        schedules: [frame.schedule],
        fixedDt: frame.fixedDt ?? 1 / 60,
        maxCatchUpStepsPerTick: frame.maxCatchUpStepsPerTick,
        paused: frame.paused,
        flushAfterStep: frame.flushAfterTick,
        scheduleInvalidation: frame.invalidation == null
            ? null
            : (_) => frame.invalidation,
        onScheduleRun: widget.onScheduleRun,
        child: child,
      ),
    };
  }

  void _configureController() {
    final external = widget.controller;
    if (external == null) {
      _controller = EcsController(
        world: widget.world,
        services: widget.services,
        afterActionSchedule: widget.schedules.afterAction,
        afterActionScheduleSpec: widget.schedules.afterActionSpec,
        onScheduleRun: widget.onScheduleRun,
      );
      _ownsController = true;
      return;
    }
    _controller = external
      ..afterActionSchedule = widget.schedules.afterAction
      ..afterActionScheduleSpec = widget.schedules.afterActionSpec
      ..onScheduleRun = widget.onScheduleRun;
    _ownsController = false;
  }

  void _disposeOwnedController() {
    if (_ownsController || widget.disposeController) {
      _controller.dispose();
    }
    _ownsController = false;
  }

  void _scheduleMount() {
    if (!widget.runOnMount || _mountScheduled) return;
    _mountScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((final _) {
      if (!mounted) return;
      _runLifecycleSchedule(EcsFlutterScheduleReason.onMount);
    });
  }

  void _runLifecycleSchedule(final EcsFlutterScheduleReason reason) {
    final schedule = widget.schedules.scheduleFor(reason);
    if (schedule == null) return;
    if (!schedule.shouldRun(const EcsInvalidationBatch.empty())) return;
    for (final scheduleName in widget.schedules.scheduleNamesFor(reason)) {
      _controller.runSchedule(
        scheduleName,
        invalidation: schedule.invalidation,
        reason: reason,
      );
    }
  }
}

EcsHostSchedule? _hostScheduleFrom(final String? name) =>
    name == null ? null : EcsHostSchedule(name);
