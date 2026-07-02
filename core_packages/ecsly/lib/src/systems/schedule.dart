// ignore_for_file: avoid_returning_this

/// # System Ordering Design Decisions
///
/// ## Overview
/// This file implements dependency-based system ordering using directed graphs,
/// replacing the previous priority-based approach for more robust and explicit
/// system execution guarantees.
///
/// ## Key Design Decisions
///
/// ### 1. Dependency-Based vs Priority-Based Ordering
/// - **Decision**: Use explicit dependency relationships instead of numeric priorities
/// - **Rationale**: Dependencies are more explicit, verifiable, and maintainable
/// - **Benefit**: Automatic cycle detection with detailed error messages
/// - **Migration**: `priority: N` → `runAfter: ['systemName']` or `then()`
///
/// ### 2. Directed Graph Implementation
/// - **Decision**: Use `directed_graph` package for topological ordering
/// - **Rationale**: Proven algorithms, better cycle detection than manual Kahn's
/// - **Benefit**: Detailed cycle paths in error messages vs simple count checks
/// - **Performance**: O(V + E) for typical game schedules (<100 systems)
///
/// ### 3. Cycle Detection Strategy
/// - **Decision**: Check `DirectedGraph.isAcyclic` before topological ordering
/// - **Rationale**: Early failure with actionable error messages
/// - **Example**: `[input, logic, output, input]` instead of generic "cycle detected"
/// - **Benefit**: Developers can immediately identify problematic dependencies
///
/// ### 4. then() Method Compatibility
/// - **Decision**: Keep `then()` but implement as dependency chain
/// - **Rationale**: Backward compatibility while enforcing dependency model
/// - **Implementation**: `then()` creates `runAfter: [_lastSystemName]`
/// - **Benefit**: Simple sequential chaining without breaking existing code
///
/// ### 5. Execution Grouping Strategy
/// - **Decision**: Group by dependency levels, respect `canRunInParallel` flag
/// - **Rationale**: Correct ordering + parallel execution optimization
/// - **Implementation**: Systems in same dependency level can run concurrently
/// - **Benefit**: Maintains performance while ensuring correctness
///
/// ### 6. Unnamed Systems Handling
/// - **Decision**: Group unnamed systems together at end of execution
/// - **Rationale**: Simple systems don't need dependency resolution
/// - **Benefit**: Reduced graph complexity for basic use cases
///
/// ## Implementation Notes
/// - Graph construction: O(systems + dependencies) - cached until changes
/// - Cycle detection: O(V + E) - fails fast on circular dependencies
/// - Execution grouping: Preserves parallel execution capabilities
/// - Error messages: Include full cycle paths for debugging
library;

import 'package:directed_graph/directed_graph.dart';

import '../errors/ecs_errors.dart';
import '../world/world.dart';
import 'certified_job_system.dart';
import 'schedule_trigger.dart';
import 'system.dart';
import 'system_descriptor.dart';
import 'system_executor.dart';

void _noopSystem(final World _) {}

/// {@template schedule}
/// A collection of systems that run together with defined ordering.
///
/// Schedules can have triggers that determine when they execute,
/// and support ordering based on dependencies and explicit chaining.
///
/// Example:
/// ```dart
/// final schedule = Schedule('Update')
///   .add(inputSystem, name: 'input')
///   .then(physicsSystem, name: 'physics')
///   .then(collisionSystem, name: 'collision')
///   .parallel([particleSystem, soundSystem]);
///
/// schedule.run(world);
/// ```
/// {@endtemplate}
class Schedule {
  /// {@macro schedule}
  Schedule(
    this.name, {
    this.trigger = const ManualTrigger(),
    final SystemExecutor? executor,
    this.maxExecutionRate,
    this.isHotPath = false,
  }) : executor = executor ?? const SystemExecutor();

  static const int _maxTrackedExecutions = 100;

  /// Name of this schedule
  final String name;

  /// Trigger that determines when this schedule runs
  final ScheduleTrigger trigger;

  /// Executor for running systems
  final SystemExecutor executor;

