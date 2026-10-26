import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

Future<void> main(List<String> args) async {
  if (args.length != 2)
    throw ArgumentError('freeze.dart ECSLY_ROOT NEW_OUTPUT');
  final root = Directory(args[0]).resolveSymbolicLinksSync();
  final output = Directory(args[1]).absolute;
  if (output.existsSync()) throw StateError('Refusing existing snapshot');
  final files = <File>[];
  void collect(String relative) {
    final type = FileSystemEntity.typeSync(
      '$root/$relative',
      followLinks: false,
    );
    if (type == FileSystemEntityType.link)
      throw StateError('Source link refused: $relative');
    if (type == FileSystemEntityType.file) {
      files.add(File('$root/$relative'));
      return;
    }
    if (type != FileSystemEntityType.directory)
      throw StateError('Required source absent: $relative');
    for (final entry in Directory(
      '$root/$relative',
    ).listSync(followLinks: false)) {
      collect(entry.path.substring(root.length + 1));
    }
  }

  collect('.agents/skills/ecsly-visualization');
  collect('examples/visualization_studio/validation/skill_history');
  for (final package in ['ecsly', 'ecsly_app', 'ecsly_flutter']) {
    for (final name in ['lib', 'pubspec.yaml', 'AGENTS.md'])
      collect('core_packages/$package/$name');
  }
  for (final name in ['lib', 'pubspec.yaml']) {
    collect('plugins/ecsly_flutter_scene/$name');
  }
  for (final name in [
    'lib',
    'test',
    'assets',
    'web',
    'hook',
    'pubspec.yaml',
    'analysis_options.yaml',
  ]) {
    collect('examples/visualization_studio/$name');
  }
  for (final name in ['lib', 'pubspec.yaml'])
    collect('examples/visualization_tokens/$name');
  files.sort((a, b) => a.path.compareTo(b.path));
  final records = <Map<String, Object?>>[];
  await output.create(recursive: true);
  try {
    for (final file in files) {
      final relative = file.path.substring(root.length + 1);
      final bytes = await file.readAsBytes();
      final target = File('${output.path}/frozen-tree/$relative');
      await target.parent.create(recursive: true);
      await target.writeAsBytes(bytes);
      records.add({
        'path': relative,
        'bytes': bytes.length,
        'sha256': sha256.convert(bytes).toString(),
      });
    }
    for (var i = 0; i < files.length; i++) {
      if (sha256.convert(await files[i].readAsBytes()).toString() !=
          records[i]['sha256']) {
        throw StateError(
          'Source changed while freezing: ${records[i]['path']}',
        );
      }
    }
    final skill =
        '${output.path}/frozen-tree/.agents/skills/ecsly-visualization';
    final cases = <Map<String, dynamic>>[];
    for (final name in ['prompts.json', 'held_out.json']) {
      final data =
          jsonDecode(File('$skill/evals/$name').readAsStringSync()) as Map;
      cases.addAll((data['cases'] as List).cast<Map<String, dynamic>>());
    }
    final prompts = {
      'schema': 1,
      'cases': [
        for (final row in cases)
          {
            'id': row['id'],
            'split': row['split'] ?? 'held_out',
            'prompt': row['prompt'],
          },
      ],
    };
    await File('${output.path}/agent-prompts.json')
        .writeAsString(jsonEncode(prompts));
    final digest = sha256.convert(utf8.encode(jsonEncode(records))).toString();
    await File('${output.path}/manifest.json').writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'schema': 1,
        'digest': digest,
        'files': records,
        'promptOnlyDigest': sha256
            .convert(utf8.encode(jsonEncode(prompts)))
            .toString(),
        'sourceRoot': root,
        'status': 'frozen replay inputs; no behavior score',
        'limits': [
          'Existing cases are not genuinely unseen.',
          'Full snapshot includes rubrics; execution must enforce prompt-only access.',
          'External references and installed skills are not frozen or sandboxed by this tool.',
        ],
      }),
    );
    stdout.writeln('Frozen ${records.length} files; digest $digest');
  } catch (error) {
    await File('${output.path}/failed.json')
        .writeAsString(jsonEncode({'error': '$error'}));
    rethrow;
  }
}
