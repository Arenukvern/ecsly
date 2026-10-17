import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_mcp_harness/flutter_mcp_harness.dart';
import 'package:universal_browser_cdp/universal_browser_cdp.dart';

/// Frozen consumer-specific oracle over the existing shared automation family.
/// The analytical reference is independent of either candidate's solver.
Future<Map<String, dynamic>> qualifyDampedOscillator(
  CdpPage page,
  Directory output,
  List<Map<String, Object?>> checks,
) async {
  final driver = CdpDriver(page);
  Future<Map<String, dynamic>> state() async => jsonDecode(
    await page.evaluate('JSON.stringify(window.__dampedState())') as String,
  ) as Map<String, dynamic>;
  double number(Map<String, dynamic> value, String key) {
    final n = value[key];
    if (n is! num || !n.isFinite) throw StateError('Invalid $key: $n');
    return n.toDouble();
  }

  void near(
    double actual,
    double expected,
    String label, [
    double tolerance = 1e-5,
  ]) {
    if ((actual - expected).abs() > tolerance) {
      throw StateError('$label: $actual != $expected (tolerance $tolerance)');
    }
  }

  void initial(Map<String, dynamic> value, double damping) {
    near(number(value, 'time'), 0, 'initial time');
    near(number(value, 'damping'), damping, 'damping');
    near(number(value, 'displacement'), 1, 'initial displacement');
    near(number(value, 'velocity'), 0, 'initial velocity');
    near(number(value, 'energy'), 2 * math.pi * math.pi, 'initial energy');
    if (value['selectedIndex'] != 0)
      throw StateError('Selection did not reset');
  }

  Future<void> click(
    String name,
    bool Function(Map<String, dynamic>, Map<String, dynamic>) changed,
  ) async {
    final receipt = await verifyEffect(
      dispatch: () =>
          CdpSemanticTargeting(page)
              .clickTarget(SemanticTarget(role: 'button', name: name)),
      observe: state,
      changed: changed,
      timeout: const Duration(seconds: 5),
      dispatchTimeout: const Duration(seconds: 4),
    );
    checks.add({
      'action': name,
      'delivery': receipt.delivery.name,
      'effect': receipt.effect.name,
      'before': receipt.before,
      'after': receipt.after,
      'dispatchError': receipt.dispatchError,
      'observationError': receipt.observationError,
    });
    if (!receipt.verified) throw StateError('Effect failed: $name');
  }

  await FlutterWebCdp(page, driver).waitForSemantics();
  final before = await state();
  initial(before, .3);
  await Future<void>.delayed(const Duration(milliseconds: 200));
  if (jsonEncode(before) != jsonEncode(await state())) {
    throw StateError('Initial paused state advanced');
  }
  checks.add({'action': 'initial paused state', 'effect': 'state unchanged'});
  await File('${output.path}/initial.png')
      .writeAsBytes(await driver.screenshot());
  // Reset is first made observable by advancing time before each preset.
  for (final preset in {
    'Undamped': 0.0,
    'Light damping': .3,
    'Overdamped': 1.2,
  }.entries) {
    await click('Step 1/60 s', (a, b) => number(b, 'time') > number(a, 'time'));
    await click(
      preset.key,
      (a, b) => number(a, 'time') > 0 && number(b, 'time') == 0,
    );
    initial(await state(), preset.value);
    await click('Step 1/60 s', (a, b) => number(b, 'time') > number(a, 'time'));
    final current = await state();
    const t = 1 / 60;
    near(number(current, 'time'), t, 'fixed step');
    final (x, v) = _analytical(preset.value, t);
    near(
      number(current, 'displacement'),
      x,
      '${preset.key} displacement',
      .003,
    );
    near(number(current, 'velocity'), v, '${preset.key} velocity', .003);
    final observedX = number(current, 'displacement');
    final observedV = number(current, 'velocity');
    near(
      number(current, 'energy'),
      (observedV * observedV + 4 * math.pi * math.pi * observedX * observedX) /
          2,
      'energy units',
    );
    checks.add({
      'action': '${preset.key} analytical reference',
      'effect': 'observed',
      'expectedDisplacement': x,
      'expectedVelocity': v,
      'tolerance': .003,
    });
  }
  await click('Next sample', (a, b) => b['selectedIndex'] == 1);
  final linked = await state();
  final selection = linked['plotSelection'] as Map;
  if (selection['time'] != 1 || selection['phase'] != 1) {
    throw StateError('Plots have independent selection');
  }
  bool containsSample(AxNode node) =>
      (node.name?.contains('Sample 1') ?? false) ||
      node.children.any(containsSample);
  final snapshot = await retry(
    () async {
      final observed = await driver.snapshot();
      return observed.roots.any(containsSample) ? observed : null;
    },
    attempts: 60,
    delay: const Duration(milliseconds: 50),
  ).timeout(const Duration(seconds: 4));
  if (snapshot == null) throw StateError('Visible Sample 1 label missing');
  await File('${output.path}/linked.png')
      .writeAsBytes(await driver.screenshot());
  await File('${output.path}/linked-ax.json')
      .writeAsString(jsonEncode(snapshot.toJson()));
  await click(
    'Reset',
    (a, b) => number(a, 'time') > 0 && number(b, 'time') == 0,
  );
  initial(await state(), 1.2);
  await page.connection.send('Emulation.setDeviceMetricsOverride', {
    'width': 320,
    'height': 1000,
    'deviceScaleFactor': 1,
    'mobile': false,
  });
  await page.evaluateAsync(
    'new Promise(r => requestAnimationFrame(() => requestAnimationFrame(r)))',
  );
  await File('${output.path}/narrow.png')
      .writeAsBytes(await driver.screenshot());
  await File('${output.path}/narrow-ax.json')
      .writeAsString(jsonEncode((await driver.snapshot()).toJson()));
  return state();
}

(double, double) _analytical(double zeta, double t) {
  final omega = 2 * math.pi;
  if (zeta < 1) {
    final wd = omega * math.sqrt(1 - zeta * zeta);
    final decay = math.exp(-zeta * omega * t);
    return (
      decay * (math.cos(wd * t) + zeta * omega / wd * math.sin(wd * t)),
      -omega * omega / wd * decay * math.sin(wd * t),
    );
  }
  final root = omega * math.sqrt(zeta * zeta - 1);
  final r1 = -zeta * omega + root, r2 = -zeta * omega - root;
  final e1 = math.exp(r1 * t), e2 = math.exp(r2 * t);
  return ((-r2 * e1 + r1 * e2) / (r1 - r2), r1 * r2 * (e2 - e1) / (r1 - r2));
}
