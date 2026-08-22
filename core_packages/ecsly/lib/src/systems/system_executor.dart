import 'dart:async';

import '../world/world.dart';
import 'ecs_observers.dart';
import 'system.dart';
import 'system_descriptor.dart';

/// {@template system_executor}
/// Executes systems with support for ordering, dependencies,
/// async execution, and parallelization.
///
/// Does not flush automatically - developers must add phase systems
/// (flushEntitiesSystem, flushCommandsSystem, etc.) to schedules explicitly.
/// {@endtemplate}
class SystemExecutor {
  /// {@macro system_executor}
  const SystemExecutor();

  /// Execute a schedule of systems synchronously.
  void executeSchedule(
    final World world,
    final String scheduleName,
    final List<List<int>> groups,
    final List<SystemDescriptor> systems,
  ) {
    final observer = world.executionObserver;
    if (observer == null) {
      for (final group in groups) {
        _executeGroup(world, group, systems);
      }
      return;
    }

    observer.onScheduleStart(world, scheduleName, systemCount: systems.length);
    try {
      for (final group in groups) {
        _executeGroupObserved(world, scheduleName, group, systems, observer);
      }
    } finally {
      observer.onScheduleEnd(world, scheduleName);
    }
  }

  /// Execute a schedule of systems asynchronously.
  ///
  /// Supports parallel and isolate execution modes.
  Future<void> executeScheduleAsync(
    final World world,
    final String scheduleName,
    final List<List<int>> groups,
    final List<SystemDescriptor> systems,
  ) async {
    final observer = world.executionObserver;
    if (observer == null) {
      for (final group in groups) {
        await _executeGroupAsync(world, group, systems);
      }
      return;
    }

    observer.onScheduleStart(world, scheduleName, systemCount: systems.length);
    try {
      for (final group in groups) {
        await _executeGroupAsyncObserved(
          world,
          scheduleName,
          group,
          systems,
          observer,
        );
      }
    } finally {
      observer.onScheduleEnd(world, scheduleName);
    }
  }

  /// Execute a group of sync systems.
  void _executeGroup(
    final World world,
    final List<int> group,
    final List<SystemDescriptor> systems,
  ) {
    for (final index in group) {
      final desc = systems[index];

      if (desc.mode case .sync) {
        desc.system(world);
      }
      if (desc.mode case .asyncParallel) {
        desc.system(world);
      }
    }
  }

  /// Execute a group of systems with async support.
  Future<void> _executeGroupAsync(
    final World world,
    final List<int> group,
    final List<SystemDescriptor> systems,
  ) async {
    final sequential = <SystemDescriptor>[];
    final parallel = <SystemDescriptor>[];

    // Categorize systems by execution mode
    for (final index in group) {
      final desc = systems[index];
      switch (desc.mode) {
        case ExecutionMode.asyncParallel when desc.canRunInParallel:
          parallel.add(desc);
        case ExecutionMode.sync ||
            ExecutionMode.async ||
            ExecutionMode.asyncParallel:
          sequential.add(desc);
      }
    }

    // Execute sequential systems first
    for (final desc in sequential) {
      if (desc.mode case .async) {
        await (desc.system as AsyncSystem)(world);
      } else {
        desc.system(world);
      }
    }

    // Execute parallel systems concurrently
    if (parallel.isNotEmpty) {
      await Future.wait(
        parallel.map((final desc) => (desc.system as AsyncSystem)(world)),
      );
    }
  }

