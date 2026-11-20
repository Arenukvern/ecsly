# Design craft: what makes a 3D model look great

A model reads as "great" through four qualities, in this order of impact:

1. **Silhouette** — is the outline recognizable from any side?
2. **Proportion** — are the part-to-part ratios deliberate?
3. **Coherence** — one style, one idea, one palette.
4. **Detail** — sharpening at the focal zone only.

Almost every amateur model fails at 1–3 and tries to compensate with 4. Detail added to a
broken proportion is wasted work that makes the fix harder. Work the list top to bottom.

## The design sheet (write this before code)

```markdown
# Model: desk lamp
Intent: hero prop, seen three-quarter from 2 m, ~1/8 frame on mobile. Reads in silhouette as "lamp".
Style: chunky toon-PBR (soft edges, saturated palette, clearcoat plastic).
Parts: base (short cylinder), joint (sphere), arm (bent tube), head (cone + disc lens), cord (polyline).
Ratios: total height 1.0 → base 0.12, lower arm 0.35, upper arm 0.30, head 0.23.
        Footprint 0.5. Arm attaches at 2/3 out from center. Head tilts 30° forward.
Palette: base + arm 0xFF2E3440 (dominant), joint + accents 0xFFEBCB8B (secondary),
         lens 0xFF88C0D0 emissive (accent). 3 hues total.
Params: height, tilt, seed (cord sag variation).
```

Three to six lines each. If you cannot write the ratios, you are not ready to code —
guessing them from primitives one at a time is how models drift into mush.

## Part decomposition

Decompose into **named parts**, each one or two primitives, arranged in a parent `Node`
hierarchy so proportions stay adjustable per part. 3–7 parts for a prop; more only for
vehicles/buildings. If a part needs custom vertices, isolate it in its own builder
function — never hand-tune vertex arrays inline in the assembly.

Common decompositions that work:

| Subject | Parts (primitive per part) |
| --- | --- |
| Tree | trunk `CylinderGeometry` (taper via topRadius), canopy 2–3 `IcosphereGeometry` (noise-jittered), optional fruit `SphereGeometry` |
| Lamp post | pole `CylinderGeometry`, cap `SphereGeometry`, arm `TubeGeometry` along a bent path, head `CylinderGeometry` + `DiscGeometry` lens |
| Crate | body `CuboidGeometry`, corner brackets 4× `WedgeGeometry` or inset `CuboidGeometry`, edge trim thin `CuboidGeometry` strips |
| Robot/character | torso `CapsuleGeometry`, head `SphereGeometry`, eyes 2× small `SphereGeometry` (unlit), limbs `CapsuleGeometry`, joints `SphereGeometry` |
| Mushroom | cap: profile lathed via `MeshAccumulator` (see procedural reference), stem `CylinderGeometry` |
| Ringed planet | body `SphereGeometry`, ring `RingGeometry` tilted, moon `SphereGeometry` |
| Vehicle body | chassis `CuboidGeometry` + `WedgeGeometry` cabin, wheels 4× `CylinderGeometry` rotated, lights small unlit `CuboidGeometry` |
| Building | massing 2–3 `CuboidGeometry`, roof `WedgeGeometry`, windows instanced `PlaneGeometry` grid or emissive unlit quads |

**Overlap, don't abut.** Parts must interpenetrate slightly (10–20% of the smaller part).
Butt joints show seams from every angle except the one you designed in; overlaps read as
solid construction from all views.

## Proportion rules of thumb

- **Footprint vs height**: props that need to feel stable ≈ 1:2 (crate) to 1:3 (lamp).
  Anything slimmer than 1:4 needs a visual counterweight (wider base, splayed feet).
- **Three-zone split**: divide the height in thirds and assign each third a distinct
  mass/shape. Even splits of identical mass read as "stacked boxes".
- **Characters**: ~3 heads tall for cute/stylized, ~7 for realistic. Stylized wins for
  realtime: bigger head = readable silhouette at distance.
- **Deliberate asymmetry beats even symmetry** for organic subjects (tilt the canopy,
  sag the cord, offset the roof). For tools/props, symmetry with one broken element
  (one handle, one lever) gives the "used" story.
- Scale is arbitrary (no physics), but **one model = one unit story**: pick "1 unit = 1 m"
  or "1 unit = character height" and keep every ratio relative to it, so it drops into a
  scene correctly.

## The silhouette test (blockout gate)

Build the whole model in one flat mid-value color (e.g. `0xFF9AA2B1`-ish gray, or the
dominant palette color). Then capture four orthographic-feeling views — front, side,
three-quarter, top — and ask per view:

