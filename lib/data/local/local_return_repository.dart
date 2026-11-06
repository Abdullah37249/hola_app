import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../core/l10n/l10n.dart';
import '../../core/network/api.dart';
import '../../core/utils/clock.dart';
import '../../core/utils/format.dart';
import '../../core/utils/photo_files.dart';
import '../../domain/entities/entities.dart';
import '../../domain/entities/json.dart' show asInt;
import '../../domain/repositories/repositories.dart';
import 'hola_mirror.dart' show money;
import 'local_auth_repository.dart';

typedef J = Map<String, dynamic>;

/// Order returns (HOLA contract 0.23.0). A HOLA salon's requests live on the
/// server: HOLA prices them, sends a rider for the goods and, once the rider
/// has them, adjusts the credit ledger, issues the voucher or makes the
/// replacement order; the app mirrors what it says. On an on-device setup
/// (tests, no server) the same rules run here, with a sales officer acting
/// for HOLA.
class LocalReturnRepository extends LocalRepository implements ReturnRepository {
  LocalReturnRepository(super.db, {this.api});
  final HolaApi? api;

  /// HOLA's returns API is live (0.23.0). Until then HOLA salons can't file
  /// returns from the app.
  static bool returnsLive = true;

  @override
  bool get live => api == null || returnsLive;

  bool _holaSalon(String salonId) => api != null && (db.salons.where((s) => s.id == salonId).firstOrNull?.hola ?? false);
  bool get _server => api != null && returnsLive;

  NotifLink _link(ReturnRequest r) => NotifLink('return', r.id);

  // ── reads ──

