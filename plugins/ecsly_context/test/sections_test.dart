import 'package:ecsly_context/ecsly_context.dart';
import 'package:test/test.dart';

void main() {
  group('parseMdSectionSpans', () {
    test('byte-exact spans: heading line preserved on replace', () {
      const content = '# Title\n\n## First\n\nalpha.\n\n## Last\n\nomega.\n';
      final sections = parseMdSectionSpans(content);
      expect(sections, hasLength(3));
      // The heading line's own bytes: start through headingEnd.
      expect(content.substring(sections[1].start, sections[1].headingEnd),
          '## First\n');
      // A section's initial span ends at the next heading of ANY level.
      expect(sections[0].end, sections[1].start);
      expect(sections.last.end, content.length);
      expect(sections.map((final s) => s.line), <int>[1, 3, 7]);
      expect(sections.map((final s) => s.ordinal), <int>[1, 2, 3]);
    });

    test('fences are inert: a # line inside ``` is content', () {
      const content = '## Real\n\n```md\n## Not a heading\n```\n\n## Tail\n';
      final sections = parseMdSectionSpans(content);
      expect(sections.map((final s) => s.title), <String>['Real', 'Tail']);
      // The fenced impostor's bytes stay inside the owning section.
      expect(content.substring(sections[0].start, sections[0].end),
          contains('## Not a heading'));
    });

    test('tilde fences toggle too', () {
      const content = '## A\n\n~~~\n## hidden\n~~~\n\n## B\n';
      expect(parseMdSectionSpans(content).map((final s) => s.title),
          <String>['A', 'B']);
    });

    test('setext forms are skipped; empty titles are kept', () {
      const content = 'Setext\n------\n\n## \n\nbody\n';
      final sections = parseMdSectionSpans(content);
      expect(sections, hasLength(1));
      expect(sections.single.title, isEmpty);
      expect(sections.single.level, 2);
    });

    test('the owning body ends at the next heading of level ≤ own', () {
      const content = '## Parent\n\ntext\n\n### Nested\n\nnested\n\n## Next\n';
      final sections = parseMdSectionSpans(content);
      // Flat spans: Parent ends where Nested begins.
      expect(sections[0].end, sections[1].start);
      // The OWNED body: nested stays inside; Next (level 2 ≤ 2) closes.
      expect(mdSectionBodyEnd(sections, 0, content.length),
          sections[2].start);
      expect(mdSectionBodyEnd(sections, 1, content.length),
          sections[2].start);
      expect(mdSectionBodyEnd(sections, 2, content.length), content.length);
    });
  });

  group('anchors and targets', () {
    test('normalization collapses whitespace and case', () {
      expect(normalizeMdHeading('  First   Section  '), 'first section');
      expect(normalizeMdHeading('First\tsection'), 'first section');
      expect(
        normalizeMdHeading('First section'),
        normalizeMdHeading('first  SECTION'),
      );
    });

    test('path#anchor targets split and validate', () {
      expect(parseMdSpanTarget('docs/design.mdx#Original title'),
          ('docs/design.mdx', 'Original title'));
      expect(parseMdSpanTarget('`docs/design.mdx#Original title`'),
          ('docs/design.mdx', 'Original title'));
      expect(parseMdSpanTarget('docs/design.mdx'), isNull);
      expect(parseMdSpanTarget('#anchor-only'), isNull);
      expect(parseMdSpanTarget('docs/design.mdx#'), isNull);
      expect(parseMdSpanTarget('no anchor here'), isNull);
    });
  });
}
