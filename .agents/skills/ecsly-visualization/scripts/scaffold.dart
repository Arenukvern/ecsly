import 'dart:convert';
import 'dart:io';

/// Generate from the package-owned example: no second bundled source template.
Future<void> main(List<String> args) async {
  if (args.isEmpty)
    throw ArgumentError(
      'scaffold.dart DEST [--ecsly-root PATH] [--flutter-bin EXEC] [--platforms web,macos] [--renderer canvas|scene]',
    );
  var root = File(
    File.fromUri(Platform.script).resolveSymbolicLinksSync(),
  ).parent;
  for (var i = 0; i < 4; i++) {
    root = root.parent;
  }
  final options = {
    'ecsly-root': root.path,
    'flutter-bin': 'flutter',
    'platforms': 'web',
    'renderer': 'canvas',
  };
  for (var i = 1; i < args.length; i += 2) {
    final key = args[i].replaceFirst('--', '');
    if (i + 1 >= args.length || !options.containsKey(key))
      throw ArgumentError('Unknown/incomplete option ${args[i]}');
    options[key] = args[i + 1];
  }
  if (!['scene', 'canvas'].contains(options['renderer'])) {
    throw ArgumentError('renderer must be scene or canvas');
  }
  final canvas = options['renderer'] == 'canvas';
  final ecsly = Directory(options['ecsly-root']!).resolveSymbolicLinksSync();
  final source = Directory('$ecsly/examples/visualization_studio');
  if (!File('${source.path}/pubspec.yaml').existsSync())
    throw StateError('Canonical example missing: ${source.path}');
  final destination = Directory(args.first).absolute;
  if (destination.existsSync())
    throw StateError('Refusing to overwrite ${destination.path}');
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

  await command(options['flutter-bin']!, [
    'create',
    destination.path,
    '--empty',
    '--platforms=${options['platforms']}',
    '--project-name=ecsly_visualization_studio',
  ]);
  final copied = <String>[];
  void copyTree(Directory from, Directory to) {
    for (final file
        in from
            .listSync(recursive: true, followLinks: false)
            .whereType<File>()) {
      final relative = file.path.substring(from.path.length + 1);
      if (canvas &&
          (relative == 'preview_scene.dart' ||
              relative == 'retained_scene_sink.dart' ||
              relative == 'preview_mapping.dart' ||
              relative == 'measured_scene.dart' ||
              relative == 'preview_contract_test.dart' ||
              relative == 'resident_viewer_test.dart'))
        continue;
      final target = File('${to.path}/$relative')
        ..parent.createSync(recursive: true);
      file.copySync(target.path);
      copied.add(target.path.substring(destination.path.length + 1));
    }
  }

  for (final name in ['lib', 'test', 'assets', 'hook', 'web']) {
    if (canvas && name == 'hook') continue;
    copyTree(
      Directory('${source.path}/$name'),
      Directory('${destination.path}/$name'),
    );
  }
  final tokens = Directory('$ecsly/examples/visualization_tokens');
  final tokenTarget = Directory(
    '${destination.path}/packages/visualization_tokens',
  );
  copyTree(
    Directory('${tokens.path}/lib'),
    Directory('${tokenTarget.path}/lib'),
  );
  File(
    '${tokenTarget.path}/pubspec.yaml',
  ).writeAsStringSync(File('${tokens.path}/pubspec.yaml').readAsStringSync());
  var manifest = File('${source.path}/pubspec.yaml').readAsStringSync();
  for (final name in ['ecsly', 'ecsly_app', 'ecsly_flutter']) {
    manifest = manifest.replaceAll(
      '../../core_packages/$name',
      '$ecsly/core_packages/$name',
    );
  }
  manifest = manifest
      .replaceAll(
        '../../plugins/ecsly_flutter_scene',
        '$ecsly/plugins/ecsly_flutter_scene',
      )
      .replaceAll('../visualization_tokens', 'packages/visualization_tokens');
  if (canvas) {
    manifest = manifest
        .replaceAll(RegExp(r'  ecsly_flutter_scene:\n    path: [^\n]+\n'), '')
        .replaceAll(RegExp(r'  flutter_scene: [^\n]+\n'), '')
        .replaceAll(RegExp(r'  hooks: [^\n]+\n'), '');
    File('${destination.path}/lib/main.dart').writeAsStringSync(
      File('${destination.path}/lib/main_canvas.dart').readAsStringSync(),
    );
  }
  File('${destination.path}/pubspec.yaml').writeAsStringSync(manifest);
  File('${destination.path}/analysis_options.yaml').writeAsStringSync(
    File('${source.path}/analysis_options.yaml').readAsStringSync(),
  );
  await File('${destination.path}/source-provenance.json').writeAsString(
    const JsonEncoder.withIndent('  ').convert({
      'schema': 1,
      'canonicalExample': source.path,
      'renderer': options['renderer'],
      'copiedSourceFiles': copied,
      'note':
          'Source copies with renderer selection; no build artifacts or claim that the working tree matches a commit.',
    }),
  );
  await command(options['flutter-bin']!, ['pub', 'get'], cwd: destination.path);
  if (canvas) {
    final resolved =
        jsonDecode(
              File(
                '${destination.path}/.dart_tool/package_config.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    final names = (resolved['packages'] as List).map(
      (package) => (package as Map)['name'],
    );
    if (names.contains('flutter_scene') ||
        names.contains('ecsly_flutter_scene')) {
      throw StateError('Canvas consumer unexpectedly resolved a scene engine');
    }
  }
  stdout.writeln('Generated from canonical ecsly example: ${destination.path}');
}
