import 'ecs_invalidation_batch.dart';

typedef EcsHostSchedulePredicate =
    bool Function(EcsInvalidationBatch triggerInvalidation);

/// Host-facing schedule metadata for app and Flutter integrations.
///
/// This is an explicit contract: hosts use [invalidation] to notify UI or
/// integration layers about what the schedule may change. Core ECS does not
/// infer or track these mutations.
final class EcsHostSchedule {
  const EcsHostSchedule(
    this.name, {
    this.invalidation,
    this.runWhen,
  });

  final String name;
  final EcsInvalidationBatch? invalidation;
  final EcsHostSchedulePredicate? runWhen;

  bool shouldRun(final EcsInvalidationBatch triggerInvalidation) =>
      runWhen?.call(triggerInvalidation) ?? true;
}