  /// Optional: Maximum execution rate (executions per second) for diagnostics.
  ///
  /// If set and schedule exceeds this rate, a warning can be logged.
  /// Helps identify tight loops that may cause CPU overload.
  final double? maxExecutionRate;

  /// Marks this schedule as a hot path.
  ///
  /// When [World.enforceSoAForHotSchedules] is enabled, object components are
  /// rejected inside this schedule's query paths.
  bool isHotPath;

  /// Systems in this schedule
  final List<SystemDescriptor> _systems = [];

  /// Name of the last system added (for then() chaining)
  String? _lastSystemName;

  /// Counter for generating temporary names for systems.
  ///
  /// Design Decision: All systems get temporary names to enable dependency resolution.
  /// This ensures that then() creates proper dependency chains instead of relying
  /// on insertion order. Names like __add_0, __then_1 enable graph participation.
  int _tempNameCounter = 0;

  /// Cached execution groups (indices into _systems) - invalidated on changes
  List<List<int>>? _executionGroups;

  /// Execution rate tracking (for diagnostics)
  final List<double> _executionTimes = [];

  /// Get all systems in this schedule
  List<SystemDescriptor> get systems => List.unmodifiable(_systems);

  /// Add a system to the schedule.
  ///
  /// [name] is used for dependency resolution with [runAfter] and [runBefore].
  ///
  /// [runAfter] specifies system names that must run before this one.
  ///
  /// [runBefore] specifies system names that must run after this one.
  ///
  /// [mode] determines how the system executes (sync, async, etc.).
  Schedule add(
    final System system, {
    final String? name,
    final List<String> runAfter = const [],
    final List<String> runBefore = const [],
    final ExecutionMode mode = ExecutionMode.sync,
  }) {
    final assignedName = name ?? '__add_${_tempNameCounter++}';
    _systems.add(
      SystemDescriptor(
        system: system,
        name: assignedName,
        runAfter: runAfter,
        runBefore: runBefore,
        mode: mode,
      ),
    );
    _lastSystemName = assignedName;
    _invalidateCache();
    return this;
  }

  /// Add a certified job system to the schedule.
  Schedule addJobSystem(
    final CertifiedScheduleJobSystem jobSystem, {
    required final String name,
    final List<String> runAfter = const [],
    final List<String> runBefore = const [],
  }) {
    _systems.add(
      SystemDescriptor(
        system: _noopSystem,
        jobSystem: jobSystem,
        name: name,
        runAfter: runAfter,
        runBefore: runBefore,
      ),
    );
    _lastSystemName = name;
    _invalidateCache();
    return this;
  }

  /// Add multiple systems in order.
  ///
  /// Systems are added with incrementing priorities.
  Schedule addSystems(final List<System> systems) {
    systems.forEach(add);
    _invalidateCache();
    return this;
  }

  /// Clear all systems from this schedule.
  void clear() {
    _systems.clear();
    _lastSystemName = null;
    _invalidateCache();
  }

  /// Get current execution rate (executions per second).
  ///
  /// Returns null if insufficient data or tracking not enabled.
  double? getExecutionRate() {
    if (_executionTimes.length < 2) return null;

    final timeSpan = _executionTimes.last - _executionTimes.first;
    if (timeSpan <= 0) return null;

    final executions = _executionTimes.length - 1;
    return executions / timeSpan;
  }

  /// Add multiple systems that can run in parallel.
  ///
  /// All systems in the group are marked as parallelizable for async execution
  /// and can run concurrently at the same dependency level.
  Schedule parallel(
    final List<System> systems, {
    final ExecutionMode mode = ExecutionMode.asyncParallel,
  }) {
    for (final sys in systems) {
      _systems.add(
        SystemDescriptor(system: sys, canRunInParallel: true, mode: mode),
      );
    }
    _lastSystemName =
        null; // Parallel systems don't have a single "last" system
    _invalidateCache();
    return this;
  }

  /// Remove a system by name.
  bool removeSystem(final String name) {
    final initialLength = _systems.length;
    _systems.removeWhere((final desc) => desc.name == name);
    if (_systems.length < initialLength) {
      if (_lastSystemName == name) {
        _lastSystemName = null;
      }
      _invalidateCache();
    }
    return _systems.length < initialLength;
  }

