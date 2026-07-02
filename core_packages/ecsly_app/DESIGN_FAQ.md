# Design Decisions FAQ - ecsly_app

Quick reference for **why** this package exists and where its boundary lies.

## Publication status

**Q: Is this package live on pub.dev?** A: Not yet. `ecsly_app` is
publish-prepared and versioned as a prerelease, but
reader-facing docs should describe it as unpublished until the hosted package is
verified.

## Why this package exists

**Q: Why not put actions and drafts in `ecsly` core?**  
A: App workflows carry wall-clock time, arbitrary results/errors, stack traces,
validation state, and host notification concerns. Core ECS stays deterministic
and summary-free in hot paths.

**Q: Why not keep everything in `ecsly_flutter`?**  
A: Jaspr, CLI tools, tests, and headless apps need the same app contracts without
a Flutter dependency.

**Q: Why re-export `ecsly`?**  
A: App hosts usually need both runtime and app APIs in one import. Simulation-only
packages should depend on `ecsly` directly.

## Actions vs commands

**Q: When is `EcsAction` correct?**  
A: Hydration, submit, sign-in, save draft, optimistic sync, feature-owned spawn
flows — reusable use-cases with async status.

**Q: When is `EcsCommand` correct?**  
A: Deferred structural ECS mutations inside simulation schedules.

**Q: Why store action status in a Resource?**  
A: Hosts observe status through normal ECS selectors/notifiers instead of a
parallel global store.

## Invalidation

**Q: Why is invalidation outside core ECS?**  
A: Hot worlds should not pay for UI refresh bookkeeping. Hosts opt into
`EcsInvalidationBatch` when they want selective rebuilds.

**Q: What happens when an action forgets invalidation hints?**  
A: `invalidationOrBroad()` tells hosts to refresh broadly — safe default.

## Identity and lookup

**Q: Why `EntityIndexResource` instead of core world ids?**  
A: Stable app/domain ids are component data. Runtime `Entity` handles are
generational and not stable across despawn/spawn. Indexes are optional cold
projections maintained by feature code.

**Q: Why cold `findEcsEntityWithComponent`?**  
A: Screens and actions need occasional predicate lookup without building a
query cache. Hot systems must use cached queries.

## Repository consistency

**Q: What should be documented on API changes?**  
A: Update [DX_FAQ.md](DX_FAQ.md) for usage, [DESIGN_FAQ.md](DESIGN_FAQ.md) for
boundary shifts, and [CHANGELOG.md](CHANGELOG.md) on release.
