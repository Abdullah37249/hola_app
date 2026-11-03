import 'package:flutter/material.dart';

import '../../../core/utils/sfx.dart';
import '../../../shared/widgets/ui.dart';

/// Calm band + scrolling content. Pages with [back] get a glass top bar
/// (back button + [title]) that content scrolls beneath cleanly.
class AuthScaffold extends StatefulWidget {
  final List<Widget> children;
  final bool back;
  final double bandHeight;
  final String? title;
  const AuthScaffold({super.key, required this.children, this.back = false, this.bandHeight = 400, this.title});
  @override
  State<AuthScaffold> createState() => _AuthScaffoldState();
}

class _AuthScaffoldState extends State<AuthScaffold> {
  bool _scrolled = false;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final pad = MediaQuery.paddingOf(context);
    return Scaffold(
      backgroundColor: c.bg,
      body: Stack(
        children: [
          Band(role: 'login', height: pad.top + kBandBody), // same height as every screen
          NotificationListener<ScrollNotification>(
            onNotification: (n) {
              if (n.depth != 0) return false;
              final s = n.metrics.pixels > 24;
              if (s != _scrolled) setState(() => _scrolled = s);
              return false;
            },
            child: ListView(padding: EdgeInsets.fromLTRB(kGutter, pad.top + (widget.back ? 68 : 32), kGutter, 40 + pad.bottom), children: staggered(widget.children)),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: StatusScrim(
              show: _scrolled,
              height: widget.back ? 60 : 0,
              child: widget.back && widget.title != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 72),
                        child: Text(widget.title!, maxLines: 1, overflow: TextOverflow.ellipsis, style: T.ttl(context)),
                      ),
                    )
                  : null,
            ),
          ),
          if (widget.back)
            Positioned(
              top: pad.top + 8,
              left: 12,
              child: IconBtn(
                'back',
                raised: true,
                onTap: () {
                  Sfx.back();
                  Navigator.of(context).maybePop();
                },
              ),
            ),
        ],
      ),
    );
  }
}

/// White card the forms sit in.
class AuthCard extends StatelessWidget {
  final List<Widget> children;
  const AuthCard({super.key, required this.children});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
    decoration: BoxDecoration(
      color: context.c.surface,
      borderRadius: BorderRadius.circular(24),
      boxShadow: context.c.liftHi,
      border: context.c.dark ? null : Border.all(color: context.c.line.withValues(alpha: .7), width: .6),
    ),
    child: VStack(gap: 16, children),
  );
}

/// Title block on the band: optional logo/eyebrow, serif title, one-line intro.
class AuthHeading extends StatelessWidget {
  final String title, sub;
  final Widget? top;
  final String? eyebrow;
  const AuthHeading({super.key, required this.title, required this.sub, this.top, this.eyebrow});
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (top != null) ...[top!, const SizedBox(height: 28)],
      if (eyebrow != null) ...[Text(eyebrow!.toUpperCase(), style: T.eyebrow(context).copyWith(color: Colors.white.withValues(alpha: .72))), SizedBox(height: 6)],
      Text(title, style: T.display(context).copyWith(color: Colors.white)),
      SizedBox(height: 8),
      Text(sub, style: T.body(context).copyWith(color: Colors.white.withValues(alpha: .82))),
    ],
  );
}

class PasswordField extends StatelessWidget {
  final String? label;
  final String? hint;
  final TextEditingController? controller;
  final bool obscure;
  final VoidCallback onToggle;
  final ValueChanged<String>? onChanged;
  final TextInputAction? action;
  final ValueChanged<String>? onSubmitted;

  /// [AutofillHints.password] to sign in; [AutofillHints.newPassword] when choosing one.
  final String autofill;
  final String name;
  final FieldErrors? errors;
  const PasswordField({
    super.key,
    this.label,
    this.hint,
    this.controller,
    required this.obscure,
    required this.onToggle,
    this.onChanged,
    this.action,
    this.onSubmitted,
    this.autofill = AutofillHints.password,
    this.name = 'password',
    this.errors,
  });
  @override
  Widget build(BuildContext context) => HField(
    label: label ?? tr('Password'),
    hint: hint ?? tr('Password'), // like the email field's example text
    icon: 'shield',
    controller: controller,
    obscure: obscure,
    onChanged: onChanged,
    action: action,
    onSubmitted: onSubmitted,
    autofill: [autofill],
    name: name,
    errors: errors,
    suffix: IconButton(
      tooltip: obscure ? tr('Show password') : tr('Hide password'),
      onPressed: () {
        Sfx.toggle();
        onToggle();
      },
      icon: Icon(obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined, size: 20, color: context.c.muted),
    ),
  );
}

/// Four-segment strength bar with a hint underneath.
class StrengthMeter extends StatelessWidget {
  final int strength;
  final String hint;
  const StrengthMeter({super.key, required this.strength, required this.hint});
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final cols = [c.bad, c.accent, c.brand, c.ok];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            for (var i = 0; i < 4; i++) ...[
              if (i > 0) const SizedBox(width: 6),
              Expanded(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  height: 4,
                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(2), color: i < strength ? cols[strength - 1] : c.line),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 6),
        Text(
          hint,
          style: T.sm(context).copyWith(color: strength == 0 ? c.muted : [c.badInk, c.accentInk, c.brandText, c.ok][strength - 1], fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}
