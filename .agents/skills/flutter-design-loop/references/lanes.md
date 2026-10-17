# Lanes, platforms, non-claims

## Design lane

Any Flutter device from `flutter devices`:

| Target | When |
| --- | --- |
| Desktop (macOS, Linux, Windows) | Default. Fastest reload, real window capture. |
| Chrome (`flutter run -d chrome`) | Web semantics and layout before a release build. |
| iOS or Android | Safe area, touch, keyboard, text scale on that OS. |

Attach the VM URI from `flutter run`. Discover `ext.mcp.toolkit.*` on the UI
isolate before calling it. Snapshot, one action, fresh snapshot.

Keyboard: focus, then one chord. If focus is unverified, stop.

Pixel capture is separate from the semantics check. On some toolkit builds an
offscreen scene grab has corrupted later glyphs. Capture the OS window or a
CDP frame instead.

## Acceptance lane (web)

```sh
flutter build web
# serve the output, then drive it headless
# visible browser only when a person must watch
```

`ChromeAppTarget` owns or borrows Chrome. Record which. Stop only what you
started. Waits are named and bounded (element appears or disappears). A wrong
label is a script bug; do not stretch the timeout to hide it.

Interactive sessions may use the same CDP driver. They are not a second
product.

Other platforms have no CDP web proxy. Their acceptance is the design-lane
device plus the app's widget or integration test. Do not claim web behavior
from an iOS run, or iOS behavior from Chrome.

## Observe / act / verify

| Step | Design | Built web |
| --- | --- | --- |
| Observe | semantics snapshot | accessible name |
| Act | one toolkit tap or text input | one click or field fill |
| Effect | fresh snapshot shows the expected node | name appears or disappears before the deadline |

Four failures without a new fact: stop. Report the target, the last tree, and
whether the mismatch is selector, layout, or data.

## Non-claims

- Debug desktop does not prove release web, Wasm, or a phone.
- A CDP run against `build/web` does not prove hot reload.
- A widget test does not prove a gesture or a frame.
- Semantics do not prove contrast, density, or motion curves.
- Optional scene or Oka does not prove a speed win.
- Do not claim a live backend, media stream, or auth flow from a fixture preview.
