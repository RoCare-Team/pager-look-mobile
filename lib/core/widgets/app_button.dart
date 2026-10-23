import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

enum AppButtonVariant { primary, secondary, outline, danger, ghost }

/// Primary action button. Shows a spinner and blocks taps while [loading].
class AppButton extends StatelessWidget {
  const AppButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.variant = AppButtonVariant.primary,
    this.loading = false,
    this.icon,
    this.expand = true,
    this.compact = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final AppButtonVariant variant;
  final bool loading;
  final IconData? icon;

  /// Full width (default) — the common case on mobile forms.
  final bool expand;

  /// Smaller height for inline/card actions.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !loading;
    final minSize = Size(compact ? 36 : 48, compact ? 36 : 48);
    final padding = EdgeInsets.symmetric(horizontal: compact ? 12 : 18);

    final spinnerColor = switch (variant) {
      AppButtonVariant.primary || AppButtonVariant.danger => Colors.white,
      _ => AppColors.brand600,
    };

    final child = Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (loading)
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2, color: spinnerColor),
          )
        else if (icon != null)
          Icon(icon, size: compact ? 16 : 18),
        if (loading || icon != null) const SizedBox(width: 8),
        Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
      ],
    );

    final callback = enabled ? onPressed : null;
    final Widget button = switch (variant) {
      AppButtonVariant.primary => FilledButton(
          onPressed: callback,
          style: FilledButton.styleFrom(minimumSize: minSize, padding: padding),
          child: child,
        ),
      AppButtonVariant.danger => FilledButton(
          onPressed: callback,
          style: FilledButton.styleFrom(
            minimumSize: minSize,
            padding: padding,
            backgroundColor: AppColors.danger,
            disabledBackgroundColor: AppColors.dangerBg,
          ),
          child: child,
        ),
      AppButtonVariant.secondary => FilledButton(
          onPressed: callback,
          style: FilledButton.styleFrom(
            minimumSize: minSize,
            padding: padding,
            backgroundColor: AppColors.brand50,
            foregroundColor: AppColors.brand600,
            disabledBackgroundColor: AppColors.hairline,
            disabledForegroundColor: AppColors.inkFaint,
          ),
          child: child,
        ),
      AppButtonVariant.outline => OutlinedButton(
          onPressed: callback,
          style: OutlinedButton.styleFrom(minimumSize: minSize, padding: padding),
          child: child,
        ),
      AppButtonVariant.ghost => TextButton(
          onPressed: callback,
          style: TextButton.styleFrom(minimumSize: minSize, padding: padding),
          child: child,
        ),
    };

    return expand ? SizedBox(width: double.infinity, child: button) : button;
  }
}
