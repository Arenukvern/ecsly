# ecsly examples

Start with the tiny pub.dev entry point:

```bash
dart run example/main.dart
```

Then explore focused examples:

- `basic_world.dart` - spawn entities and query components.
- `scheduled_run.dart` - run a small system schedule.
- `components.dart` - define extension-type and GC-backed components.
- `extension_component.dart` - use factories around extension-type components.
- `commands_and_resources.dart` - queue commands and read/write data-only
  resource state from systems.
- `simd_columns.dart` - stride-2 `simdWindow` integrate, plus a stride-4 `simdView`.
