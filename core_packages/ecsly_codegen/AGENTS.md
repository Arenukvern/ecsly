# ecsly_codegen: Agent Working Agreement

## Goal

Generate typed-column `ColumnFactory` and `FacadeFactory` boilerplate for
`ecsly` extension components. Keep runtime hot paths free of analyzer/build
dependencies.

## Package boundary

- **Owns:** `@EcsComponent`, `EcsColumnType`, build_runner builder (`.ecs.g.dart`).
- **Does not own:** ECS runtime, hand-written extension type facades, plugin
  registration, `ObjectColumn` factories.

## Consumer workflow (full path)

1. Add `ecsly` + `ecsly_codegen` to `dependencies`; `build_runner` to `dev_dependencies`.
2. Annotate `abstract final class XComponent extends Component`.
3. Hand-write `extension type` facade.
4. Add `part 'x.ecs.g.dart';` and run `dart run build_runner build`.
5. Register: `world.components.registerExtension<XComponent, X>(...)`.

See [DX_FAQ.md](DX_FAQ.md) for setup, troubleshooting, and codegen vs manual.

## When to use / not use

| Use codegen | Hand-write |
|-------------|------------|
| `FloatColumn` / `IntColumn` / `Uint8Column` | `ObjectColumn` |
| Standard factory wiring | Custom column logic |

## Compatibility

- `ecsly_codegen` `0.1.0-dev.x` requires `ecsly` `>=0.0.1-dev.9`.
- Publication status: publish-prepared unpublished prerelease. Do not claim a
  live pub.dev package until hosted publication is verified.
- Public API: `package:ecsly_codegen/ecsly_codegen.dart` only (not `src/`).

## Testing

```bash
cd core_packages/ecsly_codegen && dart test
```

Golden tests lock `generateEcsComponentFactories` output. Run
`dart pub publish --dry-run` before release.

## Docs to update

- API / usage change → [DX_FAQ.md](DX_FAQ.md) + [README.md](README.md)
- Boundary / design change → [DESIGN_FAQ.md](DESIGN_FAQ.md)
- Release → [CHANGELOG.md](CHANGELOG.md)

## Reference consumers in repo

- Production plugin consumers (outside this public repo) use generated factories.
