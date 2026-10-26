import 'dart:convert';
import 'dart:io';

import 'package:oka_core/oka_core.dart';
import 'package:oka_supervisor/oka_supervisor.dart';
import 'package:resource_composition/resource_composition.dart';

Future<void> main(List<String> args) async {
  if (args.length != 3)
    throw ArgumentError('supervise.dart CONSUMER FLUTTER_BIN NEW_EVIDENCE');
  final project = Directory(args[0]).resolveSymbolicLinksSync();
  final output = Directory(args[2]).absolute;
  if (output.existsSync())
    throw StateError('Refusing to overwrite trial evidence');
  output.createSync(recursive: true);
  final argv = [
    '--packages=${File('.dart_tool/package_config.json').absolute.path}',
    File.fromUri(Platform.script.resolve('cohort.dart')).path,
    project,
    args[1],
    output.path,
  ];
  final spec = ComponentSpec(
    id: 'visualization-code-cohort',
    providerName: 'process',
    readiness: const HandshakeLine(
      pattern: 'visualization-dev-cohort-complete',
      budget: Duration(minutes: 5),
    ),
    policy: const SupervisionPolicy(
      shape: SupervisionShape.job,
      maxRestarts: 1,
      revision: 1,
    ),
    env: {
      'command': Platform.resolvedExecutable,
      'args-json': jsonEncode(argv),
    },
  );
  final desired = DesiredState(specs: [spec]);
  final supervisor = Supervisor(
    projectRoot: project,
    registry: MachineRegistry(root: '${output.path}/supervisor'),
  );
  final provider = LeasedProcessProvider(
    leaseId: spec.id,
    command: ProcessCommand(Platform.resolvedExecutable, argv),
    registry: ProcessLeaseRegistry.forProject(project),
    runToExit: true,
  );
  final facts = JsonlEvidenceSink('${output.path}/facts.jsonl');
  await File('${output.path}/plan.json')
      .writeAsString(const SpecCodec().encode(desired));
  try {
    final report = await supervisor.converge(
      desired: desired,
      factory: (_) => provider,
      evidence: facts,
    );
    await File(
      '${output.path}/supervisor-result.json',
    ).writeAsString(jsonEncode({'ok': report.ok, 'report': report.describe()}));
    if (!report.ok) throw StateError(report.describe());
    final worker = jsonDecode(
      await File('${output.path}/result.json').readAsString(),
    ) as Map;
    if (worker['passed'] != true) throw StateError('Worker did not qualify');
  } finally {
    await facts.close();
  }
}
