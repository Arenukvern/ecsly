---
name: ecsly-plugin-pattern
description: The architecture pattern for ecsly plugins and adapters (pure core + thin shell over a seam). Use when creating a new plugin under ~/xs/ecsly/plugins/ or adapting ecsly to an external dependency (renderer, transport, codec, storage) — e.g. ecsly_world_sync, ecsly_world_sync_bridge, ecsly_serialization, ecsly_flutter_scene — or when a plugin review says "this mixes concerns" or "tests need the real thing".
---

# The ecsly plugin pattern: pure core, thin shell

Every ecsly plugin separates into a **pure Dart core** and a **thin shell** that is the
only code touching the external dependency. The core talks to an interface (the *seam*);
the shell implements the seam with the real thing. Tests run the core against fakes —
fast, hermetic, no GPU/network/codec needed.

Seen in the wild (study these before inventing variants):

| Plugin | Pure core | Seam | Shell |
| --- | --- | --- | --- |
| `ecsly_flutter_scene` | `SceneMapping`, `VisualState`, `EcsSceneBinder` | `SceneSink` (add/update/remove/count) | `FlutterSceneSink`, `EcsSceneView` |
| `ecsly_world_sync` | projection + component deltas | transport | `fake_transport.dart` + real transport |
| `ecsly_world_sync_bridge` | message/policy | transport + driver | bridge/driver wiring |
| `ecsly_serialization` | snapshot model + codecs | (de)serialization boundaries | JSON object codecs |

## Rules (with the reasons)

1. **Name the seam as a tiny interface.** Three to five members max (`add`/`update`/
   `remove`/`count`, or `send`/`recv`). A seam that wide is a leak; if you need more,
   you probably have two seams.
2. **Concentrate external-API calls in designated shell files** and say so in the library
   doc comment (`ecsly_flutter_scene` names its two shell files explicitly — the external
   package is pre-1.0, so API drift must cost one file, not the plugin).
3. **The consumer owns policy.** Layout, snapshot policy, tick cadence, codec registry —
   the plugin consumes decisions, it doesn't make them. Pure cores that arrange things
   (layout a graph, pick a snapshot policy) grow consumer-specific branches forever.
4. **Diff, don't push.** Per-frame/per-tick sync collects desired state, diffs against a
   signature, and lands only ADD/UPDATE/REMOVE. A static world costs one collection and
   zero seam calls. Give diffable states a cheap `signature` getter.
5. **Views read; the app ticks.** A widget/view never advances the `World` schedule —
   it reads queries and syncs. Ownership of the loop stays with the host app.
6. **Ship the fake.** Every seam gets a recording/canned fake in `test/`
   (`recording_sink.dart`, `fake_transport.dart`). If a feature can't be tested through
   the fake, the seam is wrong — fix the seam, don't add GPU/network to CI.
7. **Pure means pure.** No Flutter imports in core files, no `dart:io` where web/wasm
   might run, no singletons holding external state. The core compiles in a bare
   `dart test`.
8. **Language-compat guard**: plugin sources compile under Dart 3.12 *and* 3.13 —
   parameters carry no `final` modifier (files use
   `// ignore_for_file: prefer_final_parameters`). Preserve this when editing.

## Docs each plugin carries

- README with a **Design** section: the seam, what's pure vs shell, requirements
  (platform flags, static-resource init), "What was borrowed" provenance, and an explicit
  dependency list. `plugins/ecsly_flutter_scene/README.md` is the model to copy.
- Package-local DX FAQ for usage questions; `DESIGN_FAQ`/architecture notes for core.
- A plugin that becomes canonical gets its own `NORTH_STAR.md` **sub-star** linked from
  the root North Star (see `plugins/ecsly_serialization/NORTH_STAR.md`) — that promotion
  is a root ownership-table change (North Star `amends`), not a doc edit.

## Placement and promotion

- New experiments go under `plugins/<name>` only after they've proven out elsewhere;
  being present in `plugins/` does **not** make a package canonical — the ownership
  tables in `ARCHITECTURE.md` / `docs/NORTH_STAR.mdx` do (see the ecsly-repo-dev skill).
- Public claims about the plugin need proof: code, tests, examples, releases, or explicit
  blocked state.
- For the 3D/rendering adapter specifically, the user-level `flutter-scene-modeling`
  skill has the VisualState semantics, the signature trap, and the three extension
  patterns — read `~/.agents/skills/flutter-scene-modeling/references/ecsly-adapter.md`
  before touching `ecsly_flutter_scene`.
