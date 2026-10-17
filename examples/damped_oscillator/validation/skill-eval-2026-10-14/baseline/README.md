# Damped / Motion laboratory

A Flutter web app with one ECS world, an oscillator resource, ecsly_flutter controller/scope, and two Canvas plots. It starts paused. All model transitions use fixed 1/60 s RK4 steps; four-second preview curves use that same transition. There is no wall-clock simulation or flutter_scene dependency.

## Commands

Run from this directory with the canonical SDK:

```sh
/Users/antonio/fvm/versions/stable/bin/flutter pub get
/Users/antonio/fvm/versions/stable/bin/flutter analyze
/Users/antonio/fvm/versions/stable/bin/flutter test test/model_test.dart
/Users/antonio/fvm/versions/stable/bin/flutter run -d web-server --web-port 8080
/Users/antonio/fvm/versions/stable/bin/flutter build web --release
```

The pubspec pins all three ECS packages to their local canonical paths, including dependency overrides for their hosted sibling references.

## Controls and observation

Step 1/60 s advances exactly once. Undamped, Light damping, and Overdamped reset the initial conditions and selection with damping 0, 0.3, and 1.2. Reset keeps the chosen damping. Next sample advances the linked amber marker through the 241 preview observations and wraps to zero, without advancing the live model. White dots show current live state. Sample indices are zero-based.

The read-only browser function `window.__dampedState()` returns a fresh plain JSON object with live time, damping, displacement, velocity, energy and linked selection indices. Mutating its returned object cannot mutate the model.

## Validation and limitations

Five focused model tests cover initial conditions, complete trajectory, fixed stepping, analytic undamped agreement, energy decay, overdamped non-crossing, resets and linked selection. Static analysis passes. The model uses numerical RK4 rather than an exact symbolic solution. The live model can step beyond four seconds, while the preview/selection remains bounded to four seconds. No browser was launched and no visual, accessibility or release-build qualification is claimed; the parent owns those checks.
