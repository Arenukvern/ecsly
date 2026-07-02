# Design Decisions FAQ

Quick reference for architectural choices and rationale. Focus: **why**
decisions were made, not how to use the API.

## Core Performance Objective

**Q: What is the primary performance objective?**  
A: Minimize GC in hot loops and maximize CPU cache locality in Dart. The current
evidence is local benchmark data, so public claims should describe measured
local scorecards separately from long-term scale targets.

## Unified Extraction Contracts

**Q: Why does core now expose deterministic extraction sort/hash helpers?**  
A: Render/collision extraction is now shared across 2D/2.5D/3D plugins. Core owns ordering and section-hashing primitives so packet parity checks are consistent between hosts and plugins.

**Q: Why add `WorldDeterminismResource`?**  
A: It provides optional frame-level diagnostics (world hash, packet hash, section hashes, ordering violations) without changing archetype/flush internals. It is opt-in telemetry for replay/debug parity checks.

**Q: What render contract does core expose?**
A: The public core package exposes deterministic ordering and hashing helpers
that plugins can use for replay/debug parity. It does not export a render scene,
render packet resource, transform component vocabulary, or graphics ABI.

**Q: Where should render-packet and graphics ABI details live?**
A: In the plugin or host package that owns those symbols. Core docs should only
describe the reusable extraction primitives present in `package:ecsly`, so
pub.dev readers do not infer private/plugin transport APIs from the runtime
package.

## Storage Architecture

**Q: Why archetype-based storage instead of sparse sets?**  
A: Optimizes iteration speed (hot path) over mutation speed (cold path). Cache-friendly columnar storage enables SIMD. Trade-off: Entity migration cost acceptable for 60fps iteration.

**Q: Why Structure of Arrays (SoA) with dart:typed_data?**  
A: Eliminates GC in hot loop, maximizes cache locality, enables SIMD. Components stored as Float32List/Int32List, not heap objects.

**Q: Why column abstraction (FloatColumn/IntColumn/ObjectColumn)?**  
A: Unified interface preserving performance. FloatColumn enables SIMD, ObjectColumn handles complex types. Trade-off: ObjectColumn triggers GC but only for cold data.

**Q: Why flatten complex types (Rect → 4 floats) instead of storing objects?**  
A: Maintains SoA layout, enables SIMD. No heap allocation for hot-path data. Trade-off: More verbose API.

**Q: Why ObjectColumn for complex types (Strings, Lists) instead of forcing SoA?**  
A: Some data cannot be flattened. ObjectColumn provides sparse storage for cold data. Trade-off: Triggers GC but only for non-hot-path components.

**Q: Why use Uint8List for enums and small integers?**  
A: 4x memory reduction vs Int32List, better cache locality (64 vs 16 values per cache line).

**Q: Why swap-and-pop when removing entities?**  
A: Maintains dense arrays, prevents fragmentation. O(1) removal cost vs O(n) compaction.

## Event System

**Q: Why events stored in DataColumns instead of Lists?**  
A: Reuses existing column infrastructure (FloatColumn/IntColumn/ObjectColumn) for zero-GC storage and SIMD compatibility. Ring buffers on dense arrays provide O(1) send/read with cache-friendly access.

**Q: Why TypedDataEvent interface for zero-GC events?**  
A: Enables automatic FloatColumn/IntColumn storage for numeric events, eliminating heap allocation in hot loops. Trade-off: Requires factory function and sample event for registration.

**Q: Why frame-bound event lifecycle (clear at end of frame)?**  
A: Events are transient signals, not persistent state. Frame-bound clearing prevents memory leaks and ensures consistent iteration semantics. Trade-off: Events don't persist across frames.

**Q: Why per-world TypedDataEventRegistry instead of singleton?**  
A: Ensures isolation between multiple worlds. Type objects are compile-time constants, safe for multi-world isolation. Prevents cross-world event type contamination.

**Q: Why per-world ComponentFacadeRegistry/ColumnFactoryRegistry instead of singleton?**  
A: `ComponentId` values are world-local and assigned in registration order. A singleton registry lets different worlds overwrite each other's `ComponentId -> factory` mapping, causing runtime type mismatches. Per-world registries preserve isolation and make multi-world replay/editor setups deterministic.

**Q: Why ring buffer for event channels instead of growable lists?**  
A: Fixed capacity prevents unbounded growth, ring buffer provides O(1) send/read. Capacity policies (dropOld/dropNew/throwOnOverflow) handle overflow gracefully. Trade-off: Fixed capacity vs dynamic allocation.

## Entity Management

**Q: Why 64-bit Entity ID with index + generation?**  
A: Index (32-bit) enables O(1) array access. Generation (32-bit) detects stale references after despawn/respawn, preventing use-after-free bugs without complex validation.

