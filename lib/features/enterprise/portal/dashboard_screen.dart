import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/company_permissions.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/json.dart';
import '../../../core/widgets/widgets.dart';
import 'widgets_a/portal_providers.dart';
import 'widgets_a/team_utils.dart';
import 'widgets_a/team_widgets.dart';

/// Port of `pages/enterprise/Dashboard.jsx` — "Workforce Overview".
class EnterpriseDashboardScreen extends ConsumerStatefulWidget {
  const EnterpriseDashboardScreen({super.key, this.showVerifiedSuccess = false});

  final bool showVerifiedSuccess;

  @override
  ConsumerState<EnterpriseDashboardScreen> createState() => _EnterpriseDashboardScreenState();
}

class _EnterpriseDashboardScreenState extends ConsumerState<EnterpriseDashboardScreen> {
  late bool _showSuccess = widget.showVerifiedSuccess;
  Timer? _successTimer;
  bool _redirecting = false;

  @override
  void initState() {
    super.initState();
    if (_showSuccess) {
      _successTimer = Timer(const Duration(seconds: 6), () {
        if (mounted) setState(() => _showSuccess = false);
      });
    }
  }

  @override
  void didUpdateWidget(covariant EnterpriseDashboardScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.showVerifiedSuccess && !oldWidget.showVerifiedSuccess) {
      _successTimer?.cancel();
      _showSuccess = true;
      _successTimer = Timer(const Duration(seconds: 6), () {
        if (mounted) setState(() => _showSuccess = false);
      });
    }
  }

  @override
  void dispose() {
    _successTimer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    ref.invalidate(companyTeamProvider);
    ref.invalidate(dashboardJoinRequestsProvider);
    ref.invalidate(companyPendingInvitationsProvider);
    ref.invalidate(companyInsightsProvider);
    try {
      final _ = await ref.refresh(enterpriseDashboardProvider.future);
    } catch (_) {
      // The error is rendered by the banner.
    }
  }

  /// Web: a 403 from the dashboard means the company isn't approved (anymore).
  void _handleForbidden() {
    if (_redirecting) return;
    _redirecting = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await ref.read(authProvider).updateCompany({'approvalStatus': 'submitted'}, merge: true);
      if (mounted) context.go('/enterprise/pending-approval');
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<dynamic>>(enterpriseDashboardProvider, (_, next) {
      final e = next.error;
      if (e is ApiException && e.isForbidden) _handleForbidden();
    });

    final dashboardAsync = ref.watch(enterpriseDashboardProvider);
    final teamAsync = ref.watch(companyTeamProvider);
    final joinAsync = ref.watch(dashboardJoinRequestsProvider);
    final invitesAsync = ref.watch(companyPendingInvitationsProvider);
    final insightsAsync = ref.watch(companyInsightsProvider);
    final perms = ref.watch(companyPermissionsProvider).valueOrNull ?? const CompanyPermissions();

    if (dashboardAsync.isLoading && !dashboardAsync.hasValue && !dashboardAsync.hasError) {
      return Scaffold(
        appBar: AppBar(title: const Text('Dashboard')),
        body: const LoadingView(label: 'Loading dashboard...'),
      );
    }

    final dashboard = dashboardAsync.valueOrNull;
    final team = teamAsync.valueOrNull;
    final insights = insightsAsync.valueOrNull;
    final joinRequests = normalizeJoinRequests(joinAsync.valueOrNull);
    final invitations = normalizePendingInvitations(invitesAsync.valueOrNull);

    final stats = resolveDashboardStats(
      dashboard,
      teamData: team,
      joinRequests: joinRequests,
      pendingInvitations: invitations,
    );
    final trend = buildEmployeeOnboardingTrend(
      joinRequests: joinRequests,
      invitations: invitations,
      teamData: team,
      dashboard: dashboard,
      insights: insights,
    );

    final teamDepartments = buildDepartmentDistribution(team);
    final departmentData =
        teamDepartments.isNotEmpty ? teamDepartments : chartMapFrom(pick(insights, 'departmentDistribution'));

    final deptTrust = buildDepartmentTrustBars(team);
    Map<String, num> trustBars;
    if (deptTrust.isNotEmpty) {
      trustBars = deptTrust;
    } else {
      final dist = buildTrustScoreDistribution(team);
      trustBars = dist.values.any((v) => v > 0) ? dist : chartMapFrom(pick(insights, 'trustScoreDistribution'));
    }
    final trustTitle = deptTrust.isNotEmpty ? 'Avg Trust by Department' : 'Trust Score Distribution';

    final pendingItems = buildDashboardPendingItems(joinRequests, invitations, 4);
    final pendingLoading = (joinAsync.isLoading && !joinAsync.hasValue) || (invitesAsync.isLoading && !invitesAsync.hasValue);
    final showQr = perms.canSee('qr_onboarding');

    var pendingSubtitle = '${stats.pendingRequests} awaiting review';
    if (stats.pendingInvitations > 0 && stats.pendingJoinRequests > 0) {
      pendingSubtitle += ' · ${stats.pendingJoinRequests} join · ${stats.pendingInvitations} invite';
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard'),
        actions: [
          if (perms.canSee('dashboard'))
            IconButton(
              tooltip: 'Company insights',
              icon: const Icon(Icons.insights_outlined),
              onPressed: () => context.push('/company/insights'),
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            const PageIntro(title: 'Workforce Overview', subtitle: 'Monitor verification activity and team metrics'),
            if (dashboardAsync.hasError) ...[
              InfoBanner(tone: Tone.danger, message: errorMessage(dashboardAsync.error)),
              const SizedBox(height: 14),
            ],
            if (_showSuccess) ...[
              const InfoBanner(
                tone: Tone.success,
                title: 'Verification submitted successfully',
                message: 'Your company profile is under review. Welcome to your employer dashboard.',
              ),
              const SizedBox(height: 14),
            ],
            StatGrid(
              children: [
                StatCard(
                  icon: Icons.people_outline,
                  label: 'Total Candidates',
                  value: '${stats.totalCandidates}',
                  tone: Tone.brand,
                ),
                StatCard(
                  icon: Icons.check_circle_outline,
                  label: 'Approved',
                  value: '${stats.approvedEmployees}',
                  tone: Tone.success,
                ),
                StatCard(
                  icon: Icons.front_hand_outlined,
                  label: 'Join Requests',
                  value: '${stats.pendingRequests}',
                  tone: Tone.warning,
                  caption: stats.pendingRequests > 0 ? 'Pending' : null,
                ),
                StatCard(
                  icon: Icons.shield_outlined,
                  label: 'Avg PagerLook Score',
                  value: stats.avgVeriScore == 0 ? '—' : '${stats.avgVeriScore}',
                  tone: Tone.danger,
                ),
              ],
            ),
            const SizedBox(height: 16),
            AppCard(
              title: trend.title,
              subtitle: trend.subtitle,
              child: GroupedTrendChart(labels: trend.labels, series: trend.series),
            ),
            const SizedBox(height: 16),
            AppCard(
              title: 'Pending Join Requests',
              subtitle: pendingSubtitle,
              action: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (stats.pendingJoinRequests > 0)
                    _LinkText('Join requests', () => context.push('/enterprise/join-requests')),
                  if (stats.pendingInvitations > 0) _LinkText('Invitations', () => context.go('/company/team')),
                  if (stats.pendingRequests == 0)
                    _LinkText('View all', () => context.push('/enterprise/join-requests')),
                ],
              ),
              child: pendingLoading
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 20),
                      child: Center(child: CircularProgressIndicator(strokeWidth: 2.5)),
                    )
                  : pendingItems.isEmpty
                      ? EmptyState(
                          icon: Icons.inbox_outlined,
                          title: "You're all caught up",
                          message: 'New join requests and invitations will land here for review.',
                          action: TextButton(
                            onPressed: () => context.go('/company/team'),
                            child: const Text('Invite employees →'),
                          ),
                        )
                      : Column(
                          children: [
                            for (var i = 0; i < pendingItems.length; i++) ...[
                              if (i > 0) const Divider(height: 20),
                              _pendingItem(pendingItems[i]),
                            ],
                          ],
                        ),
            ),
            const SizedBox(height: 16),
            AppCard(
              title: 'Department Split',
              subtitle: 'Headcount across your teams',
              child: DepartmentSplit(data: departmentData),
            ),
            const SizedBox(height: 16),
            AppCard(
              title: trustTitle,
              subtitle: 'PagerLook Score breakdown for your workforce',
              child: LabeledBarChart(data: trustBars),
            ),
            if (showQr) ...[
              const SizedBox(height: 16),
              AppCard(
                color: AppColors.brand50,
                borderColor: AppColors.brand100,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(9),
                          decoration: BoxDecoration(
                            color: AppColors.brand600,
                            borderRadius: BorderRadius.circular(AppRadii.control),
                          ),
                          child: const Icon(Icons.qr_code_2, color: Colors.white, size: 20),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('QUICK ACTION',
                                  style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: 0.8,
                                      color: AppColors.brand500)),
                              SizedBox(height: 4),
                              Text('Generate a joining QR for new employees',
                                  style: TextStyle(
                                      fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.brand900)),
                              SizedBox(height: 4),
                              Text('Share a secure QR code so employees can join and verify instantly.',
                                  style: TextStyle(fontSize: 13, color: AppColors.inkBody)),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    AppButton(
                      label: 'Generate Joining QR',
                      icon: Icons.qr_code_2,
                      onPressed: () => context.push('/enterprise/qr-onboarding'),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _pendingItem(DashboardPendingItem item) {
    if (!item.isInvitation) return JoinRequestTile(name: item.name, role: item.role, score: item.score);
    final displayName = item.name != item.email ? item.name : item.email;
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: const BoxDecoration(color: AppColors.warningBg, shape: BoxShape.circle),
          child: Text(
            initialsFor(item),
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.warning),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.inkStrong)),
              Text(
                invitationSubtitle(item.invitedAt, item.department),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: AppColors.inkMuted),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        const StatusBadge('pending', label: 'PENDING', tone: Tone.warning),
      ],
    );
  }

  /// Web: initials of the name, or of the email's local part when there's no name.
  String initialsFor(DashboardPendingItem item) {
    final source = item.name != item.email ? item.name : item.email.split('@').first;
    final parts = source.split(' ').where((p) => p.isNotEmpty).map((p) => p[0]).join();
    if (parts.isEmpty) return '??';
    return (parts.length > 2 ? parts.substring(0, 2) : parts).toUpperCase();
  }
}

class _LinkText extends StatelessWidget {
  const _LinkText(this.label, this.onTap);

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
        child: Text(label,
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.brand600)),
      ),
    );
  }
}
