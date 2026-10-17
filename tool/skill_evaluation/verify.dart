import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

/// Verifies captured bytes only; does not score agent behavior.
Future<void> main(List<String> args) async {
  if (args.length != 1) throw ArgumentError('verify.dart SNAPSHOT');
  final root = Directory(args.single).absolute.path;
  final manifest = jsonDecode(
    await File('$root/manifest.json').readAsString(),
  ) as Map<String, dynamic>;
  if (manifest['schema'] != 1) throw StateError('Unsupported manifest');
  final rows = (manifest['files'] as List).cast<Map<String, dynamic>>();
  final digest = sha256.convert(utf8.encode(jsonEncode(rows))).toString();
  if (digest != manifest['digest'])
    throw StateError('Manifest digest mismatch');
  final expected = <String>{};
  for (final row in rows) {
    final path = row['path'] as String;
    final parts = path.split('/');
    if (parts.any((p) => p.isEmpty || p == '.' || p == '..') ||
        path.contains('\\') ||
        path.contains(':') ||
        !expected.add(path)) {
      throw StateError('Invalid or duplicate path: $path');
    }
    var current = '$root/frozen-tree';
    for (final part in parts) {
      current = '$current/$part';
      if (FileSystemEntity.typeSync(current, followLinks: false) ==
          FileSystemEntityType.link) {
        throw StateError('Snapshot link refused: $path');
      }
    }
    final bytes = await File(current).readAsBytes();
    if (bytes.length != row['bytes'] ||
        sha256.convert(bytes).toString() != row['sha256']) {
      throw StateError('Captured bytes changed: $path');
    }
  }
  final tree = Directory('$root/frozen-tree');
  final actual = <String>{};
  await for (final entry in tree.list(recursive: true, followLinks: false)) {
    if (entry is Link) throw StateError('Snapshot link refused: ${entry.path}');
    if (entry is File) actual.add(entry.path.substring(tree.path.length + 1));
  }
  if (actual.length != expected.length || !actual.containsAll(expected)) {
    throw StateError('Snapshot inventory changed');
  }
  final prompts = await File('$root/agent-prompts.json').readAsBytes();
  if (sha256.convert(prompts).toString() != manifest['promptOnlyDigest']) {
    throw StateError('Prompt-only input changed');
  }
  stdout.writeln('Verified ${rows.length} captured files; digest $digest');
}