  /// Run this schedule synchronously.
  ///
  /// If the schedule has a trigger, it will only execute if the trigger
  /// condition is met.
  ///
  /// Note: This method does not flush automatically. Developers must add
  /// phase systems (flushEntitiesSystem, flushCommandsSystem, etc.) to
  /// schedules explicitly to control when flushing occurs.
  void run(final World world) {
    if (!trigger.shouldRun(world)) return;

    if (maxExecutionRate != null) {
      _trackExecutionRate();
    }

    if (isHotPath) {
      world.enterHotSchedule();
    }
    try {
      final groups = _getExecutionGroups();
      executor.executeSchedule(world, name, groups, _systems);
    } finally {
      if (isHotPath) {
        world.exitHotSchedule();
      }
    }
  }

  /// Run this schedule asynchronously.
  ///
  /// Supports parallel and isolate execution modes.
  ///
  /// Note: This method does not flush automatically. Developers must add
  /// phase systems (flushEntitiesSystem, flushCommandsSystem, etc.) to
  /// schedules explicitly to control when flushing occurs.
  Future<void> runAsync(final World world) async {
    if (!trigger.shouldRun(world)) return;

    if (maxExecutionRate != null) {
      _trackExecutionRate();
    }

    if (isHotPath) {
      world.enterHotSchedule();
    }
    try {
      final groups = _getExecutionGroups();
      await executor.executeScheduleAsync(world, name, groups, _systems);
    } finally {
      if (isHotPath) {
        world.exitHotSchedule();
      }
    }
  }

  /// Toggle hot-path mode for this schedule.
  Schedule hotPath({final bool enabled = true}) {
    isHotPath = enabled;
    return this;
  }

  /// Add a system that runs sequentially after the last added system.
  ///
  /// This creates an implicit dependency to ensure sequential execution.
  /// Systems created by then() are assigned temporary names to enable
  /// dependency resolution, even when no explicit name is provided.
  Schedule then(final System system, {final String? name}) {
    final assignedName = name ?? '__then_${_tempNameCounter++}';
    return add(
      system,
      name: assignedName,
      runAfter: _lastSystemName != null ? [_lastSystemName!] : const [],
    );
  }

  /// Add a certified job system sequentially after the last added system.
  Schedule thenJobSystem(
    final CertifiedScheduleJobSystem jobSystem, {
    required final String name,
  }) => addJobSystem(
    jobSystem,
    name: name,
    runAfter: _lastSystemName != null ? [_lastSystemName!] : const [],
  );

  /// Get cached execution groups, computing them if necessary.
  List<List<int>> _getExecutionGroups() {
    if (_executionGroups != null) return _executionGroups!;

    final sorted = _resolveOrder();
    _executionGroups = _groupByDependencyLevel(sorted);
    return _executionGroups!;
  }

  /// Group system indices by dependency level for batch execution.
  ///
  /// Design Decision: Balance dependency ordering with parallel execution
  /// - Systems must execute in dependency order (topological sort guarantees this)
  /// - Systems marked canRunInParallel can execute concurrently within groups
  /// - This provides correctness + performance optimization
  List<List<int>> _groupByDependencyLevel(final List<int> indices) {
    if (indices.isEmpty) return [];

    // Group systems by their parallel execution capability
    // Systems that can run in parallel are grouped together
    final groups = <List<int>>[];
    var currentGroup = <int>[];

    for (final index in indices) {
      final desc = _systems[index];
      if (desc.canRunInParallel && currentGroup.isNotEmpty) {
        // Add to current parallel group
        currentGroup.add(index);
      } else if (desc.canRunInParallel) {
        // Start new parallel group
        if (currentGroup.isNotEmpty) {
          groups.add(currentGroup);
        }
        currentGroup = [index];
      } else {
        // Non-parallel system - each gets its own group
        if (currentGroup.isNotEmpty) {
          groups.add(currentGroup);
          currentGroup = [];
        }
        groups.add([index]);
      }
    }

    if (currentGroup.isNotEmpty) {
      groups.add(currentGroup);
    }

    return groups;
  }

