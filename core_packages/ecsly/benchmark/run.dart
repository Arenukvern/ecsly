// ignore_for_file: use_setters_to_change_properties

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:ecsly/ecsly.dart';

void main(final List<String> args) {
  final check = args.contains('--check');
  final json = args.contains('--json');
  final markdown = args.contains('--markdown');
  final includeLimits = args.contains('--limits');
  final out = _argValue(args, '--out=');
  final jsonOut = _argValue(args, '--json-out=');
  final markdownOut = _argValue(args, '--markdown-out=');
  final samples = _parseSamples(args);
  final report = samples == 1
      ? _runReport(includeLimits: includeLimits)
      : _runSampledReport(samples: samples, includeLimits: includeLimits);

  if (jsonOut != null) {
    _writeText(
      jsonOut,
      const JsonEncoder.withIndent('  ').convert(report.toJson()),
    );
  }
  if (markdownOut != null) {
    _writeText(markdownOut, report.toMarkdown());
  }

  final text = switch ((json, markdown)) {
    (true, _) => const JsonEncoder.withIndent('  ').convert(report.toJson()),
    (_, true) => report.toMarkdown(),
    _ => report.toText(),
  };

  if (out == null) {
    if (jsonOut == null && markdownOut == null) stdout.writeln(text);
  } else {
    _writeText(out, text);
  }

  if (!check) return;

  final metrics = {for (final metric in report.metrics) metric.name: metric};
  final thresholds = _readThresholds();
  var failed = false;
  for (final threshold in thresholds.values) {
    final actual = metrics[threshold.name];
    if (actual == null) continue;
    if (threshold.fails(actual.value)) {
      failed = true;
      stderr.writeln(
        'REGRESSION ${threshold.name}: actual='
        '${actual.value.toStringAsFixed(2)} ${actual.unit} '
        '${threshold.failureLabel}',
      );
    }
  }

  if (failed) {
    exitCode = 1;
  }
}

String? _argValue(final List<String> args, final String prefix) {
  for (final arg in args) {
    if (arg.startsWith(prefix)) return arg.substring(prefix.length);
  }
  return null;
}

int _parseSamples(final List<String> args) {
  final raw = _argValue(args, '--samples=') ?? '1';
  final samples = int.tryParse(raw);
  if (samples == null || samples < 1) {
    stderr.writeln('--samples must be a positive integer.');
    exit(64);
  }
  return samples;
}

void _writeText(final String path, final String text) {
  final file = File(path);
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(text);
}

_BenchmarkReport _runSampledReport({
  required final int samples,
  required final bool includeLimits,
}) {
  final reports = <_BenchmarkReport>[];
  for (var i = 0; i < samples; i++) {
    _gameFrame20kCache = null;
    reports.add(_runReport(includeLimits: includeLimits));
  }
  final first = reports.first;
  final metricSamples = <String, List<_BenchmarkMetric>>{};
  for (final report in reports) {
    for (final metric in report.metrics) {
      metricSamples.putIfAbsent(metric.name, () => []).add(metric);
    }
  }
  final metrics = <_BenchmarkMetric>[];
  for (final metric in first.metrics) {
    final samplesForMetric = metricSamples[metric.name] ?? const [];
    final values = [for (final sample in samplesForMetric) sample.value];
    metrics.add(
      _BenchmarkMetric(
        name: metric.name,
        value: _median(values),
        unit: metric.unit,
        category: metric.category,
        entities: metric.entities,
        notes: metric.notes,
        samples: values,
      ),
    );
  }
  return _BenchmarkReport(
    generatedAt: first.generatedAt,
    command: first.command,
    includeLimits: includeLimits,
    environment: first.environment,
    metrics: metrics,
    sampleCount: samples,
    aggregation: 'median',
  );
}

double _median(final List<double> values) {
  if (values.isEmpty) return 0;
  final sorted = [...values]..sort();
  final middle = sorted.length ~/ 2;
  if (sorted.length.isOdd) return sorted[middle];
  return (sorted[middle - 1] + sorted[middle]) / 2;
}

