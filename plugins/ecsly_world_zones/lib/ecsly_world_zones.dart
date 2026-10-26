/// Zone-travel adapter for ecsly worlds (ADR 0003; the game-side face of
/// the world layer, ADR 0047).
///
/// Two pieces, both deliberately thin:
///
/// - [meshPulseSystem] / [registerMeshPulseSchedule]: the mesh sync pulse
///   as an ORDINARY ecsly system. There is no new scheduler here — the
///   pulse composes with whatever loop the game already runs
///   (`ecsly_flutter`'s frame schedule, `ecsly_app`'s host schedule, a
///   test's manual `runAsync`), because the world layer's scheduling law
///   is host-driven (`Pulseable`): the layer never owns a loop.
/// - [ZoneCatalogInterest] / [SpatialInterestPolicy]: interest policies
///   over the world-layer contract. The zone census subscribes a whole
///   zone from its catalog doc; spatial interest delegates membership to
///   a game query — positions live in the world, never in the storage
///   family.
library;

export 'src/mesh_pulse_system.dart';
export 'src/zone_interest.dart';
