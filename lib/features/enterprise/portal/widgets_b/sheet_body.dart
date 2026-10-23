import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';

/// Opens a scroll-controlled bottom sheet that stays above the keyboard —
/// the mobile stand-in for the web's modals.
Future<T?> showAppSheet<T>(BuildContext context, {required WidgetBuilder builder}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
      child: builder(ctx),
    ),
  );
}

/// Title + scrolling body + pinned actions for a bottom sheet.
class SheetBody extends StatelessWidget {
  const SheetBody({
    super.key,
    required this.title,
    this.subtitle,
    required this.children,
    this.actions = const [],
  });

  final String title;
  final String? subtitle;
  final List<Widget> children;

  /// Stacked vertically under the scrolling content.
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.inkStrong),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 4),
                  Text(subtitle!, style: const TextStyle(fontSize: 13.5, color: AppColors.inkMuted, height: 1.4)),
                ],
                const SizedBox(height: 16),
                ...children,
              ],
            ),
          ),
        ),
        if (actions.isNotEmpty)
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < actions.length; i++) ...[
                    if (i > 0) const SizedBox(height: 8),
                    actions[i],
                  ],
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// Two or more buttons sharing a row equally.
class SheetButtonRow extends StatelessWidget {
  const SheetButtonRow({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) const SizedBox(width: 10),
          Expanded(child: children[i]),
        ],
      ],
    );
  }
}

/// Small uppercase label above a value (web `<dt>/<dd>` pairs).
class LabeledValue extends StatelessWidget {
  const LabeledValue({super.key, required this.label, required this.value, this.valueWidget});

  final String label;
  final String value;
  final Widget? valueWidget;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.6,
              color: AppColors.inkFaint,
            ),
          ),
          const SizedBox(height: 3),
          valueWidget ??
              Text(
                value.isEmpty ? '—' : value,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: AppColors.inkStrong),
              ),
        ],
      ),
    );
  }
}

/// Bordered toggle button used for two-way choices (Verified / Not verified).
class ChoiceToggle extends StatelessWidget {
  const ChoiceToggle({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.tone = Tone.brand,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final Tone tone;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        backgroundColor: selected ? tone.bg : AppColors.surface,
        foregroundColor: selected ? tone.fg : AppColors.inkBody,
        side: BorderSide(color: selected ? tone.fg : AppColors.line),
      ),
      child: Text(label),
    );
  }
}
