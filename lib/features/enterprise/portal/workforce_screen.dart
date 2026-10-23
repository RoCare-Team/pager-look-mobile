import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/json.dart';
import '../../../core/widgets/widgets.dart';
import 'widgets_b/score_and_pagination.dart';

/// The web Workforce page reads `GET /company/team`.
final _workforceTeamProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final data = await ref.watch(enterpriseApiProvider).fetchTeam();
  return data is List ? {'departments': data} : asMap(data);
});

/// Web `extractTeamEmployees`: top-level `employees`, else flattened from departments.
List<Map<String, dynamic>> _extractTeamEmployees(Map<String, dynamic> data) {
  final employees = asMapList(data['employees']);
  if (employees.isNotEmpty) return employees;
  return asMapList(data['departments']).expand((dept) {
    return asMapList(dept['employees']).map((emp) => {
          ...emp,
          'department': strOrNull(emp['department']) ?? str(dept['name']),
        });
  }).toList();
}

/// Web `resolveEmployeeId`.
String _employeeId(Map<String, dynamic> emp) =>
    str(emp['employeeId'] ?? emp['id'] ?? emp['userId'] ?? emp['employeeUserId'] ?? emp['_id']);

/// Web `getEmployeeProfilePath`.
String? _profilePath(Map<String, dynamic> emp) {
  final explicit = strOrNull(emp['profilePath']);
  if (explicit != null) return explicit;
  final id = _employeeId(emp);
  return id.isEmpty ? null : '/company/team/${Uri.encodeComponent(id)}';
}

const _stageFilters = {
  'all': 'All',
  'active': 'Active',
  'verified': 'Ready to assign',
  'pending_verification': 'Pending verification',
  'incoming': 'New',
};

/// Web `getOnboardingStageStyle` labels.
const _stageLabels = {
  'incoming': 'New',
  'pending_verification': 'Pending verification',
  'verified': 'Ready to assign',
  'active': 'Active',
};

/// Port of `pages/enterprise/Workforce.jsx`.
class WorkforceScreen extends ConsumerStatefulWidget {
  const WorkforceScreen({super.key});

  @override
  ConsumerState<WorkforceScreen> createState() => _WorkforceScreenState();
}

class _WorkforceScreenState extends ConsumerState<WorkforceScreen> {
  String _query = '';
  String _stage = 'all';

  Future<void> _refresh() async {
    try {
      final _ = await ref.refresh(_workforceTeamProvider.future);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(_workforceTeamProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Workforce')),
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          decoration: const BoxDecoration(
            color: AppColors.surface,
            border: Border(top: BorderSide(color: AppColors.hairline)),
          ),
          child: AppButton(
            label: '+ Generate Joining QR',
            onPressed: () => context.push('/enterprise/qr-onboarding'),
          ),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: AsyncValueView<Map<String, dynamic>>(
          value: async,
          loadingLabel: 'Loading workforce...',
          onRetry: () => ref.invalidate(_workforceTeamProvider),
          data: (data) => _buildList(data),
        ),
      ),
    );
  }

