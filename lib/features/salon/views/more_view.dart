import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'clients_view.dart';

import '../../../core/utils/format.dart';
import '../../../shared/widgets/actions.dart';
import '../../../shared/widgets/ui.dart';
import '../../chat/chat.dart';
import '../../profile/profile.dart';
import '../../trade/trade.dart';
import '../../../domain/entities/entities.dart';
import '../../../domain/repositories/repositories.dart';
import '../viewmodels/salon_view_model.dart';
import '../widgets/salon_widgets.dart';
import 'engagement_view.dart';
import 'menu_view.dart';
import 'offers_admin_view.dart';
import 'salon_profile_view.dart';
import 'team_view.dart';

/// Owner's "More": salon, inbox, trade, settings.
class SalonMore extends StatelessWidget {
  const SalonMore({super.key});
  @override
  Widget build(BuildContext context) => const SalonScope(child: _OwnerMore());
}

class _OwnerMore extends StatelessWidget {
  const _OwnerMore();
  @override
  Widget build(BuildContext context) {
    final vm = context.watch<SalonViewModel>();
    final s = vm.salon;
    if (s == null) return const SizedBox();
    final b = vm.branches;
    final r = vm.rating;
    return BandView(
      role: 'salon',
      children: staggered([
        TopHead(title: tr('More')),
        const SizedBox(height: 16),
        const AccountCard(),
        const SizedBox(height: 12),
        HCard(
          onTap: () => pushPage(context, const SalonProfilePage()),
          child: Row(
            children: [
              SizedBox(
                width: 56,
                height: 56,
                child: SalonArt(s.palette, photo: s.cover, n: 2, radius: 14, name: s.name),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(s.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: T.ttl(context)),
                    Text(
                      b.isEmpty ? '' : '${b.first.area}, ${b.first.city}${b.length > 1 ? ' · ${plural(b.length, 'branch', 'branches')}' : ''}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: T.sub(context),
                    ),
                    const SizedBox(height: 4),
                    Wrap(spacing: 6, children: [StatusBadge(s.status), if (r.count > 0) RatingTag(r.average)]),
                  ],
                ),
              ),
              HIcon('chev', size: 18, color: context.c.subtle),
            ],
          ),
        ),
        if (!s.isActive) ...[const SizedBox(height: 12), const VerificationBanner()],
        const SizedBox(height: 22),
        _Label(tr('Clients')),
        Group(
          children: [
            MRow(icon: 'users', title: tr('Client history'), sub: tr('Past visits, services and spend of each client'), onTap: () => pushPage(context, const ClientsPage())),
            MRow(icon: 'msg', title: tr('Messages'), sub: tr('Clients and delivery riders'), trailing: countOrChev(context, vm.unreadMessages), onTap: () => pushPage(context, const MessagesPage())),
            MRow(
              icon: 'star',
              title: tr('Reviews'),
              sub: [
                r.count == 0
                    ? (vm.waitingReviews == 0 ? tr('No reviews yet') : tr('No published reviews yet'))
                    : tr('{rating} from {reviews}', {'rating': r.average.toStringAsFixed(1), 'reviews': plural(r.count, 'review')}),
                if (vm.waitingReviews > 0) tr('{n} waiting for HOLA', {'n': vm.waitingReviews}),
              ].join(' · '),
              tint: 1,
              trailing: countOrChev(context, vm.unrepliedReviews, warn: true),
              onTap: () => pushPage(context, const ReviewsPage()),
            ),
            // Off since HOLA 0.30.0 (complaints removed).
            if (context.read<EngagementRepository>().complaintsOn)
              MRow(
                icon: 'alert',
                title: tr('Client feedback'),
                sub: vm.openFeedback == 0 ? tr('Nothing open') : tr('{n} open', {'n': vm.openFeedback}),
                tint: 1,
                trailing: countOrChev(context, vm.openFeedback, warn: true),
                onTap: () => pushPage(context, const FeedbackInboxPage()),
              ),
          ],
        ),
        const SizedBox(height: 18),
        _Label(tr('Salon')),
        Group(
          children: [
            MRow(
              icon: 'users',
              title: tr('Team'),
              sub: '${plural(vm.team.length, 'person', 'people')} · ${tr('{n} taking bookings', {'n': vm.bookable.length})}',
              trailing: countOrChev(context, vm.pendingLeave.length, warn: true),
              onTap: () => pushTab(context, const SalonTeam()),
            ),
            MRow(icon: 'scissors', title: tr('Service menu'), sub: plural(vm.activeServices.length, 'service'), onTap: () => pushTab(context, const SalonMenu())),
            MRow(
              icon: 'sparkle',
              title: tr('Offers & discounts'),
              sub: vm.runningOffers == 0 ? tr('Discounts on your services') : tr('{n} running', {'n': vm.runningOffers}),
              onTap: () => pushPage(context, const SalonOffersPage()),
            ),
            MRow(icon: 'store', title: tr('Salon profile & branches'), sub: tr('Details, address, opening hours'), onTap: () => pushPage(context, const SalonProfilePage())),
            MRow(
              icon: 'clock',
              title: tr('Booking settings'),
              sub: s.autoConfirm ? tr('Bookings confirm automatically') : tr('You confirm each booking'),
              onTap: () => pushPage(context, const BookingSettingsPage()),
            ),
            MRow(
              icon: 'cal',
              title: tr('Time off'),
              sub: vm.pendingLeave.isEmpty ? tr('Days off for you and your team') : tr('{n} waiting', {'n': vm.pendingLeave.length}),
              trailing: countOrChev(context, vm.pendingLeave.length, warn: true),
              onTap: () => pushPage(context, const LeaveRequestsPage()),
            ),
          ],
        ),
        const SizedBox(height: 18),
        const _Label('HOLA Professional'),
        Group(
          children: [
            if (s.creditLimit > 0)
              MRow(
                icon: 'cash',
                title: tr('Pay outstanding'),
                sub: tr('Pay your HOLA balance to the rider, in cash or online'),
                tint: 1,
                onTap: () => pushPage(context, PayOutstandingPage(salonId: s.id)),
              ),
            MRow(
              icon: 'doc',
              title: tr('Credit statement'),
              sub: s.creditLimit > 0 ? tr('Limit {amount}', {'amount': rsShort(s.creditLimit)}) : tr('No HOLA credit yet'),
              tint: 2,
              onTap: () => pushPage(context, StatementPage(salonId: s.id)),
            ),
            if (vm.isOwner && context.read<ReturnRepository>().live)
              Builder(
                builder: (context) {
                  final rs = context.read<ReturnRepository>().returns(salonId: s.id);
                  final answer = rs.where((r) => r.status == ReturnStatus.awaitingSalon).length;
                  final open = rs.where((r) => r.isOpen).length;
                  return MRow(
                    icon: 'again',
                    title: tr('Returns & refunds'),
                    sub: answer > 0
                        ? tr('{n} need your answer', {'n': answer})
                        : open > 0
                        ? tr('{n} open', {'n': open})
                        : tr('Replace or get money back for delivered products'),
                    trailing: countOrChev(context, answer, warn: true),
                    onTap: () => pushPage(context, ReturnsPage(salonId: s.id)),
                  );
                },
              ),
            if (context.read<ChatRepository>().holaChat)
              MRow(
                icon: 'msg',
                title: tr('Message HOLA'),
                sub: tr('Questions about orders, credit or anything else'),
                onTap: () => openHolaChat(context, salonId: s.id),
              ),
          ],
        ),
        const SizedBox(height: 18),
        const AppSettingsGroup(),
        const SizedBox(height: 18),
        const SignOutButton(),
      ]),
    );
  }
}

