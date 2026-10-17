import 'dart:async';

import 'package:ecsly_flutter/ecsly_flutter.dart';
import 'package:flutter/widgets.dart';

import 'visual_language.dart';

class AutomationFixtureResource extends Resource {
  int left = 0, right = 0, delayed = 0;
  Map<String, int> toJson() => {
    'left': left,
    'right': right,
    'delayed': delayed,
  };
}

/// Enabled only by VIEWER_FIXTURES in qualification builds, not ordinary previews.
class AutomationFixture extends StatelessWidget {
  const AutomationFixture({
    required this.world,
    required this.controller,
    super.key,
  });
  final World world;
  final EcsController controller;
  void increment(bool left) {
    controller.runTransaction(
      (w) {
        final r = w.getResource<AutomationFixtureResource>();
        left ? r.left++ : r.right++;
      },
      invalidation: EcsInvalidationBatch.resource<AutomationFixtureResource>(),
    );
    if (left) {
      Timer(
        const Duration(milliseconds: 350),
        () => controller.runTransaction(
          (w) => w.getResource<AutomationFixtureResource>().delayed++,
          invalidation:
              EcsInvalidationBatch.resource<AutomationFixtureResource>(),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      for (final left in [true, false])
        Semantics(
          container: true,
          explicitChildNodes: true,
          label: left ? 'Left panel' : 'Right panel',
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: ViewerButton(
              label: 'Inspect',
              onPressed: () => increment(left),
            ),
          ),
        ),
    ],
  );
}
