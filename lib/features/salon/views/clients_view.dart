import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/utils/clock.dart';
import '../../../core/utils/format.dart';
import '../../../domain/entities/entities.dart';
import '../../../shared/widgets/ui.dart';
import '../viewmodels/salon_view_model.dart';
import '../widgets/salon_widgets.dart';
import 'appointment_view.dart';

/// Everyone who has visited or booked the salon, most recent first.
class ClientsPage extends StatefulWidget {
  const ClientsPage({super.key});
  @override
  State<ClientsPage> createState() => _ClientsPageState();
}

class _ClientsPageState extends State<ClientsPage> {
  String _q = '';

  @override
  Widget build(BuildContext context) => SalonScope(
    child: Builder(
      builder: (context) {
        final vm = context.watch<SalonViewModel>();
        final everyone = vm.clients();
        final list = _q.isEmpty ? everyone : vm.clients(q: _q);
        return _Load(
          run: vm.loadClients,
          builder: (loading, reload) => HPage(
            title: tr('Clients'),
            onRefresh: reload,
            children: [
              const SizedBox(height: 8),
              if (loading && everyone.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (everyone.length > 4) ...[
                HField(hint: tr('Search by name or phone'), icon: 'search', onChanged: (v) => setState(() => _q = v)),
                const SizedBox(height: 14),
              ],
              if (everyone.isEmpty)
                EmptyState(icon: 'users', title: tr('No clients yet'), text: tr('Everyone who books or walks in appears here, with their visits and services.'))
              else if (list.isEmpty)
                EmptyState(icon: 'search', title: tr('No one found'), text: tr('Try another name or number.'))
              else
                for (final (i, c) in list.indexed)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Reveal(
                      i: i < 12 ? i : 12,
                      child: _ClientTile(c, onTap: () => pushPage(context, ClientHistoryPage(clientKey: c.key))),
                    ),
                  ),
            ],
          ),
        );
      },
    ),
  );
}

class _ClientTile extends StatelessWidget {
  const _ClientTile(this.c, {required this.onTap});
  final ClientSummary c;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final when = c.lastVisit == null
        ? (c.next != null ? tr('Next visit {day}', {'day': dayLabel(c.next!.startsAt, today)}) : tr('No completed visit yet'))
        : tr('Last visit {day}', {'day': dayLabel(c.lastVisit!, today)});
    return HCard(
      onTap: onTap,
      child: Row(
        children: [
          Avatar(c.name, size: 44),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: T.ttl(context)),
                Text(
                  when,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: T.sm(context).copyWith(color: context.c.muted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(plural(c.completed, 'visit'), style: T.ttl(context)),
              if (c.spent > 0) Text(rsShort(c.spent), style: T.cap(context)),
            ],
          ),
          const SizedBox(width: 6),
          HIcon('chev', size: 18, color: context.c.subtle),
        ],
      ),
    );
  }
}

/// One client's history at this salon: totals, then every booking newest first.
class ClientHistoryPage extends StatelessWidget {
  const ClientHistoryPage({super.key, required this.clientKey});
  final String clientKey;

