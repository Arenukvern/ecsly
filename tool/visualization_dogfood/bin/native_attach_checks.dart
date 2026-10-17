import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_mcp_harness/flutter_mcp_harness.dart';

// Editable Oka tool, intentionally not presented as a published library API.
import 'package:oka_dart_kernel/flutter_attach_session.dart';

Future<void> qualifyNativeAttach(
  File discovery,
  String project,
  Directory output,
) async {
  final info = jsonDecode(await discovery.readAsString()) as Map;
  final uri = Uri.parse(info['vmServiceUri'] as String);
  final client = await VmClient.connect(uri);
  final token = File(
    '$project/packages/visualization_tokens/lib/ecsly_visualization_tokens.dart',
  );
  final original = await token.readAsString();
  if (!original.contains("visualizationCodeRevision() => 'design-1'")) {
    throw StateError(
      'Copied token source does not match the declared baseline',
    );
  }
  final sdk = Platform.environment['ECSLY_NATIVE_FLUTTER_SDK'];
  if (sdk == null)
    throw StateError(
      'Native attach qualification requires explicit Flutter SDK',
    );
  FlutterAttachSession? session;
  final attachmentLines = <String>[];
  Future<Map<String, dynamic>> state() =>
      client.callExtension('ext.ecsly.visualizationState');
  try {
    final before = await state();
    session = await FlutterAttachSession.start(
      project: project,
      flutterBin: '$sdk/bin/flutter',
      vmUri: uri,
      onLine: attachmentLines.add,
    );
    await token.writeAsString(
      original.replaceFirst("'design-1'", "'design-native-attach-2'"),
    );
    session.write('r');
    final acknowledgement = await session.waitFor(
      RegExp('Reloaded [0-9]+ of|Hot reload failed|Try again after fixing'),
    );
    if (!acknowledgement.startsWith('Reloaded '))
      throw StateError('Native reload refused: $acknowledgement');
    final clock = Stopwatch()..start();
    Map<String, dynamic>? after;
    while (clock.elapsed < const Duration(seconds: 10)) {
      final current = await state();
      if (current['codeRevision'] == 'design-native-attach-2') {
        after = current;
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
    if (after == null ||
        after['runtimeId'] != before['runtimeId'] ||
        after['selected'] != before['selected'] ||
        after['distance'] != before['distance'] ||
        after['document'].toString() != before['document'].toString()) {
      throw StateError('Compiled code revision/continuity was not observed');
    }
    final code = await session.detach();
    final detached = await state();
    if (code != 0 || detached['runtimeId'] != before['runtimeId']) {
      throw StateError('Compiler detach did not preserve the running app');
    }
    await File('${output.path}/native-attach.json').writeAsString(
      jsonEncode({
        'passed': true,
        'acknowledgement': acknowledgement,
        'detachExit': code,
        'before': before,
        'after': after,
        'afterDetach': detached,
        'scope': 'One real source edit/compile/reload, resident continuity and compiler detach; not arbitrary edit parity.',
      }),
    );
  } finally {
    try {
      await session?.detach();
    } finally {
      await File('${output.path}/attach.log')
          .writeAsString(attachmentLines.join('\n'));
      await token.writeAsString(original);
      await client.dispose();
    }
  }
}
