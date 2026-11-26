import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:ecsly/ecsly.dart';

import 'simd_compiler.dart';
import 'simd_report_stub.dart' if (dart.library.io) 'simd_report_io.dart';

/// Row counts per kernel. 64 exposes per-call setup cost.
const _sizes = [64, 1000, 10000, 100000];
final _sw = Stopwatch();

void main(List<String> args) {
  final samples = _intArg(args, '--samples=', 5);
  final batchMs = _intArg(args, '--batch-ms=', 60);
  final warmMs = _intArg(args, '--warm-ms=', 300);
  final jsonOut = _stringArg(args, '--json-out=');
  final compiler = _stringArg(args, '--compiler=') ?? kEcslyCompilerKind;
  final label = _stringArg(args, '--label=');

  _verifyKernels();

  final metrics = <Map<String, Object?>>[];
  for (final entities in _sizes) {
    metrics.add(_updatePosition(entities, samples, batchMs, warmMs));
    metrics.add(_normalize(entities, samples, batchMs, warmMs));
    metrics.add(_distance(entities, samples, batchMs, warmMs));
    metrics.add(_scale(entities, 2, samples, batchMs, warmMs));
    metrics.add(_scale(entities, 4, samples, batchMs, warmMs));
    metrics.add(_add(entities, samples, batchMs, warmMs));
    metrics.add(_dot(entities, samples, batchMs, warmMs));
  }
  metrics.add(_intLessThan(100000, samples, batchMs, warmMs));

  final report = <String, Object?>{
    'generatedAt': DateTime.now().toUtc().toIso8601String(),
    'command': 'benchmark/simd_columns.dart ${args.join(' ')}'.trim(),
    'label': ?label,
    'compiler': compiler,
    'simdHardware': kEcslySimdHardware,
    'maskWordSize': emptyComponentMask.wordSize,
    'aggregation': 'median',
    'sampleCount': samples,
    'batchMs': batchMs,
    'environment': reportEnvironment(),
    'metrics': metrics,
  };
  writeReport(jsonOut, const JsonEncoder.withIndent('  ').convert(report));
}

void _verifyKernels() {
  final position = _filled2(3, (i) => (i + 1.0, i == 1 ? 0.0 : 4.0));
  final velocity = _filled2(3, (i) => (0.5, -0.25));
  final expected = _snapshot(position);
  for (var i = 0; i < 3; i++) {
    expected[i * 2] += velocity.getValue(i, 0) * 0.5;
    expected[i * 2 + 1] += velocity.getValue(i, 1) * 0.5;
  }
  updatePositionSimd(position, velocity, 0.5);
  _expectFloats(position, expected);

  final vectors = _filled2(3, (i) => i == 0 ? (double.nan, 1.0) : (3.0, 4.0));
  normalizeVectorsSimd(vectors);
  if (!vectors.getValue(0, 0).isNaN || vectors.getValue(0, 1) != 1) {
    throw StateError('normalize did not keep the NaN lane');
  }
  if ((vectors.getValue(1, 0) - 0.6).abs() > 1e-5) {
    throw StateError('normalize changed the (3, 4) vector');
  }

  final points = _filled2(2, (_) => (3.0, 4.0));
  final out = FloatColumn(stride: 1, initialCapacity: 2)
    ..addBlank()
    ..addBlank();
  calculateDistancesSimd(points, Float32x4(0, 0, 80, 90), out);
  if ((out.getValue(0, 0) - 5).abs() > 1e-5 ||
      (out.getValue(1, 0) - 5).abs() > 1e-5) {
    throw StateError('distance used target.z or target.w');
  }
}

Map<String, Object?> _updatePosition(
  int entities,
  int samples,
  int batchMs,
  int warmMs,
) {
  final position = _filled2(entities, (i) => (i * 0.01, 1));
  final velocity = _filled2(entities, (i) => (0.25, -0.5));
  final accessor = _filled2(entities, (i) => (i * 0.01, 1));
  final before = _snapshot(position);
  updatePositionSimd(position, velocity, 0.016);
  _accessorIntegrate(accessor, velocity, 0.016);
  _expectFloats(position, _snapshot(accessor));
  _restore(position, before);

  final library = _time(samples, batchMs, warmMs, 2, () {
    updatePositionSimd(position, velocity, 0.016);
    updatePositionSimd(position, velocity, -0.016);
  });
  final scalar = _time(samples, batchMs, warmMs, 2, () {
    _accessorIntegrate(accessor, velocity, 0.016);
    _accessorIntegrate(accessor, velocity, -0.016);
  });
  return _metric(
    'update_position_stride2_us',
    entities,
    library,
    scalar,
    'Stride-2 integrate. The scalar twin is the getValue/setValue loop the '
        '1.0.1 kernel ran.',
  );
}

