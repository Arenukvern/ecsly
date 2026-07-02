# ecsly benchmark profile sidecars

Use this directory for CPU, allocation, GC, and timeline captures that explain
benchmark scorecard movement.

Scorecards answer what moved. Profile sidecars are the evidence for why it
moved. Do not claim a causal hotspot from `benchmark/results/latest.md` or
`latest.json` alone.

## Naming

Use filenames that connect the profile to the scorecard and metric:

```text
2026-07-01-query-cache-miss.cpu-profile.json
2026-07-01-game-frame-p95.allocation-profile.json
29a504a9fe0a-command-flush.timeline.json
```

Prefer commit or date plus the investigated metric. If the capture is too large
to commit, store a short markdown note here with the path, command, environment,
and the observed hot symbols.

## Hotspots To Check First

- `QueryCache.getOrCompute` for cache miss and archetype matching movement.
- `CommandQueue.execute` for command flush and structural churn movement.
- Query/raw chunk iterator loops for typed-column iteration movement.
- Archetype migration and query-cache invalidation around flush boundaries.
- Accidental hot-path `List`, `Map`, closure, or record allocation.
