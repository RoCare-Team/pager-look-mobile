import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/json.dart';
import '../../../core/widgets/widgets.dart';
import 'widgets_b/score_and_pagination.dart';

typedef _AuditFilters = ({String action, int page});

final _auditLogsProvider =
    FutureProvider.autoDispose.family<Map<String, dynamic>, _AuditFilters>((ref, filters) async {
  final data = await ref.watch(enterpriseApiProvider).fetchAuditLogs(
        action: filters.action,
        page: filters.page,
        limit: 20,
      );
  return asMap(data);
});

/// Port of `pages/enterprise/AuditLogs.jsx`.
class AuditLogsScreen extends ConsumerStatefulWidget {
  const AuditLogsScreen({super.key});

  @override
  ConsumerState<AuditLogsScreen> createState() => _AuditLogsScreenState();
}

class _AuditLogsScreenState extends ConsumerState<AuditLogsScreen> {
  String _action = '';
  int _page = 1;

  _AuditFilters get _filters => (action: _action, page: _page);

  Future<void> _refresh() async {
    try {
      final _ = await ref.refresh(_auditLogsProvider(_filters).future);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(_auditLogsProvider(_filters));

    return Scaffold(
      appBar: AppBar(title: const Text('Audit Logs')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: SearchField(
              hint: 'Filter by action...',
              initialValue: _action,
              onChanged: (v) => setState(() {
                _action = v;
                _page = 1;
              }),
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _refresh,
              child: AsyncValueView<Map<String, dynamic>>(
                value: async,
                loadingLabel: 'Loading audit logs...',
                onRetry: () => ref.invalidate(_auditLogsProvider(_filters)),
                data: (data) {
                  final logs = listFrom(data, const ['logs', 'items']);
                  final pagination = asMap(data['pagination']);
                  return ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(bottom: 10),
                        child: Text('Company activity history', style: TextStyle(color: AppColors.inkMuted)),
                      ),
                      if (logs.isEmpty)
                        const EmptyState(icon: Icons.receipt_long_outlined, title: 'No audit logs found')
                      else ...[
                        for (final log in logs)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: AppCard(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    str(log['action'], '—'),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.inkStrong,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    str(log['employeeId'], '—'),
                                    style: const TextStyle(
                                      fontFamily: 'monospace',
                                      fontSize: 12,
                                      color: AppColors.inkMuted,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    formatAccessDate(log['createdAt']),
                                    style: const TextStyle(fontSize: 12, color: AppColors.inkFaint),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        PaginationBar(
                          page: asInt(pagination['page'], _page),
                          totalPages: asInt(pagination['totalPages'], 1),
                          total: asInt(pagination['total']),
                          onPageChange: (p) => setState(() => _page = p),
                        ),
                      ],
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