_BenchmarkReport _runReport({required final bool includeLimits}) {
  _gameFrame20kCache = null;
  final startedAt = DateTime.now().toUtc();
  final metrics = <_BenchmarkMetric>[
    _ops(
      name: 'query_iteration_ops_per_sec',
      value: _benchQueryIteration(),
      category: 'query',
      entities: 30000,
      notes: 'Typed-column raw extension query over two components.',
    ),
    _ops(
      name: 'raw_query_chunk_ops_per_sec',
      value: _benchRawQueryChunk(),
      category: 'query',
      entities: 30000,
      notes: 'Chunked raw query path; expected to be the strongest iterator.',
    ),
    _ops(
      name: 'query_count_ops_per_sec',
      value: _benchQueryCount(),
      category: 'query',
      entities: 30000,
      notes: 'Repeated count query over a stable archetype set.',
    ),
    _ops(
      name: 'query_any_ops_per_sec',
      value: _benchQueryAny(),
      category: 'query',
      entities: 30000,
      notes: 'Early-exit presence query over a stable archetype set.',
    ),
    _ops(
      name: 'mutable_query_iteration_ops_per_sec',
      value: _benchMutableQueryIteration(),
      category: 'mutation',
      entities: 30000,
      notes: 'In-place typed-column mutation over two components.',
    ),
    _ops(
      name: 'command_flush_ops_per_sec',
      value: _benchCommandFlush(),
      category: 'commands',
      entities: 20000,
      notes: 'Object-component upsert plus flush; useful bottleneck signal.',
    ),
    _ops(
      name: 'migration_ops_per_sec',
      value: _benchMigration(),
      category: 'commands',
      entities: 15000,
      notes: 'Batch add/remove extension component archetype migration.',
    ),
    _ops(
      name: 'query_cache_hit_ops_per_sec',
      value: _benchQueryCacheHit(),
      category: 'query-cache',
      entities: 20000,
      notes: 'Repeated query-cache hit for the same component mask.',
    ),
    _ops(
      name: 'query_cache_miss_ops_per_sec',
      value: _benchQueryCacheMiss(),
      category: 'query-cache',
      entities: 20000,
      notes:
          'Forced cache clear and recompute; highlights archetype matching cost.',
    ),
    _ops(
      name: 'event_send_ops_per_sec',
      value: _benchEventSend(),
      category: 'events',
      entities: 0,
      notes: 'Typed-data event writes into a fixed-capacity channel.',
    ),
    _ops(
      name: 'event_read_ops_per_sec',
      value: _benchEventRead(),
      category: 'events',
      entities: 0,
      notes: 'Cursor read over typed-data event channel.',
    ),
    _BenchmarkMetric(
      name: 'frame_rss_delta_bytes',
      value: _benchFrameRssDeltaBytes(),
      unit: 'bytes',
      category: 'memory',
      entities: 15000,
      notes: 'RSS delta across repeated typed-column frame updates.',
    ),
    _BenchmarkMetric(
      name: 'game_frame_20k_p50_micros',
      value: _benchGameFrame20k().p50Micros.toDouble(),
      unit: 'micros',
      category: 'game-frame',
      entities: 20000,
      notes:
          'Synthetic 120-frame game loop: typed update, packet extract, flush.',
    ),
    _BenchmarkMetric(
      name: 'game_frame_20k_p95_micros',
      value: _benchGameFrame20k().p95Micros.toDouble(),
      unit: 'micros',
      category: 'game-frame',
      entities: 20000,
      notes: 'Prototype-relevant frame budget signal; lower is better.',
    ),
    _BenchmarkMetric(
      name: 'game_frame_20k_p99_micros',
      value: _benchGameFrame20k().p99Micros.toDouble(),
      unit: 'micros',
      category: 'game-frame',
      entities: 20000,
      notes: 'Tail latency for frame-shaped ECS work; lower is better.',
    ),
    _ops(
      name: 'render_packet_extract_30k_ops_per_sec',
      value: _benchRenderPacketExtract(),
      category: 'render-extract',
      entities: 30000,
      notes: 'Packet-like extraction into Float32List, inspired by prototypes.',
    ),
    _BenchmarkMetric(
      name: 'render_packet_extract_30k_bytes',
      value: (30000 * 4 * Float32List.bytesPerElement).toDouble(),
      unit: 'bytes',
      category: 'render-extract',
      entities: 30000,
      notes: 'Packet-like Float32 payload bytes per extraction pass.',
    ),
    _ops(
      name: 'spawn_despawn_churn_ops_per_sec',
      value: _benchSpawnDespawnChurn(),
      category: 'commands',
      entities: 30000,
      notes: 'Frame-style structural churn: spawn then despawn batches.',
    ),
    if (includeLimits) ..._benchQueryScale(),
  ];
  return _BenchmarkReport(
    generatedAt: startedAt,
    command: 'dart run benchmark/run.dart',
    includeLimits: includeLimits,
    environment: _BenchmarkEnvironment.capture(),
    metrics: metrics,
    sampleCount: 1,
    aggregation: 'single',
  );
}