class _Label extends StatelessWidget {
  final String t;
  const _Label(this.t);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 4, bottom: 8),
    child: Text(t.toUpperCase(), style: T.eyebrow(context)),
  );
}

/// How bookings are accepted and the salon's cancellation / no-show rules.
class BookingSettingsPage extends StatelessWidget {
  const BookingSettingsPage({super.key});
  @override
  Widget build(BuildContext context) => const SalonScope(child: _Settings());
}

class _Settings extends StatefulWidget {
  const _Settings();
  @override
  State<_Settings> createState() => _SettingsState();
}

class _SettingsState extends State<_Settings> {
  late final SalonViewModel vm = context.read<SalonViewModel>();
  late bool auto = vm.salon?.autoConfirm ?? false;
  late int window = vm.salon?.cancelWindowHours ?? 2, grace = vm.salon?.noShowGraceMin ?? 15;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return HPage(
      title: tr('Booking settings'),
      footer: FootBar(
        child: HButton(
          tr('Save'),
          block: true,
          onTap: () async {
            final ok = await attempt(
              () => vm.updatePolicy(autoConfirm: auto, cancelWindowHours: window, noShowGraceMin: grace),
              success: tr('Booking settings saved'),
            );
            if (ok && context.mounted) popPage(context);
          },
        ),
      ),
      children: [
        const SizedBox(height: 8),
        ...staggered([
          Group(
            children: [
              SettingRow(
                title: tr('Confirm bookings automatically'),
                sub: auto ? tr('Clients get an instant confirmation') : tr('You confirm or decline each request'),
                control: HSwitch(on: auto, onChanged: (v) => setState(() => auto = v)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Group(
            children: [
              SettingRow(
                title: tr('Free cancellation'),
                sub: window == 0 ? tr('Clients can cancel any time') : tr('Clients can cancel free up to {n} h before', {'n': window}),
                control: ValueStepper(value: window, min: 0, max: 72, format: (v) => tr('{n} h', {'n': v}), onChanged: (v) => setState(() => window = v)),
              ),
              SettingRow(
                title: tr('No-show after'),
                sub: tr('You can mark a no-show {n} min after the start', {'n': grace}),
                control: ValueStepper(value: grace, min: 5, max: 60, step: 5, format: (v) => tr('{n} min', {'n': v}), onChanged: (v) => setState(() => grace = v)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(tr('Late cancellations are marked on the booking so you can see who cancels late.'), style: T.cap(context).copyWith(color: c.muted)),
        ]),
      ],
    );
  }
}