  Future<void> _executeGroupAsyncObserved(
    final World world,
    final String scheduleName,
    final List<int> group,
    final List<SystemDescriptor> systems,
    final EcsExecutionObserver observer,
  ) async {
    final sequential = <SystemDescriptor>[];
    final parallel = <SystemDescriptor>[];
    final rustParallel = <SystemDescriptor>[];

    for (final index in group) {
      final desc = systems[index];
      switch (desc.mode) {
        case ExecutionMode.asyncParallel when desc.canRunInParallel:
          parallel.add(desc);
        case ExecutionMode.sync ||
            ExecutionMode.async ||
            ExecutionMode.asyncParallel:
          sequential.add(desc);
      }
    }

    for (final desc in sequential) {
      observer.onSystemStart(world, scheduleName, desc);
      final startUs = DateTime.now().microsecondsSinceEpoch;
      Object? error;
      StackTrace? stackTrace;
      try {
        if (desc.mode case .async || .asyncParallel) {
          await (desc.system as AsyncSystem)(world);
        } else {
          desc.system(world);
        }
      } catch (e, st) {
        error = e;
        stackTrace = st;
        rethrow;
      } finally {
        final elapsedUs = DateTime.now().microsecondsSinceEpoch - startUs;
        observer.onSystemEnd(
          world,
          scheduleName,
          desc,
          elapsedMicroseconds: elapsedUs,
          error: error,
          stackTrace: stackTrace,
        );
      }
    }

    if (parallel.isNotEmpty) {
      await Future.wait(
        parallel.map((final desc) async {
          observer.onSystemStart(world, scheduleName, desc);
          final startUs = DateTime.now().microsecondsSinceEpoch;
          Object? error;
          StackTrace? stackTrace;
          try {
            await (desc.system as AsyncSystem)(world);
          } catch (e, st) {
            error = e;
            stackTrace = st;
            rethrow;
          } finally {
            final elapsedUs = DateTime.now().microsecondsSinceEpoch - startUs;
            observer.onSystemEnd(
              world,
              scheduleName,
              desc,
              elapsedMicroseconds: elapsedUs,
              error: error,
              stackTrace: stackTrace,
            );
          }
        }),
      );
    }

    if (rustParallel.isNotEmpty) {
      await Future.wait(
        rustParallel.map((final desc) async {
          observer.onSystemStart(world, scheduleName, desc);
          final startUs = DateTime.now().microsecondsSinceEpoch;
          Object? error;
          StackTrace? stackTrace;
          try {
            await _executeRustParallel(world, desc);
          } catch (e, st) {
            error = e;
            stackTrace = st;
            rethrow;
          } finally {
            final elapsedUs = DateTime.now().microsecondsSinceEpoch - startUs;
            observer.onSystemEnd(
              world,
              scheduleName,
              desc,
              elapsedMicroseconds: elapsedUs,
              error: error,
              stackTrace: stackTrace,
            );
          }
        }),
      );
    }
  }

  void _executeGroupObserved(
    final World world,
    final String scheduleName,
    final List<int> group,
    final List<SystemDescriptor> systems,
    final EcsExecutionObserver observer,
  ) {
    for (final index in group) {
      final desc = systems[index];
      // Match unobserved semantics (_executeGroup): sync runs inline;
      // asyncParallel is fired without awaiting (fire-and-forget). Skipping
      // async systems here would silently change execution when an observer
      // is installed.
      if (desc.mode == ExecutionMode.async) continue;

      observer.onSystemStart(world, scheduleName, desc);
      final startUs = DateTime.now().microsecondsSinceEpoch;
      Object? error;
      StackTrace? stackTrace;
      try {
        desc.system(world);
      } catch (e, st) {
        error = e;
        stackTrace = st;
        rethrow;
      } finally {
        final elapsedUs = DateTime.now().microsecondsSinceEpoch - startUs;
        observer.onSystemEnd(
          world,
          scheduleName,
          desc,
          elapsedMicroseconds: elapsedUs,
          error: error,
          stackTrace: stackTrace,
        );
      }
    }
  }

  /// Execute a Rust parallel system.
  Future<void> _executeRustParallel(
    final World world,
    final SystemDescriptor desc,
  ) async {
    // Rust parallel systems are synchronous from Dart's perspective
    // but execute in parallel internally using Rust/Rayon
    desc.system(world);
  }
}
