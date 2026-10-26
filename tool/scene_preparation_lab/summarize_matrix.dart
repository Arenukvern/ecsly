import 'dart:convert';
import 'dart:io';

/// Pair explicit immutable build receipts with observed material trials.
/// This diagnostic summary is not a bundle provenance or performance oracle.
void main(List<String> args) {
  if (args.length < 3 || args.length.isEven) {
    throw ArgumentError(
      'NEW_JSON BUILD_RECEIPT TRIAL_DIR [BUILD_RECEIPT TRIAL_DIR ...]',
    );
  }
  final output = File(args.first);
  if (output.existsSync()) throw StateError('refusing existing summary');
  Map<String, dynamic> read(File file) =>
      jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  final rows = <Map<String, Object?>>[];
  for (var i = 1; i < args.length; i += 2) {
    final buildFile = File(args[i]).absolute;
    final trial = Directory(args[i + 1]).absolute;
    final build = read(buildFile);
    final result = read(File('${trial.path}/result.json'));
    if (build['ok'] != true ||
        result['passed'] != true ||
        (result['runtimeErrors'] as List).isNotEmpty) {
      throw StateError('failed build or runtime: ${trial.path}');
    }
    final state = result['state'] as Map;
    final mode = state['materialMode'] as String;
    final flags = (build['extraArgs'] as List).cast<String>();
    if (!flags.contains('--dart-define=VIEWER_MATERIAL_MODE=$mode')) {
      throw StateError('build/runtime material mismatch');
    }
    final records =
        jsonDecode(
              File('${trial.path}/engine-preparation.json').readAsStringSync(),
            )
            as List;
    final policies = records
        .where((r) => r['phase'] == 'bundlePolicy')
        .toList();
    final lazy = policies.first['lazy'] as bool;
    if (policies.any((r) => r['lazy'] != lazy) ||
        !flags.contains('--dart-define=FLUTTER_SCENE_LAZY_WEB_SHADERS=$lazy')) {
      throw StateError('build/runtime preparation mismatch');
    }
    final compiled = lazy
        ? records.where((r) => r['phase'] == 'deferredShaderCompile').length
        : policies.fold<int>(0, (sum, r) => sum + (r['compiled'] as int));
    rows.add({
      'materialMode': mode,
      'lazy': lazy,
      'initialShaderCompiles': compiled,
      'checks': (result['checks'] as List).length,
      'buildElapsedMs': build['elapsedMs'],
      'worldToFirstRenderReturnUs':
          ((state['startup'] as Map)['marksUs']
              as Map)['firstSceneRenderReturned'],
      'consumerSourceDigest': build['consumerSourceDigest'],
      'flags': flags,
      'buildReceipt': buildFile.path,
      'trial': trial.path,
      'capture': '${trial.path}/first-scene.png',
    });
  }
  output.parent.createSync(recursive: true);
  output.writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert({
      'schema': 1,
      'rows': rows,
      'sameConsumerSource':
          rows.map((r) => r['consumerSourceDigest']).toSet().length == 1,
      'limits':
          'Operator-supplied receipt linkage checked against runtime mode/policy; bundle, full SDK and dependency closure are not fingerprinted. Shared-machine runs are not an isolated speed distribution.',
    }),
  );
  stdout.writeln('wrote ${rows.length} material cases');
}
