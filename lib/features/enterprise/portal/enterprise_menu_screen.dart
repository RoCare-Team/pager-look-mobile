import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/company_permissions.dart';
import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/json.dart';
import '../../../core/widgets/widgets.dart';

/// "More" tab — the rest of the web sidebar, filtered by the user's company
/// role exactly like `enterprise/Sidebar.jsx`.
class EnterpriseMenuScreen extends ConsumerWidget {
  const EnterpriseMenuScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    final perms = ref.watch(companyPermissionsProvider).valueOrNull ?? const CompanyPermissions();
    final companyName = str(auth.company?['name'], 'Your company');
    final email = str(auth.user?['email']);

    Widget item(String module, IconData icon, String title, String subtitle, String path) => MenuTile(
          icon: icon,
          title: title,
          subtitle: subtitle,
          onTap: () => context.push(path),
        );

    return Scaffold(
      appBar: AppBar(title: const Text('More')),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(companyPermissionsProvider),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            AppCard(
              child: Row(
                children: [
                  AppAvatar(name: companyName, size: 48),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(companyName,
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.inkStrong)),
                        if (email.isNotEmpty)
                          Text(email, style: const TextStyle(fontSize: 13, color: AppColors.inkMuted)),
                        if (perms.roleLabel.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: StatusBadge(perms.roleLabel, tone: Tone.brand),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            MenuSection(
              title: 'People',
              children: [
                if (perms.canSee('workforce'))
                  item('workforce', Icons.badge_outlined, 'Workforce', 'Everyone linked to your company',
                      '/enterprise/workforce'),
                if (perms.canSee('join_requests'))
                  item('join_requests', Icons.person_add_alt, 'Join Requests', 'People asking to join via QR',
                      '/enterprise/join-requests'),
              ],
            ),
            MenuSection(
              title: 'Insights',
              children: [
                if (perms.canSee('dashboard'))
                  item('dashboard', Icons.insights_outlined, 'Company Insights', 'Trust trends and verification health',
                      '/company/insights'),
                if (perms.canSee('settings'))
                  item('settings', Icons.receipt_long_outlined, 'Audit Logs', 'Every action taken in your workspace',
                      '/company/audit-logs'),
              ],
            ),
            MenuSection(
              title: 'Setup',
              children: [
                if (perms.canSee('qr_onboarding'))
                  item('qr_onboarding', Icons.qr_code_2, 'QR & Onboarding', 'Join codes for new hires',
                      '/enterprise/qr-onboarding'),
                if (perms.canSee('company_users'))
                  item('company_users', Icons.admin_panel_settings_outlined, 'Company Users', 'Staff accounts and roles',
                      '/enterprise/users'),
                if (perms.canSee('settings'))
                  item('settings', Icons.settings_outlined, 'Settings', 'Company profile, email and security',
                      '/enterprise/settings'),
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
                      message: 'You will need to sign in again to access your workspace.',
                      confirmLabel: 'Sign out',
                      destructive: true,
                    );
                    if (!ok) return;
                    await ref.read(authProvider).logout();
                    if (context.mounted) context.go('/enterprise/login');
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
