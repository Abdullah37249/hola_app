import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/utils/format.dart';
import '../../../shared/widgets/actions.dart';
import '../../../shared/widgets/ui.dart';
import '../../chat/chat.dart';
import '../../profile/profile.dart';
import '../../trade/trade.dart';
import '../viewmodels/salon_view_model.dart';
import '../widgets/salon_widgets.dart';
import 'engagement_view.dart';
import 'menu_view.dart';
import 'salon_profile_view.dart';
import 'team_view.dart';
import 'training_view.dart';

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
    final upcomingTraining = vm.upcomingTrainings.length;
    return BandView(role: 'salon', children: staggered([
      TopHead(title: tr('More')),
      const SizedBox(height: 16),
      const AccountCard(),
      const SizedBox(height: 12),
      HCard(
        onTap: () => pushPage(context, const SalonProfilePage()),
        child: Row(children: [
          SizedBox(width: 56, height: 56, child: SalonArt(s.palette, photo: s.cover, n: 2, radius: 14, name: s.name)),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(s.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: T.ttl(context)),
              Text(b.isEmpty ? '' : '${b.first.area}, ${b.first.city}${b.length > 1 ? ' · ${plural(b.length, 'branch', 'branches')}' : ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: T.sub(context)),
              const SizedBox(height: 4),
              Wrap(spacing: 6, children: [StatusBadge(s.status), if (r.count > 0) RatingTag(r.average)]),
            ]),
          ),
          HIcon('chev', size: 18, color: context.c.subtle),
        ]),
      ),
      if (!s.isActive) ...[const SizedBox(height: 12), const VerificationBanner()],
      const SizedBox(height: 22),
      _Label(tr('Clients')),
      Group(children: [
        MRow(icon: 'msg', title: tr('Messages'), sub: tr('Chats with your clients'), trailing: countOrChev(context, vm.unreadMessages), onTap: () => pushPage(context, const ChatInboxPage())),
        MRow(icon: 'star', title: tr('Reviews'), sub: r.count == 0 ? tr('No reviews yet') : tr('{rating} from {reviews}', {'rating': r.average.toStringAsFixed(1), 'reviews': plural(r.count, 'review')}), tint: 1, trailing: countOrChev(context, vm.unrepliedReviews, warn: true), onTap: () => pushPage(context, const ReviewsPage())),
        MRow(icon: 'alert', title: tr('Client feedback'), sub: vm.openFeedback == 0 ? tr('Nothing open') : tr('{n} open', {'n': vm.openFeedback}), tint: 1, trailing: countOrChev(context, vm.openFeedback, warn: true), onTap: () => pushPage(context, const FeedbackInboxPage())),
      ]),
      const SizedBox(height: 18),
      _Label(tr('Salon')),
      Group(children: [
        MRow(icon: 'store', title: tr('Salon profile & branches'), sub: tr('Details, address, opening hours'), onTap: () => pushPage(context, const SalonProfilePage())),
        MRow(icon: 'clock', title: tr('Booking settings'), sub: s.autoConfirm ? tr('Bookings confirm automatically') : tr('You confirm each booking'), onTap: () => pushPage(context, const BookingSettingsPage())),
        MRow(icon: 'cal', title: tr('Leave requests'), sub: vm.pendingLeave.isEmpty ? tr('Time off for your team') : tr('{n} waiting', {'n': vm.pendingLeave.length}), trailing: countOrChev(context, vm.pendingLeave.length, warn: true), onTap: () => pushPage(context, const LeaveRequestsPage())),
        MRow(icon: 'user', title: tr('My schedule & leave'), sub: tr('Your own hours and days off'), onTap: () => pushPage(context, const MyLeavePage())),
      ]),
      const SizedBox(height: 18),
      const _Label('HOLA Professional'),
      Group(children: [
        MRow(icon: 'box', title: tr('Product orders'), sub: s.isActive ? tr('Order HOLA products for your salon') : tr('Opens once HOLA verifies your salon'), tint: 2, onTap: () => pushPage(context, SalonOrdersPage(salonId: s.id))),
        MRow(icon: 'doc', title: tr('Credit statement'), sub: s.creditLimit > 0 ? tr('Limit {amount}', {'amount': rs(s.creditLimit)}) : tr('No HOLA credit yet'), tint: 2, onTap: () => pushPage(context, StatementPage(salonId: s.id))),
        MRow(icon: 'grad', title: tr('Training'), sub: upcomingTraining == 0 ? tr('Sessions by the HOLA Academy') : plural(upcomingTraining, 'upcoming session'), tint: 2, onTap: () => pushPage(context, const TrainingListPage())),
      ]),
      const SizedBox(height: 18),
      const AppSettingsGroup(),
      const SizedBox(height: 18),
      const SignOutButton(),
    ]));
  }
}

