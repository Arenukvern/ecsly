---
name: stylized-3d-craft
description: >-
  Art direction plus the score-and-fix critique process for stylized 3D that reads
  hand-made and alive — the Tiny Glade / Monument Valley / A Short Hike /
  felted-stop-motion bar — in ANY engine (flutter_scene, three.js, Unity, Godot,
  Blender, SDF/WebGL shaders, CSS 3D). Use whenever building, styling, or polishing
  a 3D scene, diorama, character, creature, pet, prop, or environment, and whenever
  the ask is "make it cuter / cozier / charming / alive", "it looks flat / dead /
  generic / like a default demo", or a named style anchor like "Tiny Glade style".
  Pairs with engine skills (flutter-scene-modeling, flutter_scene-looks, three):
  this skill owns WHAT good looks like and the critique loop; the engine skill owns
  the APIs.
---

# Stylized 3D craft (engine-agnostic)

Mission: work that reads **hand-made and alive**, not as a default engine demo.
Reference bar: Tiny Glade, Monument Valley, A Short Hike, felted stop-motion. The gap
between "renders correctly" and "feels crafted" is a list of small, checkable
decisions — every rule below is one, and none are optional. The craft is the
constant; only the API changes between engines.

## How this composes with engine skills

This skill is the art director. An engine skill is the builder. They compose, never
compete:

| Concern | Owner |
| --- | --- |
| Style anchor, palette, form language, story, life, signature moment | **this skill** |
| Scoring captures against the rubric, the critique loop, the ship gate | **this skill** |
| APIs, geometry builders, run/capture mechanics, look presets, perf tools | **the engine skill** |

Working agreement:

1. **Pick the engine skill first and read its idioms before any code.** flutter_scene
   → `flutter-scene-modeling` (plus the six official `flutter_scene-*` skills,
   especially `-looks` for lighting/post and `-idioms` for traps); web 3D → `three`;
   raw shaders → `typegpu`.
2. **Capture frames per that skill's verification loop** (flutter_scene: let
   auto-exposure settle, screenshot + console, four views; three: deterministic seek
   + screenshot). **Never critique a frame you imagined — only a frame you rendered.**
3. **Score the capture against the rubric below.** Engine-scope checklists (e.g.
   flutter-scene-modeling's design-craft checklist) feed items 1–6; this rubric is
   the full scorecard — it adds life, interaction feel, and the signature moment,
   which model-scope checklists don't cover.
4. **Apply fixes through the engine skill's seams** (its params objects, presets,
   builder functions) — never by reaching around it into raw API fiddling.

## Process contract

1. **Build v1 fast, rough, complete.** Blockout per the engine skill: whole scene,
   flat materials, no detail yet.
2. **STOP. Re-render. Score EVERY rubric item 0/1/2** against the actual capture.
   For every item scoring 0–1, write the **named problem** — not "polish lighting"
   but "ground is flat #888, no tonal variation, no contact shadows".
3. **Fix the lowest scores first. One named fix per pass.** Re-score after each pass.
   Twelve tweaks per pass is how you lose the plot; one fix per pass keeps cause and
   effect legible.
4. **Minimum 3 critique passes.** Ship only when no item is below 1 AND the
   signature-moment item is 2.
5. **End with a 5-line changelog**: what each pass changed and why.

Never ship the first render. Never "polish" blindly — name the problem, then apply
the specific fix.

Keep a visible critique log as you go; it is the receipt of the process:

```text
## Pass 1 — v1 blockout, three-quarter capture
anchor     1  palette obeys anchor, form doesn't (sharp boxes vs chunky rounding)
palette    1  ground flat #888, zero tonal variation between adjacent surfaces
contact    0  pot floats; no shadow blob, no sink into the soil
idle       0  dead mesh — zero motion at rest
scales     1  hero + mid props only; nothing survives zoom-in
signature  0  unnamed → DECIDE NOW: the snail eating moss on the roof
→ fix order this pass: contact, then idle
```

## The style sheet (write before building)

For anything meant to look crafted, write these five lines next to the engine
skill's design sheet (intent/parts/ratios — they compose; both get written):

```markdown
Anchor:    Tiny Glade diorama — chunky rounded stone, mossy warmth, toy scale
Palette:   warm plaster #E8DCC8 (dominant), oak #B08954, moss #7A8B5E (accent),
           slate #5C5662 (cool counterpoint), fog/page #EFE9DC
Materials: all matte (roughness ≥ 0.8), zero metal; plaster vs stone differ ~8% tone
Light:     warm key upper-front-left, cool rim right-rear, soft ambient; tinted shadows
Signature: the crooked chimney with a snail on it, trailing a silver line
```

One style anchor, **named and specific** — "cute 3D" is not an anchor. When unsure
about any decision, ask "what would the anchor do?" and obey it.

## Art direction

- **Palette ≤ 5 colors**: 2–3 warm neutrals + 1 accent + 1 cool counterpoint.
  Background == fog == page color — the scene must dissolve into its page; that is
  what makes a diorama feel like a kept object. No pure #000 or #fff anywhere;
  shadows are tinted toward the cool counterpoint, never black.
