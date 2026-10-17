import 'dart:convert';
import 'dart:io';
import 'lazy_shader_patch.dart';
import 'shader_presence_patch.dart';
import 'material_fixture.dart';

Future<void> main(List<String> args) async {
  if (args.length != 4 &&
      !(args.length == 5 && ['lazy', 'structural'].contains(args[4])) &&
      !(args.length == 6 &&
          args[4] == 'structural' &&
          args[5] == 'materials')) {
    throw ArgumentError(
      'NEW_OUTPUT ECSLY_ROOT ENGINE_SOURCE FLUTTER_EXEC [lazy|structural [materials]] required',
    );
  }
  final output = Directory(args[0]).absolute;
  final mode = args.length >= 5 ? args[4] : 'eager';
  final ecsly = Directory(args[1]).resolveSymbolicLinksSync();
  final source = Directory(args[2]).resolveSymbolicLinksSync();
  if (output.existsSync()) throw StateError('refusing existing output');
  final manifest = File('$source/pubspec.yaml').readAsStringSync();
  if (!manifest.contains('version: 0.23.0')) {
    throw StateError(
      'this profile is qualified only against flutter_scene 0.23.0',
    );
  }
  output.createSync(recursive: true);
  final engine = Directory('${output.path}/engine')..createSync();
  final copied = <String>[];
  for (final file in Directory(
    source,
  ).listSync(recursive: true, followLinks: false).whereType<File>()) {
    final rel = file.path.substring(source.length + 1);
    if (rel.split('/').any((s) => ['.dart_tool', 'build', '.git'].contains(s)))
      continue;
    final target = File('${engine.path}/$rel')
      ..parent.createSync(recursive: true);
    file.copySync(target.path);
    copied.add(rel);
  }
  void replace(String path, String before, String after) {
    final file = File('${engine.path}/$path');
    final text = file.readAsStringSync();
    if (before.allMatches(text).length != 1) {
      throw StateError('source drift at $path');
    }
    file.writeAsStringSync(text.replaceFirst(before, after));
  }

  File('${engine.path}/lib/preparation_diagnostics.dart').writeAsStringSync('''
final preparationDiagnostics = PreparationDiagnostics();
class PreparationDiagnostics {
  final List<Map<String, Object?>> _records = [];
  void record(Map<String, Object?> record) => _records.add(record);
  List<Map<String, Object?>> snapshot() => [for (final r in _records) {...r}];
  Future<void> measure(String phase, Future<void> Function() action) async {
    final clock = Stopwatch()..start();
    var ok = false;
    try { await action(); ok = true; }
    finally { record({'phase':phase, 'elapsedUs':clock.elapsedMicroseconds, 'ok':ok}); }
  }
}
''');
  replace(
    'lib/src/scene.dart',
    "import 'dart:async' show Completer, Timer;",
    "import 'dart:async' show Completer, Timer;\nimport 'package:flutter_scene/preparation_diagnostics.dart';",
  );
  for (final function in [
    'loadBaseShaderLibrary',
    'Material.initializeStaticResources',
    'SmaaPass.initializeStaticResources',
  ]) {
    replace(
      'lib/src/scene.dart',
      '$function(),',
      "preparationDiagnostics.measure('$function', $function),",
    );
  }
  replace(
    'lib/src/scene.dart',
    '.then((_) => probePlatformMipSampling())',
    ".then((_) => preparationDiagnostics.measure('probePlatformMipSampling', probePlatformMipSampling))",
  );
  replace(
    'lib/src/gpu/web/_gpu.dart',
    "import 'dart:async';",
    "import 'dart:async';\nimport 'package:flutter_scene/preparation_diagnostics.dart';",
  );
  replace(
    'lib/src/gpu/web/shader_library.dart',
    'static ShaderLibrary _loadFromBytes(ByteData data, {String? assetName}) {',
    'static ShaderLibrary _loadFromBytes(ByteData data, {String? assetName}) {\n    final preparationClock = Stopwatch()..start();',
  );
  replace(
    'lib/src/gpu/web/shader_library.dart',
    'return ShaderLibrary._(shaders);',
    "preparationDiagnostics.record({'phase':'bundleDecodeCompile', 'asset':assetName, 'entries':shaders.length, 'elapsedUs':preparationClock.elapsedMicroseconds});\n    return ShaderLibrary._(shaders);",
  );
  if (mode != 'eager') patchLazyShaders(engine);
  if (mode == 'structural') patchShaderPresence(engine);
  Future<void> command(
    String executable,
    List<String> argv, {
    String? cwd,
  }) async {
    final child = await Process.start(executable, argv, workingDirectory: cwd);
    final pumps = [
      stdout.addStream(child.stdout),
      stderr.addStream(child.stderr),
    ];
    final code = await child.exitCode;
    await Future.wait(pumps);
    if (code != 0) throw ProcessException(executable, argv, 'exit $code', code);
  }

  final consumer = '${output.path}/consumer';
  await command(Platform.resolvedExecutable, [
    '$ecsly/.agents/skills/ecsly-visualization/scripts/scaffold.dart',
    consumer,
    '--ecsly-root',
    ecsly,
    '--flutter-bin',
    args[3],
    '--platforms',
    'web',
    '--renderer',
    'scene',
  ]);
  // This historical lab deliberately targets 0.23, before Scene.dispose existed.
  final viewport = File('$consumer/lib/preview_scene.dart');
  viewport.writeAsStringSync(
    viewport.readAsStringSync().replaceFirst('    _scene?.dispose();\n', ''),
  );
  File('$consumer/pubspec_overrides.yaml').writeAsStringSync(
    'dependency_overrides:\n  flutter_scene:\n    path: ${engine.path}\n'
    '${[
      for (final name in ['ecsly', 'ecsly_app', 'ecsly_flutter']) '  $name:\n    path: $ecsly/core_packages/$name\n',
    ].join()}',
  );
  final viewer = File('$consumer/lib/resident_viewer.dart');
  viewer.writeAsStringSync(
    viewer
        .readAsStringSync()
        .replaceFirst(
          "import 'dart:convert';",
          "import 'dart:convert';\nimport 'package:flutter_scene/preparation_diagnostics.dart';",
        )
        .replaceFirst(
          "'startup': world.getResource<StartupTrace>().toJson(),",
          "'startup': world.getResource<StartupTrace>().toJson(),\n    'enginePreparation': preparationDiagnostics.snapshot(),",
        ),
  );
  if (mode != 'eager') {
    File.fromUri(
      Platform.script.resolve('shader_probe_web.dart.template'),
    ).copySync('$consumer/lib/shader_probe_web.dart');
    if (mode == 'structural') {
      final probe = File('$consumer/lib/shader_probe_web.dart');
      probe.writeAsStringSync(
        probe
            .readAsStringSync()
            .replaceFirst(
              "final shader = library['UnlitFragment'];",
              "final beforePresence = preparationDiagnostics.snapshot().where((r) => r['phase'] == 'deferredShaderCompile').length;\n  if (!library.hasEntry('UnlitFragment') || library.hasEntry('missing-probe-entry')) throw StateError('presence contract');\n  final afterPresence = preparationDiagnostics.snapshot().where((r) => r['phase'] == 'deferredShaderCompile').length;\n  if (beforePresence != afterPresence) throw StateError('presence compiled a shader');\n  final shader = library['UnlitFragment'];",
            )
            .replaceFirst(
              "'lookupCached': true,",
              "'structuralPresenceNoCompile': true,\n    'lookupCached': true,",
            ),
      );
    }
    File(
      '$consumer/lib/shader_probe_stub.dart',
    ).writeAsStringSync('void installShaderProbe() {}\n');
    final main = File('$consumer/lib/preview_app.dart');
    main.writeAsStringSync(
      main
          .readAsStringSync()
          .replaceFirst(
            "import 'multi_view_host.dart';",
            "import 'multi_view_host.dart';\nimport 'shader_probe_stub.dart' if (dart.library.js_interop) 'shader_probe_web.dart';",
          )
          .replaceFirst(
            'SemanticsBinding.instance.ensureSemantics();',
            'SemanticsBinding.instance.ensureSemantics();\n  installShaderProbe();',
          ),
    );
  }
  if (args.length == 6) installMaterialFixture(consumer);
  File('${output.path}/provenance.json').writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert({
      'source': source,
      'version': '0.23.0',
      'copiedFiles': copied,
      'policy': mode != 'eager'
          ? 'opt-in $mode lookup experiment'
          : 'existing eager preparation; diagnostics only',
      'materialFixture': args.length == 6,
    }),
  );
  await command(args[3], ['pub', 'get'], cwd: consumer);
}
