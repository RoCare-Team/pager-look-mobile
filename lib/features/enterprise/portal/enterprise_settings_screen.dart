import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/company_permissions.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/json.dart';
import '../../../core/widgets/widgets.dart';
import 'widgets_b/settings_sections.dart';

final _workspaceProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  return asMap(await ref.watch(enterpriseApiProvider).fetchWorkspace());
});

const _tabs = {'general': 'General', 'team': 'Team', 'security': 'Security'};

/// Port of `pages/enterprise/Settings.jsx` — workspace profile, SMTP, team
/// admin, change password.
class EnterpriseSettingsScreen extends ConsumerStatefulWidget {
  const EnterpriseSettingsScreen({super.key});

  @override
  ConsumerState<EnterpriseSettingsScreen> createState() => _EnterpriseSettingsScreenState();
}

class _EnterpriseSettingsScreenState extends ConsumerState<EnterpriseSettingsScreen> {
  String _tab = 'general';

  Future<void> _refresh() async {
    ref.invalidate(smtpSettingsProvider);
    try {
      final _ = await ref.refresh(_workspaceProvider.future);
    } catch (_) {}
  }

  Future<void> _signOut() async {
    final ok = await showConfirmDialog(
      context,
      title: 'Sign out?',
      message: 'You will need to sign in again to access your workspace.',
      confirmLabel: 'Sign out',
      destructive: true,
    );
    if (!ok) return;
    await ref.read(authProvider).logout();
    if (mounted) context.go('/enterprise/login');
  }

  @override
  Widget build(BuildContext context) {
    final workspaceAsync = ref.watch(_workspaceProvider);
    final authCompany = ref.watch(authProvider.select((a) => a.company));
    final perms = ref.watch(companyPermissionsProvider).valueOrNull ?? const CompanyPermissions();
    final canManageSettings = !perms.ready || perms.can('settings', 'manage');

    final workspace = workspaceAsync.valueOrNull;
    // Web: `workspace || authCompany`.
    final company = (workspace != null && workspace.isNotEmpty) ? workspace : asMap(authCompany);
    final companyName = str(company['name']);

    if (workspaceAsync.isLoading && !workspaceAsync.hasValue && company.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Settings & Team')),
        body: const LoadingView(label: 'Loading settings...'),
      );
    }

    final admin = workspace == null ? null : workspace['admin'];
    final adminMap = admin is Map ? asMap(admin) : null;

    final sections = <Widget>[
      if (_tab == 'general') ...[
        _WorkspaceCard(company: company),
        const SizedBox(height: 16),
        SmtpSettingsCard(canManage: canManageSettings),
        const SizedBox(height: 16),
        _TeamMembersCard(admin: adminMap, companyName: companyName),
        const SizedBox(height: 16),
        const _SecurityLinks(),
      ],
      if (_tab == 'team') _TeamMembersCard(admin: adminMap, companyName: companyName),
      if (_tab == 'security') ...[
        const ChangePasswordCard(),
        const SizedBox(height: 16),
        const _SecurityLinks(),
        const SizedBox(height: 16),
        _PlanCard(totalEmployees: asInt(workspace?['totalEmployees'] ?? company['totalEmployees'])),
      ],
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Settings & Team')),
      body: Column(
        children: [
          FilterChipsBar(
            options: _tabs,
            selected: _tab,
            onSelected: (v) => setState(() => _tab = v),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      companyName.isEmpty
                          ? 'Manage workspace and permissions'
                          : '$companyName · Manage workspace and permissions',
                      style: const TextStyle(color: AppColors.inkMuted),
                    ),
                  ),
                  if (workspaceAsync.hasError && !workspaceAsync.hasValue) ...[
                    InfoBanner(
                      tone: Tone.warning,
                      message: 'Showing saved company details — could not load the latest workspace. '
                          '${errorMessage(workspaceAsync.error)}',
                    ),
                    const SizedBox(height: 12),
                  ],
                  ...sections,
                  const SizedBox(height: 24),
                  MenuSection(
                    children: [
                      MenuTile(
                        icon: Icons.logout,
                        title: 'Sign out',
                        destructive: true,
                        onTap: _signOut,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Center(
                    child: Text(
                      'PagerLook Employer v2.4.0',
                      style: TextStyle(fontSize: 12, color: AppColors.inkFaint),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WorkspaceCard extends StatelessWidget {
  const _WorkspaceCard({required this.company});

  final Map<String, dynamic> company;

  @override
  Widget build(BuildContext context) {
    String v(String key) => str(company[key], '—');
    return AppCard(
      title: 'Workspace',
      child: Column(
        children: [
          InfoRow(label: 'Company Name', value: str(company['name'])),
          InfoRow(label: 'Industry', value: v('industry')),
          InfoRow(label: 'Company Size', value: v('companySize')),
          InfoRow(label: 'Work Email', value: str(company['workEmail'])),
          InfoRow(label: 'City', value: v('city')),
          InfoRow(label: 'Country', value: v('country')),
          InfoRow(label: 'Contact Person', value: v('contactName')),
        ],
      ),
    );
  }
}

class _TeamMembersCard extends StatelessWidget {
  const _TeamMembersCard({required this.admin, required this.companyName});

  final Map<String, dynamic>? admin;
  final String companyName;

  @override
  Widget build(BuildContext context) {
    final a = admin;
    if (a == null) {
      return const AppCard(
        title: 'Team Members',
        child: Text('No admin account linked.', style: TextStyle(color: AppColors.inkMuted)),
      );
    }
    final name = str(a['name']);
    return AppCard(
      title: 'Team Members',
      subtitle: 'Portal admins for ${companyName.isEmpty ? 'your workspace' : companyName}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              AppAvatar(name: name, size: 44),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.inkStrong)),
                    Text(str(a['email']), style: const TextStyle(fontSize: 12.5, color: AppColors.inkMuted)),
                  ],
                ),
              ),
              const StatusBadge('admin', label: 'ADMIN', tone: Tone.brand),
            ],
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => context.push('/enterprise/users'),
              icon: const Icon(Icons.admin_panel_settings_outlined, size: 18),
              label: const Text('Manage company users'),
            ),
          ),
        ],
      ),
    );
  }
}

/// The functional row of the web's "Security & API" list.
class _SecurityLinks extends StatelessWidget {
  const _SecurityLinks();

  @override
  Widget build(BuildContext context) {
    return MenuSection(
      title: 'Security & API',
      children: [
        MenuTile(
          icon: Icons.history,
          title: 'Audit Logs',
          subtitle: 'View all administrative actions',
          onTap: () => context.push('/company/audit-logs'),
        ),
      ],
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({required this.totalEmployees});

  final int totalEmployees;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.hairline),
        borderRadius: BorderRadius.circular(AppRadii.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Enterprise Plan',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.inkStrong),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: AppColors.successBg, borderRadius: BorderRadius.circular(999)),
                child: const Text(
                  'ACTIVE',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.success),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Workforce linked to your company',
            style: TextStyle(fontSize: 13, color: AppColors.inkMuted),
          ),
          const Divider(height: 28),
          Text(
            '$totalEmployees',
            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: AppColors.inkStrong),
          ),
          const Text(
            'Linked Employees',
            style: TextStyle(fontSize: 13, color: AppColors.inkMuted),
          ),
        ],
      ),
    );
  }
}