  /// Invalidate the cached execution groups.
  void _invalidateCache() => _executionGroups = null;

  /// Resolve execution order based on dependencies using directed graph.
  ///
  /// Design Decision: Use directed_graph package instead of manual Kahn's algorithm
  /// - Proven correctness: Well-tested topological sorting
  /// - Better cycle detection: Detailed cycle paths vs simple count checks
  /// - Maintainability: No custom graph algorithm to maintain
  /// - Performance: Optimized for typical use cases (<100 systems)
  ///
  /// Graph Construction:
  /// - Vertices: Named systems (unnamed systems handled separately)
  /// - Edges: runAfter ['A'] creates A→current, runBefore ['B'] creates current→B
  /// - Topological ordering ensures correct execution sequence
  ///
  /// Returns list of system indices in topological order.
  List<int> _resolveOrder() {
    if (_systems.isEmpty) return [];

    // Build dependency graph for named systems
    final systemsByName = <String, int>{}; // name -> index
    final unnamed = <int>[]; // indices of unnamed systems

    for (var i = 0; i < _systems.length; i++) {
      final desc = _systems[i];
      if (desc.name != null) {
        systemsByName[desc.name!] = i;
      } else {
        unnamed.add(i);
      }
    }

    // Create directed graph for topological ordering
    final graphData = <String, Set<String>>{};
    for (final name in systemsByName.keys) {
      graphData[name] = <String>{};
    }

    final directedGraph = DirectedGraph<String>(
      graphData,
      comparator: (final a, final b) =>
          a.compareTo(b), // lexicographical ordering
    );

    // Add edges based on runAfter/runBefore dependencies
    for (final desc in _systems) {
      if (desc.name == null) continue;

      // runAfter: systemA must run before this system (A -> this)
      for (final after in desc.runAfter) {
        if (systemsByName.containsKey(after)) {
          directedGraph.addEdges(after, {desc.name!});
        }
      }

      // runBefore: this system must run before systemB (this -> B)
      for (final before in desc.runBefore) {
        if (systemsByName.containsKey(before)) {
          directedGraph.addEdges(desc.name!, {before});
        }
      }
    }

    // Check for cycles with detailed error message
    // Design Decision: Improved cycle detection vs previous count-based approach
    // Before: Only checked if sorted.length != systemsByName.length (no details)
    // After: Use DirectedGraph.isAcyclic + cycle() for actionable error messages
    // Example: [input_system, logic_system, output_system, input_system]
    if (!directedGraph.isAcyclic) {
      final cycle = directedGraph.cycle();
      throw CircularDependencyError(cycle);
    }

    // Get topological ordering
    final orderedNames = directedGraph.topologicalOrdering();

    // Convert names back to indices
    final sorted = <int>[];
    if (orderedNames != null) {
      for (final name in orderedNames) {
        sorted.add(systemsByName[name]!);
      }
    }

    // Add unnamed systems (they have no dependencies, so add them at the end)
    sorted.addAll(unnamed);

    return sorted;
  }

  /// Track execution rate for diagnostics.
  void _trackExecutionRate() {
    final now = DateTime.now().millisecondsSinceEpoch / 1000.0;
    _executionTimes.add(now);

    // Keep only recent executions
    if (_executionTimes.length > _maxTrackedExecutions) {
      _executionTimes.removeAt(0);
    }

    // Check if rate exceeds maximum
    if (_executionTimes.length >= 10) {
      final timeSpan = _executionTimes.last - _executionTimes.first;
      final executions = _executionTimes.length - 1;
      final rate = executions / timeSpan;

      if (rate > maxExecutionRate!) {
        // Log warning (in production, this could use a proper logger)
        // For now, we just track - developers can check getExecutionRate()
        // ignore: avoid_print - intentional low-overhead diagnostics path
        print(
          'Warning: Schedule "$name" executing at ${rate.toStringAsFixed(1)}/s, '
          'exceeds max rate of $maxExecutionRate/s. Consider using '
          'ThrottledTrigger or EveryNFrames.',
        );
      }
    }
  }
}
