# core_packages/ecsly: Agent Working Agreement

## Goal

Near-native iteration performance in Dart: minimize GC in hot loops and maximize
cache locality.

## Hot-Loop Constraints (Do/Don't)

- Do store hot data in columns backed by `Float32List`, `Int32List`, `Uint8List`,
  etc.
- Do flatten fixed-size structs (stride packing) and keep SIMD alignment in mind.
- Don't allocate per-entity heap objects in hot systems.
- Do store enums as integers and strings/variable-length data as IDs/handles in
  hot paths.
- Do prefer cached query results; avoid per-iteration `Map` lookups.
- Use `ObjectColumn<T>` only for cold data where GC/caching trade-offs are fine.

## Core Invariants

- Archetype storage + migration trade-off is intentional (iteration wins).
- `Entity` is a 64-bit generational ID (index + generation); stale IDs are part
  of the safety model.
- Structural changes are deferred via command queue; flush semantics must remain
  correct.

## Where Things Live

- Archetypes: `core_packages/ecsly/lib/src/archetypes/`
- Entities: `core_packages/ecsly/lib/src/entities/`
- Components/queries: `core_packages/ecsly/lib/src/components/`
- Commands: `core_packages/ecsly/lib/src/commands/`
- Systems/schedules: `core_packages/ecsly/lib/src/systems/`
- Events: `core_packages/ecsly/lib/src/events/`

## Testing

- Default: `cd core_packages/ecsly && dart test`
- Add tests under `core_packages/ecsly/test/` and match existing style.

## Docs To Update When You Change Internals

If you change archetypes/entities/flush/query semantics, update:

- `core_packages/ecsly/doc/ecs_architecture_diagram.md`
- `core_packages/ecsly/DESIGN_FAQ.md`

If you change public usage patterns, update:

- `core_packages/ecsly/DX_FAQ.md`
