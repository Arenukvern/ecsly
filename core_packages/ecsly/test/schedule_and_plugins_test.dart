import 'package:ecsly/ecsly.dart';
import 'package:test/test.dart';

class CountingPlugin extends Plugin {
  const CountingPlugin(this.name, this.installs, this.uninstalls);

  @override
  final String name;
  final List<String> installs;
  final List<String> uninstalls;

  @override
  void install(final World world) {
    installs.add(name);
  }

  @override
  void uninstall(final World world) {
    uninstalls.add(name);
  }
}

void main() {
  group('Schedule and plugins', () {
    test('then() and runAfter/runBefore produce expected order', () {
      final world = World();
      final calls = <String>[];

      final schedule = Schedule('Order')
        ..add((final _) => calls.add('a'), name: 'a')
        ..then((final _) => calls.add('b'), name: 'b')
        ..add((final _) => calls.add('c'), name: 'c', runAfter: const ['b'])
        ..add((final _) => calls.add('d'), name: 'd', runBefore: const ['c']);

      schedule.run(world);

      expect(calls.indexOf('a'), lessThan(calls.indexOf('b')));
      expect(calls.indexOf('b'), lessThan(calls.indexOf('c')));
      expect(calls.indexOf('d'), lessThan(calls.indexOf('c')));
    });

    test('cycle detection throws CircularDependencyError with cycle info', () {
      final schedule = Schedule('Cycle')
        ..add((final _) {}, name: 'a', runAfter: const ['c'])
        ..add((final _) {}, name: 'b', runAfter: const ['a'])
        ..add((final _) {}, name: 'c', runAfter: const ['b']);

      expect(
        () => schedule.run(World()),
        throwsA(
          isA<CircularDependencyError>().having(
            (final e) => e.cycle,
            'cycle',
            isNotEmpty,
          ),
        ),
      );
    });

    test('parallel grouping preserves dependency levels', () {
      final world = World();
      final calls = <String>[];

      void p1(final World _) {
        calls.add('p1');
      }

      void p2(final World _) {
        calls.add('p2');
      }

      final schedule = Schedule('Parallel')
        ..add((final _) => calls.add('start'), name: 'start')
        ..parallel([p1, p2], mode: ExecutionMode.sync)
        ..add(
          (final _) => calls.add('end'),
          name: 'end',
          runAfter: const ['start'],
        );

      schedule.run(world);

      expect(calls.first, 'start');
      expect(calls, containsAll(['p1', 'p2']));
      expect(calls.indexOf('start'), lessThan(calls.indexOf('end')));
    });

    test('plugin registry rejects duplicates and uninstalls exactly once', () {
      final world = World();
      final installs = <String>[];
      final uninstalls = <String>[];

      final plugin = CountingPlugin('test.plugin', installs, uninstalls);
      world.addPlugin(plugin);
      expect(world.hasPlugin('test.plugin'), isTrue);

      expect(
        () => world.addPlugin(
          CountingPlugin('test.plugin', installs, uninstalls),
        ),
        throwsA(isA<PluginInstallationException>()),
      );

      expect(world.removePlugin('test.plugin'), isTrue);
      expect(world.removePlugin('test.plugin'), isFalse);
      expect(uninstalls.where((final p) => p == 'test.plugin').length, 1);
    });

    test('addPluginIfAbsent installs once without replacing', () {
      final world = World();
      final installs = <String>[];
      final uninstalls = <String>[];

      expect(
        world.addPluginIfAbsent(
          CountingPlugin('test.plugin', installs, uninstalls),
        ),
        isTrue,
      );
      expect(
        world.addPluginIfAbsent(
          CountingPlugin('test.plugin', installs, uninstalls),
        ),
        isFalse,
      );

      expect(installs, ['test.plugin']);
      expect(uninstalls, isEmpty);
      expect(world.hasPlugin('test.plugin'), isTrue);
    });
  });
}
