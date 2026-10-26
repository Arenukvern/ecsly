# Frozen skill replay inputs

North Star impact: applies. This local tool captures owned source and verifies
its bytes; it does not evaluate aesthetic quality or agent behavior.

Run with the repository's Dart SDK:

```sh
dart pub get
dart run freeze.dart /absolute/ecsly /absolute/new-snapshot
dart run verify.dart /absolute/new-snapshot
```

The snapshot includes the renderer-independent host and Canvas implementation,
plus the optional scene adapter. An engine-free task must be evaluated using a
Canvas consumer whose resolved dependency graph excludes both scene packages.
Examples should cover charts, graphs, simulations and ordinary Flutter widgets;
3D is not a prerequisite for the visualization workflow.

`agent-prompts.json` omits rubric criteria. The complete snapshot still contains
rubrics and references: isolation must be enforced by the execution runner.
Existing cases have already been seen and are replay cases, not novel held-out
tests. External references and installed skills are outside this capture.

The 2026-10-13 capture contains 193 files. Local plugin-eval 0.1.0 analysis
reports score 53/F, with three instruction-budget failures and one warning.
That is a static report, not a behavioral failure rate. Its generated benchmark
proposal contains generic scenarios and a model default; it has not been run.
The live tool explicitly says benchmarks perform real Codex runs and have no
simulated dry-run mode. Replace the generic scenarios, freeze the runner setup,
and enforce baseline/candidate skill exposure before measuring behavior.

The 2026-10-14 guidance capture adds the example-owned skill history to replay
inputs. Both the original 193-file snapshot and new 199-file snapshot verify.
`output/current-guidance-2026-10-13/{before,after}.json` records static analysis
around the verification-history relocation: deferred estimate 11,450 → 7,379,
score unchanged at 53/F. No agent benchmark or held-out promotion ran. The
199-file snapshot predates the later evaluation-log append and remains immutable.
