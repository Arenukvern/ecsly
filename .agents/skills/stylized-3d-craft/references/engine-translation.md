# Engine translation for stylized-3d-craft

How the craft rules map onto each engine. Read the row for your engine before
translating by guess; the engine's own skill still owns API correctness. Where a
proven recipe already exists in a repo, copy it instead of re-deriving.

## flutter_scene (Flutter GPU) — engine skill: `flutter-scene-modeling`

| Craft rule | flutter_scene translation |
| --- | --- |
| Tone mapping ON | `EnvironmentSettings` — one aggregate that carries tone mapping, exposure, IBL, and the whole post stack (bloom, AO, fog, DoF, grading, vignette). Presets live in the official `flutter_scene-looks` skill. Almost every effect is OFF by default — that default post stack is exactly why bare scenes read flat. Never ship it. |
| Storybook light | One warm `DirectionalLight` key (`castsShadow: true`, tuned `shadowSoftness`) from the upper front; the default studio IBL serves as fill. Proven "cozy plush" values: vosges `apps/desktop/lib/pet_skins/pet_look.dart` (ACES + warm grading, soft bloom, gentle half-res AO, vignette). Copy it before inventing numbers. |
| Key intensity wash | A too-hot key washes dark surfaces to gray (4.5 turned panda blacks muddy; ~2.6 kept them). Tune the key DOWN for dark palettes, one field at a time, capture between. |
| Contact law | `ShadowCatcherMaterial` plane under resting objects. KNOWN PITFALL: shadow catchers artifact on dark backdrops (vosges removed theirs) — on dark scenes ground via AO + a physical stage surface instead. |
| Bevel everything | `CuboidGeometry` cannot bevel — compose the rounding: swap to `CapsuleGeometry`/`WedgeGeometry` where it reads, `TorusGeometry` trim along rims, inset panels slightly proud of the surface. |
| Matte materials | Factors, not textures: `metallicFactor 0`, `roughnessFactor ≥ 0.8`; tone-separate adjacent parts by ~5–10% baseColor shifts. Glow = `UnlitMaterial` + emissive. |
| Embedding/silhouette | Model decomposition, overlap 10–20%, silhouette gate, palette roles: `flutter-scene-modeling` → `references/design-craft.md`. That file covers the model; this skill covers the scene around it. |
| Particles | `InstancedMesh` field placed from `FastNoiseLite(seed)`; drift on a `Ticker` (vsync). Hoist scratch `Vector3`/`Quaternion` to `static final` — vector_math has no const constructors, and per-frame allocation shows. |
| Idle life | Breathing = root scale 1 ± 0.008 over ~3 s (proven value); blinks/ear-wiggles live in the rig layer. For testable drivers, count fixed ticks (16 ms `Timer.periodic`) not wall clock — `fake_async` fakes ticks, not `DateTime.now()`. |
| Entrance | Cross-fade two look snapshots with `EnvironmentSettings.lerp(a, b, t)` driven from an animation, plus a short camera dolly. |
| Reduced motion | Gate the idle layer on `MediaQuery.disableAnimationsOf(context)`. |
| Determinism | Every builder takes a `seed`; all randomness from `Random(seed)` / `FastNoiseLite(seed)` — so a critique of capture N applies to capture N+1. |

## three.js / WebGL — engine skill: `three`

| Craft rule | three.js translation |
| --- | --- |
| Tone mapping ON | `renderer.toneMapping = THREE.ACESFilmicToneMapping` (or AgX where available) AND `renderer.outputColorSpace = THREE.SRGBColorSpace`. Both or nothing — raw linear output is the default failure. |
| Storybook light | Warm `DirectionalLight` key + cool rim light opposite + hemisphere/ambient fill. `renderer.shadowMap.type = THREE.PCFSoftShadowMap`; set `light.shadow.bias`, `normalBias`, `radius` on purpose — defaults acne. |
| Contact law | Radial-gradient `CanvasTexture` blob on a ground quad under each resting object + the key's soft shadow; sink objects 1–2% into the ground. |
| Matte materials | `MeshStandardMaterial { roughness: ≥ 0.8, metalness: 0 }`; procedural textures via `CanvasTexture` or `onBeforeCompile` noise injection. |
| Bevel everything | `RoundedBoxGeometry` (from examples/jsm), capsule/lathe swaps, merged rounded profiles — a naked `BoxGeometry` is a fail. |
| Particles | `THREE.Points` with a soft sprite texture; drift in the rAF loop with `clock.getDelta()` capped. |
| Idle life | Springs/ease-out curves; blinks on randomized timers; breathing via scale oscillation. A frozen frame must still read mid-motion. |
| Input < 100 ms | Answer in the same frame: hover scale 1 → 1.06 ease-out, press squash 0.96, settle with a spring. Sound = WebAudio oscillators, synthesized, no asset files. |
| Reduced motion | `matchMedia('(prefers-reduced-motion: reduce)')` → freeze the idle layer to one pose, keep input feedback. |
| Budget | `renderer.setPixelRatio(Math.min(devicePixelRatio, 2))`, cap dt, zero allocations in the render loop (hoist vectors, reuse geometries/materials). |
| Entrance | Camera dolly + a fade overlay; controls unlock after it settles. |

## Other engines (short rows)

- **Unity (URP)**: Volume profile carries the look — Color Adjustments with
  Tonemapping: ACES, plus Bloom, Vignette, AO. Warm directional key with Soft
  Shadows; URP defaults are the "default rig" instant fail. Rounded forms via
  ProBuilder bevel or booleans. Animation curves never Linear — Ease Out Back for
  pops, springs for settle. `Application.targetFrameRate` + capped `Time.deltaTime`.
- **Godot**: `WorldEnvironment` owns the look — tonemap ACES/Filmic, glow, SSAO, fog
  color == background color. `DirectionalLight3D` warm key, shadow enabled, tuned
  bias. `StandardMaterial3D` roughness 1.0 / metallic 0. Tweens with
  `TRANS_BACK`/`TRANS_CUBIC` + EASE_OUT, never linear.
- **Blender**: mostly the *source* of glTF assets — bevel modifier on every
  hard-edged object, squashed primitives before sculpting, Filmic/AgX view
  transform, large soft area key + cool sun rim. Exported assets then follow the
  consuming engine's import pipeline (for flutter_scene:
  `flutter-scene-modeling` → `references/gltf-pipeline.md`).
- **CSS 3D**: `perspective` + `transform-style: preserve-3d`; background == fog via
  layered gradients and opacity falloff on far layers; contact = layered tinted
  `box-shadow` (never black); transitions on `cubic-bezier` ease-outs — `linear` is
  the fail; breathing/sway as `transform` keyframes; `@media
  (prefers-reduced-motion: reduce)` gates the idle layer.
