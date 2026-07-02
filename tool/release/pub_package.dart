import 'dart:convert';
import 'dart:io';

enum _PubTool {
  dart('dart'),
  flutter('flutter');

  const _PubTool(this.command);

  final String command;
}

class _PackageSpec {
  const _PackageSpec({
    required this.name,
    required this.path,
    required this.tool,
  });

  final String name;
  final String path;
  final _PubTool tool;
}

const _packageOrder = <_PackageSpec>[
  _PackageSpec(name: 'ecsly', path: 'core_packages/ecsly', tool: _PubTool.dart),
  _PackageSpec(
    name: 'ecsly_app',
    path: 'core_packages/ecsly_app',
    tool: _PubTool.dart,
  ),
  _PackageSpec(
    name: 'ecsly_codegen',
    path: 'core_packages/ecsly_codegen',
    tool: _PubTool.dart,
  ),
  _PackageSpec(
    name: 'ecsly_flutter',
    path: 'core_packages/ecsly_flutter',
    tool: _PubTool.flutter,
  ),
];

final _packages = {for (final package in _packageOrder) package.name: package};

void main(List<String> args) async {
  final options = _Options.parse(args);
  final targets = options.all
      ? _packageOrder
      : [_targetFromTag(options.tag ?? Platform.environment['RELEASE_TAG'])];

  for (final target in targets) {
    await _preflight(target, options);
    if (options.execute) {
      await _publish(target);
    }
  }
}

_PackageSpec _targetFromTag(String? tag) {
  if (tag == null || tag.isEmpty) {
    _usage('Missing --tag or RELEASE_TAG.');
  }

  for (final entry in _packageOrder) {
    final prefix = '${entry.name}-v';
    if (tag.startsWith(prefix)) return entry;
  }

  _usage('Unsupported release tag "$tag".');
}

Future<void> _preflight(_PackageSpec package, _Options options) async {
  final pubspec = await _readPubspec(package.path);
  final actualName = pubspec['name'];
  final version = pubspec['version'];

  if (actualName != package.name) {
    _fail(
      '${package.path}/pubspec.yaml declares name "$actualName", expected "${package.name}".',
    );
  }
  if (version == null || version.isEmpty) {
    _fail('${package.name} is missing a version in pubspec.yaml.');
  }

  final expectedTag = '${package.name}-v$version';
  final tag = options.tag ?? Platform.environment['RELEASE_TAG'];
  if (!options.all && tag != expectedTag) {
    _fail(
      'Release tag "$tag" does not match ${package.name} version "$version" ($expectedTag).',
    );
  }

  if (pubspec['publish_to'] == 'none') {
    _fail('${package.name} is marked publish_to: none.');
  }

  await _checkChangelogEntry(package, version);
  _rejectPathOrGitDeps(package);

  if (options.skipExisting && await _isPublished(package.name, version)) {
    stdout.writeln(
      '${package.name} $version is already published; skipping dry-run.',
    );
    return;
  }

  await _run(package.tool.command, [
    'pub',
    'publish',
    '--dry-run',
  ], package.path);
}

