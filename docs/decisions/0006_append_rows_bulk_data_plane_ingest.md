# ADR 0006: `World.appendRows` — append-only data-plane ingest becomes a first-class runtime path

- Status: Accepted
- Date: 2026-11-07
- North Star impact: `applies` (core runtime surface grows one measured
  bulk-append primitive; no new package, no policy change)
- Evidence: `core_packages/ecsly/benchmark/append_only_ingest.dart`,
  committed results at
  `core_packages/ecsly/benchmark/results/append_only_ingest.latest.json`

## Context

ecsly's structural-write contract is the deferred command queue: a system
or caller queues spawn/despawn/add/remove commands and the World applies
them at a flush boundary. That contract is right for simulation — it keeps
iteration safe and structural churn batched — and the committed scorecard
proves the read side (ADR 0005: 81.2M ops/sec raw chunk iteration, flat
1k→100k).

But there is a second workload class the runtime did not own: the DATA
PLANE. A consumer folds an append-only event tail — a journal cursor
delta, a replay log, an ingest feed — into a World used as a queryable
projection. Its shape is the opposite of a simulation frame: homogeneous
entities, strictly batch-ordered growth, no despawns, no per-frame
structural churn, and reads that are large membership-filtered scans.

The first such consumer is real: the `ecsai_harness` convergence program
(its ADR 0138, Phase 3) put a beat-graph memory engine — 1M-beat scale —
on an ecsly World. The committed battery (median of 3, Apple M1, Dart
3.13.4) measures the same 1M-row ingest three ways: through the command
queue 826 ms (1.21M rows/s), through `appendRows` with object components
306 ms (3.26M rows/s), through `appendRows` with typed columns 216 ms
(4.63M rows/s) — the queue's per-entity command/bundle/flush machinery
costs 3.1x at 1M (826 ms vs 216 ms), 3.5x at 100k (87.3 ms vs 24.7 ms)
and 5.3x at 1k (1.0 ms vs 0.2 ms). The gap narrows with size because the
queue's fixed flush bookkeeping amortizes; it never closes. The consumer could
already reach the fast mechanics (`Entities.create`,
`Archetype.addEntities`, `DataColumn` writes are all public), but it
could NOT stay coherent doing so: the structural-revision bump that query
membership caches key on (`World.recordStructuralChanged`) is
`@internal`, and entity locations must be set by hand. An external
caller using the public pieces silently desyncs cached query results —
the runtime offered a fast path it could not let anyone walk correctly.

## Decision

### 1. `World.appendRows(signature, count)` is the supported bulk-append path

One call reserves `count` entities AND archetype rows for a component
signature, immediately (no command queue), and returns
`AppendedRows{archetype, firstRow, entities}` for direct column fill
through `Archetype.getColumn`. It maintains every invariant the command
flush would:

- entities are created and LOCATED (`Entities.setLocation`), so queries,
  `getComponent` and serialization see them;
- `structuralRevision` is bumped and cached query results for the
  signature's components are evicted;
- rows are dense and contiguous (`[firstRow, firstRow + count)`), columns
  arrive blank (zeroed typed slots / null object slots).

Guards: refuses negative counts; asserts against use during a flush or
inside a hot schedule (there, structural changes belong to the queue).

The command queue remains the path for interleaved simulation structural
changes. `appendRows` is for append-only batch ingest where the caller
drives order. Row↔domain-id identity (e.g. `row == beatId - 1` in the
ecsai fold) is the CALLER's contract: rows are stable exactly as long as
nothing despawns (removal swap-pops and renumbers), which an append-only
world never does. Capacity for a known-size tail can be pre-reserved per
column with `DataColumn.resize` before the fill.

### 2. The runtime stays domain-free

`appendRows` knows nothing of beats, logs, journals or cursors. It is the
generic primitive "reserve N homogeneous rows now, fill them yourself" —
the same relation `batchSpawn` has to per-entity spawn, minus the
deferral, plus the column-fill seam. No beat/memory concept enters the
core (the boundary law this repo's plugins already follow).

### 3. Verbatim text rides the object column; no new string column yet

The data-plane consumer stores whole verbatim strings (memory-beat text,
~90 bytes each). The measured path is `ObjectColumn<T>` with a small
`Component` wrapper per row: the append-only ingest benchmark's label
legs show the object column ingesting 1M wrapped strings on par with the
typed columns (306 ms vs 216 ms) and SCANNING them faster than the
equivalent `Map` (227M rows/s vs 129M rows/s — 1.75x; the flag-filtered
numeric scan is 544M vs 229M rows/s — 2.4x). A dedicated `StringColumn`
is therefore NOT added: it would be a new public surface without a
measured need (the repo's claim rule: an unmeasured addition is
rejected). Should a consumer ever show a string-column-bound curve, this
row reopens with that measurement.

### 4. The workload class gets a committed curve

`benchmark/append_only_ingest.dart` measures four ingest legs per size
(1k / 100k / 1M): plain `Map` (the naive baseline), command-queue spawn,
`appendRows` with object components (isolates the queue overhead), and
`appendRows` with typed SoA columns (isolates the storage-tier win), plus
flag-filtered and verbatim-string scan legs at the largest size. Results
commit to `benchmark/results/append_only_ingest.latest.json` like the
rest of the scorecard (`--samples=3` medians; `just bench-append-ingest`).
The measurement the consumer brought (its own frozen before/after at 1M
beats, in its repo) and this benchmark agree on the shape: immediate
batched row append + typed columns is the data-plane path. One honest
exception the curves name: at 1M rows the plain `Map` INGEST (270 ms)
is competitive with `appendRows`+columns (216 ms) — maps do not lose on
sequential insertion; they lose on retention (+145 MB RSS delta for the
same 1M rows vs a negative delta for the column leg, whose typed arrays
reuse capacity) and on every scan afterwards (2.4x / 1.75x). The law is
precise, not decorative: columns win WHERE the data plane actually
hurts — resident memory and repeated large scans — and the ingest path
that gets you there should not cost 3.8x for a queue the data plane
never needed.

## Consequences

- Data-plane consumers (the ecsai beat fold, replay-style projections,
  feed loaders) get a supported fast path WITHOUT reaching into
  `@internal` invariants — the class of silent query-cache desync is
  closed by construction.
- `batchSpawn` (same bundle × N) and `appendRows` (distinct data × N)
  now cover the two bulk-spawn shapes; per-entity `spawn` stays the
  interleaved/simulation path.
- The 1M-entity curves are committed evidence for ADR 0005's positioning
  claim on the ingest side, not only the frame-loop side.
- Future candidates, each requiring its own measurement before landing:
  a bulk `setRange` fill on typed columns (the fill loop is per-row
  `setValue` today), and a checkpointed append cursor analog to
  `ecsly_replay`'s log for Worlds that re-fold tails across restarts.

## Alternatives considered

- **Keep the command queue as the only structural path** (add a
  "bulk spawn with distinct data" command instead): keeps one write
  door, but the queue's per-command allocation and flush bookkeeping ARE
  the measured 3.1x at 1M (5.3x at 1k); a batched command would need a new per-row data
  carrier anyway — more surface than `appendRows`, same invariants.
- **Document the public-pieces recipe** (`Entities.create` +
  `Archetype.addEntities` + column writes): zero new API, but it cannot
  include the `@internal` revision bump — it would officially bless an
  incoherent path. Rejected: a fast path the runtime cannot keep
  coherent is a trap, not a feature.
- **`StringColumn`**: rejected for now per Decision 3 (no measured need).
