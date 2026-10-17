import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_mcp_harness/flutter_mcp_harness.dart';

Future<void> qualifyNativeDev(
  File discovery,
  String project,
  String okaRoot,
  Directory output, {
  bool cohort = false,
}) async {
  final info = jsonDecode(discovery.readAsStringSync()) as Map;
  final sdk = Platform.environment['ECSLY_NATIVE_FLUTTER_SDK'];
  if (sdk == null) throw StateError('Explicit Flutter SDK is required');
  final packages = File(
    '${File.fromUri(Platform.script).parent.parent.path}/.dart_tool/package_config.json',
  );
  final vmUri = Uri.parse(info['vmServiceUri'] as String);
  var client = await VmClient.connect(vmUri);
  final token = File(
    '$project/packages/visualization_tokens/lib/ecsly_visualization_tokens.dart',
  );
  final original = token.readAsStringSync();
  if (!original.contains("visualizationCodeRevision() => 'design-1'"))
    throw StateError('Copied baseline mismatch');
  final process = await Process.start('$sdk/bin/dart', [
    '--packages=${packages.path}',
    '$okaRoot/packages/oka_dart_kernel/tool/oka_run_dev.dart',
    '--project',
    project,
    '--platform',
    'macos',
    '--native-vm-uri',
    info['vmServiceUri'] as String,
    '--flutter-bin',
    '$sdk/bin/flutter',
    '--no-watch',
  ], workingDirectory: project);
  final tap = LogTap();
  void pump(Stream<List<int>> bytes) => bytes
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .listen(tap.add);
  pump(process.stdout);
  pump(process.stderr);
  final exit = process.exitCode;
  unawaited(exit.then((_) => tap.close()));
  Future<Map<String, dynamic>> state() =>
      client.callExtension('ext.ecsly.visualizationState');
  var exited = false;
  var cohortPassed = false;
  final observations = <Map<String, Object?>>[];
  try {
    final before = await state();
    await tap.waitFor('dev: ready', timeout: const Duration(seconds: 60));
    final methodClock = Stopwatch()..start();
    await token.writeAsString(
      original.replaceFirst("'design-1'", "'design-native-dev-2'"),
    );
    process.stdin.writeln('r ${token.path}');
    await process.stdin.flush();
    final receipt = await tap.waitFor(
      RegExp('reload 1: OK|reload 1: FAILED'),
      timeout: const Duration(seconds: 60),
    );
    if (!receipt.contains('OK')) throw StateError('Oka reload receipt failed');
    final after = await state();
    if (after['codeRevision'] != 'design-native-dev-2' ||
        after['runtimeId'] != before['runtimeId'] ||
        after['document'].toString() != before['document'].toString() ||
        after['selected'] != before['selected'] ||
        after['distance'] != before['distance']) {
      throw StateError('Oka native dev code effect/continuity failed');
    }
    observations.add({
      'kind': 'method',
      'receipt': receipt,
      'sourceToObservedUs': methodClock.elapsedMicroseconds,
      'state': after,
    });
    var last = after;
    if (cohort) {
      const baselineMethod =
          "String visualizationCodeRevision() => 'design-1';";
      final variants = [
        (
          kind: 'compatible signature',
          revision: 'design-native-signature-3',
          source: original.replaceFirst(
            baselineMethod,
            "String visualizationCodeRevision({String prefix = ''}) => prefix + 'design-native-signature-3';",
          ),
        ),
        (
          kind: 'new import',
          revision: 'design-native-import-4',
          source:
              "import 'dart:convert';\n" +
              original.replaceFirst(
                baselineMethod,
                "String visualizationCodeRevision({String prefix = ''}) => jsonDecode(jsonEncode(prefix + 'design-native-import-4')) as String;",
              ),
        ),
      ];
      for (var i = 0; i < variants.length; i++) {
        final variant = variants[i];
        final clock = Stopwatch()..start();
        await token.writeAsString(variant.source);
        process.stdin.writeln('r ${token.path}');
        await process.stdin.flush();
        final number = i + 2;
        final line = await tap.waitFor(
          RegExp('reload $number: OK|reload $number: FAILED'),
          timeout: const Duration(seconds: 60),
        );
        if (!line.contains('OK'))
          throw StateError('${variant.kind} reload failed');
        last = await state();
        if (last['codeRevision'] != variant.revision ||
            last['runtimeId'] != before['runtimeId'] ||
            last['document'].toString() != before['document'].toString() ||
            last['selected'] != before['selected'] ||
            last['distance'] != before['distance']) {
          throw StateError('${variant.kind} effect/continuity failed');
        }
        observations.add({
          'kind': variant.kind,
          'receipt': line,
          'sourceToObservedUs': clock.elapsedMicroseconds,
          'state': last,
        });
      }
      process.stdin.writeln('R');
      await process.stdin.flush();
      final restart = await tap.waitFor(
        RegExp('restart: OK|restart: FAILED'),
        timeout: const Duration(seconds: 60),
      );
      if (!restart.contains('OK')) throw StateError('Native restart failed');
      await client.dispose();
      client = await VmClient.connect(vmUri);
      last = await client.callExtensionUntil(
        'ext.ecsly.visualizationState',
        attempts: 20,
        delay: const Duration(milliseconds: 100),
        until: (current) {
          final marks = (current['startup'] as Map?)?['marksUs'] as Map?;
          return current['runtimeId'] != before['runtimeId'] &&
              marks?['firstCanvasPaintReturned'] is num &&
              marks?['firstWidgetFrameCompleted'] is num;
        },
      );
      if (last['runtimeId'] == before['runtimeId'] ||
          last['codeRevision'] != 'design-native-import-4' ||
          (last['document'] as Map)['revision'] != 1 ||
          last['applyCount'] != 0) {
        throw StateError(
          'Restart did not initialize a fresh runtime with current code',
        );
      }
      observations.add({'kind': 'restart', 'receipt': restart, 'state': last});
      final restarted = last;
      await token.writeAsString(
        variants.last.source.replaceAll(
          'design-native-import-4',
          'design-native-after-restart-5',
        ),
      );
      process.stdin.writeln('r ${token.path}');
      await process.stdin.flush();
      final nextReload = await tap.waitFor(
        RegExp('reload 4: OK|reload 4: FAILED'),
        timeout: const Duration(seconds: 60),
      );
      if (!nextReload.contains('OK'))
        throw StateError('Post-restart reload failed');
      last = await state();
      if (last['codeRevision'] != 'design-native-after-restart-5' ||
          last['runtimeId'] != restarted['runtimeId'] ||
          last['document'].toString() != restarted['document'].toString() ||
          last['selected'] != restarted['selected'] ||
          last['distance'] != restarted['distance']) {
        throw StateError('Post-restart reload effect/continuity failed');
      }
      observations.add({
        'kind': 'reload after restart',
        'receipt': nextReload,
        'state': last,
      });
    }
    process.stdin.writeln('q');
    await process.stdin.flush();
    final code = await exit.timeout(const Duration(seconds: 15));
    exited = true;
    final detached = await state();
    if (code != 0 || detached['runtimeId'] != last['runtimeId'])
      throw StateError('Oka quit did not detach safely');
    cohortPassed = true;
    await File('${output.path}/native-dev.json').writeAsString(
      jsonEncode({
        'passed': true,
        'receipt': receipt,
        'devExit': code,
        'before': before,
        'after': after,
        'afterQuit': detached,
        'cohort': cohort,
        'scope': 'Real Oka CLI native attach, observed source edits and quit leaving externally owned app alive; cohort also includes restart.',
      }),
    );
  } finally {
    if (cohort)
      await File('${output.path}/native-dev-cohort.json').writeAsString(
        jsonEncode({
          'passed': cohortPassed,
          'observations': observations,
          'scope': 'One native Oka compiler session: method/signature/import reloads, restart and detach; timings are source-to-observation, not compositor evidence.',
        }),
      );
    if (!exited) {
      try {
        process.stdin.writeln('q');
        await process.stdin.flush();
        await exit.timeout(const Duration(seconds: 10));
      } catch (_) {
        process.kill();
        await exit.timeout(const Duration(seconds: 5));
      }
    }
    await File('${output.path}/native-dev.log')
        .writeAsString(tap.lines.join('\n'));
    await token.writeAsString(original);
    await client.dispose();
  }
}
