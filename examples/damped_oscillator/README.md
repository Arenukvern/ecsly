# Damped oscillator

A scene-free ECS example linking displacement/time and velocity/displacement
plots. Compare undamped motion, light damping and an overdamped return to rest.
Both plots use the same selected observation and fixed physical scales. The
clock starts paused; manual 1/60-second steps stop at four seconds.

One world stores sampled observations as components and an immutable clock,
damping and selection resource. Typed actions update that resource. The exact
solution of the unit-mass differential equation is sampled at deterministic
times; no second timer or state bus drives the simulation. Custom Canvas marks,
labels, controls and palette require no scene engine.

From this directory, using a compatible Flutter SDK (tested with 3.47.5):

```sh
flutter pub get
flutter analyze --no-pub
flutter test --no-pub
```

The web app explicitly enables semantics before automation. Its read-only
`window.__dampedState()` returns time, damping, displacement, velocity, energy
and shared plot selection. It grants no action or evaluation authority.

For release build and real-browser dogfood, configure the existing
[dogfood tool](../../tool/visualization_dogfood/README.md), then from that tool
directory run with an explicit SDK and fresh evidence path:

```sh
dart run bin/build.dart ../../examples/damped_oscillator FLUTTER_SDK
dart run bin/supervise.dart ../../examples/damped_oscillator NEW_EVIDENCE novel-damped
```

This uses Oka's existing release target/supervisor and the shared Flutter MCP
harness/CDP automation. Build compilation delegates to Flutter. The frozen
consumer oracle checks analytical reference values and independently observed
button effects; inspect its captured pixels separately.

Source derives from the skill-assisted arm of the frozen 2026-10-14 novel-task
evaluation. Model/main/bridge bytes were retained; package naming, dependency
paths and the single-view web loader were adapted here. The original comparison
retains its failed baseline and passing skill-assisted run. A single paired task
does not establish general skill superiority, native accessibility, compositor
timings, persistent checkpoints or arbitrary renderer performance.

Roboto is bundled with its license in `assets/fonts/`.
