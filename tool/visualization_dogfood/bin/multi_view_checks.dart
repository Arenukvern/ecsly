import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:universal_browser_cdp/universal_browser_cdp.dart';
import 'package:universal_automation_interface/universal_automation_interface.dart';

Future<Map<String, Object?>> qualifyMultiView(
  CdpPage page,
  Directory output,
  List<Map<String, Object?>> checks,
) async {
  final driver = CdpDriver(page);
  final targeting = CdpSemanticTargeting(page);
  Future<void> waitFor(Future<bool> Function() predicate) async {
    final clock = Stopwatch()..start();
    const budget = Duration(seconds: 30);
    while (clock.elapsed < budget) {
      if (await predicate().timeout(budget - clock.elapsed)) return;
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    throw TimeoutException('Multi-view projection was not observed', budget);
  }

  Future<Map<String, dynamic>> view(String id) async => jsonDecode(
    await page.evaluate('window.__ecslyViewerState(${jsonEncode(id)})')
        as String,
  ) as Map<String, dynamic>;
  Future<List<dynamic>> ids() async =>
      jsonDecode(await page.evaluate('window.__ecslyViewerViews()') as String)
          as List<dynamic>;
  Future<Map<String, dynamic>> states() async => {
    for (final id in await ids()) id as String: await view(id),
  };
  Future<bool> rendered(String id) async {
    final startup = (await view(id))['startup'] as Map?;
    final marks = startup?['marksUs'] as Map?;
    return (marks?['firstSceneRenderReturned'] is num ||
            marks?['firstCanvasPaintReturned'] is num) &&
        marks?['firstWidgetFrameCompleted'] is num;
  }

  Future<void> require(bool condition, String description) async {
    if (!condition) throw StateError(description);
    checks.add({'action': description, 'effect': 'observed'});
  }

  await waitFor(() async => (await ids()).join(',') == 'alpha,beta');
  await waitFor(() async => await rendered('alpha') && await rendered('beta'));
  final initial = await states();
  await require(
    await page.evaluate('''(() => {
    try { window.__ecslyViewerState(); return false; } catch (error) { return String(error).includes('viewer_address_required'); }
  })()''') ==
        true,
    'unaddressed state refuses two mounted viewers',
  );
  await require(
    await page.evaluateAsync('window.__mcpActions.host_probe.invoke()') ==
        'host',
    'embedding host action catalog preserved',
  );

  Future<void> apply(String id, String title) async {
    final before = await view(id);
    final document = Map<String, dynamic>.from(before['document'] as Map);
    final effect = await verifyEffect(
      dispatch: () => driver.perform(
        InvokeAction(
          'viewer_apply',
          args: {
            'viewerId': id,
            'requestId': 'same-request-in-two-worlds',
            'expectedRevision': document['revision'],
            'document': jsonEncode({
              ...document,
              'revision': 2,
              'title': title,
            }),
          },
        ),
      ),
      observe: states,
      changed: (a, b) => (b[id] as Map)['presentedRevision'] == 2,
      timeout: const Duration(seconds: 15),
    );
    if (!effect.verified) throw StateError('Addressed apply not observed: $id');
    checks.add({
      'action': 'apply $id',
      'delivery': effect.delivery.name,
      'effect': effect.effect.name,
      'frameUs': (effect.after[id] as Map)['dataToFlutterFrameUs'],
    });
  }

  await apply('alpha', 'Independent alpha');
  await require(
    jsonEncode((await states())['beta']) == jsonEncode(initial['beta']),
    'alpha document leaves beta state unchanged',
  );

  final zoom = await verifyEffect(
    dispatch: () => targeting.clickTarget(
      const SemanticTarget(
        role: 'button',
        name: 'Zoom in',
        scope: [SemanticTarget(name: 'Visualization viewer alpha')],
      ),
    ),
    observe: states,
    changed: (a, b) =>
        (b['alpha'] as Map)['distance'] != (a['alpha'] as Map)['distance'],
    timeout: const Duration(seconds: 10),
  );
  if (!zoom.verified)
    throw StateError('Scoped alpha zoom not observed: ${zoom.dispatchError}');
  await require(
    (zoom.after['beta'] as Map)['distance'] ==
        (initial['beta'] as Map)['distance'],
    'scoped pointer changes alpha camera only',
  );
  await targeting.clickTarget(
    const SemanticTarget(
      role: 'button',
      name: 'Save checkpoint',
      scope: [SemanticTarget(name: 'Visualization viewer alpha')],
    ),
  );
  await waitFor(
    () async =>
        await page.evaluate(
          'Object.keys(localStorage).some(k => k.endsWith("preview.snapshot.alpha"))',
        ) ==
        true,
  );
  final alphaBeforeRemoval = await view('alpha');
  final betaBeforeRemoval = await view('beta');
  await File('${output.path}/multi-view.png')
      .writeAsBytes(await driver.screenshot());
  await page.evaluate(
    '''window.__ecslyEngine.removeView(Number(
    document.querySelector('[data-ecsly-viewer="alpha"]').dataset.flutterViewId))''',
  );
  await waitFor(() async => (await ids()).join(',') == 'beta');
  await require(
    await page.evaluate('''(() => {
    try { window.__ecslyViewerState('alpha'); return false; } catch (error) { return String(error).includes('viewer_not_mounted'); }
  })()''') ==
        true,
    'removed alpha state refuses access',
  );
  await require(
    jsonEncode(await view('beta')) == jsonEncode(betaBeforeRemoval),
    'removal preserves beta runtime camera selection and document',
  );
  await apply('beta', 'Independent beta');
  final remountClock = Stopwatch()..start();
  await page.evaluate('''(() => {
    const host = document.querySelector('[data-ecsly-viewer="alpha"]');
    host.dataset.flutterViewId = String(window.__ecslyEngine.addView({
      hostElement: host, initialData: {viewerId:'alpha'}}));
  })()''');
  await waitFor(() async => (await ids()).join(',') == 'alpha,beta');
  await waitFor(() async => await rendered('alpha'));
  final remountRenderObservedUs = remountClock.elapsedMicroseconds;
  final remounted = await states();
  final alpha = remounted['alpha'] as Map;
  await require(
    alpha['runtimeId'] != alphaBeforeRemoval['runtimeId'] &&
        alpha['applyCount'] == 0 &&
        alpha['distance'] == alphaBeforeRemoval['distance'],
    'remount creates a new world and restores only its checkpoint',
  );
  await require(
    (remounted['beta'] as Map)['runtimeId'] == betaBeforeRemoval['runtimeId'] &&
        ((remounted['beta'] as Map)['document'] as Map)['title'] ==
            'Independent beta',
    'remount leaves beta resident revision intact',
  );
  await waitFor(() async => await rendered('alpha') && await rendered('beta'));
  await File('${output.path}/multi-view-remounted.png')
      .writeAsBytes(await driver.screenshot());
  final warmSamples = <Map<String, Object?>>[
    {
      'runtimeId': alpha['runtimeId'],
      'startup': alpha['startup'],
      'hostRequestToRenderObservedUs': remountRenderObservedUs,
    },
  ];
  for (var sample = 2; sample <= 5; sample++) {
    final before = await states();
    final removalClock = Stopwatch()..start();
    await page.evaluate(
      '''window.__ecslyEngine.removeView(Number(
      document.querySelector('[data-ecsly-viewer="alpha"]').dataset.flutterViewId))''',
    );
    await waitFor(() async => (await ids()).join(',') == 'beta');
    final removalObservedUs = removalClock.elapsedMicroseconds;
    final sampleClock = Stopwatch()..start();
    await page.evaluate('''(() => {
      const host = document.querySelector('[data-ecsly-viewer="alpha"]');
      host.dataset.flutterViewId = String(window.__ecslyEngine.addView({
        hostElement: host, initialData: {viewerId:'alpha'}}));
    })()''');
    await waitFor(() async => (await ids()).join(',') == 'alpha,beta');
    await waitFor(() async => await rendered('alpha'));
    final observedUs = sampleClock.elapsedMicroseconds;
    final after = await states();
    final current = after['alpha'] as Map;
    await require(
      current['runtimeId'] != (before['alpha'] as Map)['runtimeId'] &&
          current['distance'] == alphaBeforeRemoval['distance'] &&
          jsonEncode(after['beta']) == jsonEncode(before['beta']),
      'warm remount $sample restores alpha checkpoint and preserves beta',
    );
    warmSamples.add({
      'runtimeId': current['runtimeId'],
      'startup': current['startup'],
      'hostRequestToRenderObservedUs': observedUs,
      'hostRemovalObservedUs': removalObservedUs,
    });
  }
  await File('${output.path}/multi-view-final.png')
      .writeAsBytes(await driver.screenshot());
  final startupCohort = {
    'schema': 1,
    'initial': {
      for (final id in ['alpha', 'beta'])
        id: {
          'runtimeId': (initial[id] as Map)['runtimeId'],
          'startup': (initial[id] as Map)['startup'],
        },
    },
    'remountedAlpha': {
      'runtimeId': alpha['runtimeId'],
      'startup': alpha['startup'],
      'hostRequestToRenderObservedUs': remountRenderObservedUs,
    },
    'warmSamples': warmSamples,
    'limit': 'One engine; initial views overlap loading. Render return and host observation are separate clocks, neither is a compositor-present timestamp.',
  };
  await File('${output.path}/startup-cohort.json')
      .writeAsString(const JsonEncoder.withIndent('  ').convert(startupCohort));
  return {
    'views': await states(),
    'compilerInvocationsDuringApply': 0,
    'startupCohort': startupCohort,
    'note': 'One engine, two physical Flutter views. Captures require independent inspection.',
  };
}
