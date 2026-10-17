import 'dart:convert';
import 'dart:io';

import 'package:flutter_mcp_harness/flutter_mcp_harness.dart';

Future<Map<String, Object?>> qualifySemanticText(
  VmClient client,
  ToolkitDriver driver,
  Directory output,
) async {
  final entries = (await driver.actions())
      .where((entry) => entry.name == 'enter_text')
      .toList();
  if (entries.length != 1 ||
      ((entries.single.inputSchema?['properties'] as Map?)?['semanticOnly']
              as Map?)?['type'] !=
          'boolean') {
    throw StateError(
      'Running app does not advertise semanticOnly; no write sent',
    );
  }
  await File('${output.path}/semantic-write-catalog.json')
      .writeAsString(jsonEncode(entries.single.inputSchema));
  final hasIdentity = (await client.extensionNames()).contains(
    'ext.fixture.nativeWindowIdentity',
  );
  if (hasIdentity) {
    await File('${output.path}/native-window-before-text.json').writeAsString(
      jsonEncode(
        await client.callExtension('ext.fixture.nativeWindowIdentity'),
      ),
    );
  }
  const decoy = SemanticTarget(role: 'textbox', name: 'Semantic write decoy');
  const target = SemanticTarget(role: 'textbox', name: 'Semantic write target');
  await driver.focusTarget(decoy);
  Future<Map<String, dynamic>> state() =>
      client.callExtension('ext.fixture.semanticWriteState');
  final before = await state();
  if (before['decoyFocused'] != true ||
      before['target'] != '123' ||
      before['decoy'] != 'other') {
    throw StateError(
      'Fixture has no independent focused-decoy baseline: $before',
    );
  }
  final receipts = <Map<String, Object?>>[];
  for (final text in ['123', '4 days', '']) {
    final snapshot = await driver.snapshot();
    final node = resolveSemanticTarget(snapshot, target);
    final ref = node.attributes['ref'];
    if (ref == null) throw StateError('No ref for observed text target');
    final baseline = await state();
    // One dispatch per requested value, with fresh revision and catalog schema.
    await driver.perform(
      InvokeAction(
        'enter_text',
        args: {
          'ref': ref,
          'snapshotId': snapshot.revision,
          'text': text,
          'semanticOnly': true,
        },
      ),
    );
    final expected = text == '4 days' ? '4' : text;
    final after = await retry<Map<String, dynamic>>(
      () async {
        final value = await state();
        return value['target'] == expected &&
                value['decoy'] == 'other' &&
                value['decoyFocused'] == true &&
                value['targetFocused'] == false &&
                value['changes'] ==
                    (text == '123'
                        ? 0
                        : text == '4 days'
                        ? 1
                        : 2)
            ? value
            : null;
      },
      attempts: 60,
      delay: const Duration(milliseconds: 50),
    ).timeout(const Duration(seconds: 4));
    if (after == null)
      throw StateError('Semantic write effect/focus unobserved');
    receipts.add({'requested': text, 'before': baseline, 'after': after});
  }
  final result = {
    'passed': true,
    'before': before,
    'writes': receipts,
    'scope': 'Real native Flutter controllers, callback counts and widget focus; catalog-gated InvokeAction, not shared SetValueAction or OS text events',
  };
  await File('${output.path}/semantic-write-effects.json')
      .writeAsString(jsonEncode(result));
  return result;
}
