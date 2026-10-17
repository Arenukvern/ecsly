# Stack

Start here and stop when the surface is fast enough to judge.

## 1. Flutter widgets

Preview `main` constructs the screen from an in-memory fixture and the app
theme. Use this for chrome, copy, density, hover, focus, and short transitions.

```sh
flutter run -d macos -t lib/dev/preview_main.dart
flutter run -d chrome --web-port=7357 -t lib/dev/preview_main.dart
flutter devices   # then -d <id> for iOS, Android, Linux, or Windows
```

Hot reload after widget or token edits. Hot restart after fixture type or
`main` edits.

## 2. ecsly + ecsly_flutter

Add one world when selection, a clock, or two views must stay on the same
records. Mount `EcsAppScope` once. Drive changes through `EcsController` and
`EcsAction`. Read with typed selectors (`EcsResourceSelector`,
`EcsComponentSelector`, `EcsWorldSelector`).

- Components hold records. Resources hold small coordination choices.
- Do not wrap the world in another `ChangeNotifier` bus.
- Time: `EcsFrameSchedule.fixed` inside the Flutter loop (`EcsFlutterLoop` /
  `EcsFixedStepLoop`). Bound catch-up. Pause on reload. Stop at an endpoint.
- Checkpoints may store theme, camera, and selected id. They must not store
  renderer objects or entity handles. A failed restore is visible.

Data-only edits (labels, positions, palette, selection) go through the action
with a request id and expected revision. That path does not need a compiler.
Widget and renderer structure still uses hot reload.

## 3. Optional ecsly_flutter_scene

Use only when depth or a spatial path teaches something a widget cannot.
Keep one scene view. Flutter overlays own labels and buttons.
`SceneMapping` → binder → a consumer sink. The shape set is closed.

If the question is a button, a list, or a 2D chart, stay on widgets or Canvas.
A chart does not become 3D because the scene package is available.

## 4. Optional Oka

Use Oka only when the repo already builds or watches web with it. Its web
target delegates compilation to Flutter. It can keep a session so the next
edit reloads instead of a cold start.

Do not install Oka to click the UI. Clicks stay on the VM toolkit (debug) or
`universal_browser_cdp` (built web). A missing Oka install is not a blocker
for `flutter run`.

## What not to add

- A second design-system preview app, unless the product already has one and
  the question is a single primitive in isolation.
- A live backend, login, or device cloud for color, type, and motion.
- Scene, Wasm, or a custom renderer as a speed strategy. Measure the same
  workload before claiming one is faster.
