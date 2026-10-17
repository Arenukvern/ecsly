import 'dart:convert';
import 'dart:io';

import 'package:flutter_mcp_harness/flutter_mcp_harness.dart';

import 'native_semantic_write_checks.dart';

Future<void> qualifyNativeToolkit(
  VmClient client,
  Map<String, dynamic> before,
  Directory output,
) async {
  final http = client.httpUri;
  final ws =
      http
          .toString()
          .replaceFirst('http', 'ws')
          .replaceAll(RegExp(r'/+$'), '') +
      '/ws';
  final doctor = await Process.run('fmtk', [
    '--vm-service-uri',
    ws,
    'doctor',
    '--json',
  ]);
  await File('${output.path}/toolkit-doctor.json')
      .writeAsString('${doctor.stdout}');
  await File('${output.path}/toolkit-doctor.log')
      .writeAsString('${doctor.stderr}');
  if (doctor.exitCode != 0) throw StateError('Flutter toolkit doctor failed');
  final names = await client.extensionNames();
  const required = [
    'ext.mcp.toolkit.app_errors',
    'ext.mcp.toolkit.view_details',
    'ext.mcp.toolkit.view_screenshots',
    'ext.mcp.toolkit.inspect_widget_at_point',
  ];
  if (required.any((name) => !names.contains(name)))
    throw StateError('Required toolkit extensions missing');
  final driver = ToolkitDriver.custom((extension, {args = const {}}) async {
    final result = await client.callExtension(extension, args: args);
    if (extension == ToolkitExtensions.focusWidget) {
      await File('${output.path}/toolkit-focus-receipt.json')
          .writeAsString(jsonEncode(result));
    }
    return result;
  });
  try {
    final snapshot = await driver.snapshot();
    await File('${output.path}/toolkit-before.json')
        .writeAsString(jsonEncode(snapshot.toJson()));
    final effects = <Map<String, Object?>>[];
    Map<String, Object?>? semanticWrites;
    if (names.contains('ext.fixture.semanticWriteState')) {
      semanticWrites = await qualifySemanticText(client, driver, output);
    }
    Future<Map<String, dynamic>> state() =>
        client.callExtension('ext.ecsly.visualizationState');
    Future<void> click(
      String name,
      bool Function(Map<String, dynamic>, Map<String, dynamic>) changed,
    ) async {
      final receipt = await verifyEffect(
        dispatch: () => driver.perform(ClickAction(role: 'button', name: name)),
        observe: state,
        changed: changed,
        timeout: const Duration(seconds: 3),
        dispatchTimeout: const Duration(seconds: 3),
      );
      effects.add({
        'action': name,
        'delivery': receipt.delivery.name,
        'effect': receipt.effect.name,
        'before': receipt.before,
        'after': receipt.after,
      });
      final stage = effects.length;
      await File('${output.path}/toolkit-effect-$stage.json')
          .writeAsString(jsonEncode(effects.last));
      if (names.contains('ext.fixture.nativeWindowIdentity')) {
        await File('${output.path}/native-window-after-effect-$stage.json')
            .writeAsString(
              jsonEncode(
                await client.callExtension('ext.fixture.nativeWindowIdentity'),
              ),
            );
      }
      if (!receipt.verified ||
          receipt.after['runtimeId'] != before['runtimeId'] ||
          receipt.after['document'].toString() !=
              before['document'].toString()) {
        throw StateError('Toolkit effect/continuity failed: $name');
      }
    }

    await click('Oscillators', (a, b) => b['example'] == 'simulation');
    await driver.perform(const ScrollAction(direction: 'down', distance: 650));
    const frequency = SemanticTarget(
      role: 'slider',
      scope: [SemanticTarget(name: 'Frequency control')],
    );
    await File('${output.path}/toolkit-before-focus.json')
        .writeAsString(jsonEncode((await driver.snapshot()).toJson()));
    final TargetedAutomationDriver targeted = driver;
    await targeted.focusTarget(frequency);
    final focused = await driver.snapshot();
    await File('${output.path}/toolkit-focused.json')
        .writeAsString(jsonEncode(focused.toJson()));
    final frequencyNode = resolveSemanticTarget(focused, frequency);
    if (frequencyNode.attributes['focused'] != 'true') {
      throw StateError('Independent frequency semantics does not report focus');
    }
    // The tested macOS Flutter SDK uses a 0.1 normalized slider step;
    // frequency range is 0.5..2.0, so ArrowRight increases it by 0.15 Hz.
    final keyEffect = await verifyEffect(
      dispatch: () => driver.perform(const KeyPressAction('ArrowRight')),
      observe: state,
      changed: (a, b) =>
          ((b['frequency'] as num) - (a['frequency'] as num) - 0.15).abs() <
          1e-9,
      timeout: const Duration(seconds: 3),
      dispatchTimeout: const Duration(seconds: 3),
    );
    effects.add({
      'action': 'focused frequency ArrowRight',
      'delivery': keyEffect.delivery.name,
      'effect': keyEffect.effect.name,
      'before': keyEffect.before,
      'after': keyEffect.after,
    });
    await File('${output.path}/toolkit-key-effect.json')
        .writeAsString(jsonEncode(effects.last));
    if (!keyEffect.verified)
      throw StateError('Focused key had no frequency effect');
    await driver.perform(const ScrollAction(direction: 'up', distance: 650));
    if (names.contains('ext.fixture.nativeWindowIdentity')) {
      await File('${output.path}/native-window-after-key-scroll.json')
          .writeAsString(
            jsonEncode(
              await client.callExtension('ext.fixture.nativeWindowIdentity'),
            ),
          );
    }
    await click('Linked observations', (a, b) => b['example'] == 'linked');
    await click('Use dark theme', (a, b) => b['dark'] == true);
    await click('Dependencies', (a, b) => b['example'] == 'graph');

    // Force the real app to publish a newer snapshot between resolution and
    // dispatch. Exercise the existing transport seam, never replay the action.
    final beforeStale = await state();
    final staleDriver = ToolkitDriver.custom((
      extension, {
      args = const {},
    }) async {
      if (extension == ToolkitExtensions.tap) {
        await client.callExtension(ToolkitExtensions.snapshot);
      }
      return client.callExtension(extension, args: args);
    });
    Object? refusal;
    try {
      await staleDriver.perform(const ClickAction(name: 'Oscillators'));
    } on ProtocolException catch (error) {
      refusal = error;
    } finally {
      await staleDriver.close();
    }
    final afterStale = await state();
    if (refusal == null ||
        !refusal.toString().contains('stale_snapshot') ||
        jsonEncode(beforeStale) != jsonEncode(afterStale)) {
      throw StateError('Stale-snapshot refusal changed app state: $refusal');
    }
    effects.add({
      'action': 'stale snapshot',
      'refusal': '$refusal',
      'effect': 'state unchanged',
      'before': beforeStale,
      'after': afterStale,
    });
    final after = afterStale;
    final appErrors = await client.callExtension('ext.mcp.toolkit.app_errors',
      args: {'count': 100},
    );
    await File('${output.path}/toolkit-app-errors.json')
        .writeAsString(jsonEncode(appErrors));
    final reported = appErrors['errors'];
    if (reported is! List || reported.isNotEmpty) {
      throw StateError('Native Flutter error buffer is not clean: $appErrors');
    }
    await File('${output.path}/toolkit-input-effect.json').writeAsString(
      jsonEncode({
        'passed': true,
        'effects': effects,
        'semanticWrites': semanticWrites,
        'before': before,
        'after': after,
        'scope': 'Instrumented native Flutter widget tap and independent resident-state effect; includes widget-focused toolkit key effect; not OS AX or OS keyboard-event delivery',
      }),
    );
  } finally {
    await driver.close();
  }
}
