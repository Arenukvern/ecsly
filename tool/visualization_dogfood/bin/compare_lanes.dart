import 'dart:convert';
import 'dart:io';

/// Bounded alternating measurement over existing supervisor qualification jobs.
Future<void> main(List<String> args) async {
  if (args.length != 3)
    throw ArgumentError('compare_lanes JS_PROJECT WASM_PROJECT NEW_OUTPUT');
  final projects = [
    for (final path in args.take(2)) Directory(path).resolveSymbolicLinksSync(),
  ];
  final output = Directory(args[2]).absolute;
  if (output.existsSync()) throw StateError('Refusing existing cohort');
  final builds = [
    for (final project in projects)
      jsonDecode(
        File('$project/output/validation/build.json').readAsStringSync(),
      ) as Map,
  ];
  if (builds.any((b) => b['ok'] != true) ||
      builds[0]['consumerSourceDigest'] != builds[1]['consumerSourceDigest'] ||
      builds[0]['flutterSdkRoot'] != builds[1]['flutterSdkRoot'] ||
      builds[0]['dartVersion'] != builds[1]['dartVersion']) {
    throw StateError('Successful matching source and SDK receipts required');
  }
  final root = File.fromUri(Platform.script).parent.parent.path;
  final packages = '$root/.dart_tool/package_config.json';
  output.createSync(recursive: true);
  final trials = <Map<String, Object?>>[];
  try {
    for (var pair = 0; pair < 3; pair++) {
      for (final lane in [0, 1]) {
        final name = lane == 0 ? 'js-isolated' : 'wasm';
        final evidence = '${output.path}/$pair-$name';
        final child = await Process.start(Platform.resolvedExecutable, [
          '--packages=$packages',
          '$root/bin/supervise.dart',
          projects[lane],
          evidence,
          name,
        ], workingDirectory: root);
        final log = File('${output.path}/$pair-$name-driver.log').openWrite();
        final out = child.stdout.listen(log.add);
        final err = child.stderr.listen(log.add);
        final code = await child.exitCode;
        await out.cancel();
        await err.cancel();
        await log.close();
        if (code != 0) throw StateError('Trial failed: $evidence (exit $code)');
        final result =
            jsonDecode(File('$evidence/result.json').readAsStringSync()) as Map;
        final runtime = jsonDecode(
          File('$evidence/${lane == 0 ? 'js' : 'wasm'}-runtime.json')
              .readAsStringSync(),
        ) as Map;
        if (result['passed'] != true ||
            (runtime['browser'] as Map)['isolated'] != true ||
            result['state']['compiledWithWasm'] != (lane == 1)) {
          throw StateError('Runtime lane/effect qualification failed');
        }
        final requests = jsonDecode(
          File('$evidence/server-requests.json').readAsStringSync(),
        ) as List;
        final bytes = requests
            .where((r) => r['status'] == 200)
            .fold<int>(
              0,
              (total, r) => total + (r['payloadBytes'] as int? ?? 0),
            );
        final doc = (result['checks'] as List).firstWhere(
          (r) => r['action'] == 'resident document',
        ) as Map;
        trials.add({
          'pair': pair,
          'lane': name,
          'evidence': evidence,
          'stagesUs': result['stages'],
          'dataToFlutterFrameUs': doc['frameUs'],
          'servedUncompressedPayloadBytes': bytes,
          'heap': runtime['heap'],
          'browserVersion': runtime['browserVersion'],
          'checks': result['checks'],
        });
        await File('${output.path}/trials.json')
            .writeAsString(jsonEncode(trials));
      }
    }
    final version = jsonEncode(trials.first['browserVersion']);
    if (trials.any((t) => jsonEncode(t['browserVersion']) != version)) {
      throw StateError('Browser version changed across cohort');
    }
    num median(List<num> values) {
      values.sort();
      return values[values.length ~/ 2];
    }

    final summaries = <Map<String, Object?>>[];
    for (final lane in ['js-isolated', 'wasm']) {
      final rows = trials.where((t) => t['lane'] == lane).toList();
      summaries.add({
        'lane': lane,
        'runs': rows.length,
        'medianWorkerToCaptureUs': median([
          for (final r in rows)
            (r['stagesUs'] as Map)['firstSceneCaptureReceivedUs'] as num,
        ]),
        'medianDataToFlutterFrameUs': median([
          for (final r in rows) r['dataToFlutterFrameUs'] as num,
        ]),
        'medianServedPayloadBytes': median([
          for (final r in rows) r['servedUncompressedPayloadBytes'] as num,
        ]),
      });
    }
    await File('${output.path}/result.json').writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'passed': true,
        'sourceDigest': builds[0]['consumerSourceDigest'],
        'summaries': summaries,
        'trials': trials,
        'limits': [
          'Three alternating pairs, fixed 1120×1000 browser window and require-corp isolation.',
          'Fresh owned browser/profile per trial; OS/filesystem caches and host load uncontrolled.',
          'JS/CanvasKit versus Wasm/SkWasm execution profiles, not a pure-language comparison.',
          'Worker clock excludes supervisor/worker compilation startup; capture completion is not compositor latency.',
          'Payload bytes exclude HTTP headers/compression; heap is CDP runtime heap, not total process/GPU memory.',
          'No p95, universal speed claim, or full compiler input-closure proof.',
        ],
      }),
    );
  } catch (error) {
    await File('${output.path}/failed.json')
        .writeAsString(jsonEncode({'error': '$error', 'trials': trials}));
    rethrow;
  }
}