**Q: Why can't we use Entity.index directly to access components?**  
A: Entities migrate between archetypes when components change. Must use location lookup (ArchetypeId + Row) for O(1) access. Direct index would point to wrong archetype after migration.

**Q: Why location tracking (ArchetypeId + Row) instead of direct component storage?**  
A: Entities move between archetypes when component signature changes. Location map provides O(1) lookup. Trade-off: Extra indirection enables archetype migration.

**Q: Why parallel Uint32List arrays for location tracking instead of Map?**  
A: Parallel arrays provide cache-friendly O(1) access via entity index. Map lookups trigger hash computation and cache misses.

**Q: Why free-list for entity recycling?**  
A: Reuses entity indices after despawn, preventing unbounded growth. Generation counter invalidates stale references.

**Q: Why generational validation instead of just checking if entity exists?**  
A: Index recycling reuses entity indices. Generation counter prevents stale references from accessing wrong data. Trade-off: 64-bit entity ID enables safe index reuse.

**Q: Why ensureFlushed() before getEntity/getEntityMut?**  
A: Commands may change entity locations. Flush ensures location map is current. Trade-off: Conditional flush overhead (<5%) vs manual flush complexity.

**Q: Why ensureFlushed() called automatically in queries?**  
A: Eliminates manual flush calls, prevents stale data bugs. Conditional flush (<5% overhead) only executes when changes pending.

## Component System

**Q: Why ComponentMask 256-bit limit (4 Uint64s)?**  
A: Balance between memory (32 bytes) and component count. Supports 256 components, sufficient for most games. Bitwise operations are O(1).

**Q: Why register component types before use?**  
A: Registration maps a Dart component type to a compact `ComponentId` and chooses
its storage strategy. Archetype signatures, query masks, and column lookup all
depend on those IDs being known before data is inserted.

**Q: Why extension types vs classes for components?**  
A: Extension types are zero-cost facades (compile away), classes provide runtime type identity. Trade-off: Extension types need separate class for ComponentId lookup, classes allocate on heap.

**Q: Why does an extension component need both marker and facade types?**  
A: The marker component gives the ECS runtime stable type identity for
registration, archetype signatures, and queries. The facade gives user code
typed access to packed column data. This is why APIs use
`queryExt<EnergyComponent, Energy>()`: one type selects storage, the other
selects the typed view.

**Q: Why do SIMD examples use stride-4 FloatColumn storage?**  
A: Dart SIMD exposes `Float32x4` lanes. A `FloatColumn(stride: 4)` maps one
entity row to one SIMD lane, so systems can update four numeric fields with one
vector operation. Trade-off: component shape is constrained by SIMD lane width.

**Q: Why are commands deferred instead of mutating archetypes immediately?**  
A: Immediate structural mutation can invalidate active iterators and make system
ordering hard to reason about. Deferred commands let systems request
spawn/despawn/insert/remove safely, then `flush()` applies the batch at a known
boundary.

**Q: Why use resources for global state instead of singleton components?**  
A: Resources model world-level state directly: clocks, policies, data queues,
outboxes, caches, and settings. They avoid creating special entities just to
hold global data and provide direct registry lookup. Command queues, callbacks,
system registration, and domain behavior should stay outside resource objects.

**Q: Why not use extension components for every example?**  
A: Object components are easier to read and are appropriate for cold data.
Extension components are a deliberate hot-path choice. Showing both helps users
avoid over-optimizing early while still understanding the low-GC path.

**Q: Why separate WorldEntity and WorldEntityMut?**  
A: Clear semantics: structural changes (archetype migration) vs data mutations (in-place updates). Prevents accidental archetype changes during hot loops.

**Q: Why WorldEntityExtension wrapper?**  
A: Extension types erase to base type (int), losing runtime type identity. Wrapper provides type-safe access with runtime validation.

**Q: Why `create()` method for zero-cost component creation?**  
A: Synchronous zero-initialized creation enables zero-cost extension type facades. Trade-off: Requires immediate flush vs deferred command queue.

**Q: Why `getEntityExtension()` convenience method?**  
A: Provides direct access to extension wrapper without intermediate `getEntity().toExtension()` call. Improves ergonomics for extension type workflows.

**Q: Why `getOrCreate()` method?**  
A: Combines getExtension and create for convenience. Reduces boilerplate when component may or may not exist.

## Query System

**Q: Why query-driven auto-flush instead of manual flush?**  
A: Eliminates manual flush calls, prevents stale data bugs. Conditional flush (<5% overhead) only executes when changes pending.

**Q: Why query result caching?**  
A: Archetype matching is O(archetypes). The public contract is topology/query
revision only, not host-facing component or resource change tracking. Internally
the cache keeps query-shaped data such as matched archetypes and optional entity
result entries; those entries are invalidated by flush/archetype version and
component-mask intersection, not exposed as UI observation state.

