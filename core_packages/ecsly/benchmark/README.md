# SIMD column benchmark

`benchmark/simd_columns.dart` measures the public float kernels against a
scalar loop, plus one integer probe. It does not feed `benchmark/run.dart`,
`thresholds.yaml`, or the README scorecard.

Each metric reports three numbers:

- `value`: the kernel, in microseconds per call.
- `scalarMedianUs`: the `getValue`/`setValue` loop the 1.0.1 stride-2 kernels
  ran.
- `speedup`: the ratio of the two.

## How it measures

One kernel call is far below timer resolution, and the `dart2js` `Stopwatch`
ticks in milliseconds. Each sample times a batch long enough to make
resolution negligible (60 ms by default) and divides by the batch length.
Mutating kernels alternate a call with its inverse, so a batch never drifts.
`--warm-ms` (300 by default) of unrecorded calls run first, so a JIT build
measures optimised code.

64 rows exposes per-call setup cost. 1000 to 100000 rows show throughput.

## Targets

Acceptance numbers are AOT, median of 5:

```sh
just bench-simd        # benchmark/results/simd_columns.aot.json
```

JIT is a dev signal. The Dart JIT and V8 both optimise a kernel differently
depending on the program around it, so one kernel can run several times slower
in one program than in another with the same source:

```sh
just bench-simd-jit    # benchmark/results/simd_columns.jit.json
```

These two need Node. The Wasm one needs Node 22 or newer for WasmGC:

```sh
just bench-simd-js     # benchmark/results/simd_columns.js.json
just bench-simd-wasm   # benchmark/results/simd_columns.wasm.json
```

Every report records `compiler`, `simdHardware`, and `maskWordSize` next to
the host fields ADR 0005 asks for (machine, SDK, date, commit). `simdHardware`
must be true for AOT and JIT and false for JS and Wasm. `maskWordSize` is 64
on the VM and on Wasm and 32 on JS. There is no JS or Wasm CI gate.

## Reading a change

Compare against a baseline, not against the scalar loop. `speedup` says how a
kernel compares with its 1.0.1 loop. It says nothing about whether the change
made the kernel faster. Run the same file on both trees and compare `value`
per metric. The file calls `kEcslySimdHardware` and `IntColumn.simdWindow`,
which a tree from before this change lacks. On such a tree, declare
`const kEcslySimdHardware = false;` in the file and drop the integer probe
metric with `_countVector`. The timed float workloads stay identical. `environment.gitCommit` and `--label=<text>` say which run is
which.

This machine differs by 20% or more between identical runs on some metrics.
Interleave the two runs, and treat a smaller difference as noise.