class _Label extends StatelessWidget {
  final String t;
  const _Label(this.t);
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.only(left: 4, bottom: 8), child: Text(t.toUpperCase(), style: T.eyebrow(context)));
}

/// Staff "More": own schedule & leave, menu, messages, settings.
class SStaffMore extends StatelessWidget {
  const SStaffMore({super.key});
  @override
  Widget build(BuildContext context) => const SalonScope(child: _StaffMore());
}

class _StaffMore extends StatelessWidget {
  const _StaffMore();
  @override
  Widget build(BuildContext context) {
    final vm = context.watch<SalonViewModel>();
    final me = vm.me;
    final p = me == null ? null : vm.profile(me.id);
    final pending = vm.myLeave().where((l) => l.status == 'PENDING').length;
    return BandView(role: 'sstaff', children: staggered([
      TopHead(title: tr('More'), sub: vm.salon?.name),
      const SizedBox(height: 16),
      const AccountCard(),
      const SizedBox(height: 18),
      Group(children: [
        MRow(icon: 'clock', title: tr('My schedule & leave'), sub: p == null ? null : weekSummary(p.week), trailing: countOrChev(context, pending, warn: true), onTap: () => pushPage(context, const MyLeavePage())),
        MRow(icon: 'scissors', title: tr('Service menu'), sub: plural(vm.activeServices.length, 'service'), onTap: () => pushPage(context, const ServiceMenuPage())),
        MRow(icon: 'msg', title: tr('Messages'), sub: tr('Chats with clients'), trailing: countOrChev(context, vm.unreadMessages), onTap: () => pushPage(context, const ChatInboxPage())),
        MRow(icon: 'star', title: tr('Salon reviews'), sub: vm.rating.count == 0 ? tr('No reviews yet') : tr('{rating} from {reviews}', {'rating': vm.rating.average.toStringAsFixed(1), 'reviews': plural(vm.rating.count, 'review')}), tint: 1, onTap: () => pushPage(context, const ReviewsPage())),
      ]),
      const SizedBox(height: 18),
      const AppSettingsGroup(),
      const SizedBox(height: 18),
      const SignOutButton(),
    ]));
  }
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
        child: HButton(tr('Save'), block: true, onTap: () async {
          final ok = await attempt(() => vm.updatePolicy(autoConfirm: auto, cancelWindowHours: window, noShowGraceMin: grace), success: tr('Booking settings saved'));
          if (ok && context.mounted) popPage(context);
        }),
      ),
      children: [
        const SizedBox(height: 8),
        ...staggered([
          Group(children: [
            SettingRow(
              title: tr('Confirm bookings automatically'),
              sub: auto ? tr('Clients get an instant confirmation') : tr('You confirm or decline each request'),
              control: HSwitch(on: auto, onChanged: (v) => setState(() => auto = v)),
            ),
          ]),
          const SizedBox(height: 16),
          Group(children: [
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
          ]),
          const SizedBox(height: 12),
          Text(tr('Late cancellations are marked on the booking so you can see who cancels late.'), style: T.cap(context).copyWith(color: c.muted)),
        ]),
      ],
    );
  }
}
