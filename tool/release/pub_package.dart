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
  _PackageSpec(
    name: 'ecsly_serialization',
    path: 'plugins/ecsly_serialization',
    tool: _PubTool.dart,
  ),
  _PackageSpec(
    name: 'ecsly_replay',
    path: 'plugins/ecsly_replay',
    tool: _PubTool.dart,
  ),
  _PackageSpec(
    name: 'async_parallel',
    path: 'plugins/async_parallel',
    tool: _PubTool.dart,
  ),
  _PackageSpec(
    name: 'ecsly_world_sync',
    path: 'plugins/ecsly_world_sync',
    tool: _PubTool.dart,
  ),
  _PackageSpec(
    name: 'ecsly_world_zones',
    path: 'plugins/ecsly_world_zones',
    tool: _PubTool.dart,
  ),
  _PackageSpec(
    name: 'ecsly_async_parallel',
    path: 'plugins/ecsly_async_parallel',
    tool: _PubTool.dart,
  ),
  _PackageSpec(
    name: 'ecsly_world_sync_bridge',
    path: 'plugins/ecsly_world_sync_bridge',
    tool: _PubTool.dart,
  ),
  _PackageSpec(
    name: 'ecsly_flutter_scene',
    path: 'plugins/ecsly_flutter_scene',
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

  await _runDryRun(package.tool.command, package.path);
}

