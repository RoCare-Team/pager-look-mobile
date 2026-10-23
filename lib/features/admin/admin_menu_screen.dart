import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/json.dart';
import '../../core/widgets/widgets.dart';

/// "More" tab of the admin console — the remaining sidebar items.
class AdminMenuScreen extends ConsumerWidget {
  const AdminMenuScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    final email = str(auth.user?['email'], 'Platform admin');

    return Scaffold(
      appBar: AppBar(title: const Text('More')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          AppCard(
            child: Row(
              children: [
                AppAvatar(name: email, size: 48),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(email,
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.inkStrong)),
                      const SizedBox(height: 4),
                      const StatusBadge('platform_admin', tone: Tone.brand, label: 'Platform admin'),
                    ],
                  ),
                ),
              ],
            ),
          ),
          MenuSection(
            title: 'Console',
            children: [
              MenuTile(
                icon: Icons.fact_check_outlined,
                title: 'Verifications',
                subtitle: 'Every employment verification request',
                onTap: () => context.push('/admin/verifications'),
              ),
              MenuTile(
                icon: Icons.campaign_outlined,
                title: 'Demo requests',
                subtitle: 'Leads from the public site',
                onTap: () => context.push('/admin/demo-requests'),
              ),
            ],
          ),
          MenuSection(
            children: [
              MenuTile(
                icon: Icons.logout,
                title: 'Sign out',
                destructive: true,
                onTap: () async {
                  final ok = await showConfirmDialog(
                    context,
                    title: 'Sign out?',
                    confirmLabel: 'Sign out',
                    destructive: true,
                  );
                  if (!ok) return;
                  await ref.read(authProvider).logout();
                  if (context.mounted) context.go('/admin/login');
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}
