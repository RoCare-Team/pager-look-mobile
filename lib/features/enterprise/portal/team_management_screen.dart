import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/company_permissions.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/json.dart';
import '../../../core/widgets/widgets.dart';
import 'widgets_a/portal_providers.dart';
import 'widgets_a/team_sheets.dart';
import 'widgets_a/team_utils.dart';
import 'widgets_a/team_widgets.dart';

/// Port of `pages/enterprise/TeamManagement.jsx` — employees, departments,
/// pending invitations and the invite flow.
class TeamManagementScreen extends ConsumerStatefulWidget {
  const TeamManagementScreen({super.key});

  @override
  ConsumerState<TeamManagementScreen> createState() => _TeamManagementScreenState();
}

class _TeamManagementScreenState extends ConsumerState<TeamManagementScreen> {
  String _query = '';

  Future<void> _refresh() async {
    ref.invalidate(companyPendingInvitationsProvider);
    try {
      final _ = await ref.refresh(companyTeamProvider.future);
    } catch (_) {
      // Rendered by the error view.
    }
  }

  void _refreshTeam() => invalidateTeamData(ref);

  Future<void> _invite() async {
    final ok = await showInviteEmployeeSheet(context);
    if (ok) {
      ref.invalidate(companyTeamProvider);
      ref.invalidate(companyPendingInvitationsProvider);
    }
  }

  Future<void> _requestAccess(Map<String, dynamic> emp) async {
    final ok = await showSendAccessRequestSheet(
      context,
      employeeId: resolveEmployeeId(emp),
      employeeName: employeeName(emp),
      defaultRequestType: 'full_profile_access',
    );
    if (ok) _refreshTeam();
  }

  Future<void> _removeAccess(Map<String, dynamic> emp) async {
    final ok =
        await showRemoveAccessSheet(context, employeeId: resolveEmployeeId(emp), employeeName: employeeName(emp));
    if (ok) _refreshTeam();
  }

  Future<void> _assign(Map<String, dynamic> emp) async {
    final ok = await showAssignEmployeeSheet(
      context,
      employeeId: resolveEmployeeId(emp),
      employeeName: strOrNull(emp['employeeName']) ?? 'Employee',
      department: strOrNull(emp['department']),
      designation: strOrNull(emp['designation']),
    );
    if (ok) _refreshTeam();
  }

  bool _matches(Map<String, dynamic> emp) {
    if (_query.isEmpty) return true;
    final q = _query.toLowerCase();
    return [
      employeeName(emp),
      employeeRole(emp),
      str(emp['department']),
      str(emp['veriworkId']),
    ].any((s) => s.toLowerCase().contains(q));
  }