_BenchmarkMetric _ops({
  required final String name,
  required final double value,
  required final String category,
  required final int entities,
  required final String notes,
}) => _BenchmarkMetric(
  name: name,
  value: value,
  unit: 'ops/sec',
  category: category,
  entities: entities,
  notes: notes,
);

double _benchCommandFlush() {
  final world = _buildWorld();
  final entities = _seed(world, count: 20000, withTag: false);
  const runs = 10;
  final watch = Stopwatch()..start();
  for (var i = 0; i < runs; i++) {
    for (final entity in entities) {
      world.upsertComponent(entity, const _BenchCommandValue(5));
    }
    world.flush();
  }
  watch.stop();
  final totalOps = (entities.length * runs).toDouble();
  return totalOps / (watch.elapsedMicroseconds / 1000000.0);
}

double _benchEventRead() {
  final world = _buildWorld();
  world.events.register<_BenchEvent>(
    capacity: 100000,
    fromDoubleFieldsFactory: (final fields) =>
        _BenchEvent(fields[0].toInt(), fields[1]),
    sampleEvent: const _BenchEvent(0, 0),
  );
  final writer = world.events.writer<_BenchEvent>();
  const count = 50000;
  for (var i = 0; i < count; i++) {
    writer.send(_BenchEvent(i, i.toDouble()));
  }
  final reader = world.events.reader<_BenchEvent>();
  var sink = 0.0;
  final watch = Stopwatch()..start();
  final cursor = reader.cursor();
  while (cursor.moveNext()) {
    sink += cursor.current.value;
  }
  watch.stop();
  if (sink == -1) stderr.writeln('ignore: $sink');
  return count / (watch.elapsedMicroseconds / 1000000.0);
}

double _benchEventSend() {
  final world = _buildWorld();
  world.events.register<_BenchEvent>(
    capacity: 100000,
    fromDoubleFieldsFactory: (final fields) =>
        _BenchEvent(fields[0].toInt(), fields[1]),
    sampleEvent: const _BenchEvent(0, 0),
  );
  final writer = world.events.writer<_BenchEvent>();
  const count = 50000;
  final watch = Stopwatch()..start();
  for (var i = 0; i < count; i++) {
    writer.send(_BenchEvent(i, i.toDouble()));
  }
  watch.stop();
  return count / (watch.elapsedMicroseconds / 1000000.0);
}

double _benchMigration() {
  final world = _buildWorld();
  final entities = _seed(world, count: 15000, withTag: false);
  const runs = 8;
  final benchTagId = world.components.getComponentId<_BenchTagComponent>();
  final watch = Stopwatch()..start();
  for (var i = 0; i < runs; i++) {
    world.commands.batchAddExtensionComponents(entities, const [
      (_BenchTagComponent, _BenchTag),
    ]);
    world.flush();
    world.commands.batchRemoveComponents(entities, [benchTagId]);
    world.flush();
  }
  watch.stop();
  final totalOps = (entities.length * runs * 2).toDouble();
  return totalOps / (watch.elapsedMicroseconds / 1000000.0);
}

double _benchQueryAny() {
  final world = _buildWorld();
  _seed(world, count: 30000, withTag: false);
  const runs = 25000;
  var any = false;
  final watch = Stopwatch()..start();
  for (var i = 0; i < runs; i++) {
    any = world.queryAny2<_BenchAComponent, _BenchBComponent>();
  }
  watch.stop();
  if (!any) stderr.writeln('ignore: $any');
  return runs / (watch.elapsedMicroseconds / 1000000.0);
}

double _benchQueryCount() {
  final world = _buildWorld();
  _seed(world, count: 30000, withTag: false);
  const runs = 10000;
  var countSink = 0;
  final watch = Stopwatch()..start();
  for (var i = 0; i < runs; i++) {
    countSink += world.queryCount2<_BenchAComponent, _BenchBComponent>();
  }
  watch.stop();
  if (countSink == -1) stderr.writeln('ignore: $countSink');
  return runs / (watch.elapsedMicroseconds / 1000000.0);
}

double _benchMutableQueryIteration() {
  final world = _buildWorld();
  _seed(world, count: 30000, withTag: false);
  const runs = 20;
  final watch = Stopwatch()..start();
  for (var i = 0; i < runs; i++) {
    for (final (_, a, b)
        in world
            .queryRawExt2<
              _BenchAComponent,
              _BenchA,
              _BenchBComponent,
              _BenchB
            >()) {
      a.value += 1;
      b.value -= 1;
    }
  }
  watch.stop();
  final totalOps = (30000 * runs).toDouble();
  return totalOps / (watch.elapsedMicroseconds / 1000000.0);
}

