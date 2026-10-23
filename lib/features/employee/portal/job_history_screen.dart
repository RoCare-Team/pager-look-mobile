import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/json.dart';
import '../../../core/widgets/widgets.dart';
import 'employee_portal_utils.dart';

/// `GET /employee/jobs` — raw response (`{ jobs, summary }` or a bare list).
final employeeJobsProvider = FutureProvider.autoDispose<dynamic>((ref) async {
  return ref.watch(employeeApiProvider).fetchJobs();
});

/// Jobs tab — port of `JobHistory.jsx` + `JobHistoryCard.jsx`.
class JobHistoryScreen extends ConsumerWidget {
  const JobHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final jobsAsync = ref.watch(employeeJobsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Job History'),
        actions: [
          IconButton(
            tooltip: 'Add experience',
            icon: const Icon(Icons.add),
            onPressed: () => context.push('/employee/job-history/add'),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(employeeJobsProvider.future),
        child: AsyncValueView<dynamic>(
          value: jobsAsync,
          loadingLabel: 'Loading job history...',
          onRetry: () => ref.invalidate(employeeJobsProvider),
          data: (data) => _JobsBody(data: data),
        ),
      ),
    );
  }
}

class _JobsBody extends StatelessWidget {
  const _JobsBody({required this.data});

  final dynamic data;

  @override
  Widget build(BuildContext context) {
    final jobs = listFrom(data, const ['jobs']);
    final totalRoles = asInt(pick(data, 'summary.totalRoles'), jobs.length);
    final verifiedCount = jobs.where(isJobVerified).length;
    final inProgressCount = jobs.where((j) => str(j['status']) == 'in_process').length;
    final pendingRaw = totalRoles - verifiedCount - inProgressCount;
    final pendingCount = pendingRaw < 0 ? 0 : pendingRaw;
    final progress = totalRoles > 0 ? ((verifiedCount / totalRoles) * 100).round() : 0;

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        if (jobs.isNotEmpty) ...[
          ProgressSummaryCard(
            progress: progress / 100,
            centerLabel: '$verifiedCount/$totalRoles',
            title: '$verifiedCount of $totalRoles roles verified',
            caption: pendingCount + inProgressCount == 0
                ? 'All roles verified'
                : '${pendingCount + inProgressCount} pending${inProgressCount > 0 ? ' · $inProgressCount in progress' : ''}',
          ),
          const SizedBox(height: 16),
        ],
        if (jobs.isEmpty)
          AppCard(
            child: EmptyState(
              icon: Icons.work_outline,
              title: 'No job history yet',
              message: 'Add your work experience to start building a verified career record.',
              action: AppButton(
                label: 'Add your first role',
                icon: Icons.add,
                expand: false,
                onPressed: () => context.push('/employee/job-history/add'),
              ),
            ),
          )
        else ...[
          for (final job in jobs) Padding(padding: const EdgeInsets.only(bottom: 12), child: _JobCard(job: job)),
          const SizedBox(height: 8),
          AppButton(
            label: 'Add another role',
            icon: Icons.add,
            variant: AppButtonVariant.outline,
            onPressed: () => context.push('/employee/job-history/add'),
          ),
        ],
      ],
    );
  }
}

class _JobCard extends StatelessWidget {
  const _JobCard({required this.job});

  final Map<String, dynamic> job;

  @override
  Widget build(BuildContext context) {
    final id = idOf(job);
    final company = str(job['company']);
    final verified = isJobVerified(job);
    final inProcess = str(job['status']) == 'in_process';
    final badge = jobVerificationBadge(job);
    final type = strOrNull(job['employmentType']) ?? strOrNull(job['type']) ?? 'Full-time';
    final salaryBand = strOrNull(job['salaryBand']);
    final path = '/employee/jobs/$id/verify';

    final String actionLabel;
    if (verified) {
      actionLabel = 'View details';
    } else if (inProcess) {
      actionLabel = 'View status';
    } else {
      actionLabel = 'Verify employment';
    }

    return AppCard(
      padding: EdgeInsets.zero,
      borderColor: verified ? AppColors.success.withValues(alpha: 0.25) : null,
      onTap: id.isEmpty ? null : () => context.push(path),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(height: 3, color: verified ? AppColors.success : AppColors.line),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        color: AppColors.brand50,
                      ),
                      child: Text(
                        companyInitials(company),
                        style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.brand600),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            str(job['title'], '—'),
                            style: const TextStyle(
                                fontSize: 15.5, fontWeight: FontWeight.w700, color: AppColors.inkStrong),
                          ),
                          const SizedBox(height: 2),
                          Text(company,
                              style: const TextStyle(
                                  fontSize: 13.5, fontWeight: FontWeight.w500, color: AppColors.inkMuted)),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              const Icon(Icons.calendar_today_outlined, size: 13, color: AppColors.inkFaint),
                              const SizedBox(width: 5),
                              Expanded(
                                child: Text(
                                  formatJobPeriod(job),
                                  style: const TextStyle(fontSize: 12, color: AppColors.inkMuted),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    TagChip(type),
                    if (asBool(job['isPresent'])) const TagChip('Current role', tone: Tone.success),
                    if (salaryBand != null) TagChip(salaryBand),
                  ],
                ),
                const Divider(height: 24),
                Row(
                  children: [
                    Flexible(child: StatusBadge(null, label: badge.label, tone: badge.tone)),
                    const Spacer(),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        if (verified && job['verifiedAt'] != null)
                          Text(
                            'Verified ${formatDate(job['verifiedAt'])}',
                            style: const TextStyle(fontSize: 10.5, color: AppColors.inkFaint),
                          ),
                        if (id.isNotEmpty)
                          verified || inProcess
                              ? Text(
                                  '$actionLabel →',
                                  style: const TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.brand600,
                                  ),
                                )
                              : AppButton(
                                  label: actionLabel,
                                  compact: true,
                                  expand: false,
                                  onPressed: () => context.push(path),
                                ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
