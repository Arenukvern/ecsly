import 'dart:async';

// ignore_for_file: experimental_member_use

import 'package:ecsly_flutter/ecsly_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class CounterResource extends Resource {
  int count = 0;
}

class OtherResource extends Resource {
  int count = 0;
}

class DerivedResource extends Resource {
  int value = 0;
  int runs = 0;
}

class MissingResource extends Resource {}

class TodoTitle extends Component {
  const TodoTitle(this.value);

  final String value;
}

class TodoId extends Component {
  const TodoId(this.value);

  final String value;
}

class TodoDone extends Component {
  const TodoDone({required this.value});

  final bool value;
}

class TodoRecord extends Component {
  const TodoRecord({required this.id, required this.title, required this.done});

  final String id;
  final String title;
  final bool done;

  TodoRecord copyWith({final String? title, final bool? done}) =>
      TodoRecord(id: id, title: title ?? this.title, done: done ?? this.done);
}

final class TodoIndexScope {
  const TodoIndexScope._();
}

class IncrementCounterAction extends EcsAction<int> {
  const IncrementCounterAction({this.by = 1});

  final int by;

  @override
  FutureOr<int> run(final EcsActionContext context) {
    late int next;
    context.mutateResource<CounterResource>((final counter) {
      next = counter.count += by;
    });
    return next;
  }
}

class MarkCounterAction extends EcsAction<void> {
  const MarkCounterAction();

  @override
  void run(final EcsActionContext context) {
    context.mutateResource<CounterResource>((final counter) {
      counter.count += 1;
    });
  }
}

class MarkOtherAction extends EcsAction<void> {
  const MarkOtherAction();

  @override
  void run(final EcsActionContext context) {
    context.mutateResource<OtherResource>((final other) {
      other.count += 1;
    });
  }
}

class ChainCounterAction extends EcsAction<void> {
  const ChainCounterAction();

  @override
  Future<void> run(final EcsActionContext context) async {
    await context.run(const MarkCounterAction());
    await context.run(const MarkCounterAction());
  }
}

class DelayedCounterAction extends EcsAction<int> {
  const DelayedCounterAction(this.completer);

  final Completer<int> completer;

  @override
  Future<int> run(final EcsActionContext context) async {
    final value = await completer.future;
    context.mutateResource<CounterResource>((final counter) {
      counter.count = value;
    });
    return value;
  }
}

class SharedStatusDelayedAction extends EcsAction<int> {
  const SharedStatusDelayedAction(this.completer, this.value);

  final Completer<void> completer;
  final int value;

  @override
  Object get statusKey => 'shared-counter';

  @override
  Future<int> run(final EcsActionContext context) async {
    await completer.future;
    return value;
  }
}

class SeedCounterAction extends EcsAction<void> {
  const SeedCounterAction();

  @override
  void run(final EcsActionContext context) {
    context.mutateResource<CounterResource>((final counter) {
      counter.count += 1;
    });
  }
}

class SpawnTodoAction extends EcsAction<Entity> {
  const SpawnTodoAction(this.id);

  final String id;

  @override
  Entity run(final EcsActionContext context) => context.spawnComponents([
    TodoRecord(id: id, title: 'Spawned $id', done: false),
    const TodoDone(value: false),
  ]);
}

class CountTodosResource extends Resource {
  int count = 0;
}

class CompleteTodoByIdAction extends EcsAction<void> {
  const CompleteTodoByIdAction(this.id);

  final String id;

  @override
  void run(final EcsActionContext context) {
    final entity = context.findEntityWithComponent<TodoRecord>(
      where: (final entity, final todo) => todo.id == id,
    );
    final todo = context.getComponent<TodoRecord>(entity: entity);
    context.upsertComponent(entity, todo.copyWith(done: true));
  }
}

World _todoWorld() => World()
  ..components.registerObjectComponent<TodoId>()
  ..components.registerObjectComponent<TodoTitle>()
  ..components.registerObjectComponent<TodoDone>()
  ..components.registerObjectComponent<TodoRecord>();

