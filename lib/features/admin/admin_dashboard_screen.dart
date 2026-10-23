import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/json.dart';
import '../../core/widgets/widgets.dart';

/// `GET /admin/dashboard` — the stats map (web reads `data.stats || data`).
final adminDashboardProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final data = asMap(await ref.watch(adminApiProvider).fetchDashboard());
  return data['stats'] is Map ? asMap(data['stats']) : data;
});

/// Port of `pages/admin/AdminDashboard.jsx`.
class AdminDashboardScreen extends ConsumerWidget {
  const AdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(adminDashboardProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Admin Console')),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(adminDashboardProvider.future),
        child: AsyncValueView<Map<String, dynamic>>(
          value: value,
          loadingLabel: 'Loading admin dashboard...',
          onRetry: () => ref.invalidate(adminDashboardProvider),
          data: (stats) => _DashboardBody(stats: stats),
        ),
      ),
    );
  }
}

class _DashboardBody extends StatelessWidget {
  const _DashboardBody({required this.stats});

  final Map<String, dynamic> stats;

  String _n(Object? value) => formatNumber(asNum(value) ?? 0);

  @override
  Widget build(BuildContext context) {
    final totalEmployees = asInt(stats['totalEmployees']);
    final profileComplete = asInt(stats['employeesProfileComplete']);
    final incomplete = (totalEmployees - profileComplete) < 0 ? 0 : totalEmployees - profileComplete;

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        const PageIntro(
          title: 'Platform Overview',
          subtitle: 'Enterprise approvals, employee registrations, and platform health',
        ),
        const _GroupLabel('Employees'),
        StatGrid(
          children: [
            StatCard(
              label: 'Total Employees',
              value: _n(stats['totalEmployees']),
              icon: Icons.groups_outlined,
              tone: Tone.brand,
              onTap: () => context.go('/admin/employees'),
            ),
            StatCard(
              label: 'Profile Complete',
              value: _n(stats['employeesProfileComplete']),
              icon: Icons.assignment_turned_in_outlined,
              tone: Tone.info,
              onTap: () => context.go('/admin/employees?status=complete'),
            ),
            StatCard(
              label: 'Fully Verified',
              value: _n(stats['employeesVerified']),
              icon: Icons.verified_outlined,
              tone: Tone.success,
              onTap: () => context.go('/admin/employees?status=verified'),
            ),
            StatCard(
              label: 'Incomplete Profiles',
              value: formatNumber(incomplete),
              icon: Icons.pending_outlined,
              tone: Tone.warning,
              onTap: () => context.go('/admin/employees?status=incomplete'),
            ),
          ],
        ),
        const _GroupLabel('Companies'),
        StatGrid(
          children: [
            StatCard(
              label: 'Pending Review',
              value: _n(stats['pending'] ?? stats['pendingApprovals']),
              icon: Icons.hourglass_top_outlined,
              tone: Tone.warning,
              onTap: () => context.go('/admin/companies'),
            ),
            StatCard(
              label: 'Approved Companies',
              value: _n(stats['approved'] ?? stats['approvedCompanies']),
              icon: Icons.check_circle_outline,
              tone: Tone.success,
              onTap: () => context.go('/admin/companies?status=approved'),
            ),
            StatCard(
              label: 'Rejected',
              value: _n(stats['rejected'] ?? stats['rejectedCompanies']),
              icon: Icons.block_outlined,
              tone: Tone.neutral,
              onTap: () => context.go('/admin/companies?status=rejected'),
            ),
            StatCard(
              label: 'Total Enterprises',
              value: _n(stats['total'] ?? stats['totalEnterprises']),
              icon: Icons.business_outlined,
              tone: Tone.info,
              onTap: () => context.go('/admin/companies?status=all'),
            ),
          ],
        ),
        const _GroupLabel('Leads & KYC'),
        StatGrid(
          children: [
            StatCard(
              label: 'New Demo Requests',
              value: _n(stats['demoRequestsNew']),
              icon: Icons.campaign_outlined,
              tone: Tone.warning,
              onTap: () => context.push('/admin/demo-requests'),
            ),
            if (stats['aadhaarPending'] != null)
              StatCard(
                label: 'Aadhaar Pending',
                value: _n(stats['aadhaarPending']),
                icon: Icons.fingerprint,
                tone: Tone.warning,
                onTap: () => context.go('/admin/aadhaar-requests'),
              ),
          ],
        ),
        const SizedBox(height: 20),
        AppCard(
          title: 'Employee Management',
          subtitle: 'View all registered employees, their verification status, scores, and full profile details.',
          child: AppButton(
            label: 'View All Employees',
            onPressed: () => context.go('/admin/employees'),
          ),
        ),
        const SizedBox(height: 12),
        AppCard(
          title: 'Company Approvals',
          subtitle:
              'New enterprise registrations appear here after onboarding. Approve them to unlock their employer dashboard.',
          child: AppButton(
            label: 'Review Pending Companies',
            onPressed: () => context.go('/admin/companies'),
          ),
        ),
      ],
    );
  }
}

class _GroupLabel extends StatelessWidget {
  const _GroupLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 10, left: 2),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.8, color: AppColors.inkMuted),
      ),
    );
  }
}
