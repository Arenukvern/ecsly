import 'package:ecsly_flutter/ecsly_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Choice extends Resource {
  int value = 1;
}

class _Unrelated extends Resource {}

void main() {
  testWidgets(
    'cached selection follows Flutter theme without ECS value change',
    (final tester) async {
      final world = World()
        ..upsertResource(_Choice())
        ..upsertResource(_Unrelated());
      world.flush();
      final controller = EcsController(world: world);
      final dark = ValueNotifier(false);
      var builds = 0;
      final lightTheme = ThemeData.light();
      final darkTheme = ThemeData.dark();
      final selector = EcsResourceSelector<_Choice, int>(
        world: world,
        controller: controller,
        select: (final choice) => choice.value,
        builder: (final context, final value) {
          builds++;
          return ColoredBox(
            key: const ValueKey('selected-ink'),
            color: Theme.of(context).colorScheme.onSurface,
            child: Text('$value'),
          );
        },
      );
      await tester.pumpWidget(
        ValueListenableBuilder<bool>(
          valueListenable: dark,
          child: selector,
          builder: (final context, final isDark, final child) => MaterialApp(
            theme: isDark ? darkTheme : lightTheme,
            themeAnimationDuration: Duration.zero,
            home: child,
          ),
        ),
      );
      expect(
        tester
            .widget<ColoredBox>(find.byKey(const ValueKey('selected-ink')))
            .color,
        lightTheme.colorScheme.onSurface,
      );
      final baseline = builds;
      controller.notifyWorldChanged(
        invalidation: EcsInvalidationBatch.resource<_Unrelated>(),
      );
      await tester.pump();
      expect(builds, baseline);
      dark.value = true;
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<ColoredBox>(find.byKey(const ValueKey('selected-ink')))
            .color,
        darkTheme.colorScheme.onSurface,
      );
      expect(world.getResource<_Choice>().value, 1);
      await tester.pumpWidget(const SizedBox());
      dark.dispose();
      controller.dispose();
    },
  );
}
