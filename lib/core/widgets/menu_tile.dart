import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Row in a settings / "More" menu (web: `SettingsRow`).
class MenuTile extends StatelessWidget {
  const MenuTile({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.onTap,
    this.trailing,
    this.destructive = false,
    this.locked = false,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final Widget? trailing;
  final bool destructive;
  final bool locked;

  @override
  Widget build(BuildContext context) {
    final color = destructive ? AppColors.danger : AppColors.inkStrong;
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: destructive ? AppColors.dangerBg : AppColors.brand50,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, size: 20, color: destructive ? AppColors.danger : AppColors.brand600),
      ),
      title: Text(title, style: TextStyle(fontWeight: FontWeight.w600, color: color, fontSize: 15)),
      subtitle: subtitle == null ? null : Text(subtitle!, style: const TextStyle(fontSize: 12.5)),
      trailing: trailing ??
          (locked
              ? const Icon(Icons.lock_outline, size: 18, color: AppColors.inkFaint)
              : (onTap == null || destructive ? null : const Icon(Icons.chevron_right, color: AppColors.inkFaint))),
    );
  }
}

/// Group of [MenuTile]s in a card with a small heading.
class MenuSection extends StatelessWidget {
  const MenuSection({super.key, this.title, required this.children});

  final String? title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
            child: Text(
              title!.toUpperCase(),
              style: const TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.8, color: AppColors.inkFaint),
            ),
          ),
        // A Material (not a decorated Container) so ListTile ink splashes show.
        Material(
          color: AppColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.card),
            side: const BorderSide(color: AppColors.hairline),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) const Divider(height: 1, indent: 64),
                children[i],
              ],
            ],
          ),
        ),
      ],
    );
  }
}
