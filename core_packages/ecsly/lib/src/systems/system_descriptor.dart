import 'system.dart';

/// {@template system_descriptor}
/// Metadata describing how a system should be executed.
///
/// Contains information about execution order, dependencies,
/// parallelization, and execution mode.
/// {@endtemplate}
class SystemDescriptor {
  /// {@macro system_descriptor}
  const SystemDescriptor({
    required this.system,
    this.name,
    this.runAfter = const [],
    this.runBefore = const [],
    this.canRunInParallel = false,
    this.mode = ExecutionMode.sync,
  });

  /// The system function to execute
  final System system;

  /// Optional name for the system (used for dependencies)
  final String? name;

  /// Names of systems that must run before this one
  final List<String> runAfter;

  /// Names of systems that must run after this one
  final List<String> runBefore;

  /// Whether this system can run in parallel with others at the same dependency level
  final bool canRunInParallel;

  /// How this system should be executed
  final ExecutionMode mode;

  /// Create a copy with updated values
  SystemDescriptor copyWith({
    final System? system,
    final String? name,
    final List<String>? runAfter,
    final List<String>? runBefore,
    final bool? canRunInParallel,
    final ExecutionMode? mode,
  }) => SystemDescriptor(
    system: system ?? this.system,
    name: name ?? this.name,
    runAfter: runAfter ?? this.runAfter,
    runBefore: runBefore ?? this.runBefore,
    canRunInParallel: canRunInParallel ?? this.canRunInParallel,
    mode: mode ?? this.mode,
  );
}
