# The glTF pipeline (models sourced outside Dart)

Use this route only when the model genuinely originates outside your codebase — a Blender
export, a marketplace asset, a converted scan. For anything an agent authors from
scratch, prefer procedural Dart (see the sibling reference): no import step, no binary
files in review, parameterizable.

## Choose the loading path

| Situation | Path |
| --- | --- |
| Model ships with the app (the normal case) | Build-hook pipeline: `.glb` under `assets/`, auto-converted at build time, load by source path |
| Model arrives at runtime (download, user file) | `Node.fromGlbAsset('...')` or `Node.fromGlbBytes(...)` — parses glTF on every load |
| One-off conversion to the binary format without a Flutter app | CLI: `dart run flutter_scene:import -i model.glb -o model.fsceneb` (pure Dart, no native binary; `-o` output is `.fsceneb`) |

## Build-hook pipeline (one-time setup, then it's automatic)

```sh
dart run flutter_scene:init   # writes hook/build.dart + adds flutter_scene_generated/ to pubspec assets
```

```dart
// hook/build.dart
import 'package:flutter_scene/build_hooks.dart';
import 'package:hooks/hooks.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    buildScenes(buildInput: input, buildOutput: output);
    await buildMaterials(buildInput: input, buildOutput: output);
  });
}
```

Then: drop `.glb` (and `.fscene` sources, `.fmat` materials, loose images) under
`assets/`, and load by **source path** — the hook discovers and converts each one:

```dart
final model = await loadScene('assets/trebuchet.glb'); // Future<Node>
scene.add(model);
```

Editing a source reconverts just that file and hot-reloads. The generated
`flutter_scene_generated/` directory is engine-tied compiled output; the hook manages its
`.gitignore` — keep sources in version control, never the generated directory.

There is **no** `.model` format and no `Node.fromAsset` in 0.23 — older snippets you find
refer to the removed API. The offline format is `.fsceneb`; you rarely name it, since
`loadScene` addresses the *source* path.

## What survives import (and what to check first)

- Units: glTF is meters, Y-up. The importer converts to native scene coordinates at the
  import boundary (the runtime-vs-baked policy is an importer detail; you model in
  standard glTF conventions).
- PBR factors and textures, node hierarchy/transforms, and animations carry over. After
  any first import, run the verification loop and **check scale and orientation before
  anything else** — a model 100× too large or lying on its back is the classic import
  failure, and it's a one-line transform on the returned `Node`.
- Multi-file `.gltf` (external `.bin`/images) is supported at runtime via a URI resolver;
  single-file `.glb` is the safe interchange choice. Prefer `.glb`.

## Authoring notes when the source is Blender (or a script)

- Export glTF 2.0, `.glb` single file, embed textures, **apply transforms** before export
  (unapplied scale/rotation is the #1 import surprise).
- Realtime discipline on the DCC side: triangulate or accept the importer's tessellation,
  keep one material per mesh where possible, name nodes — names survive import and make
  the imported subtree addressable (`model.children`).
- If an agent must generate a mesh file programmatically (rare), generate **glTF JSON +
  base64 buffers** for tiny meshes only; anything bigger should have been the procedural
  route.

## Custom materials for imported models

`.fmat` custom materials (WGSL shader + parameter sidecar) compile through the same hook
(`buildMaterials`) and load with `loadFmatMaterial('assets/toon.fmat')`. Cross-fade looks
with `EnvironmentSettings.lerp(a, b, t)`. Reach for `.fmat` only after factor-based
`PhysicallyBasedMaterial` settings stop expressing the look — it's a shader pipeline, a
different level of commitment.
