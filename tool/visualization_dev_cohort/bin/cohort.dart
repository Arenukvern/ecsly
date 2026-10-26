import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:universal_browser_cdp/universal_browser_cdp.dart';
import 'package:universal_automation_interface/universal_automation_interface.dart';

import '../lib/oka_dev_binding.dart';

/// Only a caller-owned generated consumer is edited, never the canonical tokens.
Future<void> main(List<String> args) async {
  if (args.length != 3)
    throw ArgumentError('cohort.dart CONSUMER FLUTTER_BIN EVIDENCE');
  final project = Directory(args[0]).resolveSymbolicLinksSync();
  if (!File('$project/source-provenance.json').existsSync()) {
    throw StateError('Refusing to edit a consumer without scaffold provenance');
  }
  final output = Directory(args[2])..createSync(recursive: true);
  final source = File(
    '$project/packages/visualization_tokens/lib/ecsly_visualization_tokens.dart',
  );
  final imported = File('${source.parent.path}/revision_label.dart');
  if (imported.existsSync()) throw StateError('Fixture import already exists');
  final original = source.readAsStringSync();
  final commands = StreamController<String>();
  final changes = StreamController<String>.broadcast();
  final ready = Completer<DevSessionAttachment>();
  final lines = <String>[];
  final processLines = <Map<String, Object?>>[];
  final checks = <Map<String, Object?>>[];
  final reservation = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = reservation.port;
  await reservation.close();
  var code = 0;
  final clock = Stopwatch()..start();
  final run = runRunDevCli(
    [
      '--project',
      project,
      '--platform',
      'web',
      '--port',
      '$port',
      '--open-browser',
      '--no-watch',
      '--json',
      '--flutter-bin',
      args[1],
      '--',
      '--no-web-resources-cdn',
      '--verbose',
    ],
    commands: commands.stream,
    setExitCode: (c) => code = c,
    browserLauncher: ({required project, required appUrl, required spec}) =>
        launchDevBrowser(
          project: project,
          appUrl: appUrl,
          spec: const BrowserSessionSpec(
            windowSize: (width: 1120, height: 1000),
          ),
        ),
    onProcessLine: (line) => processLines.add({
      'elapsedUs': clock.elapsedMicroseconds,
      'line': line,
    }),
    onSessionReady: (attachment) {
      if (!ready.isCompleted) ready.complete(attachment);
    },
    output: (line) {
      lines.add(line);
      changes.add(line);
    },
    errorOutput: (line) {
      lines.add(line);
    },
  );
  CdpPage? page;
  StreamSubscription? runtimeSubscription;
  final runtimeErrors = <String>[];
  Future<Map<String, dynamic>> state() async =>
      jsonDecode(await page!.evaluate('window.__ecslyViewerState()') as String)
          as Map<String, dynamic>;
  try {
    final session = await ready.future.timeout(const Duration(minutes: 4));
    final ws = Uri.parse(session.pageWsUrl!);
    page = await CdpPage.attach(
      await CdpConnection.connect(ws),
      CdpTargetInfo(
        id: ws.pathSegments.last,
        type: 'page',
        url: 'http://127.0.0.1:$port',
        title: 'Code-edit cohort',
        webSocketDebuggerUrl: ws.toString(),
      ),
    );
    runtimeSubscription = page.connection
        .on('Runtime.exceptionThrown')
        .listen((e) => runtimeErrors.add(jsonEncode(e.params)));
    final bootstrap = Stopwatch()..start();
    while (await page.evaluate(
          'typeof window.__ecslyViewerState === "function"',
        ) !=
        true) {
      if (bootstrap.elapsed > const Duration(seconds: 90))
        throw TimeoutException('App bridge absent');
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    final driver = CdpDriver(page);
    final initial = await state();
    await driver.perform(
      InvokeAction(
        'viewer_apply',
        args: {
          'requestId': 'cohort-seed',
          'expectedRevision': 1,
          'document': jsonEncode({
            ...initial['document'] as Map,
            'revision': 2,
            'title': 'Resident code-edit cohort',
          }),
        },
      ),
    );
    final seeded = await state();
    final methods = original.replaceFirst("'design-1'", "'body-2'");
    final signature = methods
        .replaceFirst(
          'visualizationCodeRevision()',
          "visualizationCodeRevision([String suffix = ''])",
        )
        .replaceFirst("'body-2'", "'signature-3'");
    final imports =
        "import 'revision_label.dart';\n\n" +
        signature.replaceFirst("'signature-3'", 'revisionLabel()');
    for (final change in [
      ('method', 'body-2', methods),
      ('signature', 'signature-3', signature),
      ('import', 'import-4', imports),
    ]) {
      if (change.$1 == 'import')
        await imported.writeAsString("String revisionLabel() => 'import-4';\n");
      await source.writeAsString(change.$3);
      final response = changes.stream
          .firstWhere((line) => line.startsWith('reload ${checks.length + 1}:'))
          .timeout(const Duration(seconds: 90));
      final step = Stopwatch()..start();
      commands.add('r ${source.path}');
      final receiptLine = await response;
      if (!receiptLine.endsWith('OK')) throw StateError(receiptLine);
      final effect = await verifyEffect(
        dispatch: () async {},
        observe: state,
        isSatisfied: (value) => value['codeRevision'] == change.$2,
        changed: (a, b) => b['codeRevision'] == change.$2,
        timeout: const Duration(seconds: 20),
      );
      if (!effect.verified)
        throw StateError('Code effect absent: ${change.$1}');
      final after = await state();
      if (after['runtimeId'] != seeded['runtimeId'] ||
          jsonEncode(after['document']) != jsonEncode(seeded['document']) ||
          after['selected'] != seeded['selected'] ||
          after['yaw'] != seeded['yaw']) {
        throw StateError('Code edit lost resident state: ${change.$1}');
      }
      checks.add({
        'change': change.$1,
        'elapsedUs': step.elapsedMicroseconds,
        'runtimeId': after['runtimeId'],
        'codeRevision': after['codeRevision'],
      });
    }
    await File('${output.path}/frame.png')
        .writeAsBytes(await driver.screenshot());
    if (runtimeErrors.isNotEmpty)
      throw StateError('Runtime exceptions: $runtimeErrors');
    await File('${output.path}/result.json').writeAsString(
      jsonEncode({
        'passed': true,
        'startupAndCohortUs': clock.elapsedMicroseconds,
        'checks': checks,
        'state': await state(),
        'runtimeErrors': runtimeErrors,
        'compiler':
            'Oka web target through one retained flutter run/DDC session',
        'note': 'Transport/code effect observations; pixels require inspection, no isolated performance cohort.',
      }),
    );
  } catch (error, stack) {
    await File('${output.path}/result.json').writeAsString(
      jsonEncode({
        'passed': false,
        'error': '$error',
        'stack': '$stack',
        'checks': checks,
        'runtimeErrors': runtimeErrors,
      }),
    );
    rethrow;
  } finally {
    await source.writeAsString(original);
    if (imported.existsSync()) await imported.delete();
    await runtimeSubscription?.cancel();
    await page?.close(closeTarget: false);
    commands.add('q');
    await run.timeout(const Duration(seconds: 30));
    await commands.close();
    await changes.close();
    await File('${output.path}/session.log').writeAsString(lines.join('\n'));
    await File('${output.path}/process-lines.json')
        .writeAsString(jsonEncode(processLines));
  }
  if (code != 0) throw StateError('Oka session exit $code');
  print('visualization-dev-cohort-complete');
}
