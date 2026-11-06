import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/utils/clock.dart';
import '../../../core/utils/format.dart';
import '../../../domain/entities/entities.dart';
import '../../../shared/widgets/actions.dart';
import '../../../shared/widgets/ui.dart';
import '../viewmodels/salon_view_model.dart';
import '../widgets/salon_widgets.dart';
import '../../customer/widgets/review_photos.dart' show ReviewPhotoStrip;
import 'appointment_view.dart';

/// What clients said after their visits; the salon can reply publicly.
class ReviewsPage extends StatelessWidget {
  const ReviewsPage({super.key});
  @override
  Widget build(BuildContext context) => SalonScope(
    child: Builder(
      builder: (context) {
        final vm = context.watch<SalonViewModel>();
        final rs = vm.reviews;
        final r = vm.rating;
        final c = context.c;
        return HPage(
          title: tr('Reviews'),
          children: [
            const SizedBox(height: 8),
            ...staggered([
              HCard(
                gradient: G.sun,
                child: Row(
                  children: [
                    Text(r.count == 0 ? '–' : r.average.toStringAsFixed(1), style: T.display(context).copyWith(color: Colors.white)),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Stars(r.average.round(), size: 18),
                          const SizedBox(height: 4),
                          Text(r.count == 0 ? tr('No reviews yet') : tr('from {reviews}', {'reviews': plural(r.count, 'review')}), style: T.sm(context).copyWith(color: Colors.white)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              if (rs.isEmpty)
                HCard(
                  child: EmptyState(icon: 'star', title: tr('No reviews yet'), text: tr('Clients can review you after a completed visit. Their reviews and your replies appear here.')),
                ),
              for (final x in rs)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: HCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Avatar(x.customerName, size: 36),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(x.customerName, style: T.ttl(context)),
                                  Text(ago(x.createdAt, now()), style: T.cap(context)),
                                ],
                              ),
                            ),
                            Stars(x.stars),
                            if (vm.canDeleteReviews) ...[
                              const SizedBox(width: 4),
                              IconBtn(
                                'x',
                                onTap: () async {
                                  final ok = await confirmSheet(
                                    context,
                                    title: tr('Delete this review?'),
                                    body: tr('It is removed from your profile and your rating, with its photos. This can\'t be undone.'),
                                    confirm: tr('Delete review'),
                                    danger: true,
                                  );
                                  if (ok) await attempt(() => vm.deleteReview(x.id), success: tr('Review deleted'), icon: 'x');
                                },
                              ),
                            ],
                          ],
                        ),
                        if (x.pending) ...[
                          const SizedBox(height: 10),
                          ToneBadge(tr('Waiting for HOLA'), tone: 'warn'),
                          const SizedBox(height: 4),
                          Text(tr('HOLA checks each review before clients see it. It counts in your rating once published.'), style: T.cap(context)),
                        ],
                        if (x.text.isNotEmpty) ...[const SizedBox(height: 10), Text(x.text, style: T.body(context))],
                        if (x.photos.isNotEmpty) ...[const SizedBox(height: 10), ReviewPhotoStrip(x)],
                        const SizedBox(height: 10),
                        if (x.pending)
                          const SizedBox.shrink()
                        else if (x.reply != null)
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(color: c.brandSoft, borderRadius: BorderRadius.circular(12)),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  tr('Your reply · {when}', {'when': ago(x.repliedAt ?? x.createdAt, now())}),
                                  style: T.cap(context).copyWith(color: c.brandText, fontWeight: FontWeight.w600),
                                ),
                                const SizedBox(height: 2),
                                Text(x.reply!, style: T.sm(context)),
                              ],
                            ),
                          )
                        else
                          HButton(
                            tr('Reply'),
                            icon: 'msg',
                            kind: BtnKind.secondary,
                            small: true,
                            onTap: () async {
                              final t = await askText(
                                context,
                                title: tr('Reply to {name}', {'name': x.customerName.split(' ').first}),
                                body: tr('Your reply is shown with the review.'),
                                label: tr('Reply'),
                                hint: tr('Thank you for visiting…'),
                                confirm: tr('Post reply'),
                                minLength: 2,
                              );
                              if (t != null) await attempt(() => vm.reply(x.id, t), success: tr('Reply posted'));
                            },
                          ),
                      ],
                    ),
                  ),
                ),
            ]),
          ],
        );
      },
    ),
  );
}

/// Feedback and complaints clients raised with the salon.
class FeedbackInboxPage extends StatelessWidget {
  const FeedbackInboxPage({super.key});
  @override
  Widget build(BuildContext context) => const SalonScope(child: _Feedback());
}

class _Feedback extends StatefulWidget {
  const _Feedback();
  @override
  State<_Feedback> createState() => _FeedbackState();
}

class _FeedbackState extends State<_Feedback> {
  String tab = 'OPEN';

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<SalonViewModel>();
    final c = context.c;
    final all = vm.feedback;
    final xs = all.where((x) => x.status == tab).toList();
    return HPage(
      title: tr('Client feedback'),
      children: [
        const SizedBox(height: 8),
        Seg(
          opts: [
            ('OPEN', tr('Open ({n})', {'n': all.where((x) => x.status == 'OPEN').length})),
            ('RESOLVED', tr('Resolved')),
          ],
          value: tab,
          onChanged: (v) => setState(() => tab = v),
        ),
        const SizedBox(height: 16),
        if (xs.isEmpty)
          HCard(
            child: EmptyState(
              icon: tab == 'OPEN' ? 'check' : 'doc',
              title: tab == 'OPEN' ? tr('Nothing to answer') : tr('Nothing resolved yet'),
              text: tr('When a client sends feedback or a complaint about your salon, it lands here for you to respond.'),
            ),
          ),
        for (final (i, x) in xs.indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Reveal(
              i: i,
              child: HCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(child: Text(tr(x.topic), style: T.ttl(context))),
                        StatusBadge(x.status),
                      ],
                    ),
                    Text('${x.customerName} · ${ago(x.createdAt, now())}', style: T.cap(context)),
                    const SizedBox(height: 8),
                    Text(x.text, style: T.body(context)),
                    if (vm.appointment(x.appointmentId ?? '') case final Appointment a) ...[
                      const SizedBox(height: 8),
                      GestureDetector(
                        onTap: () => pushPage(context, AppointmentDetailPage(id: a.id)),
                        child: Text(tr('Booking {code} · {date}', {'code': a.code, 'date': dLabel(a.startsAt)}), style: T.link(context)),
                      ),
                    ],
                    const SizedBox(height: 10),
                    if (x.response != null)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: c.okSoft, borderRadius: BorderRadius.circular(12)),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              tr('Your response · {when}', {'when': ago(x.resolvedAt ?? x.createdAt, now())}),
                              style: T.cap(context).copyWith(color: c.ok, fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 2),
                            Text(x.response!, style: T.sm(context)),
                          ],
                        ),
                      )
                    else
                      HButton(
                        tr('Respond'),
                        icon: 'check',
                        small: true,
                        onTap: () async {
                          final t = await askText(
                            context,
                            title: tr('Respond to {name}', {'name': x.customerName.split(' ').first}),
                            body: tr('They are notified of your response.'),
                            label: tr('Response'),
                            hint: tr('We’re sorry about…'),
                            confirm: tr('Send response'),
                            minLength: 5,
                          );
                          if (t != null) await attempt(() => vm.resolve(x.id, t), success: tr('Response sent'));
                        },
                      ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
