import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/utils/clock.dart';
import '../../../core/utils/format.dart';
import '../../../domain/repositories/repositories.dart';
import '../../../shared/widgets/ui.dart';
import '../../profile/profile.dart';
import '../../trade/trade.dart';
import '../viewmodels/field_view_models.dart';
import 'report_views.dart';
import 'training_views.dart';

class FieldMore extends StatelessWidget {
  const FieldMore({super.key});
  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
    create: (c) => DailyReportViewModel(salons: c.read<SalonRepository>(), auth: c.read<AuthRepository>(), field: c.read<FieldRepository>(), trade: c.read<TradeRepository>()),
    child: const _Body(),
  );
}

class _Body extends StatelessWidget {
  const _Body();
  @override
  Widget build(BuildContext context) {
    final vm = context.watch<DailyReportViewModel>();
    final field = context.read<FieldRepository>();
    final trade = context.read<TradeRepository>();
    final upcoming = field.trainings().where((t) => t.status == 'SCHEDULED' && t.at.isAfter(now())).toList();
    final products = trade.products(activeOnly: false);
    final lowStock = products.expand((p) => p.variants).where((v) => v.stock <= 5).length;
    return BandView(
      role: 'field',
      children: [
        ...staggered([TopHead(title: tr('More')), const SizedBox(height: 16), const AccountCard()]),
        const BandMark(),
        ...staggered([
          const SizedBox(height: 24),
          Text(tr('HOLA WORK'), style: T.eyebrow(context)),
          const SizedBox(height: 8),
          Group(
            children: [
              MRow(
                icon: 'bag',
                title: tr('Products & stock'),
                sub: products.isEmpty ? tr('Add the HOLA trade catalogue') : '${plural(products.length, 'product')}${lowStock > 0 ? ' · ${tr('{n} low on stock', {'n': lowStock})}' : ''}',
                onTap: () => pushPage(context, const ProductsAdminPage()),
              ),
              MRow(
                icon: 'grad',
                tint: 2,
                title: tr('Training sessions'),
                sub: upcoming.isEmpty ? tr('Schedule a session for salons') : tr('{sessions} · next {date}', {'sessions': plural(upcoming.length, 'upcoming session'), 'date': dLabel(upcoming.first.at)}),
                onTap: () => pushPage(context, const TrainingsPage()),
              ),
              MRow(icon: 'chart', title: tr('My performance'), sub: tr('Visits and orders, this week and month'), onTap: () => pushPage(context, const PerformancePage())),
              MRow(
                icon: 'clip',
                tint: 1,
                title: tr('Daily report'),
                sub: vm.submitted != null
                    ? tr('Submitted today at {time}', {'time': fmtTime(vm.submitted!.submittedAt)})
                    : tr('{done}/{planned} visits · {orders} today', {'done': vm.visitsDone, 'planned': vm.todays.length, 'orders': plural(vm.ordersToday.length, 'order')}),
                onTap: () => pushPage(context, const DailyReportPage()),
              ),
            ],
          ),
          const SizedBox(height: 24),
          const AppSettingsGroup(),
          const SizedBox(height: 24),
          const SignOutButton(),
        ], 3),
      ],
    );
  }
}