  @override
  Widget build(BuildContext context) => SalonScope(
    child: Builder(
      builder: (context) {
        final vm = context.watch<SalonViewModel>();
        final c = vm.client(clientKey);
        if (c == null) {
          return HPage(
            title: tr('Client'),
            children: [EmptyState(icon: 'users', title: tr('No visits found'), text: tr('This client has no bookings here.'))],
          );
        }
        final visits = vm.history(clientKey);
        final past = visits.where((a) => !(ApptStatus.upcoming.contains(a.status) && a.startsAt.isAfter(now()))).toList();
        final coming = visits.where((a) => ApptStatus.upcoming.contains(a.status) && a.startsAt.isAfter(now())).toList().reversed.toList();
        return _Load(
          run: () => vm.loadHistory(clientKey),
          builder: (loading, reload) => HPage(
            title: c.name,
            onRefresh: reload,
            children: [
              const SizedBox(height: 8),
              ...staggered([
                Row(
                  children: [
                    Avatar(c.name, size: 56),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(c.name, style: T.h2(context)),
                          if (c.phone.isNotEmpty) Text(c.phone, style: T.sub(context)),
                          const SizedBox(height: 4),
                          Wrap(spacing: 6, runSpacing: 4, children: [ToneBadge(c.hasAccount ? tr('HOLA app client') : tr('Walk-in'), tone: c.hasAccount ? 'info' : 'mute')]),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                KpiRow([Kpi(tr('Visits'), c.completed, hl: true), Kpi(tr('Spent'), c.spent, format: (v) => rsShort(v)), Kpi(tr('Missed or cancelled'), c.noShows + c.cancelled)]),
                const SizedBox(height: 12),
                HCard(
                  child: VStack(gap: 8, [
                    KV(tr('Client since'), c.firstVisit == null ? '—' : _date(c.firstVisit!)),
                    KV(tr('Last visit'), c.lastVisit == null ? '—' : _date(c.lastVisit!)),
                    KV(tr('Bookings'), '${c.bookings}'),
                    if (c.noShows > 0) KV(tr('No-shows'), '${c.noShows}', vColor: context.c.badInk),
                    if (c.favourites.isNotEmpty) ...[const HDivider(), Text(tr('Usually has'), style: T.cap(context)), Text(c.favourites.join(', '), style: T.ttl(context))],
                  ]),
                ),
                const SizedBox(height: 24),
              ]),
              if (coming.isNotEmpty) ...[
                SecHead(tr('Coming up')),
                const SizedBox(height: 12),
                for (final a in coming) Padding(padding: const EdgeInsets.only(bottom: 10), child: _VisitTile(a)),
                const SizedBox(height: 14),
              ],
              // Also lists bookings cancelled for a later time, which never happened.
              SecHead(past.any((a) => a.startsAt.isAfter(now())) ? tr('Past and cancelled') : tr('Past visits')),
              const SizedBox(height: 12),
              if (past.isEmpty && loading)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                ),
              if (past.isEmpty && !loading) HCard(child: Text(tr('No past visits yet.'), style: T.sub(context))),
              for (final a in past) Padding(padding: const EdgeInsets.only(bottom: 10), child: _VisitTile(a)),
            ],
          ),
        );
      },
    ),
  );

  static String _date(DateTime d) => '${d.day} ${months[d.month - 1]} ${d.year}';
}

/// One booking in a client's history: when, what, with whom, price, outcome.
class _VisitTile extends StatelessWidget {
  const _VisitTile(this.a);
  final Appointment a;
  @override
  Widget build(BuildContext context) {
    final vm = context.read<SalonViewModel>();
    final c = context.c;
    final review = vm.reviewOf(a.id);
    final day = a.startsAt.year == today.year ? dLabel(a.startsAt) : '${dLabel(a.startsAt)} ${a.startsAt.year}';
    return HCard(
      onTap: () => pushPage(context, AppointmentDetailPage(id: a.id)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('$day · ${fmtTime(a.startsAt)}', style: T.ttl(context)),
                    Text(
                      a.serviceNames.join(', '),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: T.sm(context).copyWith(color: c.muted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(rsShort(a.price), style: T.ttl(context)),
                  const SizedBox(height: 6),
                  StatusBadge(a.status),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            [
              tr('with {name}', {'name': vm.firstNameOf(a.staffId)}),
              fmtDur(a.durationMin),
              if (a.code.isNotEmpty) a.code,
            ].join(' · '),
            style: T.cap(context).copyWith(color: c.ink, fontWeight: FontWeight.w600),
          ),
          if (a.notes.trim().isNotEmpty) ...[const SizedBox(height: 6), Text('“${a.notes.trim()}”', style: T.sm(context).copyWith(color: c.muted))],
          if (review != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Stars(review.stars),
                if (review.text.trim().isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(review.text.trim(), maxLines: 2, overflow: TextOverflow.ellipsis, style: T.sm(context)),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Runs [run] once when the page opens (and again on pull-to-refresh), so
/// the page shows HOLA's full record. Offline, the page keeps what the phone has.
class _Load extends StatefulWidget {
  const _Load({required this.run, required this.builder});
  final Future<void> Function() run;
  final Widget Function(bool loading, Future<void> Function() reload) builder;
  @override
  State<_Load> createState() => _LoadState();
}

class _LoadState extends State<_Load> {
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    try {
      await widget.run();
    } catch (_) {
      // Offline or no access: show what this phone already has.
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => widget.builder(_loading, _reload);
}
