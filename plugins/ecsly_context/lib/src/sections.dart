/// Mechanical markdown section structure: THE fence-aware ATX scan.
///
/// One implementation for every consumer that must agree byte-exact on
/// where a section starts and ends — the splice emitter and the span
/// resolver previously carried twin scans whose agreement was enforced
/// only by tests (run 18). The scan is pure: content in, byte-offset
/// spans out; no I/O, no world, no model. Product-agnostic like the
/// clause grammar — any tool that names `path#anchor` targets resolves
/// them through the same primitives.
///
/// Laws carried over unchanged:
/// - ATX headings only (`#`..`######`); setext forms are honestly
///   skipped;
/// - code fences (``` / ~~~) are INERT (ADR 0019): a `#` line inside a
///   fence is content, never a heading;
/// - a heading's initial span ends at the next heading of ANY level; the
///   OWNING section's body (nested subsections included) ends at the
///   next heading of level ≤ its own — [mdSectionBodyEnd];
/// - anchors match on normalized titles ([normalizeMdHeading]:
///   whitespace collapsed, case-folded) — formatting variance never
///   invents an absence.
library;

/// One parsed heading's span: pure data, byte offsets into the source.
final class MdSectionSpan {
  /// Creates a span. [end] is the next heading's start (or the content
  /// end); the OWNING body's end comes from [mdSectionBodyEnd].
  const MdSectionSpan({
    required this.ordinal,
    required this.level,
    required this.title,
    required this.start,
    required this.headingEnd,
    required this.end,
    required this.line,
  });

  /// 1-based among the file's headings (stable node-id tail).
  final int ordinal;

  /// Heading level 1..6 (the `#` count).
  final int level;

  /// The heading title as written (trimmed of `#` suffix noise).
  final String title;

  /// Byte offset of the heading line start.
  final int start;

  /// Byte offset just past the heading line's newline (splice origin for
  /// replace — the heading line itself is preserved byte-for-byte).
  final int headingEnd;

  /// Byte offset of the section end (next heading line start, or EOF).
  final int end;

  /// 1-based source line of the heading.
  final int line;
}

final RegExp _headingLine = RegExp(r'^(#{1,6})\s+(.*?)\s*#*\s*$');
final RegExp _fenceLine = RegExp(r'^\s*(```|~~~)');

/// Parses ATX headings into the flat section list. Byte-exact with the
/// fs-tier map builder and the host span resolver (they delegate here).
List<MdSectionSpan> parseMdSectionSpans(final String content) {
  final headings = <(int, int, int, String, int)>[]; // start, len, lvl, title, line
  var offset = 0;
  var lineNumber = 0;
  var inFence = false;
  for (final line in content.split('\n')) {
    lineNumber += 1;
    final lineStart = offset;
    offset += line.length + 1;
    if (_fenceLine.hasMatch(line)) {
      inFence = !inFence; // ``` and ~~~ toggle (an opening fence's marker)
      continue;
    }
    if (inFence) continue; // fences are INERT (ADR 0019)
    final match = _headingLine.firstMatch(line);
    if (match == null) continue;
    headings.add((
      lineStart,
      line.length,
      match.group(1)!.length,
      match.group(2)!,
      lineNumber,
    ));
  }
  return <MdSectionSpan>[
    for (var i = 0; i < headings.length; i++)
      () {
        final (start, length, level, title, line) = headings[i];
        var headingEnd = start + length + 1;
        if (headingEnd > content.length) headingEnd = content.length;
        return MdSectionSpan(
          ordinal: i + 1,
          level: level,
          title: title,
          start: start,
          headingEnd: headingEnd,
          end: i + 1 < headings.length ? headings[i + 1].$1 : content.length,
          line: line,
        );
      }(),
  ];
}

/// The byte end of the section OWNED by heading [index]: the next heading
/// of level ≤ its own (nested subsections stay inside the parent), or
/// [contentEnd] when none follows. This is the replace_section boundary.
int mdSectionBodyEnd(
  final List<MdSectionSpan> sections,
  final int index,
  final int contentEnd,
) {
  final level = sections[index].level;
  for (var i = index + 1; i < sections.length; i++) {
    if (sections[i].level <= level) {
      return sections[i].start;
    }
  }
  return contentEnd;
}

/// Normalizes a heading for mechanical anchor matching: whitespace runs
/// collapse to one space, edges trim, case folds — identical to
/// replace-then-lowercase, expressed without the rewrite primitives the
/// design law bans.
String normalizeMdHeading(final String raw) => RegExp(r'\S+')
    .allMatches(raw)
    .map((final match) => match.group(0)!.toLowerCase())
    .join(' ');

/// A `path#anchor` span target, split and validated. Null when malformed:
/// no `#`, an empty side, or nothing but whitespace around them.
/// Backtick-wrapped authors are cleaned first (prose slots wrap targets).
(String, String)? parseMdSpanTarget(final String span) {
  final withoutBackticks = span.trim().split('`').join('').trim();
  final hash = withoutBackticks.indexOf('#');
  if (hash <= 0 || hash == withoutBackticks.length - 1) {
    return null;
  }
  final units = withoutBackticks.codeUnits;
  final file = String.fromCharCodes(units, 0, hash).trim();
  final anchor = String.fromCharCodes(units, hash + 1).trim();
  if (file.isEmpty || anchor.isEmpty) {
    return null;
  }
  return (file, anchor);
}