void main() {
  testWidgets('EcsScope exposes world and controller', (final tester) async {
    final world = _todoWorld();
    final controller = EcsController(world: world);

    late World resolvedWorld;
    late EcsController? resolvedController;
    await tester.pumpWidget(
      EcsScope(
        world: world,
        controller: controller,
        child: Builder(
          builder: (final context) {
            resolvedWorld = EcsScope.worldOf(context);
            resolvedController = EcsScope.controllerOf(context);
            return const SizedBox();
          },
        ),
      ),
    );

    expect(identical(resolvedWorld, world), isTrue);
    expect(identical(resolvedController, controller), isTrue);
  });

  testWidgets('EcsResourceSelector rebuilds after controller transaction', (
    final tester,
  ) async {
    final world = World()..upsertResource(CounterResource());
    final controller = EcsController(world: world);

    await tester.pumpWidget(
      MaterialApp(
        home: EcsScope(
          world: world,
          controller: controller,
          child: EcsResourceSelector<CounterResource, int>(
            select: (final resource) => resource.count,
            builder: (final context, final count) => Text('count: $count'),
          ),
        ),
      ),
    );

    expect(find.text('count: 0'), findsOneWidget);

    controller.runTransaction((final world) {
      world.getResource<CounterResource>().count += 1;
    });
    await tester.pump();

    expect(find.text('count: 1'), findsOneWidget);
  });

  testWidgets('EcsResourceBuilder renders absence fallback', (
    final tester,
  ) async {
    final world = _todoWorld();
    final controller = EcsController(world: world);

    await tester.pumpWidget(
      MaterialApp(
        home: EcsScope(
          world: world,
          controller: controller,
          child: EcsResourceBuilder<MissingResource>(
            whenAbsent: const Text('missing'),
            builder: (final context, final resource) => const Text('present'),
          ),
        ),
      ),
    );

    expect(find.text('missing'), findsOneWidget);
    expect(find.text('present'), findsNothing);
  });

  testWidgets('EcsResourceSelector skips unrelated tracked changes', (
    final tester,
  ) async {
    final world = _todoWorld()..upsertResource(CounterResource());
    final entity = world.entities.create();
    world.upsertComponent(entity, const TodoTitle('draft'));
    world.flush();
    final controller = EcsController(world: world);
    var selectCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: EcsScope(
          world: world,
          controller: controller,
          child: EcsResourceSelector<CounterResource, int>(
            select: (final resource) {
              selectCount += 1;
              return resource.count;
            },
            builder: (final context, final count) => Text('count: $count'),
          ),
        ),
      ),
    );

    expect(selectCount, 1);

    controller.runTransaction((final world) {
      world.upsertComponent(entity, const TodoTitle('saved'));
    }, invalidation: EcsInvalidationBatch.component<TodoTitle>(entity: entity));
    await tester.pump();

    expect(find.text('count: 0'), findsOneWidget);
    expect(selectCount, 1);
  });

  testWidgets(
    'selector outside EcsScope can use explicit controller fallback',
    (final tester) async {
      final world = _todoWorld()..upsertResource(CounterResource());
      final entity = world.entities.create();
      world.upsertComponent(entity, const TodoTitle('draft'));
      world.flush();
      final controller = EcsController(world: world);
      var selectCount = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: EcsResourceSelector<CounterResource, int>(
            world: world,
            controller: controller,
            select: (final resource) {
              selectCount += 1;
              return resource.count;
            },
            builder: (final context, final count) => Text('count: $count'),
          ),
        ),
      );

      expect(selectCount, 1);

      controller.runTransaction(
        (final world) {
          world.upsertComponent(entity, const TodoTitle('saved'));
        },
        invalidation: EcsInvalidationBatch.component<TodoTitle>(entity: entity),
      );
      await tester.pump();
      expect(selectCount, 1);

      controller.runTransaction((final world) {
        world.getResource<CounterResource>().count = 1;
      }, invalidation: EcsInvalidationBatch.resource<CounterResource>());
      await tester.pump();

      expect(find.text('count: 1'), findsOneWidget);
      expect(selectCount, 2);
    },
  );

  testWidgets('EcsComponentSelector rebuilds from sliced component state', (
    final tester,
  ) async {
    final world = _todoWorld();
    final entity = world.entities.create();
    world.upsertComponent(entity, const TodoTitle('brew coffee'));
    world.upsertComponent(entity, const TodoDone(value: false));
    world.flush();
    final controller = EcsController(world: world);

    await tester.pumpWidget(
      MaterialApp(
        home: EcsScope(
          world: world,
          controller: controller,
          child: EcsComponentSelector<TodoTitle, String>(
            entity: entity,
            select: (final component) => component.value,
            builder: (final context, final title) => Text(title),
          ),
        ),
      ),
    );

    expect(find.text('brew coffee'), findsOneWidget);

    controller.runTransaction((final world) {
      world.upsertComponent(entity, const TodoTitle('taste coffee'));
    });
    await tester.pump();

    expect(find.text('taste coffee'), findsOneWidget);
  });

  testWidgets('EcsComponentSelector skips rebuild for equal selected value', (
    final tester,
  ) async {
    final world = _todoWorld();
    final entity = world.entities.create();
    world.upsertComponent(entity, const TodoTitle('alpha'));
    world.flush();
    final controller = EcsController(world: world);
    var buildCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: EcsScope(
          world: world,
          controller: controller,
          child: EcsComponentSelector<TodoTitle, int>(
            entity: entity,
            select: (final component) => component.value.length,
            builder: (final context, final length) {
              buildCount++;
              return Text('length: $length');
            },
          ),
        ),
      ),
    );

    expect(buildCount, 1);

    controller.runTransaction((final world) {
      world.upsertComponent(entity, const TodoTitle('bravo'));
    });
    await tester.pump();

    expect(find.text('length: 5'), findsOneWidget);
    expect(buildCount, 1);
  });

  testWidgets('EcsComponentSelector skips tracked changes on other entities', (
    final tester,
  ) async {
    final world = _todoWorld();
    final first = world.entities.create();
    final second = world.entities.create();
    world.upsertComponent(first, const TodoTitle('first'));
    world.upsertComponent(second, const TodoTitle('second'));
    world.flush();
    final controller = EcsController(world: world);
    var selectCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: EcsScope(
          world: world,
          controller: controller,
          child: EcsComponentSelector<TodoTitle, String>(
            entity: first,
            select: (final component) {
              selectCount += 1;
              return component.value;
            },
            builder: (final context, final title) => Text(title),
          ),
        ),
      ),
    );

    expect(selectCount, 1);

    controller.runTransaction((final world) {
      world.upsertComponent(second, const TodoTitle('changed'));
    }, invalidation: EcsInvalidationBatch.component<TodoTitle>(entity: second));
    await tester.pump();

    expect(find.text('first'), findsOneWidget);
    expect(selectCount, 1);
  });

  testWidgets('sliced app components resolve through typed id projection', (
    final tester,
  ) async {
    final world = _todoWorld()
      ..upsertResource(EntityIndexResource<TodoIndexScope, String>());
    final entity = world.spawnComponents([
      const TodoId('todo-1'),
      const TodoTitle('Write docs'),
      const TodoDone(value: false),
    ]);
    world.flush();
    world.getResource<EntityIndexResource<TodoIndexScope, String>>().upsert(
      'todo-1',
      entity,
    );
    final controller = EcsController(world: world);

    await tester.pumpWidget(
      MaterialApp(
        home: EcsScope(
          world: world,
          controller: controller,
          child: Builder(
            builder: (final context) {
              final resolved = context
                  .getEcsResource<EntityIndexResource<TodoIndexScope, String>>()
                  .entityOf('todo-1');
              final title = context.selectEcsComponent<TodoTitle, String>(
                (final component) => component.value,
                entity: resolved,
              );
              final done = context.selectEcsComponent<TodoDone, bool>(
                (final component) => component.value,
                entity: resolved,
              );
              return Text('$title:${done ? 'done' : 'open'}');
            },
          ),
        ),
      ),
    );

    expect(find.text('Write docs:open'), findsOneWidget);

    controller.runTransaction((final world) {
      world.upsertComponent(entity, const TodoDone(value: true));
    });
    await tester.pump();

    expect(find.text('Write docs:done'), findsOneWidget);
  });

  testWidgets(
    'EcsWorldSelector derives values across resources and components',
    (final tester) async {
      final world = _todoWorld()..upsertResource(CounterResource());
      final entity = world.entities.create();
      world.upsertComponent(entity, const TodoTitle('draft'));
      world.flush();
      final controller = EcsController(world: world);

      await tester.pumpWidget(
        MaterialApp(
          home: EcsScope(
            world: world,
            controller: controller,
            child: EcsWorldSelector<String>(
              select: (final world) {
                final count = world.getResource<CounterResource>().count;
                final title = world.getComponent<TodoTitle>(entity).value;
                return '$title:$count';
              },
              builder: (final context, final value) => Text(value),
            ),
          ),
        ),
      );

      expect(find.text('draft:0'), findsOneWidget);

      controller.runTransaction((final world) {
        world.getResource<CounterResource>().count = 2;
        world.upsertComponent(entity, const TodoTitle('saved'));
      });
      await tester.pump();

      expect(find.text('saved:2'), findsOneWidget);
    },
  );

  testWidgets('EcsWorldSelector dependency hints skip unrelated changes', (
    final tester,
  ) async {
    final world = _todoWorld()..upsertResource(CounterResource());
    final entity = world.entities.create();
    world.upsertComponent(entity, const TodoTitle('draft'));
    world.flush();
    final controller = EcsController(world: world);
    var selectCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: EcsScope(
          world: world,
          controller: controller,
          child: EcsWorldSelector<int>(
            dependencies: const EcsWorldSelectorDependencies(
              resourceTypes: [CounterResource],
            ),
            select: (final world) {
              selectCount += 1;
              return world.getResource<CounterResource>().count;
            },
            builder: (final context, final value) => Text('count: $value'),
          ),
        ),
      ),
    );

    expect(selectCount, 1);

    controller.runTransaction((final world) {
      world.upsertComponent(entity, const TodoTitle('saved'));
    }, invalidation: EcsInvalidationBatch.component<TodoTitle>(entity: entity));
    await tester.pump();

    expect(selectCount, 1);

    controller.runTransaction((final world) {
      world.getResource<CounterResource>().count = 1;
    }, invalidation: EcsInvalidationBatch.resource<CounterResource>());
    await tester.pump();

    expect(find.text('count: 1'), findsOneWidget);
    expect(selectCount, 2);
  });

  testWidgets('EcsWorldSelector component dependency refreshes on component', (
    final tester,
  ) async {
    final world = _todoWorld()..upsertResource(CounterResource());
    final entity = world.entities.create();
    world.upsertComponent(entity, const TodoTitle('draft'));
    world.flush();
    final controller = EcsController(world: world);
    var selectCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: EcsScope(
          world: world,
          controller: controller,
          child: EcsWorldSelector<String>(
            dependencies: const EcsWorldSelectorDependencies(
              componentTypes: [TodoTitle],
            ),
            select: (final world) {
              selectCount += 1;
              return world.getComponent<TodoTitle>(entity).value;
            },
            builder: (final context, final value) => Text(value),
          ),
        ),
      ),
    );

    expect(selectCount, 1);

    controller.runTransaction((final world) {
      world.getResource<CounterResource>().count = 1;
    }, invalidation: EcsInvalidationBatch.resource<CounterResource>());
    await tester.pump();

    expect(selectCount, 1);

    controller.runTransaction((final world) {
      world.upsertComponent(entity, const TodoTitle('saved'));
    }, invalidation: EcsInvalidationBatch.component<TodoTitle>(entity: entity));
    await tester.pump();

    expect(find.text('saved'), findsOneWidget);
    expect(selectCount, 2);
  });

  testWidgets('selectors conservatively refresh untracked transactions', (
    final tester,
  ) async {
    final world = World()..upsertResource(CounterResource());
    world.flush();
    final controller = EcsController(world: world);
    var selectCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: EcsScope(
          world: world,
          controller: controller,
          child: EcsResourceSelector<CounterResource, int>(
            select: (final resource) {
              selectCount += 1;
              return resource.count;
            },
            builder: (final context, final count) => Text('count: $count'),
          ),
        ),
      ),
    );

    expect(selectCount, 1);

    controller.runTransaction((final world) {
      world.getResource<CounterResource>().count = 1;
    });
    await tester.pump();

    expect(find.text('count: 1'), findsOneWidget);
    expect(selectCount, 2);
  });

  testWidgets('BuildContext ecs helpers read resources and components', (
    final tester,
  ) async {
    final world = _todoWorld()..upsertResource(CounterResource());
    final entity = world.entities.create();
    world.upsertComponent(entity, const TodoTitle('initial'));
    world.flush();
    final controller = EcsController(world: world);

    await tester.pumpWidget(
      MaterialApp(
        home: EcsScope(
          world: world,
          controller: controller,
          child: Builder(
            builder: (final context) {
              final count = context.selectEcsResource<CounterResource, int>(
                (final resource) => resource.count,
              );
              expect(context.getEcsResource<CounterResource>().count, count);
              final title = context.selectEcsComponent<TodoTitle, String>(
                (final component) => component.value,
                entity: entity,
              );
              expect(
                context.getEcsComponent<TodoTitle>(entity: entity).value,
                title,
              );
              return Text('$title: $count');
            },
          ),
        ),
      ),
    );

    expect(find.text('initial: 0'), findsOneWidget);

    controller.runTransaction((final world) {
      world.getResource<CounterResource>().count = 3;
      world.upsertComponent(entity, const TodoTitle('updated'));
    });
    await tester.pump();

    expect(find.text('updated: 3'), findsOneWidget);
  });

  testWidgets('EcsController runs actions and records status', (
    final tester,
  ) async {
    final world = World()..upsertResource(CounterResource());
    final controller = EcsController(world: world);

    final result = await controller.runAction(
      const IncrementCounterAction(by: 2),
    );

    expect(result, 2);
    expect(world.getResource<CounterResource>().count, 2);
    final status = controller.actionStatusOf(IncrementCounterAction);
    expect(status.hasSucceeded, isTrue);
    expect(status.result, 2);
  });

  testWidgets(
    'EcsComponentSelector can resolve a component without an entity',
    (final tester) async {
      final world = _todoWorld();
      final first = world.entities.create();
      final second = world.entities.create();
      world.upsertComponent(
        first,
        const TodoRecord(id: 'a', title: 'Arabica', done: false),
      );
      world.upsertComponent(
        second,
        const TodoRecord(id: 'b', title: 'Robusta', done: false),
      );
      world.flush();
      final controller = EcsController(world: world);

      await tester.pumpWidget(
        MaterialApp(
          home: EcsScope(
            world: world,
            controller: controller,
            child: EcsComponentSelector<TodoRecord, String>(
              where: (final entity, final todo) => todo.id == 'b',
              select: (final todo) => todo.title,
              builder: (final context, final title) => Text(title),
            ),
          ),
        ),
      );

      expect(find.text('Robusta'), findsOneWidget);

      controller.runTransaction((final world) {
        world.upsertComponent(
          second,
          const TodoRecord(id: 'b', title: 'Liberica', done: false),
        );
      });
      await tester.pump();

      expect(find.text('Liberica'), findsOneWidget);
    },
  );

  testWidgets('context component lookup can return the resolved entity', (
    final tester,
  ) async {
    final world = _todoWorld();
    final entity = world.entities.create();
    world.upsertComponent(
      entity,
      const TodoRecord(id: 'chosen', title: 'Selected', done: false),
    );
    world.flush();
    final controller = EcsController(world: world);

    await tester.pumpWidget(
      MaterialApp(
        home: EcsScope(
          world: world,
          controller: controller,
          child: Builder(
            builder: (final context) {
              final label = context.selectEcsComponent<TodoRecord, String>(
                (final todo) => todo.title,
                where: (final candidate, final todo) => todo.id == 'chosen',
                selectWithEntity: (final resolved, final todo) {
                  expect(resolved, entity);
                  return '${todo.title}:${todo.id}';
                },
              );
              return Text(label);
            },
          ),
        ),
      ),
    );

    expect(find.text('Selected:chosen'), findsOneWidget);
  });

  testWidgets('EcsAction can resolve and mutate a component by app data', (
    final tester,
  ) async {
    final world = _todoWorld();
    final entity = world.entities.create();
    world.upsertComponent(
      entity,
      const TodoRecord(id: 'sync-target', title: 'Draft', done: false),
    );
    world.flush();
    final controller = EcsController(world: world);

    await controller.runAction(const CompleteTodoByIdAction('sync-target'));

    final updated = world.getComponent<TodoRecord>(entity);
    expect(updated.done, isTrue);
    expect(
      controller.actionStatusOf(CompleteTodoByIdAction).hasSucceeded,
      isTrue,
    );
  });

  testWidgets('EcsActionContext spawns bundled component entities', (
    final tester,
  ) async {
    final world = _todoWorld();
    final controller = EcsController(world: world);

    final entity = await controller.runAction(const SpawnTodoAction('new'));

    expect(world.entities.isAlive(entity), isTrue);
    expect(world.getComponent<TodoRecord>(entity).title, 'Spawned new');
    expect(world.getComponent<TodoDone>(entity).value, isFalse);
  });

  testWidgets('EntityIndexResource maps stable app ids to entities', (
    final tester,
  ) async {
    final world = _todoWorld()
      ..upsertResource(EntityIndexResource<TodoIndexScope, String>());
    final entity = world.entities.create();
    world.upsertComponent(
      entity,
      const TodoRecord(id: 'indexed', title: 'Indexed', done: false),
    );
    world.flush();

    final index = world
        .getResource<EntityIndexResource<TodoIndexScope, String>>();
    index.upsert('indexed', entity);

    expect(index.maybeEntityOf('indexed'), entity);
    expect(index.entityOf('indexed'), entity);
    expect(index.toMap(), containsPair('indexed', entity));
    expect(index.remove('indexed'), entity);
    expect(index.maybeEntityOf('indexed'), isNull);
  });

  testWidgets('EcsActionBuilder disables run while action is running', (
    final tester,
  ) async {
    final world = World()..upsertResource(CounterResource());
    final controller = EcsController(world: world);
    final completer = Completer<int>();
    final action = DelayedCounterAction(completer);

    await tester.pumpWidget(
      MaterialApp(
        home: EcsScope(
          world: world,
          controller: controller,
          child: EcsActionBuilder<int>(
            action: action,
            builder: (final context, final status, final run) => ElevatedButton(
              onPressed: run == null ? null : () => unawaited(run()),
              child: Text(status.isRunning ? 'saving' : 'save'),
            ),
          ),
        ),
      ),
    );

    expect(find.text('save'), findsOneWidget);
    await tester.tap(find.byType(ElevatedButton));
    await tester.pump();

    expect(find.text('saving'), findsOneWidget);
    final button = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
    expect(button.onPressed, isNull);

    completer.complete(7);
    await tester.pumpAndSettle();

    expect(find.text('save'), findsOneWidget);
    expect(world.getResource<CounterResource>().count, 7);
  });

  testWidgets('EcsActionStatusSelector observes action status', (
    final tester,
  ) async {
    final world = World()..upsertResource(CounterResource());
    final controller = EcsController(world: world);

    await tester.pumpWidget(
      MaterialApp(
        home: EcsScope(
          world: world,
          controller: controller,
          child: EcsActionStatusSelector(
            statusKey: IncrementCounterAction,
            builder: (final context, final status) =>
                Text(status.hasSucceeded ? 'done' : status.phase.name),
          ),
        ),
      ),
    );

    expect(find.text('idle'), findsOneWidget);

    await controller.runAction(const IncrementCounterAction());
    await tester.pump();

    expect(find.text('done'), findsOneWidget);
  });

  testWidgets('EcsActionOnMount runs once after mount', (final tester) async {
    final world = World()..upsertResource(CounterResource());
    final controller = EcsController(world: world);

    Widget app() => MaterialApp(
      home: EcsScope(
        world: world,
        controller: controller,
        child: const EcsActionOnMount(
          action: SeedCounterAction(),
          child: SizedBox(),
        ),
      ),
    );

    await tester.pumpWidget(app());
    await tester.pump();

    expect(world.getResource<CounterResource>().count, 1);

    await tester.pumpWidget(app());
    await tester.pump();

    expect(world.getResource<CounterResource>().count, 1);
  });

  testWidgets('EcsAppScope runs mount and after-action schedules', (
    final tester,
  ) async {
    final events = <EcsScheduleRunEvent>[];
    final world = World()..upsertResource(CounterResource());
    world.getOrCreateSchedule('boot').add((final world) {
      world.getResource<CounterResource>().count += 1;
    });
    world.getOrCreateSchedule('afterAction').add((final world) {
      world.getResource<CounterResource>().count += 10;
    });
    final controller = EcsController(world: world);

    await tester.pumpWidget(
      MaterialApp(
        home: EcsAppScope(
          world: world,
          controller: controller,
          schedules: const EcsFlutterSchedules(
            onMount: 'boot',
            afterAction: 'afterAction',
          ),
          onScheduleRun: events.add,
          child: const SizedBox(),
        ),
      ),
    );
    await tester.pump();

    expect(world.getResource<CounterResource>().count, 1);
    expect(events.single.reason, EcsFlutterScheduleReason.onMount);

    await controller.runAction(const IncrementCounterAction(by: 2));

    expect(world.getResource<CounterResource>().count, 13);
    expect(events.last.reason, EcsFlutterScheduleReason.afterAction);
    expect(events.last.scheduleName, 'afterAction');
  });

  testWidgets('EcsAppScope runs flutterFrame frame schedules', (
    final tester,
  ) async {
    final world = World()..upsertResource(CounterResource());
    world.getOrCreateSchedule('frame').add((final world) {
      world.getResource<CounterResource>().count += 1;
    });
    final controller = EcsController(world: world);

    await tester.pumpWidget(
      MaterialApp(
        home: EcsAppScope(
          world: world,
          controller: controller,
          schedules: const EcsFlutterSchedules(
            frame: EcsFrameSchedule.flutterFrame('frame'),
          ),
          child: const SizedBox(),
        ),
      ),
    );

    expect(
      const EcsFrameSchedule.flutterFrame('frame').mode,
      EcsFrameScheduleMode.flutterFrame,
    );

    await tester.pump(const Duration(milliseconds: 16));

    expect(world.getResource<CounterResource>().count, 1);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('EcsLoop can narrow frame invalidation to schedule hints', (
    final tester,
  ) async {
    final world = _todoWorld()..upsertResource(CounterResource());
    final entity = world.spawnComponents(const [TodoTitle('initial')]);
    world.flush();
    final controller = EcsController(world: world);
    var frame = 0;
    var resourceSelects = 0;
    var componentSelects = 0;
    world.getOrCreateSchedule('frame').add((final world) {
      frame += 1;
      world.upsertComponent(entity, TodoTitle('frame $frame'));
    });

    await tester.pumpWidget(
      MaterialApp(
        home: EcsScope(
          world: world,
          controller: controller,
          child: EcsLoop(
            world: world,
            controller: controller,
            schedules: const ['frame'],
            scheduleInvalidation: (_) =>
                EcsInvalidationBatch.component<TodoTitle>(entity: entity),
            child: Column(
              children: [
                EcsResourceSelector<CounterResource, int>(
                  select: (final counter) {
                    resourceSelects += 1;
                    return counter.count;
                  },
                  builder: (final context, final count) =>
                      Text('count: $count'),
                ),
                EcsComponentSelector<TodoTitle, String>(
                  entity: entity,
                  select: (final title) {
                    componentSelects += 1;
                    return title.value;
                  },
                  builder: (final context, final title) => Text(title),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    final initialResourceSelects = resourceSelects;
    final initialComponentSelects = componentSelects;

    await tester.pump(const Duration(milliseconds: 16));

    expect(find.text('frame 1'), findsOneWidget);
    expect(resourceSelects, initialResourceSelects);
    expect(componentSelects, initialComponentSelects + 1);
    expect(controller.lastInvalidation.broad, isFalse);
    expect(
      controller.lastInvalidation.matchesResourceType(DeltaTimeResource),
      isTrue,
    );
    expect(
      controller.lastInvalidation.matchesResourceType(ScheduleTimeResource),
      isTrue,
    );

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('EcsLoop broad-invalidates when schedule hints are omitted', (
    final tester,
  ) async {
    final world = _todoWorld()..upsertResource(CounterResource());
    final entity = world.spawnComponents(const [TodoTitle('initial')]);
    world.flush();
    final controller = EcsController(world: world);
    var resourceSelects = 0;
    world.getOrCreateSchedule('frame').add((final world) {
      world.upsertComponent(entity, const TodoTitle('changed'));
    });

    await tester.pumpWidget(
      MaterialApp(
        home: EcsScope(
          world: world,
          controller: controller,
          child: EcsLoop(
            world: world,
            controller: controller,
            schedules: const ['frame'],
            child: EcsResourceSelector<CounterResource, int>(
              select: (final counter) {
                resourceSelects += 1;
                return counter.count;
              },
              builder: (final context, final count) => Text('count: $count'),
            ),
          ),
        ),
      ),
    );
    final initialResourceSelects = resourceSelects;

    await tester.pump(const Duration(milliseconds: 16));

    expect(resourceSelects, initialResourceSelects + 1);
    expect(controller.lastInvalidation.broad, isTrue);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'EcsFixedStepLoop coalesces narrow invalidation per ticker frame',
    (final tester) async {
      final world = _todoWorld();
      final entity = world.spawnComponents(const [TodoTitle('initial')]);
      world.flush();
      final controller = EcsController(world: world);
      var notifications = 0;
      var componentSelects = 0;
      var frame = 0;
      controller.addListener(() => notifications += 1);
      world.getOrCreateSchedule('fixed').add((final world) {
        frame += 1;
        world.upsertComponent(entity, TodoTitle('step $frame'));
      });

      await tester.pumpWidget(
        MaterialApp(
          home: EcsScope(
            world: world,
            controller: controller,
            child: EcsFixedStepLoop(
              world: world,
              controller: controller,
              schedules: const ['fixed'],
              fixedDt: 0.01,
              scheduleInvalidation: (_) =>
                  EcsInvalidationBatch.component<TodoTitle>(entity: entity),
              child: EcsComponentSelector<TodoTitle, String>(
                entity: entity,
                select: (final title) {
                  componentSelects += 1;
                  return title.value;
                },
                builder: (final context, final title) => Text(title),
              ),
            ),
          ),
        ),
      );
      final initialComponentSelects = componentSelects;

      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 40));

      expect(notifications, 1);
      expect(componentSelects, initialComponentSelects + 1);
      expect(frame, greaterThan(0));
      expect(find.text('step $frame'), findsOneWidget);
      expect(controller.lastInvalidation.broad, isFalse);
      expect(
        controller.lastInvalidation.matchesComponentType(
          TodoTitle,
          entity: entity,
        ),
        isTrue,
      );

      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  test('after-action schedules run after app actions', () async {
    final world = World()
      ..upsertResource(CounterResource())
      ..upsertResource(OtherResource())
      ..upsertResource(DerivedResource())
      ..flush();
    world.getOrCreateSchedule('afterAction').add((final world) {
      world.getResource<DerivedResource>()
        ..runs += 1
        ..value = world.getResource<CounterResource>().count * 2;
    });
    final controller = EcsController(
      world: world,
      afterActionSchedule: 'afterAction',
    );

    await controller.runAction(const MarkOtherAction());

    expect(world.getResource<DerivedResource>().runs, 1);

    await controller.runAction(const MarkCounterAction());

    expect(world.getResource<DerivedResource>().runs, 2);
    expect(world.getResource<DerivedResource>().value, 2);
  });

  test('string after-action schedules keep broad invalidation', () async {
    final world = World()
      ..upsertResource(CounterResource())
      ..upsertResource(DerivedResource())
      ..flush();
    world.getOrCreateSchedule('afterAction').add((final world) {
      world.getResource<DerivedResource>().runs += 1;
    });
    final controller = EcsController(
      world: world,
      afterActionSchedule: 'afterAction',
    );

    await controller.runAction(const MarkCounterAction());

    expect(world.getResource<DerivedResource>().runs, 1);
    expect(controller.lastInvalidation.broad, isTrue);
  });

  test(
    'after-action schedule specs gate work and preserve narrow invalidation',
    () async {
      final world = World()
        ..upsertResource(CounterResource())
        ..upsertResource(OtherResource())
        ..upsertResource(DerivedResource())
        ..flush();
      world.getOrCreateSchedule('afterAction').add((final world) {
        world.getResource<DerivedResource>()
          ..runs += 1
          ..value = world.getResource<CounterResource>().count * 2;
      });
      final controller = EcsController(
        world: world,
        afterActionScheduleSpec: EcsHostSchedule(
          'afterAction',
          invalidation: EcsInvalidationBatch.resource<DerivedResource>(),
          runWhen: (final trigger) =>
              trigger.matchesResourceType(CounterResource),
        ),
      );

      await controller.runAction(const MarkOtherAction());

      expect(world.getResource<DerivedResource>().runs, 0);
      expect(controller.lastInvalidation.broad, isFalse);
      expect(
        controller.lastInvalidation.matchesResourceType(OtherResource),
        isTrue,
      );
      expect(
        controller.lastInvalidation.matchesResourceType(DerivedResource),
        isFalse,
      );

      await controller.runAction(const MarkCounterAction());

      expect(world.getResource<DerivedResource>().runs, 1);
      expect(world.getResource<DerivedResource>().value, 2);
      expect(controller.lastInvalidation.broad, isFalse);
      expect(
        controller.lastInvalidation.matchesResourceType(CounterResource),
        isTrue,
      );
      expect(
        controller.lastInvalidation.matchesResourceType(DerivedResource),
        isTrue,
      );
      expect(
        controller.lastInvalidation.matchesResourceType(
          EcsActionStatusResource,
        ),
        isTrue,
      );
    },
  );

  test('after-action schedules see deferred command changes', () async {
    final world = _todoWorld()
      ..upsertResource(CountTodosResource())
      ..flush();
    world.getOrCreateSchedule('afterAction').add((final world) {
      final rows = world.query<TodoRecord>().toList(growable: false);
      world.getResource<CountTodosResource>().count = rows.length;
    });
    final controller = EcsController(
      world: world,
      afterActionSchedule: 'afterAction',
    );

    await controller.runAction(const SpawnTodoAction('a'));

    expect(world.getResource<CountTodosResource>().count, 1);
  });

  test('actions can explicitly chain nested actions', () async {
    final world = World()..upsertResource(CounterResource());
    final controller = EcsController(world: world);

    await controller.runAction(const ChainCounterAction());

    expect(world.getResource<CounterResource>().count, 2);
  });

  test(
    'older overlapping action completion does not overwrite newer status',
    () async {
      final first = Completer<void>();
      final second = Completer<void>();
      final controller = EcsController(world: World());

      final firstRun = controller.runAction(
        SharedStatusDelayedAction(first, 1),
      );
      final secondRun = controller.runAction(
        SharedStatusDelayedAction(second, 2),
      );

      second.complete();
      expect(await secondRun, 2);
      expect(controller.actionStatusOf('shared-counter').result, 2);

      first.complete();
      expect(await firstRun, 1);
      expect(controller.actionStatusOf('shared-counter').result, 2);
    },
  );

  test('EcsDraft tracks dirty state, field errors, reset, and commit', () {
    final draft = EcsDraft<String>(original: 'old');

    expect(draft.isDirty, isFalse);

    draft.current = 'new';
    draft.touch('name');
    draft.setFieldError('name', 'Too short');

    expect(draft.isDirty, isTrue);
    expect(draft.field('name').touched, isTrue);
    expect(draft.hasErrors, isTrue);

    draft.setFieldError('name', null);
    expect(draft.hasErrors, isFalse);

    draft.commit();
    expect(draft.original, 'new');
    expect(draft.current, 'new');
    expect(draft.isDirty, isFalse);

    draft.current = 'again';
    draft.reset();
    expect(draft.current, 'new');
  });
}
