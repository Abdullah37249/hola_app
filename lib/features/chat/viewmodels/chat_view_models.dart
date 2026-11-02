import 'dart:async';

import '../../../core/mvvm/repo_view_model.dart';
import '../../../domain/entities/entities.dart';
import '../../../domain/repositories/repositories.dart';
import '../../../core/l10n/l10n.dart';

/// One row in an inbox: who, the last message and how many are unread.
class ThreadSummary {
  final ChatThread thread;
  final String name;
  final int palette;
  final ChatMessage? last;
  final int unread;
  const ThreadSummary(this.thread, this.name, this.palette, this.last, this.unread);
}

String _customerName(AuthRepository auth, String id) => auth.account(id)?.name ?? tr('Former customer');

class ChatViewModel extends RepoViewModel {
  ChatViewModel(this.threadId, this.asSalon, this._chat, this._salons, this._auth) : super(_chat) {
    _markRead();
  }
  final String threadId;
  final bool asSalon;
  final EngagementRepository _chat;
  final SalonRepository _salons;
  final AuthRepository _auth;

  ChatThread? get thread => _chat.thread(threadId);
  List<ChatMessage> get messages => _chat.messages(threadId);
  Salon? get salon => thread == null ? null : _salons.salon(thread!.salonId);

  String get title => thread == null ? tr('Conversation') : (asSalon ? _customerName(_auth, thread!.customerId) : (salon?.name ?? tr('Salon')));
  String get subtitle {
    if (thread == null) return '';
    if (asSalon) return _auth.account(thread!.customerId)?.phone ?? '';
    final b = _salons.branches(thread!.salonId);
    return b.isEmpty ? '' : '${b.first.area}, ${b.first.city}';
  }

  int get palette => asSalon ? title.codeUnits.fold(0, (s, x) => s + x) : (salon?.palette ?? 0);

  @override
  void refresh() => _markRead();

  void _markRead() {
    if (_chat.unread(threadId, asSalon: asSalon) == 0) return;
    // Out of the change callback: marking read is itself a change.
    scheduleMicrotask(() => _chat.markThreadRead(threadId, asSalon: asSalon));
  }

  Future<void> send(String text) => _chat.send(threadId, text, asSalon: asSalon);
}

class ChatInboxViewModel extends RepoViewModel {
  ChatInboxViewModel(this._chat, this._auth) : super(_chat);
  final EngagementRepository _chat;
  final AuthRepository _auth;

  List<ThreadSummary> get threads {
    final salonId = _auth.current?.salonId;
    if (salonId == null) return const [];
    return [
      for (final t in _chat.threadsForSalon(salonId))
        () {
          final name = _customerName(_auth, t.customerId);
          return ThreadSummary(t, name, name.codeUnits.fold(0, (s, x) => s + x), _chat.lastMessage(t.id), _chat.unread(t.id, asSalon: true));
        }(),
    ];
  }
}

class CustomerChatsViewModel extends RepoViewModel {
  CustomerChatsViewModel(this._chat, this._salons, this._auth) : super(_chat);
  final EngagementRepository _chat;
  final SalonRepository _salons;
  final AuthRepository _auth;

  List<ThreadSummary> get threads {
    final me = _auth.current;
    if (me == null) return const [];
    return [
      for (final t in _chat.threadsForCustomer(me.id))
        () {
          final s = _salons.salon(t.salonId);
          return ThreadSummary(t, s?.name ?? tr('Salon'), s?.palette ?? 0, _chat.lastMessage(t.id), _chat.unread(t.id, asSalon: false));
        }(),
    ];
  }
}
