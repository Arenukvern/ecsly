# ecsly_world_zones

Zone-travel adapter for [ecsly](https://pub.dev/packages/ecsly) worlds
([ADR 0003](../../docs/decisions/0003_world_zones_seamless_travel.md)): the
mesh sync pulse as an **ordinary ecsly system** driven by the game's own
scheduler, and interest policies (zone census, spatial) over the world-layer
contract ([`universal_storage_world`](https://pub.dev/packages/universal_storage_world)).

In the repo, in active development; not published (`publish_to: none`).
Depend on it through the pub workspace inside this repo, or via a git
dependency outside it. 8 tests cover the pulse system and both interest
policies.

## What it does

Three surfaces, all deliberately thin:

- **`WorldZonesPlugin`** — the one-call install: registers the mesh pulse
  schedule into a world (`world.addPlugin(WorldZonesPlugin(session))`);
  `removePlugin` removes the schedule again.
- **`meshPulseSystem` / `registerMeshPulseSchedule`** — the mesh sync pulse
  as an ordinary ecsly system. There is no new scheduler here: the pulse
  composes with whatever loop the game already runs (`ecsly_flutter`'s frame
  schedule, `ecsly_app`'s host schedule, a test's manual `runAsync`), because
  the world layer's scheduling law is host-driven (`Pulseable`) — the layer
  never owns a loop.
- **`ZoneCatalogInterest` / `SpatialInterestPolicy`** — interest policies over
  the world-layer contract. The zone census subscribes a whole zone from its
  catalog doc; spatial interest delegates membership to a game query, so
  positions live in the world and never in the storage family.

```dart
final session = MeshWorldSession(storage: storage, selfId: peerId);
world.addPlugin(WorldZonesPlugin(session, trigger: EveryNSeconds(1)));
```

## Dependencies

`universal_storage_world` is published on pub.dev (`0.1.0-dev.1`,
2026-10-12) and resolves as an ordinary hosted dependency; `ecsly` resolves
through the pub workspace.

## Validate

```sh
dart pub get        # from the repo root (pub workspace)
cd plugins/ecsly_world_zones
dart analyze
dart test           # 8 tests
```

## Design record

- [ADR 0003 — zone travel: the mesh pulse is an ordinary system; interest
  policies stay game-side](../../docs/decisions/0003_world_zones_seamless_travel.md)
