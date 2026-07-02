# ecsly_codegen

Typed-column factory codegen for [`ecsly`](https://pub.dev/packages/ecsly).

`ecsly_codegen` provides the `@EcsComponent` annotation and a `build_runner`
builder that emits `ColumnFactory` and `FacadeFactory` boilerplate for SoA
extension components. The ECS runtime stays in `ecsly`; this package owns
annotations and generated source only.

**Status:** published prerelease. Pin the `dev` version deliberately.

**Compatibility:** `ecsly_codegen` `0.1.0-dev.x` requires `ecsly` `>=0.0.1-dev.9`.

Further docs: [DX_FAQ.md](DX_FAQ.md) (how) · [DESIGN_FAQ.md](DESIGN_FAQ.md) (why)

## Install

Add to a component or plugin package that defines marker components:

```yaml
dependencies:
  ecsly: ^0.0.1-dev.9
  ecsly_codegen: ^0.1.0-dev.1

dev_dependencies:
  build_runner: ^2.7.1
```

`ecsly_codegen` belongs in `dependencies` (not only `dev_dependencies`) because
its `build.yaml` builder auto-applies to dependents.

Monorepo/workspace packages may use key-only entries (`ecsly:` /
`ecsly_codegen:`) or local path overrides while developing multiple packages
together.

## Package chooser

| Need | Package | Public status |
|------|---------|---------------|
| Hot simulation | `ecsly` | Public package |
| Cold app path | `ecsly_app` | Published prerelease |
| Typed-column builders | `ecsly_codegen` | Published prerelease |
| Flutter host | `ecsly_flutter` | Published prerelease |

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

### 3. Register with a World

Generated factories are inert until registered:

```dart
final world = World();
world.components.registerExtension<PositionComponent, Position>(
  columnFactory: PositionColumnFactory(),
  facadeFactory: PositionFacadeFactory(),
);
world.flush();
```

See [example/main.dart](example/main.dart) for a runnable end-to-end sample.

## When to use codegen

| Use codegen | Hand-write factories instead |
|-------------|------------------------------|
| `FloatColumn`, `IntColumn`, `Uint8Column` | `ObjectColumn` (cold / variable-length data) |
| Fixed stride per entity | Custom column construction logic |
| Standard facade wiring | Non-standard `initialize` behavior |

## Limitations

- Generates factories only — extension type facades stay hand-written.
- Typed columns only (`float32`, `int32`, `uint8`). `uint8` ignores `stride`.
- Marker classes must `extend Component`.
- Plugin/world registration (`registerExtension`) is always manual.

## Related packages

- [`ecsly`](https://pub.dev/packages/ecsly) — ECS runtime
- Production consumers register generated factories from their owning package.
