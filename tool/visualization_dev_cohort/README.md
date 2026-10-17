# Resident code-edit cohort

This separate consumer reuses Oka's existing experimental dev-session entrypoint,
Flutter's retained DDC session, the shared CDP surface, and a generated studio app.
The prebuilt dogfood tool remains free of the dev harness. Paths are explicit inputs;
configure writes an ignored editable-owner binding instead of committing file URLs.

```sh
dart run configure.dart --oka-root /path/to/oka --automation-root /path/to/dart_flutter_packages --toolkit-root /path/to/mcp_flutter
dart pub get
dart run ../../.agents/skills/ecsly-visualization/scripts/scaffold.dart ./output/consumer --flutter-bin /path/to/flutter/bin/flutter
dart run bin/supervise.dart ./output/consumer /path/to/flutter/bin/flutter ./output/trial-1
```

The consumer must carry scaffold provenance. Only its copied token package is edited
and restored. Method, compatible signature and new-import changes are applied through
one owning Oka/Flutter session, while document, camera, selection and resident identity
are checked after each. The browser is headless; no bring-to-front call is made.
Source/receipts and GPU pixels remain separate evidence. Runtime errors and teardown
fail the trial. Cold bring-up has a four-minute observation bound; the underlying
runner's launch/ownership cancellation must separately qualify against forced failure.

Exact editable versions and source ownership must be preserved with receipts before
using results as a benchmark. Three successful edits are a small compatibility cohort,
not a guarantee for every signature, deletion, dependency change or application scale.

`bin/supervise.dart` declares one bounded Oka job, retains plan/facts/worker receipts
and reports success only after the cohort and owned teardown complete. New trials
require new evidence directories. `process-lines.json` separates Flutter's compiler
acknowledgements from total code-effect observations. The final three-edit trial
passed after correcting duplicated reload ownership and removing the runner's
4,000 ms workaround delay from the acknowledged path. Later edits were observed
in about 222 ms, with unchanged runtime and no exceptions; this is not a cold-start
or arbitrary-code-edit guarantee. Debug process lines can contain local service
endpoints and remain private, ignored trial evidence.
