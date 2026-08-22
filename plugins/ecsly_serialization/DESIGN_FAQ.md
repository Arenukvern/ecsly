# Design FAQ — ecsly_serialization

## Why JSON maps instead of binary?

JSON keeps the format debuggable, diffable, and versionable. The SoA columns
are read/written through their typed accessors so no reflection or dynamic
field access is needed on the hot path. A binary column codec can be added
later behind the same `WorldSnapshot` envelope without breaking the API.

## Why does restore require pre-spawned entities?

Structural identity (which archetype an entity belongs to) depends on
registration order and spawn sequence, which are app concerns. Serializing
state only keeps the plugin small and avoids duplicating spawn logic. The
snapshot stores each entity's index/generation so handles stay valid when the
target world reproduces the same layout.

## Why per-type codecs for object components?

Object columns hold heap objects whose shape only the app knows. A registry of
`ObjectComponentCodec`s keeps core serialization generic while letting apps opt
in per type.

## Why is this a plugin package, not part of core?

Core `ecsly` stays pure runtime (entities, archetypes, schedules). Serialization
is a companion concern like codegen or Flutter bridges, matching the repo's
package-boundary rules.
