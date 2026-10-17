import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_mcp_harness/flutter_mcp_harness.dart';
import 'package:crypto/crypto.dart';

import 'native_toolkit_checks.dart';

Future<void> qualifyNativeRuntime(
  File discovery,
  Directory output, {
  int? Function()? launchExit,
  File? captureProbe,
  bool inputProbe = false,
  bool windowProbe = false,
  bool toolkitProbe = false,
}) async {
  final clock = Stopwatch()..start();
  Map? info;
  while (clock.elapsed < const Duration(seconds: 15)) {
    if (launchExit?.call() != null && !discovery.existsSync()) {
      final launch = jsonDecode(
        await File('${output.path}/launch.json').readAsString(),
      ) as Map;
      throw StateError(
        'Native launcher refused: ${launch['gap'] ?? launch['phase']}',
      );
    }
    if (discovery.existsSync()) {
      try {
        info = jsonDecode(discovery.readAsStringSync()) as Map;
        if (info['phase'] == 'service_discovery') break;
      } on FormatException {
        /* Bootstrap receipt may still be flushing. */
      }
    }
    await Future<void>.delayed(const Duration(milliseconds: 25));
  }
  if (info == null)
    throw TimeoutException('Native engine bootstrap was not published');
  if (info['vmServiceUri'] is! String)
    throw StateError('Native VM service URI is unavailable (${info['phase']})');
  final client = await VmClient.connect(
    Uri.parse(info['vmServiceUri'] as String),
  );
  try {
    final names = await client.extensionNames();
    if (!names.contains('ext.ecsly.visualizationState') ||
        !names.contains('ext.ecsly.visualizationApply'))
      throw StateError('Native viewer extensions missing');
    String? viewerId;
    final mountClock = Stopwatch()..start();
    while (mountClock.elapsed < const Duration(seconds: 10)) {
      final views = await client.callExtension('ext.ecsly.visualizationViews');
      final ids = (views['viewerIds'] as List).cast<String>();
      if (ids.length > 1)
        throw StateError('Native trial requires one addressed viewer');
      if (ids.length == 1) {
        viewerId = ids.single;
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
    if (viewerId == null) throw TimeoutException('Native viewer did not mount');
    Future<Map<String, dynamic>> state() => client.callExtension(
      'ext.ecsly.visualizationState',
      args: {'viewerId': viewerId},
    );
    Future<Map<String, dynamic>> observe(
      bool Function(Map<String, dynamic>) ready,
    ) async {
      final watch = Stopwatch()..start();
      while (watch.elapsed < const Duration(seconds: 10)) {
        final current = await state();
        if (ready(current)) return current;
        await Future<void>.delayed(const Duration(milliseconds: 25));
      }
      await File('${output.path}/unobserved-state.json')
          .writeAsString(jsonEncode(await state()));
      throw TimeoutException('Native completed Flutter frame was not observed');
    }

    final before = await observe(
      (value) =>
          ((value['startup'] as Map?)?['marksUs']
                  as Map?)?['firstCanvasPaintReturned']
              is num,
    );
    await File('${output.path}/native-before.json')
        .writeAsString(jsonEncode(before));
    final document = Map<String, dynamic>.from(before['document'] as Map);
    final revision = (document['revision'] as int) + 1;
    final requestId = 'native-background-revision-$revision';
    final applied = await client.callExtension(
      'ext.ecsly.visualizationApply',
      args: {
        'viewerId': viewerId,
        'requestId': requestId,
        'expectedRevision': '${document['revision']}',
        'document': jsonEncode({
          ...document,
          'revision': revision,
          'title': 'Native background revision',
        }),
      },
    );
    await File('${output.path}/native-apply-receipt.json')
        .writeAsString(jsonEncode(applied));
    final after = await observe(
      (value) => value['presentedRevision'] == revision,
    );
    if (after['runtimeId'] != before['runtimeId'] ||
        after['selected'] != before['selected'] ||
        after['distance'] != before['distance']) {
      throw StateError('Native resident continuity failed');
    }
    await File('${output.path}/native-after.json')
        .writeAsString(jsonEncode(after));
    if (toolkitProbe) await qualifyNativeToolkit(client, after, output);
    if (windowProbe ||
        (inputProbe &&
            (await client.extensionNames()).contains(
              'ext.ecsly.nativeWindowState',
            ))) {
      final window = await client.callExtension('ext.ecsly.nativeWindowState');
      await File('${output.path}/native-window-state.json')
          .writeAsString(jsonEncode(window));
    }
    if (inputProbe) {
      if (after['example'] != 'graph')
        throw StateError('Native input requires graph fixture');
      const label = 'Oscillators';
      final input = File.fromUri(
        Platform.script.resolve('../native_capture/bin/native_input.dart'),
      );
      final dart = '${File(Platform.resolvedExecutable).parent.path}/dart';
      final result = await Process.run(dart, [
        'run',
        input.path,
        '${info['pid']}',
        label,
        '${output.path}/native-input',
      ], workingDirectory: input.parent.parent.path);
      await File('${output.path}/native-input.log')
          .writeAsString('${result.stdout}\n${result.stderr}');
      if (result.exitCode != 0)
        throw StateError('Native semantic input failed');
      final selected = await observe(
        (value) => value['example'] == 'simulation',
      );
      if (selected['runtimeId'] != after['runtimeId'] ||
          selected['document'].toString() != after['document'].toString() ||
          selected['selected'] != after['selected'] ||
          selected['distance'] != after['distance']) {
        throw StateError('Native input changed unrelated resident state');
      }
      await File('${output.path}/native-input-effect.json').writeAsString(
        jsonEncode({
          'passed': true,
          'before': after,
          'after': selected,
          'target': label,
          'scope': 'Anchored background AXPress delivered; changed recipe independently observed via VM resource',
        }),
      );
    }
    final capture = File.fromUri(
      Platform.script.resolve('../native_capture/bin/native_capture.dart'),
    );
    int? captureWindowId;
    if ((await client.extensionNames()).contains(
      'ext.fixture.nativeWindowIdentity',
    )) {
      final identity = await client.callExtension(
        'ext.fixture.nativeWindowIdentity',
      );
      await File('${output.path}/native-window-before-capture.json')
          .writeAsString(jsonEncode(identity));
      final host = identity['host'] as Map?;
      final id = host?['windowId'];
      if (identity['schema'] != 1 ||
          identity['pid'] != info['pid'] ||
          identity['controllerAttachedToHost'] != true ||
          host?['controllerClass'] != 'FlutterViewController' ||
          id is! int ||
          id <= 0) {
        throw StateError(
          'Native Flutter host identity not qualified: $identity',
        );
      }
      captureWindowId = id;
    }
    final sdkDart = '${File(Platform.resolvedExecutable).parent.path}/dart';
    if (captureWindowId != null) {
      final rejectedPath = '${output.path}/wrong-owner.png';
      final rejected = await Process.run(sdkDart, [
        'run',
        capture.path,
        '$pid',
        rejectedPath,
        '$captureWindowId',
      ], workingDirectory: capture.parent.parent.path);
      await File('${output.path}/native-capture-owner-refusal.log')
          .writeAsString('${rejected.stdout}\n${rejected.stderr}');
      if (rejected.exitCode == 0 || File(rejectedPath).existsSync()) {
        throw StateError('Explicit native capture crossed process ownership');
      }
    }
    final captured = await Process.run(sdkDart, [
      'run',
      capture.path,
      '${info['pid']}',
      '${output.path}/native-frame.png',
      if (captureWindowId != null) '$captureWindowId',
    ], workingDirectory: capture.parent.parent.path);
    await File('${output.path}/native-capture.log')
        .writeAsString('${captured.stdout}\n${captured.stderr}');
    if (captured.exitCode != 0)
      throw StateError(
        'Owned native window capture failed: ${captured.exitCode}',
      );
    if (captureProbe != null) {
      final executable = '${output.path}/window-capture-probe';
      final compiled = await Process.run('/usr/bin/swiftc', [
        '-parse-as-library',
        captureProbe.path,
        '-o',
        executable,
      ]);
      await File('${output.path}/capture-probe-compile.log')
          .writeAsString('${compiled.stdout}\n${compiled.stderr}');
      if (compiled.exitCode != 0)
        throw StateError('Window capture probe compile failed');
      final frame = await Process.run(executable, [
        '${info['pid']}',
        '${output.path}/native-frame-sck.png',
        '${output.path}/native-frame-sck.json',
      ]);
      await File('${output.path}/capture-probe-identity.json').writeAsString(
        jsonEncode({
          'source': captureProbe.path,
          'sha256': sha256.convert(await captureProbe.readAsBytes()).toString(),
          'exitCode': frame.exitCode,
        }),
      );
      await File('${output.path}/capture-probe.log')
          .writeAsString('${frame.stdout}\n${frame.stderr}');
      if (frame.exitCode != 0)
        throw StateError('ScreenCaptureKit window probe failed');
    }
    await File('${output.path}/native-runtime.json').writeAsString(
      jsonEncode({
        'passed': true,
        'pid': info['pid'],
        'discoveryToObservedUs': clock.elapsedMicroseconds,
        'dataToFlutterFrameUs': after['dataToFlutterFrameUs'],
        'scope': 'Registered VM extension, initial Canvas paint and resident revision Flutter frame; OS window capture retained for inspection, no compositor timing.',
      }),
    );
  } finally {
    await client.dispose();
  }
}
