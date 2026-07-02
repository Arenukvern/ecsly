import 'package:ecsly/ecsly.dart';
import 'package:meta/meta.dart';

typedef EcsValueEquals<T> = bool Function(T previous, T next);

/// Field-level edit metadata for an [EcsDraft].
@immutable
class EcsFieldState {
  const EcsFieldState({this.touched = false, this.error});

  final bool touched;
  final String? error;

  bool get hasError => error != null && error!.isNotEmpty;

  EcsFieldState copyWith({
    final bool? touched,
    final String? error,
    final bool clearError = false,
  }) => EcsFieldState(
    touched: touched ?? this.touched,
    error: clearError ? null : error ?? this.error,
  );
}

/// Headless edit draft with dirty, touched, and validation metadata.
///
/// Drafts deliberately do not own Flutter controllers. Widgets may bind text
/// fields to this state, while systems/actions remain testable without a
/// widget tree.
class EcsDraft<T> {
  EcsDraft({
    required this.original,
    final T? current,
    final EcsValueEquals<T>? equals,
  }) : current = current ?? original,
       _equals = equals == null
           ? null
           : ((final previous, final next) => equals(previous as T, next as T));

  T original;
  T current;
  final bool Function(Object? previous, Object? next)? _equals;
  final Map<Object, EcsFieldState> _fields = <Object, EcsFieldState>{};

  bool get isDirty => !_same(original, current);

  bool get hasErrors => _fields.values.any((final field) => field.hasError);

  Map<Object, EcsFieldState> get fields => Map.unmodifiable(_fields);

  EcsFieldState field(final Object key) =>
      _fields[key] ?? const EcsFieldState();

  void touch(final Object key) {
    _fields[key] = field(key).copyWith(touched: true);
  }

  void setFieldError(final Object key, final String? error) {
    _fields[key] = field(key).copyWith(error: error, clearError: error == null);
  }

  void clearField(final Object key) {
    _fields.remove(key);
  }

  void reset() {
    current = original;
    _fields.clear();
  }

  void commit([final T? value]) {
    if (value != null) {
      current = value;
    }
    original = current;
    _fields.clear();
  }

  void rebase(final T newOriginal, {final bool keepCurrent = true}) {
    original = newOriginal;
    if (!keepCurrent) {
      current = newOriginal;
      _fields.clear();
    }
  }

  bool _same(final T previous, final T next) =>
      _equals?.call(previous, next) ?? previous == next;
}

/// Resource that stores active drafts by app-defined key.
///
/// Keep keys stable and domain-owned, such as `('coffee', coffeeId)`.
class EcsDraftsResource extends Resource {
  final Map<Object, Object> _drafts = <Object, Object>{};

  bool hasDraft(final Object key) => _drafts.containsKey(key);

  EcsDraft<T>? maybeDraft<T>(final Object key) {
    final draft = _drafts[key];
    if (draft == null) return null;
    return draft as EcsDraft<T>;
  }

  EcsDraft<T> draft<T>(
    final Object key, {
    required final T original,
    final T? current,
    final EcsValueEquals<T>? equals,
  }) {
    final existing = maybeDraft<T>(key);
    if (existing != null) return existing;
    final draft = EcsDraft<T>(
      original: original,
      current: current,
      equals: equals,
    );
    _drafts[key] = draft;
    return draft;
  }

  void removeDraft(final Object key) {
    _drafts.remove(key);
  }

  void clear() {
    _drafts.clear();
  }
}
