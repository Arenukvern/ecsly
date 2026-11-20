import 'dart:async';

// ignore_for_file: experimental_member_use

import 'package:ecsly_flutter/ecsly_flutter.dart';
import 'package:material_ui/material_ui.dart';

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

final class TodoIdIndex {
  const TodoIdIndex._();
}

class TodoUiResource extends Resource {
  final List<String> order = <String>[];
  String? activeTodoId;
  bool showDone = true;
  bool didSeed = false;
  int nextNumber = 1;
}

class TodoAppPlugin extends Plugin {
  const TodoAppPlugin();

  @override
  String get name => 'todo_app';

  @override
  void install(World world) {
    world.components.registerObjectComponent<TodoId>();
    world.components.registerObjectComponent<TodoTitle>();
    world.components.registerObjectComponent<TodoDone>();
    world.upsertResource(TodoUiResource());
    world.upsertResource(EntityIndexResource<TodoIdIndex, String>());
  }
}

class SeedTodosAction extends EcsAction<void> {
  const SeedTodosAction();

  @override
  void run(EcsActionContext context) {
    final ui = context.readResource<TodoUiResource>();
    if (ui.didSeed) return;

    for (final title in const <String>[
      'Slice app state into components',
      'Keep resources tiny',
    ]) {
      _spawnTodo(context, title);
    }
    context.mutateResource<TodoUiResource>((ui) {
      ui.didSeed = true;
    });
  }
}

class AddTodoAction extends EcsAction<Entity> {
  const AddTodoAction();

  @override
  Entity run(EcsActionContext context) {
    final ui = context.readResource<TodoUiResource>();
    return _spawnTodo(context, 'Todo ${ui.nextNumber}');
  }
}

class ToggleTodoAction extends EcsAction<void> {
  const ToggleTodoAction(this.entity);

  final Entity entity;

  @override
  void run(EcsActionContext context) {
    final done = context.getComponent<TodoDone>(entity: entity);
    context.upsertComponent(entity, TodoDone(value: !done.value));
  }
}

class ActivateTodoAction extends EcsAction<void> {
  const ActivateTodoAction(this.entity);

  final Entity entity;

  @override
  void run(EcsActionContext context) {
    final id = context.getComponent<TodoId>(entity: entity);
    context.mutateResource<TodoUiResource>((ui) {
      ui.activeTodoId = id.value;
    });
  }
}

class ToggleDoneVisibilityAction extends EcsAction<void> {
  const ToggleDoneVisibilityAction();

  @override
  void run(EcsActionContext context) {
    context.mutateResource<TodoUiResource>((ui) {
      ui.showDone = !ui.showDone;
    });
  }
}

void main() {
  final world = buildTodoWorld();
  final controller = EcsController(world: world);

  runApp(TodoApp(world: world, controller: controller));
}

World buildTodoWorld() => World()..addPlugin(const TodoAppPlugin());

Entity _spawnTodo(EcsActionContext context, String title) {
  final ui = context.getResource<TodoUiResource>();
  final index = context.getResource<EntityIndexResource<TodoIdIndex, String>>();
  final id = 'todo-${ui.nextNumber}';
  final entity = context.spawnComponents([
    TodoId(id),
    TodoTitle(title),
    const TodoDone(value: false),
  ]);
  index.upsert(id, entity);
  context.invalidateResource<EntityIndexResource<TodoIdIndex, String>>();
  context.mutateResource<TodoUiResource>((ui) {
    ui.order.add(id);
    ui.activeTodoId ??= id;
    ui.nextNumber += 1;
  });
  return entity;
}

class TodoApp extends StatelessWidget {
  const TodoApp({required this.world, required this.controller, super.key});

  final World world;
  final EcsController controller;

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: EcsScope(
      world: world,
      controller: controller,
      child: const EcsActionOnMount(
        action: SeedTodosAction(),
        child: TodoScreen(),
      ),
    ),
  );
}

