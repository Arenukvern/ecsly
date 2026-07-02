# ecsly_flutter Design FAQ

## Publication status

**Q: Is this package live on pub.dev?** A: Not yet. `ecsly_flutter` is
publish-prepared and versioned as a prerelease, but reader-facing docs should
describe it as unpublished until the hosted package is verified.

## Why is this package small?

`ecsly_flutter` is a bridge, not a game framework and not a replacement for all
Flutter app architecture. Its job is to connect an ecsly `World` to Flutter
widget rebuilds, app actions, draft state, and optional schedule driving.

The package boundary is defined by public package contracts and host requirements.

## Why keep `Ecs` in Flutter API names?

Flutter developers should recognize the shape, but the semantics are ECS-owned.
`context.selectEcsResource` and `context.selectEcsComponent` are explicit about
where the value comes from. Unqualified `watch/read` names would hide the fact
that rebuilds happen when `EcsController` notifies after transactions, actions,
or loop ticks.

## Why add component selectors?

Without component selectors, examples naturally drift toward one giant resource
that stores all UI/domain state. That defeats the point of ECS. Component
selectors make the normal path ergonomic: slice domain state into components and
let Flutter rebuild from selected values.

Direct component lookup by `Entity` lives in `ecsly` core. Cold
predicate-to-entity lookup lives in `ecsly_app` because it is app/UI cadence
behavior, not core simulation identity. `ecsly_flutter` reexports that app
surface for convenience. Stable app ids should be normal components; optional
typed projections such as `EntityIndexResource<TodoIds, String>` only help
screens/actions resolve an id to the current runtime entity.

## What belongs in resources?

Resources should be small world singletons: frame time, viewport/session state,
selected ids, filters, status tables, queues, caches, policies, and host
coordination. A resource can index entities, but repeated/domain state should
usually live on those entities as components.

`EntityIndexResource<TScope, K>` is intentionally data-only and experimental. It
maps app ids to entities for one typed id space, but it does not own item
payloads, UI controllers, callbacks, business logic, or the persistent identity
itself. The feature plugin or action helper that owns that id space must update
the projection when entities are spawned, despawned, or re-identified.

## Why call reusable app logic `EcsAction` instead of `Command`?

Core `EcsCommand` already means deferred structural mutation interpreted by the
command queue. App logic has a different contract: async work, services,
validation, status, cancellation, optimistic updates, and domain results.
`EcsAction` keeps those concepts separate.

## Why not ship a Material `EcsActionButton`?

The base bridge is toolkit-neutral. `EcsActionBuilder` exposes status and a run
callback so Material, Cupertino, game HUDs, and custom design systems can build
their own controls without extra dependencies.

## Why not depend on broader game bundles?

Broader game bundles would pull camera, input, collision, rendering, HUD, and
debug concepts into normal app installs.

## Why app-neutral loop names?

The same Flutter binding should serve apps and games. `EcsLoop` and
`EcsFixedStepLoop` describe how the ECS world is driven without telling app
developers they are using a game-only package.

Loop invalidation is host-declared for the same reason. Core ECS does not track
semantic component/resource writes, so unknown schedules remain broad. A host
that owns a schedule can provide an app-layer `EcsInvalidationBatch` for
selective Flutter rebuilds without adding revision maps to core.

## Why are actions and drafts in `ecsly_app` instead of core?

`EcsAction` carries app/host status details such as wall-clock timestamps,
arbitrary result/error objects, and stack traces. `EcsDraft` carries validation
and edit state. Both are useful for Flutter, Jaspr, Flame, CLI tools, and tests,
but they are not deterministic simulation machinery.

`ecsly_app` is the shared pure Dart layer for those app contracts. Core stays
focused on ECS storage, scheduling, commands, and hot/warm query behavior.
