import 'context_exception.dart';

final RegExp _isoDatePattern = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');

/// Validates [date] as a real ISO calendar date (`yyyy-mm-dd`) and returns
/// it unchanged.
///
/// Throws [InvalidDateException] when the shape or the calendar date is
/// invalid (for example `2026-02-31`). Text is never transformed: a valid
/// date comes back byte-identical.
String validateIsoDate(final String date) {
  final match = _isoDatePattern.firstMatch(date);
  if (match == null) {
    throw InvalidDateException(date);
  }
  final year = int.parse(match.group(1)!);
  final month = int.parse(match.group(2)!);
  final day = int.parse(match.group(3)!);
  final candidate = DateTime(year, month, day);
  if (candidate.year != year ||
      candidate.month != month ||
      candidate.day != day) {
    throw InvalidDateException(date);
  }
  return date;
}
