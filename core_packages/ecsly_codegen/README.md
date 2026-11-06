# ecsly_codegen

Typed-column factory codegen for [`ecsly`](https://pub.dev/packages/ecsly).

`ecsly_codegen` provides the `@EcsComponent` annotation and a `build_runner`
builder that emits `ColumnFactory` and `FacadeFactory` boilerplate for SoA
extension components. The ECS runtime stays in `ecsly`; this package owns
annotations and generated source only.

Prerelease `0.1.x`: pin your version and follow the
[CHANGELOG](CHANGELOG.md).

Further docs: [DX_FAQ.md](DX_FAQ.md) (how) · [DESIGN_FAQ.md](DESIGN_FAQ.md) (why)

## Install

Add to a component or plugin package that defines marker components:

```sh
dart pub add ecsly ecsly_codegen
dart pub add --dev build_runner
```

`ecsly_codegen` belongs in `dependencies` (not only `dev_dependencies`) because
its `build.yaml` builder auto-applies to dependents.

Monorepo/workspace packages may use key-only entries (`ecsly:` /
`ecsly_codegen:`) or local path overrides while developing multiple packages
together.

## Package chooser

| Need                  | Package         |
| --------------------- | --------------- |
| Hot simulation        | `ecsly`         |
| Cold app path         | `ecsly_app`     |
| Typed-column builders | `ecsly_codegen` |
| Flutter host          | `ecsly_flutter` |

## Use

### 1. Annotate the marker and hand-write the facade

```dart
import 'package:ecsly/ecsly.dart';
import 'package:ecsly_codegen/ecsly_codegen.dart';

part 'position.ecs.g.dart';

@EcsComponent(column: EcsColumnType.float32, stride: 2, facade: 'Position')
abstract final class PositionComponent extends Component {}

extension type const Position((int, FloatColumn) data) {
  double get x => data.$2.getValue(data.$1, 0);
  set x(double value) => data.$2.setValue(data.$1, 0, value);

  double get y => data.$2.getValue(data.$1, 1);
  set y(double value) => data.$2.setValue(data.$1, 1, value);
}
```

### 2. Generate factories

```sh
dart run build_runner build
# or during development:
dart run build_runner watch --delete-conflicting-outputs
```

Generated files use the `.ecs.g.dart` suffix and emit:

- `{BaseName}ColumnFactory` — from the marker class name (`PositionComponent` → `Position`)
- `{Facade}FacadeFactory` — from the `facade` argument (`facade: 'EntityTags'` → `EntityTagsFacadeFactory`)
- `{BaseName}Registration` — one-call `register(World)` handle binding marker,
  facade, and both factories

### 3. Register with a World

Generated factories are inert until registered. Use the generated one-call
registration handle:

```dart
final world = World();
PositionRegistration.register(world);
world.flush();
```

The handle is equivalent to the manual wiring:

```dart
world.components.registerExtension<PositionComponent, Position>(
  columnFactory: PositionColumnFactory(),
  facadeFactory: PositionFacadeFactory(),
);
```

See [example/](example/) for a runnable end-to-end sample.

## When to use codegen

| Use codegen                               | Hand-write factories instead                 |
| ----------------------------------------- | -------------------------------------------- |
| `FloatColumn`, `IntColumn`, `Uint8Column` | `ObjectColumn` (cold / variable-length data) |
| Fixed stride per entity                   | Custom column construction logic             |
| Standard facade wiring                    | Non-standard `initialize` behavior           |

## Scope

- Generates column factories, facade factories, and a one-call registration
  handle; extension type facades stay hand-written so you own the field API.
- Covers the typed columns: `float32`, `int32`, `uint8` (`uint8` ignores
  `stride`). Object columns are registered by hand — see the codegen-vs-manual
  table above.
- Marker classes must `extend Component`.
- Annotated components belong under `lib/`; the builder applies to dependent
  packages' `lib/` sources.

## Related packages

- [`ecsly`](https://pub.dev/packages/ecsly) — ECS runtime
- Production consumers register generated factories from their owning package.
