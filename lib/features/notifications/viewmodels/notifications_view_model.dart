import '../../../core/mvvm/repo_view_model.dart';
import '../../../core/utils/clock.dart';
import '../../../domain/entities/entities.dart';
import '../../../domain/repositories/repositories.dart';

class NotificationsViewModel extends RepoViewModel {
  NotificationsViewModel(this._repo) : super(_repo);
  final EngagementRepository _repo;

  List<AppNotification> get all => _repo.notifications();
  int get unread => _repo.unreadNotifications();
  List<AppNotification> get todays => all.where((n) => sameDay(n.at, now())).toList();
  List<AppNotification> get earlier => all.where((n) => !sameDay(n.at, now())).toList();

  Future<void> open(AppNotification n) => _repo.markNotificationRead(n.id);
  Future<void> markAllRead() => _repo.markAllNotificationsRead();
}

/// Unread count for the bell, kept live.
class UnreadViewModel extends RepoViewModel {
  UnreadViewModel(this._repo) : super(_repo);
  final EngagementRepository _repo;
  int get count => _repo.unreadNotifications();
}
