// ignore_for_file: unused_field, use_setters_to_change_properties

import 'dart:convert';
import 'dart:io';

import 'package:ecsly/ecsly.dart';

void main(final List<String> args) {
  final jsonOut = _argValue(args, '--json-out=');
  final samples = _parseSamples(args);
  final report = _CommandProfileReport(
    generatedAt: DateTime.now().toUtc(),
    command: _commandLine('benchmark/profile_commands.dart', args),
    environment: _ProfileEnvironment.capture(),
    git: _GitInfo.capture(),
    sampleCount: samples,
    scenarios: [
      _profileCommandFlush(samples: samples),
      _profileMigration(samples: samples),
    ],
  );
  final text = const JsonEncoder.withIndent('  ').convert(report.toJson());

  if (jsonOut == null) {
    stdout.writeln(text);
    return;
  }
  final file = File(jsonOut);
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(text);
}

String? _argValue(final List<String> args, final String prefix) {
  for (final arg in args) {
    if (arg.startsWith(prefix)) return arg.substring(prefix.length);
  }
  return null;
}

int _parseSamples(final List<String> args) {
  final raw = _argValue(args, '--samples=') ?? '5';
  final samples = int.tryParse(raw);
  if (samples == null || samples < 1) {
    stderr.writeln('--samples must be a positive integer.');
    exit(64);
  }
  return samples;
}

String _commandLine(final String script, final List<String> args) {
  final suffix = args.isEmpty ? '' : ' ${args.join(' ')}';
  return 'dart run $script$suffix';
}

_ScenarioProfile _profileCommandFlush({required final int samples}) {
  const entityCount = 20000;
  final enqueue = <int>[];
  final flush = <int>[];
  final rssBefore = ProcessInfo.currentRss;
  var archetypeCountBefore = 0;
  var archetypeCountAfter = 0;
  var structuralRevision = 0;

  for (var sample = 0; sample < samples; sample++) {
    final world = _buildWorld();
    final entities = _seed(world, count: entityCount);
    archetypeCountBefore = world.archetypes.count;

    final enqueueWatch = Stopwatch()..start();
    for (final entity in entities) {
      world.commands.upsert(entity, const _BenchCommandValue(5));
    }
    enqueueWatch.stop();
    enqueue.add(enqueueWatch.elapsedMicroseconds);

    final flushWatch = Stopwatch()..start();
    world.flush();
    flushWatch.stop();
    flush.add(flushWatch.elapsedMicroseconds);

    archetypeCountAfter = world.archetypes.count;
    structuralRevision = world.structuralRevision;
  }

  return _ScenarioProfile(
    name: 'command_flush',
    entities: entityCount,
    runs: samples,
    commandCount: entityCount,
    archetypeCountBefore: archetypeCountBefore,
    archetypeCountAfter: archetypeCountAfter,
    structuralRevision: structuralRevision,
    rssDeltaBytes: ProcessInfo.currentRss - rssBefore,
    phases: {
      'enqueue_upsert': _PhaseStats.fromSamples(enqueue),
      'flush': _PhaseStats.fromSamples(flush),
    },
    notes: const [
      'Splits command enqueue from world.flush for object-component upsert.',
      'RSS is coarse process context, not allocator proof.',
    ],
  );
}

