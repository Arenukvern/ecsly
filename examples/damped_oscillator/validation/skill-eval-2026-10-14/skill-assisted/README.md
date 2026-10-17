# Damped oscillator — Canvas consumer

Owned by the skill-assisted arm of the 2026-10-14 frozen visualization evaluation. Created from the canonical Canvas scaffold, then adapted in this consumer only. No scene package or GPU scene adapter is required.

One ECS world stores the three sampled trajectories as observation components and the current clock, damping and shared plot selection as a resource. Typed EcsAction operations update immutable selected values through EcsController. The app starts paused; manual steps advance a bounded integer 1/60 s clock. The exact damped-oscillator ODE solution avoids numerical integrator drift. Both plots use the same selected index, and pointer selection in either plot updates both.

```sh
cd /Users/antonio/xs/ecsly/tool/visualization_dogfood/output/novel-skill-2026-10-14/skill-assisted
/Users/antonio/fvm/versions/stable/bin/flutter pub get
/Users/antonio/fvm/versions/stable/bin/flutter analyze --no-pub
/Users/antonio/fvm/versions/stable/bin/flutter test --no-pub test/model_test.dart
/Users/antonio/fvm/versions/stable/bin/flutter build web --release --no-web-resources-cdn
/Users/antonio/fvm/versions/stable/bin/flutter run -d chrome
```

Read-only browser hook: `window.__dampedState()` returns a plain object with current time, damping, displacement, velocity, energy, selectedIndex and plotSelection `{time:index, phase:index}`. Selection is independent of the paused simulation clock. Next sample wraps after 240. Presets reset the clock and selection; Reset keeps the chosen damping. Trajectories cover 0–4 s with 241 observations and shared fixed scales across damping choices. The outline denotes current state and the filled orange mark denotes selected observation.

Limitations: no automatic playback or persisted checkpoint; every reload deliberately starts paused at the requested initial conditions. Model tests and analysis do not establish browser rendering, accessibility hit testing, narrow-width pixels or release readiness. Parent owns release build and real-browser qualification. This consumer has not launched a browser or UI.
