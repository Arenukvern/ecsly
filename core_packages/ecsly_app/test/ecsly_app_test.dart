import 'dart:async';

import 'package:ecsly_app/ecsly_app.dart';
import 'package:test/test.dart';

class CounterResource extends Resource {
  CounterResource(this.value);
  int value;
}

class OtherResource extends Resource {}

class NameComponent extends Component {
  const NameComponent(this.value);
  final String value;
}

class IncrementAction extends EcsAction<int> {
  const IncrementAction();

  @override
  int run(final EcsActionContext context) {
    final counter = context.getResource<CounterResource>();
    counter.value += context.readService<int>();
    context.invalidateResource<CounterResource>();
    return counter.value;
  }
}

class FailingAction extends EcsAction<void> {
  const FailingAction();

  @override
  void run(final EcsActionContext context) {
    throw StateError('nope');
  }
}

class CancellingAction extends EcsAction<void> {
  const CancellingAction();

  @override
  void run(final EcsActionContext context) {
    context.cancellationToken.cancel();
    context.cancelIfRequested();
  }
}

class SharedDelayedAction extends EcsAction<int> {
  const SharedDelayedAction(this.result, this.completer);

  final int result;
  final Completer<void> completer;

  @override
  Object get statusKey => SharedDelayedAction;

  @override
  Future<int> run(final EcsActionContext context) async {
    await completer.future;
    return result;
  }
}

class ProgressAction extends EcsAction<void> {
  const ProgressAction();

  @override
  void run(final EcsActionContext context) {
    context.setProgress(0.5);
  }
}

class HelperMutationAction extends EcsAction<void> {
  const HelperMutationAction(this.entity);

  final Entity entity;

  @override
  void run(final EcsActionContext context) {
    context.mutateResource<CounterResource>((final counter) {
      counter.value += 1;
    });
    context.upsertComponent(entity, const NameComponent('updated'));
  }
}

class ServiceRoundTripAction extends EcsAction<String> {
  const ServiceRoundTripAction();

  @override
  String run(final EcsActionContext context) {
    expect(context.hasService<String>(), isTrue);
    context.services.upsert<double>(2.5);
    return '${context.readService<String>()}:${context.readService<double>()}';
  }
}