_ScenarioProfile _profileMigration({required final int samples}) {
  const entityCount = 15000;
  final addCommand = <int>[];
  final addFlush = <int>[];
  final removeCommand = <int>[];
  final removeFlush = <int>[];
  final rssBefore = ProcessInfo.currentRss;
  var archetypeCountBefore = 0;
  var archetypeCountAfter = 0;
  var structuralRevision = 0;

  for (var sample = 0; sample < samples; sample++) {
    final world = _buildWorld();
    final entities = _seed(world, count: entityCount);
    final benchTagId = world.components.getComponentId<_BenchTagComponent>();
    archetypeCountBefore = world.archetypes.count;

    final addCommandWatch = Stopwatch()..start();
    world.commands.batchAddExtensionComponents(entities, const [
      (_BenchTagComponent, _BenchTag),
    ]);
    addCommandWatch.stop();
    addCommand.add(addCommandWatch.elapsedMicroseconds);

    final addFlushWatch = Stopwatch()..start();
    world.flush();
    addFlushWatch.stop();
    addFlush.add(addFlushWatch.elapsedMicroseconds);

    final removeCommandWatch = Stopwatch()..start();
    world.commands.batchRemoveComponents(entities, [benchTagId]);
    removeCommandWatch.stop();
    removeCommand.add(removeCommandWatch.elapsedMicroseconds);

    final removeFlushWatch = Stopwatch()..start();
    world.flush();
    removeFlushWatch.stop();
    removeFlush.add(removeFlushWatch.elapsedMicroseconds);

    archetypeCountAfter = world.archetypes.count;
    structuralRevision = world.structuralRevision;
  }

  return _ScenarioProfile(
    name: 'migration',
    entities: entityCount,
    runs: samples,
    commandCount: entityCount * 2,
    archetypeCountBefore: archetypeCountBefore,
    archetypeCountAfter: archetypeCountAfter,
    structuralRevision: structuralRevision,
    rssDeltaBytes: ProcessInfo.currentRss - rssBefore,
    phases: {
      'add_command_enqueue': _PhaseStats.fromSamples(addCommand),
      'add_flush': _PhaseStats.fromSamples(addFlush),
      'remove_command_enqueue': _PhaseStats.fromSamples(removeCommand),
      'remove_flush': _PhaseStats.fromSamples(removeFlush),
    },
    notes: const [
      'Splits batch add/remove enqueue from each migration flush.',
      'Use VM-service profiling only after these phase timings identify a hot phase.',
    ],
  );
}

World _buildWorld() {
  final world = World();
  world.components
    ..registerObjectComponent<_BenchCommandValue>()
    ..registerExtension<_BenchAComponent, _BenchA>(
      columnFactory: _BenchScalarColumnFactory(),
      facadeFactory: _BenchAFacadeFactory(),
    )
    ..registerExtension<_BenchBComponent, _BenchB>(
      columnFactory: _BenchScalarColumnFactory(),
      facadeFactory: _BenchBFacadeFactory(),
    )
    ..registerExtension<_BenchCComponent, _BenchC>(
      columnFactory: _BenchScalarColumnFactory(),
      facadeFactory: _BenchCFacadeFactory(),
    )
    ..registerExtension<_BenchTagComponent, _BenchTag>(
      columnFactory: _BenchTagColumnFactory(),
      facadeFactory: _BenchTagFacadeFactory(),
    );
  return world;
}

List<Entity> _seed(final World world, {required final int count}) {
  final entities = world.reserveEmptyEntities(count);
  final baseBundle = ComponentBundle.fromLists(const [], const [
    (_BenchAComponent, _BenchA),
    (_BenchBComponent, _BenchB),
    (_BenchCComponent, _BenchC),
  ]);
  for (final entity in entities) {
    world.spawnBundle(entity, baseBundle);
  }
  world.flush();
  return entities;
}

final class _CommandProfileReport {
  const _CommandProfileReport({
    required this.generatedAt,
    required this.command,
    required this.environment,
    required this.git,
    required this.sampleCount,
    required this.scenarios,
  });

  final DateTime generatedAt;
  final String command;
  final _ProfileEnvironment environment;
  final _GitInfo git;
  final int sampleCount;
  final List<_ScenarioProfile> scenarios;

  Map<String, Object?> toJson() => {
    'schemaId': 'ecsly.core.command_profile',
    'package': 'ecsly',
    'generatedAt': generatedAt.toIso8601String(),
    'command': command,
    'environment': environment.toJson(),
    'git': git.toJson(),
    'sampleCount': sampleCount,
    'scenarios': [for (final scenario in scenarios) scenario.toJson()],
  };
}

final class _ScenarioProfile {
  const _ScenarioProfile({
    required this.name,
    required this.entities,
    required this.runs,
    required this.commandCount,
    required this.archetypeCountBefore,
    required this.archetypeCountAfter,
    required this.structuralRevision,
    required this.rssDeltaBytes,
    required this.phases,
    required this.notes,
  });

