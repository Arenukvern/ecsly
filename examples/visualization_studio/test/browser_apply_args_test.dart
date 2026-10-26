import 'package:flutter_test/flutter_test.dart';

import 'package:ecsly_visualization_studio/browser_apply_args.dart';

void main() {
  test('browser numeric representations normalize without mutating caller', () {
    final input = <String, Object?>{'expectedRevision': 2.0, 'requestId': 'r'};
    final result = browserApplyArgs(input);
    expect(result['expectedRevision'], isA<int>());
    expect(result['expectedRevision'], 2);
    expect(input['expectedRevision'], isA<double>());
    expect(result['requestId'], 'r');
    expect(browserApplyArgs({'expectedRevision': 2})['expectedRevision'], 2);
  });
  test('fractional, nonfinite, unsafe and nonnumeric revisions refuse', () {
    for (final value in [
      1.5,
      double.nan,
      double.infinity,
      9007199254740992,
      -1,
      '2',
      null,
    ]) {
      expect(
        () => browserApplyArgs({'expectedRevision': value}),
        throwsFormatException,
      );
    }
  });
}
