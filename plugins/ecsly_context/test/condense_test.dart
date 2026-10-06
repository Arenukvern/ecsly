import 'package:ecsly_context/ecsly_context.dart';
import 'package:test/test.dart';

void main() {
  test('live clauses are shown verbatim; settled ones are named', () {
    final segmentation = segmentText(
      'blocker: seat wedged at panel; the fold landed green. next = retest',
    );
    final condensed = condenseSegmentation(segmentation);
    expect(condensed.shown.map((final c) => c.text), <String>[
      'blocker: seat wedged at panel',
      'next = retest',
    ]);
    expect(condensed.shown.every((final c) => c.text.contains('seat') ||
        c.text.contains('retest')), isTrue);
    expect(condensed.elided.map((final c) => c.index), <int>[2]);
    expect(condensed.hasElisions, isTrue);
  });

  test('elided names compact contiguous runs and list kinds', () {
    final segmentation = segmentText('a plain fact; another fact; all done');
    final condensed = condenseSegmentation(segmentation);
    expect(condensed.shown, isEmpty);
    expect(condensed.elidedNames, 'c1-c3');
    expect(condensed.elidedKinds, 'done, fact');
  });

  test('non-contiguous elisions are named one by one', () {
    final segmentation = segmentText(
      'one plain; blocker: x; two plain. and done; next = y',
    );
    final condensed = condenseSegmentation(segmentation);
    // shown: c2 (open), c5 (action); elided: c1, c3, c4.
    expect(condensed.elidedNames, 'c1, c3-c4');
  });

  test('nothing elided: the text renders whole', () {
    final condensed = condenseSegmentation(segmentText('blocker: a; run: b'));
    expect(condensed.hasElisions, isFalse);
    expect(condensed.elidedNames, isEmpty);
  });

  test('shown clauses stay exact char spans of the source', () {
    const text = 'keep this live; drop this done. next = keep too';
    final segmentation = segmentText(text);
    final condensed = condenseSegmentation(segmentation);
    for (final clause in condensed.shown) {
      expect(
        String.fromCharCodes(
          text.codeUnits,
          clause.start,
          clause.end,
        ),
        clause.text,
      );
    }
  });
}
