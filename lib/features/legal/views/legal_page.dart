import 'package:flutter/material.dart';

import '../../../shared/widgets/ui.dart';
import '../legal_text.dart';

/// Terms of use or privacy policy, as numbered sections.
class LegalPage extends StatelessWidget {
  final String title;
  final List<LegalSection> sections;
  const LegalPage({super.key, required this.title, required this.sections});

  const LegalPage.terms({super.key}) : title = 'Terms of use', sections = termsOfUse;
  const LegalPage.privacy({super.key}) : title = 'Privacy policy', sections = privacyPolicy;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return HPage(
      title: tr(title),
      children: [
        const SizedBox(height: 8),
        Text(tr(title), style: T.h1(context)),
        const SizedBox(height: 4),
        Text(tr('Last updated {date}', {'date': legalUpdated}), style: T.sm(context).copyWith(color: c.muted)),
        if (!legalReviewed) ...[
          const SizedBox(height: 14),
          HCard(
            color: c.accentSoft,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                HIcon('alert', size: 18, color: c.accentInk),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    tr('Draft. HOLA is reviewing this wording before release.'),
                    style: T.sm(context).copyWith(color: c.accentInk, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
        ],
        // The body stays English until HOLA approves the wording.
        if (L10n.ur) ...[const SizedBox(height: 10), Text(tr('The Urdu version will be added once HOLA approves this text.'), style: T.sm(context).copyWith(color: c.muted))],
        const SizedBox(height: 20),
        for (final (i, (heading, body)) in sections.indexed) ...[
          // English text keeps left-to-right layout inside the Urdu app, so punctuation stays put.
          Text('${i + 1}. $heading', textDirection: TextDirection.ltr, style: T.h3(context)),
          const SizedBox(height: 6),
          Text(
            body,
            textDirection: TextDirection.ltr,
            style: T.body(context).copyWith(color: c.body, height: 1.5),
          ),
          const SizedBox(height: 20),
        ],
      ],
    );
  }
}
