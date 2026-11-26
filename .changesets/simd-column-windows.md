---
'ecsly': minor
---

`FloatColumn.simdWindow` and `IntColumn.simdWindow` expose the live `Float32x4` or `Int32x4` prefix of a column for any stride, plus a 0–3 element tail, so a stride-2 column packs two rows per vector. The view is reused while the column's length and buffer are unchanged, so a system that takes it every frame does not allocate.

The kernels pick their path with the new `kEcslySimdHardware` constant. On the VM and in AOT, `updatePositionSimd`, `calculateDistancesSimd`, `scalePositionsSimd`, `addColumnsSimd`, `multiplyColumnSimd`, and `dotProductSimd` at stride 2 and 4 run `Float32x4` loops. On `dart2js`, DDC, and `dart2wasm`, where a `Float32x4` loop is slower than a scalar one, and for rows outside the vector prefix, they run scalar loops over the raw typed data instead of the `getValue`/`setValue` loops. `normalizeVectorsSimd` stays scalar everywhere, because a vector square root and divide measured slower than the double loop. `benchmark/results/simd_columns.{aot,jit,js,wasm}.json` record each target. `Float32x4` stays available on every target, for user kernels that want it.

Vector rows change results by rounding. They compute in float32 and can differ from the scalar loops by an ulp, or more where terms cancel. A VM build is therefore no longer bit-identical to a `dart2js` build for the vectorised kernels. `normalizeVectorsSimd` keeps its exact 1.0.1 results.

- `simdView` is still null unless the stride is a multiple of 4. It now covers live rows only and is the vector list of `simdWindow`.
- `getSimdViewForRows` returns the requested rows. For a non-zero start row it threw or returned the wrong row.
- SIMD iteration no longer reads or writes spare capacity.
- `simdAdd` and `simdMultiply` apply to one row at every stride: component `j` takes lane `j % 4`. They were a silent no-op below stride 4 and wrote across two rows at stride 5, 6, and 7.
- `batchSimdUpdate` is a no-op unless the stride is a multiple of 4. It wrote across rows at stride 5, 6, and 7.
- `updatePositionSimd` and `calculateDistancesSimd` stop at the shorter column instead of failing an assert.
