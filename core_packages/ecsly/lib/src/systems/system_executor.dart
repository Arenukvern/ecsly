import 'dart:async';

import '../errors/ecs_errors.dart';
import '../world/world.dart';
import 'ecs_observers.dart';
import 'system.dart';
import 'system_descriptor.dart';

/// {@template system_executor}
/// Executes systems with support for ordering, dependencies,
/// async execution, and parallelization.
///
/// Note: `ExecutionMode.isolate` is a non-production placeholder pending
/// framework-agnostic deterministic isolate boundaries. Those systems still run
/// on the main owner synchronously today.
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
      if (desc.jobSystem != null) {
        desc.jobSystem!.runSerial(world);
        continue;
      }
      if (desc.mode == ExecutionMode.sync) {
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
    final isolates = <SystemDescriptor>[];
    final rustParallel = <SystemDescriptor>[];

    // Categorize systems by execution mode
    for (final index in group) {
      final desc = systems[index];
      if (desc.jobSystem != null) {
        sequential.add(desc);
        continue;
      }
      switch (desc.mode) {
        case ExecutionMode.isolate:
          isolates.add(desc);
        case ExecutionMode.rustParallel:
          rustParallel.add(desc);
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
      if (desc.jobSystem != null) {
        await desc.jobSystem!.runAsync(world);
        continue;
      }
      if (desc.mode == ExecutionMode.async) {
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

    // Execute Rust parallel systems
    if (rustParallel.isNotEmpty) {
      await Future.wait(
        rustParallel.map((final desc) => _executeRustParallel(world, desc)),
      );
    }

    // Execute isolate systems
    for (final desc in isolates) {
      await _executeInIsolate(world, desc);
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
    final isolates = <SystemDescriptor>[];
    final rustParallel = <SystemDescriptor>[];

    for (final index in group) {
      final desc = systems[index];
      if (desc.jobSystem != null) {
        sequential.add(desc);
        continue;
      }
      switch (desc.mode) {
        case ExecutionMode.isolate:
          isolates.add(desc);
        case ExecutionMode.rustParallel:
          rustParallel.add(desc);
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
        if (desc.jobSystem != null) {
          await desc.jobSystem!.runAsync(world);
        } else if (desc.mode == ExecutionMode.async) {
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

    for (final desc in isolates) {
      observer.onSystemStart(world, scheduleName, desc);
      final startUs = DateTime.now().microsecondsSinceEpoch;
      Object? error;
      StackTrace? stackTrace;
      try {
        await _executeInIsolate(world, desc);
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

  void _executeGroupObserved(
    final World world,
    final String scheduleName,
    final List<int> group,
    final List<SystemDescriptor> systems,
    final EcsExecutionObserver observer,
  ) {
    for (final index in group) {
      final desc = systems[index];
      if (desc.jobSystem != null) {
        observer.onSystemStart(world, scheduleName, desc);
        final startUs = DateTime.now().microsecondsSinceEpoch;
        Object? error;
        StackTrace? stackTrace;
        try {
          desc.jobSystem!.runSerial(world);
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
        continue;
      }
      if (desc.mode != ExecutionMode.sync) continue;

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

  /// Execute a system in the isolate placeholder path.
  ///
  /// Currently runs synchronously on the main owner until deterministic isolate
  /// abstraction is implemented.
  Future<void> _executeInIsolate(
    final World world,
    final SystemDescriptor desc,
  ) async {
    final config = desc.isolateConfig;
    if (config == null) {
      throw SystemConfigurationError(
        desc.name ?? 'unnamed',
        'marked for isolate execution but has no isolate config',
      );
    }

    // TODO(arenukvern): migrate to isolate execution with framework-agnostic abstraction (plugin: game_isolates)
    // For now, run synchronously
    desc.system(world);
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