  Widget _buildList(Map<String, dynamic> data) {
    final employees = _extractTeamEmployees(data);
    final queues = asMap(data['workforceQueues']);
    final incomingQ = asList(queues['incoming']).length;
    final verifiedQ = asList(queues['verified']).length;
    final activeQ = asList(queues['active']).length;

    final counts = <String, int>{'all': employees.length, 'active': 0, 'verified': 0, 'pending_verification': 0, 'incoming': 0};
    for (final emp in employees) {
      final stage = str(emp['onboardingStage'], 'incoming');
      if (counts.containsKey(stage)) counts[stage] = counts[stage]! + 1;
    }

    final q = _query.trim().toLowerCase();
    final filtered = employees.where((emp) {
      final stage = str(emp['onboardingStage'], 'incoming');
      if (_stage != 'all' && stage != _stage) return false;
      if (q.isEmpty) return true;
      final name = str(emp['employeeName'] ?? emp['name']).toLowerCase();
      final role = str(emp['role'] ?? emp['designation']).toLowerCase();
      final dept = str(emp['department']).toLowerCase();
      return name.contains(q) || role.contains(q) || dept.contains(q);
    }).toList();

    final n = employees.length;

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        Text(
          n > 0
              ? '$n linked employee${n != 1 ? 's' : ''} in your organization'
              : 'Employees appear here after they accept your invite and join',
          style: const TextStyle(color: AppColors.inkMuted),
        ),
        if (incomingQ > 0 || verifiedQ > 0) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              if (incomingQ > 0) StatusBadge('onboarding', label: '$incomingQ onboarding', tone: Tone.neutral),
              if (verifiedQ > 0) StatusBadge('ready', label: '$verifiedQ ready to assign', tone: Tone.brand),
              if (activeQ > 0) StatusBadge('active', label: '$activeQ active', tone: Tone.success),
            ],
          ),
        ],
        const SizedBox(height: 12),
        SearchField(
          hint: 'Search name, role, or department...',
          initialValue: _query,
          onChanged: (v) => setState(() => _query = v),
        ),
        FilterChipsBar(
          padding: const EdgeInsets.symmetric(vertical: 10),
          options: {
            for (final e in _stageFilters.entries)
              e.key: (counts[e.key] ?? 0) > 0 ? '${e.value} (${counts[e.key]})' : e.value,
          },
          selected: _stage,
          onSelected: (v) => setState(() => _stage = v),
        ),
        if (filtered.isEmpty)
          EmptyState(
            icon: Icons.groups_outlined,
            title: n > 0 ? 'No employees match your filters' : 'No workforce data yet',
            message: n > 0
                ? 'Try a different search or stage filter.'
                : 'Invite employees from Team Management — they will appear here once they join.',
            action: n > 0
                ? null
                : AppButton(
                    label: 'Go to Team Management →',
                    variant: AppButtonVariant.ghost,
                    expand: false,
                    onPressed: () => context.go('/company/team'),
                  ),
          )
        else
          for (final emp in filtered)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _EmployeeCard(
                employee: emp,
                onViewProfile: () {
                  final path = _profilePath(emp);
                  if (path != null) context.push(path);
                },
              ),
            ),
      ],
    );
  }
}

/// Web `components/enterprise/EmployeeCard.jsx`.
class _EmployeeCard extends StatelessWidget {
  const _EmployeeCard({required this.employee, required this.onViewProfile});

  final Map<String, dynamic> employee;
  final VoidCallback onViewProfile;

  @override
  Widget build(BuildContext context) {
    final emp = employee;
    final name = str(emp['employeeName'] ?? emp['name'], 'Employee');
    final role = str(emp['role'] ?? emp['designation'], '—');
    final department = str(emp['department'], 'Unassigned');
    final stage = str(emp['onboardingStage'], 'incoming');
    final stageLabel = _stageLabels[stage] ?? 'New';
    final score = asNum(emp['trustScore']) ?? 0;
    final rating = scoreRating(score);
    final verified = stage == 'active' || asBool(emp['isVerified']);

    return AppCard(
      onTap: onViewProfile,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppAvatar(name: name, imageUrl: strOrNull(emp['photoUrl']), size: 48),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700, color: AppColors.inkStrong),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$role · $department',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13, color: AppColors.inkMuted),
                    ),
                    const SizedBox(height: 6),
                    StatusBadge(stage, label: stageLabel, tone: Tone.neutral),
                  ],
                ),
              ),
            ],
          ),
          const Divider(height: 24),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'PAGERLOOK SCORE',
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.inkFaint),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text(
                          '${score.round()}',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: rating.tone.fg),
                        ),
                        const SizedBox(width: 6),
                        Flexible(child: StatusBadge(rating.label, label: rating.label, tone: rating.tone)),
                      ],
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'VERIFICATION',
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.inkFaint),
                    ),
                    const SizedBox(height: 6),
                    verified
                        ? const StatusBadge('verified', label: '✓ Verified', tone: Tone.brand)
                        : const StatusBadge('pending', label: 'Pending', tone: Tone.warning),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          AppButton(
            label: 'View Profile',
            variant: AppButtonVariant.outline,
            compact: true,
            onPressed: onViewProfile,
          ),
        ],
      ),
    );
  }
}

