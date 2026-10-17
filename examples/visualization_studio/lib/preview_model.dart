import 'dart:convert';
import 'dart:math' as math;

import 'package:ecsly_flutter/ecsly_flutter.dart';

import 'resident_document.dart';
import 'automation_fixture.dart';
import 'startup_trace.dart';

enum Example { graph, simulation, linked }

const graphNames = ['Source', 'Parse', 'Layout', 'Scene', 'Labels', 'Preview'];
const graphPositions = <List<double>>[
  [-3, 0, 0],
  [-1.5, 0, 0],
  [0, 0.8, 0],
  [1.5, 0.8, 0],
  [1.5, -0.8, 0],
  [3, 0, 0],
];
const graphEdges = [(0, 1), (1, 2), (2, 3), (2, 4), (3, 5), (4, 5)];

/// Serializable user choices, separate from renderer objects and entity ids.
class PreviewSnapshot {
  const PreviewSnapshot({
    this.example = Example.graph,
    this.selected = 0,
    this.time = 0,
    this.frequency = 1,
    this.playing = false,
    this.dark = false,
    this.yaw = -3.06,
    this.pitch = 0.18,
    this.distance = 8,
  });
  final Example example;
  final int selected;
  final double time, frequency, yaw, pitch, distance;
  final bool playing, dark;

  PreviewSnapshot copyWith({
    Example? example,
    int? selected,
    double? time,
    double? frequency,
    bool? playing,
    bool? dark,
    double? yaw,
    double? pitch,
    double? distance,
  }) => PreviewSnapshot(
    example: example ?? this.example,
    selected: selected ?? this.selected,
    time: time ?? this.time,
    frequency: frequency ?? this.frequency,
    playing: playing ?? this.playing,
    dark: dark ?? this.dark,
    yaw: yaw ?? this.yaw,
    pitch: pitch ?? this.pitch,
    distance: distance ?? this.distance,
  );

  String encode() => jsonEncode({
    'version': 1,
    'example': example.name,
    'selected': selected,
    'time': time,
    'frequency': frequency,
    'playing': playing,
    'dark': dark,
    'yaw': yaw,
    'pitch': pitch,
    'distance': distance,
  });

  factory PreviewSnapshot.decode(String source) {
    final json = jsonDecode(source) as Map<String, dynamic>;
    if (json['version'] != 1) {
      throw const FormatException('Unsupported snapshot');
    }
    double number(String key, double min, double max) {
      final n = (json[key] as num).toDouble();
      if (!n.isFinite || n < min || n > max) {
        throw FormatException('Invalid $key');
      }
      return n;
    }

    final example = Example.values.byName(json['example'] as String);
    final selected = json['selected'] as int;
    final maxSelection = switch (example) {
      Example.graph => 5,
      Example.simulation => 2,
      Example.linked => 32,
    };
    if (selected < 0 || selected > maxSelection) {
      throw const FormatException('Invalid selection');
    }
    return PreviewSnapshot(
      example: example,
      selected: selected,
      time: number('time', 0, 8),
      frequency: number('frequency', 0.5, 2),
      dark: json['dark'] as bool,
      // Reload is deliberately paused so the saved observation is inspectable.
      playing: false,
      yaw: number('yaw', -1000, 1000),
      pitch: number('pitch', -1.3, 1.3),
      distance: number('distance', 6, 24),
    );
  }
}

class PreviewResource extends Resource {
  PreviewResource(this.value);
  PreviewSnapshot value;
}

class PreviewMark extends Component {
  const PreviewMark(this.example, this.index, this.label);
  final Example example;
  final int index;
  final String label;
}

class PreviewEdge extends Component {
  const PreviewEdge(this.from, this.to);
  final int from, to;
}

double displacement(double time, double frequency, [int particle = 0]) =>
    math.sin(2 * math.pi * frequency * time + particle * math.pi / 3);

List<double> markPosition(Example example, int index, PreviewSnapshot s) =>
    switch (example) {
      Example.graph => graphPositions[index],
      Example.simulation => [
        -2.4 + index * 2.4,
        1.5 * displacement(s.time, s.frequency, index),
        0,
      ],
      Example.linked => [
        -3.2 + index * 0.2,
        1.3 * displacement(index / 8, 1),
        0.7 * math.cos(index / 8 * 2 * math.pi),
      ],
    };

String selectionDetail(
  PreviewSnapshot s, [
  VisualizationDocument? document,
]) => switch (s.example) {
  Example.graph =>
    '${(document?.graphLabels ?? graphNames)[s.selected]} · ${graphEdges.where((e) => e.$2 == s.selected).length} dependencies',
  Example.simulation =>
    'Oscillator ${s.selected + 1} · ${displacement(s.time, s.frequency, s.selected).toStringAsFixed(2)} m',
  Example.linked =>
    'Sample ${s.selected} · t = ${(s.selected / 8).toStringAsFixed(3)} s · ${displacement(s.selected / 8, 1).toStringAsFixed(2)} m',
};

World createPreviewWorld([PreviewSnapshot snapshot = const PreviewSnapshot()]) {
  final world = World()
    ..upsertResource(StartupTrace())
    ..components.registerObjectComponent<PreviewMark>()
    ..components.registerObjectComponent<PreviewEdge>()
    ..upsertResource(PreviewResource(snapshot))
    ..upsertResource(AutomationFixtureResource())
    ..upsertResource(DocumentResource(defaultDocument));
  for (var i = 0; i < graphNames.length; i++) {
    world.spawnComponents([PreviewMark(Example.graph, i, graphNames[i])]);
  }
  for (final edge in graphEdges) {
    world.spawnComponents([PreviewEdge(edge.$1, edge.$2)]);
  }
  for (var i = 0; i < 3; i++) {
    world.spawnComponents([
      PreviewMark(Example.simulation, i, 'Oscillator ${i + 1}'),
    ]);
  }
  for (var i = 0; i <= 32; i++) {
    world.spawnComponents([PreviewMark(Example.linked, i, '$i')]);
  }
  world.getOrCreateSchedule(const ScheduleId('preview.tick')).add((w) {
    final r = w.getResource<PreviewResource>();
    if (!r.value.playing || r.value.example != Example.simulation) return;
    final time = r.value.time + w.getResource<DeltaTimeResource>().deltaTime;
    r.value = r.value.copyWith(time: time.clamp(0, 8), playing: time < 8);
  }, name: 'preview.advance');
  world.flush();
  return world;
}

class ChangePreview extends EcsAction<void> {
  const ChangePreview(this.change);
  final PreviewSnapshot Function(PreviewSnapshot) change;
  @override
  void run(EcsActionContext context) =>
      context.mutateResource<PreviewResource>((r) => r.value = change(r.value));
}
