import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/json.dart';
import '../../../core/widgets/widgets.dart';
import 'widgets_a/portal_providers.dart';
import 'widgets_a/team_utils.dart';
import 'widgets_a/team_widgets.dart';

/// Port of `pages/enterprise/CompanyInsights.jsx`.
class CompanyInsightsScreen extends ConsumerWidget {
  const CompanyInsightsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(companyInsightsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Company Insights')),
      body: RefreshIndicator(
        onRefresh: () async {
          try {
            final _ = await ref.refresh(companyInsightsProvider.future);
          } catch (_) {
            // Rendered by the error view.
          }
        },
        child: AsyncValueView<dynamic>(
          value: async,
          loadingLabel: 'Loading insights...',
          onRetry: () => ref.invalidate(companyInsightsProvider),
          data: (raw) {
            final data = asMap(raw);
            final metrics = data['metrics'] is Map ? asMap(data['metrics']) : data;
            final verification = asMap(data['verificationAnalytics']);
            final verified = asInt(metrics['verifiedEmployees']);
            final total = asInt(metrics['totalEmployees']);
            final verifiedLabel = total > 0 ? '$verified of $total' : '$verified';

            final growth = asMapList(data['workforceGrowth'])
                .map((d) => ChartPoint(formatChartMonth(d['month']), asNum(d['count']) ?? 0))
                .toList();

            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: [
                const PageIntro(title: 'Company Insights', subtitle: 'Workforce analytics and verification trends'),
                StatGrid(
                  children: [
                    StatCard(
                      icon: Icons.people_outline,
                      label: 'Total Employees',
                      value: '$total',
                      tone: Tone.brand,
                    ),
                    StatCard(
                      icon: Icons.shield_outlined,
                      label: 'Average Trust Score',
                      value: '${asInt(metrics['averageTrustScore'])}/900',
                      tone: Tone.success,
                    ),
                    StatCard(
                      icon: Icons.verified_outlined,
                      label: 'Verified Employees',
                      value: verifiedLabel,
                      tone: Tone.warning,
                      caption: total > 0 ? '${(verified / total * 100).round()}%' : null,
                    ),
                    StatCard(
                      icon: Icons.apartment_outlined,
                      label: 'Active Departments',
                      value: '${asInt(metrics['activeDepartments'])}',
                      tone: Tone.danger,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                AppCard(
                  title: 'Workforce Growth',
                  subtitle: 'Employee count over time',
                  child: growth.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.symmetric(vertical: 28),
                          child: Center(
                            child: Text('No workforce growth data', style: TextStyle(color: AppColors.inkMuted)),
                          ),
                        )
                      : MiniBarChart(points: growth),
                ),
                const SizedBox(height: 16),
                AppCard(
                  title: 'Department Distribution',
                  subtitle: 'Headcount by department',
                  child: DepartmentSplit(data: chartMapFrom(data['departmentDistribution'])),
                ),
                const SizedBox(height: 16),
                AppCard(
                  title: 'Trust Score Distribution',
                  subtitle: 'Employee count by score range',
                  child: LabeledBarChart(data: chartMapFrom(data['trustScoreDistribution'])),
                ),
                const SizedBox(height: 16),
                AppCard(
                  title: 'Verification Analytics',
                  subtitle: 'Request outcomes across your workforce',
                  child: StatGrid(
                    children: [
                      _MiniStat(
                        label: 'Total Verification Requests',
                        value: asInt(verification['totalRequests'] ?? verification['total']),
                        color: AppColors.brand600,
                      ),
                      _MiniStat(label: 'Approved', value: asInt(verification['approved']), color: AppColors.success),
                      _MiniStat(label: 'Pending', value: asInt(verification['pending']), color: AppColors.warning),
                      _MiniStat(label: 'Rejected', value: asInt(verification['rejected']), color: AppColors.danger),
                    ],
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

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.label, required this.value, required this.color});

  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    // A non-uniform border can't have rounded corners, so the accent is a strip.
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadii.control),
        border: Border.all(color: AppColors.hairline),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 4, color: color),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('$value',
                        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.inkStrong)),
                    const SizedBox(height: 2),
                    Text(label,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.inkMuted)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
