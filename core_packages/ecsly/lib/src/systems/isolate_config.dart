import '../world/world.dart';

/// {@template isolate_config}
/// Configuration for running a system in an isolate.
///
/// Defines how to transfer data to the isolate, the function to run,
/// and how to apply results back to the world.
/// {@endtemplate}
class IsolateConfig {
  /// {@macro isolate_config}
  const IsolateConfig({
    required this.transferData,
    required this.isolateFunction,
    required this.applyResults,
  });

  /// Extract data from the world to send to the isolate
  final dynamic Function(World world) transferData;

  /// The function to run in the isolate
  // ignore: avoid_annotating_with_dynamic
  final dynamic Function(dynamic data) isolateFunction;

  /// Apply the results back to the world
  // ignore: avoid_annotating_with_dynamic
  final void Function(World world, dynamic results) applyResults;
}
