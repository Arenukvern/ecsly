import 'dart:convert';
import 'dart:io';

import 'package:ecsly/ecsly.dart';

void main(final List<String> args) {
  final json = args.contains('--json');
  final out = _argValue(args, '--out=');
  final report = _runReport(args);
  final text = json
      ? const JsonEncoder.withIndent('  ').convert(report)
      : _toText(report);

  if (out == null) {
    stdout.writeln(text);
    return;
  }
  final file = File(out);
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(text);
}

String? _argValue(final List<String> args, final String prefix) {
  for (final arg in args) {
    if (arg.startsWith(prefix)) return arg.substring(prefix.length);
  }
  return null;
}

Map<String, Object?> _runReport(final List<String> args) {
  const entityCount = 12000;
  const writeRuns = 20000;
  const runCount = 1;
  final metrics = <Map<String, Object?>>[
    _benchStructuralChurn(
      entityCount: entityCount,
      runs: runCount,
    ).toJson('topology_structural_churn'),
    _benchResourceWrites(
      runs: writeRuns,
      samples: runCount,
    ).toJson('resource_in_place_writes_no_core_tracking'),
  ];

  return <String, Object?>{
    'schemaId': 'ecsly.core.world_revisions',
    'package': 'ecsly',
    'generatedAt': DateTime.now().toUtc().toIso8601String(),
    'command': _commandLine('benchmark/world_revisions.dart', args),
    'mode': 'topology_revisions_only',
    'environment': _WorldRevisionEnvironment.capture().toJson(),
    'git': _GitInfo.capture().toJson(),
    'runCount': runCount,
    'entityCount': entityCount,
    'writeRuns': writeRuns,
    'metrics': metrics,
  };
}

_WorldRevisionMetric _benchStructuralChurn({
  required final int entityCount,
  required final int runs,
}) {
  final rssBefore = ProcessInfo.currentRss;
  final world = _buildWorld();
  final entities = world.reserveEmptyEntities(entityCount);
  final watch = Stopwatch()..start();
  for (final entity in entities) {
    world.spawnBundle(
      entity,
      ComponentBundle.fromLists(const <Component>[_BenchComponent(1)]),
    );
  }
  world.flush();
  entities.forEach(world.despawnEntity);
  world.flush();
  watch.stop();
  final rssAfter = ProcessInfo.currentRss;
  return _WorldRevisionMetric(
    opsPerSec: (entityCount * 2) / (watch.elapsedMicroseconds / 1000000.0),
    elapsedMicros: watch.elapsedMicroseconds,
    rssDeltaBytes: rssAfter - rssBefore,
    structuralRevision: world.structuralRevision,
    samples: runs,
  );
}

_WorldRevisionMetric _benchResourceWrites({
  required final int runs,
  required final int samples,
}) {
  final world = _buildWorld();
  world.upsertResource(_BenchResource(0));
  world.flush();
  final rssBefore = ProcessInfo.currentRss;
  final watch = Stopwatch()..start();
  for (var i = 0; i < runs; i++) {
    world.getResource<_BenchResource>().value = i;
  }
  watch.stop();
  final rssAfter = ProcessInfo.currentRss;
  return _WorldRevisionMetric(
    opsPerSec: runs / (watch.elapsedMicroseconds / 1000000.0),
    elapsedMicros: watch.elapsedMicroseconds,
    rssDeltaBytes: rssAfter - rssBefore,
    structuralRevision: world.structuralRevision,
    samples: samples,
  );
}

World _buildWorld() {
  final world = World();
  world.components.registerObjectComponent<_BenchComponent>();
  return world;
}

String _toText(final Map<String, Object?> report) {
  final buffer = StringBuffer()
    ..writeln('ecsly world revision benchmark')
    ..writeln('generatedAt: ${report['generatedAt']}')
    ..writeln('git: ${report['git']}')
    ..writeln('environment: ${report['environment']}')
    ..writeln('runCount: ${report['runCount']}')
    ..writeln('entityCount: ${report['entityCount']}')
    ..writeln('writeRuns: ${report['writeRuns']}');
  for (final metric in report['metrics']! as List<Map<String, Object?>>) {
    buffer.writeln(
      '${metric['name']}: ${metric['opsPerSec']} ops/sec, '
      '${metric['elapsedMicros']} us, rssDelta=${metric['rssDeltaBytes']}, '
      'structuralRevision=${metric['structuralRevision']}',
    );
  }
  return buffer.toString();
}

