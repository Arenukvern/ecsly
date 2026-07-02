import 'dart:convert';
import 'dart:io';

import 'package:ecsly_flutter/ecsly_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('writes selector invalidation profile artifact', (
    final tester,
  ) async {
    final scenarios = <_SelectorProfileScenario>[];

    scenarios.add(await _scopedResourceUnrelatedComponent(tester));
    scenarios.add(await _scopedResourceMatch(tester));
    scenarios.add(await _explicitResourceUnrelatedComponent(tester));
    scenarios.add(await _scopedComponentOtherEntity(tester));
    scenarios.add(await _scopedComponentWhereMatch(tester));
    scenarios.add(await _scopedWorldUnrelatedComponent(tester));
    scenarios.add(await _scopedWorldResourceMatch(tester));
    scenarios.add(await _broadUntrackedResource(tester));

    final artifact = <String, Object?>{
      'schemaVersion': 1,
      'package': 'ecsly_flutter',
      'generatedAt': DateTime.now().toUtc().toIso8601String(),
      'command':
          'flutter test test/selector_invalidation_profile_test.dart '
          '--reporter expanded',
      'environment': <String, Object?>{
        'dartVersion': Platform.version,
        'executable': Platform.executable,
        'flutterVersion': _flutterVersion(),
        'gitCommit': _gitOutput(['rev-parse', '--short=12', 'HEAD']),
        'gitDirty': _gitOutput(['status', '--porcelain']).isNotEmpty,
      },
      'scenarios': [for (final scenario in scenarios) scenario.toJson()],
    };

    final file = File('build/reports/selector_invalidation_profile.v1.json');
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(artifact),
    );
  });
}

Future<_SelectorProfileScenario> _scopedResourceUnrelatedComponent(
  final WidgetTester tester,
) async {
  final world = _profileWorld()..upsertResource(_CounterResource());
  final entity = world.entities.create();
  world.upsertComponent(entity, const _TitleComponent('draft'));
  world.flush();
  final controller = EcsController(world: world);
  final counters = _SelectorCounters();
  var notifications = 0;
  controller.addListener(() => notifications += 1);

  await tester.pumpWidget(
    _host(
      EcsScope(
        world: world,
        controller: controller,
        child: EcsResourceSelector<_CounterResource, int>(
          select: (final resource) {
            counters.selectorCalls += 1;
            return resource.count;
          },
          builder: (final context, final count) {
            counters.builderCalls += 1;
            return Text('count: $count');
          },
        ),
      ),
    ),
  );
  final baseline = counters.snapshot();

  controller.runTransaction(
    (final world) {
      world.upsertComponent(entity, const _TitleComponent('saved'));
    },
    invalidation: EcsInvalidationBatch.component<_TitleComponent>(
      entity: entity,
    ),
  );
  await tester.pump();

  expect(counters.selectorCalls, baseline.selectorCalls);
  expect(counters.builderCalls, baseline.builderCalls);
  expect(notifications, 1);
  await tester.pumpWidget(const SizedBox.shrink());

  return _SelectorProfileScenario(
    scenario: 'scoped_resource_unrelated_component',
    subscriptionMode: 'scopedAspect',
    selectorKind: 'resource',
    invalidationKind: 'component',
    controllerNotificationCount: notifications,
    initialSelectorCallCount: baseline.selectorCalls,
    finalSelectorCallCount: counters.selectorCalls,
    initialWidgetBuildCount: baseline.builderCalls,
    finalWidgetBuildCount: counters.builderCalls,
    expectedInvalidated: false,
    selectedValueChanged: false,
    lastInvalidation: _invalidationJson(controller.lastInvalidation),
  );
}

