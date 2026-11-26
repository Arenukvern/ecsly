set dotenv-load := false

default:
    @just --list

# Show the Steward-generated agent map.
map:
    steward map

# Validate the local Steward contract without running package gates.
doctor:
    steward doctor --json

# List typed Steward actions and their safety/effect contracts.
actions:
    steward actions list --json

# Run the quick Steward smoke probe.
probe:
    steward probe --profile quick --json

# Fetch workspace dependencies.
get:
    dart pub get

# Analyze the core Dart ECS package.
analyze-core:
    cd core_packages/ecsly && dart analyze

# Run core ECS tests.
test-core:
    cd core_packages/ecsly && dart test

# Run app-layer tests.
test-app:
    cd core_packages/ecsly_app && dart test

# Run codegen package tests.
test-codegen:
    cd core_packages/ecsly_codegen && dart test

# Run Flutter bridge tests.
test-flutter:
    cd core_packages/ecsly_flutter && flutter test

# Run serialization plugin tests.
test-serialization:
    cd plugins/ecsly_serialization && flutter test

# Run replay plugin tests.
test-replay:
    cd plugins/ecsly_replay && dart test

# Run serialization benchmarks.
bench-serialization:
    cd plugins/ecsly_serialization && flutter test test/benchmark_test.dart

# Run the append-only data-plane ingest benchmark (ADR 0006).
bench-append-ingest:
    cd core_packages/ecsly && dart run benchmark/append_only_ingest.dart --sizes=1000,100000,1000000 --samples=3 --json --out=benchmark/results/append_only_ingest.latest.json

# AOT SIMD column benchmark, the acceptance numbers. Writes benchmark/results/simd_columns.aot.json.
bench-simd:
    cd core_packages/ecsly && dart compile exe benchmark/simd_columns.dart -o benchmark/simd_columns.exe && ./benchmark/simd_columns.exe --compiler=aot --json-out=benchmark/results/simd_columns.aot.json

# JIT SIMD column benchmark. A dev signal, not the acceptance number.
bench-simd-jit:
    cd core_packages/ecsly && dart run benchmark/simd_columns.dart --compiler=jit --json-out=benchmark/results/simd_columns.jit.json

# dart2js SIMD column benchmark. Needs Node. Records simdHardware false.
bench-simd-js:
    cd core_packages/ecsly && dart compile js -O4 benchmark/simd_columns.dart -o benchmark/results/simd_columns.js && node benchmark/results/simd_columns.js > benchmark/results/simd_columns.js.json

# dart2wasm SIMD column benchmark. Needs Node 22 or newer for WasmGC. Records simdHardware false.
bench-simd-wasm:
    cd core_packages/ecsly && dart compile wasm -O4 benchmark/simd_columns.dart -o benchmark/results/simd_columns.wasm && node benchmark/simd_wasm_runner.mjs --compiler=wasm > benchmark/results/simd_columns.wasm.json

# Run all package tests that do not publish.
test: test-core test-app test-codegen test-flutter test-serialization test-replay

# Check docs.page configuration and pages.
docs-check:
    npx --yes @docs.page/cli check

# Regenerate README benchmark blocks and docs.json version from artifacts.
sync-benchmarks:
    dart tool/docs/sync_readme_benchmarks.dart

# Fail when README benchmark blocks or docs.json drift from the artifacts.
check-docs-sync:
    dart tool/docs/sync_readme_benchmarks.dart --check

# Run core publish dry-run.
publish-core-dry-run:
    cd core_packages/ecsly && dart pub publish --dry-run

# Run publish dry-run preflight for all publishable packages.
publish-dry-run:
    dart tool/release/pub_package.dart --all --skip-existing

# Sync pubspec versions from the Release Please manifest.
sync-release-pubspecs:
    dart tool/release/sync_release_pubspec_versions.dart

# Check pubspec versions against the Release Please manifest.
check-release-pubspecs:
    dart tool/release/sync_release_pubspec_versions.dart --check

# Run publish dry-run preflight for one release tag.
publish-tag-dry-run tag:
    dart tool/release/pub_package.dart --tag "{{tag}}" --skip-existing

# Publish one release tag. Intended for CI or supervised maintainer bootstrap.
publish-tag-execute tag:
    dart tool/release/pub_package.dart --tag "{{tag}}" --execute --skip-existing

# Run the default local gate used before PRs.
check: probe get analyze-core test docs-check check-docs-sync

# Run the release-oriented local gate.
release-check: check check-release-pubspecs publish-dry-run
