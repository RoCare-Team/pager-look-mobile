import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// One tile in an [IconGridSection].
class GridAction {
  const GridAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.locked = false,
    this.badge,
    this.color,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  /// Shows a lock instead of the icon (feature needs verification first).
  final bool locked;

  /// Small pill over the tile, e.g. `NEW` or a count.
  final String? badge;

  /// Accent for the icon and its tinted tile; defaults to the sky accent.
  final Color? color;
}

/// White card with a title and a 4-per-row grid of icon tiles —
/// the sectioned "services" layout of super-apps like Paytm.
class IconGridSection extends StatelessWidget {
  const IconGridSection({super.key, required this.title, required this.actions, this.trailing});

  final String title;
  final List<GridAction> actions;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 6),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [BoxShadow(color: Color(0x0F0E1D4A), blurRadius: 16, offset: Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.brand900),
                  ),
                ),
                if (trailing != null) trailing!,
              ],
            ),
          ),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth / 4;
              return Wrap(
                children: [for (final a in actions) SizedBox(width: width, child: _Tile(action: a))],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.action});

  final GridAction action;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: action.onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
        child: Column(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: action.locked
                        ? const Color(0xFFF2F3F5)
                        : (action.color?.withValues(alpha: 0.12) ?? AppColors.skyBg),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(
                    action.locked ? Icons.lock_outline_rounded : action.icon,
                    size: 26,
                    color: action.locked ? AppColors.inkFaint : (action.color ?? AppColors.skyDeep),
                  ),
                ),
                if (action.badge != null)
                  Positioned(
                    top: -6,
                    right: -10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.danger,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: Colors.white, width: 1.5),
                      ),
                      child: Text(
                        action.badge!,
                        style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, color: Colors.white),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 7),
            Text(
              action.label,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style:
                  const TextStyle(fontSize: 12, height: 1.2, fontWeight: FontWeight.w500, color: AppColors.inkStrong),
            ),
          ],
        ),
      ),
    );
  }
}