Map<String, Object?> _normalize(
  int entities,
  int samples,
  int batchMs,
  int warmMs,
) {
  final column = _filled2(entities, (i) => (3 + (i % 5), 4));
  final accessor = _filled2(entities, (i) => (3 + (i % 5), 4));
  _accessorNormalize(accessor);
  final before = _snapshot(column);
  normalizeVectorsSimd(column);
  _expectFloats(column, _snapshot(accessor));
  _restore(column, before);

  final library = _time(samples, batchMs, warmMs, 1, () {
    normalizeVectorsSimd(column);
  });
  final scalar = _time(samples, batchMs, warmMs, 1, () {
    _accessorNormalize(accessor);
  });
  return _metric(
    'normalize_stride2_us',
    entities,
    library,
    scalar,
    'Stride-2 normalize. The scalar twin is the getValue/setValue loop the '
        '1.0.1 kernel ran.',
  );
}

Map<String, Object?> _distance(
  int entities,
  int samples,
  int batchMs,
  int warmMs,
) {
  final points = _filled2(entities, (i) => (i * 0.02, 4));
  final out = FloatColumn(stride: 1, initialCapacity: entities);
  final outAccessor = FloatColumn(stride: 1, initialCapacity: entities);
  for (var i = 0; i < entities; i++) {
    out.addBlank();
    outAccessor.addBlank();
  }
  final target = Float32x4(0, 0, 7, 8);
  calculateDistancesSimd(points, target, out);
  for (var i = 0; i < entities; i++) {
    final dx = points.getValue(i, 0);
    final dy = points.getValue(i, 1);
    final expected = math.sqrt(dx * dx + dy * dy);
    if (!_closeFloat32(out.getValue(i, 0), expected)) {
      throw StateError(
        'distance mismatch at $i: ${out.getValue(i, 0)} != $expected',
      );
    }
  }
  final library = _time(samples, batchMs, warmMs, 1, () {
    calculateDistancesSimd(points, target, out);
  });
  final scalar = _time(samples, batchMs, warmMs, 1, () {
    _accessorDistance(points, target, outAccessor);
  });
  return _metric(
    'distance_stride2_us',
    entities,
    library,
    scalar,
    'Stride-2 distance to (target.x, target.y). The scalar twin is the '
        'getValue/setValue loop the 1.0.1 kernel ran.',
  );
}

Map<String, Object?> _scale(
  int entities,
  int stride,
  int samples,
  int batchMs,
  int warmMs,
) {
  final column = FloatColumn(stride: stride, initialCapacity: entities);
  final accessor = FloatColumn(stride: stride, initialCapacity: entities);
  for (var i = 0; i < entities; i++) {
    column.addBlank();
    accessor.addBlank();
    for (var lane = 0; lane < stride; lane++) {
      column.setValue(i, lane, (i + lane + 1) * 0.1);
      accessor.setValue(i, lane, (i + lane + 1) * 0.1);
    }
  }
  final before = _snapshot(column);
  scalePositionsSimd(column, 1.1);
  for (var i = 0; i < before.length; i++) {
    if (!_closeFloat32(column.data[i], before[i] * 1.1)) {
      throw StateError(
        'scale stride $stride mismatch at float $i: '
        '${column.data[i]} != ${before[i] * 1.1}',
      );
    }
  }
  _restore(column, before);

  final library = _time(samples, batchMs, warmMs, 2, () {
    scalePositionsSimd(column, 1.1);
    scalePositionsSimd(column, 1 / 1.1);
  });
  final scalar = _time(samples, batchMs, warmMs, 2, () {
    _accessorScale(accessor, 1.1);
    _accessorScale(accessor, 1 / 1.1);
  });
  return _metric(
    'scale_stride${stride}_us',
    entities,
    library,
    scalar,
    'Layout measurement. The scalar twin is a getValue/setValue loop.',
  );
}

Map<String, Object?> _add(int entities, int samples, int batchMs, int warmMs) {
  final a = _filled2(entities, (i) => (i * 0.01, -i * 0.02));
  final b = _filled2(entities, (i) => (0.5, 1.5));
  final result = _filled2(entities, (_) => (0, 0));
  final aAccessor = _filled2(entities, (i) => (i * 0.01, -i * 0.02));
  final bAccessor = _filled2(entities, (i) => (0.5, 1.5));
  final resultAccessor = _filled2(entities, (_) => (0, 0));
  SimdUtils.addColumnsSimd(a, b, result);
  _accessorAdd(aAccessor, bAccessor, resultAccessor);
  _expectFloats(result, _snapshot(resultAccessor));

  final library = _time(samples, batchMs, warmMs, 1, () {
    SimdUtils.addColumnsSimd(a, b, result);
  });
  final scalar = _time(samples, batchMs, warmMs, 1, () {
    _accessorAdd(aAccessor, bAccessor, resultAccessor);
  });
  return _metric(
    'add_stride2_us',
    entities,
    library,
    scalar,
    'Stride-2 element-wise add into a third column. The scalar twin is a '
        'getValue/setValue loop.',
  );
}