Future<_SelectorProfileScenario> _scopedResourceMatch(
  final WidgetTester tester,
) async {
  final world = _profileWorld()..upsertResource(_CounterResource());
  world.flush();
  final controller = EcsController(world: world);
  final counters = _SelectorCounters();
  var notifications = 0;
  controller.addListener(() => notifications += 1);

  await tester.pumpWidget(
    _host(
      EcsScope(
        world: world,
        controller: controller,
        child: EcsResourceSelector<_CounterResource, int>(
          select: (final resource) {
            counters.selectorCalls += 1;
            return resource.count;
          },
          builder: (final context, final count) {
            counters.builderCalls += 1;
            return Text('count: $count');
          },
        ),
      ),
    ),
  );
  final baseline = counters.snapshot();

  controller.runTransaction((final world) {
    world.getResource<_CounterResource>().count = 1;
  }, invalidation: EcsInvalidationBatch.resource<_CounterResource>());
  await tester.pump();

  expect(counters.selectorCalls, baseline.selectorCalls + 1);
  expect(counters.builderCalls, baseline.builderCalls + 1);
  expect(notifications, 1);
  await tester.pumpWidget(const SizedBox.shrink());

  return _SelectorProfileScenario(
    scenario: 'scoped_resource_match',
    subscriptionMode: 'scopedAspect',
    selectorKind: 'resource',
    invalidationKind: 'resource',
    controllerNotificationCount: notifications,
    initialSelectorCallCount: baseline.selectorCalls,
    finalSelectorCallCount: counters.selectorCalls,
    initialWidgetBuildCount: baseline.builderCalls,
    finalWidgetBuildCount: counters.builderCalls,
    expectedInvalidated: true,
    selectedValueChanged: true,
    lastInvalidation: _invalidationJson(controller.lastInvalidation),
  );
}

Future<_SelectorProfileScenario> _explicitResourceUnrelatedComponent(
  final WidgetTester tester,
) async {
  final world = _profileWorld()..upsertResource(_CounterResource());
  final entity = world.entities.create();
  world.upsertComponent(entity, const _TitleComponent('draft'));
  world.flush();
  final controller = EcsController(world: world);
  final counters = _SelectorCounters();
  var notifications = 0;
  controller.addListener(() => notifications += 1);

  await tester.pumpWidget(
    _host(
      EcsResourceSelector<_CounterResource, int>(
        world: world,
        controller: controller,
        select: (final resource) {
          counters.selectorCalls += 1;
          return resource.count;
        },
        builder: (final context, final count) {
          counters.builderCalls += 1;
          return Text('count: $count');
        },
      ),
    ),
  );
  final baseline = counters.snapshot();

  controller.runTransaction(
    (final world) {
      world.upsertComponent(entity, const _TitleComponent('saved'));
    },
    invalidation: EcsInvalidationBatch.component<_TitleComponent>(
      entity: entity,
    ),
  );
  await tester.pump();

  expect(counters.selectorCalls, baseline.selectorCalls);
  expect(counters.builderCalls, baseline.builderCalls);
  expect(notifications, 1);
  await tester.pumpWidget(const SizedBox.shrink());

  return _SelectorProfileScenario(
    scenario: 'explicit_resource_unrelated_component',
    subscriptionMode: 'explicitController',
    selectorKind: 'resource',
    invalidationKind: 'component',
    controllerNotificationCount: notifications,
    initialSelectorCallCount: baseline.selectorCalls,
    finalSelectorCallCount: counters.selectorCalls,
    initialWidgetBuildCount: baseline.builderCalls,
    finalWidgetBuildCount: counters.builderCalls,
    expectedInvalidated: false,
    selectedValueChanged: false,
    lastInvalidation: _invalidationJson(controller.lastInvalidation),
  );
}

Future<_SelectorProfileScenario> _scopedComponentOtherEntity(
  final WidgetTester tester,
) async {
  final world = _profileWorld();
  final first = world.entities.create();
  final second = world.entities.create();
  world.upsertComponent(first, const _TitleComponent('first'));
  world.upsertComponent(second, const _TitleComponent('second'));
  world.flush();
  final controller = EcsController(world: world);
  final counters = _SelectorCounters();
  var notifications = 0;
  controller.addListener(() => notifications += 1);

  await tester.pumpWidget(
    _host(
      EcsScope(
        world: world,
        controller: controller,
        child: EcsComponentSelector<_TitleComponent, String>(
          entity: first,
          select: (final component) {
            counters.selectorCalls += 1;
            return component.value;
          },
          builder: (final context, final title) {
            counters.builderCalls += 1;
            return Text(title);
          },
        ),
      ),
    ),
  );
  final baseline = counters.snapshot();

  controller.runTransaction(
    (final world) {
      world.upsertComponent(second, const _TitleComponent('changed'));
    },
    invalidation: EcsInvalidationBatch.component<_TitleComponent>(
      entity: second,
    ),
  );
  await tester.pump();

  expect(counters.selectorCalls, baseline.selectorCalls);
  expect(counters.builderCalls, baseline.builderCalls);
  expect(notifications, 1);
  await tester.pumpWidget(const SizedBox.shrink());

  return _SelectorProfileScenario(
    scenario: 'scoped_component_other_entity',
    subscriptionMode: 'scopedAspect',
    selectorKind: 'component',
    invalidationKind: 'component',
    controllerNotificationCount: notifications,
    initialSelectorCallCount: baseline.selectorCalls,
    finalSelectorCallCount: counters.selectorCalls,
    initialWidgetBuildCount: baseline.builderCalls,
    finalWidgetBuildCount: counters.builderCalls,
    expectedInvalidated: false,
    selectedValueChanged: false,
    lastInvalidation: _invalidationJson(controller.lastInvalidation),
  );
}