  @override
  Widget build(BuildContext context) {
    final teamAsync = ref.watch(companyTeamProvider);
    final perms = ref.watch(companyPermissionsProvider).valueOrNull ?? const CompanyPermissions();
    final canInvite = perms.can('team', 'manage');
    final canAccess = perms.can('access_requests', 'manage');
    final canAssign = perms.can('workforce', 'manage');

    return Scaffold(
      appBar: AppBar(title: const Text('Team')),
      floatingActionButton: canInvite
          ? FloatingActionButton.extended(
              onPressed: _invite,
              backgroundColor: AppColors.brand600,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.person_add_alt_1_rounded),
              label: const Text('Invite', style: TextStyle(fontWeight: FontWeight.w700)),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: AsyncValueView<dynamic>(
          value: teamAsync,
          loadingLabel: 'Loading team...',
          onRetry: () => ref.invalidate(companyTeamProvider),
          data: (data) {
            final employees = extractTeamEmployees(data);
            final visible = employees.where(_matches).toList();
            final departments = extractTeamDepartments(data)
                .where((d) => asInt(d['employeeCount']) > 0 || asList(d['employees']).isNotEmpty)
                .toList();

            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              children: [
                // ── Employees ──
                if (employees.isNotEmpty) ...[
                  SearchField(hint: 'Search your team', onChanged: (v) => setState(() => _query = v)),
                  SectionHeader('Employees · ${employees.length}', padding: const EdgeInsets.only(top: 18, bottom: 10)),
                ],
                if (employees.isEmpty)
                  AppCard(
                    child: EmptyState(
                      icon: Icons.group_add_outlined,
                      title: 'No employees yet',
                      message: 'Once someone accepts your invite and creates their profile, they will show up here.',
                      action: canInvite ? AppButton(label: 'Invite Employee', expand: false, onPressed: _invite) : null,
                    ),
                  )
                else if (visible.isEmpty)
                  const EmptyState(
                      icon: Icons.search_off, title: 'No matches', message: 'Try a different name or role.')
                else
                  ...visible.map(
                    (emp) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: TeamEmployeeCard(
                        employee: emp,
                        onRequestAccess: canAccess ? _requestAccess : null,
                        onRemoveAccess: canAccess ? _removeAccess : null,
                        onAssign: canAssign ? _assign : null,
                      ),
                    ),
                  ),

                // ── Departments ──
                if (departments.isNotEmpty) ...[
                  const SectionHeader('Departments'),
                  AppCard(
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: [
                        for (var i = 0; i < departments.length; i++) ...[
                          if (i > 0) const Divider(height: 1),
                          _DepartmentTile(department: departments[i]),
                        ],
                      ],
                    ),
                  ),
                ],

                // ── Pending invitations ──
                const SectionHeader('Pending invitations'),
                const _PendingInvitationsSection(),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _DepartmentTile extends StatelessWidget {
  const _DepartmentTile({required this.department});

  final Map<String, dynamic> department;

  @override
  Widget build(BuildContext context) {
    final name = str(department['name'], 'Unassigned');
    final count = department['employeeCount'] != null
        ? asInt(department['employeeCount'])
        : asList(department['employees']).length;
    final avg = asNum(department['averageTrustScore']);
    return ListTile(
      onTap: () => context.push('/company/team/department/${Uri.encodeComponent(name)}'),
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: AppColors.brand50, borderRadius: BorderRadius.circular(8)),
        child: const Icon(Icons.apartment_outlined, size: 20, color: AppColors.brand600),
      ),
      title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.inkStrong)),
      subtitle: Text(
        '$count employee${count != 1 ? 's' : ''}${avg != null && avg > 0 ? ' · Avg trust ${avg.round()}' : ''}',
        style: const TextStyle(fontSize: 12.5),
      ),
      trailing: const Icon(Icons.chevron_right, color: AppColors.inkFaint),
    );
  }
}

/// Web `PendingInvitationsTab`.
class _PendingInvitationsSection extends ConsumerWidget {
  const _PendingInvitationsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(companyPendingInvitationsProvider);

    Widget empty({bool withHint = true}) => AppCard(
          child: EmptyState(
            icon: Icons.mail_outline,
            title: 'No pending invitations',
            message: withHint ? 'Invited employees will appear here until they accept.' : null,
          ),
        );

    return async.when(
      skipLoadingOnRefresh: true,
      skipLoadingOnReload: true,
      loading: () => const LoadingView(label: 'Loading invitations...'),
      error: (e, _) {
        final unavailable =
            e is ApiException && (e.isNotFound || RegExp('not found', caseSensitive: false).hasMatch(e.message));
        if (unavailable) return empty(withHint: false);
        return InfoBanner(tone: Tone.danger, message: errorMessage(e));
      },
      data: (data) {
        final invitations = normalizePendingInvitations(data);
        if (invitations.isEmpty) return empty();
        return AppCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (var i = 0; i < invitations.length; i++) ...[
                if (i > 0) const Divider(height: 1),
                PendingInvitationTile(invitation: invitations[i]),
              ],
            ],
          ),
        );
      },
    );
  }
}