  final String name;
  final int entities;
  final int runs;
  final int commandCount;
  final int archetypeCountBefore;
  final int archetypeCountAfter;
  final int structuralRevision;
  final int rssDeltaBytes;
  final Map<String, _PhaseStats> phases;
  final List<String> notes;

  Map<String, Object?> toJson() => {
    'name': name,
    'entities': entities,
    'runs': runs,
    'commandCount': commandCount,
    'archetypeCountBefore': archetypeCountBefore,
    'archetypeCountAfter': archetypeCountAfter,
    'structuralRevision': structuralRevision,
    'rssDeltaBytes': rssDeltaBytes,
    'phaseTimingsMicros': {
      for (final entry in phases.entries) entry.key: entry.value.toJson(),
    },
    'notes': notes,
  };
}

final class _PhaseStats {
  const _PhaseStats({
    required this.median,
    required this.min,
    required this.max,
    required this.samples,
  });

  factory _PhaseStats.fromSamples(final List<int> samples) {
    final sorted = [...samples]..sort();
    final middle = sorted.length ~/ 2;
    final median = sorted.length.isOdd
        ? sorted[middle]
        : ((sorted[middle - 1] + sorted[middle]) / 2).round();
    return _PhaseStats(
      median: median,
      min: sorted.first,
      max: sorted.last,
      samples: samples,
    );
  }

  final int median;
  final int min;
  final int max;
  final List<int> samples;

  Map<String, Object?> toJson() => {
    'median': median,
    'min': min,
    'max': max,
    'samples': samples,
  };
}

final class _ProfileEnvironment {
  const _ProfileEnvironment({
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

  factory _ProfileEnvironment.capture() {
    final memoryBytes = int.tryParse(_sysctl('hw.memsize')) ?? 0;
    final machineModel = _sysctl('hw.model');
    return _ProfileEnvironment(
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

class _BenchCommandValue extends Component {
  const _BenchCommandValue(this.value);

  final int value;
}

abstract final class _BenchAComponent extends Component {}

abstract final class _BenchBComponent extends Component {}

abstract final class _BenchCComponent extends Component {}

class _BenchTagComponent extends Component {
  const _BenchTagComponent();
}

extension type _BenchA._(int index) {
  static late IntColumn _column;

  static void _init(final IntColumn column) {
    _column = column;
  }
}

extension type _BenchB._(int index) {
  static late IntColumn _column;

  static void _init(final IntColumn column) {
    _column = column;
  }
}

extension type _BenchC._(int index) {
  static late IntColumn _column;

  static void _init(final IntColumn column) {
    _column = column;
  }
}

extension type _BenchTag._(int index) {
  static late Uint8Column _column;

  static void _init(final Uint8Column column) {
    _column = column;
  }
}

final class _BenchScalarColumnFactory extends ColumnFactory {
  @override
  DataColumn createColumn(
    final ComponentId componentId, {
    final int initialCapacity = 8,
  }) => IntColumn(initialCapacity: initialCapacity);
}

final class _BenchTagColumnFactory extends ColumnFactory {
  @override
  DataColumn createColumn(
    final ComponentId componentId, {
    final int initialCapacity = 8,
  }) => Uint8Column(initialCapacity: initialCapacity);
}

final class _BenchAFacadeFactory extends ComponentFacadeFactory<_BenchA> {
  @override
  _BenchA create(final int index) => _BenchA._(index);

  @override
  void initialize(final DataColumn column) {
    _BenchA._init(column as IntColumn);
  }
}

final class _BenchBFacadeFactory extends ComponentFacadeFactory<_BenchB> {
  @override
  _BenchB create(final int index) => _BenchB._(index);

  @override
  void initialize(final DataColumn column) {
    _BenchB._init(column as IntColumn);
  }
}

final class _BenchCFacadeFactory extends ComponentFacadeFactory<_BenchC> {
  @override
  _BenchC create(final int index) => _BenchC._(index);

  @override
  void initialize(final DataColumn column) {
    _BenchC._init(column as IntColumn);
  }
}

final class _BenchTagFacadeFactory extends ComponentFacadeFactory<_BenchTag> {
  @override
  _BenchTag create(final int index) => _BenchTag._(index);

  @override
  void initialize(final DataColumn column) {
    _BenchTag._init(column as Uint8Column);
  }
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