Future<_SelectorProfileScenario> _scopedComponentWhereMatch(
  final WidgetTester tester,
) async {
  final world = _profileWorld();
  final first = world.entities.create();
  final second = world.entities.create();
  world.upsertComponent(first, const _RecordComponent(id: 'a', title: 'first'));
  world.upsertComponent(
    second,
    const _RecordComponent(id: 'b', title: 'second'),
  );
  world.flush();
  final controller = EcsController(world: world);
  final counters = _SelectorCounters();
  var notifications = 0;
  controller.addListener(() => notifications += 1);

  await tester.pumpWidget(
    _host(
      EcsScope(
        world: world,
        controller: controller,
        child: EcsComponentSelector<_RecordComponent, String>(
          where: (final entity, final component) => component.id == 'b',
          select: (final component) {
            counters.selectorCalls += 1;
            return component.title;
          },
          builder: (final context, final title) {
            counters.builderCalls += 1;
            return Text(title);
          },
        ),
      ),
    ),
  );
  final baseline = counters.snapshot();

  controller.runTransaction(
    (final world) {
      world.upsertComponent(
        second,
        const _RecordComponent(id: 'b', title: 'saved'),
      );
    },
    invalidation: EcsInvalidationBatch.component<_RecordComponent>(
      entity: second,
    ),
  );
  await tester.pump();

  expect(counters.selectorCalls, baseline.selectorCalls + 1);
  expect(counters.builderCalls, baseline.builderCalls + 1);
  expect(notifications, 1);
  await tester.pumpWidget(const SizedBox.shrink());

  return _SelectorProfileScenario(
    scenario: 'scoped_component_where_match',
    subscriptionMode: 'scopedAspect',
    selectorKind: 'component',
    invalidationKind: 'component',
    controllerNotificationCount: notifications,
    initialSelectorCallCount: baseline.selectorCalls,
    finalSelectorCallCount: counters.selectorCalls,
    initialWidgetBuildCount: baseline.builderCalls,
    finalWidgetBuildCount: counters.builderCalls,
    expectedInvalidated: true,
    selectedValueChanged: true,
    lastInvalidation: _invalidationJson(controller.lastInvalidation),
  );
}

Future<_SelectorProfileScenario> _scopedWorldUnrelatedComponent(
  final WidgetTester tester,
) async {
  final world = _profileWorld()..upsertResource(_CounterResource());
  final entity = world.entities.create();
  world.upsertComponent(entity, const _TitleComponent('draft'));
  world.flush();
  final controller = EcsController(world: world);
  final counters = _SelectorCounters();
  var notifications = 0;
  controller.addListener(() => notifications += 1);

  await tester.pumpWidget(
    _host(
      EcsScope(
        world: world,
        controller: controller,
        child: EcsWorldSelector<int>(
          dependencies: const EcsWorldSelectorDependencies(
            resourceTypes: [_CounterResource],
          ),
          select: (final world) {
            counters.selectorCalls += 1;
            return world.getResource<_CounterResource>().count;
          },
          builder: (final context, final value) {
            counters.builderCalls += 1;
            return Text('count: $value');
          },
        ),
      ),
    ),
  );
  final baseline = counters.snapshot();

  controller.runTransaction(
    (final world) {
      world.upsertComponent(entity, const _TitleComponent('saved'));
    },
    invalidation: EcsInvalidationBatch.component<_TitleComponent>(
      entity: entity,
    ),
  );
  await tester.pump();

  expect(counters.selectorCalls, baseline.selectorCalls);
  expect(counters.builderCalls, baseline.builderCalls);
  expect(notifications, 1);
  await tester.pumpWidget(const SizedBox.shrink());

  return _SelectorProfileScenario(
    scenario: 'scoped_world_unrelated_component',
    subscriptionMode: 'scopedAspect',
    selectorKind: 'world',
    invalidationKind: 'component',
    controllerNotificationCount: notifications,
    initialSelectorCallCount: baseline.selectorCalls,
    finalSelectorCallCount: counters.selectorCalls,
    initialWidgetBuildCount: baseline.builderCalls,
    finalWidgetBuildCount: counters.builderCalls,
    expectedInvalidated: false,
    selectedValueChanged: false,
    lastInvalidation: _invalidationJson(controller.lastInvalidation),
  );
}