  @override
  List<ReturnRequest> returns({String? salonId}) {
    final m = me;
    final sid = salonId ?? (m?.role == Role.salesOfficer ? null : m?.salonId);
    return db.returns.where((r) => sid == null || r.salonId == sid).toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  @override
  ReturnRequest? returnRequest(String id) => db.returns.where((r) => r.id == id).firstOrNull;

  @override
  List<ReturnRequest> returnsForOrder(String orderId) => db.returns.where((r) => r.orderId == orderId).toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  /// Units already taken by requests that weren't rejected or withdrawn.
  int _held(String orderId, String variantId) {
    var n = 0;
    for (final r in db.returns) {
      if (r.orderId != orderId || r.status == ReturnStatus.rejected || r.status == ReturnStatus.cancelled) continue;
      for (final i in r.items) {
        if (i.variantId == variantId) n += i.qty;
      }
    }
    return n;
  }

  @override
  int returnable(TradeOrder o, String variantId) {
    final bought = o.lines.where((l) => l.variantId == variantId).fold(0, (s, l) => s + l.qty + l.freeQty);
    final left = bought - _held(o.id, variantId);
    return left < 0 ? 0 : left;
  }

  @override
  bool canReturn(TradeOrder o) => (o.status == OrderStatus.delivered || o.status == OrderStatus.confirmed) && o.lines.any((l) => returnable(o, l.variantId) > 0);

  @override
  int unitValue(TradeOrder o, String variantId) {
    final l = o.lines.where((l) => l.variantId == variantId).firstOrNull;
    final units = l == null ? 0 : l.qty + l.freeQty;
    if (l == null || units == 0 || o.subtotal == 0) return 0;
    // What the line cost after the coupon, spread over every unit (free ones too).
    return (l.total * o.total / o.subtotal / units).floor();
  }

  // ── the salon ──

  @override
  Future<ReturnRequest> requestReturn({
    required String orderId,
    required String option,
    required String reason,
    String note = '',
    required Map<String, int> qty,
    List<String> photoPaths = const [],
  }) async {
    requireRole({Role.salonOwner});
    final m = requireMe;
    final o = db.orders.where((x) => x.id == orderId).firstOrNull ?? (throw DomainError(tr('Order not found.')));
    if (m.salonId != o.salonId) throw DomainError(tr('Not your salon.'));
    if (o.status != OrderStatus.delivered && o.status != OrderStatus.confirmed) throw DomainError(tr('Only a delivered order can be returned.'));
    if (option != ReturnOption.replace && option != ReturnOption.refund) throw DomainError(tr('Choose a replacement or a refund.'));
    if (!ReturnReason.all.contains(reason)) throw DomainError(tr('Choose why you are returning it.'), field: 'reason');
    if (reason == ReturnReason.other && note.trim().length < 3) throw DomainError(tr('Tell HOLA what is wrong.'), field: 'note');
    if (photoPaths.length > 6) throw DomainError(tr('Add up to 6 photos.'));
    final picked = {
      for (final e in qty.entries)
        if (e.value > 0) e.key: e.value,
    };
    if (picked.isEmpty) throw DomainError(tr('Pick at least one product to return.'));
    final items = <ReturnItem>[];
    for (final e in picked.entries) {
      final l = o.lines.where((l) => l.variantId == e.key).firstOrNull ?? (throw DomainError(tr('That product is not on this order.')));
      final left = returnable(o, e.key);
      if (e.value > left) {
        throw DomainError(left == 0 ? tr('{name} is already in another return.', {'name': l.name}) : tr('You can return at most {n} of {name}.', {'n': left, 'name': l.name}));
      }
      items.add(ReturnItem(orderItemId: l.itemId, variantId: l.variantId, name: l.name, qty: e.value, unitPrice: unitValue(o, l.variantId)));
    }

    if (_holaSalon(o.salonId)) {
      if (!returnsLive) throw DomainError(tr('Returns will open once HOLA switches them on.'));
      if (items.any((i) => i.orderItemId.isEmpty)) throw DomainError(tr('Refresh your orders and try again.'));
      final photoIds = <String>[];
      for (final p in photoPaths) {
        photoIds.add(await _upload(p));
      }
      final res = await _call(
        () => api!.post(
          '/salons/${o.salonId}/returns',
          {
            'orderId': o.id,
            'option': option,
            'reason': reason,
            if (note.trim().isNotEmpty) 'note': note.trim(),
            'items': [
              for (final i in items) {'orderItemId': i.orderItemId, 'qty': i.qty},
            ],
            if (photoIds.isNotEmpty) 'photoIds': photoIds,
          },
          headers: {'Idempotency-Key': db.newId() + db.newId()},
        ),
      );
      final r = mirrorReturn(_data(res));
      db.commit();
      return r;
    }

    final r = ReturnRequest(
      id: db.newId(),
      code: _nextCode(),
      salonId: o.salonId,
      orderId: o.id,
      orderCode: o.code,
      cod: o.isCod,
      option: option,
      reason: reason,
      note: note.trim(),
      items: items,
      photos: [for (final p in photoPaths) await _keep(p)],
      status: ReturnStatus.requested,
      history: [ReturnEvent(ReturnStatus.requested, now(), by: m.name, side: 'SALON', note: note.trim())],
      createdAt: now(),
    );
    db.returns.add(r);
    _openThread(r);
    db.notify(m.id, 'Return request sent', '{code} · {order} · {amount}', args: {'code': r.code, 'order': o.code, 'amount': rs(r.amount)}, icon: 'box', link: _link(r));
    db.notifyRole(Role.salesOfficer, 'New return request', '{salon} · {code} · {amount}', args: {'salon': _salonName(r.salonId), 'code': r.code, 'amount': rs(r.amount)}, icon: 'box', link: _link(r));
    db.commit();
    return r;
  }

  @override
  Future<void> cancelReturn(String id) async {
    final r = _mine(id);
    if (!ReturnStatus.cancellable.contains(r.status)) throw DomainError(tr('HOLA has already decided this request.'));
    if (_holaSalon(r.salonId)) return _post(r, 'cancel');
    _move(r, ReturnStatus.cancelled, side: 'SALON');
    db.notifyRole(Role.salesOfficer, 'Return withdrawn', '{salon} · {code}', args: {'salon': _salonName(r.salonId), 'code': r.code}, icon: 'x', link: _link(r));
    db.commit();
  }

  @override
  Future<void> acceptProposal(String id) async {
    final r = _mine(id);
    if (r.status != ReturnStatus.awaitingSalon || r.proposal == null) throw DomainError(tr('There is no offer to answer.'));
    if (_holaSalon(r.salonId)) return _post(r, 'accept');
    r.approvedAmount = r.proposal!.amount;
    _move(r, ReturnStatus.approved, side: 'SALON', note: 'Salon accepted the offer');
    db.notifyRole(Role.salesOfficer, 'Salon accepted the offer', '{salon} · {code}', args: {'salon': _salonName(r.salonId), 'code': r.code}, icon: 'check', link: _link(r));
    db.commit();
  }

  @override
  Future<void> declineProposal(String id, String note) async {
    final r = _mine(id);
    if (r.status != ReturnStatus.awaitingSalon) throw DomainError(tr('There is no offer to answer.'));
    if (_holaSalon(r.salonId)) return _post(r, 'decline', {if (note.trim().isNotEmpty) 'note': note.trim()});
    r.proposal = null;
    _move(r, ReturnStatus.underReview, side: 'SALON', note: note.trim());
    db.notifyRole(Role.salesOfficer, 'Salon declined the offer', '{salon} · {code}', args: {'salon': _salonName(r.salonId), 'code': r.code}, icon: 'x', link: _link(r));
    db.commit();
  }

  // ── HOLA's side (on the device: a sales officer) ──

  ReturnRequest _forHola(String id) {
    requireRole({Role.salesOfficer});
    final r = returnRequest(id) ?? (throw DomainError(tr('Return not found.')));
    if (_holaSalon(r.salonId)) throw DomainError(tr('HOLA handles this in the HOLA dashboard.'));
    return r;
  }

  void _undecided(ReturnRequest r) {
    if (!ReturnStatus.undecided.contains(r.status)) throw DomainError(tr('This return is already decided.'));
  }

  @override
  Future<void> startReview(String id) async {
    final r = _forHola(id);
    if (r.status != ReturnStatus.requested) return;
    _move(r, ReturnStatus.underReview, side: 'HOLA');
    _notifySalon(r, 'HOLA is reviewing your return', '{code} · {order}');
    db.commit();
  }

  @override
  Future<void> respond(String id, String note) async {
    final r = _forHola(id);
    _undecided(r);
    if (note.trim().length < 2) throw DomainError(tr('Write a message.'), field: 'note');
    _say(r, note.trim());
    _move(r, ReturnStatus.responseSent, side: 'HOLA', note: note.trim());
    _notifySalon(r, 'HOLA replied about your return', '{code}: {note}', {'note': note.trim()});
    db.commit();
  }

  @override
  Future<void> approveReturn(String id, {String note = ''}) async {
    final r = _forHola(id);
    _undecided(r);
    // A cash order's money-back return is settled by an offer the salon accepts.
    if (r.option == ReturnOption.refund && r.cod) throw DomainError(tr('Offer a voucher or a replacement for a cash order.'));
    r.approvedAmount = r.amount;
    _move(r, ReturnStatus.approved, side: 'HOLA', note: note.trim());
    _notifySalon(r, 'Return approved', '{code}: a rider will collect the products');
    db.commit();
  }

  @override
  Future<void> rejectReturn(String id, String reason) async {
    final r = _forHola(id);
    if (!ReturnStatus.undecided.contains(r.status) && r.status != ReturnStatus.awaitingSalon) throw DomainError(tr('This return is already decided.'));
    if (reason.trim().length < 3) throw DomainError(tr('Tell the salon why.'), field: 'reason');
    r.rejectReason = reason.trim();
    _move(r, ReturnStatus.rejected, side: 'HOLA', note: reason.trim());
    _notifySalon(r, 'Return rejected', '{code}: {note}', {'note': reason.trim()});
    db.commit();
  }

  @override
  Future<void> proposeSettlement(String id, {required String settlement, int validDays = 90, String note = ''}) async {
    final r = _forHola(id);
    if (!r.cod || r.option != ReturnOption.refund) throw DomainError(tr('Offers are for cash orders asking for money back.'));
    _undecided(r);
    if (settlement != Settlement.voucher && settlement != Settlement.replace) throw DomainError(tr('Choose a voucher or a replacement.'));
    r.proposal = ReturnProposal(settlement: settlement, amount: r.amount, validUntil: settlement == Settlement.voucher ? addDays(today, validDays) : null, note: note.trim(), proposedAt: now());
    _move(r, ReturnStatus.awaitingSalon, side: 'HOLA', note: note.trim());
    _notifySalon(r, 'HOLA sent an offer', '{code}: {offer}', {'offer': settlement == Settlement.voucher ? 'a voucher of ${rs(r.amount)}' : 'replace the products'});
    db.commit();
  }

  @override
  Future<void> assignPickup(String id, String riderId, {DateTime? expectedOn}) async {
    final r = _forHola(id);
    if (r.status != ReturnStatus.approved) throw DomainError(tr('Approve the return first.'));
    final rider = db.accounts.where((a) => a.id == riderId && a.role == Role.rider).firstOrNull ?? (throw DomainError(tr('Choose a rider.')));
    r.pickup = ReturnPickup(riderId: rider.id, riderName: rider.name, assignedAt: now(), expectedOn: expectedOn);
    _move(r, ReturnStatus.pickupAssigned, side: 'HOLA', note: rider.name);
    _notifySalon(r, 'Pickup assigned', '{code}: {rider} will collect the products', {'rider': rider.name});
    db.notify(rider.id, 'Return pickup', '{salon} · {code}', args: {'salon': _salonName(r.salonId), 'code': r.code}, icon: 'truck', link: _link(r));
    db.commit();
  }

  // ── the rider ──

  /// A rider's pickups name the salon, which the rider's phone may not have.
  final _pickupInfo = <String, ({String salon, String phone, String address})>{};

  @override
  List<ReturnPickupTask> pickups() {
    final m = me;
    if (m == null || m.role != Role.rider) return const [];
    return [
      for (final r in db.returns.where((r) => r.status == ReturnStatus.pickupAssigned && r.pickup?.riderId == m.id && r.pickup?.collectedAt == null))
        ReturnPickupTask(
          returnId: r.id,
          code: r.code,
          salonName: _pickupInfo[r.id]?.salon ?? _salonName(r.salonId),
          salonPhone: _pickupInfo[r.id]?.phone ?? db.salons.where((s) => s.id == r.salonId).firstOrNull?.phone ?? '',
          address: _pickupInfo[r.id]?.address ?? db.branches.where((b) => b.salonId == r.salonId && !b.id.endsWith('~delivery')).firstOrNull?.address ?? '',
          items: r.items,
          expectedOn: r.pickup?.expectedOn,
        ),
    ];
  }

  @override
  Future<void> syncPickups() async {
    if (!_server || me?.role != Role.rider) return;
    try {
      final res = await api!.get('/rider/return-pickups');
      final seen = <String>{};
      for (final j in (res is Map ? (res['data'] as List? ?? const []) : res as List).cast<J>()) {
        seen.add(mirrorReturn(j, pickupOnly: true).id);
      }
      // Pickups no longer on the list were collected or taken off this rider.
      db.returns.removeWhere((r) => r.status == ReturnStatus.pickupAssigned && r.pickup?.riderId == me?.id && !seen.contains(r.id));
      db.commit();
    } catch (e) {
      debugPrint('Returns: pickups failed: $e');
    }
  }

  @override
  Future<void> collectPickup(String returnId) async {
    requireRole({Role.rider});
    final r = returnRequest(returnId) ?? (throw DomainError(tr('Return not found.')));
    if (r.status != ReturnStatus.pickupAssigned || r.pickup?.riderId != requireMe.id) throw DomainError(tr('This pickup is not yours.'));
    if (_server) {
      final res = await _call(() => api!.post('/rider/return-pickups/${r.id}/collect', const {}, headers: {'Idempotency-Key': db.newId() + db.newId()}));
      final j = _data(res);
      final x = j.isEmpty ? r : mirrorReturn(j, pickupOnly: true);
      x.pickup?.collectedAt ??= DateTime.tryParse('${j['collectedAt'] ?? ''}')?.toLocal() ?? now();
      db.commit();
      return;
    }
    r.pickup!.collectedAt = now();
    _settle(r);
    db.commit();
  }

  // ── settlement: only once the rider has the goods ──

  void _settle(ReturnRequest r) {
    final amount = r.approvedAmount ?? r.amount;
    switch (r.outcome) {
      case SettlementType.creditAdjusted:
        db.credit.add(CreditEntry(id: db.newId(), salonId: r.salonId, kind: 'RETURN', amount: amount, ref: r.code, note: r.orderCode, at: now()));
        r.settlement = ReturnSettlement(type: SettlementType.creditAdjusted, amount: amount);
        _move(r, ReturnStatus.completed, side: 'RIDER', action: 'CREDIT_ADJUSTED');
        _notifySalon(r, 'Outstanding adjusted', '{code}: {amount} taken off what you owe', {'amount': rs(amount)});
      case SettlementType.voucher:
        final v = ReturnVoucher(id: db.newId(), code: 'HV-${r.code.split('-').last}', amount: amount, validUntil: r.proposal?.validUntil ?? addDays(today, 90));
        r.settlement = ReturnSettlement(type: SettlementType.voucher, amount: amount, voucher: v);
        _move(r, ReturnStatus.completed, side: 'RIDER', action: 'VOUCHER', note: v.code);
        _notifySalon(r, 'Voucher ready', '{code}: voucher {voucher} for {amount}', {'voucher': v.code, 'amount': rs(amount)});
      default:
        final o = db.orders.where((x) => x.id == r.orderId).firstOrNull;
        final repl = TradeOrder(
          id: db.newId(),
          code: db.nextOrderCode(),
          salonId: r.salonId,
          placedById: o?.placedById ?? requireMe.id,
          lines: [
            for (final i in r.items)
              OrderLine(productId: o?.lines.where((l) => l.variantId == i.variantId).firstOrNull?.productId ?? '', variantId: i.variantId, name: i.name, qty: i.qty, freeQty: 0, unitPrice: 0),
          ],
          payment: o?.payment ?? PaymentMethod.credit,
          notes: 'Replacement for return ${r.code}',
          // Already approved: HOLA sends it like any order.
          status: OrderStatus.approved,
          history: [StatusEvent(OrderStatus.placed, now(), 'system', r.code), StatusEvent(OrderStatus.approved, now(), 'system', r.code)],
          createdAt: now(),
          replacementFor: r.code,
          replacementOfOrder: r.orderCode,
        );
        db.orders.add(repl);
        r.settlement = ReturnSettlement(type: SettlementType.replacement, amount: amount, replacementOrderId: repl.id, replacementOrderCode: repl.code);
        _move(r, ReturnStatus.replacementCreated, side: 'RIDER', action: 'REPLACEMENT', note: repl.code);
        _notifySalon(r, 'Replacement order created', '{code}: replacement order {order2}', {'order2': repl.code});
        db.notifyRole(
          Role.salesOfficer,
          'Replacement order to send',
          '{salon} · {order2}',
          args: {'salon': _salonName(r.salonId), 'order2': repl.code},
          icon: 'box',
          link: NotifLink('order', repl.id),
        );
    }
  }

  /// Ends returns whose replacement order has arrived; true if any did.
  bool _finishReplacements() {
    var changed = false;
    for (final r in db.returns.where((r) => r.status == ReturnStatus.replacementCreated).toList()) {
      final repl = db.orders.where((o) => o.id == r.settlement?.replacementOrderId).firstOrNull;
      if (repl != null && (repl.status == OrderStatus.delivered || repl.status == OrderStatus.confirmed)) {
        _move(r, ReturnStatus.completed, side: 'HOLA');
        changed = true;
      }
    }
    return changed;
  }

  // ── sync with HOLA ──

  @override
  Future<void> syncReturns() async {
    final m = me;
    if (m == null) return;
    if (api == null) {
      if (_finishReplacements()) db.commit();
      return;
    }
    if (m.role == Role.rider) return syncPickups();
    if (!returnsLive || m.salonId == null || !_holaSalon(m.salonId!)) return;
    try {
      for (var page = 1, pages = 1; page <= pages; page++) {
        final res = await api!.get('/salons/${m.salonId}/returns', query: {'page': '$page', 'pageSize': '50'});
        final list = (res is Map ? (res['data'] as List? ?? const []) : res as List).cast<J>();
        if (res is Map) pages = asInt((res['meta'] as Map?)?['totalPages'], 1);
        for (final j in list) {
          mirrorReturn(j);
        }
      }
      db.commit();
    } catch (e) {
      debugPrint('Returns: sync failed: $e');
    }
  }

  @override
  Future<void> syncReturn(String id) async {
    if (!_server || me?.role == Role.rider) return;
    final r = returnRequest(id);
    if (r != null && !_holaSalon(r.salonId)) return;
    try {
      final j = _data(await api!.get('/returns/$id'));
      try {
        final tl = await api!.get('/returns/$id/timeline');
        j['timeline'] = tl is Map ? (tl['data'] ?? const []) : tl;
      } catch (_) {}
      mirrorReturn(j);
      db.commit();
    } catch (e) {
      debugPrint('Returns: $id failed: $e');
    }
  }

  Future<void> _post(ReturnRequest r, String action, [Map<String, Object?>? body]) async {
    final res = await _call(() => api!.post('/returns/${r.id}/$action', {...?body, 'version': r.version}, headers: {'Idempotency-Key': db.newId() + db.newId()}));
    final j = _data(res);
    j.isEmpty ? await syncReturn(r.id) : mirrorReturn(j);
    db.commit();
  }

  /// HOLA's ReturnView (or a rider's pickup) as a [ReturnRequest].
  ReturnRequest mirrorReturn(J j, {bool pickupOnly = false}) {
    Map p(Object? v) => v is Map ? v : const {};
    final id = '${j['returnId'] ?? j['id']}';
    final old = returnRequest(id);
    final order = p(j['order']), proposal = p(j['proposal']), settle = p(j['settlement']), pickup = p(j['pickup']), salon = p(j['salon']);
    final voucher = p(settle['voucher']), repl = p(settle['replacementOrder']);
    DateTime? when(Object? v) => DateTime.tryParse('${v ?? ''}')?.toLocal();
    final r = ReturnRequest(
      id: id,
      code: '${j['code'] ?? j['returnCode'] ?? old?.code ?? ''}',
      salonId: '${salon['id'] ?? j['salonId'] ?? old?.salonId ?? ''}',
      orderId: '${order['id'] ?? j['orderId'] ?? old?.orderId ?? ''}',
      orderCode: '${order['code'] ?? j['orderCode'] ?? old?.orderCode ?? ''}',
      cod: order.isEmpty ? (old?.cod ?? false) : order['paymentMethod'] == 'COD',
      option: '${j['option'] ?? old?.option ?? ReturnOption.replace}',
      reason: '${j['reason'] ?? old?.reason ?? ReturnReason.other}',
      note: '${j['note'] ?? old?.note ?? ''}',
      items: j['items'] is List
          ? [
              for (final i in (j['items'] as List).cast<Map>())
                ReturnItem(
                  orderItemId: '${i['orderItemId'] ?? ''}',
                  variantId: '${i['variantId'] ?? ''}',
                  name: [i['product'] ?? i['name'], i['variant']].where((v) => v is String && v.isNotEmpty).join(' · '),
                  qty: asInt(i['qty']),
                  unitPrice: money(i['unitPrice']),
                ),
            ]
          : (old?.items ?? []),
      photos: j['photos'] is List ? [for (final x in (j['photos'] as List)) x is Map ? '${x['fileId'] ?? x['id']}' : '$x'] : (old?.photos ?? []),
      status: '${j['status'] ?? (pickupOnly ? ReturnStatus.pickupAssigned : null) ?? old?.status ?? ReturnStatus.requested}',
      approvedAmount: j['approvedAmount'] == null ? old?.approvedAmount : money(j['approvedAmount']),
      proposal: proposal.isEmpty
          ? (j.containsKey('proposal') ? null : old?.proposal)
          : ReturnProposal(
              settlement: '${proposal['settlement']}',
              amount: money(proposal['amount']),
              validUntil: when(proposal['validUntil']),
              note: '${proposal['note'] ?? ''}',
              proposedAt: when(proposal['proposedAt']) ?? now(),
            ),
      pickup: pickup.isNotEmpty
          ? ReturnPickup(
              riderId: '${p(pickup['rider'])['id'] ?? ''}',
              riderName: '${p(pickup['rider'])['fullName'] ?? ''}',
              assignedAt: when(pickup['assignedAt']) ?? now(),
              expectedOn: when(pickup['expectedOn']),
              collectedAt: when(pickup['collectedAt']),
            )
          : pickupOnly
          ? ReturnPickup(riderId: me?.id ?? '', riderName: me?.name ?? '', assignedAt: when(j['assignedAt']) ?? now(), expectedOn: when(j['expectedOn']))
          : (j.containsKey('pickup') ? null : old?.pickup),
      settlement: settle.isEmpty
          ? (j.containsKey('settlement') ? null : old?.settlement)
          : ReturnSettlement(
              type: '${settle['type']}',
              amount: money(settle['amount']),
              voucher: voucher.isEmpty
                  ? null
                  : ReturnVoucher(
                      id: '${voucher['id']}',
                      code: '${voucher['code']}',
                      amount: money(voucher['amount']),
                      validUntil: when(voucher['validUntil']),
                      status: voucher['used'] == true ? 'USED' : '${voucher['status'] ?? 'ACTIVE'}',
                    ),
              replacementOrderId: repl['id'] as String?,
              replacementOrderCode: repl['code'] as String?,
            ),
      conversationId: (j['conversationId'] ?? old?.conversationId) as String?,
      rejectReason: (j['rejectReason'] ?? j['rejectionReason'] ?? old?.rejectReason) as String?,
      history: old?.history ?? [],
      createdAt: when(j['createdAt']) ?? old?.createdAt ?? now(),
      version: asInt(j['version'], old?.version ?? 1),
    );
    if (j['timeline'] is List) {
      r.history
        ..clear()
        ..addAll([
          for (final e in (j['timeline'] as List).cast<Map>())
            ReturnEvent(
              '${e['to'] ?? e['status'] ?? ''}',
              when(e['at']) ?? now(),
              by: '${p(e['actor'])['fullName'] ?? ''}',
              side: '${p(e['actor'])['side'] ?? e['side'] ?? ''}',
              action: '${e['action'] ?? ''}',
              note: '${e['note'] ?? ''}',
            ),
        ]);
    } else if (r.history.isEmpty || r.history.last.status != r.status) {
      r.history.add(ReturnEvent(r.status, when(j['updatedAt']) ?? now()));
    }
    final at = db.returns.indexWhere((x) => x.id == id);
    at < 0 ? db.returns.add(r) : db.returns[at] = r;
    if (pickupOnly) {
      // The pickup row has the delivery address on its own (0.23.0).
      final a = p(j['address']);
      final where = a.isEmpty ? '${salon['address'] ?? ''}' : [a['addressLine'], a['area'], a['city']].where((x) => x is String && x.isNotEmpty).join(', ');
      _pickupInfo[id] = (salon: '${salon['name'] ?? j['salonName'] ?? ''}', phone: '${salon['phone'] ?? a['phone'] ?? ''}', address: where);
    }
    return r;
  }

  // ── helpers ──

  ReturnRequest _mine(String id) {
    requireRole({Role.salonOwner});
    final r = returnRequest(id) ?? (throw DomainError(tr('Return not found.')));
    if (r.salonId != requireMe.salonId) throw DomainError(tr('Not your salon.'));
    return r;
  }

  void _move(ReturnRequest r, String to, {String side = '', String action = '', String note = ''}) {
    r
      ..status = to
      ..version += 1;
    r.history.add(ReturnEvent(to, now(), by: me?.name ?? '', side: side, action: action, note: note));
  }

  String _salonName(String id) => db.salons.where((s) => s.id == id).firstOrNull?.name ?? '';

  void _notifySalon(ReturnRequest r, String title, String body, [Map<String, String> extra = const {}]) {
    final owner = db.salons.where((s) => s.id == r.salonId).firstOrNull?.ownerId;
    if (owner == null) return;
    db.notify(owner, title, body, args: {'code': r.code, 'order': r.orderCode, ...extra}, icon: 'box', link: _link(r));
  }

  /// The return's own conversation with HOLA, opened with the salon's
  /// reason (on the device; HOLA makes it on the server).
  void _openThread(ReturnRequest r) {
    final t = ChatThread(id: db.newId(), kind: ChatKind.holaSalon, salonId: r.salonId, salonName: _salonName(r.salonId), contextType: 'RETURN', contextId: r.id, contextCode: r.code, lastAt: now());
    db.threads.add(t);
    r.conversationId = t.id;
    final text = [tr(returnReasonLabel(r.reason)), if (r.note.isNotEmpty) r.note].join(': ');
    db.messages.add(ChatMessage(id: db.newId(), threadId: t.id, senderId: requireMe.id, side: ChatSide.salon, senderName: requireMe.name, text: text, at: now(), delivered: true));
  }

  /// HOLA's note, into the return's conversation.
  void _say(ReturnRequest r, String text) {
    final tid = r.conversationId;
    if (tid == null) return;
    db.messages.add(ChatMessage(id: db.newId(), threadId: tid, senderId: requireMe.id, side: ChatSide.hola, senderName: requireMe.name, text: text, at: now(), delivered: true));
    db.threads.where((t) => t.id == tid).firstOrNull?.lastAt = now();
  }

  String _nextCode() => 'HR-${(db.returns.length + 1).toString().padLeft(6, '0')}';

  Future<String> _keep(String path) async {
    try {
      return await PhotoFiles.keep(path);
    } catch (_) {
      return path;
    }
  }

  Future<String> _upload(String path) async {
    try {
      final png = path.toLowerCase().endsWith('.png');
      return await api!.uploadFile(await File(path).readAsBytes(), contentType: png ? 'image/png' : 'image/jpeg', purpose: 'return_photo', fileName: 'return.${png ? 'png' : 'jpg'}');
    } on ApiError catch (e) {
      throw apiToDomain(e);
    }
  }

  J _data(Object? res) => res is Map ? ((res['data'] is Map ? res['data'] : res) as Map).cast<String, dynamic>() : <String, dynamic>{};

  Future<Object?> _call(Future<Object?> Function() f) async {
    try {
      return await f();
    } on ApiError catch (e) {
      if (e.status == 409) throw DomainError(e.detail.isEmpty ? tr('These products are already in another return.') : e.detail);
      throw apiToDomain(e);
    }
  }
}