void main() {
  group('EcsActionRunner', () {
    test('runs actions, records status, and notifies host callback', () async {
      final world = World()..upsertResource(CounterResource(1));
      final runner = EcsActionRunner(
        world: world,
        services: EcsActionServices({int: 2}),
      );
      var notifications = 0;

      final result = await runner.run(
        const IncrementAction(),
        onChanged: ({final flush = true, final invalidation}) {
          notifications += 1;
          if (flush) world.flush();
        },
      );

      expect(result, 3);
      expect(world.getResource<CounterResource>().value, 3);
      final status = runner.actionStatusOf(IncrementAction);
      expect(status.hasSucceeded, isTrue);
      expect(status.result, 3);
      expect(notifications, greaterThanOrEqualTo(2));
    });

    test('records failed and cancelled statuses', () async {
      final world = World();
      final runner = EcsActionRunner(world: world);

      await expectLater(
        runner.run(const FailingAction()),
        throwsA(isA<StateError>()),
      );
      expect(runner.actionStatusOf(FailingAction).hasFailed, isTrue);

      await expectLater(
        runner.run(const CancellingAction()),
        throwsA(isA<EcsActionCancelledException>()),
      );
      expect(runner.actionStatusOf(CancellingAction).isCancelled, isTrue);
    });

    test(
      'older overlapping completion cannot overwrite newer status',
      () async {
        final world = World();
        final runner = EcsActionRunner(world: world);
        final slow = Completer<void>();
        final fast = Completer<void>();

        final slowRun = runner.run(SharedDelayedAction(1, slow));
        final fastRun = runner.run(SharedDelayedAction(2, fast));

        fast.complete();
        expect(await fastRun, 2);
        slow.complete();
        expect(await slowRun, 1);

        final status = runner.actionStatusOf(SharedDelayedAction);
        expect(status.hasSucceeded, isTrue);
        expect(status.result, 2);
      },
    );

    test('records progress and exposes app services', () async {
      final world = World();
      final runner = EcsActionRunner(
        world: world,
        services: EcsActionServices({String: 'ready'}),
      );
      final observedProgress = <double?>[];

      await runner.run(
        const ProgressAction(),
        onChanged: ({final flush = true, final invalidation}) {
          if (flush) world.flush();
          observedProgress.add(runner.actionStatusOf(ProgressAction).progress);
        },
      );

      expect(observedProgress, contains(0.5));
      expect(runner.actionStatusOf(ProgressAction).hasSucceeded, isTrue);

      final result = await runner.run(const ServiceRoundTripAction());
      expect(result, 'ready:2.5');
    });

    test('mutation helpers emit narrow invalidation hints', () async {
      final world = World()
        ..components.registerObjectComponent<NameComponent>()
        ..upsertResource(CounterResource(0));
      final entity = world.spawnComponents(const [NameComponent('initial')]);
      world.flush();
      final runner = EcsActionRunner(world: world);
      final invalidations = <EcsInvalidationBatch>[];

      await runner.run(
        HelperMutationAction(entity),
        onChanged: ({final flush = true, final invalidation}) {
          invalidations.add(invalidation ?? const EcsInvalidationBatch.broad());
          if (flush) world.flush();
        },
      );

      final last = invalidations.last;
      expect(last.broad, isFalse);
      expect(last.matchesResourceType(CounterResource), isTrue);
      expect(last.matchesResourceType(OtherResource), isFalse);
      expect(last.matchesComponentType(NameComponent, entity: entity), isTrue);
      expect(
        world.getEcsComponent<NameComponent>(entity: entity).value,
        'updated',
      );
    });
  });

  test(
    'EcsInvalidationBatch matches broad resource component and entity hints',
    () {
      final entity = Entity.create(1);
      const broad = EcsInvalidationBatch.broad();
      expect(broad.matchesResourceType(CounterResource), isTrue);
      expect(broad.matchesComponentType(NameComponent, entity: entity), isTrue);
      expect(broad.matchesStructural(), isTrue);

      final resource = EcsInvalidationBatch.resource<CounterResource>();
      expect(resource.matchesResourceType(CounterResource), isTrue);
      expect(resource.matchesResourceType(EcsActionStatusResource), isFalse);

      final component = EcsInvalidationBatch.component<NameComponent>(
        entity: entity,
      );
      expect(
        component.matchesComponentType(NameComponent, entity: entity),
        isTrue,
      );
      expect(
        component.matchesComponentType(NameComponent, entity: Entity.create(2)),
        isFalse,
      );
      expect(component.matchesComponentType(NameComponent), isTrue);
    },
  );

  test('EcsDraft tracks dirty fields and commit/reset state', () {
    final draft = EcsDraft<String>(original: 'old');

    draft.current = 'new';
    draft.touch('title');
    draft.setFieldError('title', 'required');

    expect(draft.isDirty, isTrue);
    expect(draft.hasErrors, isTrue);
    expect(draft.field('title').touched, isTrue);

    draft.setFieldError('title', null);
    expect(draft.hasErrors, isFalse);

    draft.commit();
    expect(draft.original, 'new');
    expect(draft.isDirty, isFalse);

    draft.current = 'again';
    draft.reset();
    expect(draft.current, 'new');
  });

  test('EcsDraft supports custom equality and rebasing', () {
    final draft = EcsDraft<List<int>>(
      original: [1, 2],
      current: [1, 2],
      equals: (final previous, final next) =>
          previous.length == next.length &&
          previous.indexed.every((final item) => item.$2 == next[item.$1]),
    );

    expect(draft.isDirty, isFalse);

    draft.current = [1, 3];
    expect(draft.isDirty, isTrue);

    draft.rebase([9], keepCurrent: false);
    expect(draft.original, [9]);
    expect(draft.current, [9]);
    expect(draft.isDirty, isFalse);
  });

  test('EcsDraftsResource stores typed drafts by app key', () {
    final drafts = EcsDraftsResource();

    final first = drafts.draft<String>('title', original: 'old');
    final second = drafts.draft<String>('title', original: 'ignored');

    expect(identical(first, second), isTrue);
    expect(drafts.hasDraft('title'), isTrue);
    expect(drafts.maybeDraft<String>('title'), first);

    drafts.removeDraft('title');
    expect(drafts.maybeDraft<String>('title'), isNull);

    drafts.draft<int>('count', original: 1);
    drafts.clear();
    expect(drafts.hasDraft('count'), isFalse);
  });

  test('EntityIndexResource maps typed id spaces to entities', () {
    final entity = Entity.create(1);
    final index = EntityIndexResource<Object, String>()..upsert('a', entity);

    expect(index.entityOf('a'), entity);
    expect(index.toMap(), {'a': entity});
    expect(() => index.entityOf('missing'), throwsStateError);
    expect(index.toMap, returnsNormally);
    expect(() => index.toMap()['b'] = entity, throwsUnsupportedError);
  });

  test('cold component lookup ignores despawned entities after flush', () {
    final world = World();
    world.components.registerObjectComponent<NameComponent>();
    final entity = world.spawnComponents(const [NameComponent('a')]);
    world.flush();

    expect(
      world.findEcsEntityWithComponent<NameComponent>(
        where: (final _, final name) => name.value == 'a',
      ),
      entity,
    );

    world.despawnEntity(entity);
    world.flush();

    expect(
      world.maybeFindEcsEntityWithComponent<NameComponent>(
        where: (final _, final name) => name.value == 'a',
      ),
      isNull,
    );
  });

  group('EcsHostSchedule', () {
    test('shouldRun defaults to true without runWhen', () {
      const schedule = EcsHostSchedule('app.boot');

      expect(schedule.shouldRun(const EcsInvalidationBatch.empty()), isTrue);
      expect(
        schedule.shouldRun(EcsInvalidationBatch.resource<CounterResource>()),
        isTrue,
      );
    });

    test('shouldRun respects runWhen predicate', () {
      final schedule = EcsHostSchedule(
        'app.after_action',
        runWhen: (final invalidation) =>
            invalidation.matchesResourceType(CounterResource),
      );

      expect(
        schedule.shouldRun(EcsInvalidationBatch.resource<CounterResource>()),
        isTrue,
      );
      expect(schedule.shouldRun(const EcsInvalidationBatch.empty()), isFalse);
      expect(
        schedule.shouldRun(EcsInvalidationBatch.resource<OtherResource>()),
        isFalse,
      );
    });

    test('exposes schedule name and optional invalidation metadata', () {
      const schedule = EcsHostSchedule(
        'app.resume',
        invalidation: EcsInvalidationBatch.broad(),
      );

      expect(schedule.name, 'app.resume');
      expect(schedule.invalidation?.broad, isTrue);
      expect(schedule.runWhen, isNull);
    });
  });

  test(
    'EcsInvalidationBatch merge collapses to broad when either side is broad',
    () {
      final narrow = EcsInvalidationBatch.resource<CounterResource>();
      const broad = EcsInvalidationBatch.broad();

      expect(narrow.merge(broad).broad, isTrue);
      expect(broad.merge(narrow).broad, isTrue);
    },
  );
}