double _benchQueryCacheHit() {
  final world = _buildWorld();
  _seed(world, count: 20000, withTag: false);
  final mask = createComponentMask([
    world.components.getComponentId<_BenchAComponent>(),
    world.components.getComponentId<_BenchBComponent>(),
  ]);

  world.queryCache.getOrCompute(mask, world.archetypes);
  const runs = 10000;
  final watch = Stopwatch()..start();
  for (var i = 0; i < runs; i++) {
    world.queryCache.getOrCompute(mask, world.archetypes);
  }
  watch.stop();
  return runs / (watch.elapsedMicroseconds / 1000000.0);
}

double _benchQueryCacheMiss() {
  final world = _buildWorld();
  _seed(world, count: 20000, withTag: false);
  const runs = 1000;
  final watch = Stopwatch()..start();
  for (var i = 0; i < runs; i++) {
    world.queryCache.clear();
    final mask = createComponentMask([
      world.components.getComponentId<_BenchAComponent>(),
      if (i.isEven) world.components.getComponentId<_BenchBComponent>(),
      if (i.isOdd) world.components.getComponentId<_BenchCComponent>(),
    ]);
    world.queryCache.getOrCompute(mask, world.archetypes);
  }
  watch.stop();
  return runs / (watch.elapsedMicroseconds / 1000000.0);
}

double _benchQueryIteration() {
  final world = _buildWorld();
  _seed(world, count: 30000, withTag: false);
  const runs = 20;
  var accumulator = 0;
  final watch = Stopwatch()..start();
  for (var i = 0; i < runs; i++) {
    for (final (_, a, b)
        in world
            .queryRawExt2<
              _BenchAComponent,
              _BenchA,
              _BenchBComponent,
              _BenchB
            >()) {
      accumulator += a.value + b.value;
    }
  }
  watch.stop();
  if (accumulator == 0) stderr.writeln('ignore: $accumulator');
  final totalOps = (30000 * runs).toDouble();
  return totalOps / (watch.elapsedMicroseconds / 1000000.0);
}

double _benchRawQueryChunk() {
  final world = _buildWorld();
  _seed(world, count: 30000, withTag: false);
  const runs = 20;
  var accumulator = 0;
  final watch = Stopwatch()..start();
  for (var i = 0; i < runs; i++) {
    for (final chunk
        in world
            .queryRaw2<
              _BenchAComponent,
              _BenchA,
              _BenchBComponent,
              _BenchB
            >()) {
      chunk.forEachRow((final _, final _, final a, final b) {
        accumulator += a.value + b.value;
      });
    }
  }
  watch.stop();
  if (accumulator == 0) stderr.writeln('ignore: $accumulator');
  final totalOps = (30000 * runs).toDouble();
  return totalOps / (watch.elapsedMicroseconds / 1000000.0);
}

double _benchFrameRssDeltaBytes() {
  final world = _buildWorld();
  _seed(world, count: 15000, withTag: false);
  const frames = 120;
  final rssBefore = ProcessInfo.currentRss.toDouble();
  for (var frame = 0; frame < frames; frame++) {
    for (final (_, a, b)
        in world
            .queryRawExt2<
              _BenchAComponent,
              _BenchA,
              _BenchBComponent,
              _BenchB
            >()) {
      a.value += 1;
      b.value -= 1;
    }
    world.flush();
  }
  final rssAfter = ProcessInfo.currentRss.toDouble();
  final delta = rssAfter - rssBefore;
  return delta > 0 ? delta : 0;
}

_GameFrameStats? _gameFrame20kCache;

_GameFrameStats _benchGameFrame20k() =>
    _gameFrame20kCache ??= _measureGameFrame20k();

_GameFrameStats _measureGameFrame20k() {
  final world = _buildWorld();
  _seed(world, count: 20000, withTag: false);
  final packet = Float32List(20000 * 4);
  const frames = 120;
  final timings = <int>[];
  var sink = 0.0;
  for (var frame = 0; frame < frames; frame++) {
    final watch = Stopwatch()..start();
    for (final (_, a, b)
        in world
            .queryRawExt2<
              _BenchAComponent,
              _BenchA,
              _BenchBComponent,
              _BenchB
            >()) {
      a.value += 1;
      b.value -= 1;
    }
    var offset = 0;
    for (final chunk
        in world
            .queryRaw3<
              _BenchAComponent,
              _BenchA,
              _BenchBComponent,
              _BenchB,
              _BenchCComponent,
              _BenchC
            >()) {
      chunk.forEachRow((final _, final _, final a, final b, final c) {
        packet[offset++] = a.value.toDouble();
        packet[offset++] = b.value.toDouble();
        packet[offset++] = c.value.toDouble();
        packet[offset++] = frame.toDouble();
      });
    }
    world.flush();
    watch.stop();
    timings.add(watch.elapsedMicroseconds);
    sink += packet[0];
  }
  if (sink == -1) stderr.writeln('ignore: $sink');
  timings.sort();
  return _GameFrameStats(
    p50Micros: _percentile(timings, 0.50),
    p95Micros: _percentile(timings, 0.95),
    p99Micros: _percentile(timings, 0.99),
  );
}