class TodoScreen extends StatelessWidget {
  const TodoScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('ecsly_flutter todos'),
      actions: <Widget>[
        EcsResourceSelector<TodoUiResource, bool>(
          select: (ui) => ui.showDone,
          builder: (context, showDone) => IconButton(
            tooltip: showDone ? 'Hide completed' : 'Show completed',
            onPressed: () => unawaited(
              context.runEcsAction(const ToggleDoneVisibilityAction()),
            ),
            icon: Icon(showDone ? Icons.visibility : Icons.visibility_off),
          ),
        ),
      ],
    ),
    body: const Column(
      children: <Widget>[
        ActiveTodoPanel(),
        Expanded(child: TodoList()),
      ],
    ),
    floatingActionButton: EcsActionBuilder<Entity>(
      action: const AddTodoAction(),
      builder: (context, status, run) => FloatingActionButton(
        onPressed: run == null ? null : () => unawaited(run()),
        child: status.isRunning
            ? const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.add),
      ),
    ),
  );
}

class ActiveTodoPanel extends StatelessWidget {
  const ActiveTodoPanel({super.key});

  @override
  Widget build(BuildContext context) => EcsWorldSelector<String?>(
    select: _selectActiveTodoLabel,
    builder: (context, label) {
      if (label == null) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(label, style: Theme.of(context).textTheme.titleMedium),
        ),
      );
    },
  );
}

String? _selectActiveTodoLabel(World world) {
  final activeId = world.getResource<TodoUiResource>().activeTodoId;
  if (activeId == null) return null;

  final entity = world
      .getResource<EntityIndexResource<TodoIdIndex, String>>()
      .maybeEntityOf(activeId);
  if (entity == null) return null;

  final title = world.maybeGetComponent<TodoTitle>(entity);
  final done = world.maybeGetComponent<TodoDone>(entity);
  if (title == null || done == null) return null;
  return '${done.value ? 'Done' : 'Active'}: ${title.value}';
}

class TodoList extends StatelessWidget {
  const TodoList({super.key});

  @override
  Widget build(BuildContext context) => EcsWorldSelector<List<Entity>>(
    select: _selectVisibleTodos,
    equals: _sameEntities,
    builder: (context, entities) => ListView.builder(
      itemCount: entities.length,
      itemBuilder: (context, index) =>
          TodoTile(entity: entities[index]),
    ),
  );
}

List<Entity> _selectVisibleTodos(World world) {
  final ui = world.getResource<TodoUiResource>();
  final index = world.getResource<EntityIndexResource<TodoIdIndex, String>>();
  final visible = <Entity>[];
  for (final id in ui.order) {
    final entity = index.maybeEntityOf(id);
    if (entity == null) continue;
    final done = world.maybeGetComponent<TodoDone>(entity);
    if (done == null) continue;
    if (!ui.showDone && done.value) continue;
    visible.add(entity);
  }
  return List<Entity>.unmodifiable(visible);
}

bool _sameEntities(List<Entity> previous, List<Entity> next) {
  if (identical(previous, next)) return true;
  if (previous.length != next.length) return false;
  for (var i = 0; i < previous.length; i += 1) {
    if (previous[i] != next[i]) return false;
  }
  return true;
}

class TodoTile extends StatelessWidget {
  const TodoTile({required this.entity, super.key});

  final Entity entity;

  @override
  Widget build(BuildContext context) =>
      EcsComponentSelector<TodoDone, bool>(
        entity: entity,
        select: (done) => done.value,
        builder: (context, done) =>
            EcsComponentSelector<TodoTitle, String>(
              entity: entity,
              select: (title) => title.value,
              builder: (context, title) => CheckboxListTile(
                value: done,
                onChanged: (_) {
                  unawaited(context.runEcsAction(ActivateTodoAction(entity)));
                  unawaited(context.runEcsAction(ToggleTodoAction(entity)));
                },
                title: Text(title),
              ),
            ),
      );
}
