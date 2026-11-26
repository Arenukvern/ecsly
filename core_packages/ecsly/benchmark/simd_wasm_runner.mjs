// Runs the dart2wasm build of benchmark/simd_columns.dart under Node.
//
// Usage, from core_packages/ecsly:
//   dart compile wasm -O4 benchmark/simd_columns.dart \
//     -o benchmark/results/simd_columns.wasm
//   node benchmark/simd_wasm_runner.mjs --compiler=wasm \
//     > benchmark/results/simd_columns.wasm.json
import { compile } from './results/simd_columns.mjs';
import { readFileSync } from 'node:fs';

const compiled = await compile(
  readFileSync(new URL('./results/simd_columns.wasm', import.meta.url)),
);
const app = await compiled.instantiate({});
app.invokeMain(...process.argv.slice(2));
