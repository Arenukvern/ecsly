# ecsly benchmark results

Benchmark reports in this directory are generated artifacts. Do not hand-edit
numbers.

Generate matching reader-facing and machine-readable reports from one benchmark
scorecard. Use median-of-5 for publishable comparisons:

```sh
dart run benchmark/run.dart --limits --samples=5 \
  --markdown-out=benchmark/results/latest.md \
  --json-out=benchmark/results/latest.json
```

Generate only machine-readable data:

```sh
dart run benchmark/run.dart --json --limits --out benchmark/results/latest.json
```

Run the faster threshold check used for regression-style feedback:

```sh
dart run benchmark/run.dart --check
```

This is a one-sample smoke gate against `benchmark/thresholds.yaml`, useful for
fast local smell checks. It is not the publishable scorecard. Use
`latest.json` from a median-of-5 run for local comparison claims.

`benchmark/thresholds.yaml` accepts the original scalar form for throughput
floors:

```yaml
query_iteration_ops_per_sec: 10000000
```

Latency and memory diagnostics use explicit ceilings:

```yaml
game_frame_20k_p95_micros:
  max: 5000
  lowerIsBetter: true
```

Generate local command/migration phase timing JSON when command bottlenecks need
more detail before opening DevTools:

```sh
dart run benchmark/profile_commands.dart \
  --json-out=benchmark/results/command_profile.latest.json
```

The command profile artifact uses top-level `scenarios` and
`schemaId: ecsly.core.command_profile`, with additive fields instead of
version-family names. Do not append `.v1` to the schema id. This keeps local
automation stable without creating a growing stack of schema variants.
Each profile records environment, git commit/dirty state when available, the
requested sample count, per-scenario runs, and raw phase samples.

From the repo root:

```sh
just bench-core
just bench-core-check
just profile-core-commands
just profile-core run --json
```

## What the suite shows

- Hot-path strengths: typed-column query iteration, raw chunk iteration, mutable
  typed-column iteration, query-cache hits.
- Bottleneck signals: command flush, archetype migration, query-cache misses,
  spawn/despawn churn, event throughput, RSS delta.
- Game-frame signals: p50/p95/p99 frame-shaped ECS update + extract timings.
- Render extraction signals: packet-like Float32 payload extraction and bytes
  per extraction pass.
- Scale behavior: `--limits` adds entity-count scan metrics so throughput bends
  become visible.

## Game-shaped relevance

The game-shaped metrics map benchmark rows to common runtime pressures:

- Dense movement: typed mutation, game-frame p95/p99, entity-count scaling,
  spawn/despawn churn.
- Render extraction: render-packet-like extract, packet bytes, draw-like counts.
- Asset-heavy scenes: render-packet-like extract, packet bytes, entity-count
  scaling.
- Focused gameplay loops: typed-column query/mutation cost and schedule-shaped
  frame timings.

## How to read reports

- Compare reports from the same machine, OS, Dart SDK, and runtime mode.
- Prefer `--samples=5` reports for decisions. `latest.json` stores the median,
  sample count, min/max, and raw sample values per metric; this is the
  publishable local scorecard format.
- Treat `ops/sec` as throughput: higher is better.
- Treat `ns/op` as per-operation cost: lower is better.
- Treat `micros` as frame/latency cost: lower is better.
- Treat `frame_rss_delta_bytes` as a coarse memory diagnostic, not a precise
  allocator profile.
- Use Dart DevTools CPU/allocation/GC/timeline profiling when a metric moves;
  the scorecard identifies movement but does not explain the cause.
- Keep scorecards and causal evidence separate: a median report can show that
  `QueryCache.getOrCompute`-shaped cache misses moved, but only CPU/allocation
  profile evidence can say whether that symbol caused the movement.
- Store profile sidecars under `benchmark/results/profiles/` next to the
  scorecard they explain.
- Use application profiling for real workload decisions.
