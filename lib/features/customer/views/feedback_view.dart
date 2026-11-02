import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/utils/clock.dart';
import '../../../core/utils/format.dart';
import '../../../core/utils/sfx.dart';
import '../../../domain/entities/entities.dart';
import '../../../domain/repositories/repositories.dart';
import '../../../shared/widgets/actions.dart';
import '../../../shared/widgets/ui.dart';
import '../viewmodels/bookings_view_models.dart';

/// Feedback and complaints the customer raised, with the salons' responses.
class MyFeedbackPage extends StatelessWidget {
  const MyFeedbackPage({super.key});
  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
        create: (c) => FeedbackViewModel(c.read<SalonRepository>(), c.read<AuthRepository>(), c.read<BookingRepository>(), c.read<EngagementRepository>()),
        child: const _FeedbackBody(),
      );
}

class _FeedbackBody extends StatelessWidget {
  const _FeedbackBody();
  @override
  Widget build(BuildContext context) {
    final vm = context.watch<FeedbackViewModel>();
    final items = vm.items;
    final booked = vm.bookedSalons;
    return HPage(
      title: tr('Feedback & complaints'),
      footer: booked.isEmpty ? null : HButton(tr('Give feedback'), icon: 'msg', block: true, onTap: () => _pickSalon(context, booked)),
      children: [
        Text(tr('Tell a salon what went well or what went wrong. They reply here and you get a notification.'), style: T.body(context).copyWith(color: context.c.muted)),
        const SizedBox(height: 18),
        if (items.isEmpty)
          HCard(
            child: EmptyState(
              icon: 'msg',
              title: tr('No feedback yet'),
              text: booked.isEmpty ? tr('After you visit a salon you can share feedback with them here.') : tr('Share feedback about a salon you have booked.'),
            ),
          )
        else
          VStack(gap: 12, staggered([for (final x in items) ComplaintCard(x, salonName: vm.salonName(x.salonId))])),
      ],
    );
  }

  Future<void> _pickSalon(BuildContext context, List<Salon> salons) async {
    if (salons.length == 1) return showComplaintSheet(context, salonId: salons.first.id, salonName: salons.first.name);
    final s = await showHSheet<Salon>(
      context,
      (ctx) => VStack(gap: 10, [
        SheetHead(tr('Which salon?')),
        Group(children: [for (final x in salons) MRow(icon: 'store', title: x.name, onTap: () => Navigator.pop(ctx, x))]),
      ]),
    );
    if (s != null && context.mounted) await showComplaintSheet(context, salonId: s.id, salonName: s.name);
  }
}

/// One complaint with its status and the salon's response.
class ComplaintCard extends StatelessWidget {
  final Complaint x;
  final String salonName;
  const ComplaintCard(this.x, {super.key, required this.salonName});
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return HCard(
      child: VStack(gap: 8, [
        Row(children: [
          Expanded(child: Text(tr(x.topic), style: T.ttl(context))),
          const SizedBox(width: 8),
          StatusBadge(x.status, label: x.status == 'OPEN' ? tr('Waiting for reply') : tr('Answered')),
        ]),
        Text('$salonName · ${ago(x.createdAt, now())}', style: T.cap(context)),
        Text(x.text, style: T.sm(context).copyWith(color: c.ink)),
        if (x.response != null)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: c.okSoft, borderRadius: BorderRadius.circular(12)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tr('Reply from {salon}', {'salon': salonName}), style: T.cap(context).copyWith(color: c.ok, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text(x.response!, style: T.sm(context).copyWith(color: c.ink)),
            ]),
          ),
      ]),
    );
  }
}

/// Feedback form for a salon (optionally about one booking).
Future<void> showComplaintSheet(BuildContext context, {required String salonId, required String salonName, String? appointmentId}) async {
  final engage = context.read<EngagementRepository>();
  final text = TextEditingController();
  String? topic;
  await showHSheet(
    context,
    (ctx) => StatefulBuilder(
      builder: (ctx, set) => VStack(gap: 14, [
        SheetHead(tr('Feedback for {salon}', {'salon': salonName}), sub: appointmentId == null ? null : tr('About this booking. The salon will reply in the app.')),
        Text(tr('WHAT IS IT ABOUT?'), style: T.eyebrow(ctx)),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final t in feedbackTopics)
            HChip(tr(t), on: topic == t, onTap: () {
              Sfx.tap();
              set(() => topic = t);
            }),
        ]),
        HField(label: tr('Tell them what happened'), hint: tr('At least 10 characters'), controller: text, multiline: true, onChanged: (_) => set(() {})),
        HButton(tr('Send to salon'), block: true, onTap: topic == null || text.text.trim().length < 10
            ? null
            : () async {
                final ok = await attempt(() => engage.raiseComplaint(salonId: salonId, appointmentId: appointmentId, topic: topic!, text: text.text), success: tr('Sent. {salon} will reply here.', {'salon': salonName}), icon: 'msg');
                if (ok && ctx.mounted) Navigator.pop(ctx);
              }),
      ]),
    ),
  );
  text.dispose();
}
