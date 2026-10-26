import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'package:oka_core/oka_core.dart';
import 'package:oka_web/oka_web.dart';

Future<void> main(List<String> args) async {
  if (args.length < 2)
    throw ArgumentError('build.dart PROJECT FLUTTER_SDK [FLUTTER_ARG ...]');
  final startedAt = DateTime.now().toUtc();
  final project = Directory(args[0]).resolveSymbolicLinksSync();
  final context = BuildContext(
    projectPath: project,
    buildDir: '$project/build',
    mode: BuildMode.release,
    config: OkaConfig.empty,
    flutterSdkPath: Directory(args[1]).resolveSymbolicLinksSync(),
  );
  final sources = <Map<String, Object?>>[];
  final sourcePaths = <File>[
    for (final name in [
      'pubspec.yaml',
      'pubspec.lock',
      'analysis_options.yaml',
    ])
      File('$project/$name'),
    for (final name in ['lib', 'web', 'assets', 'hook'])
      if (Directory('$project/$name').existsSync())
        ...Directory('$project/$name')
            .listSync(recursive: true, followLinks: false)
            .whereType<File>(),
  ]..sort((a, b) => a.path.compareTo(b.path));
  for (final file in sourcePaths) {
    if (!file.existsSync()) continue;
    final bytes = file.readAsBytesSync();
    sources.add({
      'path': file.path.substring(project.length + 1),
      'bytes': bytes.length,
      'sha256': sha256.convert(bytes).toString(),
    });
  }
  final sourceDigest = sha256
      .convert(utf8.encode(jsonEncode(sources)))
      .toString();
  final clock = Stopwatch()..start();
  final state = PipelineState();
  final target = WebBuildTarget(
    extraArgs: [
      '--no-pub',
      '--no-web-resources-cdn',
      '--no-wasm-dry-run',
      ...args.skip(2),
    ],
  );
  final result = await Pipeline(target.compile(context))
      .run(context, initialState: state);
  final bundleManifest = result.ok
      ? await WebBundleManifest.capture(Directory('$project/build/web'))
      : null;
  final receipt = {
    'schema': 2,
    'startedAt': startedAt.toIso8601String(),
    'completedAt': DateTime.now().toUtc().toIso8601String(),
    'ok': result.ok,
    'elapsedMs': clock.elapsedMilliseconds,
    'error': result.error,
    'outputs': state.snapshot,
    'compiler': 'Oka WebBuildTarget delegated Flutter release build',
    'mode': 'release',
    'extraArgs': target.extraArgs,
    'dartVersion': Platform.version,
    'flutterSdkRoot': context.flutterSdkPath,
    'consumerSourceDigest': sourceDigest,
    'consumerSources': sources,
    'outputBundle': bundleManifest?.toJson(),
    'provenanceLimit': 'Consumer source and full output file identities; dependency/SDK input closure and reproducible compilation remain unqualified.',
  };
  final archive = File(
    '$project/output/validation/build-trials/${startedAt.microsecondsSinceEpoch}-$pid.json',
  )..parent.createSync(recursive: true);
  if (archive.existsSync())
    throw StateError('Refusing to overwrite build trial');
  final encoded = const JsonEncoder.withIndent('  ').convert(receipt);
  await archive.writeAsString(encoded);
  // Compatibility pointer for callers; immutable trials are authoritative history.
  await File('$project/output/validation/build.json').writeAsString(encoded);
  if (!result.ok) throw StateError(result.error ?? 'Build failed');
}