/// Runs `pub publish --dry-run` and tolerates a warnings-only validation.
///
/// pub's dry-run exits 65 whenever validation reports ANY warning — including
/// advisory ones such as "depends on a pre-release of another package". A
/// real publish with `--force` proceeds through warnings ("publish without
/// confirmation if there are no errors"), so a warnings-only dry-run must not
/// block the release pipeline. Errors still fail.
Future<void> _runDryRun(String executable, String workingDirectory) async {
  stdout.writeln(
    '> $executable pub publish --dry-run  ($workingDirectory)',
  );
  final result = await Process.run(
    executable,
    ['pub', 'publish', '--dry-run'],
    workingDirectory: workingDirectory,
  );
  final output = (result.stdout.toString()) + (result.stderr.toString());
  stdout.write(output);
  final exitCode = result.exitCode;
  if (exitCode == 0) return;

  final hasWarningsOnly =
      output.contains(RegExp(r'Package has [0-9]+ warning')) &&
      !output.contains(RegExp(r'Package has [0-9]+ error')) &&
      !output.contains(RegExp(r'^Error:', multiLine: true));
  if (exitCode == 65 && hasWarningsOnly) {
    stdout.writeln(
      'dry-run reported warnings only; proceeding (a --force publish allows warnings).',
    );
    return;
  }
  _fail(
    '$executable pub publish --dry-run failed in $workingDirectory with exit code $exitCode.',
  );
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

    final constraint = dependency.value;
    if (_minimumVersionFromConstraint(constraint) == null) {
      _fail(
        '${package.name} depends on ${dependency.key} without a hosted version constraint.',
      );
    }

    await _waitUntilConstraintSatisfied(dependency.key, constraint);
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

/// Waits until ANY version of [packageName] published on pub.dev satisfies
/// [constraint]. Waiting for the exact floor version (the old behavior)
/// deadlocks whenever the floor was cut from a release that never published
/// — e.g. `^0.1.0-dev.13` is satisfied by the newer `0.1.0-dev.14`.
Future<void> _waitUntilConstraintSatisfied(
  String packageName,
  String constraint,
) async {
  const attempts = 18;
  const pause = Duration(seconds: 20);

  for (var attempt = 1; attempt <= attempts; attempt++) {
    final published = await _publishedVersions(packageName);
    final satisfying =
        published.where((v) => _satisfiesConstraint(v, constraint)).toList();
    if (satisfying.isNotEmpty) {
      stdout.writeln(
        '$packageName "${constraint}" is satisfied on pub.dev '
        '(latest match: ${satisfying.last}).',
      );
      return;
    }

    if (attempt < attempts) {
      stdout.writeln(
        'Waiting for a published $packageName satisfying "$constraint" '
        '($attempt/$attempts)...',
      );
      await Future<void>.delayed(pause);
    }
  }

  _fail('No published $packageName version satisfies "$constraint".');
}

Future<bool> _isPublished(String packageName, String version) async {
  final versions = await _publishedVersions(packageName);
  return versions.contains(version);
}

/// Post-publish confirmation: waits for THIS exact [version] to become
/// visible on pub.dev before a dependent package's turn runs.
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

Future<List<String>> _publishedVersions(String packageName) async {
  final client = HttpClient();
  client.connectionTimeout = const Duration(seconds: 10);
  try {
    final uri = Uri.https('pub.dev', '/api/packages/$packageName');
    final request = await client.getUrl(uri);
    final response = await request.close();
    if (response.statusCode == 404) return const [];
    if (response.statusCode != 200) {
      _fail('pub.dev lookup for $packageName returned ${response.statusCode}.');
    }

    final payload =
        jsonDecode(await response.transform(utf8.decoder).join())
            as Map<String, dynamic>;
    return (payload['versions'] as List<dynamic>? ?? const [])
        .cast<Map<String, dynamic>>()
        .map((entry) => entry['version'])
        .whereType<String>()
        .toList();
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

/// Splits "major.minor.patch[-prerelease]" (build metadata dropped).
(List<int>, List<String>)? _parseVersion(String version) {
  final core = version.split('+').first;
  final dash = core.indexOf('-');
  final numeric = dash < 0 ? core : core.substring(0, dash);
  final prerelease = dash < 0 ? '' : core.substring(dash + 1);
  final parts = numeric.split('.');
  if (parts.length != 3) return null;
  final numbers = <int>[];
  for (final part in parts) {
    final value = int.tryParse(part);
    if (value == null) return null;
    numbers.add(value);
  }
  return (numbers, prerelease.isEmpty ? const [] : prerelease.split('.'));
}

int _comparePrerelease(List<String> a, List<String> b) {
  if (a.isEmpty && b.isEmpty) return 0;
  if (a.isEmpty) return 1; // a release outranks any prerelease
  if (b.isEmpty) return -1;
  for (var i = 0; i < a.length && i < b.length; i++) {
    final an = int.tryParse(a[i]);
    final bn = int.tryParse(b[i]);
    final int result;
    if (an != null && bn != null) {
      result = an.compareTo(bn);
    } else if (an != null) {
      result = -1; // numeric identifiers rank below alphanumeric
    } else if (bn != null) {
      result = 1;
    } else {
      result = a[i].compareTo(b[i]);
    }
    if (result != 0) return result;
  }
  return a.length.compareTo(b.length);
}

int _compareVersions(String a, String b) {
  final pa = _parseVersion(a);
  final pb = _parseVersion(b);
  if (pa == null || pb == null) return a.compareTo(b);
  for (var i = 0; i < 3; i++) {
    final result = pa.$1[i].compareTo(pb.$1[i]);
    if (result != 0) return result;
  }
  return _comparePrerelease(pa.$2, pb.$2);
}

/// Satisfaction check for the constraint shapes internal deps use:
/// `^x.y.z[-pre]` (caret), `>=x.y.z[-pre]` (floor), `=x.y.z` (exact).
bool _satisfiesConstraint(String version, String constraint) {
  final trimmed = constraint.trim();
  final lower = _minimumVersionFromConstraint(trimmed);
  if (lower == null) return false;
  if (_compareVersions(version, lower) < 0) return false;

  if (trimmed.startsWith('=')) return version == lower;
  if (!trimmed.startsWith('^')) return true; // `>=` floor: no upper bound

  final parsedLower = _parseVersion(lower);
  final parsedVersion = _parseVersion(version);
  if (parsedLower == null || parsedVersion == null) return true;
  // Caret upper bound (exclusive): <(major+1).0.0 normally; <0.(minor+1).0
  // when major == 0; <0.0.(patch+1) when major == 0 and minor == 0.
  final lowerNums = parsedLower.$1;
  final upper = lowerNums[0] != 0
      ? [lowerNums[0] + 1, 0, 0]
      : (lowerNums[1] != 0
            ? [0, lowerNums[1] + 1, 0]
            : [0, 0, lowerNums[2] + 1]);
  for (var i = 0; i < 3; i++) {
    if (parsedVersion.$1[i] != upper[i]) {
      return parsedVersion.$1[i] < upper[i];
    }
  }
  // Base tuple equal to the exclusive upper bound: outside the range
  // (its own prereleases included).
  return false;
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
