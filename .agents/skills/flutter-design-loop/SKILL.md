---
name: flutter-design-loop
description: Iterate Flutter UI, motion, and visuals at hot-reload speed using in-memory fixtures, ecsly plus ecsly_flutter, and optional ecsly_flutter_scene. Design lane is flutter run on desktop, mobile, or Chrome with the VM toolkit. Acceptance lane is built web plus universal_browser_cdp. Oka is an optional build or watch host, not the click driver. Use for design-system polish, animation, linked views, and web or native preview loops. When no product design system exists, critique palette and type with frontend-design; when one exists, that system is the brief. Hand a brand-new explainer scaffold to ecsly-visualization; hand model craft to flutter-scene-modeling.
---

# Flutter design loop

Make one surface answer one question, then change it in the running app.
Prefer the smallest stack that stays coherent while you reload.

| Need | Use |
| --- | --- |
| Text, controls, layout, tokens | Flutter widgets. Design-system theme, not one-off colors. |
| Shared selection, many marks, animation clock, linked views | `ecsly` + `ecsly_flutter` (`EcsAppScope`, `EcsController`, `EcsAction`, typed selectors). One world. |
| Depth or spatial motion | Optional `ecsly_flutter_scene`. Skip it when a widget or Canvas view is enough. |
| Retained web compile or watch, if the repo already has it | Optional Oka. It hosts. It does not tap. |

Do not add a catalog app, a second world, or a scene package to go faster.
Hot reload of the real surface is the fast path.

Brand-new explainer composition and the studio scaffold stay in
[ecsly-visualization](../ecsly-visualization/SKILL.md). After that app exists,
iterate it with this loop. Model silhouette and materials stay in
`flutter-scene-modeling`.

## Two lanes

| Lane | Run | Driver | Proves |
| --- | --- | --- | --- |
| Design | `flutter run -d <desktop\|chrome\|mobile>` on a preview entrypoint with in-memory data | VM service + `ext.mcp.toolkit.*` | Layout, motion, semantics while you reload |
| Acceptance | Built web | `universal_browser_cdp` (`ChromeAppTarget` + CDP). The same stack is the interactive browser driver. | Shipped web, not the debug VM |

Headless acceptance is the default. A visible window is opt-in.
Desktop or Chrome debug is usually the fastest design lane. Use a phone or
tablet target only when the question is that platform's size, input, or safe area.

## Loop

1. Name what a person should see or do. One dominant visual, few controls, one selected detail.
2. Put records in memory (fixture, components, resources). No remote backend required for look and motion.
3. Run the preview. **Hot reload** for widgets, tokens, and curves. **Hot restart** when `main`, a `const` fixture, or a type changes. If the surface has a versioned document or action, push data with a request id and expected revision so labels and motion change without a compiler.
4. **Observe** semantics or accessible names. Save the baseline.
5. **Act once.** Focus before keys. Do not replay a miss.
6. **Verify** a fresh snapshot or a bounded appear/disappear. Focus success is not a state change. A semantics tree is not pixels.
7. Capture the frame before judging alignment, contrast, or motion.
8. Pause a simulation on reload. The host owns time: `EcsFrameSchedule.fixed` with bounded catch-up. Do not advance time in `build` or with a second timer.

Select immutable values from resources. Selecting the mutable resource itself
can compare equal after a write and leave the widget stale.

## Design direction

An existing design system is the brief. Use its tokens, type, motion, and chrome. Do not invent a second palette beside it. For the customer admin panel, that owner is `admin-surface-design` and `packages/ui_kit/DESIGN.md`: kit primitives, the house palette, and the design-canon test.

When the surface has no system, read [frontend-design](../frontend-design/SKILL.md) before choosing palette, type, or layout. Use it as a critique:

- Name the subject, the audience, and the one job of the screen before drawing.
- Spend boldness in one place. Keep everything around it quiet.
- Motion answers an action. One orchestrated moment is enough.
- Copy is navigation. The same verb runs through the control, the result, and the empty state. An empty screen invites the next action. An error names what failed and how to continue.
- Plan tokens and layout, check that plan against the generic defaults in that skill, then build.
- Capture a frame and remove one accessory before calling the pass done.

Do not import that skill's web defaults (new hex palettes, display typefaces, CSS, marketing heroes) into a Flutter screen that already has a theme. A broken route is a design bug: the control and the place it opens must be the same task.

## Motion and visuals

- Short, intentional motion. Respect reduced motion.
- Labels and legends are Flutter overlays, not text meshes.
- Pair color with shape, size, or text. Shared scales. Show uncertainty when you have it.
- Scene camera, polyline width, and pick rays: follow
  [ecsly-visualization](../ecsly-visualization/SKILL.md) rendering notes. Do not
  copy them into every widget screen.
- Check ~320px, the usual window, and a wide window, plus enlarged text.
  Stack panels when labels collide. Keep keyboard and touch targets usable.

## Acceptance

Launch or borrow a browser with an explicit owner. Flutter web semantics are
proxy nodes: use an effect-verified click when a DOM hit-test misses Flutter's
pointer forwarding. Do not force a stale click.

A design-lane pass does not prove release web. An acceptance pass does not
prove hot reload. A widget test does not replace either lane.

Commands, platforms, and non-claims: [references/lanes.md](references/lanes.md).
Stack choice: [references/stack.md](references/stack.md).

## Sources

[references/sources.md](references/sources.md).
