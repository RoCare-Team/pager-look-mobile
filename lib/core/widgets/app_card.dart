import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Card shell — port of the web `<Card title subtitle action>`.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    this.title,
    this.subtitle,
    this.action,
    this.child,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
    this.color,
    this.borderColor,
  });

  final String? title;
  final String? subtitle;
  final Widget? action;
  final Widget? child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? color;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final hasHeader = title != null || action != null;
    final content = Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (hasHeader)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (title != null)
                        Text(
                          title!,
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.inkStrong),
                        ),
                      if (subtitle != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(subtitle!, style: const TextStyle(fontSize: 12.5, color: AppColors.inkMuted)),
                        ),
                    ],
                  ),
                ),
                if (action != null) action!,
              ],
            ),
          if (hasHeader && child != null) const SizedBox(height: 12),
          if (child != null) child!,
        ],
      ),
    );

    return Material(
      color: color ?? AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.card),
        side: BorderSide(color: borderColor ?? AppColors.hairline),
      ),
      clipBehavior: Clip.antiAlias,
      child: onTap == null ? content : InkWell(onTap: onTap, child: content),
    );
  }
}

/// Label/value pair used in detail cards.
class InfoRow extends StatelessWidget {
  const InfoRow({super.key, required this.label, this.value, this.valueWidget, this.icon});

  final String label;
  final String? value;
  final Widget? valueWidget;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 18, color: AppColors.inkFaint),
            const SizedBox(width: 10),
          ],
          Expanded(
            flex: 2,
            child: Text(label, style: const TextStyle(fontSize: 13, color: AppColors.inkMuted)),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 3,
            child: valueWidget ??
                Text(
                  (value == null || value!.isEmpty) ? '—' : value!,
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500, color: AppColors.inkStrong),
                ),
          ),
        ],
      ),
    );
  }
}

/// Section heading inside a scrolling page.
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.subtitle, this.action, this.padding});

  final String title;
  final String? subtitle;
  final Widget? action;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding ?? const EdgeInsets.only(top: 20, bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.inkStrong)),
                if (subtitle != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(subtitle!, style: const TextStyle(fontSize: 12.5, color: AppColors.inkMuted)),
                  ),
              ],
            ),
          ),
          if (action != null) action!,
        ],
      ),
    );
  }
}

/// Page title block for the top of a screen body.
class PageIntro extends StatelessWidget {
  const PageIntro({super.key, required this.title, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.headlineSmall),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(subtitle!, style: const TextStyle(fontSize: 14, color: AppColors.inkMuted, height: 1.45)),
          ],
        ],
      ),
    );
  }
}

/// Metric tile — web `StatCard`.
class StatCard extends StatelessWidget {
  const StatCard({
    super.key,
    required this.label,
    required this.value,
    this.icon,
    this.tone = Tone.brand,
    this.caption,
    this.onTap,
  });

  final String label;
  final String value;
  final IconData? icon;
  final Tone tone;
  final String? caption;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              if (icon != null)
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(color: tone.bg, borderRadius: BorderRadius.circular(8)),
                  child: Icon(icon, size: 16, color: tone.fg),
                ),
              if (icon != null) const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.inkMuted),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: AppColors.inkStrong,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
          if (caption != null) ...[
            const SizedBox(height: 2),
            Text(caption!, style: const TextStyle(fontSize: 11.5, color: AppColors.inkFaint)),
          ],
        ],
      ),
    );
  }
}

/// Two-column grid of [StatCard]s that works on narrow phones.
class StatGrid extends StatelessWidget {
  const StatGrid({super.key, required this.children, this.columns = 2});

  final List<Widget> children;
  final int columns;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cols = constraints.maxWidth > 600 ? columns * 2 : columns;
        const gap = 10.0;
        final width = (constraints.maxWidth - gap * (cols - 1)) / cols;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: children.map((c) => SizedBox(width: width, child: c)).toList(),
        );
      },
    );
  }
}

/// Coloured callout for notes, warnings and errors.
class InfoBanner extends StatelessWidget {
  const InfoBanner({super.key, required this.message, this.title, this.tone = Tone.info, this.icon, this.action});

  final String message;
  final String? title;
  final Tone tone;
  final IconData? icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final defaultIcon = switch (tone) {
      Tone.success => Icons.check_circle_outline,
      Tone.warning => Icons.warning_amber_rounded,
      Tone.danger => Icons.error_outline,
      _ => Icons.info_outline,
    };
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: tone.bg,
        borderRadius: BorderRadius.circular(AppRadii.control),
        border: Border.all(color: tone.fg.withValues(alpha: 0.18)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon ?? defaultIcon, size: 18, color: tone.fg),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Text(title!, style: TextStyle(fontWeight: FontWeight.w600, color: tone.fg, fontSize: 13.5)),
                  ),
                Text(message, style: const TextStyle(fontSize: 13, color: AppColors.inkBody, height: 1.4)),
                if (action != null) Padding(padding: const EdgeInsets.only(top: 8), child: action!),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
