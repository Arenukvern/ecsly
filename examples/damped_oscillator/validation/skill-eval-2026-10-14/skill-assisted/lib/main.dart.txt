import 'dart:async';

import 'package:ecsly_flutter/ecsly_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import 'model.dart';
import 'bridge_stub.dart' if (dart.library.js_interop) 'bridge_web.dart';

const ink = Color(0xff17334a);
const teal = Color(0xff087f8c);
const coral = Color(0xffdc5b43);
const paper = Color(0xfff4f1e9);
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SemanticsBinding.instance.ensureSemantics();
  runApp(const OscillatorApp());
}

class OscillatorApp extends StatefulWidget {
  const OscillatorApp({super.key});
  @override
  State<OscillatorApp> createState() => _OscillatorAppState();
}

class _OscillatorAppState extends State<OscillatorApp> {
  late final world = createOscillatorWorld();
  late final controller = EcsController(world: world);
  @override
  void initState() {
    super.initState();
    installBridge(() => world.getResource<OscillatorResource>().value);
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void act(Operation op, {double? damping, int? index}) => unawaited(
    controller.runAction(OscillatorAction(op, damping: damping, index: index)),
  );
  @override
  Widget build(BuildContext context) => EcsAppScope(
    world: world,
    controller: controller,
    child: MaterialApp(
      title: 'Damped oscillator',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: paper,
        colorScheme: ColorScheme.fromSeed(seedColor: teal, surface: paper),
        textTheme: ThemeData.light().textTheme.apply(
          bodyColor: ink,
          displayColor: ink,
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            minimumSize: const Size(48, 48),
            backgroundColor: ink,
            foregroundColor: Colors.white,
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(48, 48),
            foregroundColor: ink,
            side: const BorderSide(color: ink),
          ),
        ),
      ),
      home: Scaffold(
        body: SafeArea(
          child: EcsResourceSelector<OscillatorResource, OscillatorState>(
            select: (r) => r.value,
            builder: (context, s) {
              final samples = world.getResource<OscillatorResource>().samples;
              final current = s.current;
              final selected = samples[s.selectedIndex];
              return SingleChildScrollView(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1180),
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'MOTION LAB / 01',
                            style: TextStyle(
                              color: teal,
                              letterSpacing: 2.5,
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 14),
                          const Text(
                            'Where does the motion go?',
                            style: TextStyle(
                              fontSize: 34,
                              height: 1.12,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'A damped oscillator loses mechanical energy. Compare a repeating orbit with a shrinking spiral and a slow return to rest.',
                            style: TextStyle(fontSize: 16, height: 1.5),
                          ),
                          const SizedBox(height: 20),
                          Container(
                            padding: const EdgeInsets.all(18),
                            decoration: BoxDecoration(
                              color: ink,
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'x″ + 2ζωx′ + ω²x = 0',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 23,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                const Text(
                                  'ω = 2π rad/s · mass = 1 kg · x₀ = 1 m · v₀ = 0 m/s',
                                  style: TextStyle(
                                    color: Color(0xffc3d8e0),
                                    height: 1.5,
                                  ),
                                ),
                                const SizedBox(height: 14),
                                Wrap(
                                  spacing: 24,
                                  runSpacing: 12,
                                  children: [
                                    metric(
                                      'TIME',
                                      '${s.time.toStringAsFixed(3)} s',
                                    ),
                                    metric(
                                      'DISPLACEMENT',
                                      '${current.displacement.toStringAsFixed(3)} m',
                                    ),
                                    metric(
                                      'VELOCITY',
                                      '${current.velocity.toStringAsFixed(3)} m/s',
                                    ),
                                    metric(
                                      'ENERGY',
                                      '${current.energy.toStringAsFixed(3)} J',
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 20),
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: [
                              for (final preset in [
                                ('Undamped', 0.0),
                                ('Light damping', .3),
                                ('Overdamped', 1.2),
                              ])
                                Semantics(
                                  selected: s.damping == preset.$2,
                                  child: OutlinedButton(
                                    onPressed: () => act(
                                      Operation.preset,
                                      damping: preset.$2,
                                    ),
                                    style: OutlinedButton.styleFrom(
                                      backgroundColor: s.damping == preset.$2
                                          ? const Color(0xffd2e9e7)
                                          : Colors.transparent,
                                    ),
                                    child: Text(preset.$1),
                                  ),
                                ),
                              FilledButton(
                                onPressed: s.step == lastStep
                                    ? null
                                    : () => act(Operation.step),
                                child: const Text('Step 1/60 s'),
                              ),
                              OutlinedButton(
                                onPressed: () => act(Operation.reset),
                                child: const Text('Reset'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Paused · ζ = ${s.damping.toStringAsFixed(1)} · fixed steps stop at 4 s',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 24),
                          LayoutBuilder(
                            builder: (context, constraints) {
                              final plots = [
                                plotPanel(
                                  '01 / Displacement over time',
                                  'Time (s)',
                                  'Displacement (m)',
                                  samples,
                                  s,
                                  false,
                                ),
                                plotPanel(
                                  '02 / Phase portrait',
                                  'Displacement (m)',
                                  'Velocity (m/s)',
                                  samples,
                                  s,
                                  true,
                                ),
                              ];
                              return constraints.maxWidth >= 780
                                  ? Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Expanded(child: plots[0]),
                                        const SizedBox(width: 16),
                                        Expanded(child: plots[1]),
                                      ],
                                    )
                                  : Column(
                                      children: [
                                        plots[0],
                                        const SizedBox(height: 16),
                                        plots[1],
                                      ],
                                    );
                            },
                          ),
                          const SizedBox(height: 18),
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              border: Border.all(color: coral),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Wrap(
                                  spacing: 20,
                                  runSpacing: 10,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    Text(
                                      'Sample ${s.selectedIndex}',
                                      style: const TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.w800,
                                        color: coral,
                                      ),
                                    ),
                                    FilledButton(
                                      onPressed: () => act(Operation.next),
                                      style: FilledButton.styleFrom(
                                        backgroundColor: coral,
                                      ),
                                      child: const Text('Next sample'),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  't = ${selected.time.toStringAsFixed(3)} s · x = ${selected.displacement.toStringAsFixed(3)} m · v = ${selected.velocity.toStringAsFixed(3)} m/s',
                                  style: const TextStyle(height: 1.5),
                                ),
                                const SizedBox(height: 8),
                                const Text(
                                  'Orange marks the same observation in both plots. Tap either curve to inspect a sample; outlined teal marks the current step.',
                                  style: TextStyle(height: 1.5),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 22),
                          Text(
                            s.damping == 0
                                ? 'No damping: energy stays constant, so the phase orbit closes.'
                                : s.damping < 1
                                ? 'Light damping: oscillations continue while energy decays, drawing a spiral toward rest.'
                                : 'Overdamped: the mass returns without crossing equilibrium; strong damping slows its return.',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              height: 1.5,
                            ),
                          ),
                          const SizedBox(height: 20),
                          const Text(
                            'Four-second trajectories · 241 observations · exact ODE solution on a deterministic 1/60 s clock',
                            style: TextStyle(fontSize: 12, height: 1.5),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    ),
  );
  Widget metric(String label, String value) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: const TextStyle(
          color: Color(0xffc3d8e0),
          fontSize: 10,
          letterSpacing: 1.5,
        ),
      ),
      const SizedBox(height: 5),
      Text(
        value,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.w700,
        ),
      ),
    ],
  );
  Widget plotPanel(
    String title,
    String xLabel,
    String yLabel,
    List<Observation> samples,
    OscillatorState state,
    bool phase,
  ) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border.all(color: const Color(0xffd7dfdd)),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
        ),
        const SizedBox(height: 10),
        Text(
          yLabel,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, constraints) => Semantics(
            label: '$title. Selected Sample ${state.selectedIndex}',
            child: GestureDetector(
              onTapDown: (event) {
                final size = Size(constraints.maxWidth, 240);
                var nearest = 0;
                var distance = double.infinity;
                for (var i = 0; i < samples.length; i++) {
                  final delta =
                      (point(samples[i], size, phase) - event.localPosition)
                          .distanceSquared;
                  if (delta < distance) {
                    distance = delta;
                    nearest = i;
                  }
                }
                act(Operation.select, index: nearest);
              },
              child: CustomPaint(
                size: Size(constraints.maxWidth, 240),
                painter: PlotPainter(samples, state, phase),
              ),
            ),
          ),
        ),
        Center(
          child: Text(
            xLabel,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );
}

Offset point(Observation sample, Size size, bool phase) {
  final x = phase ? (sample.displacement + 1.1) / 2.2 : sample.time / 4;
  final y = phase
      ? (sample.velocity + 7) / 14
      : (sample.displacement + 1.1) / 2.2;
  return Offset(40 + x * (size.width - 52), 12 + (1 - y) * (size.height - 40));
}

class PlotPainter extends CustomPainter {
  PlotPainter(this.samples, this.state, this.phase);
  final List<Observation> samples;
  final OscillatorState state;
  final bool phase;
  void text(Canvas canvas, String value, Offset at) {
    final p = TextPainter(
      text: TextSpan(
        text: value,
        style: const TextStyle(fontSize: 11, color: ink),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    p.paint(canvas, at);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = const Color(0xffe2e9e6)
      ..strokeWidth = 1;
    for (var i = 0; i <= 4; i++) {
      final x = 40 + (size.width - 52) * i / 4;
      final y = 12 + (size.height - 40) * i / 4;
      canvas.drawLine(Offset(x, 12), Offset(x, size.height - 28), grid);
      canvas.drawLine(Offset(40, y), Offset(size.width - 12, y), grid);
      text(
        canvas,
        phase ? (-1 + i * .5).toStringAsFixed(1) : '$i',
        Offset(x - 9, size.height - 22),
      );
      text(
        canvas,
        phase
            ? (7 - i * 3.5).toStringAsFixed(1)
            : (1.1 - i * .55).toStringAsFixed(1),
        Offset(0, y - 6),
      );
    }
    // Phase x ticks use the same fixed +/-1.1 m scale as the actual curve.
    if (phase) {
      final cover = Paint()..color = Colors.white;
      canvas.drawRect(
        Rect.fromLTWH(0, size.height - 25, size.width, 25),
        cover,
      );
      for (var i = 0; i <= 4; i++) {
        text(
          canvas,
          (-1.1 + i * .55).toStringAsFixed(2),
          Offset(40 + (size.width - 52) * i / 4 - 13, size.height - 22),
        );
      }
    }
    final path = Path();
    for (var i = 0; i < samples.length; i++) {
      final p = point(samples[i], size, phase);
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = teal
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4,
    );
    final live = point(state.current, size, phase);
    canvas.drawCircle(
      live,
      7,
      Paint()
        ..color = teal
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    final selected = point(samples[state.selectedIndex], size, phase);
    canvas.drawCircle(selected, 6, Paint()..color = coral);
    canvas.drawCircle(selected, 2, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(PlotPainter old) =>
      old.state != state || old.samples != samples;
}