- Can I name the object from this outline alone?
- Is there a distinct 2D shape rhythm (not "rectangle, rectangle, rectangle")?
- Do any two parts visually merge into a blob from this angle? (Separate by offsetting,
  not by shrinking — silhouette gaps between parts are free detail.)

If any view fails, fix proportion/arrangement **before** adding anything else. This gate
is the highest-leverage 5 minutes of the whole process.

## Refinement order (strict)

1. **Proportions** — change part dims/offsets (cheap, param-level).
2. **Breaks and overlaps** — parts read as joined construction, not floating debris.
3. **Edge softening** — hard edges scream "programmer art". Options: swap `CuboidGeometry`
   for `CapsuleGeometry`/`WedgeGeometry` where it reads, inset panels (smaller cuboid
   slightly proud of the surface), or torus trim along an edge (`TorusGeometry` around the
   rim). You cannot bevel `CuboidGeometry` itself — compose instead.
4. **Focal-zone detail only** — the part the camera actually sees (usually the ⅓ of the
   model nearest the viewer) gets greebles/panel lines/noise displacement; the far side
   stays chunky. Detail economy is what makes it look *designed* rather than *noisy*.
5. **Materials and look** — palette pass, then the official `flutter_scene-looks` presets
   for lighting/post. A great model in a default-lit scene still looks amateur.

## Palette discipline

- **4 hues max**, roles: dominant (~60% of surface), secondary (~30%), accent (~8%),
  neutral dark/light for grounding. Write them as ARGB in the design sheet.
- Saturation carries mood; value carries readability. When in doubt, keep hues close and
  push **value** contrast between the silhouette and its interior.
- Lifecycle/semantic colors (green = verified, red = failed, amber = open — the ecsly
  convention) override palette rules: semantics first, decoration around them.
- Materials tell the material story with **factors, not textures**: plastic =
  `metallicFactor 0, roughnessFactor ~0.35, clearcoat ~0.6`; metal = `metallicFactor 1,
  roughnessFactor ~0.3`; rubber = `metallic 0, roughness ~0.9`; wood = `metallic 0,
  roughness ~0.7`; glow = `UnlitMaterial` or high `emissiveFactor`. Exact recipes in the
  procedural reference.

## Style lock

Pick ONE style per project and write it in the design sheet; never mix within a scene:

| Style | Geometry | Material |
| --- | --- | --- |
| Low-poly flat | `IcosphereGeometry` (subdivisions 1–2), flat-ish shading, faceted | PBR roughness ~0.8, no textures |
| Chunky toon | capsules/spheres, fat rounded edges, 3–7 parts | clearcoat plastic factors, saturated palette |
| Realistic-ish PBR | swept profiles, panel insets, higher tessellation | full factor set, textures if sourced |
| Neon/unlit | simple silhouettes, polyline accents | `UnlitMaterial` + emissive + the looks skill's bloom |

## The critique checklist (run against every capture)

1. Silhouette: nameable from all four views?
2. One idea: can you state the model's single design idea in a sentence?
3. Proportions: match the sheet? (Drift from the written ratios is the #1 failure.)
4. Overlaps: no butt seams, no floating parts, contacts grounded?
5. Palette: ≤ 4 hues, roles respected, accents only on focal elements?
6. Materials: consistent style; factors tell one material story?
7. Focal zone: detail where the camera looks, calm elsewhere?
8. Grounding: sits on the ground plane with contact (drop shadow via the looks skill)?
9. Variation: if part of a scatter/crowd, do seed-driven variants differ meaningfully?

Every critique yields **one** named change. Iterate. Stop when three consecutive passes
change nothing — that is "done", not "perfect".

## Parameterization contract

```dart
class LampParams {
  const LampParams({
    this.height = 1.6,
    this.tiltDeg = 30,
    this.seed = 7,
  });
  final double height;
  final double tiltDeg;
  final int seed;
}

/// Builds the model as a detached Node subtree. No scene access, no
/// side effects — callers position/parent it.
Node buildDeskLamp(LampParams p) { ... }
```

- Builder returns a `Node` (subtree root); the caller owns placement.
- All randomness from `p.seed`. `FastNoiseLite(p.seed)` for fields, `Random(p.seed)` for
  picks — same params, same model, forever.
- Named params over positional so a variant is a one-token diff.
- Keep a `variants` map or list of `Params` for the 2–3 variants you actually need, rather
  than promising configurability you won't verify.
