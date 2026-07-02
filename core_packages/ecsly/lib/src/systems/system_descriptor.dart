import 'certified_job_system.dart';
import 'isolate_config.dart';
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
    this.jobSystem,
    this.name,
    this.runAfter = const [],
    this.runBefore = const [],
    this.canRunInParallel = false,
    this.mode = ExecutionMode.sync,
    this.isolateConfig,
  });

  /// The system function to execute
  final System system;

  /// Optional certified job system used by async schedules.
  ///
  /// Sync schedule execution falls back to [runSerial] semantics.
  final CertifiedScheduleJobSystem? jobSystem;

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

  /// Configuration for isolate execution.
  ///
  /// This is only used by the current non-production isolate placeholder path.
  final IsolateConfig? isolateConfig;

  /// Create a copy with updated values
  SystemDescriptor copyWith({
    final System? system,
    final CertifiedScheduleJobSystem? jobSystem,
    final String? name,
    final List<String>? runAfter,
    final List<String>? runBefore,
    final bool? canRunInParallel,
    final ExecutionMode? mode,
    final IsolateConfig? isolateConfig,
  }) => SystemDescriptor(
    system: system ?? this.system,
    jobSystem: jobSystem ?? this.jobSystem,
    name: name ?? this.name,
    runAfter: runAfter ?? this.runAfter,
    runBefore: runBefore ?? this.runBefore,
    canRunInParallel: canRunInParallel ?? this.canRunInParallel,
    mode: mode ?? this.mode,
    isolateConfig: isolateConfig ?? this.isolateConfig,
  );
}
