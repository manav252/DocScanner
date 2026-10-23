// Cooperative cancellation for long tasks (export, import, text recognition):
// the task checks the token between pages and stops cleanly.
class CancelToken {
  bool _cancelled = false;

  bool get isCancelled => _cancelled;

  void cancel() => _cancelled = true;

  /// Throws [Cancelled] if [cancel] was called.
  void check() {
    if (_cancelled) throw const Cancelled();
  }
}

/// Thrown by a task that was cancelled; callers treat it as "no result", not an error.
class Cancelled implements Exception {
  const Cancelled();

  @override
  String toString() => 'Cancelled';
}