Map<String, Object?> _dot(int entities, int samples, int batchMs, int warmMs) {
  final a = _filled2(entities, (i) => (i * 0.01, 1));
  final b = _filled2(entities, (i) => (0.5, -0.25));
  var consumed = 0.0;

  final library = _time(samples, batchMs, warmMs, 1, () {
    consumed += SimdUtils.dotProductSimd(a, b).getValue(0, 0);
  });
  final scalar = _time(samples, batchMs, warmMs, 1, () {
    consumed += _accessorDot(a, b).getValue(0, 0);
  });
  if (consumed == 0) throw StateError('dot product probe dropped work');
  return _metric(
    'dot_stride2_us',
    entities,
    library,
    scalar,
    'Stride-2 row dot products into a new stride-1 column. The scalar twin is '
        'the getValue/setValue loop the 1.0.1 kernel ran.',
  );
}

Map<String, Object?> _intLessThan(
  int entities,
  int samples,
  int batchMs,
  int warmMs,
) {
  final column = IntColumn(initialCapacity: entities);
  for (var i = 0; i < entities; i++) {
    column.addBlank();
    column.setValue(i, 0, i % 17);
  }
  const limit = 8;
  final scalar = _countScalar(column, limit);
  final vector = _countVector(column, limit);
  if (scalar != vector) {
    throw StateError('int less-than count $vector != scalar $scalar');
  }
  var consumed = 0;
  final vectorTimes = _time(samples, batchMs, warmMs, 1, () {
    consumed += _countVector(column, limit);
  });
  final scalarTimes = _time(samples, batchMs, warmMs, 1, () {
    consumed += _countScalar(column, limit);
  });
  if (consumed == 0) throw StateError('int less-than probe dropped work');
  return _metric(
    'int_less_than_count_us',
    entities,
    vectorTimes,
    scalarTimes,
    'Int32x4 lessThan plus signMask versus a scalar Int32List loop. '
        'A public integer kernel stays out of the library.',
  );
}

int _countScalar(IntColumn column, int limit) {
  var count = 0;
  for (var i = 0; i < column.length; i++) {
    if (column.getValue(i, 0) < limit) count++;
  }
  return count;
}

int _countVector(IntColumn column, int limit) {
  final bound = Int32x4(limit, limit, limit, limit);
  var count = 0;
  final vectors = column.simdWindow.vectors;
  for (var i = 0; i < vectors.length; i++) {
    count += _pop4(vectors[i].lessThan(bound).signMask);
  }
  final tail = column.length - vectors.length * 4;
  for (var i = column.length - tail; i < column.length; i++) {
    if (column.getValue(i, 0) < limit) count++;
  }
  return count;
}

int _pop4(int mask) =>
    (mask & 1) + ((mask >> 1) & 1) + ((mask >> 2) & 1) + ((mask >> 3) & 1);

// ----------------------------------------------------------------- timing ---

/// Per-call microseconds of [body], which runs [calls] kernel invocations.
///
/// One kernel call is far below timer resolution, and the dart2js `Stopwatch`
/// ticks in milliseconds. Each sample times a batch long enough to make that
/// resolution negligible, then divides. [warmMs] of unrecorded calls run
/// first, so a JIT build measures optimised code.
List<double> _time(
  int samples,
  int batchMs,
  int warmMs,
  int calls,
  void Function() body,
) {
  var warm = 0;
  _sw.start();
  while (_sw.elapsedMicroseconds < warmMs * 1000 || warm < 300) {
    body();
    warm++;
  }
  _sw
    ..stop()
    ..reset();

  var batch = 1;
  while (true) {
    _sw.start();
    _repeat(body, batch);
    _sw.stop();
    if (_sw.elapsedMicroseconds >= batchMs * 1000 || batch >= 1 << 27) break;
    batch *= 2;
    _sw.reset();
  }

  final perCall = <double>[];
  for (var sample = 0; sample < samples; sample++) {
    _sw
      ..reset()
      ..start();
    _repeat(body, batch);
    _sw.stop();
    perCall.add(_sw.elapsedMicroseconds / (batch * calls));
  }
  return perCall;
}

void _repeat(void Function() body, int count) {
  for (var i = 0; i < count; i++) {
    body();
  }
}

Map<String, Object?> _metric(
  String name,
  int entities,
  List<double> library,
  List<double> scalar,
  String notes,
) {
  final median = _median(library);
  final scalarMedian = _median(scalar);
  return {
    'name': name,
    'entities': entities,
    'value': median,
    'unit': 'us',
    'samples': library,
    'scalarMedianUs': scalarMedian,
    'speedup': median == 0 ? null : scalarMedian / median,
    'notes': notes,
  };
}