int _percentile(final List<int> sortedValues, final double percentile) {
  final index = ((sortedValues.length - 1) * percentile).round();
  final safeIndex = index.clamp(0, sortedValues.length - 1);
  return sortedValues[safeIndex];
}

String _formatMemoryGiB(final int bytes) {
  if (bytes <= 0) return '';
  return (bytes / (1024 * 1024 * 1024)).toStringAsFixed(1);
}

double _benchRenderPacketExtract() {
  final world = _buildWorld();
  _seed(world, count: 30000, withTag: false);
  final packet = Float32List(30000 * 4);
  const runs = 30;
  var sink = 0.0;
  final watch = Stopwatch()..start();
  for (var run = 0; run < runs; run++) {
    var offset = 0;
    for (final chunk
        in world
            .queryRaw3<
              _BenchAComponent,
              _BenchA,
              _BenchBComponent,
              _BenchB,
              _BenchCComponent,
              _BenchC
            >()) {
      chunk.forEachRow((final _, final _, final a, final b, final c) {
        packet[offset++] = a.value.toDouble();
        packet[offset++] = b.value.toDouble();
        packet[offset++] = c.value.toDouble();
        packet[offset++] = run.toDouble();
      });
    }
    sink += packet[0];
  }
  watch.stop();
  if (sink == -1) stderr.writeln('ignore: $sink');
  return (30000 * runs) / (watch.elapsedMicroseconds / 1000000.0);
}

double _benchSpawnDespawnChurn() {
  final world = _buildWorld();
  final survivors = _seed(world, count: 30000, withTag: false);
  const frames = 60;
  const churnPerFrame = 500;
  var cursor = 0;
  final bundle = ComponentBundle.fromLists(const [], const [
    (_BenchAComponent, _BenchA),
    (_BenchBComponent, _BenchB),
  ]);
  final watch = Stopwatch()..start();
  for (var frame = 0; frame < frames; frame++) {
    final spawned = world.reserveEmptyEntities(churnPerFrame);
    for (final entity in spawned) {
      world.spawnBundle(entity, bundle);
    }
    for (var i = 0; i < churnPerFrame; i++) {
      world.commands.despawn(survivors[cursor++ % survivors.length]);
    }
    world.flush();
    survivors
      ..removeRange(0, churnPerFrame)
      ..addAll(spawned);
    cursor = 0;
  }
  watch.stop();
  return (frames * churnPerFrame * 2) / (watch.elapsedMicroseconds / 1000000.0);
}

