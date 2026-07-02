import 'dart:convert';
import 'dart:io';

const _packages = <String, String>{
  'core_packages/ecsly': 'ecsly',
  'core_packages/ecsly_app': 'ecsly_app',
  'core_packages/ecsly_codegen': 'ecsly_codegen',
  'core_packages/ecsly_flutter': 'ecsly_flutter',
};

void main(List<String> args) {
  final check = args.contains('--check');
  final unknown = args.where((arg) => arg != '--check').toList();
  if (unknown.isNotEmpty) {
    stderr.writeln('Unknown argument: ${unknown.join(' ')}');
    stderr.writeln(
      'Usage: dart tool/release/sync_release_pubspec_versions.dart [--check]',
    );
    exit(64);
  }

  final manifest = _readManifest();
  final drift = <String>[];

  for (final entry in _packages.entries) {
    final packagePath = entry.key;
    final packageName = entry.value;
    final expectedVersion = manifest[packagePath];
    if (expectedVersion == null || expectedVersion.isEmpty) {
      _fail('Missing $packagePath in .release-please-manifest.json.');
    }

    _validatePubVersion(packageName, expectedVersion);

    final pubspec = File('$packagePath/pubspec.yaml');
    if (!pubspec.existsSync()) {
      _fail('Missing ${pubspec.path}.');
    }

    final original = pubspec.readAsStringSync();
    final versionLine = RegExp(
      r'^version:\s*(.+)$',
      multiLine: true,
    ).firstMatch(original);
    if (versionLine == null) {
      _fail('${pubspec.path} has no top-level version field.');
    }

    final actualVersion = versionLine.group(1)!.trim();
    if (actualVersion == expectedVersion) continue;

    drift.add('${pubspec.path}: $actualVersion -> $expectedVersion');

    if (!check) {
      final updated = original.replaceFirst(
        RegExp(r'^version:\s*.+$', multiLine: true),
        'version: $expectedVersion',
      );
      pubspec.writeAsStringSync(updated);
    }
  }

  if (drift.isEmpty) {
    stdout.writeln('release pubspec versions are in sync');
    return;
  }

  if (check) {
    stderr.writeln('release pubspec version drift:');
    for (final line in drift) {
      stderr.writeln('- $line');
    }
    exit(1);
  }

  stdout.writeln('synchronized release pubspec versions:');
  for (final line in drift) {
    stdout.writeln('- $line');
  }
}

Map<String, String> _readManifest() {
  final file = File('.release-please-manifest.json');
  if (!file.existsSync()) {
    _fail('Missing .release-please-manifest.json.');
  }

  final decoded = jsonDecode(file.readAsStringSync());
  if (decoded is! Map<String, dynamic>) {
    _fail('.release-please-manifest.json must be a JSON object.');
  }

  return decoded.map((key, value) => MapEntry(key, value.toString()));
}

void _validatePubVersion(String packageName, String version) {
  final pubVersion = RegExp(
    r'^[0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z.]+)?(?:\+[0-9A-Za-z.]+)?$',
  );
  if (!pubVersion.hasMatch(version)) {
    _fail('$packageName manifest version is not pub-compatible: $version');
  }

  if (version.contains('+-')) {
    _fail(
      '$packageName manifest version has invalid empty build metadata: $version',
    );
  }
}

Never _fail(String message) {
  stderr.writeln(message);
  exit(1);
}