Future<_SelectorProfileScenario> _scopedWorldResourceMatch(
  final WidgetTester tester,
) async {
  final world = _profileWorld()..upsertResource(_CounterResource());
  world.flush();
  final controller = EcsController(world: world);
  final counters = _SelectorCounters();
  var notifications = 0;
  controller.addListener(() => notifications += 1);

  await tester.pumpWidget(
    _host(
      EcsScope(
        world: world,
        controller: controller,
        child: EcsWorldSelector<int>(
          dependencies: const EcsWorldSelectorDependencies(
            resourceTypes: [_CounterResource],
          ),
          select: (final world) {
            counters.selectorCalls += 1;
            return world.getResource<_CounterResource>().count;
          },
          builder: (final context, final value) {
            counters.builderCalls += 1;
            return Text('count: $value');
          },
        ),
      ),
    ),
  );
  final baseline = counters.snapshot();

  controller.runTransaction((final world) {
    world.getResource<_CounterResource>().count = 1;
  }, invalidation: EcsInvalidationBatch.resource<_CounterResource>());
  await tester.pump();

  expect(counters.selectorCalls, baseline.selectorCalls + 1);
  expect(counters.builderCalls, baseline.builderCalls + 1);
  expect(notifications, 1);
  await tester.pumpWidget(const SizedBox.shrink());

  return _SelectorProfileScenario(
    scenario: 'scoped_world_resource_match',
    subscriptionMode: 'scopedAspect',
    selectorKind: 'world',
    invalidationKind: 'resource',
    controllerNotificationCount: notifications,
    initialSelectorCallCount: baseline.selectorCalls,
    finalSelectorCallCount: counters.selectorCalls,
    initialWidgetBuildCount: baseline.builderCalls,
    finalWidgetBuildCount: counters.builderCalls,
    expectedInvalidated: true,
    selectedValueChanged: true,
    lastInvalidation: _invalidationJson(controller.lastInvalidation),
  );
}

Future<_SelectorProfileScenario> _broadUntrackedResource(
  final WidgetTester tester,
) async {
  final world = _profileWorld()..upsertResource(_CounterResource());
  world.flush();
  final controller = EcsController(world: world);
  final counters = _SelectorCounters();
  var notifications = 0;
  controller.addListener(() => notifications += 1);

  await tester.pumpWidget(
    _host(
      EcsScope(
        world: world,
        controller: controller,
        child: EcsResourceSelector<_CounterResource, int>(
          select: (final resource) {
            counters.selectorCalls += 1;
            return resource.count;
          },
          builder: (final context, final count) {
            counters.builderCalls += 1;
            return Text('count: $count');
          },
        ),
      ),
    ),
  );
  final baseline = counters.snapshot();

  controller.runTransaction((final world) {
    world.getResource<_CounterResource>().count = 1;
  });
  await tester.pump();

  expect(counters.selectorCalls, baseline.selectorCalls + 1);
  expect(counters.builderCalls, baseline.builderCalls + 1);
  expect(notifications, 1);
  await tester.pumpWidget(const SizedBox.shrink());

  return _SelectorProfileScenario(
    scenario: 'broad_untracked_resource',
    subscriptionMode: 'scopedAspect',
    selectorKind: 'resource',
    invalidationKind: 'broad',
    controllerNotificationCount: notifications,
    initialSelectorCallCount: baseline.selectorCalls,
    finalSelectorCallCount: counters.selectorCalls,
    initialWidgetBuildCount: baseline.builderCalls,
    finalWidgetBuildCount: counters.builderCalls,
    expectedInvalidated: true,
    selectedValueChanged: true,
    lastInvalidation: _invalidationJson(controller.lastInvalidation),
  );
}

