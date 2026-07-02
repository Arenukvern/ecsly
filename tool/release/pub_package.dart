import 'dart:convert';
import 'dart:io';

const _packages = <String, String>{
  'ecsly': 'core_packages/ecsly',
  'ecsly_app': 'core_packages/ecsly_app',
  'ecsly_codegen': 'core_packages/ecsly_codegen',
  'ecsly_flutter': 'core_packages/ecsly_flutter',
};

void main(List<String> args) async {
  final options = _Options.parse(args);
  final targets = options.all
      ? _packages.entries
      : [_targetFromTag(options.tag ?? Platform.environment['RELEASE_TAG'])];

  for (final target in targets) {
    await _preflight(target.key, target.value, options);
    if (options.execute) {
      await _publish(target.key, target.value);
    }
  }
}

MapEntry<String, String> _targetFromTag(String? tag) {
  if (tag == null || tag.isEmpty) {
    _usage('Missing --tag or RELEASE_TAG.');
  }

  for (final entry in _packages.entries) {
    final prefix = '${entry.key}-v';
    if (tag.startsWith(prefix)) {
      return MapEntry(entry.key, entry.value);
    }
  }

  _usage('Unsupported release tag "$tag".');
}

Future<void> _preflight(
  String packageName,
  String packagePath,
  _Options options,
) async {
  final pubspec = await _readPubspec(packagePath);
  final actualName = pubspec['name'];
  final version = pubspec['version'];

  if (actualName != packageName) {
    _fail(
      '$packagePath/pubspec.yaml declares name "$actualName", expected "$packageName".',
    );
  }
  if (version == null || version.isEmpty) {
    _fail('$packageName is missing a version in pubspec.yaml.');
  }

  final expectedTag = '$packageName-v$version';
  final tag = options.tag ?? Platform.environment['RELEASE_TAG'];
  if (!options.all && tag != expectedTag) {
    _fail(
      'Release tag "$tag" does not match $packageName version "$version" ($expectedTag).',
    );
  }

  if (pubspec['publish_to'] == 'none') {
    _fail('$packageName is marked publish_to: none.');
  }

  _rejectPathOrGitDeps(packageName, pubspec);

  if (options.skipExisting && await _isPublished(packageName, version)) {
    stdout.writeln(
      '$packageName $version is already published; skipping dry-run.',
    );
    return;
  }

  await _run('dart', ['pub', 'publish', '--dry-run'], packagePath);
}

Future<void> _publish(String packageName, String packagePath) async {
  final pubspec = await _readPubspec(packagePath);
  final version = pubspec['version']!;

  if (await _isPublished(packageName, version)) {
    stdout.writeln(
      '$packageName $version is already published; skipping publish.',
    );
    return;
  }

  await _run('dart', ['pub', 'publish', '--force'], packagePath);
}

Future<Map<String, String>> _readPubspec(String packagePath) async {
  final file = File('$packagePath/pubspec.yaml');
  final values = <String, String>{};

  for (final line in await file.readAsLines()) {
    final match = RegExp(
      r'^([A-Za-z_][A-Za-z0-9_]*):\s*(.*)$',
    ).firstMatch(line);
    if (match == null) continue;
    values[match.group(1)!] = match.group(2)!.trim().replaceAll('"', '');
  }

  return values;
}

void _rejectPathOrGitDeps(String packageName, Map<String, String> pubspec) {
  final text = File(
    '${_packages[packageName]}/pubspec.yaml',
  ).readAsStringSync();
  final dependencyBlocks = RegExp(
    r'^(dependencies|dev_dependencies):\n(?<body>(?:^[ \t].*\n?)*)',
    multiLine: true,
  ).allMatches(text);

  for (final block in dependencyBlocks) {
    final body = block.namedGroup('body') ?? '';
    if (RegExp(r'^\s+(path|git):', multiLine: true).hasMatch(body)) {
      _fail('$packageName pubspec.yaml contains path/git dependency specs.');
    }
  }
}

Future<bool> _isPublished(String packageName, String version) async {
  final client = HttpClient();
  client.connectionTimeout = const Duration(seconds: 10);
  try {
    final uri = Uri.https('pub.dev', '/api/packages/$packageName');
    final request = await client.getUrl(uri);
    final response = await request.close();
    if (response.statusCode == 404) return false;
    if (response.statusCode != 200) {
      stderr.writeln(
        'pub.dev lookup for $packageName returned ${response.statusCode}; continuing.',
      );
      return false;
    }

    final payload =
        jsonDecode(await response.transform(utf8.decoder).join())
            as Map<String, dynamic>;
    final versions = (payload['versions'] as List<dynamic>? ?? const [])
        .cast<Map<String, dynamic>>()
        .map((entry) => entry['version'])
        .whereType<String>();
    return versions.contains(version);
  } on Object catch (error) {
    stderr.writeln(
      'pub.dev lookup for $packageName failed: $error; continuing.',
    );
    return false;
  } finally {
    client.close(force: true);
  }
}

Future<void> _run(
  String executable,
  List<String> args,
  String workingDirectory,
) async {
  stdout.writeln('> ${[executable, ...args].join(' ')}  ($workingDirectory)');
  final result = await Process.start(
    executable,
    args,
    workingDirectory: workingDirectory,
    mode: ProcessStartMode.inheritStdio,
  );
  final exitCode = await result.exitCode;
  if (exitCode != 0) {
    _fail(
      '${[executable, ...args].join(' ')} failed in $workingDirectory with exit code $exitCode.',
    );
  }
}

Never _usage(String message) {
  stderr.writeln(message);
  stderr.writeln(
    'Usage: dart tool/release/pub_package.dart --tag <package-vversion> [--execute] [--skip-existing]',
  );
  stderr.writeln(
    '       dart tool/release/pub_package.dart --all [--skip-existing]',
  );
  exit(64);
}

Never _fail(String message) {
  stderr.writeln(message);
  exit(1);
}

class _Options {
  const _Options({
    required this.tag,
    required this.execute,
    required this.skipExisting,
    required this.all,
  });

  final String? tag;
  final bool execute;
  final bool skipExisting;
  final bool all;

  static _Options parse(List<String> args) {
    String? tag;
    var execute = false;
    var skipExisting = false;
    var all = false;

    for (var i = 0; i < args.length; i++) {
      final arg = args[i];
      switch (arg) {
        case '--tag':
          if (i + 1 >= args.length) _usage('Missing value for --tag.');
          tag = args[++i];
        case '--execute':
          execute = true;
        case '--skip-existing':
          skipExisting = true;
        case '--all':
          all = true;
        case '--help':
        case '-h':
          _usage('');
        default:
          _usage('Unknown argument "$arg".');
      }
    }

    if (all && tag != null) {
      _usage('Use either --all or --tag, not both.');
    }

    return _Options(
      tag: tag,
      execute: execute,
      skipExisting: skipExisting,
      all: all,
    );
  }
}