// ---------------------------------------------------------- scalar twins ---

/// The loops the stride-2 kernels ran in 1.0.1: double math through
/// getValue and setValue.

void _accessorIntegrate(FloatColumn position, FloatColumn velocity, double dt) {
  for (var i = 0; i < position.length; i++) {
    position.setValue(
      i,
      0,
      position.getValue(i, 0) + velocity.getValue(i, 0) * dt,
    );
    position.setValue(
      i,
      1,
      position.getValue(i, 1) + velocity.getValue(i, 1) * dt,
    );
  }
}

void _accessorNormalize(FloatColumn column) {
  for (var i = 0; i < column.length; i++) {
    final x = column.getValue(i, 0);
    final y = column.getValue(i, 1);
    final magnitude = math.sqrt(x * x + y * y);
    if (magnitude > 0) {
      column.setValue(i, 0, x / magnitude);
      column.setValue(i, 1, y / magnitude);
    }
  }
}

void _accessorDistance(FloatColumn points, Float32x4 target, FloatColumn out) {
  for (var i = 0; i < points.length; i++) {
    final dx = points.getValue(i, 0) - target.x;
    final dy = points.getValue(i, 1) - target.y;
    out.setValue(i, 0, math.sqrt(dx * dx + dy * dy));
  }
}

void _accessorScale(FloatColumn column, double factor) {
  for (var i = 0; i < column.length; i++) {
    for (var lane = 0; lane < column.stride; lane++) {
      column.setValue(i, lane, column.getValue(i, lane) * factor);
    }
  }
}

void _accessorAdd(FloatColumn a, FloatColumn b, FloatColumn result) {
  for (var i = 0; i < a.length; i++) {
    for (var lane = 0; lane < a.stride; lane++) {
      result.setValue(i, lane, a.getValue(i, lane) + b.getValue(i, lane));
    }
  }
}

FloatColumn _accessorDot(FloatColumn a, FloatColumn b) {
  final result = FloatColumn(stride: 1, initialCapacity: a.length);
  for (var i = 0; i < a.length; i++) {
    result.addBlank();
  }
  for (var i = 0; i < a.length; i++) {
    var sum = 0.0;
    for (var lane = 0; lane < a.stride; lane++) {
      sum += a.getValue(i, lane) * b.getValue(i, lane);
    }
    result.setValue(i, 0, sum);
  }
  return result;
}

// ---------------------------------------------------------------- helpers ---

FloatColumn _filled2(int entities, (double, double) Function(int i) at) {
  final column = FloatColumn(stride: 2, initialCapacity: entities);
  for (var i = 0; i < entities; i++) {
    column.addBlank();
    final (x, y) = at(i);
    column.setValue(i, 0, x);
    column.setValue(i, 1, y);
  }
  return column;
}

Float32List _snapshot(FloatColumn column) =>
    Float32List.fromList(column.data.sublist(0, column.length * column.stride));

void _restore(FloatColumn column, Float32List saved) {
  column.data.setRange(0, saved.length, saved);
}

void _expectFloats(FloatColumn column, Float32List expected) {
  final live = column.length * column.stride;
  if (live != expected.length) {
    throw StateError('shape ${expected.length} != $live');
  }
  for (var i = 0; i < live; i++) {
    final actual = column.data[i];
    final want = expected[i];
    if (_closeFloat32(actual, want)) continue;
    throw StateError('float $i $actual != $want');
  }
}

/// Float32 kernels round where the scalar twin uses [double].
///
/// Eight float32 ulps covers `Float32x4.sqrt` against `math.sqrt`. An
/// off-by-one lane is much larger than that at every benchmark size.
bool _closeFloat32(double actual, double expected) {
  if (actual.isNaN && expected.isNaN) return true;
  final diff = (actual - expected).abs();
  final mag = actual.abs() > expected.abs() ? actual.abs() : expected.abs();
  final ulps = mag * (8 / 8388608);
  return diff <= (ulps > 1e-6 ? ulps : 1e-6);
}

double _median(List<double> values) {
  final sorted = [...values]..sort();
  final middle = sorted.length ~/ 2;
  if (sorted.length.isOdd) return sorted[middle];
  return (sorted[middle - 1] + sorted[middle]) / 2;
}

int _intArg(List<String> args, String prefix, int fallback) {
  final raw = _stringArg(args, prefix);
  if (raw == null) return fallback;
  final parsed = int.tryParse(raw);
  if (parsed == null || parsed < 1) {
    throw ArgumentError('$prefix must be a positive integer');
  }
  return parsed;
}

String? _stringArg(List<String> args, String prefix) {
  for (final arg in args) {
    if (arg.startsWith(prefix)) return arg.substring(prefix.length);
  }
  return null;
}
