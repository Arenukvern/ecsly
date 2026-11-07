// ignore_for_file: avoid_print

/// Append-only data-plane ingest benchmark (ADR 0006).
///
/// Measures the workload class the runtime historically did not own:
/// folding an append-only event tail (a journal/log cursor delta) into a
/// World — homogeneous entities, batch-ordered structural growth, direct
/// column fill, then large membership-filtered scans. Four ingest legs at
/// each size isolate the two orthogonal choices:
///
///   map_ingest             plain `Map<int, record>` (the naive baseline)
///   command_queue_ingest   deferred command queue, object components
///   append_rows_objects    World.appendRows, same object components
///                          (isolates the command-queue overhead)
///   append_rows_columns    World.appendRows + typed SoA columns
///                          (isolates the storage-tier win)
///
/// plus scan legs at the largest size (flag-filtered numeric scan and
/// verbatim-string scan, map vs columns).
///
/// Run: `dart run benchmark/append_only_ingest.dart [--sizes=1000,100000,1000000] [--json] [--out=...]`
library;
import 'dart:convert';
import 'dart:io';

import 'package:ecsly/ecsly.dart';

void main(final List<String> args) {
  final json = args.contains('--json');
  final out = _argValue(args, '--out=');
  final sizes = _parseSizes(_argValue(args, '--sizes='));
  final samples = _parseSamples(_argValue(args, '--samples='));
  final report = samples == 1
      ? _runReport(args, sizes)
      : _runSampledReport(args, sizes, samples);
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

int _parseSamples(final String? raw) {
  if (raw == null) return 1;
  final samples = int.tryParse(raw);
  if (samples == null || samples < 1) {
    stderr.writeln('--samples must be a positive integer.');
    exit(64);
  }
  return samples;
}

/// Runs the whole battery [samples] times and keeps the MEDIAN of every
/// metric (the repo's sampling convention from `benchmark/run.dart`).
Map<String, Object?> _runSampledReport(
  final List<String> args,
  final List<int> sizes,
  final int samples,
) {
  final reports = <Map<String, Object?>>[
    for (var i = 0; i < samples; i++) _runReport(args, sizes),
  ];
  final byName = <String, List<Map<String, Object?>>>{};
  for (final report in reports) {
    for (final metric in report['metrics']! as List<Map<String, Object?>>) {
      byName.putIfAbsent(metric['name']! as String, () => []).add(metric);
    }
  }
  final median = <Map<String, Object?>>[];
  for (final entry in byName.entries) {
    final runs = entry.value;
    Map<String, Object?> pick(final String key) {
      final sorted = [...runs]..sort(
          (final a, final b) =>
              (a[key]! as num).compareTo(b[key]! as num),
        );
      return sorted[sorted.length ~/ 2];
    }
    final base = pick('opsPerSec');
    median.add(<String, Object?>{
      ...base,
      'elapsedMicros': pick('elapsedMicros')['elapsedMicros'],
      'rssDeltaBytes': pick('rssDeltaBytes')['rssDeltaBytes'],
      'samples': samples,
    });
  }
  return <String, Object?>{
    ...reports.first,
    'samples': samples,
    'metrics': median,
  };
}

List<int> _parseSizes(final String? raw) {
  if (raw == null) return const [1000, 100000, 1000000];
  return raw.split(',').map(int.parse).toList();
}

/// The verbatim payload of one ingested row. Fixed shape (~80 chars) so
/// the object-column legs measure the storage path, not a payload-size
/// difference: a data plane's whole job is keeping text like this intact.
String labelOf(final int i) =>
    'record $i with a verbatim text payload used for scan legs and kept '
    'whole, never truncated';

// ---------------------------------------------------------------------------
// Legs.
// ---------------------------------------------------------------------------

final class _Record {
  _Record(this.value, this.flags, this.label);
  final int value;
  final int flags;
  final String label;
}

({int micros, int rssDelta, int sink}) _benchMapIngest(final int n) {
  final rssBefore = ProcessInfo.currentRss;
  final sw = Stopwatch()..start();
  final map = <int, _Record>{};
  for (var i = 1; i <= n; i++) {
    map[i] = _Record(i, i % 7 == 0 ? 3 : 1, labelOf(i));
  }
  sw.stop();
  return (
    micros: sw.elapsedMicroseconds,
    rssDelta: ProcessInfo.currentRss - rssBefore,
    sink: map.length,
  );
}

// Command-queue leg components (object tier — the cold path a data-plane
// consumer reaches for today).
final class _CqValue extends Component {
  const _CqValue(this.value);
  final int value;
}

final class _CqFlags extends Component {
  const _CqFlags(this.flags);
  final int flags;
}

final class _CqLabel extends Component {
  const _CqLabel(this.label);
  final String label;
}

({int micros, int rssDelta, int sink}) _benchCommandQueueIngest(final int n) {
  final world = World();
  world.components
    ..registerObjectComponent<_CqValue>()
    ..registerObjectComponent<_CqFlags>()
    ..registerObjectComponent<_CqLabel>();
  final rssBefore = ProcessInfo.currentRss;
  final sw = Stopwatch()..start();
  const flushEvery = 1024;
  for (var i = 1; i <= n; i++) {
    final entity = world.entities.create();
    world.spawnBundle(
      entity,
      ComponentBundle.fromLists(<Component>[
        _CqValue(i),
        _CqFlags(i % 7 == 0 ? 3 : 1),
        _CqLabel(labelOf(i)),
      ]),
    );
    if (i % flushEvery == 0) world.flush();
  }
  world.flush();
  sw.stop();
  return (
    micros: sw.elapsedMicroseconds,
    rssDelta: ProcessInfo.currentRss - rssBefore,
    sink: world.entities.count,
  );
}

({int micros, int rssDelta, int sink}) _benchAppendRowsObjects(final int n) {
  final world = World();
  world.components
    ..registerObjectComponent<_CqValue>()
    ..registerObjectComponent<_CqFlags>()
    ..registerObjectComponent<_CqLabel>();
  final signature = ArchetypeSignature.fromIds([
    world.components.getComponentId<_CqValue>(),
    world.components.getComponentId<_CqFlags>(),
    world.components.getComponentId<_CqLabel>(),
  ]);
  final rssBefore = ProcessInfo.currentRss;
  final sw = Stopwatch()..start();
  const chunk = 4096;
  var done = 0;
  while (done < n) {
    final count = (n - done) < chunk ? (n - done) : chunk;
    final appended = world.appendRows(signature, count);
    final values = appended.archetype.getColumn(
      world.components.getComponentId<_CqValue>(),
    )! as ObjectColumn<_CqValue>;
    final flags = appended.archetype.getColumn(
      world.components.getComponentId<_CqFlags>(),
    )! as ObjectColumn<_CqFlags>;
    final labels = appended.archetype.getColumn(
      world.components.getComponentId<_CqLabel>(),
    )! as ObjectColumn<_CqLabel>;
    for (var k = 0; k < count; k++) {
      final i = done + k + 1;
      final row = appended.firstRow + k;
      values.setValue(row, _CqValue(i));
      flags.setValue(row, _CqFlags(i % 7 == 0 ? 3 : 1));
      labels.setValue(row, _CqLabel(labelOf(i)));
    }
    done += count;
  }
  sw.stop();
  return (
    micros: sw.elapsedMicroseconds,
    rssDelta: ProcessInfo.currentRss - rssBefore,
    sink: world.entities.count,
  );
}

// Typed-column leg components (SoA markers; data lives in the columns).
final class _SoaValue extends Component {
  const _SoaValue();
}

final class _SoaFlags extends Component {
  const _SoaFlags();
}

final class _SoaLabel extends Component {
  const _SoaLabel(this.label);
  final String label;
}

final class _IntColumnFactory extends ColumnFactory {
  @override
  DataColumn createColumn(
    final ComponentId componentId, {
    final int initialCapacity = 8,
  }) => IntColumn(initialCapacity: initialCapacity);
}

final class _Uint8ColumnFactory extends ColumnFactory {
  @override
  DataColumn createColumn(
    final ComponentId componentId, {
    final int initialCapacity = 8,
  }) => Uint8Column(initialCapacity: initialCapacity);
}

final class _ColumnWorld {
  _ColumnWorld(this.world, this.valueId, this.flagsId, this.labelId)
    : signature = ArchetypeSignature.fromIds([valueId, flagsId, labelId]);
  final World world;
  final ComponentId valueId;
  final ComponentId flagsId;
  final ComponentId labelId;
  final ArchetypeSignature signature;
}

_ColumnWorld _buildColumnWorld() {
  final world = World();
  final valueId = world.components.registerSoAComponent<_SoaValue>(
    columnFactory: _IntColumnFactory(),
  );
  final flagsId = world.components.registerSoAComponent<_SoaFlags>(
    columnFactory: _Uint8ColumnFactory(),
  );
  final labelId = world.components.registerObjectComponent<_SoaLabel>();
  return _ColumnWorld(world, valueId, flagsId, labelId);
}

({int micros, int rssDelta, int sink, _ColumnWorld holder})
_benchAppendRowsColumns(final int n) {
  final holder = _buildColumnWorld();
  final rssBefore = ProcessInfo.currentRss;
  final sw = Stopwatch()..start();
  const chunk = 4096;
  var done = 0;
  while (done < n) {
    final count = (n - done) < chunk ? (n - done) : chunk;
    final appended = holder.world.appendRows(holder.signature, count);
    final values =
        appended.archetype.getColumn(holder.valueId)! as IntColumn;
    final flags =
        appended.archetype.getColumn(holder.flagsId)! as Uint8Column;
    final labels = appended.archetype.getColumn(holder.labelId)!
        as ObjectColumn<_SoaLabel>;
    for (var k = 0; k < count; k++) {
      final i = done + k + 1;
      final row = appended.firstRow + k;
      values.setValueAt(row, i);
      flags.setValue(row, i % 7 == 0 ? 3 : 1);
      labels.setValue(row, _SoaLabel(labelOf(i)));
    }
    done += count;
  }
  sw.stop();
  return (
    micros: sw.elapsedMicroseconds,
    rssDelta: ProcessInfo.currentRss - rssBefore,
    sink: holder.world.entities.count,
    holder: holder,
  );
}

({int micros, int rssDelta, int sink}) _benchMapFlagScan(final int n) {
  final map = <int, _Record>{};
  for (var i = 1; i <= n; i++) {
    map[i] = _Record(i, i % 7 == 0 ? 3 : 1, labelOf(i));
  }
  final rssBefore = ProcessInfo.currentRss;
  final sw = Stopwatch()..start();
  var sink = 0;
  for (final record in map.values) {
    if (record.flags & 1 != 0 && record.flags & 2 == 0) {
      sink += record.value;
    }
  }
  sw.stop();
  return (
    micros: sw.elapsedMicroseconds,
    rssDelta: ProcessInfo.currentRss - rssBefore,
    sink: sink,
  );
}

({int micros, int rssDelta, int sink}) _benchColumnFlagScan(
  final _ColumnWorld holder,
  final int n,
) {
  final archetypeId = holder.world.archetypes.getOrCreateArchetype(
    holder.signature,
  );
  final archetype =
      holder.world.archetypes[holder.world.archetypes.findArchetypeIndex(
        archetypeId,
      )];
  final values = archetype.getColumn(holder.valueId)! as IntColumn;
  final flags = archetype.getColumn(holder.flagsId)! as Uint8Column;
  final flagData = flags.data;
  final valueData = values.data;
  final rssBefore = ProcessInfo.currentRss;
  final sw = Stopwatch()..start();
  var sink = 0;
  for (var row = 0; row < n; row++) {
    final f = flagData[row];
    if (f & 1 != 0 && f & 2 == 0) {
      sink += valueData[row];
    }
  }
  sw.stop();
  return (
    micros: sw.elapsedMicroseconds,
    rssDelta: ProcessInfo.currentRss - rssBefore,
    sink: sink,
  );
}

({int micros, int rssDelta, int sink}) _benchMapLabelScan(final int n) {
  final map = <int, _Record>{};
  for (var i = 1; i <= n; i++) {
    map[i] = _Record(i, i % 7 == 0 ? 3 : 1, labelOf(i));
  }
  final rssBefore = ProcessInfo.currentRss;
  final sw = Stopwatch()..start();
  var sink = 0;
  for (final record in map.values) {
    sink += record.label.length;
  }
  sw.stop();
  return (
    micros: sw.elapsedMicroseconds,
    rssDelta: ProcessInfo.currentRss - rssBefore,
    sink: sink,
  );
}

({int micros, int rssDelta, int sink}) _benchColumnLabelScan(
  final _ColumnWorld holder,
  final int n,
) {
  final archetypeId = holder.world.archetypes.getOrCreateArchetype(
    holder.signature,
  );
  final archetype =
      holder.world.archetypes[holder.world.archetypes.findArchetypeIndex(
        archetypeId,
      )];
  final labels = archetype.getColumn(holder.labelId)!
      as ObjectColumn<_SoaLabel>;
  final rssBefore = ProcessInfo.currentRss;
  final sw = Stopwatch()..start();
  var sink = 0;
  for (var row = 0; row < n; row++) {
    sink += labels.getValue(row)!.label.length;
  }
  sw.stop();
  return (
    micros: sw.elapsedMicroseconds,
    rssDelta: ProcessInfo.currentRss - rssBefore,
    sink: sink,
  );
}

// ---------------------------------------------------------------------------
// Report.
// ---------------------------------------------------------------------------

Map<String, Object?> _runReport(final List<String> args, final List<int> sizes) {
  final metrics = <Map<String, Object?>>[];
  for (final n in sizes) {
    final mapIngest = _benchMapIngest(n);
    metrics.add(_metric('map_ingest', n, mapIngest.micros, mapIngest.rssDelta));
    final cq = _benchCommandQueueIngest(n);
    metrics.add(_metric('command_queue_ingest', n, cq.micros, cq.rssDelta));
    final arObjects = _benchAppendRowsObjects(n);
    metrics.add(
      _metric(
        'append_rows_objects_ingest',
        n,
        arObjects.micros,
        arObjects.rssDelta,
      ),
    );
    final arColumns = _benchAppendRowsColumns(n);
    metrics.add(
      _metric(
        'append_rows_columns_ingest',
        n,
        arColumns.micros,
        arColumns.rssDelta,
      ),
    );
    if (n == sizes.last) {
      // Scan legs at the largest size only: they re-ingest their own data
      // (map legs) or ride the retained column world (appendRows legs).
      final mapFlag = _benchMapFlagScan(n);
      metrics.add(
        _metric('map_flag_scan', n, mapFlag.micros, mapFlag.rssDelta),
      );
      final colFlag = _benchColumnFlagScan(arColumns.holder, n);
      metrics.add(
        _metric(
          'column_flag_scan',
          n,
          colFlag.micros,
          colFlag.rssDelta,
        ),
      );
      final mapLabel = _benchMapLabelScan(n);
      metrics.add(
        _metric('map_label_scan', n, mapLabel.micros, mapLabel.rssDelta),
      );
      final colLabel = _benchColumnLabelScan(arColumns.holder, n);
      metrics.add(
        _metric(
          'column_label_scan',
          n,
          colLabel.micros,
          colLabel.rssDelta,
        ),
      );
    }
    // Cross-leg parity: every ingest leg sank the same entity count.
    if (mapIngest.sink != cq.sink ||
        cq.sink != arObjects.sink ||
        arObjects.sink != arColumns.sink) {
      stderr.writeln('ingest legs disagree on entity count at n=$n');
      exitCode = 1;
    }
  }
  return <String, Object?>{
    'schemaId': 'ecsly.core.append_only_ingest',
    'package': 'ecsly',
    'generatedAt': DateTime.now().toUtc().toIso8601String(),
    'command': _commandLine('benchmark/append_only_ingest.dart', args),
    'environment': _Environment.capture().toJson(),
    'git': _GitInfo.capture().toJson(),
    'sizes': sizes,
    'metrics': metrics,
  };
}

Map<String, Object?> _metric(
  final String name,
  final int n,
  final int micros,
  final int rssDelta,
) => <String, Object?>{
  'name': '$name${_sizeSuffix(n)}',
  'entities': n,
  'opsPerSec': (n / (micros / 1000000.0)).round(),
  'elapsedMicros': micros,
  'rssDeltaBytes': rssDelta,
};

String _sizeSuffix(final int n) => switch (n) {
  >= 1000000 => '_1m',
  >= 100000 => '_100k',
  _ => '_$n',
};

String _toText(final Map<String, Object?> report) {
  final buffer = StringBuffer()
    ..writeln('ecsly append-only ingest benchmark (ADR 0006)')
    ..writeln('generatedAt: ${report['generatedAt']}')
    ..writeln('git: ${report['git']}')
    ..writeln('environment: ${report['environment']}')
    ..writeln('sizes: ${report['sizes']}');
  for (final metric in report['metrics']! as List<Map<String, Object?>>) {
    buffer.writeln(
      '${metric['name']}: ${metric['opsPerSec']} ops/sec, '
      '${metric['elapsedMicros']} us, rssDelta=${metric['rssDeltaBytes']}',
    );
  }
  return buffer.toString();
}

String _commandLine(final String script, final List<String> args) {
  final suffix = args.isEmpty ? '' : ' ${args.join(' ')}';
  return 'dart run $script$suffix';
}

final class _Environment {
  const _Environment({
    required this.os,
    required this.osVersion,
    required this.dartVersion,
    required this.processors,
    required this.machineModel,
    required this.cpuBrand,
    required this.memoryGiB,
  });

  factory _Environment.capture() {
    final memoryBytes = Platform.isMacOS
        ? int.tryParse(_sysctl('hw.memsize')) ?? 0
        : 0;
    return _Environment(
      os: Platform.operatingSystem,
      osVersion: Platform.operatingSystemVersion,
      dartVersion: Platform.version,
      processors: Platform.numberOfProcessors,
      machineModel: _sysctl('hw.model'),
      cpuBrand: _sysctl('machdep.cpu.brand_string'),
      memoryGiB: memoryBytes <= 0
          ? '0.0'
          : (memoryBytes / (1024 * 1024 * 1024)).toStringAsFixed(1),
    );
  }

  final String os;
  final String osVersion;
  final String dartVersion;
  final int processors;
  final String machineModel;
  final String cpuBrand;
  final String memoryGiB;

  Map<String, Object> toJson() => <String, Object>{
    'os': os,
    'osVersion': osVersion,
    'dartVersion': dartVersion,
    'processors': processors,
    'machineModel': machineModel,
    'cpuBrand': cpuBrand,
    'memoryGiB': memoryGiB,
  };
}

String _sysctl(final String key) {
  if (!Platform.isMacOS) return '';
  final result = Process.runSync('sysctl', ['-n', key]);
  if (result.exitCode != 0) return '';
  return result.stdout.toString().trim();
}

final class _GitInfo {
  const _GitInfo({required this.commit, required this.branch, this.dirty});

  factory _GitInfo.capture() => _GitInfo(
    commit: _gitOutput(['rev-parse', 'HEAD']),
    branch: _gitOutput(['branch', '--show-current']),
    dirty: _gitOutput(['status', '--porcelain'])?.isNotEmpty ?? false,
  );

  final String? commit;
  final String? branch;
  final bool? dirty;

  Map<String, Object?> toJson() => <String, Object?>{
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
