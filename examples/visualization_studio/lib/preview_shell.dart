import 'dart:async';

import 'package:ecsly_flutter/ecsly_flutter.dart';
import 'package:flutter/material.dart';

import 'preview_checkpoint.dart';

import 'preview_model.dart';
import 'preview_canvas.dart';
import 'signal_chart.dart';
import 'visualization_frame.dart';
import 'resident_document.dart';
import 'visual_language.dart';
import 'automation_fixture.dart';

/// Shared host: theme, checkpoint, controls and adaptive scene/chart layout.
class PreviewShell extends StatelessWidget {
  const PreviewShell({
    required this.world,
    required this.controller,
    this.checkpoint,
    this.renderScene = true,
    this.viewportBuilder = canvasViewport,
    super.key,
  });
  final World world;
  final EcsController controller;
  final CheckpointHandle? checkpoint;
  final bool renderScene;
  final PreviewViewportBuilder viewportBuilder;
  void change(PreviewSnapshot Function(PreviewSnapshot) transform) =>
      unawaited(controller.runAction(ChangePreview(transform)));
  @override
  Widget build(BuildContext context) => VisualizationFrame(
    child: EcsResourceSelector<PreviewResource, PreviewSnapshot>(
      select: (r) => r.value,
      builder: (context, s) =>
          EcsResourceSelector<DocumentResource, VisualizationDocument>(
            select: (r) => r.value,
            builder: (context, document) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'ECSLY / RESIDENT STUDIO',
                  style: Theme.of(context).textTheme.labelMedium!.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  document.title,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  document.description,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    for (final e in Example.values)
                      ViewerButton(
                        label: switch (e) {
                          Example.graph => 'Dependencies',
                          Example.simulation => 'Oscillators',
                          Example.linked => 'Linked observations',
                        },
                        selected: s.example == e,
                        onPressed: () => change(
                          (old) => old.copyWith(
                            example: e,
                            selected: 0,
                            playing: false,
                          ),
                        ),
                      ),
                    ViewerButton(
                      label: s.dark ? 'Use light theme' : 'Use dark theme',
                      onPressed: () =>
                          change((old) => old.copyWith(dark: !old.dark)),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(switch (s.example) {
                  Example.graph => 'How does source become a readable preview?',
                  Example.simulation =>
                    'How do frequency and phase change motion?',
                  Example.linked =>
                    'Which spatial observation produced this chart value?',
                }, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                LayoutBuilder(
                  builder: (context, c) {
                    final spatial = VisualPanel(
                      child: SizedBox(
                        height: c.maxWidth < 500 ? 280 : 360,
                        child: renderScene
                            ? viewportBuilder(world, controller)
                            : const Center(
                                child: Text('Scene test substitute'),
                              ),
                      ),
                    );
                    if (s.example != Example.linked) return spatial;
                    final chart = VisualPanel(
                      child: SignalChart(
                        selected: s.selected,
                        onSelected: (i) =>
                            change((old) => old.copyWith(selected: i)),
                      ),
                    );
                    return AdaptiveVisualPair(first: spatial, second: chart);
                  },
                ),
                const SizedBox(height: 8),
                Semantics(
                  liveRegion: !s.playing,
                  child: Text(
                    selectionDetail(s, document),
                    key: const ValueKey('selection-detail'),
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
                const SizedBox(height: 12),
                if (s.example == Example.graph)
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      for (var i = 0; i < graphNames.length; i++)
                        ViewerButton(
                          onPressed: () =>
                              change((old) => old.copyWith(selected: i)),
                          selected: i == s.selected,
                          label: document.graphLabels[i],
                        ),
                    ],
                  ),
                if (s.example == Example.simulation) ...[
                  Wrap(
                    spacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      ViewerButton(
                        primary: true,
                        onPressed: () => change(
                          (old) => old.copyWith(
                            playing: !old.playing,
                            time: old.time >= 8 ? 0 : old.time,
                          ),
                        ),
                        label: s.playing ? 'Pause' : 'Play',
                      ),
                      ViewerButton(
                        onPressed: () => change(
                          (old) => old.copyWith(
                            time: (old.time + 1 / 60).clamp(0, 8),
                            playing: false,
                          ),
                        ),
                        label: 'Step 1/60 s',
                      ),
                      for (var i = 0; i < 3; i++)
                        ViewerButton(
                          onPressed: () =>
                              change((old) => old.copyWith(selected: i)),
                          label: 'Oscillator ${i + 1}',
                        ),
                    ],
                  ),
                  _slider(
                    context,
                    'Time',
                    '${s.time.toStringAsFixed(2)} s',
                    s.time,
                    0,
                    8,
                    (v) =>
                        change((old) => old.copyWith(time: v, playing: false)),
                  ),
                  _slider(
                    context,
                    'Frequency',
                    '${s.frequency.toStringAsFixed(2)} Hz',
                    s.frequency,
                    0.5,
                    2,
                    (v) => change((old) => old.copyWith(frequency: v)),
                  ),
                ],
                if (s.example == Example.linked)
                  _slider(
                    context,
                    'Observation',
                    '${s.selected}',
                    s.selected.toDouble(),
                    0,
                    32,
                    (v) => change((old) => old.copyWith(selected: v.round())),
                    divisions: 32,
                  ),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    ViewerButton(
                      onPressed: () => change(
                        (old) =>
                            old.copyWith(yaw: -3.06, pitch: 0.18, distance: 8),
                      ),
                      label: 'Frame scene',
                    ),
                    ViewerButton(
                      onPressed: () => change(
                        (old) => old.copyWith(
                          distance: (old.distance * 0.85).clamp(6, 24),
                        ),
                      ),
                      label: 'Zoom in',
                    ),
                    ViewerButton(
                      onPressed: () => change(
                        (old) => old.copyWith(
                          distance: (old.distance / 0.85).clamp(6, 24),
                        ),
                      ),
                      label: 'Zoom out',
                    ),
                    ViewerButton(
                      onPressed: checkpoint == null
                          ? null
                          : () async {
                              bool success;
                              try {
                                success = await checkpoint!.save(s.encode());
                              } catch (_) {
                                success = false;
                              }
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    success
                                        ? 'Checkpoint saved'
                                        : 'Checkpoint could not be saved',
                                  ),
                                ),
                              );
                            },
                      label: 'Save checkpoint',
                    ),
                    ViewerButton(
                      onPressed: checkpoint == null
                          ? null
                          : () async {
                              try {
                                final saved = await checkpoint!.load();
                                if (!context.mounted || !checkpoint!.active) {
                                  return;
                                }
                                if (saved == null) {
                                  throw const FormatException(
                                    'No saved checkpoint',
                                  );
                                }
                                final restored = PreviewSnapshot.decode(saved);
                                change((_) => restored);
                              } catch (error) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('Restore failed: $error'),
                                    ),
                                  );
                                }
                              }
                            },
                      label: 'Restore checkpoint',
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  '${document.id} / revision ${document.revision} · resident recipe',
                  style: Theme.of(context).textTheme.labelMedium!.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                if (const bool.fromEnvironment('VIEWER_FIXTURES'))
                  AutomationFixture(world: world, controller: controller),
              ],
            ),
          ),
    ),
  );
  Widget _slider(
    BuildContext context,
    String label,
    String value,
    double current,
    double min,
    double max,
    ValueChanged<double> onChanged, {
    int? divisions,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('$label · $value', style: Theme.of(context).textTheme.labelLarge),
      Semantics(
        label: '$label control',
        container: true,
        explicitChildNodes: true,
        child: Slider(
          value: current,
          min: min,
          max: max,
          divisions: divisions,
          label: label,
          semanticFormatterCallback: (_) => '$label $value',
          onChanged: onChanged,
        ),
      ),
    ],
  );
}
