import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:universal_browser_cdp/universal_browser_cdp.dart';
import 'package:universal_automation_interface/universal_automation_interface.dart';

/// Keep the serialized bundle valid but rename its required physical entry.
({Uint8List bytes, int replacements}) corruptPhysicalEntry(Uint8List input) {
  final marker = ascii.encode('PhysicalOpaque');
  final bytes = Uint8List.fromList(input);
  var replacements = 0;
  for (var i = 0; i <= bytes.length - marker.length; i++) {
    if (bytes[i] != marker.first) continue;
    var match = true;
    for (var j = 1; j < marker.length; j++) {
      if (bytes[i + j] != marker[j]) {
        match = false;
        break;
      }
    }
    if (match) {
      bytes[i + 10] = 65;
      replacements++;
    }
  }
  if (replacements == 0)
    throw StateError('physical shader entry fixture anchor missing');
  return (bytes: bytes, replacements: replacements);
}

Future<Map<String, dynamic>> verifyMissingEntry(CdpPage page) async {
  final clock = Stopwatch()..start();
  while (clock.elapsed < const Duration(seconds: 30)) {
    final state = jsonDecode(
      await page.evaluate('window.__ecslyViewerState()') as String,
    ) as Map<String, dynamic>;
    final startup = state['startup'] as Map;
    final error = startup['failure'];
    final marks = startup['marksUs'] as Map;
    if (error is String && error.contains('physical material shader bundle')) {
      bool hasError(AxNode node) =>
          (node.name?.startsWith('Scene unavailable:') ?? false) ||
          node.children.any(hasError);
      final visible = (await CdpDriver(page).snapshot()).roots.any(hasError);
      if (visible) {
        if (marks['firstSceneRenderEntered'] != null ||
            marks['firstSceneRenderReturned'] != null) {
          throw StateError('failed preparation reached renderer');
        }
        return state;
      }
    } else if (marks['firstSceneRenderReturned'] != null) {
      throw StateError(
        'missing shader entry was reported ready instead of rejecting preparation',
      );
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  throw StateError('missing shader entry did not produce observable failure');
}

Future<void> writeMissingEntryResult(
  CdpPage page,
  Directory output,
  Map<String, int> stages,
  List<Map<String, Object?>> checks,
  List<String> errors,
) async {
  final state = await verifyMissingEntry(page);
  if (errors.isNotEmpty)
    throw StateError(
      'uncaught runtime error instead of owned failure: $errors',
    );
  checks.add({
    'action': 'missing physical entry rejects preparation with visible error',
    'effect': 'observed',
  });
  await File('${output.path}/expected-failure.png')
      .writeAsBytes(await CdpDriver(page).screenshot());
  await File('${output.path}/result.json').writeAsString(
    const JsonEncoder.withIndent('  ').convert({
      'passed': true,
      'scope':
          'negative shader bundle fixture; no normal visual interaction claim',
      'stages': stages,
      'checks': checks,
      'runtimeErrors': errors,
      'state': state,
    }),
  );
}