World _buildWorld() {
  final world = World();
  world.enforceSoAForHotSchedules = false;
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

Map<String, _BenchmarkThreshold> _readThresholds() {
  final file = File('benchmark/thresholds.yaml');
  if (!file.existsSync()) return const {};
  final output = <String, _BenchmarkThreshold>{};
  _BenchmarkThresholdBuilder? pending;

  void flushPending() {
    final threshold = pending?.build();
    if (threshold != null) output[threshold.name] = threshold;
    pending = null;
  }

  for (final raw in file.readAsLinesSync()) {
    final withoutComment = raw.split('#').first;
    final line = withoutComment.trimRight();
    if (line.isEmpty || line.startsWith('#')) continue;
    final split = line.split(':');
    if (split.length < 2) continue;
    final key = split.first.trim();
    final value = split.sublist(1).join(':').trim();
    if (!raw.startsWith(' ')) {
      flushPending();
      if (value.isEmpty) {
        pending = _BenchmarkThresholdBuilder(key);
      } else {
        final parsed = double.tryParse(value);
        if (parsed != null) {
          output[key] = _BenchmarkThreshold.minimum(key, parsed);
        }
      }
      continue;
    }

    final builder = pending;
    if (builder == null) continue;
    builder.accept(key, value);
  }
  flushPending();
  return output;
}

enum _BenchmarkThresholdDirection { minimum, maximum }

final class _BenchmarkThreshold {
  const _BenchmarkThreshold._({
    required this.name,
    required this.limit,
    required this.direction,
  });

  factory _BenchmarkThreshold.minimum(final String name, final double limit) =>
      _BenchmarkThreshold._(
        name: name,
        limit: limit,
        direction: _BenchmarkThresholdDirection.minimum,
      );

  factory _BenchmarkThreshold.maximum(final String name, final double limit) =>
      _BenchmarkThreshold._(
        name: name,
        limit: limit,
        direction: _BenchmarkThresholdDirection.maximum,
      );

  final String name;
  final double limit;
  final _BenchmarkThresholdDirection direction;

  bool fails(final double actual) => switch (direction) {
    _BenchmarkThresholdDirection.minimum => actual < limit,
    _BenchmarkThresholdDirection.maximum => actual > limit,
  };

  String get failureLabel => switch (direction) {
    _BenchmarkThresholdDirection.minimum =>
      'below minimum ${limit.toStringAsFixed(2)}',
    _BenchmarkThresholdDirection.maximum =>
      'above maximum ${limit.toStringAsFixed(2)}',
  };
}

final class _BenchmarkThresholdBuilder {
  _BenchmarkThresholdBuilder(this.name);

  final String name;
  double? min;
  double? max;
  double? limit;
  String? direction;
  bool? lowerIsBetter;

  void accept(final String key, final String value) {
    switch (key) {
      case 'min' || 'minimum':
        min = double.tryParse(value);
      case 'max' || 'maximum':
        max = double.tryParse(value);
      case 'threshold' || 'limit':
        limit = double.tryParse(value);
      case 'direction' || 'better':
        direction = value.toLowerCase();
      case 'lowerIsBetter' || 'lower_is_better':
        lowerIsBetter = _parseBool(value);
    }
  }

  _BenchmarkThreshold? build() {
    if (min case final value?) {
      return _BenchmarkThreshold.minimum(name, value);
    }
    if (max case final value?) {
      return _BenchmarkThreshold.maximum(name, value);
    }
    if (limit case final value?) {
      if (lowerIsBetter == true) {
        return _BenchmarkThreshold.maximum(name, value);
      }
      return switch (direction) {
        'lower' => _BenchmarkThreshold.maximum(name, value),
        _ => _BenchmarkThreshold.minimum(name, value),
      };
    }
    return null;
  }
}

bool? _parseBool(final String value) => switch (value.toLowerCase()) {
  'true' || 'yes' || '1' => true,
  'false' || 'no' || '0' => false,
  _ => null,
};

List<_BenchmarkMetric> _benchQueryScale() {
  const counts = [1000, 10000, 30000, 100000];
  return [
    for (final count in counts)
      _ops(
        name: 'query_iteration_${count}_entities_ops_per_sec',
        value: _benchQueryIterationFor(count),
        category: 'limit-scan',
        entities: count,
        notes: 'Same typed-column query at increasing entity counts.',
      ),
  ];
}

double _benchQueryIterationFor(final int count) {
  final world = _buildWorld();
  _seed(world, count: count, withTag: false);
  final runs = count <= 10000 ? 50 : 20;
  var accumulator = 0;
  final watch = Stopwatch()..start();
  for (var i = 0; i < runs; i++) {
    for (final (_, a, b)
        in world
            .queryRawExt2<
              _BenchAComponent,
              _BenchA,
              _BenchBComponent,
              _BenchB
            >()) {
      accumulator += a.value + b.value;
    }
  }
  watch.stop();
  if (accumulator == 0) stderr.writeln('ignore: $accumulator');
  final totalOps = (count * runs).toDouble();
  return totalOps / (watch.elapsedMicroseconds / 1000000.0);
}

List<Entity> _seed(
  final World world, {
  required final int count,
  required final bool withTag,
}) {
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
  for (final chunk
      in world
          .queryRaw3<
            _BenchAComponent,
            _BenchA,
            _BenchBComponent,
            _BenchB,
            _BenchCComponent,
            _BenchC
          >()) {
    chunk.forEachRow((final _, final _, final a, final b, final c) {
      a.value = 1;
      b.value = 2;
      c.value = 3;
    });
  }
  if (withTag) {
    world.commands.batchAddExtensionComponents(entities, const [
      (_BenchTagComponent, _BenchTag),
    ]);
    world.flush();
  }
  return entities;
}

class _BenchCommandValue extends Component {
  const _BenchCommandValue(this.value);
  final int value;
}

abstract final class _BenchAComponent extends Component {}

abstract final class _BenchBComponent extends Component {}

abstract final class _BenchCComponent extends Component {}

extension type _BenchA._(int index) {
  static late IntColumn _column;

  static void _init(final IntColumn column) {
    _column = column;
  }

  int get value => _column.getValueAt(index);
  set value(final int v) => _column.setValueAt(index, v);
}

extension type _BenchB._(int index) {
  static late IntColumn _column;

  static void _init(final IntColumn column) {
    _column = column;
  }

  int get value => _column.getValueAt(index);
  set value(final int v) => _column.setValueAt(index, v);
}

extension type _BenchC._(int index) {
  static late IntColumn _column;

  static void _init(final IntColumn column) {
    _column = column;
  }

  int get value => _column.getValueAt(index);
  set value(final int v) => _column.setValueAt(index, v);
}

class _BenchEvent extends EcsEvent
    with TypedDataEventMixin
    implements TypedDataEvent {
  const _BenchEvent(this.id, this.value);

  final int id;
  final double value;

  @override
  int get numericFieldCount => 2;

  @override
  List<double> get numericFields => [id.toDouble(), value];

  @override
  void writeNumericFieldsTo(final Float32List target) {
    target[0] = id.toDouble();
    target[1] = value;
  }
}

class _BenchTagComponent extends Component {
  const _BenchTagComponent();
}

extension type _BenchTag._(int index) {
  static late Uint8Column _column;

  static void _init(final Uint8Column column) {
    _column = column;
  }

  int get value => _column.getValue(index);
  set value(final int v) => _column.setValue(index, v);
}

final class _BenchTagColumnFactory extends ColumnFactory {
  @override
  DataColumn createColumn(
    final ComponentId componentId, {
    final int initialCapacity = 8,
  }) => Uint8Column(initialCapacity: initialCapacity);
}

final class _BenchScalarColumnFactory extends ColumnFactory {
  @override
  DataColumn createColumn(
    final ComponentId componentId, {
    final int initialCapacity = 8,
  }) => IntColumn(initialCapacity: initialCapacity);
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

final class _BenchmarkEnvironment {
  const _BenchmarkEnvironment({
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
    required this.gitCommit,
    required this.gitDirty,
  });

  factory _BenchmarkEnvironment.capture() => _BenchmarkEnvironment(
    os: Platform.operatingSystem,
    osVersion: Platform.operatingSystemVersion,
    dartVersion: Platform.version,
    processors: Platform.numberOfProcessors,
    executable: Platform.executable,
    machineModel: _sysctl('hw.model'),
    machineName: _friendlyMachineName(_sysctl('hw.model')),
    cpuBrand: _sysctl('machdep.cpu.brand_string'),
    memoryBytes: int.tryParse(_sysctl('hw.memsize')) ?? 0,
    memoryGiB: _formatMemoryGiB(int.tryParse(_sysctl('hw.memsize')) ?? 0),
    gitCommit: _gitOutput(['rev-parse', '--short=12', 'HEAD']),
    gitDirty: _gitOutput(['status', '--porcelain']).isNotEmpty,
  );

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
  final String gitCommit;
  final bool gitDirty;

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
    'gitCommit': gitCommit,
    'gitDirty': gitDirty,
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

String _gitOutput(final List<String> args) {
  final result = Process.runSync('git', args);
  if (result.exitCode != 0) return '';
  return result.stdout.toString().trim();
}

final class _GameFrameStats {
  const _GameFrameStats({
    required this.p50Micros,
    required this.p95Micros,
    required this.p99Micros,
  });

  final int p50Micros;
  final int p95Micros;
  final int p99Micros;
}

final class _BenchmarkMetric {
  const _BenchmarkMetric({
    required this.name,
    required this.value,
    required this.unit,
    required this.category,
    required this.entities,
    required this.notes,
    this.samples = const [],
  });

  final String name;
  final double value;
  final String unit;
  final String category;
  final int entities;
  final String notes;
  final List<double> samples;

  double? get nsPerOp {
    if (unit != 'ops/sec' || value <= 0) return null;
    return 1000000000.0 / value;
  }

  int get sampleCount => samples.isEmpty ? 1 : samples.length;

  double? get minSample {
    if (samples.isEmpty) return null;
    return samples.reduce((final a, final b) => a < b ? a : b);
  }

  double? get maxSample {
    if (samples.isEmpty) return null;
    return samples.reduce((final a, final b) => a > b ? a : b);
  }

  String get improvementDirection {
    if (unit == 'ops/sec') return 'higher';
    if (name == 'render_packet_extract_30k_bytes') return 'informational';
    return 'lower';
  }

  Map<String, Object?> toJson() => {
    'name': name,
    'value': value,
    'unit': unit,
    'category': category,
    'entities': entities,
    'nsPerOp': nsPerOp,
    'sampleCount': sampleCount,
    'aggregation': samples.isEmpty ? 'single' : 'median',
    'improvementDirection': improvementDirection,
    if (samples.isNotEmpty) ...{
      'samples': samples,
      'min': minSample,
      'max': maxSample,
    },
    'notes': notes,
  };
}

final class _BenchmarkReport {
  const _BenchmarkReport({
    required this.generatedAt,
    required this.command,
    required this.includeLimits,
    required this.environment,
    required this.metrics,
    required this.sampleCount,
    required this.aggregation,
  });

  final DateTime generatedAt;
  final String command;
  final bool includeLimits;
  final _BenchmarkEnvironment environment;
  final List<_BenchmarkMetric> metrics;
  final int sampleCount;
  final String aggregation;

  Map<String, Object> toJson() => {
    'package': 'ecsly',
    'generatedAt': generatedAt.toIso8601String(),
    'command': _commandText(),
    'sampleCount': sampleCount,
    'aggregation': aggregation,
    'environment': environment.toJson(),
    'metrics': [for (final metric in metrics) metric.toJson()],
  };

  String _commandText() {
    final parts = <String>[
      command,
      if (includeLimits) '--limits',
      if (sampleCount > 1) '--samples=$sampleCount',
    ];
    return parts.join(' ');
  }

  String toText() {
    final buffer = StringBuffer()
      ..writeln('ecsly benchmark metrics')
      ..writeln('generated_at: ${generatedAt.toIso8601String()}')
      ..writeln('command: ${_commandText()}')
      ..writeln('samples: $sampleCount')
      ..writeln('aggregation: $aggregation')
      ..writeln('os: ${environment.os}')
      ..writeln('machine: ${environment.machineName}')
      ..writeln('cpu: ${environment.cpuBrand}')
      ..writeln('memory_gib: ${environment.memoryGiB}')
      ..writeln('git_commit: ${environment.gitCommit}')
      ..writeln('git_dirty: ${environment.gitDirty}')
      ..writeln('dart: ${environment.dartVersion.split('\n').first}');
    for (final metric in metrics) {
      final suffix = metric.nsPerOp == null
          ? ''
          : ' (${metric.nsPerOp!.toStringAsFixed(2)} ns/op)';
      buffer.writeln(
        '${metric.name}: ${metric.value.toStringAsFixed(2)} '
        '${metric.unit}$suffix',
      );
    }
    return buffer.toString();
  }

  String toMarkdown() {
    final buffer = StringBuffer()
      ..writeln('# ecsly benchmark report')
      ..writeln()
      ..writeln('- Generated: `${generatedAt.toIso8601String()}`')
      ..writeln('- Command: `${_commandText()}`')
      ..writeln('- Samples: `$sampleCount`')
      ..writeln('- Aggregation: `$aggregation`')
      ..writeln('- OS: `${environment.os}`')
      ..writeln('- Machine: `${environment.machineName}`')
      ..writeln('- CPU: `${environment.cpuBrand}`')
      ..writeln('- Memory: `${environment.memoryGiB} GiB`')
      ..writeln('- Git commit: `${environment.gitCommit}`')
      ..writeln('- Git dirty: `${environment.gitDirty}`')
      ..writeln('- Dart: `${environment.dartVersion.split('\n').first}`')
      ..writeln('- Processors: `${environment.processors}`')
      ..writeln()
      ..writeln('## Metrics')
      ..writeln()
      ..writeln(
        '| Metric | Category | Entities | Value | ns/op | Range | Better | Notes |',
      )
      ..writeln('|---|---:|---:|---:|---:|---:|---:|---|');
    for (final metric in metrics) {
      final ns = metric.nsPerOp?.toStringAsFixed(2) ?? '';
      final range = metric.samples.isEmpty
          ? ''
          : '${metric.minSample!.toStringAsFixed(2)}-'
                '${metric.maxSample!.toStringAsFixed(2)}';
      buffer.writeln(
        '| `${metric.name}` | ${metric.category} | ${metric.entities} | '
        '${metric.value.toStringAsFixed(2)} ${metric.unit} | $ns | $range | '
        '${metric.improvementDirection} | '
        '${metric.notes} |',
      );
    }
    buffer
      ..writeln()
      ..writeln('## Reading the numbers')
      ..writeln()
      ..writeln('- Higher `ops/sec` is better for throughput metrics.')
      ..writeln('- Lower `ns/op` is better for per-operation cost.')
      ..writeln('- Lower `micros` is better for frame and latency metrics.')
      ..writeln('- Query and raw chunk metrics show hot-path strengths.')
      ..writeln(
        '- Command, migration, cache-miss, and frame-tail metrics expose bottlenecks.',
      )
      ..writeln('- Compare reports from the same machine, OS, and Dart SDK.');
    return buffer.toString();
  }
}
