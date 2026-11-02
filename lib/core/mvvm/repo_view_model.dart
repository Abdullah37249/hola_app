import 'package:flutter/foundation.dart';

import '../../domain/repositories/repositories.dart';
import 'view_model.dart';

/// A ViewModel that re-reads its data whenever any repository changes, so
/// screens of every role stay live (a booking made by a customer appears on the
/// salon's screens straight away). Override [refresh] if you cache derived data.
abstract class RepoViewModel extends ViewModel {
  RepoViewModel(this.source) {
    source.changes.addListener(_onChange);
  }
  final Observable source;

  void _onChange() {
    refresh();
    notify();
  }

  /// Recompute cached state from the repositories. Default: nothing cached.
  @protected
  void refresh() {}

  @override
  void dispose() {
    source.changes.removeListener(_onChange);
    super.dispose();
  }
}