**Q: What does structural touch tracking mean in QueryCache?**
A: It is an internal cache-eviction hint after a structural write touched a
component type. QueryCache caches matching archetypes and, for entity-list
queries, cached entity lists valid for the current structural/flush versions.
This is not semantic mutation tracking or UI invalidation.

**Q: Why was `ArchetypeMatchResult.allEntities` removed?**  
A: It was dead payload in core runtime hot paths and caused avoidable list churn
per archetype-match cache fill. Archetype matching now stores matched archetypes
and lets hot iterators stream rows directly; any separate entity-result cache is
an internal implementation detail for entity-list queries.

**Q: Why ComponentMask-based queries instead of Type-based?**  
A: Bitwise operations are O(1) vs Type comparison. Enables efficient archetype matching and query caching.

**Q: Why queryExt methods that return explicit extension types?**  
A: Eliminates runtime casting, provides compile-time type safety. Zero-allocation extension type facades. Trade-off: More verbose type parameters.

**Q: Why predicate-based queries (queryExtWhere) instead of manual filtering?**  
A: Predicate filtering happens at column iteration level, eliminating manual if-checks in hot loops. Reduces cache misses and branch prediction failures.

## Flush System

**Q: Why flush order: entities → components → resources → commands?**  
A: Commands may access components/resources. Components depend on flushed entities. Fixed order prevents dependency bugs.

**Q: Why flush again after commands execute?**  
A: Commands may create new pending changes. Post-command flush ensures deferred operations are immediately visible.

**Q: Why prevent recursive flushing during command execution?**  
A: Commands may trigger queries that would auto-flush. `isFlushing` flag prevents infinite flush-during-flush cycles.

**Q: Why conditional flushing instead of always flushing?**  
A: O(changed entities) cost, not O(all entities). Negligible overhead (~1-5%) when no changes.

**Q: Why queryExt methods auto-flush before querying?**  
A: Ensures queries see latest state without manual flush calls. Conditional flush (<5% overhead) only when changes pending. Prevents stale data bugs.

**Q: Why explicit flushAllWithTimingSystem needed at end of schedules?**  
A: Commits all pending changes at frame boundary. Required when multiple systems modify state. queryExt auto-flush handles mid-schedule queries, frame-end flush ensures consistency.

## System Ordering

**Q: Why dependency-based ordering instead of numeric priorities?**  
A: Explicit relationships over magic numbers. Automatic cycle detection with detailed errors. Guarantees correctness.

**Q: Why directed graph for system dependencies?**  
A: Proven correctness via well-tested algorithms. Better cycle detection with path reporting.

## Performance Optimizations

**Q: Why SIMD requirements (stride multiple of 4)?**  
A: Float32x4 operations process 4 floats simultaneously. Stride alignment enables vectorization. Trade-off: Component design constraints vs 4x performance gain.

**Q: Why command queue for structural changes?**  
A: Batches archetype migrations, prevents changes during iteration. Commands validated before execution. Prevents iterator invalidation bugs.

**Q: Why drain command queue in-place instead of cloning before execute?**  
A: Full-queue cloning scaled with queue length and inflated flush latency. In-place draining preserves deferred semantics while removing one hot allocation path per flush.

**Q: Why no implicit `DateTime.now()` fallback for time-based triggers?**  
A: Deterministic simulation requires explicit time inputs. Core triggers now require `ScheduleTimeResource` (preferred), optional `DeltaTimeResource` (compatibility adapter), or explicit `WallClockScheduleTimeResource` opt-in for non-deterministic runtime adapters.

**Q: Why batch operations (addEntities/removeEntities)?**  
A: Reduces overhead from repeated archetype lookups. Single migration pass for multiple entities. Trade-off: Batch API complexity vs O(k²) sequential cost.

## Error Handling

**Q: Why Error vs Exception separation (EcsStateError vs EcsException)?**  
A: Follows Dart best practices: StateError signals programming mistakes, Exception signals recoverable conditions. Prevents defensive try-catch in hot paths.

**Q: Why specific error types (EntityNotFoundError, ComponentNotFoundError) instead of generic errors?**  
A: Provides clear debugging context (entity ID, component type) without performance cost. Enables precise error handling and faster diagnosis.

**Q: Why StateError base class instead of custom error hierarchy?**  
A: Signals programming mistakes that indicate bugs, not recoverable failures. Matches Dart conventions. Prevents defensive try-catch patterns.

**Q: Why context fields in error classes (entity, componentType, archetypeId)?**  
A: Better error messages without performance overhead. Errors only thrown in cold paths (validation), so context capture is free.

## Plugin System