- **Materials matte**: roughness ≥ 0.8, zero metal unless the anchor demands it.
  Adjacent parts differ slightly in tone (~5–10%) — a flat single-color surface reads
  unfinished even when the form is right.
- **Light like a storybook**: warm key from the upper side, cool rim from the
  opposite side, soft ambient fill. Shadows soft and tinted. Tone mapping ON
  (ACES / AgX / filmic) — raw linear output is an instant fail.

## Form language

- **Characters**: head ≈ 40–60% of body height, chunky limbs, tiny feet. Cuteness is
  ratio, not decoration — no bow fixes a seven-heads-tall body.
- **Build from squashed/stretched primitives that EMBED 10–30% into each other.**
  Parts that merely touch, or float 1 mm apart, are bugs, not style — butt joints
  show seams from every angle except the one you designed in.
- **Silhouette test**: squint / outline-only — the subject must be identifiable
  without interior detail. If it fails, RESHAPE, don't re-texture.
- **One asymmetry + one imperfection per organic subject** (crooked scarf, drooped
  ear, leaf on the head). Perfection reads as CG.
- **Bevel or fillet every hard edge.** A default sharp box is a fail; if the engine
  can't bevel the primitive, compose the rounding (capsule swaps, torus trim along
  rims, inset panels slightly proud of the surface).

## Scene & storytelling

- **Every prop implies a story**: footprints, wear, leftovers, weather. A model on
  an empty plane is a render test, not a scene.
- **Contact is visual law**: soft contact-shadow blob + slight sink under everything
  resting on a surface. Nothing hovers.
- **Three scales of detail**: hero forms / mid props / micro detail (pebbles, tufts,
  tracks) that only reveals on zoom. Detail that doesn't survive zoom-in is
  decoration; detail at three scales is a world.
- **Environmental particles**: sparse, slow, mood-matched (snow, motes, fireflies).
  Fast dense particles read as noise.
- **Staging**: the camera is the narrator — three-quarter view, hero off-center, at
  least one foreground/midground/background layer. A centered subject on empty
  ground with a horizon-line camera is a render test again.

## Life & interaction

- **Alive at rest**: ≥ 3 idle motions (breathing ±1–3% scale, sway, randomized
  blinks, twitches). The frozen-frame test: a still of the final scene must look
  mid-motion.
- **Characters subtly track the viewer** where the medium allows (lookAt /
  billboard); a face that follows you slightly is what makes a creature feel aware.
- **Every reaction**: anticipation → squash & stretch → settle. All easing
  non-linear (ease-out or springs). Linear tweens are a fail.
- **Every input answers within ~100 ms** (one to two frames): hover pop, press
  reaction, sound synthesized in code where audio exists. No visual + no sound =
  dead input.
- **Gentle auto-drift when idle**, paused during user input. Honor the medium's
  reduced-motion signal (`prefers-reduced-motion` / disableAnimations).

## Technical floor

- **Procedural everything**: textures from canvas/noise, geometry from primitives.
  No external assets unless explicitly provided.
- **Shadow settings tuned, not defaults** — bias / normal bias / softness set on
  purpose; visible acne or peter-panning is a fail.
- **Budget**: pixel ratio ≤ 2, capped dt, zero per-frame allocations in the hot loop.
- **Graceful entrance**: short camera dolly + fade; controls unlock after. The first
  frame is a poster, not a slap.

## Rubric (score every item, every pass)

Anchors: **0** = violated or absent · **1** = present but weak, partial, or
arguable · **2** = deliberate and visible — you can point at the pixels that prove
it.

1. Style anchor named and consistently obeyed
2. Silhouette identifies the subject at thumbnail size (shrink the capture to
   ~120 px and look again)
3. Palette ≤ 5, background == fog == page, no pure black/white
4. No default / flat-unlit / raw-linear materials anywhere
5. Parts embedded; nothing floating or just-kissing
6. Contact shadows under every resting object
7. ≥ 3 idle motions; the frozen frame looks mid-motion
8. Non-linear easing; input feedback < 100 ms
9. ≥ 3 scales of detail; detail survives zoom-in
10. **SIGNATURE MOMENT** — name the ONE thing a viewer would describe to a friend.
    If you can't name it, build it. This item must reach 2 before shipping.

## Instant fails — fix before anything else

- Default lighting rig, unlit/basic materials, unshadowed scene
- Perfect bilateral symmetry on an organic subject
- Subject centered on an empty ground, no framing idea
- Correct geometry, zero motion ("dead scene")
- Linear easing, instant snaps, no input feedback

## Engine translation

Rules are engine-agnostic — translate, don't skip. "Squashed primitives" → sculpt
or booleans; "soft shadows" → the engine's best approximation; "camera tracking" →
lookAt or billboards. Before mapping terms by guess, read
[references/engine-translation.md](references/engine-translation.md): several
engines have proven values and known traps already worked out (flutter_scene's
shadow-catcher-on-dark pitfall, key-intensity wash, bevel-by-composition; three.js's
tone-mapping/color-space pair).
