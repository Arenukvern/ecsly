import 'package:ecsly_app/ecsly_app.dart';

class CounterResource extends Resource {
  CounterResource(this.value);

  int value;
}

class IncrementAction extends EcsAction<int> {
  const IncrementAction();

  @override
  int run(final EcsActionContext context) {
    context.mutateResource<CounterResource>((final counter) {
      counter.value += 1;
    });
    return context.getResource<CounterResource>().value;
  }
}

Future<void> main() async {
  final world = World()..upsertResource(CounterResource(0));
  final runner = EcsActionRunner(world: world);
  final invalidations = <EcsInvalidationBatch>[];

  final result = await runner.run(
    const IncrementAction(),
    onChanged: ({final flush = true, final invalidation}) {
      invalidations.add(invalidation ?? const EcsInvalidationBatch.broad());
      if (flush) world.flush();
    },
  );

  final status = runner.actionStatusOf(IncrementAction);
  final lastInvalidation = invalidations.last;

  assert(result == 1, 'Action should return the updated counter value.');
  assert(
    world.getResource<CounterResource>().value == 1,
    'World resource should reflect the mutation.',
  );
  assert(status.hasSucceeded, 'Runner should record succeeded status.');
  assert(
    lastInvalidation.matchesResourceType(CounterResource),
    'Mutation helper should emit a narrow resource invalidation hint.',
  );
  assert(lastInvalidation.broad == false, 'Hint should not be broad.');
}
