import 'dart:math' as math;

import 'package:ecsly_flutter/ecsly_flutter.dart';

const omega = 2 * math.pi;
const fixedDt = 1 / 60;
const lastStep = 240;

class Observation extends Component {
  const Observation(this.time, this.displacement, this.velocity);
  final double time, displacement, velocity;
  double get energy =>
      (velocity * velocity + omega * omega * displacement * displacement) / 2;
}

/// Exact solution of the unit-mass ODE, evaluated on a fixed-step clock.
Observation observe(double time, double damping) {
  if (damping < 1) {
    final a = damping * omega;
    final b = omega * math.sqrt(1 - damping * damping);
    final envelope = math.exp(-a * time);
    return Observation(
      time,
      envelope * (math.cos(b * time) + a / b * math.sin(b * time)),
      -envelope * omega * omega / b * math.sin(b * time),
    );
  }
  if (damping == 1) {
    final envelope = math.exp(-omega * time);
    return Observation(
      time,
      envelope * (1 + omega * time),
      -omega * omega * time * envelope,
    );
  }
  final root = math.sqrt(damping * damping - 1);
  final r1 = -omega * (damping - root);
  final r2 = -omega * (damping + root);
  final a = -r2 / (r1 - r2);
  final b = r1 / (r1 - r2);
  return Observation(
    time,
    a * math.exp(r1 * time) + b * math.exp(r2 * time),
    a * r1 * math.exp(r1 * time) + b * r2 * math.exp(r2 * time),
  );
}

class OscillatorState {
  OscillatorState({this.damping = .3, this.step = 0, this.selectedIndex = 0});
  final double damping;
  final int step, selectedIndex;
  double get time => step * fixedDt;
  Observation get current => observe(time, damping);
  Map<String, Object> toJson() => {
    'time': time,
    'damping': damping,
    'displacement': current.displacement,
    'velocity': current.velocity,
    'energy': current.energy,
    'selectedIndex': selectedIndex,
    'plotSelection': {'time': selectedIndex, 'phase': selectedIndex},
  };
}

class OscillatorResource extends Resource {
  OscillatorResource() : value = OscillatorState();
  OscillatorState value;
  final trajectories = <double, List<Observation>>{};
  List<Observation> get samples => trajectories[value.damping]!;
}

World createOscillatorWorld() {
  final resource = OscillatorResource();
  final world = World()
    ..components.registerObjectComponent<Observation>()
    ..upsertResource(resource);
  for (final damping in [0.0, .3, 1.2]) {
    final samples = List<Observation>.unmodifiable(
      List.generate(lastStep + 1, (i) => observe(i * fixedDt, damping)),
    );
    resource.trajectories[damping] = samples;
    for (final sample in samples) {
      world.spawnComponents([sample]);
    }
  }
  world.flush();
  return world;
}

enum Operation { step, reset, preset, next, select }

class OscillatorAction extends EcsAction<void> {
  const OscillatorAction(this.operation, {this.damping, this.index});
  final Operation operation;
  final double? damping;
  final int? index;
  @override
  void run(EcsActionContext context) {
    context.mutateResource<OscillatorResource>((resource) {
      final s = resource.value;
      resource.value = switch (operation) {
        Operation.step => OscillatorState(
          damping: s.damping,
          step: math.min(lastStep, s.step + 1),
          selectedIndex: s.selectedIndex,
        ),
        Operation.reset => OscillatorState(damping: s.damping),
        Operation.preset => OscillatorState(damping: damping!),
        Operation.next => OscillatorState(
          damping: s.damping,
          step: s.step,
          selectedIndex: (s.selectedIndex + 1) % (lastStep + 1),
        ),
        Operation.select => OscillatorState(
          damping: s.damping,
          step: s.step,
          selectedIndex: index!.clamp(0, lastStep),
        ),
      };
    });
  }
}