Future<void> _publish(_PackageSpec package) async {
  final pubspec = await _readPubspec(package.path);
  final version = pubspec['version']!;

  if (await _isPublished(package.name, version)) {
    stdout.writeln(
      '${package.name} $version is already published; skipping publish.',
    );
    return;
  }

  await _waitForInternalDependencies(package);
  await _run(package.tool.command, ['pub', 'publish', '--force'], package.path);
  await _waitUntilPublished(package.name, version);
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

Future<void> _checkChangelogEntry(_PackageSpec package, String version) async {
  final changelog = File('${package.path}/CHANGELOG.md');
  if (!changelog.existsSync()) {
    _fail('${package.name} is missing CHANGELOG.md.');
  }

  final versionHeading = RegExp(
    r'^##\s+\[?' + RegExp.escape(version) + r'\]?(?:\s|$|\(|-)',
    multiLine: true,
  );
  if (!versionHeading.hasMatch(await changelog.readAsString())) {
    _fail(
      '${package.name} CHANGELOG.md is missing a heading for version $version.',
    );
  }
}

void _rejectPathOrGitDeps(_PackageSpec package) {
  final text = File('${package.path}/pubspec.yaml').readAsStringSync();
  final dependencyBlocks = RegExp(
    r'^(dependencies|dev_dependencies):\n(?<body>(?:^[ \t].*\n?)*)',
    multiLine: true,
  ).allMatches(text);

  for (final block in dependencyBlocks) {
    final body = block.namedGroup('body') ?? '';
    if (RegExp(r'^\s+(path|git):', multiLine: true).hasMatch(body)) {
      _fail('${package.name} pubspec.yaml contains path/git dependency specs.');
    }
  }
}

Future<void> _waitForInternalDependencies(_PackageSpec package) async {
  final dependencies = _readDependencyConstraints(package);
  for (final dependency in dependencies.entries) {
    if (!_packages.containsKey(dependency.key)) continue;

    final version = _minimumVersionFromConstraint(dependency.value);
    if (version == null) {
      _fail(
        '${package.name} depends on ${dependency.key} without a hosted version constraint.',
      );
    }

    await _waitUntilPublished(dependency.key, version);
  }
}

Map<String, String> _readDependencyConstraints(_PackageSpec package) {
  final text = File('${package.path}/pubspec.yaml').readAsStringSync();
  final block = RegExp(
    r'^dependencies:\n(?<body>(?:^[ \t].*\n?)*)',
    multiLine: true,
  ).firstMatch(text);
  final body = block?.namedGroup('body') ?? '';
  final dependencies = <String, String>{};

  for (final match in RegExp(
    r'^\s{2}([A-Za-z_][A-Za-z0-9_]*):\s*(.*)$',
    multiLine: true,
  ).allMatches(body)) {
    dependencies[match.group(1)!] = match.group(2)!.trim();
  }

  return dependencies;
}

String? _minimumVersionFromConstraint(String constraint) {
  final match = RegExp(
    r'(?:\^|>=|>|=)?\s*([0-9]+\.[0-9]+\.[0-9]+(?:[-+][0-9A-Za-z.-]+)?)',
  ).firstMatch(constraint);
  return match?.group(1);
}

Future<void> _waitUntilPublished(String packageName, String version) async {
  const attempts = 18;
  const pause = Duration(seconds: 20);

  for (var attempt = 1; attempt <= attempts; attempt++) {
    if (await _isPublished(packageName, version)) {
      stdout.writeln('$packageName $version is visible on pub.dev.');
      return;
    }

    if (attempt < attempts) {
      stdout.writeln(
        'Waiting for $packageName $version to become visible on pub.dev '
        '($attempt/$attempts)...',
      );
      await Future<void>.delayed(pause);
    }
  }

  _fail('$packageName $version did not become visible on pub.dev.');
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
      _fail('pub.dev lookup for $packageName returned ${response.statusCode}.');
    }

    final payload =
        jsonDecode(await response.transform(utf8.decoder).join())
            as Map<String, dynamic>;
    final versions = (payload['versions'] as List<dynamic>? ?? const [])
        .cast<Map<String, dynamic>>()
        .map((entry) => entry['version'])
        .whereType<String>();
    return versions.contains(version);
  } on SocketException catch (error) {
    _fail('pub.dev lookup for $packageName failed: $error.');
  } on TlsException catch (error) {
    _fail('pub.dev lookup for $packageName failed: $error.');
  } on FormatException catch (error) {
    _fail('pub.dev lookup for $packageName returned invalid JSON: $error.');
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
  if (message.isNotEmpty) stderr.writeln(message);
  stderr.writeln(
    'Usage: dart tool/release/pub_package.dart --tag <package-vversion> [--execute] [--skip-existing]',
  );
  stderr.writeln(
    '       dart tool/release/pub_package.dart --all [--execute] [--skip-existing]',
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
    if (!all && tag == null && Platform.environment['RELEASE_TAG'] == null) {
      _usage('Missing --tag or RELEASE_TAG.');
    }

    return _Options(
      tag: tag,
      execute: execute,
      skipExisting: skipExisting,
      all: all,
    );
  }
}