final class _WorldRevisionMetric {
  const _WorldRevisionMetric({
    required this.opsPerSec,
    required this.elapsedMicros,
    required this.rssDeltaBytes,
    required this.structuralRevision,
    required this.samples,
  });

  final double opsPerSec;
  final int elapsedMicros;
  final int rssDeltaBytes;
  final int structuralRevision;
  final int samples;

  Map<String, Object?> toJson(final String name) => <String, Object?>{
    'name': name,
    'samples': samples,
    'opsPerSec': opsPerSec,
    'elapsedMicros': elapsedMicros,
    'rssDeltaBytes': rssDeltaBytes,
    'structuralRevision': structuralRevision,
  };
}

final class _BenchComponent extends Component {
  const _BenchComponent(this.value);

  final int value;
}

final class _WorldRevisionEnvironment {
  const _WorldRevisionEnvironment({
    required this.os,
    required this.osVersion,
    required this.dartVersion,
    required this.processors,
    required this.executable,
    required this.machineModel,
    required this.machineName,
    required this.cpuBrand,
    required this.memoryBytes,
    required this.memoryGiB,
  });

  factory _WorldRevisionEnvironment.capture() {
    final memoryBytes = int.tryParse(_sysctl('hw.memsize')) ?? 0;
    final machineModel = _sysctl('hw.model');
    return _WorldRevisionEnvironment(
      os: Platform.operatingSystem,
      osVersion: Platform.operatingSystemVersion,
      dartVersion: Platform.version,
      processors: Platform.numberOfProcessors,
      executable: Platform.executable,
      machineModel: machineModel,
      machineName: _friendlyMachineName(machineModel),
      cpuBrand: _sysctl('machdep.cpu.brand_string'),
      memoryBytes: memoryBytes,
      memoryGiB: _formatMemoryGiB(memoryBytes),
    );
  }

  final String os;
  final String osVersion;
  final String dartVersion;
  final int processors;
  final String executable;
  final String machineModel;
  final String machineName;
  final String cpuBrand;
  final int memoryBytes;
  final String memoryGiB;

  Map<String, Object> toJson() => {
    'os': os,
    'osVersion': osVersion,
    'dartVersion': dartVersion,
    'processors': processors,
    'executable': executable,
    'machineModel': machineModel,
    'machineName': machineName,
    'cpuBrand': cpuBrand,
    'memoryBytes': memoryBytes,
    'memoryGiB': memoryGiB,
  };
}

String _sysctl(final String key) {
  if (!Platform.isMacOS) return '';
  final result = Process.runSync('sysctl', ['-n', key]);
  if (result.exitCode != 0) return '';
  return result.stdout.toString().trim();
}

String _friendlyMachineName(final String model) => switch (model) {
  'Mac14,2' => 'MacBook Air (M2, 2022)',
  _ => model,
};

String _formatMemoryGiB(final int bytes) {
  if (bytes <= 0) return '0.0';
  return (bytes / (1024 * 1024 * 1024)).toStringAsFixed(1);
}

String _commandLine(final String script, final List<String> args) {
  final suffix = args.isEmpty ? '' : ' ${args.join(' ')}';
  return 'dart run $script$suffix';
}

final class _GitInfo {
  const _GitInfo({
    required this.commit,
    required this.branch,
    required this.dirty,
  });

  factory _GitInfo.capture() => _GitInfo(
    commit: _gitOutput(['rev-parse', 'HEAD']),
    branch: _gitOutput(['branch', '--show-current']),
    dirty: _gitDirty(),
  );

  final String? commit;
  final String? branch;
  final bool? dirty;

  Map<String, Object?> toJson() => {
    'commit': commit,
    'branch': branch,
    'dirty': dirty,
  };
}

String? _gitOutput(final List<String> args) {
  try {
    final result = Process.runSync('git', args);
    if (result.exitCode != 0) return null;
    final output = result.stdout.toString().trim();
    return output.isEmpty ? null : output;
  } on ProcessException {
    return null;
  }
}

bool? _gitDirty() {
  try {
    final result = Process.runSync('git', ['status', '--porcelain']);
    if (result.exitCode != 0) return null;
    return result.stdout.toString().trim().isNotEmpty;
  } on ProcessException {
    return null;
  }
}

final class _BenchResource extends Resource {
  _BenchResource(this.value);

  int value;
}
