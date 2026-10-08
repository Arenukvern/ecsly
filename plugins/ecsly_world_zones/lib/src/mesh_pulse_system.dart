import 'package:ecsly/ecsly.dart';
import 'package:universal_storage_world/universal_storage_world.dart';

/// The mesh sync pulse as an ORDINARY ecsly system (ADR 0003 §1; the
/// host-driven scheduling law is ADR 0047 §4).
///
/// There is no new scheduler to adopt: [AsyncSystem] is ecsly's own
/// typedef, so the pulse composes with whatever loop the game already
/// runs — `ecsly_flutter`'s frame schedule, `ecsly_app`'s host schedule,
/// a headless test's `runAsync`. The world layer never owns a loop; the
/// game keeps every scheduling decision, including "don't pulse while
/// loading" (just don't register the schedule yet) and "pulse per tick"
/// ([ThrottledTrigger] over [EveryFrame]).
///
/// ```dart
/// final session = MeshWorldSession(storage: storage, selfId: peerId);
/// registerMeshPulseSchedule(world, session, trigger: EveryNSeconds(1));
/// ```
AsyncSystem meshPulseSystem(final Pulseable pulse) =>
    (final World world) async {
      await pulse.pulse();
    };

/// The schedule id [registerMeshPulseSchedule] registers under.
const meshPulseScheduleId = ScheduleId('mesh-pulse');

/// Wires the pulse into [world]'s systems registry under its own
/// schedule, driven by [trigger] (default: every 30 seconds — the
/// pre-0047 app cadence; `EveryNSeconds` is stateful, so the default is
/// applied at registration time). The game's existing scheduler runs it
/// like any other schedule. Safe to call once per world; calling it twice
/// returns the same schedule (the second [add] is a no-op duplicate
/// system, so prefer the once-per-world pattern of a plugin's `add`).
Schedule registerMeshPulseSchedule(
  final World world,
  final Pulseable pulse, {
  ScheduleTrigger? trigger,
}) {
  final schedule = world.systems.getOrCreateSchedule(
    meshPulseScheduleId,
    trigger: trigger ?? EveryNSeconds(30),
  );
  schedule.add(meshPulseSystem(pulse), name: 'mesh-pulse');
  return schedule;
}
