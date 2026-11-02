import 'package:flutter/foundation.dart';

/// Base class for all ViewModels: loading/error state and safe notify.
abstract class ViewModel extends ChangeNotifier {
  bool _loading = false, _disposed = false;
  Object? error;

  bool get loading => _loading;

  /// Runs [task] with loading/error bookkeeping, then notifies listeners.
  @protected
  Future<T?> run<T>(Future<T> Function() task) async {
    _loading = true;
    error = null;
    notify();
    try {
      return await task();
    } catch (e) {
      error = e;
      return null;
    } finally {
      _loading = false;
      notify();
    }
  }

  @protected
  void notify() { if (!_disposed) notifyListeners(); }

  @override
  void dispose() { _disposed = true; super.dispose(); }
}