**Q: Why separate feature packages from core ECS?**
A: Framework-agnostic feature packages enable reuse across hosts, while
framework-specific packages can add widgets/components without duplicating core
logic. Trade-off: multiple packages vs a monolithic runtime package.

**Q: Why plugin registry prevents duplicate installations?**  
A: Plugins register resources/systems. Duplicate installation would create duplicate resources or systems, causing conflicts. Name-based tracking enables safe re-installation checks.

**Q: When should I use `addPluginIfAbsent` instead of `addPlugin`?**
A: Use `addPlugin` for strict bootstrap where a duplicate is a bug. Use
`addPluginIfAbsent` for optional dependency/bootstrap installation where the
same feature may have been installed by the host or another plugin. Runtime
replacement should stay explicit: call `removePlugin(name)` and then
`addPlugin(plugin)` so uninstall/install side effects are visible.

**Q: Why plugins install resources/systems instead of direct registration?**  
A: Encapsulates feature setup (resources, systems, schedules) into reusable bundles. Enables modular composition without manual setup. Trade-off: Plugin abstraction vs direct control.

## Package Ecosystem

**Q: Why separate packages for plugins, algorithms, and isolates?**
A: Enables modular composition and independent evolution. Core ECS focuses on data structures, plugins add game logic, algorithms provide pure computation, isolates handle concurrency. Trade-off: Package complexity vs monolithic coupling.

**Q: Why keep plugin-style features out of core?**
A: Framework-agnostic feature packages can evolve without changing the runtime
core. Framework-specific packages can add widgets or host integrations without
pulling UI dependencies into `ecsly`.

**Q: Why should shared domain components live outside core?**
A: Shared gameplay concepts such as position, velocity, health, input, camera,
and collision belong in feature packages. Core examples stay focused on runtime
mechanics so `ecsly` does not become a bundle of domain assumptions.

**Q: Why do core examples avoid defining Position/Velocity?**
A: Position and velocity are shared gameplay concepts, so defining them again in
core examples would create a misleading second component vocabulary. Core
examples demonstrate runtime mechanics; plugin examples demonstrate reusable
domain components.

**Q: Why keep input separate from Flutter host code?**
A: Input state can be represented as framework-neutral ECS data, while Flutter
widgets are host-specific. Keeping them separate avoids forcing Flutter
dependencies into headless or non-Flutter worlds.

**Q: Why keep camera data separate from camera controls?**
A: Camera state and smoothing can be pure ECS data/logic. Input bindings and
presets are host/control concerns and should not be required for programmatic
camera movement.

**Q: Why keep controls as their own feature layer?**
A: Controls compose input and camera state. Keeping that layer separate lets hosts
choose presets without changing the underlying data contracts.

**Q: Why keep broader Flutter/game bundles separate from `ecsly_flutter`?**
A: `ecsly_flutter` is the small official bridge for scope, controller, selectors,
actions, and loops. Broader UI, debug, input, camera, rendering, and HUD bundles
should stay outside the base bridge.

**Q: Why keep collision outside core ECS?**
A: Collision algorithms and response policies are domain systems. Core ECS should
provide storage, queries, schedules, and commands rather than choosing one
collision model.

**Q: Why keep algorithms separate from ECS storage?**
A: Pure algorithms can operate on typed buffers without depending on ECS world
structure. That keeps them reusable, testable, and easier to run concurrently.

**Q: Why keep isolate helpers separate from core ECS?**
A: Isolate management is an execution concern, not the data model. Core schedules
should expose explicit data boundaries rather than hiding concurrency policy in
the world type.

**Q: Why add `ScheduleExecutionPolicyResource` instead of another per-system flag?**
A: Parallel job execution needs one canonical frame policy, not ad hoc system-local switches. `ScheduleExecutionPolicyResource` makes the execution mode explicit (`serial`, `deterministic`, `bestEffort`), keeps deterministic mode as the default surface, and lets unsupported systems stay serial without changing schedule order.

**Q: Why introduce certified job systems instead of using `Schedule.parallel()` for hot paths?**
A: `Schedule.parallel()` still runs shared-world async systems and does not model deterministic data extraction, partition ownership, or stable merge order. Certified job systems force an explicit `extract -> partition -> execute -> merge` boundary, which is the minimum contract needed for reproducible worker execution and safe cross-frame job queues.

## Performance Targets

**Q: Why performance targets (< 1ns component access, < 100ns spawn, < 500ns migration)?**  
A: They are design targets for keeping hot-loop work small enough for large
simulations. Treat them as targets, not proof of current universal performance.

**Q: Why scalability targets (1k @ 60 FPS, 10k @ 60 FPS, 100k @ 60 FPS, 1M @ 60 FPS on web)?**  
A: They describe the scale ladder the architecture is shaped around. Each rung
requires current benchmark or runtime evidence before it becomes a public
capability claim.
