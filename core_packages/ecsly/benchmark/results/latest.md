# ecsly benchmark report

- Generated: `2026-06-30T23:58:17.330092Z`
- Command: `dart run benchmark/run.dart --limits --samples=5`
- Samples: `5`
- Aggregation: `median`
- OS: `macos`
- Machine: `MacBook Air (M2, 2022)`
- CPU: `Apple M2`
- Memory: `8.0 GiB`
- Git commit: `3d6d4540d69b`
- Git dirty: `true`
- Dart: `3.12.1 (stable) (Tue May 26 01:02:21 2026 -0700) on "macos_arm64"`
- Processors: `8`

## Metrics

| Metric | Category | Entities | Value | ns/op | Range | Better | Notes |
|---|---:|---:|---:|---:|---:|---:|---|
| `query_iteration_ops_per_sec` | query | 30000 | 72771376.59 ops/sec | 13.74 | 41634862.26-79093066.17 | higher | Typed-column raw extension query over two components. |
| `raw_query_chunk_ops_per_sec` | query | 30000 | 111919418.02 ops/sec | 8.94 | 71106897.37-113421550.09 | higher | Chunked raw query path; expected to be the strongest iterator. |
| `query_count_ops_per_sec` | query | 30000 | 2864508.74 ops/sec | 349.10 | 989511.18-3012955.71 | higher | Repeated count query over a stable archetype set. |
| `query_any_ops_per_sec` | query | 30000 | 2672653.41 ops/sec | 374.16 | 2444509.63-2865657.96 | higher | Early-exit presence query over a stable archetype set. |
| `mutable_query_iteration_ops_per_sec` | mutation | 30000 | 77901843.68 ops/sec | 12.84 | 71778920.92-81688223.28 | higher | In-place typed-column mutation over two components. |
| `command_flush_ops_per_sec` | commands | 20000 | 11241007.19 ops/sec | 88.96 | 4031526.54-12633440.72 | higher | Object-component upsert plus flush; useful bottleneck signal. |
| `migration_ops_per_sec` | commands | 15000 | 8173273.40 ops/sec | 122.35 | 4819083.57-8332465.37 | higher | Batch add/remove extension component archetype migration. |
| `query_cache_hit_ops_per_sec` | query-cache | 20000 | 47846889.95 ops/sec | 20.90 | 26525198.94-48309178.74 | higher | Repeated query-cache hit for the same component mask. |
| `query_cache_miss_ops_per_sec` | query-cache | 20000 | 1432664.76 ops/sec | 698.00 | 960614.79-3663003.66 | higher | Forced cache clear and recompute; highlights archetype matching cost. |
| `event_send_ops_per_sec` | events | 0 | 23009664.06 ops/sec | 43.46 | 6876633.20-32030749.52 | higher | Typed-data event writes into a fixed-capacity channel. |
| `event_read_ops_per_sec` | events | 0 | 39123630.67 ops/sec | 25.56 | 5733287.47-41666666.67 | higher | Cursor read over typed-data event channel. |
| `frame_rss_delta_bytes` | memory | 15000 | 0.00 bytes |  | 0.00-16384.00 | lower | RSS delta across repeated typed-column frame updates. |
| `game_frame_20k_p50_micros` | game-frame | 20000 | 478.00 micros |  | 468.00-502.00 | lower | Synthetic 120-frame game loop: typed update, packet extract, flush. |
| `game_frame_20k_p95_micros` | game-frame | 20000 | 607.00 micros |  | 558.00-641.00 | lower | Prototype-relevant frame budget signal; lower is better. |
| `game_frame_20k_p99_micros` | game-frame | 20000 | 739.00 micros |  | 602.00-890.00 | lower | Tail latency for frame-shaped ECS work; lower is better. |
| `render_packet_extract_30k_ops_per_sec` | render-extract | 30000 | 83916083.92 ops/sec | 11.92 | 80833483.02-84929697.08 | higher | Packet-like extraction into Float32List, inspired by prototypes. |
| `render_packet_extract_30k_bytes` | render-extract | 30000 | 480000.00 bytes |  | 480000.00-480000.00 | informational | Packet-like Float32 payload bytes per extraction pass. |
| `spawn_despawn_churn_ops_per_sec` | commands | 30000 | 3582089.55 ops/sec | 279.17 | 2852253.28-3903708.52 | higher | Frame-style structural churn: spawn then despawn batches. |
| `query_iteration_1000_entities_ops_per_sec` | limit-scan | 1000 | 78247261.35 ops/sec | 12.78 | 36469730.12-82101806.24 | higher | Same typed-column query at increasing entity counts. |
| `query_iteration_10000_entities_ops_per_sec` | limit-scan | 10000 | 79101408.01 ops/sec | 12.64 | 71510297.48-83111702.13 | higher | Same typed-column query at increasing entity counts. |
| `query_iteration_30000_entities_ops_per_sec` | limit-scan | 30000 | 81956016.94 ops/sec | 12.20 | 80096115.34-85360648.74 | higher | Same typed-column query at increasing entity counts. |
| `query_iteration_100000_entities_ops_per_sec` | limit-scan | 100000 | 83941912.20 ops/sec | 11.91 | 83042683.94-84749353.79 | higher | Same typed-column query at increasing entity counts. |

## Reading the numbers

- Higher `ops/sec` is better for throughput metrics.
- Lower `ns/op` is better for per-operation cost.
- Lower `micros` is better for frame and latency metrics.
- Query and raw chunk metrics show hot-path strengths.
- Command, migration, cache-miss, and frame-tail metrics expose bottlenecks.
- Compare reports from the same machine, OS, and Dart SDK.
