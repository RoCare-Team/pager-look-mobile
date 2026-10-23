import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/company_permissions.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/widgets/widgets.dart';
import 'widgets_a/portal_providers.dart';
import 'widgets_a/team_sheets.dart';
import 'widgets_a/team_utils.dart';
import 'widgets_a/team_widgets.dart';

/// Port of `pages/enterprise/DepartmentDetails.jsx`.
class DepartmentDetailsScreen extends ConsumerWidget {
  const DepartmentDetailsScreen({super.key, required this.department});

  /// Raw path segment; decoded here like the web's `decodeURIComponent`.
  final String department;

  String get _name {
    try {
      return Uri.decodeComponent(department);
    } catch (_) {
      return department;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final name = _name;
    final deptAsync = ref.watch(teamDepartmentProvider(name));
    final perms = ref.watch(companyPermissionsProvider).valueOrNull ?? const CompanyPermissions();
    final canAccess = perms.can('access_requests', 'manage');

    // If the department endpoint isn't routed on this backend (404), fall
    // back to the team overview filtered to this department — same records.
    final deptError = deptAsync.error;
    final useTeamFallback = deptError is ApiException && deptError.isNotFound;
    final AsyncValue<dynamic> source = useTeamFallback ? ref.watch(companyTeamProvider) : deptAsync;

    void refreshAll() => invalidateTeamData(ref, department: name);

    Future<void> requestAccess(Map<String, dynamic> emp) async {
      final ok = await showSendAccessRequestSheet(
        context,
        employeeId: resolveEmployeeId(emp),
        employeeName: employeeName(emp),
        defaultRequestType: 'full_profile_access',
      );
      if (ok) refreshAll();
    }

    Future<void> removeAccess(Map<String, dynamic> emp) async {
      final ok =
          await showRemoveAccessSheet(context, employeeId: resolveEmployeeId(emp), employeeName: employeeName(emp));
      if (ok) refreshAll();
    }

    return Scaffold(
      appBar: AppBar(title: Text(name, overflow: TextOverflow.ellipsis)),
      body: RefreshIndicator(
        onRefresh: () async {
          refreshAll();
          try {
            await (useTeamFallback ? ref.read(companyTeamProvider.future) : ref.read(teamDepartmentProvider(name).future));
          } catch (_) {
            // Shown by the error view.
          }
        },
        child: AsyncValueView<dynamic>(
          value: source,
          loadingLabel: 'Loading department...',
          onRetry: refreshAll,
          data: (data) {
            final employees = useTeamFallback
                ? extractTeamEmployees(data).where((e) => (e['department'] ?? 'Unassigned') == name).toList()
                : extractDepartmentEmployees(data);
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: [
                PageIntro(
                  title: name,
                  subtitle: '${employees.length} linked employee${employees.length != 1 ? 's' : ''}',
                ),
                if (employees.isEmpty)
                  const AppCard(
                    child: EmptyState(
                      icon: Icons.groups_outlined,
                      title: 'No employees linked yet. Invite your first employee.',
                    ),
                  )
                else
                  ...employees.map(
                    (emp) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: TeamEmployeeCard(
                        employee: emp,
                        department: name,
                        onRequestAccess: canAccess ? requestAccess : null,
                        onRemoveAccess: canAccess ? removeAccess : null,
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}
