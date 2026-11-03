import 'package:flutter/material.dart';

import '../../core/utils/sfx.dart';
import '../../domain/repositories/repositories.dart';
import 'ui.dart';

/// Runs a user action: shows [success] (if given) or the rule that was broken.
/// Returns true when it worked. Unexpected errors show a generic message.
/// With [errors], a problem with one form field shows under that field instead.
Future<bool> attempt(Future<void> Function() action, {String? success, String icon = 'check', bool confetti = false, FieldErrors? errors}) async {
  try {
    await action();
    if (success != null) {
      Sfx.success();
      Fx.toast(success, icon: icon);
      if (confetti) Fx.confetti();
    }
    return true;
  } on DomainError catch (e) {
    Sfx.error();
    if (errors != null && errors.knows(e.field)) {
      errors.set(e.field!, e.message);
    } else {
      Fx.toast(e.message, icon: 'alert', tone: 'bad');
    }
    return false;
  } catch (e) {
    Sfx.error();
    Fx.toast(tr('Something went wrong. Please try again.'), icon: 'alert', tone: 'bad');
    debugPrint('attempt failed: $e');
    return false;
  }
}

/// Yes/no confirmation as a bottom sheet. Returns true if confirmed.
Future<bool> confirmSheet(BuildContext context, {required String title, String? body, required String confirm, bool danger = false, String? cancel}) async {
  final ok = await showHSheet<bool>(
    context,
    (ctx) => VStack(gap: 14, [
      SheetHead(title, sub: body),
      HButton(confirm, block: true, kind: danger ? BtnKind.danger : BtnKind.primary, onTap: () => Navigator.pop(ctx, true)),
      HButton(cancel ?? tr('Not now'), block: true, kind: BtnKind.ghost, onTap: () => Navigator.pop(ctx, false)),
    ]),
  );
  return ok ?? false;
}

/// Asks for a short text (reason, note, reply). Returns null if dismissed.
Future<String?> askText(
  BuildContext context, {
  required String title,
  String? body,
  required String label,
  String hint = '',
  required String confirm,
  bool danger = false,
  int minLength = 0,
  bool multiline = true,
  TextInputType? keyboard,
}) {
  final ctl = TextEditingController();
  return showHSheet<String>(
    context,
    (ctx) => StatefulBuilder(
      builder: (ctx, set) => VStack(gap: 14, [
        SheetHead(title, sub: body),
        HField(label: label, hint: hint, controller: ctl, multiline: multiline, keyboard: keyboard, onChanged: (_) => set(() {})),
        HButton(confirm, block: true, kind: danger ? BtnKind.danger : BtnKind.primary, onTap: ctl.text.trim().length < minLength ? null : () => Navigator.pop(ctx, ctl.text.trim())),
      ]),
    ),
  );
}