Widget _host(final Widget child) => MaterialApp(home: child);

World _profileWorld() {
  final world = World()
    ..components.registerObjectComponent<_TitleComponent>()
    ..components.registerObjectComponent<_RecordComponent>();
  return world;
}

Map<String, Object?> _invalidationJson(final EcsInvalidationBatch batch) => {
  'broad': batch.broad,
  'structural': batch.structural,
  'resourceTypes': [for (final type in batch.resourceTypes) '$type'],
  'componentTypes': [for (final type in batch.componentTypes) '$type'],
  'touchedEntityCount': batch.touchedEntities.length,
  'entityDetailOverflow': batch.entityDetailOverflow,
};

String _gitOutput(final List<String> args) {
  final result = Process.runSync('git', args);
  if (result.exitCode != 0) return '';
  return result.stdout.toString().trim();
}

String _flutterVersion() {
  final result = Process.runSync('flutter', ['--version', '--machine']);
  if (result.exitCode != 0) return '';
  try {
    final decoded = jsonDecode(result.stdout.toString());
    if (decoded is! Map<String, Object?>) return '';
    final frameworkVersion = decoded['frameworkVersion'];
    return frameworkVersion is String ? frameworkVersion : '';
  } on FormatException {
    return '';
  }
}

final class _SelectorCounters {
  int selectorCalls = 0;
  int builderCalls = 0;

  _SelectorCounterSnapshot snapshot() => _SelectorCounterSnapshot(
    selectorCalls: selectorCalls,
    builderCalls: builderCalls,
  );
}

final class _SelectorCounterSnapshot {
  const _SelectorCounterSnapshot({
    required this.selectorCalls,
    required this.builderCalls,
  });

  final int selectorCalls;
  final int builderCalls;
}

final class _SelectorProfileScenario {
  const _SelectorProfileScenario({
    required this.scenario,
    required this.subscriptionMode,
    required this.selectorKind,
    required this.invalidationKind,
    required this.controllerNotificationCount,
    required this.initialSelectorCallCount,
    required this.finalSelectorCallCount,
    required this.initialWidgetBuildCount,
    required this.finalWidgetBuildCount,
    required this.expectedInvalidated,
    required this.selectedValueChanged,
    required this.lastInvalidation,
  });

  final String scenario;
  final String subscriptionMode;
  final String selectorKind;
  final String invalidationKind;
  final int controllerNotificationCount;
  final int initialSelectorCallCount;
  final int finalSelectorCallCount;
  final int initialWidgetBuildCount;
  final int finalWidgetBuildCount;
  final bool expectedInvalidated;
  final bool selectedValueChanged;
  final Map<String, Object?> lastInvalidation;

  Map<String, Object?> toJson() {
    final selectorCallDelta = finalSelectorCallCount - initialSelectorCallCount;
    final selectorBuilderCallDelta =
        finalWidgetBuildCount - initialWidgetBuildCount;
    return {
      'scenario': scenario,
      'subscriptionMode': subscriptionMode,
      'selectorKind': selectorKind,
      'invalidationKind': invalidationKind,
      'controllerNotificationCount': controllerNotificationCount,
      'selectorCallCount': finalSelectorCallCount,
      'selectorBuilderCallCount': finalWidgetBuildCount,
      'selectorCallDelta': selectorCallDelta,
      'selectorBuilderCallDelta': selectorBuilderCallDelta,
      'expectedSelectorCallDelta': expectedInvalidated ? 1 : 0,
      'expectedSelectorBuilderCallDelta': selectedValueChanged ? 1 : 0,
      // Kept as schema-v1 compatibility aliases. Prefer selectorBuilder* fields.
      'widgetBuildCount': finalWidgetBuildCount,
      'widgetBuildDelta': selectorBuilderCallDelta,
      'expectedInvalidated': expectedInvalidated,
      'selectedValueChanged': selectedValueChanged,
      'lastInvalidation': lastInvalidation,
    };
  }
}

class _CounterResource extends Resource {
  int count = 0;
}

class _TitleComponent extends Component {
  const _TitleComponent(this.value);

  final String value;
}

class _RecordComponent extends Component {
  const _RecordComponent({required this.id, required this.title});

  final String id;
  final String title;
}
