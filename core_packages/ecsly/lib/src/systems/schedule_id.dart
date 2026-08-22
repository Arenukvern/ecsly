/// Typed, zero-cost identifier for a schedule.
///
/// [ScheduleId] is a const wrapper over [String]. It exists so schedule
/// references become greppable, typo-safe constants instead of magic strings,
/// while keeping the runtime representation identical: registry lookups still
/// key off the underlying string, so there is no hot-path cost.
///
/// Define package-owned vocabularies as constants so hosts and plugins compose
/// schedules explicitly:
///
/// ```dart
/// abstract final class GameSchedules {
///   static const input = ScheduleId('input');
///   static const simulation = ScheduleId('simulation');
/// }
///
/// world.createSchedule(GameSchedules.simulation).add(movementSystem);
/// world.runSchedule(GameSchedules.simulation);
/// ```
///
/// Cross-package composition benefits most: a plugin exports its own ids
/// (`PhysicsSchedules.step`) and hosts order against them without sharing
/// string literals.
extension type const ScheduleId(String value) {
  /// Runs before the main update stage.
  static const ScheduleId preUpdate = ScheduleId('preUpdate');

  /// Main update stage. The default schedule used across ecsly examples.
  static const ScheduleId update = ScheduleId('update');

  /// Runs after the main update stage.
  static const ScheduleId postUpdate = ScheduleId('postUpdate');

  /// High-frequency stage used by the built-in debug/performance plugin.
  static const ScheduleId highFrequency = ScheduleId('HighFrequency');
}
