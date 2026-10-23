import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/widgets.dart';
import 'admin_utils.dart';
import 'widgets/delete_employee_dialog.dart';

/// Web: `fetchAdminEmployees` → `normalizeAdminEmployeeList`.
final adminEmployeesProvider =
    FutureProvider.autoDispose.family<List<AdminEmployee>, AdminListQuery>((ref, query) async {
  final data = await ref.watch(adminApiProvider).fetchEmployees(status: query.status, q: query.q);
  return normalizeAdminEmployeeList(data);
});

const _statusTabs = {
  'all': 'All',
  'complete': 'Profile Complete',
  'incomplete': 'Incomplete',
  'verified': 'Verified',
};

/// Badge shared with the detail screen: a deactivated account outranks every
/// other state — "Verified" on a login that no longer works would mislead.
class AdminEmployeeStatusBadge extends StatelessWidget {
  const AdminEmployeeStatusBadge({super.key, required this.employee});

  final AdminEmployee employee;

  @override
  Widget build(BuildContext context) {
    if (!employee.isActive) return const StatusBadge('deactivated', tone: Tone.neutral, label: 'Deactivated');
    if (employee.isVerified) return const StatusBadge('verified', tone: Tone.success, label: 'Verified');
    if (employee.profileSetupComplete) {
      return const StatusBadge('complete', tone: Tone.info, label: 'Profile Complete');
    }
    return const StatusBadge('incomplete', tone: Tone.warning, label: 'Incomplete');
  }
}

/// Port of `pages/admin/AdminEmployees.jsx`.
class AdminEmployeesScreen extends ConsumerStatefulWidget {
  const AdminEmployeesScreen({super.key, this.initialStatus = 'all'});

  final String initialStatus;

  @override
  ConsumerState<AdminEmployeesScreen> createState() => _AdminEmployeesScreenState();
}

class _AdminEmployeesScreenState extends ConsumerState<AdminEmployeesScreen> {
  late String _status = widget.initialStatus;
  String _query = '';

  /// Only the card being acted on greys out.
  final Set<String> _busyIds = {};

  AdminListQuery get _key => (status: _status, q: _query);

  @override
  void didUpdateWidget(covariant AdminEmployeesScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Follows `?status=` like the web's useEffect on searchParams.
    if (oldWidget.initialStatus != widget.initialStatus) {
      setState(() => _status = widget.initialStatus);
    }
  }

  Future<void> _toggleActive(AdminEmployee employee) async {
    final next = !employee.isActive;
    setState(() => _busyIds.add(employee.id));
    try {
      await ref.read(adminApiProvider).setEmployeeStatus(employee.id, next);
      // Every employees view, not just this filter.
      ref.invalidate(adminEmployeesProvider);
      showToast(
        next ? 'Employee reactivated' : 'Employee deactivated — they can no longer log in',
        type: next ? ToastType.success : ToastType.info,
      );
    } catch (e) {
      showErrorToast(e, 'Could not update the employee');
    } finally {
      if (mounted) setState(() => _busyIds.remove(employee.id));
    }
  }

  Future<void> _delete(AdminEmployee employee) async {
    await showDeleteEmployeeDialog(
      context,
      name: employee.name,
      veriworkId: employee.veriworkId,
      onConfirm: (confirm) async {
        if (mounted) setState(() => _busyIds.add(employee.id));
        try {
          await ref.read(adminApiProvider).deleteEmployee(employee.id, confirm);
          ref.invalidate(adminEmployeesProvider);
          showToast('${employee.name} was permanently deleted', type: ToastType.success);
          return true;
        } catch (e) {
          showErrorToast(e, 'Could not delete the employee');
          return false;
        } finally {
          if (mounted) setState(() => _busyIds.remove(employee.id));
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final value = ref.watch(adminEmployeesProvider(_key));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Employees'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: value.isLoading
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.refresh),
            onPressed: value.isLoading ? null : () => ref.invalidate(adminEmployeesProvider(_key)),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: SearchField(
              hint: 'Search name, email, phone, ID...',
              onChanged: (q) => setState(() => _query = q.trim()),
            ),
          ),
          FilterChipsBar(
            options: _statusTabs,
            selected: _status,
            onSelected: (key) => setState(() => _status = key),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => ref.refresh(adminEmployeesProvider(_key).future),
              child: value.when(
                skipLoadingOnRefresh: true,
                skipLoadingOnReload: true,
                loading: () => const LoadingView(label: 'Loading employees...'),
                error: (e, _) => ErrorView(
                  error: e,
                  title: 'Could not load employees',
                  onRetry: () => ref.invalidate(adminEmployeesProvider(_key)),
                ),
                data: (list) => _buildList(list),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildList(List<AdminEmployee> list) {
    final complete = list.where((e) => e.profileSetupComplete).length;
    final verified = list.where((e) => e.isVerified).length;

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
      children: [
        StatGrid(
          columns: 3,
          children: [
            StatCard(label: 'Showing in current view', value: '${list.length}', tone: Tone.neutral),
            StatCard(label: 'Profile complete', value: '$complete', tone: Tone.info),
            StatCard(label: 'Fully verified', value: '$verified', tone: Tone.success),
          ],
        ),
        const SizedBox(height: 14),
        if (list.isEmpty)
          const EmptyState(title: 'No employees found for this filter.', icon: Icons.person_search_outlined)
        else
          for (final employee in list) ...[
            _EmployeeCard(
              employee: employee,
              busy: _busyIds.contains(employee.id),
              onToggleActive: () => _toggleActive(employee),
              onDelete: () => _delete(employee),
            ),
            const SizedBox(height: 12),
          ],
      ],
    );
  }
}

class _EmployeeCard extends StatelessWidget {
  const _EmployeeCard({
    required this.employee,
    required this.busy,
    required this.onToggleActive,
    required this.onDelete,
  });

  final AdminEmployee employee;
  final bool busy;
  final VoidCallback onToggleActive;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    void open() => context.push('/admin/employees/${employee.id}');

    return AppCard(
      onTap: open,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppAvatar(name: employee.name, imageUrl: employee.photoUrl, size: 44),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      employee.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.inkStrong),
                    ),
                    Text(employee.currentCity, style: const TextStyle(fontSize: 12.5, color: AppColors.inkMuted)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              AdminEmployeeStatusBadge(employee: employee),
            ],
          ),
          const SizedBox(height: 8),
          InfoRow(label: 'Email', value: employee.email),
          InfoRow(label: 'Phone', value: employee.phone),
          InfoRow(label: 'Role', value: employee.role),
          InfoRow(label: 'Companies', value: employee.linkedCompanyLabel),
          InfoRow(
            label: 'PagerLook ID',
            valueWidget: Text(
              employee.veriworkId,
              textAlign: TextAlign.right,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12.5, color: AppColors.inkStrong),
            ),
          ),
          InfoRow(
            label: 'Score',
            valueWidget: Text(
              '${employee.employeeScore}',
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: AppColors.brand600),
            ),
          ),
          InfoRow(label: 'Joined', value: formatDate(employee.createdAt)),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: AppButton(
                  label: 'View',
                  compact: true,
                  variant: AppButtonVariant.secondary,
                  onPressed: open,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: AppButton(
                  label: employee.isActive ? 'Deactivate' : 'Restore',
                  compact: true,
                  variant: AppButtonVariant.outline,
                  loading: busy,
                  onPressed: busy ? null : onToggleActive,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: AppButton(
                  label: 'Delete',
                  compact: true,
                  variant: AppButtonVariant.danger,
                  onPressed: busy ? null : onDelete,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
