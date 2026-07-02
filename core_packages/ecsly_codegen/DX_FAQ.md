# ecsly_codegen DX_FAQ - Memory Palace

Developer notes for practical setup and safe integration.

**Requires `ecsly` `>=0.0.1-dev.9`.** `ecsly_codegen` is a published
prerelease; see [README.md](README.md) for hosted and workspace setup.

## Quick setup

Add `ecsly`, `ecsly_codegen`, and `build_runner` to the component package:

```yaml
dependencies:
  ecsly: ^0.0.1-dev.9
  ecsly_codegen: ^0.1.0-dev.1

dev_dependencies:
  build_runner: ^2.7.1
```

Keep `ecsly_codegen` in `dependencies` — the builder auto-applies via `build.yaml`.

## Package chooser

| Need | Package | Status |
|------|---------|--------|
| Systems, queries, hot loops | `ecsly` | Public package |
| Actions, drafts, invalidation, cold lookup | `ecsly_app` | Published prerelease |
| Typed-column builders | `ecsly_codegen` | Published prerelease |
| Widgets, scope, controller | `ecsly_flutter` | Published prerelease |

## First use

Create a marker component, add the generated part directive, and keep the
extension type facade hand-written:

```dart
import 'package:ecsly/ecsly.dart';
import 'package:ecsly_codegen/ecsly_codegen.dart';

part 'velocity.ecs.g.dart';

@EcsComponent(column: EcsColumnType.float32, stride: 2, facade: 'Velocity')
abstract final class VelocityComponent extends Component {}

extension type const Velocity((int, FloatColumn) data) {
  double get dx => data.$2.getValue(data.$1, 0);
  set dx(double value) => data.$2.setValue(data.$1, 0, value);
}
```

Run:

```sh
dart run build_runner build
```

## Register with World

Codegen output is dead code until factories are registered:

```dart
world.components.registerExtension<VelocityComponent, Velocity>(
  columnFactory: VelocityColumnFactory(),
  facadeFactory: VelocityFacadeFactory(),
);
```

Bundle registration in a `Plugin.install` when shipping a reusable component set.

## Generated output

For each marker class, the builder emits:

- `{BaseName}ColumnFactory` — strips a trailing `Component` suffix from the marker name
- `{Facade}FacadeFactory` — uses the `facade:` string, not the marker class name

Example: `TagComponent` with `facade: 'EntityTags'` → `TagColumnFactory` +
`EntityTagsFacadeFactory`.

Supported storage:

| `EcsColumnType` | Column | `stride` |
|-----------------|--------|----------|
| `float32` | `FloatColumn` | honored |
| `int32` | `IntColumn` | honored |
| `uint8` | `Uint8Column` | ignored (one byte per entity) |

## Codegen vs hand-written

| Scenario | Approach |
|----------|----------|
| Hot SoA numeric state (`FloatColumn`, etc.) | `@EcsComponent` + codegen |
| Variable-length / cold data (`ObjectColumn`) | Hand-write `ColumnFactory` + `FacadeFactory` |
| Custom `createColumn` logic | Hand-write |
| Plugin shipping many typed components | Codegen per component + `registerExtension` in `Plugin` |

## Boundary

Do not import `ecsly_codegen` from runtime-only packages. Component packages and
test fixtures may depend on it where annotations are present.

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| `part 'x.ecs.g.dart'` not found | Run `dart run build_runner build` |
| Stale generated API | `dart run build_runner build --delete-conflicting-outputs` |
| `ComponentNotRegisteredError` | Call `registerExtension` with generated factories |
| Wrong factory class name | Check `facade:` — `FacadeFactory` uses that name, not the marker class |
| `@EcsComponent` build error on class | Marker must be a `class` that `extends Component` |
| `stride must be > 0` | Set `stride` to at least `1` for `float32` / `int32` |
| `facade must be a valid Dart identifier` | Use a legal type name (e.g. `Position`, `EntityTags`) |
