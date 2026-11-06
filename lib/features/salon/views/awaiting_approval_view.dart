import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/viewmodels/session_view_model.dart';
import '../../../domain/repositories/repositories.dart';
import '../../../shared/widgets/actions.dart';
import '../../../shared/widgets/ui.dart';

/// A new salon waits here until HOLA approves it (contract 0.33.0). HOLA
/// refuses every salon action until then, so this is all the owner sees.
/// Root swaps to the salon shell as soon as the salon is approved; a sign-up
/// HOLA turns down signs out (SessionViewModel).
class AwaitingApprovalView extends StatelessWidget {
  const AwaitingApprovalView({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SessionViewModel>();
    final c = context.c;
    final a = s.account;
    final salon = a?.salonId == null ? null : context.read<SalonRepository>().salon(a!.salonId!);
    final pad = MediaQuery.paddingOf(context);
    Future<void> check() => attempt(s.checkApproval);
    return Scaffold(
      backgroundColor: c.bg,
      body: RefreshIndicator(
        onRefresh: check,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(kGutter, pad.top + 48, kGutter, pad.bottom + 32),
          children: [
            Center(
              child: Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: c.accentSoft,
                  border: Border.all(color: c.accent.withValues(alpha: .35), width: 2),
                  boxShadow: [BoxShadow(color: c.accent.withValues(alpha: .25), blurRadius: 32)],
                ),
                alignment: Alignment.center,
                child: HIcon('clock', size: 40, color: c.accentInk),
              ),
            ),
            const SizedBox(height: 28),
            Text(tr('Waiting for HOLA approval'), textAlign: TextAlign.center, style: T.h1(context)),
            const SizedBox(height: 10),
            Text(
              tr('Thanks for joining HOLA. Our team is reviewing your salon. You’ll get a notification as soon as it’s approved, and then you can start using the app.'),
              textAlign: TextAlign.center,
              style: T.body(context).copyWith(color: c.body, height: 1.5),
            ),
            if (salon != null) ...[
              const SizedBox(height: 24),
              HCard(
                child: Row(
                  children: [
                    HIcon('store', size: 22, color: c.accentInk),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(salon.name, style: T.ttl(context)),
                          const SizedBox(height: 2),
                          Text(a?.email ?? '', style: T.sm(context).copyWith(color: c.muted)),
                        ],
                      ),
                    ),
                    ToneBadge(tr('In review'), tone: 'warn'),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 28),
            HButton(tr('Check again'), icon: 'sync', block: true, onTap: s.checking ? null : check),
            const SizedBox(height: 12),
            HButton(tr('Sign out'), kind: BtnKind.secondary, block: true, onTap: s.signOut),
          ],
        ),
      ),
    );
  }
}
