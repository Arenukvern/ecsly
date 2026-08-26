# ecsly — performance-oriented Dart ECS

Distilled canonical of `core_packages/ecsly`: a deterministic, low-GC
Entity Component System runtime.

## Decomposition

- **world/** — the World facade binding all registries; structural batching.
- **archetypes/** — signature-keyed columnar storage; bulk ops; resolver.
- **entities/** — id allocation, generations, liveness.
- **commands/** — deferred structural changes, applied at flush.
- **components/** — object components + typed SoA extension columns.
- **resources/** — global singletons with change batching.
- **events/** — typed pub/sub.
- **systems/** — schedules, phases, triggers, executors, registries.
- **extraction/** — query/component extraction helpers.
- **plugins/** — world plugin installation.
- **debug/** — execution/flush observers (telemetry).

## Cross-cutting guarantees

deterministic-structural-changes · low-gc-hot-path · no-flutter-in-core ·
three-lane-api (see proposed_concepts).
