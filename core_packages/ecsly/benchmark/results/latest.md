# ecsly benchmark report

- Generated: `2026-11-06T23:06:37.730108Z`
- Command: `dart run benchmark/run.dart --limits --samples=5`
- Samples: `5`
- Aggregation: `median`
- OS: `macos`
- Machine: `MacBookAir10,1`
- CPU: `Apple M1`
- Memory: `16.0 GiB`
- Git commit: `b6bfef612134`
- Git dirty: `false`
- Dart: `3.13.4 (stable) (Tue Sep 15 01:01:15 2026 -0700) on "macos_arm64"`
- Processors: `8`

## Metrics

| Metric | Category | Entities | Value | ns/op | Range | Better | Notes |
|---|---:|---:|---:|---:|---:|---:|---|
| `query_iteration_ops_per_sec` | query | 30000 | 56845097.11 ops/sec | 17.59 | 33732501.26-64550833.78 | higher | Typed-column raw extension query over two components. |
| `raw_query_chunk_ops_per_sec` | query | 30000 | 81179813.29 ops/sec | 12.32 | 52115000.43-81510664.31 | higher | Chunked raw query path; expected to be the strongest iterator. |
| `query_count_ops_per_sec` | query | 30000 | 2615746.80 ops/sec | 382.30 | 760571.95-2787845.00 | higher | Repeated count query over a stable archetype set. |
| `query_any_ops_per_sec` | query | 30000 | 2674654.97 ops/sec | 373.88 | 2224595.12-2789555.90 | higher | Early-exit presence query over a stable archetype set. |
| `mutable_query_iteration_ops_per_sec` | mutation | 30000 | 62402496.10 ops/sec | 16.02 | 54864667.15-66585284.65 | higher | In-place typed-column mutation over two components. |
| `command_flush_ops_per_sec` | commands | 20000 | 10549079.59 ops/sec | 94.80 | 3693580.56-10670650.38 | higher | Object-component upsert plus flush; useful bottleneck signal. |
| `migration_ops_per_sec` | commands | 15000 | 6646726.49 ops/sec | 150.45 | 4110996.92-6909855.18 | higher | Batch add/remove extension component archetype migration. |
| `query_cache_hit_ops_per_sec` | query-cache | 20000 | 32679738.56 ops/sec | 30.60 | 20202020.20-33557046.98 | higher | Repeated query-cache hit for the same component mask. |
| `query_cache_miss_ops_per_sec` | query-cache | 20000 | 1288659.79 ops/sec | 776.00 | 865051.90-3367003.37 | higher | Forced cache clear and recompute; highlights archetype matching cost. |
| `event_send_ops_per_sec` | events | 0 | 20064205.46 ops/sec | 49.84 | 5850690.38-27352297.59 | higher | Typed-data event writes into a fixed-capacity channel. |
| `event_read_ops_per_sec` | events | 0 | 24201355.28 ops/sec | 41.32 | 5100999.80-28200789.62 | higher | Cursor read over typed-data event channel. |
| `frame_rss_delta_bytes` | memory | 15000 | 16384.00 bytes |  | 0.00-1507328.00 | lower | RSS delta across repeated typed-column frame updates. |
| `game_frame_20k_p50_micros` | game-frame | 20000 | 657.00 micros |  | 646.00-667.00 | lower | Synthetic 120-frame game loop: typed update, packet extract, flush. |
| `game_frame_20k_p95_micros` | game-frame | 20000 | 769.00 micros |  | 708.00-866.00 | lower | Prototype-relevant frame budget signal; lower is better. |
| `game_frame_20k_p99_micros` | game-frame | 20000 | 1110.00 micros |  | 831.00-1642.00 | lower | Tail latency for frame-shaped ECS work; lower is better. |
| `render_packet_extract_30k_ops_per_sec` | render-extract | 30000 | 59210526.32 ops/sec | 16.89 | 58727569.33-61446029.90 | higher | Packet-like extraction into Float32List, inspired by prototypes. |
| `render_packet_extract_30k_bytes` | render-extract | 30000 | 480000.00 bytes |  | 480000.00-480000.00 | informational | Packet-like Float32 payload bytes per extraction pass. |
| `spawn_despawn_churn_ops_per_sec` | commands | 30000 | 3182686.19 ops/sec | 314.20 | 2588773.35-3492839.68 | higher | Frame-style structural churn: spawn then despawn batches. |
| `query_iteration_1000_entities_ops_per_sec` | limit-scan | 1000 | 63051702.40 ops/sec | 15.86 | 28344671.20-64020486.56 | higher | Same typed-column query at increasing entity counts. |
| `query_iteration_10000_entities_ops_per_sec` | limit-scan | 10000 | 62821962.56 ops/sec | 15.92 | 53960716.60-66225165.56 | higher | Same typed-column query at increasing entity counts. |
| `query_iteration_30000_entities_ops_per_sec` | limit-scan | 30000 | 62992125.98 ops/sec | 15.88 | 58309037.90-64703979.29 | higher | Same typed-column query at increasing entity counts. |
| `query_iteration_100000_entities_ops_per_sec` | limit-scan | 100000 | 65123245.74 ops/sec | 15.36 | 62715584.82-66728947.02 | higher | Same typed-column query at increasing entity counts. |

## Reading the numbers

- Higher `ops/sec` is better for throughput metrics.
- Lower `ns/op` is better for per-operation cost.
- Lower `micros` is better for frame and latency metrics.
- Query and raw chunk metrics show hot-path strengths.
- Command, migration, cache-miss, and frame-tail metrics expose bottlenecks.
- Compare reports from the same machine, OS, and Dart SDK.
